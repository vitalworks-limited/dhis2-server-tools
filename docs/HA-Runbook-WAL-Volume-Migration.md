# Runbook — migrate existing pg_wal to a dedicated volume

WAL Phase 2 lets you put `pg_wal/` on its own block device so a WAL
filesystem-full event cannot kill the data filesystem.

This runbook is for **existing clusters**. For fresh clusters set
`pg_wal_volume=/dev/sdb` before `dhis2-deploy apply` and the role
takes care of everything.

**You will take a short write outage.** Plan for 5–30 minutes of
downtime depending on `pg_wal/` size and target volume throughput.

## Prerequisites

- A spare block device on the DB host (e.g. `/dev/sdb`).
- A verified, recent base backup (we create a fresh one in step 1
  below but defence in depth is cheap).
- Operator access to the DB host (sudo).

## Procedure

```bash
# 1. Fresh pre-change backup
dhis2-backup create <instance> --format custom --verify
dhis2-doctor wal                               # confirm current state

# 2. Stop DHIS2 so writes drain
dhis2-instance stop <instance>

# 3. Checkpoint + stop PostgreSQL cleanly
#    Single-node:
ssh <db-host> 'sudo -u postgres psql -X -c "CHECKPOINT"'
ssh <db-host> 'sudo systemctl stop postgresql'

#    HA (Patroni-managed):
dhis2-cluster pause --yes
dhis2-cluster switchover --to <another-replica> --yes    # if migrating the current primary
# Then on the demoted / idle member:
ssh <db-host> 'sudo systemctl stop patroni'

# 4. Set inventory variables and apply the role
#    inventory:
#      <db-host> ansible_host=...  pg_wal_volume=/dev/sdb  pg_wal_volume_migrate=true
#    If the device already has a filesystem you need to overwrite,
#    also set pg_wal_volume_force=true (confirms the destroy).
dhis2-deploy apply --limit <db-host> --only database --yes

# 5. Verify
dhis2-db wal volume status --host <db-host>    # should show DEDICATED
dhis2-doctor wal

# 6. Start services back up
#    Single-node:
ssh <db-host> 'sudo systemctl start postgresql'
dhis2-instance start <instance>

#    HA:
ssh <db-host> 'sudo systemctl start patroni'
dhis2-cluster resume --yes
# Patroni will rejoin the migrated node as a replica; use
# dhis2-cluster reinit if the timeline diverged for any reason.

# 7. Confirm end-to-end
dhis2-instance health <instance> --retry 20 --interval 10
dhis2-db wal status --host <db-host>
```

## Safety gates the role enforces

The `pg-wal-volume.yml` task refuses to proceed when:

1. The target device already has a filesystem AND
   `pg_wal_volume_force=true` was NOT set.
2. PostgreSQL is RUNNING on the host (checked via
   `systemctl is-active postgresql`).
3. The host has an existing PG cluster AND
   `pg_wal_volume_migrate=true` was NOT set.

Each refusal prints a clear message pointing back at this runbook.

## Rollback

Before step 4 (format + mount), rollback is trivial: unset the
inventory variables and start PG back up.

After step 4 (device formatted, pg_wal is now a mount point):

```bash
# As root on the DB host
systemctl stop postgresql       # or systemctl stop patroni
cp -a /var/lib/postgresql/<ver>/main/pg_wal.predvolume.*/. \
      /var/lib/postgresql/<ver>/main/pg_wal/
# Remove the fstab entry the role added
sed -i '/pg_wal/d' /etc/fstab
umount /var/lib/postgresql/<ver>/main/pg_wal
# The original pg_wal is still at the .predvolume.<ts> path if you
# want to go back to the pre-migration layout:
rmdir /var/lib/postgresql/<ver>/main/pg_wal
mv /var/lib/postgresql/<ver>/main/pg_wal.predvolume.<ts> \
   /var/lib/postgresql/<ver>/main/pg_wal
systemctl start postgresql
```

Then restart DHIS2 and verify health. If the rollback also fails:
restore the base backup from step 1 using
`dhis2-restore database`.

## What this change gives you

- `pg_wal` lives on its own filesystem. A WAL ENOSPC event cannot
  take down the data filesystem. PG stops writes on ENOSPC-WAL but
  the data cluster remains intact and recovery requires only
  freeing WAL (or expanding the WAL volume), not any data-side
  surgery.
- `dhis2-db wal volume status` reports `DEDICATED`.
- `dhis2-doctor wal` and the dhis2-wal-watchdog systemd timer
  continue to monitor the WAL filesystem's own capacity, now
  bounded.

## Not changed by this migration

- `max_wal_size`, `max_slot_wal_keep_size`, and the compliance
  math (WAL Phase 1) still apply. A dedicated volume lets you
  tolerate the configured ceilings being briefly exceeded by a
  spike without an outage; it does not make the ceilings
  irrelevant.
- Streaming replication and PITR semantics are unchanged.
- The `backups` role continues to use its existing backup
  destination.
