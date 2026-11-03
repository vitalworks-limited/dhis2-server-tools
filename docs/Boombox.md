# Boombox — all-in-one single-host DHIS2

Boombox puts every DHIS2 service directly on one Ubuntu host, no
LXD. Fits workshop laptops, conference demos, small single-site
production, and operators who prefer OS-native systemd units to
containers.

Design decisions (locked):
[docs/vital-enhancements/boombox-plan.md](./vital-enhancements/boombox-plan.md).

## When to pick boombox

- Workshop / demo laptops.
- Small single-site production (one country office).
- Operators who need the simplest possible mental model.

## When NOT to pick boombox

- **HA.** One host is one failure domain; the preflight refuses
  `dhis2_ha=true` with `dhis2_architecture=boombox`.
- **Multi-tenant isolation.** Three DHIS2 instances on one boombox
  share one PG, one Tomcat process, one nginx. Use LXD or
  distributed SSH for isolation.
- **Running Doris** — needs ≥16 GB RAM, out of scope for Phase 1.

## Prerequisites

- Ubuntu 22.04 or 24.04.
- `sudo` and SSH access as the operator.
- `ufw` installed (strict in production mode; relaxed in workshop).
- **LXD must not be installed.** The preflight refuses a boombox
  deploy when `lxc` is present (locked decision 3).

Recommended (not enforced — locked decision 1):

- 4+ GB RAM
- 2+ CPU cores
- 50+ GB disk free

A 2 GB demo VM still works; `dhis2-deploy preflight` warns and
proceeds.

## Install

```bash
# 1. Clone + install the CLI
git clone https://github.com/vitalworks-limited/dhis2-server-tools.git
cd dhis2-server-tools
sudo ./install.sh

# 2. Generate a boombox inventory
#    Production: fqdn + email required
sudo dhis2-deploy init --architecture boombox --mode production \
    --fqdn hmis.example.org --email ops@example.org

#    Workshop: fqdn optional, self-signed TLS
sudo dhis2-deploy init --architecture boombox --mode workshop

# 3. Preflight (reads the inventory, runs the 15 boombox checks)
sudo dhis2-deploy preflight

# 4. Deploy
sudo dhis2-deploy apply

# 5. Verify
sudo dhis2-status
sudo dhis2-doctor boombox
```

At the end, DHIS2 is reachable at:

```
https://<fqdn>/hmis
```

Default admin: `admin` / `district` — **change this immediately**.

## Modes

### `production`

- fqdn + email mandatory (hard preflight fail without them).
- Let's Encrypt is the default TLS (`TLS_TYPE=letsencrypt`).
- UFW must be `active` (hard preflight fail otherwise).
- `dhis2-doctor boombox` treats UFW inactive as FAIL.

### `workshop`

- fqdn + email optional.
- Self-signed TLS by default.
- UFW inactive is a warning, not a failure.
- Faster to stand up for a demo.

> **Warning**: do not expose a `workshop` mode boombox to the
> public internet.

## Fact-based tunings

The `boombox` role computes defaults from the host's RAM / CPU /
disk and exports them as Ansible facts that downstream roles
(`postgres`, `create-instance`, `proxy`) consume. Every value is
overridable per host in inventory.

| Setting | Formula | Rationale |
|---------|---------|-----------|
| `pg_shared_buffers` | 25 % of RAM | PG rule of thumb |
| `pg_effective_cache_size` | 60 % of RAM | PG planner hint |
| `pg_work_mem` | `max(4 MiB, 5% RAM / max_connections)` | Avoid OOM under concurrency |
| `pg_maintenance_work_mem` | 10 % of RAM, min 256 MiB, max 2 GiB | VACUUM / CREATE INDEX speed |
| `pg_max_connections` | `max(100, 20 × nproc)` | Reasonable headroom |
| `heap_memory_size` (Tomcat JVM) | 40 % of RAM, capped at 32 GiB | Leave room for PG + OS cache |
| `pg_max_wal_size` | `min(16 GiB, 10 % of filesystem free)` | WAL compliance Phase 1 |
| `pg_max_slot_wal_keep_size` | 2 × `pg_max_wal_size` | WAL compliance Phase 1 |
| `TLS_TYPE` | `letsencrypt` (production) / `selfsigned` (workshop) | Mode-driven default |

Override any value by setting it in `deploy/inventory/hosts`:

```ini
[all:vars]
pg_shared_buffers=2GB      # overrides the 25 % default
heap_memory_size=4096m     # overrides the 40 % default
```

The role **only** sets a value when the operator has not already
set it.

## Preflight (15 checks)

| # | Check | Mode: production | Mode: workshop |
|---|-------|------------------|----------------|
| 1 | `lxc` binary absent | HARD FAIL | HARD FAIL |
| 2 | `fqdn` set | HARD FAIL | warn |
| 3 | `email` set | HARD FAIL | warn |
| 4 | RAM ≥ 4 GB | warn | warn |
| 5 | CPU ≥ 2 cores | warn | warn |
| 6 | Root FS ≥ 50 GB free | warn | warn |
| 8 | UFW active | HARD FAIL | warn |
| 9 | Port 80 free | HARD FAIL | HARD FAIL |
| 10 | Port 443 free | HARD FAIL | HARD FAIL |
| 11 | Port 5432 free | HARD FAIL | HARD FAIL |
| 12 | Port 8080 free | HARD FAIL | HARD FAIL |
| 13 | `dhis2_ha` != true | HARD FAIL | HARD FAIL |

Resource findings (4–6) are warnings, not failures, per locked
decision 1.

## Day-two commands

Every existing `dhis2-*` CLI command works on boombox because they
all route through Ansible against the inventory, which here points
at `127.0.0.1` with `ansible_connection=local`.

```bash
dhis2-status                           # instances + infrastructure overview
dhis2-doctor boombox                   # boombox host cross-check
dhis2-doctor                           # full cross-check (includes boombox when applicable)
dhis2-db status                        # local postgresql status
dhis2-instance restart hmis
dhis2-backup create hmis               # local pg_dump
dhis2-upgrade run hmis --to 2.43.2 \
    --backup-before-migration --verify-backup --monitor-migrations
dhis2-logs hmis -f
```

## Day-two: adding another instance

```bash
dhis2-inventory add-instance training \
    ansible_host=127.0.0.1 database_host=127.0.0.1 \
    dhis2_version=2.42 fqdn=training.example.org
dhis2-deploy apply --only instance
```

The two instances share:
- one PostgreSQL cluster
- one Tomcat process
- one nginx

That is OK for workshop + small single-site. For real isolation
across instances, use LXD.

## Migrating to LXD later (Phase 4)

If you outgrow boombox (performance ceiling, multi-tenant need,
upgrade to HA), a dedicated migration subcommand is planned:

```bash
dhis2-deploy migrate boombox-to-lxd    # Phase 4 - not yet shipped
```

Until Phase 4 lands, the manual migration path is:
1. `dhis2-backup create <instance> --format custom --verify`
2. Provision a new host or wipe this one.
3. `dhis2-deploy init --architecture lxd` on the new host.
4. `dhis2-deploy apply`.
5. `dhis2-restore database --backup <path> --instance <inst>
   --drop-existing --create-db --reassign-owner --verify`.

Full runbook will ship with Phase 4.

## No-regression contract

- Role runs ONLY when `dhis2_architecture=boombox`. Zero
  behaviour change for existing LXD / distributed / hybrid
  deployments.
- The `boombox` role only sets facts — no packages installed, no
  services started by this role.
- `dhis2-cluster`, `dhis2-cluster topology --check`, and every
  other HA command continue to refuse to run with HA disabled;
  the `dhis2_ha=true` + boombox preflight refuses the deploy at
  the correct layer.

## See also

- [docs/vital-enhancements/boombox-plan.md](./vital-enhancements/boombox-plan.md) — design decisions
- [docs/Deployment-Architectures.md](./Deployment-Architectures.md) — architecture overview
- [docs/CLI-WAL-Operations.md](./CLI-WAL-Operations.md) — WAL compliance (applies here too)
