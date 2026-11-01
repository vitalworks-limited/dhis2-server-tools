# HA ADR 01 — DHIS2 version baseline for HA

**Status:** accepted
**Date:** 2026-10-30

## Context

Phase 2 of the HA plan ships a Tomcat Redis session manager so that
2+ Tomcat nodes behind a sticky LB can survive a node failure
without logging users out. The session-manager JAR differs between
Tomcat 9 (DHIS2 2.41 and earlier) and Tomcat 10 (DHIS2 2.42+;
Jakarta namespaces).

## Decision

HA supports DHIS2 **2.41 and later**. The `tomcat-redis-session`
role (Phase 2) ships two JARs and selects by `tomcat_version`.

## Consequences

- Operators on 2.39 and 2.40 must upgrade DHIS2 before adopting HA.
- Documentation and tests cover both Tomcat 9 and Tomcat 10 code
  paths.

## Alternatives considered

- 2.42+ only: simpler test matrix, but excludes operators who are
  currently on 2.41 LTS.
- 2.39+ LTS: broadest coverage; three JARs to maintain. Rejected as
  not worth the ongoing cost.
