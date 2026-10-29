# postgres

Installs and configures PostgreSQL on hosts in the `[databases]`
inventory group.

## Responsibilities

- Install the configured PostgreSQL major version
  (`postgresql_version`, default `16`).
- Lay down a tuned `dhispg.conf` fragment with safe defaults.
- Honour operator-maintained `dhispg.conf` and `pg_hba.conf` — custom
  settings are **not** silently replaced on re-run.
- Create instance databases, roles, and HBA entries by delegation from
  the `create-instance` role.
- Install PostgreSQL exporters for monitoring where configured.
- Install backup tooling when invoked with the `backup-script` tag.

## Dispatch

The role entry (`tasks/main.yml`) chooses between
`tasks/lxd.yml` and `tasks/ssh.yml` based on each host's
`ansible_connection`. The CLI never flattens the connection mode.

## Variables

See `defaults/main.yml` and the inventory variables documented in
[docs/Variables.md](../../../docs/Variables.md).

Key knobs:

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `postgresql_version` | `16` | Major version to install |
| `pg_shared_buffers` | unset | Hint for working-set cache (~25% RAM) |
| `pg_work_mem` | unset | Per-sort/hash memory |
| `pg_maintenance_work_mem` | unset | Used by VACUUM / CREATE INDEX |
| `pg_effective_cache_size` | unset | Planner hint |
| `pg_max_connections` | unset | Keep in sync with memory budget |

## Tags

- `postgresql-install`
- `postgresql-conf`
- `backup-script` (owned by the `backups` role but shares DB plays)

## CLI integration

- `dhis2-db status | version | connections | activity | locks | tables
  | indexes | bloat | ownership | roles | extensions | hba show |
  config diff` — read-only inspection.
- `dhis2-db hba add | remove | validate` — HBA mutation with
  pre-change backup and config reload only on success.
- `dhis2-db config apply --preserve | --merge | --replace` — explicit
  mode selection; `preserve` and `merge` keep operator-maintained
  settings intact.
- `dhis2-db capacity | oom-check` — memory/cgroup estimates and OOM
  log scraping.

## No-regression notes

- Existing `dhispg.conf` is preserved; the role does not rewrite it
  unless explicit replace behaviour is requested.
- The database password used by DHIS2 is generated once by the
  `pre-install` role and reused forever unless an explicit rotation
  is performed. Section 11.5.1 "Database password stability".
