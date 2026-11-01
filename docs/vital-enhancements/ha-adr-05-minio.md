# HA ADR 05 — MinIO as a shipped role

**Status:** accepted
**Date:** 2026-10-30

## Context

HA needs an S3-compatible object store for the DHIS2 filestore (so
app nodes share uploaded documents) and for WAL archiving / PITR
seeds. Operators who don't already run S3 face a decision gap.

## Decision

Ship a **`minio` role** in Phase 2 with two modes:
- `single-node` — development / small production
- `distributed-4` — production minimum with erasure coding on 4
  nodes

Operators who already run S3-compatible storage set
`ha_filestore_external=true` to skip the role.

## Consequences

- Larger operational surface for the project (we own a MinIO
  deployment). Mitigated by sticking to MinIO's recommended
  distributed-4 topology and documenting upgrade paths.
- Operators get a working endpoint without having to pick
  storage. Reduces "I would adopt HA but I'd need to pick an S3
  provider first" friction.

## Alternatives considered

- Document integration only; operator brings their own S3.
  Rejected — would push every small operator toward AWS, which
  conflicts with the project's self-hosted ethos.
- Defer to a later phase. Rejected — the filestore is a
  prerequisite for Phase 2 app HA.
