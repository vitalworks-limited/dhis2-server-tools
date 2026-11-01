# HA ADR 02 — PostgreSQL major version for HA

**Status:** accepted
**Date:** 2026-10-30

## Context

Patroni config, HAProxy health-check semantics, and WAL-G flags
differ by PG major. Supporting multiple majors doubles the test
matrix and requires conditional Jinja in `patroni.yml`.

## Decision

HA supports **PostgreSQL 16 only**. The `patroni` role refuses
other major versions in preflight.

## Consequences

- Matches the current `create-instance` role default
  (`postgresql_version=16`).
- Operators on PG 15 or earlier must upgrade PG before adopting
  HA. Documented in `docs/HA-Patroni.md`.
- Later PG majors (17, 18) will be added by a dedicated ADR once
  Patroni + DHIS2 compatibility is confirmed.

## Alternatives considered

- PG 15 and 16: two config templates; small code gain, meaningful
  test burden. Rejected.
- PG 14, 15, 16: three templates; same reasoning, more work.
