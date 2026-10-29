# dhis2-upgrade — controlled DHIS2 upgrades

The upgrade workflow implements sections 18, 57.9, and 73–80 of the
implementation requirements. It is additive — `dhis2_version` /
`dhis2_auto_upgrade` behavior in the existing `create-instance` role is
preserved.

## Database upgrade policy

`deploy/roles/create-instance/defaults/main/main.yml` sets:

```yaml
dhis2_database_upgrade_mode: detect
```

Values and meaning:

| Mode    | Behavior |
| ------- | -------- |
| `refuse`  | Never let a mismatched schema start — stop before WAR activation. |
| `detect`  | Inspect, report, and only migrate when an explicit upgrade command is used. |
| `prompt`  | Detect and request explicit operator approval. |
| `auto`    | Full controlled workflow (backup → stage → migrate → verify). |
| `force`   | Break-glass; requires `--yes` + ongoing backup unless disabled. |

## Workflow stages

```bash
dhis2-upgrade check hmis
dhis2-upgrade plan  hmis --to 2.43.2
dhis2-upgrade stage hmis --to 2.43.2       # download + checksum only
dhis2-upgrade run   hmis --to 2.43.2 \
     --backup-before-migration \
     --verify-backup \
     --monitor-migrations
dhis2-upgrade verify hmis
dhis2-upgrade rollback hmis                # WAR rollback (DB migrations NOT reverted)
```

A full DB rollback requires a verified pre-upgrade backup and
`dhis2-restore database --backup PATH --drop-existing --create-db`.

## No-regression guarantees

- Attaching an old DHIS2 database (e.g. via
  `dhis2-instance database attach`) does NOT trigger an uncontrolled
  Flyway migration — policy defaults to `detect`.
- Existing database passwords are preserved
  (`dhis2_preserve_database_credentials: true`).
- Unknown source lineage blocks automatic migration.
- A failed migration never reports deployment success — the CLI
  surfaces the Ansible non-zero exit code and backup path.
- Unrelated databases on the same PostgreSQL host are untouched.
