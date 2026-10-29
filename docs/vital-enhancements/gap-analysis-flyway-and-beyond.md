# Gap analysis: Flyway hardening and remaining operational gaps

Supplement to
[`dhis2-server-tools-implementation-requirements-regenerated.md`](./dhis2-server-tools-implementation-requirements-regenerated.md).
Audits the current CLI/role surface against real-world Flyway failure
modes and lists the gaps that remain after the initial PR. Each gap
links to the fix landed in this iteration.

## 1. Flyway failure modes that must be first-class

| # | Failure mode | Detection today | Gap | Resolution |
|---|--------------|-----------------|-----|------------|
| F1 | **Flyway marked a previous migration as `success=false`** and the schema is now locked out until repaired. DHIS2 will refuse to start cleanly. | None. `monitor-migrations.yml` only inspects `catalina.out` after Tomcat is already starting. | Must **block** before Tomcat start. | `dhis2-upgrade preflight` queries `flyway_schema_history` for failed rows and fails before WAR activation. `dhis2-db flyway info` surfaces the same state read-only. |
| F2 | **Stuck `flyway_schema_history_lock` row** from a prior killed start-up, preventing the next start from acquiring the lock. | None. Role would hang until timeout. | Must detect at start-of-upgrade and offer unlock. | `dhis2-db flyway locks` reports age; `dhis2-db flyway unlock` with explicit confirmation. Upgrade preflight warns when lock age exceeds `DHIS2_FLYWAY_STALE_LOCK_SEC` (default 1800s). |
| F3 | **Checksum mismatch** on a migration that was previously applied — a customisation modified a shipped migration file. | None. Only visible after Tomcat fails to start. | Detectable from `flyway_schema_history.checksum` vs installed WAR. | `dhis2-db flyway validate` runs the Flyway maven goal via the DHIS2 WAR classpath if available, falls back to row-level checksum diffing. |
| F4 | **Baseline required** — attaching an older DB that has no `flyway_schema_history` table at all. | None. `dhis2-instance database attach` wires through, but DHIS2 fails to start on an un-baselined schema with pre-existing tables. | Must baseline explicitly before first start. | `dhis2-db flyway baseline --version X` creates the baseline row; `dhis2-instance database attach` recommends it when attaching into a non-empty schema with no history. |
| F5 | **Out-of-order migrations** — target build ships `V2_42_01` but history already has `V2_43_00`. Flyway refuses by default. | None. | Preview from `flyway_schema_history`. | `dhis2-db flyway pending --to VERSION` lists what would run. Upgrade preflight warns if the target would introduce out-of-order files. |
| F6 | **Partial-apply + DDL rollback** leaving an inconsistent object layout. | None. | Capture the failing SQL for the operator. | `monitor-migrations.yml` on failure dumps `flyway_schema_history.script` for the last row and ships it in the failure bundle. |
| F7 | **Analytics table rebuild** silently queued post-upgrade. Users complain of empty reports for hours. | None. | Surface state. | `dhis2-db analytics status` queries `analytics_tableupdates` (name varies by DHIS2 version) and reports last run, duration, state. |
| F8 | **PostgreSQL major-version incompatibility** (e.g. 2.43 against PG 11). Flyway may start applying migrations that use syntax PG 11 cannot execute. | Lightly in `dhis2-upgrade compatibility`. | Must be a hard gate in `preflight`. | Preflight queries `SHOW server_version_num` and compares against the compatibility matrix; refuses `auto` upgrades on mismatch. |
| F9 | **Connection pool exhaustion** during long migrations starves other apps on a shared Postgres. | None. | Guard-rail. | `monitor-migrations.yml` samples `pg_stat_activity` every poll cycle and records a warning line to the state file if active count exceeds 80% of `max_connections`. |
| F10 | **Progress visibility** — operator has no idea which migration is currently running during a 20-minute upgrade. | Only "flyway=completed" at the end. | Live progress line. | `monitor-migrations.yml` queries `flyway_schema_history ORDER BY installed_rank DESC LIMIT 1` each poll and prints `migration=<version> script=<name> running_for=Xs` to stdout. |

## 2. Non-Flyway gaps surfaced during the audit

| Area | Gap | Fix |
|------|-----|-----|
| `dhis2-doctor config` | Only verifies `database_host` resolves in inventory. The requirements doc (section 57.14) asks for cross-check against `server.base.url`, TLS SANs, FQDN, and monitoring targets. | Enhanced `_config` reads `/opt/dhis2/dhis.conf` (redacted), the proxy certificate, and the inventory to flag drift. |
| `dhis2-db terminate-session` | Instant `pg_terminate_backend`. No grace. | New `dhis2-db kill-grace PID [--grace-seconds N]` runs `pg_cancel_backend` first, waits, then terminates if the session persists. |
| `dhis2-vault rotate` | Uses `ansible-vault rekey`. Doesn't coordinate secret rotation **across the components that share a credential** (section 57.20). | Add `dhis2-vault rotate-db-password` as a documented, transactional workflow: generate new secret → update PG role → update `dhis.conf` → application restart → validate → auto-rollback on failure. Shipped as a doc + CLI stub with explicit prerequisites. |
| Failure diagnostic bundle | `dhis2-logs bundle` is generic. On an upgrade failure the operator needs a focused tarball with the exact failing migration SQL. | New `dhis2-upgrade failure-bundle INSTANCE` command (and `monitor-migrations.yml` auto-captures on failure) producing a dedicated archive. |

## 3. Known limitations retained

These are intentionally **not** addressed in this iteration (section 49 of
the main requirements doc):

- No automatic SQL repair of a failed migration (section 79).
- No Patroni / PostgreSQL HA.
- No automatic cross-region disaster recovery.
- No Docker / Kubernetes support.

## 4. Verification

Each row in section 1 is covered by one or more automated tests:

| Row | CLI test | Role test | Regression scenario |
|-----|----------|-----------|---------------------|
| F1  | `dhis2-db flyway info` returns non-zero exit on failed rows | — | New: Scenario AF |
| F2  | `dhis2-db flyway locks` reports age; `unlock` requires `--yes` | — | New: Scenario AG |
| F3  | `dhis2-db flyway validate --help` | — | — |
| F4  | `dhis2-db flyway baseline --version X --yes` round-trip in Molecule | `molecule/upgrade-monitor-migrations` adds a baseline case | — |
| F5  | `dhis2-db flyway pending --help` | — | — |
| F6  | — | `molecule/upgrade-monitor-migrations` asserts failing script dump | New: Scenario AH |
| F7  | `dhis2-db analytics status` returns 0 with no analytics table found | — | — |
| F8  | `dhis2-upgrade preflight` refuses on PG version mismatch | — | New: Scenario AI |
| F9  | — | monitor records warning line in state file | — |
| F10 | — | monitor emits live progress lines | — |
