# pre-install

Prepares the Ansible controller / deployment host before any role runs
against managed nodes.

## Responsibilities

- Create and secure `/opt/ansible/` and `/opt/ansible/secrets/` with
  `0700` and the invoking operator as owner.
- Generate per-instance database passwords when they do not already
  exist (tag `db_password_generate`), writing them under
  `/opt/ansible/secrets/`. Existing files are preserved — passwords
  are never rotated by this role (section 11.5.1 of the implementation
  requirements doc: "Database password stability").
- Install Debian prerequisites (`Debian.yml`) or macOS prerequisites
  (`Darwin.yml`) on the controller.
- Optionally install a Grafana client on the controller when
  `server_monitoring` is set.
- Configure firewall rules on the controller.

## When it runs

Automatically from `deploy/dhis2.yml` as the first play against
`127.0.0.1`.

## Tags

- `pre-install`
- `db_password_generate`

## No-regression notes

- Password files under `/opt/ansible/secrets/` are **never overwritten**
  if they already exist. The CLI's `--preserve-dhis-conf` depends on
  this behaviour. See
  [docs/CLI-Configuration-Preservation.md](../../../docs/CLI-Configuration-Preservation.md).
- The `dhis2-vault` CLI exposes `init`, `scan`, `rotate`, and
  `references` operations that interact with this directory.
