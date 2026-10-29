# Compatibility and no-regression guarantees

This CLI is additive. The following existing workflows continue to work
unchanged:

- `sudo ./deploy/deploy.sh` — unchanged entry point for existing LXD and
  hybrid deployments.
- `ansible-playbook deploy/dhis2.yml` — direct playbook execution.
- `ansible-playbook deploy/dhis2.yml --tags <tag>` with the existing tag
  names (`postgresql-install`, `proxy-install`, `monitoring`,
  `create-instance`, `alerting`, `backup-script`, `set-dhis2-url`,
  `deploy-war`, `proxy-conf`, `tomcat-munin-monitoring`,
  `prometheus-connect`, `delete-instance`, `doris-install`, …).
- Existing INI inventory format under `deploy/inventory/hosts`.
- `ansible_connection=lxd`, `ansible_connection=ssh`, and per-host
  overrides.
- All existing inventory variables (`database_host`, `dhis2_version`,
  `dhis2_war_file`, `dhis2_auto_upgrade`, `postgresql_version`,
  `server_monitoring`, `wireguard_enabled`, `wireguard_data_plane`,
  `proxy`, `fqdn`, `email`, `timezone`, `create_db`, `java_version`,
  `TLS_TYPE`, …).

The CLI additions:

- Introduce new Ansible variables defaulted so that existing inventories
  behave identically:
  - `dhis2_conf_mode` (default: existing behavior for new installs,
    `preserve` for existing instances when invoked by the CLI).
  - `dhis2_database_upgrade_mode` (default: `detect`).
  - `dhis2_backup_before_migration`, `dhis2_verify_backup`,
    `dhis2_monitor_migrations`, `dhis2_restore_on_failure`.
- Add safety gates (confirmation, locks, atomic writes, redacted diffs)
  around destructive and mutating commands. The underlying Ansible
  behavior is unchanged.
- Leave `create-intance.sh` in place; a correctly spelled `dhis2-instance
  create` is now also available.
