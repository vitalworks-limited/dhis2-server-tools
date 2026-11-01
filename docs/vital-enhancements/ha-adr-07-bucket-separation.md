# HA ADR 07 — WAL and filestore bucket separation

**Status:** accepted
**Date:** 2026-10-30

## Context

The DHIS2 filestore (uploaded documents) and the WAL archive (PITR)
both need object storage. A single-bucket design is simpler
operationally but means a compromised DHIS2 upload credential can
corrupt the WAL archive.

## Decision

**Two buckets, two credentials.** Role variables:

```
ha_filestore_bucket, ha_filestore_credentials, ha_filestore_endpoint
ha_wal_bucket,       ha_wal_credentials,       ha_wal_endpoint
```

Operators who insist on one bucket set
`ha_wal_credentials=ha_filestore_credentials` and point to a WAL
prefix.

## Consequences

- Blast-radius isolation: a leaked DHIS2 app credential cannot
  touch the WAL archive the operator depends on for PITR.
- Two sets of credentials to rotate. Mitigated by
  `dhis2-vault rotate` family in Phase 2.
- The `minio` role (ADR 05) grants IAM to each bucket's dedicated
  credential by default.

## Alternatives considered

- One bucket, one credential, two prefixes: simplest; worst for
  compromise containment.
- Two buckets, same credential, two prefixes: trades convenience
  for a false sense of isolation.
