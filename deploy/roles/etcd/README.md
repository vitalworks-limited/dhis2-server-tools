# etcd

Three-node etcd cluster used as the DCS by Patroni. Section 15b of
the HA plan requires a dedicated `[etcd]` inventory group with 3+
hosts on 3+ distinct `physical_host` values.

## Responsibilities

- Install the pinned etcd binary (not the Ubuntu package - too old for
  current Patroni).
- Render `etcd.conf.yml` with the cluster bootstrap list computed
  from the `[etcd]` inventory group.
- Install a hardened systemd unit (`NoNewPrivileges`, `ProtectHome`,
  `ProtectSystem=full`, `PrivateTmp`).
- Open UFW rules on ports 2379 (client) and 2380 (peer) scoped to the
  cluster members only.
- Enable periodic compaction + a backend quota so a runaway DCS
  cannot wedge the cluster.

## Variables

See `defaults/main.yml`. Common overrides:

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `etcd_version` | `3.5.21` | Pinned release |
| `etcd_data_dir` | `/var/lib/etcd` | On-disk state |
| `etcd_client_port` | `2379` | |
| `etcd_peer_port` | `2380` | |
| `etcd_quota_backend_bytes` | `8589934592` | 8 GiB |
| `etcd_cluster_token` | `{{ ha_cluster_name }}-etcd` | Unique per environment |
| `ha_etcd_tls` | `false` | Flip to `true` in Phase 4 hardening |

## Tags

- `etcd-install`

## CLI integration

- `dhis2-cluster etcd-health` runs `etcdctl endpoint health` against
  every member.
- `dhis2-doctor cluster` includes the etcd quorum check.

## No-regression notes

- Role runs **only** when `dhis2_ha=true` AND an `[etcd]` group is
  populated. For every existing single-node deployment the role is
  entirely skipped.
- The initial-cluster string is only consulted on first boot; adding
  or removing members on a running cluster is operator-driven via
  `etcdctl member add|remove`, documented in
  `docs/HA-Runbook-Failover.md`.
