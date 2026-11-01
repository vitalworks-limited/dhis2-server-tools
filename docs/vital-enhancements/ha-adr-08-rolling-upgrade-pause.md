# HA ADR 08 — DHIS2 rolling upgrade and Patroni auto-failover

**Status:** accepted
**Date:** 2026-10-30

## Context

A DHIS2 rolling upgrade across multiple app nodes may restart the
primary DB briefly (via Flyway migrations) and could trigger
Patroni's automatic failover unnecessarily. We want:

1. The upgrade to proceed without surprise failovers.
2. The failover protection to be back in place as soon as the
   upgrade completes.
3. The operator to retain full control if they want to coordinate
   manually.

## Decision

`dhis2-upgrade run --rolling` **auto-pauses Patroni** before the
first app-node upgrade and **auto-resumes** after the last. An
explicit `--no-auto-pause` disables the auto-wrap; in that mode
`dhis2-upgrade run` refuses to proceed unless Patroni is already
paused.

## Consequences

- Fewer surprises for the operator in the common case.
- An operator who wants to coordinate pauses with other HA work
  (e.g. a planned switchover) has a documented path.
- `dhis2-upgrade run --rolling` is the recommended production
  upgrade path when HA is in use.

## Alternatives considered

- Always auto-pause; no override: convenient but makes some HA
  maintenance workflows harder.
- Operator always manually pauses: safest in theory, but the extra
  friction leads to operators skipping the step and causing
  spurious failovers during upgrades.
