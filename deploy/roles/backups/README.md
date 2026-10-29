# backups

Installs the DHIS2 backup script and schedule on hosts in the
`[databases]` group.

## Responsibilities

- Install the backup wrapper script (uses `pg_dump --format=custom`
  by default, writes under `/var/backups/dhis2/`).
- Render `.pgpass` and (optionally) `s3cfg` so the script can push
  dumps to an S3-compatible bucket.
- Install a cron entry on the database host.
- Preserve any operator-maintained backup configuration between runs.

## Dispatch

`tasks/main.yml` chooses `tasks/lxd.yml` or `tasks/ssh.yml` from each
database host's `ansible_connection`.

## Variables

Common overrides (see `defaults/main.yml` and
[docs/Variables.md](../../../docs/Variables.md)):

| Variable | Purpose |
| -------- | ------- |
| `backup_cron_schedule` | cron expression for the scheduled dump |
| `s3_bucket`, `s3_access_key`, `s3_secret_key` | push to S3 if set |

Secret-containing templates (`.pgpass.j2`, `s3cfg.j2`) are written
with `0600`.

## Tags

- `backup-script`

## CLI integration

- `dhis2-backup create INSTANCE [--format custom|plain|plain-gzip|tar|directory]`
- `dhis2-backup verify PATH` — gzip integrity, `pg_restore -l`,
  manifest presence.
- `dhis2-backup test PATH` — restores into a disposable temp
  database.
- `dhis2-backup list | show | manifest | checksum`
- `dhis2-backup prune --keep N` — never removes the newest valid
  backup (section 16.3).
- `dhis2-backup schedule INSTANCE --cron "..."` and
  `dhis2-backup unschedule`.
- `dhis2-backup export PATH --to s3://…`
- `dhis2-backup config INSTANCE` — read-only, redacted.

## Manifest format

Every CLI-created backup writes a sibling `.manifest.json` containing
non-secret metadata (instance, database, PG version, format, size,
SHA-256, timestamp, tool version). This is the input to
`dhis2-restore plan` (section 57.7).

## No-regression notes

- The existing scheduled dumps continue to run unchanged when a
  deployment is re-applied.
- Pruning refuses to delete the newest valid backup even with
  `--yes`.
- Checksum-only verification is **not** labelled as a full restore
  test; `dhis2-backup test` is distinct.
