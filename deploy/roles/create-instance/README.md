# create-instance

Provisions and reconciles a single DHIS2 application instance:
Tomcat, Java, the DHIS2 WAR, `dhis.conf`, the proxy route, instance
database and role, Glowroot APM, Munin / Prometheus hookup, and the
nginx / apache2 / openresty location block.

## Responsibilities

- Resolve the target DHIS2 release (`dhis2-releases.yml`) from the
  inventory variables `dhis2_version` and `dhis2_war_file`.
- Create or reuse the LXD container (via `lxd.yml`) or validate an
  SSH-managed host (`ssh.yml`).
- Lay down Tomcat and Java (`tomcat-setup.yml`).
- Manage `dhis.conf` with explicit mode selection: **preserve**,
  **merge**, or **replace**. See
  [docs/CLI-Configuration-Preservation.md](../../../docs/CLI-Configuration-Preservation.md).
- Create the instance database and role (`postgresql-db.yml`), only
  when `[databases]` group membership applies.
- Deploy the WAR (`deploy-war.yml`), optionally gated by
  `dhis2_skip_war_deploy` so a configuration-only re-run cannot
  re-extract the running webapp.
- Render the proxy location block (`proxy/<engine>.yml`), including
  a maintenance-mode `return 503` when
  `/etc/dhis2-server-tools/maint/<instance>` is present.
- Wire up TLS: `tls/letsencrypt.yml`, `tls/customssl.yml`,
  `tls/selfsigned.yml`.
- Install Glowroot APM when `app_monitoring: glowroot`.
- Monitor Flyway migrations (`monitor-migrations.yml`) when the
  upgrade workflow sets `dhis2_monitor_migrations: true`.

## Key variables

See `defaults/main/main.yml` for the full list and defaults.

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `dhis2_version` | `2.42` | Target application version |
| `dhis2_war_file` | unset | Explicit WAR URL / path overrides version lookup |
| `JAVA_VERSION` | `17` | JVM major version |
| `postgresql_version` | `16` | Required PG major version |
| `database_host` | `postgres` | Inventory host serving this instance's DB |
| `app_monitoring` | `glowroot` | APM backend |
| `dhis2_conf_mode` | unset ⇒ `preserve` on existing installs; `replace` on fresh installs | How to handle `dhis.conf` |
| `dhis2_preserve_database_credentials` | `true` | Never rotate the DB password implicitly |
| `dhis2_database_upgrade_mode` | `detect` | `refuse` / `detect` / `prompt` / `auto` / `force` |
| `dhis2_allow_db_migrations` | `false` | Explicit permission for Flyway migrations during startup |
| `dhis2_monitor_migrations` | `false` | Watch catalina.out for Flyway completion / failure |
| `dhis2_migration_timeout` | `1800` | Seconds before failing the migration-monitor task |
| `dhis2_skip_war_deploy` | `false` | Skip the WAR deployment step |
| `dhis2_skip_restart` | `false` | Suppress Tomcat restarts for this run |

## Tags

- `create-instance`
- `set-dhis2-url`
- `deploy-war`
- `proxy-conf`
- `tomcat-munin-monitoring`
- `prometheus-connect`
- `monitor-migrations`
- `delete-instance`

## CLI integration

- `dhis2-instance list | show | create | delete | start | stop |
  restart | reload | status | health | logs`
- `dhis2-instance version | system-info | endpoint check | jvm status
  | jvm memory | threads summary | resources`
- `dhis2-instance config show | validate | diff | backup | preserve |
  merge | replace`
- `dhis2-instance war status | deploy | verify | backup | rollback`
- `dhis2-instance database inspect | attach --upgrade-mode …`
- `dhis2-instance maintenance status | enable | disable`

## No-regression guarantees

- An existing `/opt/dhis2/dhis.conf` is **never** overwritten by a
  re-run under default or `preserve` mode (section 11.5.1, scenario
  E1).
- Merge mode is property-aware and keeps existing values on conflict
  (scenario E2).
- Replace mode creates a timestamped backup before writing (scenario
  E3) and in the CLI path requires explicit `--yes`.
- The WAR deployment step is skipped when `dhis2_skip_war_deploy:
  true`, so a configuration-only run cannot destroy the running
  webapp (scenario I).
- Flyway failures are detected and surfaced as task failures, so an
  interrupted or failing upgrade can **never** be reported as success
  (scenarios P and X).
- Deleting one instance's inventory entry and re-running
  `--only proxy-conf` preserves routes for every other instance
  (scenario K).
