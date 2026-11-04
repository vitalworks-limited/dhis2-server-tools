# Regression run report

Generated: 2026-11-04T05:50:49Z

Mode: mock

Results: PASS=105 FAIL=0 SKIP=2

| ID | Scenario | Mode | Result | Notes |
|----|----------|------|--------|-------|
| A | LXD deploy.sh help | mock | PASS | deploy.sh accepts --help |
| B | SSH deployment direct ansible-playbook | mock | SKIP | ansible-playbook not installed on this host |
| C | Hybrid connection detected | mock | PASS | dhis2-deploy show reports hybrid |
| D | Existing Ansible tags exposed | mock | PASS | all canonical tags present |
| E | create-instance preserves existing config path | mock | PASS | preserve branch present in tomcat-setup.yml |
| E1 | --preserve-dhis-conf passes dhis2_conf_mode=preserve | mock | PASS | flag wired through CLI and role |
| E2 | dhis.conf merge branch present | mock | PASS | property-aware merge task present |
| E3 | replace requires explicit confirmation | mock | PASS | config replace prompts for instance name |
| F | backup role present | mock | PASS | roles/backups/ exists |
| G | WireGuard playbook present | mock | PASS | wireguard.yml preserved |
| H | monitoring role present | mock | PASS | roles/monitoring preserved |
| I | config-only deployment skips WAR | mock | PASS | --skip-war-deploy wires dhis2_skip_war_deploy=true |
| I2 | role respects dhis2_skip_war_deploy | mock | PASS | deploy-war gated by variable |
| J | pg_conf preserve mode wired | mock | PASS | both CLI entry points honor postgres_conf_mode |
| K | proxy remove preserves other routes | mock | PASS | operator is directed to inventory-driven removal |
| L | restore terminates ONLY target-db sessions | mock | PASS | pg_terminate_backend scoped by datname |
| M | idempotent deployment | mock | SKIP | ansible-playbook not installed |
| N | proxy reload gated on config test | mock | PASS | reload invokes test first |
| O | TLS install validates proxy before reload | mock | PASS | install refuses to reload on failed test |
| P | interrupted upgrade state is captured | mock | PASS | state file recorded by monitor-migrations |
| Q | restore validates backup before destructive action | mock | PASS | verify runs before DROP |
| R | secret redaction removes raw passwords | mock | PASS | redactor replaces connection.password |
| S | LXD snapshot not misrepresented as DB backup | mock | PASS | snapshot has safety warning |
| T | --no-package-upgrades honored | mock | PASS | CLI maps --no-package-upgrades to extra-var |
| U | database upgrade default policy is 'detect' | mock | PASS | defaults.yml sets dhis2_database_upgrade_mode: detect |
| V | upgrade plan runs read-only db inspection | mock | PASS | plan output describes inspect stage |
| W | upgrade run supports backup-before-migration | mock | PASS | controlled workflow includes backup stage |
| X | failed health check returns distinct exit code | mock | PASS | upgrade exits with DHIS2_EXIT_HEALTH on failed verify |
| Y | existing database credentials preserved by default | mock | PASS | defaults.yml preserves credentials |
| Z | unknown source version recorded with confidence | mock | PASS | monitor task records UNKNOWN lineage + confidence |
| AA | install.sh is controller-only | mock | PASS | installer touches local PREFIX only |
| AB | managed VMs do not need the CLI repo | mock | PASS | all stateful ops routed through Ansible |
| AC | controller loss does not stop runtime services | mock | PASS | no data-path daemon installed by install.sh |
| AD | controller coordinates multi-host operations | mock | PASS | upgrade orchestrates backup+instance+deploy |
| AE | environments isolate inventory | mock | PASS | config resolver honors --environment |
| AF | dhis2-db flyway failed-row gate | mock | PASS | query against flyway_schema_history is wired |
| AF2 | role refuses start on failed rows | mock | PASS | pre-start fail task present |
| AG | upgrade preflight detects stale Flyway locks | mock | PASS | lock-age query present |
| AG2 | role refuses start on stuck locks | mock | PASS | pre-start lock gate present |
| AH | role dumps failing migration SQL on failure | mock | PASS | bundle capture task present |
| AH2 | dhis2-upgrade failure-bundle on-demand | mock | PASS | command dumps flyway state |
| AI | upgrade preflight gates on PG major-version mismatch | mock | PASS | compatibility matrix enforced |
| AI2 | role records pool-pressure warnings | mock | PASS | pool-pressure watcher present |
| AI3 | dhis2-db analytics status wired | mock | PASS | analytics subcommand present |
| AJ | upgrade run blocks on UNKNOWN source without override | mock | PASS | escape hatch wired |
| AK | doctor config cross-checks base URL + TLS SAN | mock | PASS | cross-check present |
| AL | normalize_dhis2_version detects pinned patch (>=3 dotted parts) | mock | PASS | pinned_exact flag implemented |
| AL2 | role fails on strict-pin + unknown patch | mock | PASS | fail task present |
| AM | dhis2-upgrade run --to rejects bare channel | mock | PASS | requires patch by default |
| AM2 | dhis2-instance set-version refuses bare channel by default | mock | PASS | guard present |
| AN | upgrade run defaults to strict pin on patch versions | mock | PASS | pin flag propagated |
| AO | deploy-war.yml verifies sha256 via get_url | mock | PASS | integrity check wired |
| AP | dhis2-instance health supports --retry and --expect-version | mock | PASS | retry wired |
| AP2 | upgrade run post-flight calls API health with version check | mock | PASS | post-flight API probe |
| AQ | dhis2-vault rotate-db-password transactional with rollback | mock | PASS | rotation + rollback paths present |
| AR | preflight checks DNS, disk, RAM, CPU | mock | PASS | all four resource checks present |
| AS | upgrade run --all / --instances / --serial supported | mock | PASS | multi-instance orchestrator wired |
| AT | install.sh writes logrotate policy | mock | PASS | logrotate policy present |
| AU | dhis2-doctor --fix dry-run + apply | mock | PASS | fix path with dry-run present |
| AV | dhis2-backup create supports --encrypt gpg --recipient | mock | PASS | encryption wired |
| AV2 | dhis2-backup verify understands .gpg | mock | PASS | gpg verify branch present |
| AV3 | dhis2-restore database decrypts .gpg transparently | mock | PASS | decrypt path present |
| AW | dhis2-db wal + replication-slot families wired | mock | PASS | all WAL subcommands present |
| AX | emergency-drain is confirmation-gated + audited | mock | PASS | safety wiring present |
| AX2 | replication-slot drop refuses active slots without --force | mock | PASS | active-slot guard present |
| AY | dhis2-doctor wal cross-check present | mock | PASS | doctor wal wired |
| AZ | postgres role has max_wal_size default | mock | PASS | WAL retention bounded |
| AZ2 | archive-command preflight exists and is wired | mock | PASS | preflight included |
| BA | HA roles etcd/patroni/haproxy-pg present | mock | PASS | all three HA roles exist |
| BB | etcd role templates renders correct cluster bootstrap | mock | PASS | etcd templates present |
| BC | patroni template has scope, slots, pg_rewind | mock | PASS | patroni template correct |
| BD | haproxy-pg routes writes to /leader + reads to /replica | mock | PASS | both listeners wired |
| BE | dhis2-cluster exposes all 13 subcommands | mock | PASS | all subcommands wired |
| BF | failover/switchover/reinit all confirmation-gated | mock | PASS | all three gated |
| BG | dhis2-cluster refuses without dhis2_ha=true | mock | PASS | preflight guard present |
| BH | preflight rejects 3-etcd-same-physical_host | mock | PASS | rule 1 enforced |
| BI | preflight rejects primary+sync on same physical_host | mock | PASS | rule 2 enforced |
| BJ | postgres role delegates to Patroni when dhis2_ha=true | mock | PASS | delegation task present |
| BK | dhis2.yml gates HA import on dhis2_ha=true | mock | PASS | no-regression preserved |
| BL | patroni role masks OS postgresql service | mock | PASS | OS pg masked |
| BM | dhis2-cluster output passes through secret redaction | mock | PASS | redaction wired |
| BN | pg_max_slot_wal_keep_size defaults to a bounded value | mock | PASS | default 10GB (not -1) |
| BO | WAL compliance preflight task present + wired + refuses -1 | mock | PASS | preflight compliance task present |
| BP | preflight does sizing math and cites PG16 official docs | mock | PASS | math + docs cited |
| BQ | dhis2-db wal compliance computes budget and exits 6/8 on breach | mock | PASS | compliance subcommand correct |
| BR | dhis2-doctor wal integrates compliance via dhis2-db wal compliance | mock | PASS | doctor compliance wired |
| BR2 | patroni template includes compliance knobs | mock | PASS | max_slot_wal_keep_size + archive_timeout rendered |
| BS | pg_wal_volume task has fresh + migration paths + safety gates | mock | PASS | role task complete |
| BT | wal-watchdog service+timer present + wired to dhis2-db wal | mock | PASS | watchdog units present |
| BU | install.sh wires the watchdog + uninstall removes it | mock | PASS | installer wired |
| BV | dhis2-db wal volume + watchdog status subcommands present | mock | PASS | Phase 2 CLI complete |
| BW | dhis2-deploy architectures lists boombox as SUPPORTED | mock | PASS | boombox is first-class |
| BW2 | architectures --json includes boombox | mock | PASS | JSON schema updated |
| BX | init --architecture boombox writes a valid inventory | mock | PASS | boombox init works |
| BY | preflight refuses boombox + dhis2_ha=true | mock | PASS | rule 13 enforced |
| BZ | boombox role + playbook + doctor all wired | mock | PASS | integration complete |
| BZ2 | resource shortfalls are warnings (locked decision 1) | mock | PASS | warnings not fails |
| CA | migrate boombox-to-lxd refuses non-boombox inventories | mock | PASS | architecture gate present |
| CB | migrate --execute refuses without --yes | mock | PASS | safety guard present |
| CC | migrate --dry-run prints full plan including destructive stages | mock | PASS | dry-run complete |
| CD | migrate has rollback-pre + operator-restore + audit records | mock | PASS | safety paths wired |
| CE | post-migration inventory is LXD-shaped | mock | PASS | renderer correct |
| CF | migrate drift detection parses dhis.conf + versions | mock | PASS | drift detector present |
| CG | migrate supports multi-instance boombox | mock | PASS | multi-instance wired |
| CH | migrate --rotate-db-password flag wired to dhis2-vault | mock | PASS | rotation hook present |
| CI | migrate preserves custom nginx + pg systemd overrides | mock | PASS | preservation present |
| CJ | backup/restore resolve configured DB from dhis.conf | mock | PASS | configured-db resolution wired |
