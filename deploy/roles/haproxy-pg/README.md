# haproxy-pg

PostgreSQL connection router for HA. Separate from the application-
tier reverse proxy (that's the existing `proxy` role for nginx /
apache2 / openresty).

## What it does

- Listens on `:5000` (writes) and `:5001` (reads).
- Health-checks each PG host by polling the Patroni REST API on
  `:8008`. `/leader` returns 200 only on the current primary;
  `/replica` returns 200 on any up replica (or on the primary when
  no replicas are up).
- `postgres-write` routes 100% of connections to whichever host
  returns 200 on `/leader`. On failover, HAProxy repoints writes
  within one check cycle (~6 seconds with the default `inter 2s
  fall 3 rise 2`).
- `postgres-read` load-balances `leastconn` across `/replica`
  responders.
- Exposes stats on 127.0.0.1:7000 and a Unix socket at
  `/run/haproxy/pg.sock` for operator inspection.

## Placement

Three valid topologies for this role:

1. **Dedicated `[pg_lb]` hosts** — recommended for larger
   deployments.
2. **Co-located on the application / nginx hosts** — reasonable for
   small deployments; the PG LB listens on different ports from the
   app LB and does not interfere.
3. **Co-located on the PG hosts themselves** (Zalando pattern) — the
   app connects to any PG host's `:5000` and HAProxy on that host
   forwards to the current leader.

Whichever placement the operator picks, update `dhis.conf`:

```
connection.url = jdbc:postgresql://<pg_lb_vip>:5000/<db>?targetServerType=master
```

For analytics / read-only tooling, point at `:5001`.

## Tags

- `haproxy-pg-install`

## CLI integration

- `dhis2-proxy test` validates the config before reload (same safe-
  reload contract as the app proxy).
- `dhis2-cluster leader` and `dhis2-cluster replicas` show what
  HAProxy is routing to.

## No-regression notes

- Runs only when `dhis2_ha=true`. For every single-node deployment
  this role is skipped and nothing is installed.
- `ExecStartPre=haproxy -c -f ...` makes the systemd unit refuse to
  start on a broken config, preventing a bad reload from taking down
  the DB routing.
