# Boombox — all-in-one single-server architecture (no LXD)

**Status:** draft plan (not yet implemented)
**Scope:** First-class support for running every DHIS2 service
directly on a single Ubuntu host, without LXD containers.

## 1. What "boombox" is

A **single-host deployment** that runs:
- PostgreSQL (on the host, systemd-managed)
- Tomcat + the DHIS2 WAR (on the host, systemd-managed)
- Nginx (on the host, systemd-managed, binding :80 and :443)
- Monitoring (Munin by default; Prometheus/Grafana optional)
- Optional: WireGuard, integration services, Doris (lab-only on
  boombox because Doris needs real memory headroom)

Everything binds to `127.0.0.1` except the single public port
pair (`:80 → :443` redirect). No container runtime. No bridged
networking. `ansible_connection=local` on the single inventory
host.

## 2. When to pick boombox

- Workshop / demo laptops.
- Conference bake-off installs.
- Small single-site production (one country office, one clinic,
  one NGO).
- Operators who prefer OS-native systemd units to LXD containers.

## 3. When NOT to pick boombox

- **HA.** A single host has one failure domain. The HA preflight
  will REFUSE `dhis2_ha=true` with `dhis2_architecture=boombox`.
- **Multi-tenant isolation.** Three DHIS2 instances on the same
  boombox share one PG, one Tomcat process space, one nginx.
  Blast radius of any one instance's bad migration includes the
  others. Use LXD or distributed SSH for isolation.
- **Mixed PG + non-DHIS2 workloads.** Boombox tunes PG for DHIS2;
  co-locating another app's DB is possible but tunings will
  surprise.

## 4. Locked decisions (from plan review)

| # | Decision | Consequence |
|---|----------|-------------|
| 1 | **No minimum host size enforced.** Preflight *warns* on <4 GB RAM, <2 CPU, <50 GB disk, but does not refuse. | Operator can run on a 2 GB VM for a demo. Documentation explicitly flags that this is not a production configuration. |
| 2 | **Two modes, selected at init.** `dhis2-deploy init --architecture boombox` prompts `--mode production\|workshop`. Role templates both; `boombox_mode` inventory variable selects. | Production: fqdn required, Let's Encrypt default, hardened preflight. Workshop: fqdn optional, self-signed default, more warnings and fewer failures, faster setup. |
| 3 | **Boombox refuses to run if LXD is installed.** Preflight checks for the `lxc` binary and any existing LXD containers. | Prevents operator footgun ("I set up LXD last week, now I want to try boombox, oh no why did my containers die"). Message explicitly recommends `dhis2-architecture=lxd` or clean uninstall. |
| 4 | **Migration tooling: `dhis2-deploy migrate boombox-to-lxd`** — automated migration subcommand. | Scoped as a follow-up iteration (large). Phase 4 of this plan. |

## 5. Target architecture

```
                    public (fqdn, :443)
                            │
                            ▼
                     +---------------+
                     |     nginx     |
                     | (host service)|
                     +-------+-------+
                             │
                             │ 127.0.0.1:8080
                             ▼
                     +---------------+
                     |    tomcat     |
                     |  + DHIS2 WAR  |
                     +-------+-------+
                             │
                             │ 127.0.0.1:5432
                             ▼
                     +---------------+
                     |  PostgreSQL   |
                     |   + PostGIS   |
                     +---------------+
                             ▲
                             │ /var/backups/dhis2
                             │
                     +---------------+
                     |  dhis2-backup |
                     |   cron entry  |
                     +---------------+

                     +---------------+
                     | Munin / Grafana|
                     |   (host, 4949) |
                     +---------------+
```

Firewall:
- `80/tcp` → redirects to 443
- `443/tcp` → nginx TLS termination
- `22/tcp` → operator SSH only
- Everything else: default-deny

Co-located but **not exposed to the public**:
- `5432/tcp` postgresql, bound 127.0.0.1
- `8080/tcp` tomcat, bound 127.0.0.1
- `4949/tcp` munin-node
- `9090/tcp` prometheus (if installed), bound 127.0.0.1
- `6379/tcp` redis (if installed), bound 127.0.0.1

## 6. Inventory shape

```ini
# deploy/inventory/hosts  (boombox)
#
# A single host carries every role group. ansible_connection=local
# so we run against this host from itself.
#

127.0.0.1 ansible_connection=local

[web]
127.0.0.1

[databases]
127.0.0.1

[instances]
hmis ansible_host=127.0.0.1 database_host=127.0.0.1 dhis2_version=2.43 fqdn=hmis.example.org

[monitoring]
127.0.0.1

[backup_servers]
127.0.0.1

[all:vars]
dhis2_architecture=boombox
boombox_mode=production            # or workshop
fqdn=hmis.example.org              # required in production mode
email=ops@example.org              # required for Let's Encrypt
timezone=Africa/Nairobi
```

`dhis2-deploy init --architecture boombox` generates this verbatim
with the operator's answers substituted in.

## 7. New / changed files

### New

```
docs/Boombox.md                                              # operator guide
docs/Boombox-to-LXD-Migration.md                             # Phase 4 runbook (manual steps until Phase 4 ships the command)
deploy/roles/boombox/                                        # tuning + preflight
  defaults/main.yml
  tasks/main.yml                                             # fact-based tunings
  tasks/preflight.yml                                        # LXD-absence check + resource warnings + port availability
  tasks/mode-production.yml
  tasks/mode-workshop.yml
```

### Changed

- `bin/dhis2-deploy` — `architectures` lists `boombox` as
  SUPPORTED; `init --architecture boombox` added with `--mode`
  prompt; `preflight` branches on `dhis2_architecture`.
- `deploy/dhis2.yml` — includes the boombox role when
  `dhis2_architecture=boombox`.
- `deploy/roles/create-instance/defaults/main/main.yml` — honours
  `boombox_mode` for Let's Encrypt / self-signed defaults.
- `deploy/inventory/hosts.template` — gains a commented
  `[boombox]` quick-start block.

## 8. CLI surface

```
dhis2-deploy init --architecture boombox --mode production|workshop
dhis2-deploy architectures                               # 'boombox' listed as SUPPORTED
dhis2-deploy preflight                                   # boombox-specific checks when boombox is selected
dhis2-doctor boombox                                     # new sub-check: service co-tenancy, port conflicts, resource budget
dhis2-deploy migrate boombox-to-lxd [--yes]              # Phase 4 only; refuses to run until implemented
```

Every existing command (`dhis2-status`, `dhis2-instance`,
`dhis2-db`, `dhis2-backup`, `dhis2-upgrade`, `dhis2-logs`,
`dhis2-doctor`, `dhis2-proxy`, `dhis2-tls`, `dhis2-monitor`,
`dhis2-security`, `dhis2-vault`) continues to work unchanged on
boombox because they all route through Ansible against the
inventory, which just happens to point at `127.0.0.1 local`.

## 9. Tunings computed from facts

The `boombox` role computes defaults from `ansible_facts` on the
single host and renders them BEFORE the postgres and
create-instance roles run:

| Setting | Formula | Rationale |
|---------|---------|-----------|
| `pg_shared_buffers` | 25 % of `ansible_memtotal_mb` | PG rule of thumb |
| `pg_effective_cache_size` | 60 % of `ansible_memtotal_mb` | PG planner hint |
| `pg_work_mem` | `max(4 MiB, (memtotal_mb * 0.05) / max_connections)` | Avoid OOM under high concurrency |
| `pg_maintenance_work_mem` | 10 % of `ansible_memtotal_mb`, min 256 MiB, max 2 GiB | VACUUM / CREATE INDEX speed |
| `pg_max_connections` | `max(100, 20 * nproc)` | Reasonable headroom |
| `heap_memory_size` (Tomcat JVM) | `memtotal_mb * 0.40` (capped at 32 GB) | Leave room for PG + OS cache + nginx |
| `pg_max_wal_size` | `min(16 GB, 10 % of filesystem free)` | Compliance-safe |
| `pg_max_slot_wal_keep_size` | 2× `pg_max_wal_size` | Compliance (ADR WAL-01) |
| nginx `worker_processes` | `auto` | Nginx picks nproc |
| nginx `worker_connections` | 2048 | Reasonable for a demo + small prod |

Every value is **overridable** per host via inventory. The role
only sets the value if the operator has not already set it.

## 10. Modes

### Production mode (`boombox_mode=production`)

- `fqdn` is required (preflight fails without it).
- `email` is required (preflight fails without it).
- TLS: Let's Encrypt by default (`TLS_TYPE=letsencrypt`).
- Nginx HSTS + `security_headers.conf` enforced.
- UFW enabled with 80/443 allow + default-deny.
- `dhis2-doctor` runs in strict mode (every WARN becomes a FAIL on
  the boombox check).

### Workshop mode (`boombox_mode=workshop`)

- `fqdn` optional; defaults to the hostname.
- `email` optional (no Let's Encrypt in workshop mode).
- TLS: self-signed by default (`TLS_TYPE=selfsigned`).
- UFW allowed to be disabled with a warning (lab networks).
- `dhis2-doctor boombox` treats resource/perf findings as WARN,
  not FAIL.
- Documented in `docs/Boombox.md` as "do not expose a workshop
  box to the public internet".

## 11. Preflight (boombox-specific)

Runs when `dhis2_architecture=boombox` is in the inventory. All of
these are checks ON TOP OF the existing cross-architecture
preflight:

| # | Check | Mode: production | Mode: workshop |
|---|-------|------------------|----------------|
| 1 | `lxc` binary absent AND no `lxc list` containers | **HARD FAIL** (locked decision 3) | HARD FAIL |
| 2 | `fqdn` set | HARD FAIL | warn |
| 3 | `email` set | HARD FAIL | warn |
| 4 | RAM ≥ 4 GB | warn (locked decision 1) | warn |
| 5 | CPU ≥ 2 cores | warn | warn |
| 6 | Root FS free ≥ 50 GB | warn | warn |
| 7 | `/dev/shm` not nested too small | warn | warn |
| 8 | `ufw` installed + status | HARD FAIL (expected enabled) | warn |
| 9 | Port 80 free (no competing nginx/apache) | HARD FAIL | HARD FAIL |
| 10 | Port 443 free | HARD FAIL | HARD FAIL |
| 11 | Port 5432 free (no competing postgresql install) | HARD FAIL | HARD FAIL |
| 12 | Port 8080 free | HARD FAIL | HARD FAIL |
| 13 | `dhis2_ha` is not true | HARD FAIL (section 15b: one host is not HA) | HARD FAIL |
| 14 | DNS: `fqdn` resolves to this host's IP | warn | — |
| 15 | Time sync + timezone set | warn | warn |

## 12. Phased delivery

### Phase 1 — Boombox architecture scaffold

- `dhis2-deploy architectures` lists `boombox` as SUPPORTED.
- `dhis2-deploy init --architecture boombox` writes an inventory;
  prompts for `--mode production|workshop` when stdin is a tty,
  otherwise reads `--mode` from argv.
- New `boombox` role with `preflight.yml` + `tasks/main.yml`
  (fact-based tunings).
- `deploy/dhis2.yml` conditionally includes the role when
  `dhis2_architecture=boombox`.

### Phase 2 — Preflight + doctor

- Preflight branches on `dhis2_architecture` and runs all 15
  boombox-specific checks.
- `dhis2-doctor boombox` cross-check (co-tenancy, port use,
  resource budget).
- Regression scenarios BW–BZ.

### Phase 3 — Docs

- `docs/Boombox.md` (operator guide + runbook).
- Update `README.md` architecture table.
- Update `docs/Deployment-Architectures.md`.

### Phase 4 — Migration tooling (own iteration)

- `dhis2-deploy migrate boombox-to-lxd`:
  1. `dhis2-backup create <instance> --format custom --verify`
  2. `dhis2-doctor` (snapshot operational state)
  3. `dhis2-instance stop <instance>`
  4. Stop services on the host (`systemctl stop tomcat9 postgresql nginx`)
  5. Install LXD (`apt install lxd lxd-utils; lxd init`)
  6. Lay out containers per the LXD architecture
  7. Restore DB + files into the containerised PG + Tomcat
  8. Re-point `dhis.conf` + nginx upstream
  9. Verify end-to-end

  This is the dangerous piece. Shipping it is **its own
  iteration**: dedicated runbook, dedicated preflight ("have you
  backed up?"), audit trail, --dry-run mode.

## 13. Acceptance criteria

### Phase 1

- [ ] `dhis2-deploy architectures` prints `boombox / SUPPORTED`.
- [ ] `dhis2-deploy init --architecture boombox --mode production`
      writes a working inventory into a dev VM.
- [ ] `dhis2-deploy apply` end-to-end on a 4 GB Ubuntu 22.04 VM
      results in a reachable DHIS2 at `https://<fqdn>/<instance>`.
- [ ] No regression on the 89 existing scenarios.

### Phase 2

- [ ] `dhis2-deploy preflight` refuses when `lxc` is installed.
- [ ] `dhis2-deploy preflight` refuses when `dhis2_ha=true`
      alongside `dhis2_architecture=boombox`.
- [ ] `dhis2-doctor boombox` reports resource budget vs usage.

### Phase 3

- [ ] `docs/Boombox.md` end-to-end from fresh Ubuntu to running
      DHIS2 in <15 commands.
- [ ] README table updated.

### Phase 4

- [ ] `dhis2-deploy migrate boombox-to-lxd` runs in `--dry-run`.
- [ ] A real migration round-trip documented in a dedicated
      runbook.
- [ ] Automatic rollback on failure of any single step.

## 14. Risk register

| Risk | Mitigation |
|------|------------|
| Operator deploys boombox on a shared host that already has postgresql/nginx | Phase 2 preflight refuses the deploy (ports 80/443/5432 free). |
| Workshop boombox exposed to the public with weak credentials | Workshop mode documents "do not expose publicly". Preflight warns when both workshop mode + public FQDN are set. |
| Boombox tunings crowd out a non-DHIS2 workload on the host | Documented: boombox owns the host. Role flags any non-DHIS2 service it detects. |
| Operator wants HA later and painted themselves into a boombox | Migration tool (Phase 4). Documented in docs/Boombox.md. |
| Resource under-provisioning (<4 GB RAM) with heavy use | Warnings in preflight + `dhis2-doctor boombox`; not a hard failure (decision 1). |

## 15. Explicitly out of scope

- Running Doris on boombox (works but needs 16+ GB RAM; separate
  runbook if demand materialises).
- Running multiple instances on boombox *with resource isolation*
  (operator should use LXD).
- A boombox variant for RHEL / Fedora (project targets Ubuntu).
- Automatic re-provisioning (install.sh is operator-run, not an
  installer that fetches itself).
