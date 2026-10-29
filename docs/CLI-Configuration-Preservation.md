# dhis.conf and PostgreSQL configuration preservation

Routine redeployment of a healthy DHIS2 instance must not alter the
local `dhis.conf` or regenerate the database password. The CLI provides
explicit controls, and the `create-instance` Ansible role implements
them.

## Role variable

`deploy/roles/create-instance/defaults/main/main.yml` exposes:

```yaml
# dhis2_conf_mode: preserve | merge | replace
# Default (unset): preserve on existing installs; replace on first-time.
dhis2_preserve_database_credentials: true
dhis2_database_upgrade_mode: detect
dhis2_allow_db_migrations: false
```

The role (`tasks/tomcat-setup.yml`) detects an existing
`/opt/dhis2/dhis.conf` and picks the correct branch:

| Mode | Behavior |
| ---- | -------- |
| `preserve` | Leave existing file untouched. Report mode. No database password regeneration. |
| `merge` | Backup existing file, render candidate, add only *new* keys. Existing values win. |
| `replace` | Backup existing file, re-render fully from template (legacy behavior). |

## CLI

```bash
dhis2-deploy apply --instance hmis --preserve-dhis-conf   # default on existing installs
dhis2-deploy apply --instance hmis --merge-dhis-conf
dhis2-deploy apply --instance hmis --replace-dhis-conf --yes

dhis2-instance config show hmis       # redacted
dhis2-instance config backup hmis
dhis2-instance config preserve hmis
dhis2-instance config merge hmis
dhis2-instance config replace hmis
```

## Guarantees — scenarios E1/E2/E3 of the requirements document

- Re-running deployment with preservation keeps `connection.password`,
  `connection.username`, `encryption.password`, and custom properties.
- Merge mode never regenerates `connection.password`; existing values
  win over template defaults.
- Replace mode always creates a timestamped backup first and (in the
  CLI path) requires `--yes`.
- `connection-only` deployment with `--skip-war-deploy` does NOT delete
  or re-extract the running webapp.
