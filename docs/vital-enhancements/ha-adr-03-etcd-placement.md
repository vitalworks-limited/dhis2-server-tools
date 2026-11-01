# HA ADR 03 — etcd placement

**Status:** accepted
**Date:** 2026-10-30

## Context

Patroni's DCS (etcd) can be co-located on the PG nodes or deployed
on dedicated hosts. Co-location saves 3 hosts in a lean HA
deployment. Dedicated hosts prevent a cascading failure where
etcd disk pressure interferes with PG I/O.

## Decision

HA requires a **dedicated `[etcd]` inventory group** with 3+ hosts
on 3+ distinct `physical_host` values. The role refuses to run
without it.

## Consequences

- Minimum 6 hosts for a lean HA deployment (3 PG + 3 etcd), or 9
  with 2 app + 2 LB. Documented in `docs/HA-Patroni.md`.
- Clean failure isolation: DCS disk pressure cannot kill the PG I/O
  path.
- Operators who want co-location can still achieve it by assigning
  the same `physical_host` to a PG and an etcd container in LXD
  topologies — the role does not care, only the preflight does.

## Alternatives considered

- Co-locate on PG nodes by default: smaller host count, but a
  disk-full etcd on the PG primary would compound the outage.
  Rejected on failure-domain grounds.
- Inventory-driven override (co-locate when `[etcd]` empty): would
  work but makes the "it's not real HA" preflight message harder
  to produce.
