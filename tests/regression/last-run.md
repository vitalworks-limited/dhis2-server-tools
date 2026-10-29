# Regression run report

Generated: 2026-10-29T15:09:38Z

Mode: mock

Results: PASS=33 FAIL=0 SKIP=2

| ID | Scenario | Mode | Result | Notes |
|----|----------|------|--------|-------|
| A | LXD deploy.sh help | mock | PASS | deploy.sh accepts --help |
| B | SSH deployment direct ansible-playbook | mock | SKIP | community.general collection not installed |
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
| M | idempotent deployment | mock | SKIP | community.general collection not installed |
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
| Z | unknown source version recorded as 'unknown' | mock | PASS | monitor task records unknown lineage |
| AA | install.sh is controller-only | mock | PASS | installer touches local PREFIX only |
| AB | managed VMs do not need the CLI repo | mock | PASS | all stateful ops routed through Ansible |
| AC | controller loss does not stop runtime services | mock | PASS | no controller daemon installed |
| AD | controller coordinates multi-host operations | mock | PASS | upgrade orchestrates backup+instance+deploy |
| AE | environments isolate inventory | mock | PASS | config resolver honors --environment |
