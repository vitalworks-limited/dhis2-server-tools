# patroni

HA PostgreSQL manager for the `[databases]` tier when `dhis2_ha=true`.
Patroni owns the PG process directly - the OS `postgresql` service is
stopped and masked by this role, and all lifecycle (start, stop,
failover, replica rebuild) goes through `patronictl` or the
`dhis2-cluster` CLI.

## When it runs

Only when `dhis2_ha=true`. The `postgres` role continues to install
PG binaries and extensions; Patroni manages the cluster.

## Variables

See `defaults/main.yml`. Must set in a vaulted file:

| Variable | Purpose |
| -------- | ------- |
| `patroni_rest_password` | Protects the REST API (HAProxy health checks + CLI) |
| `patroni_replication_password` | Streaming replication user |
| `patroni_superuser_password` | PG superuser the role creates on first boot |

Topology:

| Host var | Values | Purpose |
| -------- | ------ | ------- |
| `ha_role` | `primary` \| `replica` | Operator intent only; Patroni elects the real leader |
| `ha_pg_sync_standby` | `true` on exactly one replica | Marks the replica that MUST be in the synchronous group |
| `physical_host` | arbitrary string | Checked by `dhis2-deploy preflight` to enforce cross-host spread |

## Tags

- `patroni-install`

## CLI integration

Full operator surface lives in `bin/dhis2-cluster` (13 subcommands;
refuses without `dhis2_ha=true`):

```
dhis2-cluster list                           # members + leader
dhis2-cluster status                         # per-node state + lag
dhis2-cluster topology [--check]             # 2-node + 3-etcd rules
dhis2-cluster failover   --candidate HOST --yes
dhis2-cluster switchover --candidate HOST --yes
dhis2-cluster reinit     HOST --yes          # rebuild replica
dhis2-cluster pause | resume                 # halt auto-failover
dhis2-cluster etcd    status | members | endpoints
dhis2-cluster haproxy status | pools | log
dhis2-cluster vip     status                 # keepalived + VIP
dhis2-cluster logs    <node>
dhis2-cluster certs   check
```

Every destructive subcommand (`failover`, `switchover`, `reinit`,
`pause`) is confirmation-gated. Output passes through the standard
secret-redaction pipeline. Reads use the Patroni REST API
(`/cluster`, `/leader`, `/replica`, `/history`). Writes shell out
to `patronictl` on the target host.

## No-regression notes

- Role is skipped unless `dhis2_ha=true`. Every existing single-node
  deployment is untouched.
- Patroni respects the `pg_max_wal_size` / `pg_min_wal_size` defaults
  from the `postgres` role, so the WAL safety work in
  `docs/CLI-WAL-Operations.md` applies here too.
- `use_slots: true` + `max_replication_slots: 10` keep the WAL
  retention contract on the primary; `dhis2-db replication-slot
  list` surfaces anything orphaned.
- `use_pg_rewind: true` means a demoted primary can rejoin without a
  full re-base-backup. `dhis2-cluster reinit` forces a full rebuild
  when rewind is not safe.
