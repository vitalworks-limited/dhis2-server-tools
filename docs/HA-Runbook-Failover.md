# HA Runbook — PostgreSQL failover and recovery

Operator-facing runbook for Phase 1 HA incidents. Pin this somewhere
operators can read it before 2 AM.

## Scenarios

### 1. Automatic failover triggered (healthy)

**Signal:**
```
dhis2-cluster status
```
shows a new leader; HAProxy repointed `:5000` within one check cycle
(~6 seconds).

**Expected operator action:** none beyond verification.

**Verify:**
```bash
dhis2-cluster leader                    # new primary host
dhis2-cluster replicas                  # includes the demoted old primary (will auto-rejoin)
dhis2-cluster etcd-health
dhis2-doctor cluster                    # end-to-end health
```

If the old primary rejoins as a replica → done. If it stays in
`stopped` state, see scenario 3.

---

### 2. Planned switchover (maintenance window)

Use this when you need to patch the current primary's OS, reboot
the host, or move primary to a different physical host for load
balancing.

```bash
dhis2-cluster pause --yes                       # suspend auto-failover
dhis2-cluster switchover --to pg02 --yes        # graceful; waits for pg02 to catch up
# ... do maintenance on pg01 ...
dhis2-cluster resume --yes                      # re-enable auto-failover
```

If a replica is lagging and switchover refuses:
```bash
dhis2-cluster lag                               # which replica is behind?
# wait or dhis2-cluster reinit <lagging-replica>
```

---

### 3. Replica stuck in `stopped` or `creating replica`

**Signal:**
```
dhis2-cluster status
```
shows a replica in `stopped`, `creating replica`, or
`in archive recovery` for > 10 minutes.

**Cause:** usually one of
- divergent timeline after a failover (pg_rewind cannot rejoin)
- disk full on the replica
- a Patroni crash during basebackup

**Response:**
```bash
dhis2-cluster reinit <replica-host> --yes       # wipe local PG + rebuild from leader
dhis2-cluster status                            # verify streaming resumes
```

`reinit` runs `pg_basebackup` from the current leader. Expect
proportional time to the DB size (10 min / 100 GB is typical on a
LAN).

---

### 4. All replicas offline, sync-strict was set

**Signal:** writes to `:5000` hang. `dhis2-cluster status` shows
only the leader, in `running` state, but every replica is `stopped`.

If `patroni_synchronous_mode_strict=true` the primary refuses writes
when no sync replica is available (that is the whole point of strict
mode).

**Response:**
```bash
dhis2-cluster patroni-config show               # confirm synchronous_mode_strict
dhis2-cluster pause --yes                       # suspend auto-failover
# option A: bring replicas back
dhis2-cluster reinit pg02 --yes
# option B: temporarily disable strict mode (writes resume at RPO >0 risk)
dhis2-cluster patroni-config edit               # set synchronous_mode_strict: false
dhis2-cluster resume --yes
```

Document the strict-mode-off window in your change log. Flip back
to `true` once replicas are healthy.

---

### 5. etcd quorum lost

**Signal:**
```
dhis2-cluster etcd-health
```
reports fewer than 2 healthy endpoints. Patroni on every node
enters read-only mode (and refuses to promote anything).

**Cause:** usually one of
- a network partition
- 2+ etcd hosts rebooted simultaneously
- etcd disk full (the quota is 8 GiB by default, enforced via
  `--quota-backend-bytes`; the role sets periodic compaction)

**Response:**
```bash
# 1. Identify the surviving etcd member
for h in etcd01 etcd02 etcd03; do
    ssh $h 'etcdctl --endpoints=http://127.0.0.1:2379 endpoint health' || echo "$h down"
done

# 2. If only one etcd is up, promote a new 3-node cluster from a
#    fresh snapshot:
#    - stop etcd on the two dead hosts
#    - on the survivor:
ssh etcd01 'etcdctl --endpoints=http://127.0.0.1:2379 snapshot save /tmp/etcd.snap'
#    - follow the etcd disaster-recovery doc:
#      https://etcd.io/docs/v3.5/op-guide/recovery/

# 3. Once etcd quorum is back, Patroni resumes writes automatically.
dhis2-cluster status
```

Prevent future recurrence by alerting on etcd leader loss (planned
in HA Phase 4).

---

### 6. Split-brain protection fired

Patroni refuses to promote a replica when etcd quorum is unknown.
That is the correct behaviour — never override it.

**Signal:** no leader in `dhis2-cluster status` for > 5 minutes;
`dhis2-cluster etcd-health` shows reachable members but mixed
"leader" opinions.

**Response:** restore etcd quorum first (scenario 5), then Patroni
will elect a new leader on its own.

**Do NOT:** manually promote via `pg_ctl promote` on any node. That
is the one guaranteed way to lose data.

---

### 7. Rolling PostgreSQL minor upgrade

Example: 16.4 → 16.5. In Phase 1 this is operator-driven; a dedicated
`dhis2-cluster rolling-upgrade` command is on the Phase 4 backlog.

```bash
dhis2-cluster pause --yes

# upgrade a replica first
ssh pg03 'sudo apt-get update && sudo apt-get install -y postgresql-16'
dhis2-cluster reinit pg03 --yes      # not strictly needed for minor; forces a clean rejoin

# switchover away from the current primary
dhis2-cluster switchover --to pg03 --yes

# upgrade the demoted primary (now a replica)
ssh pg01 'sudo apt-get install -y postgresql-16'

# optional: switchover back if you want pg01 as the long-term primary
dhis2-cluster switchover --to pg01 --yes

dhis2-cluster resume --yes
```

For major version upgrades (16 → 17), see the dedicated runbook
planned for Phase 4.

---

### 8. HAProxy backend is slow but reachable

**Signal:** `dhis2-cluster leader` returns a host but
`dhis2-doctor cluster` reports write latency climbing. HAProxy
`:7000` stats page shows the leader with a long `qtime`.

**Response:**
```bash
dhis2-db long-running                           # idle-in-transaction?
dhis2-db wal retention                          # replication slot pinning WAL?
dhis2-db connections                            # pool exhaustion?
```

Fix root cause; HAProxy itself is rarely the bottleneck.

---

## Audit trail

Every failover, switchover, reinit, pause, and resume writes to
`/var/log/dhis2-server-tools/audit.ndjson`:

```bash
tail -20 /var/log/dhis2-server-tools/audit.ndjson | jq .
```

## Related

- [docs/HA-Patroni.md](./HA-Patroni.md) — the full operator guide.
- [docs/CLI-WAL-Operations.md](./CLI-WAL-Operations.md) — WAL
  pressure under HA (replication slots pin WAL).
- [Patroni upstream failover docs](https://patroni.readthedocs.io/en/latest/README.html).
- [etcd disaster recovery](https://etcd.io/docs/v3.5/op-guide/recovery/).
