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

## Compliance

The role **mathematically guarantees** that WAL cannot grow past the
`pg_wal` filesystem under normal operation. Every HA deploy and
every single-node deploy that enables archive mode runs
`roles/postgres/tasks/wal-compliance-preflight.yml`, which validates
the following inequality:

```
max_wal_size
+ max_slot_wal_keep_size
+ wal_keep_size
+ max_wal_size            # 1x archive-lag headroom
+ 2 * wal_segment_size    # current + next-segment overhead
<=  pg_wal_fs_safe_pct% of the pg_wal filesystem size
```

If the inequality fails the role **refuses to deploy** unless
`pg_wal_compliance_override=true` is set (which writes an audit
record and prints a HIGH-SEVERITY warning).

### Required knobs (official PostgreSQL 16 docs)

Every knob below is set to a safe default in
`roles/postgres/defaults/main.yml` and overridable in inventory.

| Knob | Role default | PG official doc |
|------|--------------|-----------------|
| `max_wal_size` | 4GB | [runtime-config-wal § MAX_WAL_SIZE](https://www.postgresql.org/docs/16/runtime-config-wal.html#GUC-MAX-WAL-SIZE) |
| `min_wal_size` | 80MB | [runtime-config-wal § MIN_WAL_SIZE](https://www.postgresql.org/docs/16/runtime-config-wal.html#GUC-MIN-WAL-SIZE) |
| `max_slot_wal_keep_size` | **10GB** (role refuses -1) | [runtime-config-replication § MAX_SLOT_WAL_KEEP_SIZE](https://www.postgresql.org/docs/16/runtime-config-replication.html#GUC-MAX-SLOT-WAL-KEEP-SIZE) |
| `wal_keep_size` | **0** (keep at 0 with slots) | [runtime-config-replication § WAL_KEEP_SIZE](https://www.postgresql.org/docs/16/runtime-config-replication.html#GUC-WAL-KEEP-SIZE) |
| `archive_timeout` | 60s (when `archive_mode=on`) | [runtime-config-wal § ARCHIVE_TIMEOUT](https://www.postgresql.org/docs/16/runtime-config-wal.html#GUC-ARCHIVE-TIMEOUT) |
| `log_checkpoints` | on | [runtime-config-logging § LOG_CHECKPOINTS](https://www.postgresql.org/docs/16/runtime-config-logging.html#GUC-LOG-CHECKPOINTS) |
| `checkpoint_timeout` | PG default (5min) | [runtime-config-wal § CHECKPOINT_TIMEOUT](https://www.postgresql.org/docs/16/runtime-config-wal.html#GUC-CHECKPOINT-TIMEOUT) |

### Policy enforcements

The role refuses to proceed when:

1. `max_slot_wal_keep_size` is `-1` (unlimited).
   Rationale: an orphaned replication slot can then retain WAL
   without bound, which is the single most common way to fill
   `pg_wal` in HA deployments.

2. The configured retention sum exceeds `pg_wal_fs_safe_pct` of
   the `pg_wal` filesystem. Default `pg_wal_fs_safe_pct=70` leaves
   30% of the filesystem for unarchived WAL spikes and segment
   overhead.

The role warns (does not refuse) when:

3. `wal_keep_size != 0` while replication slots are in use.
   Rationale: the slot already retains WAL for the standby;
   `wal_keep_size` just adds disk pressure. The PG docs recommend
   `wal_keep_size=0` with slots.

### Live validation

Operators can verify a running cluster at any time:

```bash
dhis2-db wal compliance
dhis2-db wal compliance --json | jq .

dhis2-doctor wal                      # includes a compliance line
```

Exit codes:
- `0` compliant
- `6` (health) retention sum > budget
- `8` (safety) `max_slot_wal_keep_size=-1` (unlimited)

### Example output

```
WAL compliance on postgres
  pg_wal filesystem:            51200 MiB
  pg_wal_fs_safe_pct:           70%
  budget:                       35840 MiB
  required:                     18464 MiB
  headroom:                     17376 MiB (compliant)

  max_wal_size:                 4096 MiB
  max_slot_wal_keep_size:       10240 MiB
  wal_keep_size:                0 MiB
  wal_segment_size:             16 MiB

OK - WAL configuration is compliant
```

### Overriding compliance (break glass)

Only when the operator explicitly accepts the risk:

```yaml
# inventory
pg_wal_compliance_override: true
```

The role proceeds, writes an audit entry to
`/var/log/dhis2-server-tools/audit.ndjson`, and prints the exact
overage in MiB so the operator can act on the risk.

## Phase 2 — dedicated pg_wal volume

Compliance (above) keeps WAL within budget mathematically. A
**dedicated `pg_wal` filesystem** is the hardware-level
belt-and-braces: even if a bug or an operator mistake exceeds the
configured ceiling, a WAL ENOSPC event only kills the WAL volume,
never the data volume.

Opt in with an inventory host var:

```ini
[databases]
pg01 ansible_host=10.0.1.21 pg_wal_volume=/dev/sdb
```

Fresh clusters: the role formats and mounts `/dev/sdb` at
`pg_wal/` *before* `initdb` runs. WAL is on the dedicated volume
from day one.

Existing clusters: migration is a documented runbook that requires
PG stopped first and `pg_wal_volume_migrate=true`. See
[docs/HA-Runbook-WAL-Volume-Migration.md](./HA-Runbook-WAL-Volume-Migration.md).

Inspection:

```bash
dhis2-db wal volume status           # DEDICATED | SHARED, size, used %
dhis2-db wal volume status --json
```

## Phase 2 watchdog

A systemd timer runs every 5 minutes and surfaces WAL issues even
on deployments without Prometheus or Munin alerting.

- Unit:   `/etc/systemd/system/dhis2-wal-watchdog.service`
- Timer:  `/etc/systemd/system/dhis2-wal-watchdog.timer`
- Log:    `/var/log/dhis2-server-tools/wal-watchdog.log`

The service calls `dhis2-db wal status --json` and
`dhis2-db wal compliance --json`; non-zero exit (6 or 8) is
surfaced as a FAILED unit in `systemctl` and journald. Operators
scraping `systemctl status --failed` or wiring journald to their
alerting stack catch WAL incidents without any Prometheus setup.

```bash
dhis2-db wal watchdog status
journalctl -u dhis2-wal-watchdog.service -n 40
```

The watchdog is installed and enabled automatically by
`install.sh` when a `[databases]` host is reachable. Operators who
want to disable it:

```bash
sudo systemctl disable --now dhis2-wal-watchdog.timer
```

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
