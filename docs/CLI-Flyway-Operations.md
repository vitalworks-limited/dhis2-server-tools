# Flyway operations

DHIS2 uses [Flyway](https://flywaydb.org/) for schema migrations.
Upgrades fail more often because of Flyway state than because of
anything else, and the failure modes are mostly recoverable **if you
know what state the schema is in**. This page is the operator runbook
for the `dhis2-db flyway` and `dhis2-upgrade preflight` tooling.

See
[docs/vital-enhancements/gap-analysis-flyway-and-beyond.md](./vital-enhancements/gap-analysis-flyway-and-beyond.md)
for the failure-mode taxonomy that this tooling implements.

## Read-only inspection

```bash
dhis2-db flyway info     hmis            # latest version, failed count, lock count, recent 20 migrations
dhis2-db flyway history  hmis            # full history table (default limit 100)
dhis2-db flyway failed   hmis            # list only failed rows; exit 6 if any present
dhis2-db flyway locks    hmis            # active row/advisory locks with age
dhis2-db flyway pending  hmis --to 2.43.2
dhis2-db flyway validate hmis            # gaps, duplicates, null checksums
dhis2-db flyway source-version hmis      # best-effort source DHIS2 version
```

Every read-only command returns exit `0` on success, `6` when the DB
is in a known-bad state, and `3` on inventory/preflight problems.
Secret-looking values (`installed_by` et al) are redacted from `failed`
output.

## Pre-upgrade gate

`dhis2-upgrade preflight INSTANCE --to VERSION` is a **hard gate** that
blocks `dhis2-upgrade run` when the DB is in a state that would make
an upgrade dangerous. It runs:

- Flyway failed-rows check (**F1** of the gap analysis)
- Flyway lock-age check (**F2**, threshold `DHIS2_FLYWAY_STALE_LOCK_SEC`,
  default 1800s)
- PostgreSQL major-version compatibility against the version matrix
  (**F8**)
- Source-lineage probe — blocks `auto` mode when the lineage is
  `UNKNOWN` unless `--allow-unknown-source` or
  `--source-dhis2-version X.Y.Z` is supplied (**section 73.2**)
- Connection-pool pressure (warn only)

```bash
dhis2-upgrade preflight hmis --to 2.43.2
dhis2-upgrade preflight hmis --to 2.43.2 --json | jq .
```

`dhis2-upgrade run` always calls `preflight` first; you cannot
accidentally proceed through a known-bad state.

## Live upgrade monitoring

During `dhis2-upgrade run`, the `create-instance` role's
`monitor-migrations.yml` task:

- Polls `flyway_schema_history` every `dhis2_migration_poll_seconds`
  (default 5s) and records the currently-running migration as
  `progress: installed_rank=X version=Y script="..."` lines in
  `/var/lib/dhis2-server-tools/state/upgrade.<instance>.state` (**F10**).
- Watches `pg_stat_activity` for pool pressure and records a warning
  line when active connections reach 80% of `max_connections` (**F9**).
- Fails fast on any `FlywayException` / `Migration ... failed` /
  `ERROR .*Flyway` line in `catalina.out` (**F6**).
- On failure, dumps the failing migration SQL from
  `flyway_schema_history.script` to a focused tarball under
  `/var/log/dhis2-server-tools/bundles/upgrade-<instance>-<ts>.tgz`
  with redaction.

```bash
# Watch progress live during an upgrade
watch -n 5 'ssh app01 "cat /var/lib/dhis2-server-tools/state/upgrade.hmis.state"'
```

## Recovery runbook

### Failed migration (success=false row in history)

```bash
# 1. Confirm the failure
dhis2-db flyway failed hmis

# 2. Collect a diagnostic bundle (if role did not auto-capture one)
dhis2-upgrade failure-bundle hmis

# 3. Review the dumped SQL inside the bundle
tar tzf /var/log/dhis2-server-tools/bundles/upgrade-hmis-*.tgz

# 4. Fix the root cause (DB config, extensions, custom SQL, etc.)
#    This step is manual - the CLI will NEVER apply arbitrary SQL repairs.

# 5. Clear the failed rows ONLY after root cause is understood
dhis2-db flyway repair hmis    # requires explicit confirmation

# 6. Rerun the upgrade with monitoring
dhis2-upgrade run hmis --to 2.43.2 \
    --backup-before-migration --verify-backup --monitor-migrations
```

### Stuck Flyway lock

```bash
# 1. Confirm no live DHIS2 process is migrating
dhis2-instance status hmis

# 2. Inspect the lock
dhis2-db flyway locks hmis

# 3. Clear it
dhis2-db flyway unlock hmis    # terminates any backend holding the lock
```

### Attaching an older database

When an older DHIS2 database is attached to a new instance (for
cloning, DR, or migration), the schema may lack a Flyway history
table. Flyway refuses to migrate a non-empty schema without one.

```bash
# 1. Attach the DB (writes database_host, source version, upgrade mode)
dhis2-instance database attach training \
    --database production_old --host postgres \
    --source-dhis2-version 2.40 \
    --upgrade-mode detect

# 2. Baseline Flyway history
dhis2-db flyway baseline training --version 2.40 --description "baseline attach from production"

# 3. Run the controlled upgrade
dhis2-upgrade run training --to 2.43.2 \
    --source-dhis2-version 2.40 \
    --backup-before-migration --verify-backup --monitor-migrations
```

### Unknown source lineage

`dhis2-db flyway source-version` returns `UNKNOWN` when the Flyway
table is missing or empty. In that state `dhis2-upgrade run` **blocks**
unless the operator explicitly accepts the risk:

```bash
dhis2-upgrade run hmis --to 2.43.2 --source-dhis2-version 2.40
# or (break-glass):
dhis2-upgrade run hmis --to 2.43.2 --allow-unknown-source
```

## Automatic restore on failure

```bash
dhis2-upgrade run hmis --to 2.43.2 \
    --backup-before-migration --verify-backup --monitor-migrations \
    --restore-on-failure
```

Only enables when the pre-upgrade backup was created and verified in
the same `run`. On Flyway failure the CLI performs a
`dhis2-restore database --drop-existing --create-db --reassign-owner`
against the pre-upgrade dump. If the restore itself fails the CLI
surfaces that too — it will never claim success in the face of a
double failure.

## Variables

Set in inventory (`[all:vars]` or per-host) or as `-e` extra-vars:

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `dhis2_database_upgrade_mode` | `detect` | `refuse` / `detect` / `prompt` / `auto` / `force` |
| `dhis2_allow_db_migrations` | `false` | Explicit permission for migrations during startup |
| `dhis2_monitor_migrations` | `false` | Enable live Flyway monitoring |
| `dhis2_migration_timeout` | `1800` | Seconds before failing the migration-monitor task |
| `dhis2_migration_poll_seconds` | `5` | Flyway history poll interval |
| `dhis2_flyway_stale_lock_sec` | `1800` | Lock age that triggers preflight failure |
| `dhis2_pre_upgrade_backup` | — | Path recorded in state file; `dhis2-upgrade run` sets it automatically |
| `dhis2_restore_on_failure` | `false` | Auto-restore pre-upgrade backup on Flyway failure |
| `dhis2_preserve_database_credentials` | `true` | Never regenerate `connection.password` during an upgrade |

Environment overrides (for the CLI):

| Variable | Default | Effect |
| -------- | ------- | ------ |
| `DHIS2_FLYWAY_STALE_LOCK_SEC` | `1800` | Lock age threshold used by `dhis2-upgrade preflight` and `dhis2-db flyway locks` |

## Hard limits

The CLI **does not** attempt arbitrary SQL repairs (section 79 of the
implementation requirements doc). `dhis2-db flyway repair` only deletes
the `success=false` rows in the history table — enough to let a
retried start-up proceed, but **not** enough to fix the underlying
schema damage. That part is the operator's responsibility and
typically means a restore from the pre-upgrade backup.
