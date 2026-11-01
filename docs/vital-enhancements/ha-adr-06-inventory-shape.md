# HA ADR 06 — Inventory shape for the HA PG tier

**Status:** accepted
**Date:** 2026-10-30

## Context

HA needs a way to express per-host role (primary vs replica) and
sync-standby selection. The two obvious options are:
1. Split `[databases]` into `[pg_primary]` and `[pg_replicas]`.
2. Keep `[databases]`, add `ha_role=primary|replica` host var.

## Decision

Keep `[databases]`. Add host vars:
- `ha_role=primary|replica` — operator intent (Patroni elects the
  real leader; this is for preflight sanity only).
- `ha_pg_sync_standby=true` — on exactly one replica, marks it as
  the sync-standby candidate.
- `physical_host=<label>` — purely metadata for the preflight
  cross-host rules.

## Consequences

- Backward compatible: an existing single-node operator who adopts
  HA simply adds replica hosts to `[databases]` and sets `ha_role`.
- Topology is less visible at inventory read time (one has to
  check host vars to see who is primary). Mitigated by
  `dhis2-cluster topology` which renders the shape.
- Preflight parses the INI directly rather than via
  `ansible-inventory --host` because that command may not be
  available on all operator workstations.

## Alternatives considered

- Split groups: cleaner topology at inventory read time but a
  breaking change for operators migrating from single-node.
- Hybrid (`[databases]` + optional `[pg_sync_standby]` subgroup):
  more inventory concepts without a strong benefit.
