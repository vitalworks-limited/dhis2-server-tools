# integration

Provisions integration services on hosts in the `[integration]` group
and lets those services reach the DHIS2 instance over the local
firewall.

## Responsibilities

- Install LXD / SSH prerequisites on the integration host.
- Deploy any configured JAR artifacts (`jar-file-deploy.yml`).
- Open firewall rules on the DHIS2 instance so the integration host
  can reach the application port.

## Tags

- `integration-install`
- `integration-restart`

## CLI integration

- `dhis2-integration list | status | install | restart | remove`
- `dhis2-integration logs | health | config | enable | disable | test`

## No-regression notes

- Removing an integration host **does not** delete application data
  or credentials unless explicitly requested (section 57.19).
- Integration services expose common metadata (service name, listen
  port, target DHIS2 instance, config path, health check, log source,
  secret references) through the CLI without displaying secret
  values.
