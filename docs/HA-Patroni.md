# HA PostgreSQL with Patroni

Phase 1 of the HA plan ships three roles plus the `dhis2-cluster`
CLI. This page is the operator guide. Full design discussion lives
in [docs/vital-enhancements/ha-implementation-plan.md](./vital-enhancements/ha-implementation-plan.md).

## When this applies

Only when the inventory sets `dhis2_ha=true` and populates the
`[etcd]` and `[databases]` groups. For every other deployment the
three HA roles are skipped entirely and nothing in the existing
single-node path changes.

## Architecture

```
                      app nodes (dhis2-instance)
                             │
                             ▼
                      HAProxy (haproxy-pg role)
                   writes :5000    reads :5001
                             │
             ┌───────────────┼───────────────┐
             ▼               ▼               ▼
         pg01 primary   pg02 sync      pg03 async
         (Patroni)      (Patroni)      (Patroni)
             │               │               │
             └──── streaming replication ────┘
                             │
                             ▼
                      etcd DCS (3 nodes)
                      etcd01 / etcd02 / etcd03
```

- **Patroni** owns the PostgreSQL process on every DB node. The OS
  `postgresql` service is stopped and masked; all PG lifecycle
  (start, stop, failover, replica rebuild) goes through
  `patronictl` or `dhis2-cluster`.
- **etcd** is the DCS. Patroni writes cluster state (who is leader,
  which replicas are in the sync group) to etcd on every DCS loop.
- **HAProxy** (role `haproxy-pg`) polls Patroni's REST API on
  `:8008/leader` and `:8008/replica` and routes TCP connections
  accordingly.

## Topology prerequisites

Section 15b of the HA plan is enforced by
`dhis2-deploy preflight` and the `dhis2-cluster topology --check`
command:

| # | Rule | Enforced by |
|---|------|-------------|
| 1 | 3 etcd members on 3 distinct `physical_host` values | preflight (hard fail) |
| 2 | Patroni primary + sync-standby on distinct `physical_host` | preflight (hard fail) |

Set the `physical_host` host variable on every HA inventory host
even for distributed-SSH deployments; it is purely metadata for the
preflight.

## Inventory shape

```ini
[databases]
pg01 ansible_host=10.0.1.21 physical_host=host-a ha_role=primary
pg02 ansible_host=10.0.1.22 physical_host=host-b ha_role=replica ha_pg_sync_standby=true
pg03 ansible_host=10.0.1.23 physical_host=host-c ha_role=replica

[etcd]
etcd01 ansible_host=10.0.1.31 physical_host=host-a
etcd02 ansible_host=10.0.1.32 physical_host=host-b
etcd03 ansible_host=10.0.1.33 physical_host=host-c

[pg_lb]
# optional - haproxy-pg falls back to co-location on [databases] when empty

[all:vars]
dhis2_ha=true
ha_cluster_name=dhis2-production
postgresql_version=16
```

Required vaulted variables (see
[docs/CLI-Configuration-Preservation.md](./CLI-Configuration-Preservation.md)):

- `patroni_rest_password`
- `patroni_replication_password`
- `patroni_superuser_password`

## Day-one bootstrap

```bash
# 1. Preflight validates section-15b rules
dhis2-deploy preflight

# 2. Apply the HA plays
dhis2-deploy apply

# 3. Cluster inspection
dhis2-cluster status
dhis2-cluster topology --check
dhis2-cluster etcd-health
```

Expected first boot:
- etcd quorum established on all 3 nodes
- Patroni starts on `pg01` and initializes PG via `initdb`
- `pg02` and `pg03` run `pg_basebackup` from the current leader
- Within ~30 seconds `dhis2-cluster status` shows 1 leader + 2 replicas
- `pg02` is in the synchronous group (because `ha_pg_sync_standby=true`)
- HAProxy on each `[pg_lb]` or `[databases]` host routes `:5000` to the leader

## Point `dhis.conf` at the HA endpoint

In your DHIS2 instance inventory, set:

```
database_host=<pg_lb hostname or VIP>
# dhis.conf then renders:
# connection.url = jdbc:postgresql://<pg_lb>:5000/<db>?targetServerType=primary
```

The `targetServerType=primary` hint lets libpq know we expect
read-write access.

## Day-two operations (dhis2-cluster)

```bash
dhis2-cluster status                       # scope, leader, members with lag
dhis2-cluster topology                     # groups + physical_host per host
dhis2-cluster topology --check             # enforce section 15b
dhis2-cluster leader                       # current primary name
dhis2-cluster replicas                     # names + lag_bytes
dhis2-cluster lag
dhis2-cluster watch --interval 5           # live dashboard

dhis2-cluster failover --to pg02 --yes     # UNPLANNED promotion (forced)
dhis2-cluster switchover --to pg02 --yes   # PLANNED, waits for catch-up
dhis2-cluster reinit pg03 --yes            # rebuild from leader via pg_basebackup

dhis2-cluster patroni-config show
dhis2-cluster etcd-health

dhis2-cluster pause   --yes                # suspend auto-failover (maintenance window)
dhis2-cluster resume  --yes                # resume auto-failover
```

All destructive paths pass through `dhis2_cli_confirm` and write to
`/var/log/dhis2-server-tools/audit.ndjson`.

## Known limitations in Phase 1

| Item | Status | Reference |
|------|--------|-----------|
| App-tier HA (2+ Tomcat nodes behind an L7 LB, Redis sessions) | Phase 2 | HA plan §13 |
| keepalived VIP for the app LB | Phase 2 | HA plan §13 |
| Redis for shared Tomcat sessions | Phase 2 | HA plan §13 |
| MinIO + DHIS2 filestore on S3 | Phase 2 | HA plan §13 |
| WAL-G continuous archiving + PITR | Phase 3 | HA plan §13 |
| Automatic alerting dashboards for the HA cluster | Phase 4 | HA plan §13 |
| Chaos smoke tests on real hosts | Phase 6 | HA plan §13 |

## Local reproducible test

The `molecule/ha-patroni-bootstrap` scenario validates the three
roles in CI (`molecule test -s ha-patroni-bootstrap`). It runs in
`--check` mode because Patroni / etcd / PG inside Docker with
systemd is unreliable for failover-timing tests. For a real test:

```bash
# On a workstation with Vagrant + libvirt (or VirtualBox)
cd tests/ha
vagrant up                          # 3 Ubuntu 22.04 VMs
./run.sh bootstrap                  # dhis2-deploy apply against the Vagrant inventory
./run.sh verify                     # dhis2-cluster status
./run.sh failover-chaos             # kills the primary, asserts <30s promotion
```

The `tests/ha/` directory is planned for Phase 6.

## No-regression contract

- When `dhis2_ha=false` (default) nothing changes: `deploy.sh`,
  `ansible-playbook deploy/dhis2.yml`, every existing tag, every
  existing inventory variable, every existing single-node CLI
  command. All 60 pre-HA regression scenarios still pass.
- `dhis2-cluster` is the only command that assumes HA. It exits 3
  (preflight) with a clear message on any inventory that is not
  opted into HA.
- The `postgres` role continues to install PG binaries + extensions
  for both paths; only the service management (who starts the PG
  process) differs.

## See also

- [docs/HA-Runbook-Failover.md](./HA-Runbook-Failover.md)
- [docs/vital-enhancements/ha-implementation-plan.md](./vital-enhancements/ha-implementation-plan.md)
- [docs/CLI-WAL-Operations.md](./CLI-WAL-Operations.md) — WAL safety
  under HA (replication slots pin WAL; `dhis2-db replication-slot
  list` identifies orphans)
- [Patroni upstream](https://patroni.readthedocs.io/)
