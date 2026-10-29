# dhis2-* command reference

The `dhis2-*` CLI is a thin orchestration layer over the existing Ansible
roles. It does not replace them — it standardizes operator-facing
commands, preflight validation, lifecycle operations, safety gates, and
machine-readable output.

Every documented workflow in `README.md` still works. `deploy.sh`,
`ansible-playbook deploy/dhis2.yml`, inventory tags, and connection
semantics are preserved. See `docs/Compatibility.md`.

## Installation

```bash
sudo ./install.sh                 # install under /opt/dhis2-server-tools
dhis2-deploy --version            # verify
sudo ./install.sh --uninstall     # remove symlinks (keeps data)
```

## Common options

Supported wherever applicable:

```
--inventory PATH         Explicit inventory path
--environment NAME       Named environment (/etc/dhis2-server-tools/environments/NAME)
--limit HOST_OR_GROUP    Ansible --limit
--instance NAME          Scope operation to a single DHIS2 instance
--host NAME              Scope operation to a host
--user USER              Remote SSH user
--connection lxd|ssh     Override connection selection
--check                  Non-destructive planning
--diff                   Show diffs
--verbose / --quiet
--yes                    Non-interactive confirmation
--json                   Machine-readable output (human logs on stderr)
--no-color
--help / --version
```

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | success |
| 1 | generic failure |
| 2 | invalid arguments |
| 3 | preflight/validation failure |
| 4 | connectivity failure |
| 5 | Ansible execution failure |
| 6 | health-check failure |
| 7 | partial success — operator attention required |
| 8 | safety check prevented destructive action |
| 9 | concurrent operation / lock conflict |

## Commands

| Command | Purpose |
| ------- | ------- |
| `dhis2-status` | fast environment overview |
| `dhis2-deploy` | preflight, plan, apply, verify, snapshot, history |
| `dhis2-host` | bootstrap, SSH, sudo, services, resources, LXD |
| `dhis2-inventory` | inspect, validate, lint, safely mutate |
| `dhis2-instance` | lifecycle, config, war, endpoint, maintenance |
| `dhis2-db` | status, activity, locks, tuning, config, HBA |
| `dhis2-backup` | create, verify, manifest, retention |
| `dhis2-restore` | plan, restore, clone, verify |
| `dhis2-upgrade` | releases, compatibility, run, resume, rollback |
| `dhis2-proxy` | routes, config, test, reload |
| `dhis2-tls` | inspect, verify, issue, install, renew |
| `dhis2-monitor` | status, install, targets, exporters |
| `dhis2-logs` | query, follow, bundle |
| `dhis2-doctor` | cross-stack diagnostics |
| `dhis2-security` | audit, exposure, permissions |
| `dhis2-vpn` | WireGuard peers, routes |
| `dhis2-doris` | FE/BE status, catalogs |
| `dhis2-integration` | list, status, install, remove |
| `dhis2-vault` | init, edit, view, references |

Each command exposes `--help` with full usage. See the per-topic docs
under `docs/CLI-*.md`.
