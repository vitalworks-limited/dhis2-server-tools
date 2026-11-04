# Runbook — migrate a boombox to the LXD architecture

Phase 4 of the boombox plan ships `dhis2-deploy migrate
boombox-to-lxd`, which automates the migration from the all-in-one
single-host layout to the LXD-containerised layout. This runbook
is what the operator reads before, during, and after the
migration.

## When to run this

You outgrew boombox:
- performance ceiling on a shared PG + Tomcat + nginx process
  space,
- need multi-tenant isolation across DHIS2 instances,
- upgrade path to HA (HA Phase 1 and later require the LXD or
  distributed architecture).

## Downtime expectation

**10–30 minutes typical.** The destructive window starts at
stage 5 (PostgreSQL stop) and ends at stage 11 (maintenance mode
off). DHIS2 is unreachable to users during that window.

## Before you start

- A fresh, verified pre-migration backup lives in
  `/var/backups/dhis2`. The command creates one in stage 2 but a
  defence-in-depth second copy is cheap:

  ```bash
  dhis2-backup create <instance> --format custom --verify
  cp /var/backups/dhis2/<instance>-*.dump /some/off-host/path/
  ```

- Disk headroom: at least 2× the current `/var/lib/postgresql`
  footprint on `/`. The command's preflight checks this and
  refuses otherwise.

- A maintenance window agreed with your users. Communicate the
  outage.

- You know how to restore from the backup. The migration can fail
  past the destructive point and hand off to you.

## Four modes

```bash
# 1. preflight only (default). Prints the plan + 'OK' + exits 0.
dhis2-deploy migrate boombox-to-lxd

# 2. detect-drift. Scans the live host for Tomcat major, PostgreSQL
#    major, DHIS2 version, and compares /opt/dhis2/dhis.conf against
#    the inventory. Prints a drift report. Exits 0 even on drift so
#    you can see every finding before deciding how to proceed.
dhis2-deploy migrate boombox-to-lxd --detect-drift

# 3. dry-run. Prints every command that would run. Exits 0.
dhis2-deploy migrate boombox-to-lxd --dry-run

# 4. actually execute. Requires --yes and typed instance name(s).
#    Multi-instance boomboxes: repeat --instance per instance.
#    Optionally rotate the DB password transactionally during the
#    restore window.
dhis2-deploy migrate boombox-to-lxd --execute --yes \
    --instance hmis [--instance training] \
    [--rotate-db-password]
```

Always run modes 1, 2, and 3 before 4.

## Drift detection

Operators run boomboxes in the field for months. The host state drifts:
Tomcat gets upgraded (9→10→11), PostgreSQL might get a minor bump, and
somebody might have hand-edited `/opt/dhis2/dhis.conf` to point at a
renamed database. The migration must cope with this or it fails
destructively.

`--detect-drift` reports four axes:

1. **Tomcat major** detected from the running systemd unit (falls back
   to webapps presence on disk). The LXD inventory emits
   `tomcat_version=<detected>` so the new containers install the same
   major.
2. **PostgreSQL major** detected from `/etc/postgresql/<N>/main`. The
   LXD inventory emits `postgresql_version=<detected>` so no silent
   major upgrade happens through a restore.
3. **DHIS2 version** parsed from the deployed WAR MANIFEST.MF under
   `/var/lib/tomcat*/webapps/<instance>/META-INF/MANIFEST.MF`.
4. **dhis.conf vs. inventory** parsed via regex over
   `connection.url = jdbc:postgresql://HOST[:PORT]/DBNAME` and
   `connection.username`. If `HOST` is not `localhost`/`127.0.0.1`
   the preflight **refuses** the migration — a boombox by definition
   runs PG locally; a non-local JDBC URL means the operator already
   split the DB off to another host and this command is the wrong
   tool.

If `DBNAME` in `dhis.conf` differs from the instance name (a common
rename), **the migration honours the real name** and prints:

```
Instance 'hmis' -> database 'hmis_prod' (from dhis.conf)
```

The same resolution is used by `dhis2-backup create` and
`dhis2-restore database`, so the rename-aware behaviour is consistent
across the backup/restore primitives this command composes.

## The 13 stages

### Pre-destructive (automatic rollback on failure)

| # | Stage | What happens | On failure |
|---|-------|--------------|------------|
| 1 | **State snapshot** | Copy inventory, `dhis.conf`, nginx config, `postgresql.conf` to `/var/lib/dhis2-server-tools/snapshots/migrate-<instance>-<ts>/`. | Automatic rollback: no services were touched. |
| 2 | **Verified backup** | `dhis2-backup create --format custom --verify`. Hard fail if the verify step does not pass. | Automatic rollback: no services were touched. |
| 3 | **Maintenance mode on** | Nginx returns 503 for `/<instance>`. Users see a maintenance page. | Automatic rollback: disable maintenance mode, exit. |
| 4 | **Stop user-facing services** | `systemctl stop tomcat9 nginx`. | Automatic rollback: start tomcat9 + nginx + disable maintenance. |
| 5 | **Stop PostgreSQL** | `CHECKPOINT; systemctl stop postgresql`. **Destructive from this point.** | Automatic rollback: start postgresql + nginx + tomcat9 + disable maintenance. |

### Post-destructive (operator-driven on failure)

| # | Stage | What happens | On failure |
|---|-------|--------------|------------|
| 6 | **Install LXD** | `apt install -y lxd lxd-client; lxd init --preseed`. | **Operator handoff.** Backup is at `/var/backups/dhis2/<instance>-pre-migrate-<ts>.dump`. See "Rollback after step 6". |
| 7 | **Rewrite inventory** | New `hosts` with `dhis2_architecture=lxd`, `ansible_connection=lxd`, container IPs. Previous `hosts` is in the snapshot directory. | Operator handoff. |
| 8 | **Deploy LXD stack** | `dhis2-deploy apply` creates proxy / postgres / instance / monitor containers and installs the normal LXD topology. | Operator handoff. |
| 9 | **Restore DB** | `dhis2-restore database --drop-existing --create-db --reassign-owner --verify` into the new postgres container. | Operator handoff. |
| 10 | **File store** | `lxc file push -r /opt/dhis2/files <instance>:/opt/dhis2/` (if present). | Non-fatal: logged as a warning; operator can rsync manually. |
| 11 | **Maintenance mode off** | Nginx resumes routing. | Logged; disable manually if the automatic step did not. |
| 12 | **Health** | `dhis2-instance health --retry 30 --interval 10` hits `/api/system/info`. | Operator handoff. Backup is retained. |
| 13 | **Operational snapshot** | `dhis2-doctor snapshot` captures the post-migration state. | Non-fatal. |

Every stage boundary writes to
`/var/log/dhis2-server-tools/audit.ndjson`:

```json
{"ts":"...","action":"migrate-boombox-to-lxd","instance":"hmis","stage":"destructive-point","backup":"/var/backups/dhis2/hmis-pre-migrate-20261103-....dump"}
```

## Rollback after step 6

Automatic rollback is **not safe** past the destructive point
(step 5). The command instead hands off to the operator with:

```
Operator-driven recovery:
  1. Decide: fix forward (continue to LXD) OR fresh host (restore boombox).
  2. Backup is at:  /var/backups/dhis2/hmis-pre-migrate-<ts>.dump
  3. See docs/Boombox-to-LXD-Migration.md section 'Rollback after step 6'.
```

Two realistic recovery paths:

### Path A: fix the failing step and continue to LXD

Example: step 8 (`dhis2-deploy apply`) failed because an LXD
container could not reach the apt mirror. Fix the network, then:

```bash
# Delete the half-created LXD containers
sudo lxc delete --force proxy postgres <instance> monitor 2>/dev/null
# Re-run the LXD portion only
sudo dhis2-deploy apply --yes
sudo dhis2-restore database --backup <backup> --instance <instance> \
    --drop-existing --create-db --reassign-owner --verify --yes
sudo dhis2-instance maintenance <instance> disable --yes
sudo dhis2-instance health <instance> --retry 30 --interval 10
```

### Path B: provision a fresh host and restore boombox

The migration mutated this host (LXD installed, PG stopped and
masked). Simpler to abandon it:

```bash
# On a new Ubuntu 22.04 or 24.04 host:
git clone https://github.com/vitalworks-limited/dhis2-server-tools.git
cd dhis2-server-tools
sudo ./install.sh
sudo dhis2-deploy init --architecture boombox --mode production \
    --fqdn <same-fqdn> --email <same-email>
sudo dhis2-deploy apply
# Copy the pre-migration backup to the new host, then:
sudo dhis2-restore database --backup /path/to/<instance>-pre-migrate-<ts>.dump \
    --instance <instance> --drop-existing --create-db --reassign-owner --verify --yes
# Point DNS at the new host and verify
dhis2-instance health <instance> --retry 30 --interval 10
```

The failed host can be reclaimed afterward (`apt purge lxd`, `rm
-rf /var/lib/lxd`).

## Verifying success

```bash
dhis2-status
dhis2-cluster topology 2>/dev/null       # harmless on non-HA
dhis2-doctor                             # cross-stack
dhis2-doctor boombox 2>/dev/null         # should now say architecture != boombox
dhis2-instance health <instance> --retry 10 --expect-version <configured>
dhis2-logs <instance> --since '15 minutes ago' --grep ERROR
```

Expected post-migration state:
- `dhis2-status` lists the proxy / postgres / instance / monitor containers under LXD.
- `/opt/dhis2/dhis.conf` on the LXD instance container points at
  the LXD postgres container (`connection.url = jdbc:postgresql://postgres/...`).
- Nginx on the LXD proxy container terminates TLS and proxies to
  the LXD instance container.
- The host's `/var/lib/postgresql/` is now stale and can be
  archived or deleted after a comfortable retention window (one
  week typical). The command does NOT delete the old data.

## Keeping the pre-migration backup

The pre-migration backup is retained at the path printed in the
migration summary. **Do not delete it until**:
- `dhis2-doctor` is green for at least 48 hours after migration,
- a fresh backup from the LXD topology has been created and
  verified,
- you have confirmed the application behaves correctly end-to-
  end against the new topology.

## Multi-instance boomboxes

A single boombox host can carry more than one DHIS2 instance (they
share one PG cluster, one Tomcat, one nginx). Pass `--instance` once
per instance. The command will:

1. Take one combined state snapshot + verified per-instance backup
   for each instance (stage 1–2 iterated).
2. Stop user-facing services once (stage 3–5).
3. Install LXD and render a multi-instance LXD inventory (one
   `[instances]` row per migrated name).
4. Deploy the LXD stack once (stage 6–8).
5. Restore each instance's database into the new postgres container
   in turn (stage 9 iterated).
6. Push file stores for each instance (stage 10 iterated).
7. Exit maintenance and verify each instance's health (stage 11–13).

The audit records emit one `destructive-point` entry per instance so
operators can locate which instance's data the backup belongs to.

## Rotating the database password during migration

`--rotate-db-password` adds a transactional password rotation during
stage 9 of each instance:

1. After the database is restored into the new postgres container,
   `dhis2-vault rotate-db-password` generates a fresh secret.
2. The new secret is written to the postgres container (via
   `ALTER USER ... PASSWORD`) **and** to the new instance
   container's `/opt/dhis2/dhis.conf` atomically.
3. If either side fails, the transaction aborts and the old password
   is restored, leaving the system in a consistent state.

Use this flag when the boombox was exposed (shared workshop network,
former lead left the team, suspected compromise) — rotating here
avoids a second restart window right after migration.

## Preserving custom nginx + PostgreSQL files

The migration snapshots and re-pushes operator customisations that
live outside `sites-enabled/` and `postgresql.conf`:

| Source on boombox | Destination in LXD |
|---|---|
| `/etc/nginx/conf.d/*` | `proxy` container `/etc/nginx/conf.d/` |
| `/etc/nginx/snippets/*` | `proxy` container `/etc/nginx/snippets/` |
| `/etc/systemd/system/postgresql.service.d/*.conf` | `postgres` container, same path |
| `/etc/systemd/system/postgresql@.service.d/*.conf` | `postgres` container, same path |

Everything is snapshotted to
`/var/lib/dhis2-server-tools/snapshots/migrate-<instance>-<ts>/preserve/`
before being pushed, so if the push fails you can `lxc file push`
manually from the snapshot. The command does **not** push
`/etc/nginx/sites-enabled/` — those are regenerated by the `proxy`
role from inventory to prevent drift.

## Known limitations

- **No tested round-trip in CI (free tier).** LXD + Patroni + etcd
  does not run reliably on nested virtualisation in GitHub Actions.
  The command's behaviour is exercised two ways:
  1. Mock-mode regression (scenarios CA–CJ) covers every code path.
  2. An opt-in live-matrix workflow runs the round-trip on a
     self-hosted runner you provide. See
     [tests/live/README.md](../tests/live/README.md) for the harness
     (Vagrant-based, Ubuntu 22.04 and 24.04).

For the second iteration of this command (planned):
- Live-rollback for a subset of post-destructive failures.
- Analytics-schema parity report after the restore.

## Related

- [docs/Boombox.md](./Boombox.md) — Boombox operator guide
- [docs/vital-enhancements/boombox-plan.md](./vital-enhancements/boombox-plan.md) — Boombox design + locked decisions
- [docs/CLI-Backup-Restore.md](./CLI-Backup-Restore.md) — backup / restore primitives this command composes
