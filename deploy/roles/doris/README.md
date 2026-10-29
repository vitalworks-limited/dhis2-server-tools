# doris

Provisions a single-node Apache Doris FE+BE (analytics database backend for
DHIS2) inside an LXD container, and wires it up to the paired PostgreSQL
instance and DHIS2 instance.

## Requirements

LXD only — hosts in `[apache_doris]` with `ansible_connection=ssh` cause this
role to fail with a clear error. Requires `community.general`,
`community.mysql`, `community.postgresql`, `ansible.posix`, and
`ansible.utils` collections (installed by `deploy/deploy.sh`).

## Role Variables

See `defaults/main.yml` for `doris_version`, `doris_user`, `doris_home`,
`java_home`, `doris_download_url`. Per-host inventory variables (set in
`deploy/inventory/hosts`, documented in `hosts.template`):

- `apache_doris_db` (on an `[instances]` host) — name of the `[apache_doris]`
  host this instance's analytics queries should use. Required to opt in.
- `apache_doris_db_user` / `apache_doris_db_password` — optional, default to
  `doris_user` and an auto-generated password stored under
  `/opt/ansible/secrets/apache_doris_db_password`.
- `lxd_memory_limit`, `doris_fe_heap_size`, `doris_be_mem_limit` — optional
  memory tuning, unset = no limit.

## How it's invoked

Not run directly — included from `deploy/dhis2.yml` as `- role: doris`,
gated on `groups['apache_doris'] | length > 0`, after `postgres` and before
`create-instance`.

## Tags

- `doris-install`

## CLI integration

- `dhis2-doris status | health | version | resources` — reports the
  configured host, FE / BE process state, **and** FE :8030 /
  BE :8040 HTTP `/api/health` endpoints so the health signal
  distinguishes "process running" from "answering requests".
- `dhis2-doris frontend | backend` — service status plus
  HTTP health probe, with secrets redacted from the response body.
- `dhis2-doris databases | catalogs` — expose SQL state via the
  MySQL protocol (9030) with redaction.
- `dhis2-doris connect-postgres` — reminder that a JDBC catalog in
  Doris is an **external federated bridge**, not a materialised copy
  of the source PostgreSQL data (section 57.18).
- `dhis2-doris connectivity | logs` — listener and log inspection.

## No-regression notes

- SSH-based Doris deployment is **not** production-ready; the role
  fails fast when `ansible_connection=ssh` is used on an
  `[apache_doris]` host, and the CLI reports the limitation rather
  than attempting unsupported behaviour.
- `dhis2-host lxd snapshot` prints an explicit warning that an LXD
  container snapshot is **not** a validated database backup
  (section 57.3 and scenario S).
