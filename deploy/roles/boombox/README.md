# boombox

All-in-one single-host DHIS2 architecture: every service runs
directly on the host, no LXD containers.

## When this role runs

Only when `dhis2_architecture=boombox` is set in inventory.
`deploy/dhis2.yml` includes it as the first play after `pre-install`
and before `postgres`, so downstream roles consume the facts this
role sets.

## What it does

- Gathers hardware facts (RAM, CPU, root filesystem free).
- Computes compliance-safe tunings and exports them as set_facts
  that `postgres`, `create-instance`, and `proxy` consume:
  - `pg_shared_buffers`, `pg_effective_cache_size`,
    `pg_work_mem`, `pg_maintenance_work_mem`,
    `pg_max_connections`
  - `heap_memory_size` (Tomcat JVM heap)
  - `pg_max_wal_size`, `pg_max_slot_wal_keep_size` (WAL Phase 1
    compliance targets)
  - `TLS_TYPE` (defaults to `letsencrypt` in production mode,
    `selfsigned` in workshop mode)
- Reports the final values via `ansible.builtin.debug`.

Every variable is **overridable per host** in inventory - the role
only sets a value when the operator has not. See
`defaults/main.yml` for the formulas and `docs/Boombox.md` for the
operator guide.

## No-regression contract

- Role runs ONLY when `dhis2_architecture=boombox`. Zero behaviour
  change for existing LXD / distributed / hybrid deployments.
- Only sets facts. No packages are installed, no services are
  started by this role.
- Honours operator overrides first; auto-computes only unset
  variables.

## Related

- `docs/Boombox.md` - operator guide
- `docs/vital-enhancements/boombox-plan.md` - design + locked
  decisions
- `docs/CLI-WAL-Operations.md` - WAL compliance math (the role
  stays within the compliance budget by construction)
