# Migrating to the dhis2-* CLI

The CLI is a drop-in orchestration layer; migration is optional.

## No-op path

Existing workflows keep working with no changes:

```bash
sudo ./deploy/deploy.sh
ansible-playbook deploy/dhis2.yml --tags postgresql-install
ansible-playbook deploy/dhis2.yml --tags create-instance --limit hmis
```

## Opting in

Install:

```bash
sudo ./install.sh
dhis2-deploy --version
dhis2-status
dhis2-doctor --quick
```

### Equivalences

| Previously | CLI equivalent |
| ---------- | -------------- |
| `sudo ./deploy.sh` | `dhis2-deploy apply` |
| `ansible-playbook dhis2.yml --tags postgresql-install` | `dhis2-deploy apply --only database` |
| `ansible-playbook dhis2.yml --tags proxy-install` | `dhis2-deploy apply --only proxy` |
| `ansible-playbook dhis2.yml --tags create-instance --limit hmis` | `dhis2-instance create hmis ...` |
| `ansible-playbook dhis2.yml --tags deploy-war --limit hmis` | `dhis2-instance war deploy hmis --version X` |
| `ansible-playbook dhis2.yml --tags backup-script` | `dhis2-backup schedule hmis` |
| `./create-intance.sh` | `dhis2-instance create ...` (the typo wrapper is kept) |

## Preserving dhis.conf

The most important operational safety improvement — see
`CLI-Configuration-Preservation.md`.

For routine redeployment of a healthy production instance:

```bash
dhis2-deploy apply --instance hmis --preserve-dhis-conf --skip-war-deploy
```

## Legacy scripts

The following remain functional:

- `deploy/deploy.sh`
- `deploy/create-intance.sh`
- `deploy/postgresql-install.sh`
- `deploy/proxy-conf.sh`
- `deploy/install-ansible.sh`
