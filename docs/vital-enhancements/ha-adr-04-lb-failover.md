# HA ADR 04 — LB failover mechanism

**Status:** accepted
**Date:** 2026-10-30

## Context

The app-tier LB needs a single addressable endpoint (VIP or
hostname) that survives an LB-node failure. keepalived VRRP is the
usual choice but requires L2 adjacency; DNS round-robin + a health
script works anywhere but has coarser failover timing.

## Decision

Document and ship **both** mechanisms. `dhis2-deploy init
--architecture ha` prompts the operator to choose. The
`ha_lb_mode` inventory variable selects at apply time
(`keepalived | dns-rr`).

## Consequences

- Role matrix doubles for the LB layer: `keepalived` role in Phase
  2 + `dns-rr` role (DNS provider plugins) in Phase 2.
- Operators in cloud VPCs without L2 adjacency have a supported
  path (DNS or the cloud LB).
- On-prem operators get the sub-5-second failover they expect.

## Alternatives considered

- keepalived default: rejected because many cloud deployments can't
  use it; silent failure mode (VIP never migrates) is worse than
  an explicit init-time prompt.
- DNS default: rejected because on-prem operators would get
  slower failover without being asked.
