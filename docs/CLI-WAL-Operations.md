# PostgreSQL WAL disk safety

PostgreSQL's write-ahead log (`pg_wal/`) can grow faster than the
operator realises and fill the data filesystem. When that happens
PostgreSQL refuses writes — the application sees connection errors
and the operator sees a hard outage. This page is the operator
runbook for preventing, monitoring, and recovering from WAL
disk-pressure events.

The full design discussion is in
[docs/vital-enhancements/wal-disk-safety-plan.md](./vital-enhancements/wal-disk-safety-plan.md).

## Why WAL fills up

Eight root causes, roughly in order of frequency:

1. **`archive_command` fails silently.** With `archive_mode=on` PG
   keeps every WAL segment until the archive command returns 0. An
   unreachable S3 endpoint accumulates WAL forever.
2. **Orphaned replication slot.** A physical slot pins WAL on the
   primary until the replica acknowledges it. A permanently-gone
   replica whose slot was never dropped is the #1 killer under HA.
3. **`wal_keep_size` set too high.**
4. **Very long transaction.** PG retains all WAL between a
   transaction's start and the current LSN.
5. **Infrequent checkpoints.**
6. **Logical replication subscription paused.**
7. **Analytics table rebuild** generating planned write bursts.
8. **Timeline divergence after HA failover.**

## Prevention

The `postgres` role now sets safe defaults for WAL retention:

```yaml
# deploy/roles/postgres/defaults/main.yml
pg_max_wal_size: 4GB      # soft target before aggressive checkpoint
pg_min_wal_size: 80MB     # recycle floor
# pg_checkpoint_timeout: 5min
# pg_wal_keep_size: 1GB   # usually leave unset
pg_archive_mode: off      # explicit opt-in for continuous archiving
# pg_archive_command: 'wal-g wal-push %p'
# pg_wal_level: replica
```

When the operator sets `pg_archive_mode=on`, the role runs
`wal-archive-preflight.yml` which **actually executes the configured
`pg_archive_command` against a test file** before enabling archiving.
A broken archive command fails the deployment at that step, so a
stuck archive cannot fill `pg_wal` on a production host that was
previously healthy.

## Inspection

Read-only commands that are safe to run under pressure:

```bash
dhis2-db wal status                     # size, segment count, filesystem %, archive lag, oldest segment
dhis2-db wal status --json              # machine-readable
dhis2-db wal archive-status             # pg_stat_archiver output + last failures
dhis2-db wal retention                  # WAL retention reasons: slots, keep_size, long transactions
dhis2-db replication-slot list          # per-slot retained_wal bytes
dhis2-db long-running                   # long transactions (pre-existing)
```

The cross-cutting health check:

```bash
dhis2-doctor wal
```

returns exit code `6` (health) when any of these thresholds is
breached:

| Signal | Warn | Fail |
|--------|------|------|
| `pg_wal` filesystem used | 75% | 90% |
| Archive lag seconds | 300 | 900 |
| `pg_stat_archiver.failed_count` | > 0 | — |
| Per-slot retained WAL | 1 GiB | 10 GiB |
| Idle-in-transaction age | 1 hour | — |

## Response

### Scenario 1 — Orphaned replication slot

Symptom: a slot holds many GiB of WAL and its `active` column is
`f` (false).

```bash
dhis2-db replication-slot list
# find a slot where active=f and retained_wal is large

dhis2-db replication-slot drop <slot_name>    # confirmation required

dhis2-db wal flush                            # CHECKPOINT + pg_switch_wal
```

If the slot shows `active=t` but the replica is actually gone:

```bash
dhis2-db replication-slot drop <slot_name> --force
```

`--force` additionally requires `--yes`.

### Scenario 2 — Archive command failing

Symptom: `dhis2-db wal archive-status` shows `failed_count > 0` or
`last_archived_time` far in the past.

```bash
dhis2-db wal archive-status
dhis2-logs postgres --grep archive_command --lines 200
# fix the destination (S3 creds, network, endpoint)

dhis2-db wal flush                            # retries archiving
dhis2-doctor wal                              # confirm healthy
```

### Scenario 3 — Long transaction

Symptom: `dhis2-db wal retention` lists a transaction older than 15
minutes.

```bash
dhis2-db long-running
dhis2-db kill-grace <pid> --grace-seconds 30 --yes
```

### Scenario 4 — Disk almost full and none of the above works

This is the break-glass path. `emergency-drain` temporarily sets
`archive_command=/bin/true` for 30 seconds so PG can reclaim WAL,
then restores the original command. **WAL generated during the drain
window is NOT archived — PITR history regresses from that point until
you take a fresh base backup.**

```bash
dhis2-db wal emergency-drain --yes

# After the storm:
dhis2-db config apply --merge                 # restores archive_command
dhis2-backup create <instance> --format custom --encrypt gpg --recipient ops@example.org
dhis2-doctor wal
```

The emergency drain writes an audit record to
`/var/log/dhis2-server-tools/audit.ndjson` with the command, user,
and timestamp.

## Exit codes

All the WAL commands follow the project-wide exit-code convention:

| Code | Meaning |
|------|---------|
| 0 | success |
| 2 | invalid arguments |
| 3 | preflight failed (e.g. no `[databases]` host) |
| 6 | health check failed (filesystem or archive thresholds breached) |
| 8 | safety check prevented destructive action (active slot without `--force`) |

## One-page runbook

Pin this somewhere operators can read it in an outage:

```
# WAL IS FILLING THE DATA DISK — RUNBOOK

# 1. Confirm the problem is WAL (not table data, not WAL on its own volume)
dhis2-db wal status

# 2. Identify the cause
dhis2-db wal retention
dhis2-db replication-slot list
dhis2-db long-running --host <db-host>

# 3. Fix (one of):
dhis2-db replication-slot drop <slot_name> --yes          # orphaned slot
dhis2-db wal archive-status; fix S3; dhis2-db wal flush   # archive broken
dhis2-db kill-grace <pid> --grace-seconds 30 --yes        # idle-in-transaction

# 4. BREAK GLASS only if steps 1-3 do not free space
#    AND the disk is >95% full AND you accept the loss of recent archive history
dhis2-db wal emergency-drain --yes

# 5. After the storm
dhis2-db config apply --merge
dhis2-backup create <instance> --format custom --encrypt gpg --recipient <key>
dhis2-doctor wal

# NEVER:
#   rm /var/lib/postgresql/*/main/pg_wal/*
#   mv pg_wal to another filesystem while PG is running
#   drop an ACTIVE replication slot (unless --force and you are certain)
```

## Related

- [docs/CLI-Flyway-Operations.md](./CLI-Flyway-Operations.md) — Flyway
  failure recovery (related: a stuck Flyway migration can hold a
  transaction open and pin WAL).
- [docs/CLI-Backup-Restore.md](./CLI-Backup-Restore.md) — base backup
  that re-seeds PITR after an emergency drain.
- [docs/vital-enhancements/wal-disk-safety-plan.md](./vital-enhancements/wal-disk-safety-plan.md)
  — full design + phase 2 roadmap (dedicated `pg_wal` volume, systemd
  watchdog).
- [docs/vital-enhancements/ha-implementation-plan.md](./vital-enhancements/ha-implementation-plan.md)
  — WAL semantics under HA (replication slots, WAL-G, timeline
  divergence).
