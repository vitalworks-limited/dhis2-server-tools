# PostgreSQL WAL disk-safety plan

**Problem:** `pg_wal/` can grow faster than the operator realises and
fill the data filesystem. PostgreSQL responds by refusing writes (and,
in some edge cases, refusing to start). For DHIS2 this means an
outage, a corrupted-looking state to end users, and recovery that
usually requires a dangerous `rm` on files that look like they belong
to the database.

This plan is **not HA-specific** — it applies to the current
single-node deployment as much as to the HA roadmap — but under HA
the risk is strictly worse because physical replication slots can pin
WAL indefinitely.

---

## 1. Root causes we have to prevent, monitor, and recover from

| # | Cause | Why it fills the disk |
|---|-------|------------------------|
| 1 | **`archive_command` failing silently** | With `archive_mode=on`, PG keeps every WAL segment on disk until the archive command returns 0. S3 outage → unbounded accumulation. |
| 2 | **Orphaned replication slot** | A physical slot keeps WAL on the primary until the replica acknowledges consumption. If a replica dies and the slot is not dropped, WAL accumulates forever. **The #1 WAL-disk killer in HA.** |
| 3 | **`wal_keep_size` set too high** | Operators sometimes bump this for safety and forget. 100 GB of "safety margin" at 10 MB/s means 1000 segments on disk. |
| 4 | **Very long transaction** | PG retains all WAL between the transaction start and the current LSN so it can be rolled back. An `IDLE in transaction` session held for hours by a buggy client fills WAL. |
| 5 | **Checkpoint timing** | Rare checkpoints keep more WAL around than necessary. Default `checkpoint_timeout=5min` is usually fine; operators sometimes raise it to reduce I/O and forget. |
| 6 | **Logical replication subscription paused** | Same WAL-pinning problem as physical slots. DHIS2 doesn't ship with logical replication by default, but third-party extensions and ETL pipelines use it. |
| 7 | **Analytics table rebuilds** | DHIS2 generates significant WAL during analytics runs. Not a leak; a planned spike. Operators mistake it for a leak and panic. |
| 8 | **Timeline divergence after failover** | pg_rewind leaves stale WAL on the demoted node until cleanup. HA-only. |

---

## 2. Defence in depth

Three layers. Each has to be in place to be robust.

### 2.1 Prevention (make the system refuse to lose data this way)

| Measure | Current state | Target |
|---------|--------------|--------|
| **Dedicated `pg_wal` filesystem**, so WAL filling cannot kill the data volume | Not implemented | `postgres` role gains `pg_wal_volume` host var; when set, mounts a separate volume at `/var/lib/postgresql/<ver>/main/pg_wal` and bind-mounts PG's `pg_wal` to it. If WAL fills ITS own volume, PG stops writes with ENOSPC on commit; data volume is untouched; recovery is simple |
| **`max_wal_size` / `min_wal_size`** safe defaults sized by expected database | Not set; PG defaults (1 GB max) apply | Role defaults: `max_wal_size=4GB`, `min_wal_size=80MB`. Overridable via `pg_max_wal_size` / `pg_min_wal_size` inventory vars. |
| **`checkpoint_timeout`** | Default 5 min | Keep; expose as `pg_checkpoint_timeout` |
| **Validate `archive_command` BEFORE enabling `archive_mode`** | `archive_mode=off` by default | New role task: run the configured archive command against a test file. Fail the deploy if it doesn't return 0. Only then set `archive_mode=on`. |
| **Refuse unbounded `wal_keep_size`** | No guard | Role refuses `wal_keep_size > pg_wal_disk_size * 0.5` with a clear error. |
| **Document safe values for `track_commit_timestamp`, `max_wal_senders`, `max_replication_slots`** | Defaults | Documented in `docs/CLI-WAL-Operations.md`. |

### 2.2 Monitoring (catch it before the disk fills)

| Signal | Current state | Target |
|--------|---------------|--------|
| **`pg_wal/` byte size** | Not monitored | Prometheus exporter `pg_wal_bytes` with alerts at 50%, 75%, 90% of the `pg_wal` filesystem. |
| **`pg_stat_archiver` failure count** | Not monitored | Prometheus `pg_archive_failed_count` with alert on any increase, regardless of absolute size. |
| **Oldest unarchived WAL segment age** | Not monitored | Alert when > 15 min. |
| **Replication slot `retained_wal_bytes` per slot** | Not monitored | Alert at 1 GB per slot (configurable). |
| **Idle-in-transaction sessions pinning WAL** | Already in `dhis2-db long-running` | `dhis2-doctor wal` surfaces specifically those pinning WAL. |
| **Checkpoint lag** | Not monitored | Alert when `pg_stat_bgwriter.checkpoints_timed` < `checkpoints_req` for a sustained window (indicates WAL-pressure checkpoints). |
| **Systemd watchdog timer `dhis2-wal-watchdog.service`** | Does not exist | Runs every 5 min; `du -sB1 /var/lib/postgresql/.../pg_wal` ; writes to `/var/log/dhis2-server-tools/wal-watchdog.log`; sends a wall-of-text alert via `dhis2-monitor test-alert` or exits 0 silently. Independent of Prometheus so it works on single-node Munin deployments too. |

### 2.3 Response and recovery (safe operator actions)

Operators need commands that are **safe** to run under pressure. The
new `dhis2-db wal` and `dhis2-db replication-slot` subcommand families
cover every scenario the operator should be able to reach without
touching `psql` directly:

```
dhis2-db wal status                   current pg_wal size, archive lag, oldest segment, pg_wal filesystem free %
dhis2-db wal archive-status           pg_stat_archiver + what the last 10 failures were (redacted)
dhis2-db wal retention                WAL retention reasons: archive, slot, keep_size, long tx
dhis2-db wal flush                    CHECKPOINT + request archive flush (safe, idempotent)
dhis2-db wal checkpoint               manual CHECKPOINT (safe)
dhis2-db wal emergency-drain --yes    LOUD: temporarily sets archive_command=/bin/true to unblock disk; archived WAL since the drain window is LOST so PITR regresses. Audit log entry.
dhis2-db replication-slot list        all slots with slot_name, slot_type, active, retained_wal_bytes, since_xid_age
dhis2-db replication-slot drop NAME --yes  drop a slot after confirming no live consumer
dhis2-db replication-slot advance NAME --to LSN --yes  advance a slot without consumer action (dangerous)
```

Every destructive path (`emergency-drain`, `drop`, `advance`) requires
explicit confirmation and writes an audit record.

The `dhis2-doctor wal` subcommand runs a focused read-only check that
synthesises the above signals and reports PASS / WARN / FAIL with
exact next commands.

---

## 3. Operator playbook when the disk is already filling

The CLI makes the response boring:

```
# 1. Confirm it is really WAL
dhis2-db wal status

# 2. Identify the cause
dhis2-db wal retention
dhis2-db replication-slot list
dhis2-db long-running --host $DB_HOST

# 3. Fix the cause (one of):

#  3a. Orphaned replication slot
dhis2-db replication-slot drop replica02_slot --yes

#  3b. Archive command failure
dhis2-db wal archive-status                     # look at the error
# fix the S3 credential / network / endpoint
dhis2-db wal flush                              # retries archiving

#  3c. Idle-in-transaction session
dhis2-db kill-grace $PID --grace-seconds 30 --yes

# 4. Only if the above does not free space AND the disk is >95% full
#    AND you accept losing recent WAL from the archive:
dhis2-db wal emergency-drain --yes

# 5. After the storm, re-enable the archive and run a fresh base backup
dhis2-db config apply --merge                   # restores archive_command
dhis2-backup create INSTANCE --mode base
```

Section 7 of `docs/CLI-WAL-Operations.md` captures this verbatim as a
printable one-page runbook.

---

## 4. HA-specific additions (slot into the HA plan Phase 1 and 4)

| HA concern | Mitigation |
|------------|------------|
| Patroni creates replication slots per replica; if a replica is permanently removed from the cluster, Patroni should drop the slot | Patroni `permanent_slots` config is **not** used (section 15b decision). We rely on Patroni's automatic slot cleanup. `dhis2-db replication-slot list` surfaces any slot whose owner is unknown. |
| `pg_rewind` after failover can leave timeline-mismatched WAL on the demoted node | `dhis2-cluster reinit` rebuilds the demoted node cleanly from the new primary via `pg_basebackup`. |
| Standby applies WAL at a slower rate than the primary generates it under load | Patroni's `maximum_lag_on_failover` + the HAProxy health check on `/replica` take a lagging replica out of the read pool automatically. |
| WAL-G parallel upload must keep up with WAL generation | Role sets `WALG_UPLOAD_CONCURRENCY` based on CPU count; monitors archive lag. |
| Patroni DCS writes also go to etcd; etcd disk full breaks DCS | etcd role sets `--quota-backend-bytes` and alerts. Documented in `docs/HA-Patroni.md`. |

All of these are already implicitly covered by the Phase 1 and Phase 4
scopes in the HA plan. This WAL plan makes the specific commands and
preflight rules explicit.

---

## 5. Delivery plan

### Phase 1 (this iteration) — CLI + role defaults + doctor + monitoring + docs

Deliverable:
- `dhis2-db wal` subcommand family (8 subcommands)
- `dhis2-db replication-slot` subcommand family (3 subcommands)
- `dhis2-doctor wal` cross-check
- `postgres` role gains sensible `max_wal_size` / `min_wal_size` defaults and new inventory variables
- `postgres` role runs an archive-command preflight before enabling `archive_mode=on`
- `monitoring` role: Prometheus exporter metrics documented, Grafana dashboard snippet
- Regression scenarios AW–AZ covering the above
- `docs/CLI-WAL-Operations.md` plus one-page runbook

**Not** in this phase:
- Dedicated `pg_wal_volume` filesystem automation (deferred to phase 2 because it needs an LVM / mount orchestration layer)
- `dhis2-wal-watchdog.service` systemd timer (phase 2)
- Automatic WAL-G configuration (phase 2 — needs the HA WAL-G role, which is itself in HA Phase 3)

### Phase 2 — dedicated `pg_wal` volume + systemd watchdog

Separate iteration, scoped as a follow-up. Needs a filesystem layer
that can safely add a volume to an existing production host without
downtime (or at least with documented downtime). Operator-opt-in
via `pg_wal_volume=/dev/sdb` host var.

### Phase 3 — Automated WAL-G + archive-aware alerting

Rolls into HA Phase 3 (WAL archiving and PITR). Once WAL-G is a
first-class role, the archive-command preflight becomes an archive-G
preflight, and the Prometheus alerts move from "archive_command
failures" to "backup success timestamp older than N minutes".

---

## 6. Acceptance criteria for Phase 1

- [ ] `dhis2-db wal status` shows size, archive lag, oldest segment, free %
- [ ] `dhis2-db wal retention` correctly attributes WAL retention to the three main causes (archive, slot, long tx)
- [ ] `dhis2-db replication-slot drop` refuses to drop an active slot without `--yes`
- [ ] `dhis2-db wal emergency-drain` requires `--yes`, writes an audit entry, and prints LOUD recovery guidance
- [ ] `dhis2-doctor wal` returns exit 6 (health) when any threshold is breached
- [ ] Role refuses to deploy with `archive_mode=on` + a failing archive_command
- [ ] Regression scenarios AW–AZ pass in mock mode
- [ ] `docs/CLI-WAL-Operations.md` reads cleanly as a runbook
- [ ] Shellcheck, yaml, cli-tests, regression, pytest all green locally

---

## 7. Risk register for the WAL work itself

| Risk | Mitigation |
|------|------------|
| Operator mistakes `emergency-drain` for a routine command and loses PITR history | Confirmation + typed-slot-name + audit record + LOUD UX |
| `dhis2-db replication-slot drop` kills an active HA replica mid-replication | Refuses when slot is `active` unless `--force`; `--force` additionally requires `--yes` |
| Role's archive-command preflight test leaves a test file in the archive bucket | Preflight test uses a short-TTL object name and deletes it on success; failure path leaves the test object so the operator can inspect |
| `pg_wal_volume` mount orchestration (Phase 2) damages a production data dir | Phase 2 only, implemented with safe shutdown + verify + atomic mount move; documented in a dedicated runbook; opt-in |
