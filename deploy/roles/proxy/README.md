# proxy

Installs the chosen reverse proxy on hosts in the `[web]` inventory
group.

## Supported engines

| Engine | Install task | Status |
| ------ | ------------ | ------ |
| `nginx` | `nginx-install.yml` | SUPPORTED (default) |
| `apache2` | `apache2-install.yml` | SUPPORTED |
| `openresty` | `openresty-install.yml` | SUPPORTED |

Set the inventory variable `proxy=nginx|apache2|openresty`.

## Responsibilities

- Install the proxy and its dependencies.
- Serve the DHIS2 instance route(s) rendered by the `create-instance`
  role (`create-instance/templates/<engine>/`).
- Serve Munin (`munin.j2`) and, when configured, Prometheus / Grafana
  (`prometheus.j2`, `grafana.j2`).
- Enforce basic-auth in front of Munin when `server_monitoring: munin`.

## Dispatch

`tasks/main.yml` includes `{{ ansible_connection }}.yml` first (LXD
container creation or SSH prerequisite checks), then
`{{ proxy }}-install.yml`, then the engine-specific config generation
is handled by the `create-instance` role's `proxy/<engine>.yml`.

## Tags

- `proxy-install` — install the engine
- `proxy-conf` — rebuild config from inventory
- `nginx-perf-log` — enable the performance log
- `securing-munin` — basic auth

## CLI integration

- `dhis2-proxy status | show | config | test | reload | restart` —
  **`test` must pass before any reload or restart**; the CLI aborts
  the operation if the configuration is invalid, so a broken
  rendering never replaces a working one (section 57.10).
- `dhis2-proxy routes | upstream | listeners | certificates` —
  read-only inspection.
- `dhis2-proxy maintenance enable | disable` — writes
  `/etc/dhis2-server-tools/maint/<instance>` and the Nginx template
  returns HTTP 503 for that instance's location block while
  preserving the original route. Disabling removes the flag file.
- `dhis2-proxy backup | diff` — recovery artifacts and planning.

## No-regression notes

- Last-known-good configuration is preserved across all CLI-driven
  operations (sections 57.10 and scenario N).
- Maintenance mode uses an advisory flag file; no proxy rules are
  deleted or rewritten.
