# Backup and restore

Each DHIS2 backup produced by `dhis2-backup create` is accompanied by
a sibling `.manifest.json` carrying non-secret metadata (instance,
database, PostgreSQL version, format, size, SHA-256, timestamp, tool
version, encryption status). Section 57.7.

## Create

```bash
# Plain custom-format dump (default)
dhis2-backup create hmis

# All supported formats
dhis2-backup create hmis --format custom|plain|plain-gzip|tar|directory

# Encrypted at rest (gap 8)
dhis2-backup create hmis --format custom --encrypt gpg --recipient ops@example.org
```

GPG encryption uses the operator-supplied public key. The plaintext
dump is shredded immediately after encryption; only `.gpg` output
remains on disk. The manifest records `encryption: "gpg"` and the
recipient id so the restore side can decide whether to prompt for a
key.

**Prerequisites for encrypted backups:**

- `gpg` installed on the `[databases]` host (the role will refuse with
  a clear message if it's missing).
- The recipient public key imported into the postgres user's keyring
  on that host. Automate with your existing config-management or
  `apt install gnupg && gpg --import` as part of host bootstrap.

## Verify

```bash
dhis2-backup verify /var/backups/dhis2/hmis-20261029-120000.dump
dhis2-backup verify /var/backups/dhis2/hmis-20261029-120000.dump.gpg
dhis2-backup verify /var/backups/dhis2/hmis-20261029-120000.sql.gz
```

For `.gpg` files, verification runs `gpg --list-packets` (header
integrity) without requiring the private key. A full decrypt+restore
round-trip is `dhis2-backup test`.

## Test (isolated restore)

```bash
dhis2-backup test /var/backups/dhis2/hmis-20261029-120000.dump
```

Creates a disposable database on the DB host, restores into it, runs
a sanity count, and drops it. Does not touch any production DB.

## Restore

```bash
# Plain restore
dhis2-restore database --backup /var/backups/dhis2/hmis-...dump \
    --instance hmis --drop-existing --create-db --reassign-owner --verify

# Encrypted restore (same command - decryption is transparent)
dhis2-restore database --backup /var/backups/dhis2/hmis-...dump.gpg \
    --instance hmis --drop-existing --create-db --reassign-owner --verify
```

For encrypted archives, the CLI decrypts into a `0700` temp directory
on the DB host and shreds the plaintext immediately after use.

## Retention

```bash
dhis2-backup prune --keep 14 --yes
```

Never deletes the newest valid backup; respects the manifest to avoid
touching ad-hoc dumps that someone else placed in the same directory.

## Automation

```bash
dhis2-backup schedule hmis --cron "0 2 * * *"
dhis2-backup unschedule hmis
```

Rotate / retain via the `backups` role's existing cron + logrotate.
The CLI additionally installs `/etc/logrotate.d/dhis2-server-tools`
during `install.sh` so CLI audit logs (`/var/log/dhis2-server-tools/`)
are rotated weekly with 12 weeks retained.

## Integrity when installing a new DHIS2 release

Section 57.9 "Artifact verification". `set-dhis2-url.yml` resolves
`dhis2_url_sha256` from `releases.json` and `deploy-war.yml` passes
it to `ansible.builtin.get_url --checksum=sha256:...`. A truncated
or tampered WAR fails the task — the running application is never
replaced with a bad artifact.

For operator-supplied `dhis2_war_file`, add
`dhis2_war_file_sha256=<hex>` to inventory to opt into the same
integrity check. Without it, the role prints a warning and installs
the WAR unverified (preserves legacy behaviour).
