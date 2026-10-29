<!--
Regenerated DHIS2 Server Tools Implementation Requirements
Repository: vitalworks-limited/dhis2-server-tools
Regenerated: 2026-10-29
Scope: No-regression CLI, deployment, configuration preservation, controlled legacy-database
upgrade, distributed controller architecture, backup/restore, diagnostics, monitoring,
security, and complete pull-request acceptance requirements.
-->

# DHIS2 Server Tools — Comprehensive Implementation Requirements for a No-Regression CLI and Deployment Management Upgrade

**Repository:** `vitalworks-limited/dhis2-server-tools`  
**Target branch:** Fork feature branch before upstream pull request  
**Document type:** Implementation Requirements Specification  
**Primary objective:** Introduce a comprehensive, consistent `dhis2-*` command suite over the existing Ansible implementation while preserving all currently supported deployment behavior and preventing regressions.  
**Supported deployment architectures in scope:** LXD, distributed SSH/VM, and hybrid LXD/SSH  
**Out of scope for this PR:** Claiming production support for Docker or Kubernetes unless separately implemented and fully tested.

---

## 1. Purpose

This document defines the functional, technical, compatibility, testing, security, packaging, documentation, and release requirements that MUST be implemented on the fork before submitting a complete pull request to the upstream `dhis2-server-tools` project.

The implementation MUST build on the existing Ansible roles and playbooks rather than replacing them unnecessarily. The primary change is to introduce a stable operator-facing command layer that standardizes deployment, lifecycle management, diagnostics, backups, restores, upgrades, inventory management, database administration, proxy/TLS management, monitoring, VPN operations, Doris operations, integration services, and supporting platform administration.

The implementation MUST preserve all currently working deployment paths and MUST NOT require existing operators to immediately migrate their inventories, variables, playbooks, or automation.

---

# 2. Core Goals

The implementation MUST achieve the following goals:

1. Provide a consistent `dhis2-*` command family for supported infrastructure and DHIS2 operations.
2. Preserve the existing Ansible roles, variables, inventory semantics, tags, and supported workflows unless a change is unavoidable.
3. Support all currently implemented deployment architectures:
   - single-host LXD;
   - distributed physical/virtual servers over SSH;
   - hybrid LXD and SSH deployments.
4. Make direct `ansible-playbook` knowledge optional for normal operators.
5. Introduce safe preflight, validation, planning, execution, and post-deployment verification workflows.
6. Provide complete lifecycle operations for DHIS2 instances.
7. Provide comprehensive PostgreSQL administration and diagnostics appropriate for DHIS2.
8. Provide safe backup and restore workflows.
9. Provide controlled DHIS2 upgrade orchestration.
10. Provide actionable infrastructure diagnostics through `dhis2-doctor`.
11. Improve logging, auditability, error handling, and machine-readable output.
12. Preserve backward compatibility with existing wrapper scripts and command paths.
13. Add automated test coverage sufficient to demonstrate no regression.
14. Add documentation for every new command and migration path.
15. Keep Docker and Kubernetes explicitly marked as unsupported until fully implemented.

---

# 3. Mandatory No-Regression Principle

No existing supported behavior may be removed, silently changed, or made dependent on the new CLI.

The following MUST continue to work after the implementation:

- `deploy/deploy.sh`
- `ansible-playbook deploy/dhis2.yml`
- existing Ansible inventory files using the current INI structure;
- existing `ansible_connection=lxd` deployments;
- existing `ansible_connection=ssh` deployments;
- per-host connection overrides;
- hybrid deployments where different hosts use different connection types;
- existing PostgreSQL role behavior;
- existing proxy role behavior;
- existing monitoring role behavior;
- existing `create-instance` role behavior;
- existing backup role behavior;
- existing WireGuard playbooks and roles;
- existing alerting role behavior;
- existing Doris provisioning behavior;
- existing integration role behavior;
- existing supported DHIS2 version variables;
- existing `dhis2_war_file` behavior;
- existing `dhis2_auto_upgrade` behavior;
- existing custom TLS, Let's Encrypt, and self-signed TLS behavior;
- existing monitoring choices;
- existing inventory group names;
- existing tags used by automation.

Where a legacy shell script is superseded by a new command, the original script SHOULD remain as a compatibility wrapper for at least one deprecation cycle.

No legacy command may be removed in the same pull request that introduces its replacement unless upstream maintainers explicitly approve the breaking change.

---

# 4. Existing Baseline That Must Be Preserved

The current implementation already includes or partially includes the following functional areas:

- pre-installation;
- LXD provisioning;
- SSH-based provisioning;
- PostgreSQL installation and configuration;
- DHIS2 instance creation;
- Tomcat configuration;
- WAR deployment;
- DHIS2 release resolution;
- reverse proxy configuration;
- Nginx;
- Apache2;
- OpenResty;
- TLS;
- monitoring;
- Munin;
- Prometheus;
- Grafana;
- Zabbix-related tasks;
- PostgreSQL exporters;
- application monitoring;
- backups;
- S3-related backup support;
- WireGuard;
- alerting;
- Apache Doris;
- integration services;
- instance deletion;
- unattended upgrades.

The new command layer MUST invoke these capabilities where they already exist instead of duplicating configuration logic in shell code.

---

# 5. Design Principles

## 5.1 Thin CLI, strong Ansible backend

The CLI MUST be an orchestration layer.

The CLI MUST NOT become a second independent configuration-management engine.

Where an operation is already represented by an Ansible role or playbook, the CLI SHOULD execute that role/playbook with validated arguments.

Shared behaviors MUST be implemented centrally rather than copied into individual scripts.

Recommended internal layout:

```text
bin/
  dhis2-deploy
  dhis2-host
  dhis2-inventory
  dhis2-instance
  dhis2-db
  dhis2-backup
  dhis2-restore
  dhis2-upgrade
  dhis2-proxy
  dhis2-tls
  dhis2-monitor
  dhis2-logs
  dhis2-doctor
  dhis2-security
  dhis2-vpn
  dhis2-doris
  dhis2-integration
  dhis2-vault
  dhis2-status

lib/
  common.sh
  config.sh
  ansible.sh
  inventory.sh
  validation.sh
  logging.sh
  output.sh
  privilege.sh
  locks.sh
```

Equivalent implementation in Python is acceptable if approved for the project, but it MUST remain dependency-light and easy to install on supported Ubuntu deployment controllers.

---

# 6. Naming Requirements

## 6.1 Stable top-level commands

The target command family SHOULD include:

```text
dhis2-deploy
dhis2-host
dhis2-inventory
dhis2-instance
dhis2-db
dhis2-backup
dhis2-restore
dhis2-upgrade
dhis2-proxy
dhis2-tls
dhis2-monitor
dhis2-logs
dhis2-doctor
dhis2-security
dhis2-vpn
dhis2-doris
dhis2-integration
dhis2-vault
dhis2-status
```

Commands MUST use subcommands rather than proliferating executables such as:

```text
dhis2-instance-restart
dhis2-instance-stop
dhis2-instance-start
```

Preferred:

```bash
dhis2-instance restart hmis
dhis2-instance stop hmis
dhis2-instance start hmis
```

---

# 7. Common CLI Requirements

All applicable commands MUST support a consistent set of global options.

Minimum common options:

```text
--inventory PATH
--limit HOST_OR_GROUP
--instance NAME
--host NAME
--user USER
--connection lxd|ssh
--check
--diff
--verbose
--quiet
--yes
--json
--no-color
--help
--version
```

Not every option must be accepted by every command, but shared options MUST use identical names and semantics.

## 7.1 Exit codes

At minimum:

| Exit Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Generic execution failure |
| `2` | Invalid arguments |
| `3` | Preflight/validation failure |
| `4` | Connectivity failure |
| `5` | Ansible execution failure |
| `6` | Health-check failure |
| `7` | Partial success requiring operator attention |
| `8` | Safety check prevented destructive action |
| `9` | Lock/concurrent operation conflict |

Exit codes MUST be documented.

## 7.2 Machine-readable output

Commands supporting `--json` MUST output valid JSON to stdout.

Human log messages MUST go to stderr when `--json` is active.

JSON output MUST be versioned or structured consistently enough for automation.

Example:

```json
{
  "command": "dhis2-status",
  "success": true,
  "instances": [],
  "warnings": [],
  "errors": []
}
```

---

# 8. Configuration and Installation Requirements

## 8.1 Recommended installation path

The installed application SHOULD use:

```text
/opt/dhis2-server-tools/
```

Executable links SHOULD be exposed in:

```text
/usr/local/bin/
```

Example:

```text
/usr/local/bin/dhis2-deploy -> /opt/dhis2-server-tools/bin/dhis2-deploy
```

## 8.2 Configuration search order

A deterministic search order MUST be documented.

Recommended:

1. explicit CLI argument;
2. environment variable;
3. project-local configuration;
4. `/etc/dhis2-server-tools/`;
5. built-in defaults.

## 8.3 Environment variables

Supported environment variables SHOULD include:

```text
DHIS2_TOOLS_HOME
DHIS2_INVENTORY
DHIS2_ENVIRONMENT
DHIS2_ANSIBLE_CONFIG
DHIS2_LOG_LEVEL
DHIS2_NO_COLOR
```

Passwords and private keys MUST NOT be passed through unsafe environment variables by default when safer mechanisms exist.

---

# 9. Privilege Management

The implementation MUST clearly separate:

- controller-user privileges;
- remote SSH user;
- Ansible become privileges;
- LXD group access;
- PostgreSQL administrative privileges.

Commands MUST NOT blindly run the entire process as root unless required.

Where `sudo` is needed, the CLI SHOULD elevate only the required operation.

The CLI MUST detect and explain missing privileges.

---

# 10. Deployment Architecture Requirements

The CLI MUST model supported architectures explicitly.

Supported architecture identifiers:

```text
lxd
distributed
hybrid
```

## 10.1 LXD architecture

Must support:

- single deployment controller/host;
- LXD bridge creation/use;
- proxy container;
- PostgreSQL container;
- one or more DHIS2 instance containers;
- monitoring container;
- optional Doris container;
- optional WireGuard hub/container;
- backup infrastructure.

## 10.2 Distributed architecture

Must support separate physical/virtual hosts for:

- proxy;
- PostgreSQL;
- DHIS2 application server(s);
- monitoring;
- Doris, when supported;
- backup services;
- integration services.

Communication MUST use SSH-based Ansible connections.

## 10.3 Hybrid architecture

Must support per-host connection selection.

Example:

```text
postgres  -> ssh
proxy     -> lxd
hmis      -> lxd
monitor   -> ssh
```

The CLI MUST NOT globally force all inventory hosts to the same connection mode.

---

# 11. `dhis2-deploy` Requirements

`dhis2-deploy` SHALL be the primary deployment orchestration command.

Required subcommands:

```text
dhis2-deploy init
dhis2-deploy architectures
dhis2-deploy preflight
dhis2-deploy plan
dhis2-deploy apply
dhis2-deploy verify
dhis2-deploy resume
```

Optional but recommended:

```text
dhis2-deploy history
dhis2-deploy show
```

## 11.1 `init`

Must support:

```bash
dhis2-deploy init --architecture lxd
dhis2-deploy init --architecture distributed
dhis2-deploy init --architecture hybrid
```

It MUST:

- create a deployment workspace;
- create inventory from the current supported template;
- preserve comments where useful;
- create secure permissions;
- validate target directory;
- never overwrite an existing inventory without explicit approval.

## 11.2 `architectures`

Must report support state.

Expected:

```text
lxd          SUPPORTED
distributed  SUPPORTED
hybrid       SUPPORTED
docker       NOT IMPLEMENTED
kubernetes   NOT IMPLEMENTED
```

The tool MUST NOT claim unsupported architectures as available.

## 11.3 `preflight`

Must validate at minimum:

- supported Ubuntu release;
- Ansible availability/version;
- required Ansible collections;
- inventory syntax;
- duplicate IP addresses;
- duplicate host names;
- required groups;
- referenced database hosts;
- referenced proxy/monitoring hosts;
- SSH reachability for SSH hosts;
- SSH authentication;
- sudo/become access;
- Python availability;
- LXD availability for LXD deployments;
- LXD bridge configuration;
- LXD network overlap;
- disk availability;
- RAM availability;
- CPU availability;
- DNS resolution where FQDN is configured;
- outbound access required for package/WAR/certificate downloads;
- PostgreSQL port conflicts;
- HTTPS port conflicts;
- Java/DHIS2 compatibility where known;
- target DHIS2 release resolvability;
- TLS prerequisites;
- supported proxy selection;
- monitoring configuration consistency.

Preflight MUST be read-only.

## 11.4 `plan`

Must run a non-destructive Ansible plan using appropriate check/diff behavior where supported.

It MUST identify tasks that cannot accurately execute in check mode.

## 11.5 `apply`

Must:

- acquire an operation lock;
- record execution metadata;
- validate preflight unless explicitly bypassed by a documented expert-only flag;
- call the canonical playbooks;
- preserve per-host connection type;
- stream useful output;
- return Ansible failure status correctly;
- perform post-deployment verification;
- produce a summary.


## 11.5.1 DHIS2 configuration preservation during deployment

`dhis2-deploy apply` and any deployment path that re-runs the `create-instance` role MUST provide explicit control over how an existing `dhis.conf` is handled.

The deployment system MUST support preserving an existing `dhis.conf` without replacing local configuration values such as:

```text
connection.url
connection.username
connection.password
server.base.url
encryption.password
connection.pool.*
analytics.*
tracker.*
redis.*
mail.*
custom application properties
```

At minimum, the CLI MUST support the following modes:

```bash
dhis2-deploy apply --preserve-dhis-conf
dhis2-deploy apply --merge-dhis-conf
dhis2-deploy apply --replace-dhis-conf
```

Recommended default behavior for an existing DHIS2 installation:

```text
preserve existing dhis.conf
```

A deployment MUST NOT overwrite an existing production `dhis.conf` merely because the Ansible role is re-run.

### `--preserve-dhis-conf`

When specified:

- an existing `dhis.conf` MUST remain unchanged;
- database credentials MUST remain unchanged;
- locally managed settings MUST remain unchanged;
- Ansible MAY validate the file but MUST NOT rewrite it;
- missing required configuration MUST be reported as a warning/error rather than silently regenerated;
- the command MUST clearly report that configuration preservation was used.

Example:

```bash
dhis2-deploy apply --instance hmis --preserve-dhis-conf
```

Expected result:

```text
Existing /opt/dhis2/dhis.conf detected.
Configuration mode: PRESERVE
No existing DHIS2 configuration values were replaced.
```

### `--merge-dhis-conf`

When specified:

- the current `dhis.conf` MUST be read first;
- existing values MUST be preserved unless an explicit CLI/inventory override requires a change;
- new required properties MAY be added;
- generated defaults MUST NOT replace existing passwords or local settings;
- a diff MUST be shown with `--diff`;
- a backup MUST be created before writing;
- the resulting file MUST be written atomically.

The merge operation MUST use property-aware parsing and MUST NOT rely on unsafe line replacement that can duplicate keys.

Recommended precedence:

```text
explicit CLI override
inventory/host_vars explicit value
existing dhis.conf value
generated default
```

Secrets such as `connection.password` and `encryption.password` MUST NOT appear in normal diff output.

### `--replace-dhis-conf`

This mode MAY regenerate the complete file from Ansible templates.

It MUST:

- require explicit operator intent;
- create a timestamped backup of the existing file first;
- warn that existing local configuration may be replaced;
- preserve file ownership and permissions;
- never expose secret values in logs.

For an existing production instance, replacement SHOULD require confirmation unless `--yes` is supplied.

Example:

```text
Existing dhis.conf will be replaced.
Backup: /opt/dhis2/dhis.conf.20261029-105200.bak
Type the instance name "hmis" to continue:
```

### First-time deployments

For a new instance where no `dhis.conf` exists:

- the normal Ansible template MAY create the file;
- database credentials MAY be generated according to the existing workflow;
- generated credentials MUST be stored securely;
- subsequent deployments MUST reuse those values unless explicit rotation or replacement is requested.

### Database password stability

Re-running deployment MUST NOT regenerate or replace an existing database password by default.

The following MUST remain consistent unless an explicit password-rotation operation is requested:

```text
PostgreSQL role password
dhis.conf connection.password
stored Ansible/vault secret
backup/restore connection settings
```

A deployment MUST fail safely if it detects a mismatch between the configured PostgreSQL password and the password recorded for DHIS2, rather than automatically changing one side without operator approval.

### Recommended additional commands/options

The implementation SHOULD provide:

```bash
dhis2-instance config show hmis
dhis2-instance config diff hmis
dhis2-instance config backup hmis
dhis2-instance config validate hmis
dhis2-instance config merge hmis
dhis2-instance config replace hmis
```

Sensitive values MUST be redacted by default.

### Ansible role requirement

The `create-instance` role SHOULD expose a backward-compatible variable such as:

```yaml
dhis2_conf_mode: preserve
```

Supported values:

```text
preserve
merge
replace
```

For compatibility with existing deployments, if the variable is not defined, existing behavior MAY initially remain unchanged during migration; however, the new CLI SHOULD explicitly set the safe mode for existing instances.

A second safety variable MAY be provided:

```yaml
dhis2_preserve_database_credentials: true
```

This MUST default to `true` for existing installations.

The implementation MUST distinguish between:

```text
new installation
existing installation
explicit configuration replacement
explicit credential rotation
```

These states MUST NOT be inferred solely from whether the Ansible role is being re-run.

## 11.6 `verify`

Must perform service and endpoint verification without redeploying.

---

# 12. `dhis2-host` Requirements

Required subcommands:

```text
dhis2-host list
dhis2-host show
dhis2-host ping
dhis2-host facts
dhis2-host check
dhis2-host bootstrap
dhis2-host ssh-install-key
dhis2-host sudo-check
dhis2-host firewall
```

## 12.1 Bootstrap

Must be able to prepare fresh supported Ubuntu servers for Ansible management.

At minimum:

- validate OS;
- install Python if missing;
- ensure SSH is functional;
- optionally create/validate deployment user;
- install SSH key;
- validate sudo;
- ensure required packages;
- avoid locking out the current SSH session;
- preserve existing SSH authorized keys;
- avoid replacing `sshd_config` wholesale.

Destructive SSH/firewall changes MUST require explicit confirmation or `--yes`.

---

# 13. `dhis2-inventory` Requirements

Required subcommands:

```text
dhis2-inventory list
dhis2-inventory show
dhis2-inventory validate
dhis2-inventory graph
dhis2-inventory add-host
dhis2-inventory remove-host
dhis2-inventory set
dhis2-inventory unset
dhis2-inventory add-instance
dhis2-inventory remove-instance
```

## 13.1 Compatibility

The CLI MUST continue supporting the current INI inventory format.

Migration to YAML MUST NOT be mandatory.

## 13.2 Validation

Must detect:

- malformed inventory;
- duplicate hosts;
- duplicate IPs where inappropriate;
- unresolved `database_host`;
- unsupported `ansible_connection`;
- invalid network definitions;
- invalid PostgreSQL versions;
- invalid proxy choice;
- invalid TLS mode;
- invalid monitoring combination;
- missing required variables;
- empty referenced inventory groups;
- dangerous conflicting ports;
- unsupported combinations.

## 13.3 Safe writes

Before mutating inventory, the command MUST:

- create a timestamped backup or equivalent recoverable copy;
- write atomically;
- validate the modified inventory;
- roll back the file if validation fails.

---

# 14. `dhis2-instance` Requirements

Required subcommands:

```text
dhis2-instance list
dhis2-instance show
dhis2-instance create
dhis2-instance delete
dhis2-instance start
dhis2-instance stop
dhis2-instance restart
dhis2-instance reload
dhis2-instance status
dhis2-instance health
dhis2-instance logs
dhis2-instance maintenance
```

Recommended:

```text
dhis2-instance clone
dhis2-instance config
```

## 14.1 Create

Must support at minimum:

```bash
dhis2-instance create hmis \
  --host tomcat \
  --database postgres \
  --version 2.43 \
  --fqdn hmis.example.org
```

Must validate:

- unique instance name;
- valid database host;
- valid DHIS2 release;
- compatible Java version;
- host connectivity;
- port availability;
- database creation policy;
- proxy mapping;
- TLS prerequisites.

## 14.2 Delete

Delete MUST be protected.

Default behavior MUST NOT silently destroy the database.

Deletion workflow SHOULD support independently controlled actions:

```text
--remove-app
--remove-proxy
--remove-monitoring
--remove-database
--remove-backups
```

`--remove-database` MUST require explicit confirmation.

A backup SHOULD be offered or required before destructive database deletion.

## 14.3 Start/stop/restart

Must work for:

- LXD-managed application instances;
- SSH-managed application servers;
- supported Tomcat/systemd layout.

The operator MUST not need to know whether the instance is LXD or SSH.

---

# 15. `dhis2-db` Requirements

Required subcommands:

```text
dhis2-db status
dhis2-db version
dhis2-db list
dhis2-db show
dhis2-db create
dhis2-db drop
dhis2-db size
dhis2-db connections
dhis2-db activity
dhis2-db locks
dhis2-db vacuum
dhis2-db analyze
dhis2-db reindex
dhis2-db terminate-session
dhis2-db config
dhis2-db tune
dhis2-db capacity
dhis2-db oom-check
```

## 15.1 Database create

Must support:

- database name;
- owner;
- encoding;
- template where needed;
- safe existence checks.

## 15.2 Database drop

Must:

- warn of data destruction;
- support terminating active sessions;
- require explicit confirmation;
- refuse accidental drop of protected/system databases.

## 15.3 Connections

Must report:

- active;
- idle;
- idle in transaction;
- total;
- max connections;
- percentage used;
- application/source addresses where possible.

## 15.4 Locks/activity

Must provide actionable output for:

- blocking sessions;
- blocked sessions;
- long-running transactions;
- long-running queries;
- idle-in-transaction sessions.

## 15.5 Memory/capacity analysis

Must inspect where available:

- cgroup/container memory limit;
- host memory;
- `shared_buffers`;
- `work_mem`;
- `maintenance_work_mem`;
- `max_connections`;
- `effective_cache_size`;
- temp buffers;
- major WAL/checkpoint settings.

The tool SHOULD warn when plausible peak configuration materially exceeds the host/container memory budget.

The estimate MUST be described as an estimate, not an exact PostgreSQL memory ceiling.

## 15.6 Tuning

`dhis2-db tune` MUST support a dry-run mode.

It MUST NOT overwrite custom PostgreSQL configuration without showing proposed changes.

Tuning profiles MAY include:

```text
small
medium
large
custom
auto
```

Any automatic profile MUST state assumptions.

---

# 16. `dhis2-backup` Requirements

Required subcommands:

```text
dhis2-backup create
dhis2-backup list
dhis2-backup show
dhis2-backup verify
dhis2-backup prune
dhis2-backup schedule
dhis2-backup unschedule
```

The implementation MUST preserve the existing backup role and S3-related workflows.

## 16.1 Backup formats

Where PostgreSQL tools support them, the CLI SHOULD support:

```text
plain SQL
plain SQL gzip
custom pg_dump
tar
directory
```

## 16.2 Verification

Backup verification MUST be available.

At minimum:

- file exists;
- non-zero size;
- compression test for compressed files;
- `pg_restore -l` for compatible archive formats;
- metadata checks.

Optional full restore verification MAY be added.

## 16.3 Retention

Pruning MUST:

- respect retention policy;
- never delete the newest valid backup;
- support dry-run;
- clearly show what will be removed.

---

# 17. `dhis2-restore` Requirements

Restore is a critical requirement.

Required:

```text
dhis2-restore database
dhis2-restore files
dhis2-restore full
dhis2-restore verify
```

## 17.1 Supported database sources

At minimum:

```text
.sql
.sql.gz
custom pg_dump
tar pg_dump
directory-format pg_dump
```

## 17.2 Database restore options

Must support:

```text
--owner USER
--database NAME
--create-db
--drop-existing
--clean
--jobs N
--reassign-owner
--verify
```

## 17.3 Safe restore workflow

For restoration into an actively configured DHIS2 instance, the workflow SHOULD:

1. resolve target instance;
2. validate backup;
3. verify available disk;
4. stop application when appropriate;
5. terminate target database sessions where required;
6. optionally preserve/backup current database;
7. create/drop database according to explicit options;
8. restore;
9. normalize ownership;
10. run `ANALYZE` where appropriate;
11. start application;
12. verify PostgreSQL connectivity;
13. verify DHIS2 startup;
14. verify HTTP/API health;
15. record outcome.

Failure MUST leave clear recovery instructions.

## 17.4 Ownership

Ownership reassignment MUST be explicit and deterministic.

The implementation MUST correctly handle objects not owned by the target application role when restoring dumps from another environment.

---

# 18. `dhis2-upgrade` Requirements

Required subcommands:

```text
dhis2-upgrade releases
dhis2-upgrade compatibility
dhis2-upgrade check
dhis2-upgrade plan
dhis2-upgrade run
dhis2-upgrade status
dhis2-upgrade rollback
```

## 18.1 Upgrade plan

Must inspect:

- current DHIS2 version;
- target version;
- Java version;
- PostgreSQL version;
- available disk;
- database size;
- backup state;
- URL/source of WAR;
- application health before upgrade.

## 18.2 Upgrade execution

A production-safe upgrade workflow MUST include:

1. preflight;
2. current-state capture;
3. backup;
4. backup verification;
5. WAR acquisition;
6. checksum/integrity verification where upstream data permits;
7. application stop;
8. old WAR preservation;
9. target WAR deployment;
10. application start;
11. startup log monitoring;
12. Flyway/database migration monitoring;
13. health endpoint/API verification;
14. version confirmation;
15. summary and audit record.

## 18.3 Rollback

The command MUST NOT imply that rolling back the WAR automatically rolls back completed database migrations.

The CLI MUST distinguish:

- application artifact rollback;
- full database rollback from a pre-upgrade backup.

Full database rollback MUST require explicit confirmation.

---

# 19. `dhis2-proxy` Requirements

Required subcommands:

```text
dhis2-proxy status
dhis2-proxy show
dhis2-proxy config
dhis2-proxy test
dhis2-proxy reload
dhis2-proxy restart
dhis2-proxy routes
dhis2-proxy add
dhis2-proxy remove
dhis2-proxy upstream
```

Must support currently implemented proxy engines:

```text
nginx
apache2
openresty
```

`test` MUST validate configuration before reload.

Proxy writes MUST NOT reload a broken configuration.

---

# 20. `dhis2-tls` Requirements

Required subcommands:

```text
dhis2-tls status
dhis2-tls verify
dhis2-tls issue
dhis2-tls install
dhis2-tls renew
```

Must support currently implemented modes:

```text
letsencrypt
customssl
selfsigned
```

Status SHOULD report:

- subject;
- issuer;
- SANs;
- expiry;
- days remaining;
- chain verification status where possible.

Private key contents MUST never be printed.

Private key permissions MUST be validated.

---

# 21. `dhis2-monitor` Requirements

Required subcommands:

```text
dhis2-monitor status
dhis2-monitor install
dhis2-monitor enable
dhis2-monitor disable
dhis2-monitor targets
dhis2-monitor exporters
dhis2-monitor dashboards
```

Must preserve currently supported monitoring implementations.

The CLI MUST correctly reflect what is configured rather than assuming Grafana/Prometheus.

---

# 22. `dhis2-logs` Requirements

Required forms:

```bash
dhis2-logs hmis
dhis2-logs postgres
dhis2-logs proxy
dhis2-logs monitor
```

Required filters:

```text
--follow
--since
--until
--lines
--errors
--grep
```

Recommended shortcuts:

```text
dhis2-logs startup INSTANCE
dhis2-logs migration INSTANCE
dhis2-logs database
dhis2-logs proxy
```

The CLI MUST resolve correct log locations for supported deployment types.

Passwords, tokens, and obvious secrets SHOULD be redacted from diagnostic bundles.

---

# 23. `dhis2-doctor` Requirements

`dhis2-doctor` SHALL provide a comprehensive diagnostic layer.

Required:

```text
dhis2-doctor
dhis2-doctor --quick
dhis2-doctor --full
dhis2-doctor network
dhis2-doctor database
dhis2-doctor proxy
dhis2-doctor memory
dhis2-doctor instance
```

Recommended:

```text
dhis2-doctor --fix
dhis2-doctor bundle
```

## 23.1 Checks

At minimum:

### Controller
- inventory readable;
- Ansible available;
- required collections available.

### Network
- host reachability;
- SSH connectivity;
- DNS;
- expected ports.

### Proxy
- service active;
- config syntax valid;
- instance upstream reachable;
- TLS certificate usable.

### DHIS2/Tomcat
- service active;
- Java executable/version;
- WAR deployed;
- application responds;
- expected DHIS2 version;
- `server.base.url` consistency where detectable.

### PostgreSQL
- service active;
- database reachable;
- target database exists;
- active connection level;
- dangerous lock/transaction state;
- disk availability.

### Memory
- host/container memory;
- swap;
- cgroup limits;
- recent OOM indicators where accessible.

### Monitoring
- configured server reachable;
- configured exporters active.

### Backup
- recent backup availability where configured;
- backup directory/storage health.

## 23.2 `--fix`

Automatic fixes MUST be limited to well-understood, low-risk, reversible corrections.

The command MUST show proposed changes first unless `--yes` is provided.

High-risk database, firewall, TLS, or SSH actions MUST NOT be silently auto-fixed.

---

# 24. `dhis2-status` Requirements

`dhis2-status` MUST provide a fast environment overview.

Expected output SHOULD include:

```text
INSTANCE
DHIS2 VERSION
APPLICATION STATE
DATABASE STATE
PROXY STATE
HEALTH
```

Infrastructure summary SHOULD include:

```text
PostgreSQL
Proxy
Monitoring
Doris
WireGuard
Backup
```

It MUST support `--json`.

---

# 25. `dhis2-security` Requirements

Required:

```text
dhis2-security audit
dhis2-security firewall
dhis2-security ssh
dhis2-security permissions
dhis2-security secrets
```

Recommended:

```text
dhis2-security harden
```

Audit SHOULD check:

- exposed PostgreSQL;
- exposed monitoring services;
- root SSH login settings;
- password authentication settings;
- unsafe file permissions;
- world-readable `dhis.conf`;
- plaintext credential files;
- TLS health;
- private-key permissions;
- firewall state;
- unintended service listeners;
- WireGuard restrictions where enabled.

The command MUST NOT expose secret values.

---

# 26. `dhis2-vpn` Requirements

Must expose the existing WireGuard capability.

Required:

```text
dhis2-vpn status
dhis2-vpn enable
dhis2-vpn disable
dhis2-vpn peers
dhis2-vpn add-peer
dhis2-vpn remove-peer
dhis2-vpn test
dhis2-vpn lockdown
```

Recommended:

```text
dhis2-vpn rotate-key
```

Key material MUST be handled securely.

Private keys MUST not be logged.

---

# 27. `dhis2-doris` Requirements

Required:

```text
dhis2-doris status
dhis2-doris health
dhis2-doris install
dhis2-doris databases
dhis2-doris catalogs
```

Recommended:

```text
dhis2-doris connect-postgres
```

If Doris SSH-based deployment is not production-ready, the CLI MUST report the limitation rather than silently attempting unsupported behavior.

Support status MUST be documented per architecture.

---

# 28. `dhis2-integration` Requirements

Required:

```text
dhis2-integration list
dhis2-integration status
dhis2-integration install
dhis2-integration restart
dhis2-integration remove
```

It SHOULD provide a common framework for current and future integration services without hardcoding service-specific behavior into the main deployment command.

---

# 29. `dhis2-vault` Requirements

If Ansible Vault or equivalent project secret handling is used, expose consistent operations:

```text
dhis2-vault init
dhis2-vault edit
dhis2-vault view
dhis2-vault check
dhis2-vault scan
```

Secret scanning SHOULD detect likely plaintext credentials in:

- inventory;
- variables;
- configuration files;
- generated support bundles.

It MUST avoid printing the discovered secret value.

---

# 30. Logging and Audit Requirements

Every mutating operation SHOULD generate an execution record containing:

```text
timestamp
command
arguments with secrets redacted
user
controller host
inventory
target hosts
Ansible playbook/tag
result
duration
warnings
errors
```

Recommended location:

```text
/var/log/dhis2-server-tools/
```

or user-writable equivalent for non-root execution.

Log rotation MUST be documented or configured.

---

# 31. Concurrency and Locking

Destructive or state-changing operations MUST prevent unsafe concurrent execution.

Examples:

- deployment;
- restore;
- upgrade;
- database drop;
- instance delete;
- inventory mutation.

Recommended lock scope:

```text
global deployment lock
per-instance lock
per-database lock
```

A stale-lock recovery mechanism MUST exist.

---

# 32. Idempotency Requirements

Every Ansible-backed operation SHOULD remain idempotent.

Repeated execution MUST NOT:

- create duplicate PostgreSQL HBA entries;
- duplicate proxy includes;
- duplicate UFW rules;
- recreate users unnecessarily;
- overwrite valid certificates unexpectedly;
- duplicate cron jobs/systemd timers;
- duplicate monitoring targets;
- generate a new database password unintentionally.

Idempotency SHOULD be tested.

---

# 33. Destructive Operation Safety

The following actions MUST require explicit confirmation unless `--yes` is supplied:

```text
drop database
delete instance
remove backup
prune backups
restore over existing database
firewall lockdown
SSH access changes that can lock out operators
TLS private-key replacement
full database rollback
```

The confirmation prompt MUST identify the exact target.

Example:

```text
This will DROP database "hmis" on host "postgres".
Type the database name to continue:
```

---

# 34. Secrets and Sensitive Data

The implementation MUST:

- redact passwords from logs;
- redact tokens;
- redact private keys;
- not print vault passwords;
- avoid placing secrets on the process command line where practical;
- use restrictive file permissions;
- not commit generated secret files;
- include secret patterns in `.gitignore` where appropriate.

---

# 35. Backward Compatibility Layer

Existing scripts SHOULD remain functional.

Where replaced, convert them into wrappers.

Example:

```bash
#!/usr/bin/env bash
exec dhis2-instance create "$@"
```

However, wrapper semantics MUST preserve the historical behavior unless explicitly documented otherwise.

Known legacy names and typos SHOULD not be silently removed.

For example, `create-intance.sh` MAY be retained as a deprecated wrapper while introducing a correctly spelled replacement.

Deprecation warnings MUST go to stderr.

---

# 36. Ansible Tag Compatibility

Existing tags MUST be preserved unless there is a strong technical reason to change them.

Current automation relying on tags such as these MUST continue to work where applicable:

```text
postgresql-install
proxy-install
monitoring
create-instance
alerting
backup-script
set-dhis2-url
deploy-war
proxy-conf
tomcat-munin-monitoring
prometheus-connect
delete-instance
```

New CLI operations SHOULD map to canonical playbooks/tags.

Tag renames MUST include aliases or a migration path.

---

# 37. Inventory Compatibility

Existing variables MUST continue to be recognized.

Examples include:

```text
ansible_connection
ansible_host
ansible_user
database_host
dhis2_version
dhis2_war_file
dhis2_auto_upgrade
postgresql_version
server_monitoring
app_monitoring
wireguard_enabled
wireguard_data_plane
lxd_network
lxd_bridge_interface
lxd_storage_driver
guest_os
guest_os_arch
proxy
TLS_TYPE
fqdn
email
timezone
create_db
java_version
unattended_upgrades
```

The implementation MUST avoid unnecessary renames.

If a variable is replaced, the old form SHOULD remain accepted with a deprecation warning.

---

# 38. Error Handling Requirements

Errors MUST be actionable.

Bad:

```text
FAILED
```

Good:

```text
PostgreSQL host "postgres" is unreachable on 172.27.0.52:22.
SSH authentication for user "deploy" failed.
Run:
  dhis2-host ssh-install-key postgres --user deploy
or verify the configured ansible_user.
```

The CLI MUST distinguish:

- invalid configuration;
- unreachable host;
- authentication failure;
- sudo failure;
- application health failure;
- Ansible failure;
- unsupported architecture;
- safety refusal.

---

# 39. Testing Requirements

No pull request should be submitted until automated tests demonstrate the new CLI does not regress the existing implementation.

## 39.1 Test layers

Required:

1. shell/static tests;
2. unit tests;
3. inventory validation tests;
4. CLI parsing tests;
5. Ansible syntax checks;
6. Ansible lint;
7. role-level tests;
8. integration tests;
9. deployment smoke tests;
10. upgrade/restore workflow tests where feasible.

## 39.2 Shell checks

If Bash is used:

```text
shellcheck
bash -n
```

MUST pass for new scripts.

## 39.3 Ansible checks

Required:

```text
ansible-playbook --syntax-check
ansible-lint
yamllint
```

for relevant files.

## 39.4 CLI tests

Each command MUST test:

- `--help`;
- invalid subcommand;
- missing required argument;
- invalid inventory;
- human output;
- JSON output where implemented;
- successful command mapping;
- exit codes.

## 39.5 Deployment matrix

At minimum, CI or documented pre-PR testing MUST cover:

| Architecture | Requirement |
|---|---|
| LXD | Required |
| Distributed SSH | Required |
| Hybrid | Required |
| Multi-instance | Required |
| Multiple connection types | Required |

## 39.6 Proxy matrix

At minimum:

| Proxy | Requirement |
|---|---|
| Nginx | Required |
| Apache2 | Required |
| OpenResty | Required if still officially supported |

## 39.7 TLS matrix

At minimum:

| TLS Mode | Requirement |
|---|---|
| Self-signed | Required |
| Custom SSL | Required |
| Let's Encrypt | Required where test infrastructure permits |

## 39.8 Monitoring

At minimum test the currently default/recommended monitoring path plus syntax/idempotency checks for other supported paths.

## 39.9 Database versions

Tests SHOULD cover the currently supported PostgreSQL version(s), especially PostgreSQL 16 if that remains the default.

---

# 40. Regression Test Scenarios

The following MUST be explicitly tested before the final PR.

## Scenario A — Existing LXD deployment

Using an existing-style inventory:

```bash
sudo ./deploy.sh
```

Expected:

- deployment succeeds;
- no CLI migration required;
- existing URLs work;
- database works;
- monitoring works.

## Scenario B — Existing distributed SSH deployment

Using:

```text
ansible_connection=ssh
```

Expected:

```bash
ansible-playbook dhis2.yml
```

continues to work.

## Scenario C — Hybrid connection inventory

Expected:

- SSH hosts use SSH;
- LXD hosts use LXD;
- CLI does not flatten connection mode.

## Scenario D — Existing tag usage

Expected:

```bash
ansible-playbook dhis2.yml --tags postgresql-install
```

continues to behave as before.

## Scenario E — Existing instance deployment

Existing `create-instance` behavior MUST remain functional.


## Scenario E1 — Existing `dhis.conf` preservation

Given an already deployed DHIS2 instance with a working `dhis.conf`, re-running deployment with preservation enabled MUST:

- leave the existing file content unchanged;
- retain `connection.password`;
- retain `connection.username`;
- retain custom application properties;
- not generate a new database password;
- keep DHIS2 able to connect to PostgreSQL after deployment.

## Scenario E2 — `dhis.conf` merge

Given an existing file containing local overrides, merge mode MUST:

- keep existing local settings;
- add newly required properties;
- update only explicitly overridden values;
- redact secrets from displayed diffs;
- produce a valid resulting configuration.

## Scenario E3 — Explicit `dhis.conf` replacement

Replacement mode MUST:

- back up the current file;
- require explicit operator intent;
- create a valid new file;
- preserve correct ownership/permissions;
- allow recovery from the backup.

## Scenario F — Existing backup workflow

Existing scheduled/manual backups MUST continue to run.

## Scenario G — Existing WireGuard setup

Existing VPN configuration MUST not be broken by CLI introduction.

## Scenario H — Existing monitoring

Monitoring configuration MUST continue to operate.

---

# 41. Restore Test Scenarios

At minimum:

1. restore `.sql`;
2. restore `.sql.gz`;
3. restore custom-format dump;
4. restore to blank database;
5. restore over existing database with explicit confirmation;
6. reassign ownership;
7. reject invalid backup;
8. application health after restore.

---

# 42. Upgrade Test Scenarios

At minimum:

1. valid patch upgrade;
2. backup created;
3. failed WAR download;
4. failed application startup;
5. Flyway error detection;
6. version verification after success;
7. rollback guidance after database migration;
8. no false success when health check fails.

---

# 43. Documentation Requirements

Every command MUST have:

```bash
COMMAND --help
```

Documentation MUST include:

- purpose;
- syntax;
- options;
- examples;
- destructive behavior;
- architecture limitations;
- exit codes where relevant.

Required documentation additions SHOULD include:

```text
docs/CLI.md
docs/CLI-Deployment.md
docs/CLI-Instances.md
docs/CLI-Database.md
docs/CLI-Backup-Restore.md
docs/CLI-Upgrades.md
docs/CLI-Diagnostics.md
docs/CLI-Security.md
docs/Migration-to-CLI.md
docs/Compatibility.md
```

README MUST be updated without removing the existing direct-Ansible instructions immediately.

---

# 44. Packaging Requirements

Provide an installation mechanism.

Recommended:

```bash
sudo ./install.sh
```

or equivalent packaging.

It MUST:

- install into a predictable path;
- create `/usr/local/bin` links;
- not overwrite local inventory;
- preserve configuration;
- be idempotent;
- support uninstall instructions;
- report installed version.

Recommended:

```bash
dhis2-deploy --version
```

Expected:

```text
dhis2-server-tools X.Y.Z
```

---

# 45. Versioning Requirements

The command interface MUST be versioned with the repository release.

Any breaking CLI change after public release MUST follow the project release/versioning policy.

Machine-readable output SHOULD include a schema/version identifier once relied on externally.

---

# 46. CI Requirements

The pull request SHOULD extend the current CI pipeline to include:

```text
shellcheck
bash syntax
pytest
ansible-lint
yamllint
Ansible syntax checks
CLI smoke tests
Molecule tests
```

CI MUST fail on newly introduced lint/syntax/test failures.

Existing CI checks MUST not be weakened simply to make the new implementation pass.

Suppressions MUST be justified inline.

---

# 47. Code Quality Requirements

The implementation MUST:

- use `set -Eeuo pipefail` for production Bash scripts unless a justified exception exists;
- quote shell variables;
- avoid unsafe `eval`;
- avoid parsing command output when structured alternatives exist;
- validate user-supplied paths;
- use `mktemp` for temporary files;
- clean temporary sensitive files;
- use atomic writes for configuration changes;
- include useful function-level comments;
- avoid large duplicated command bodies.

---

# 48. Repository Cleanup Allowed in This PR

Low-risk cleanup MAY be included where directly relevant:

- spelling fixes;
- command wrapper normalization;
- documentation corrections;
- moving duplicated shell helpers into shared libraries;
- consistent executable permissions;
- missing shebangs;
- safe tag/documentation corrections.

Cleanup MUST NOT be mixed with unrelated architectural refactoring that makes regression review difficult.

---

# 49. Changes That Should Be Deferred

Unless independently implemented and tested, defer:

- Docker deployment;
- Kubernetes deployment;
- PostgreSQL HA;
- Patroni;
- multi-primary databases;
- automatic database failover;
- full disaster-recovery orchestration across regions;
- automatic schema-level DHIS2 repair;
- transparent Flyway migration modification;
- unsupported OS families.

These SHOULD be tracked separately rather than partially implemented in the same PR.

---

# 50. Implementation Phases

## Phase 1 — CLI foundation

Implement:

- shared library;
- common options;
- logging;
- inventory loader;
- Ansible execution wrapper;
- locks;
- output helpers;
- installation.

Deliver:

```text
dhis2-status
dhis2-inventory
dhis2-deploy preflight
dhis2-deploy plan
```

## Phase 2 — Deployment and lifecycle

Implement:

```text
dhis2-deploy apply
dhis2-host
dhis2-instance
dhis2-proxy
dhis2-tls
```

## Phase 3 — Database and recovery

Implement:

```text
dhis2-db
dhis2-backup
dhis2-restore
```

## Phase 4 — Upgrades and diagnostics

Implement:

```text
dhis2-upgrade
dhis2-logs
dhis2-doctor
```

## Phase 5 — Supporting services

Implement:

```text
dhis2-monitor
dhis2-security
dhis2-vpn
dhis2-doris
dhis2-integration
dhis2-vault
```

## Phase 6 — Hardening

Complete:

- regression suite;
- compatibility tests;
- documentation;
- shellcheck;
- lint;
- idempotency verification;
- release notes.

---

# 51. Pull Request Acceptance Criteria

The final PR MUST NOT be considered ready until all mandatory criteria below are satisfied.

## Functional

- [ ] `dhis2-*` command suite installed successfully.
- [ ] Existing `dhis.conf` can be preserved during redeployment.
- [ ] Existing database passwords are not regenerated or replaced by default.
- [ ] `--merge-dhis-conf` preserves local values and only applies explicit overrides.
- [ ] `--replace-dhis-conf` creates a backup and requires explicit operator intent.
- [ ] LXD deployments work.
- [ ] Distributed SSH deployments work.
- [ ] Hybrid deployments work.
- [ ] Existing direct Ansible deployment remains functional.
- [ ] Existing inventories remain valid.
- [ ] Instance lifecycle works.
- [ ] PostgreSQL administration commands work.
- [ ] Backup commands work.
- [ ] Restore commands work.
- [ ] Upgrade workflow works.
- [ ] Proxy management works.
- [ ] TLS management works.
- [ ] Monitoring commands work.
- [ ] Diagnostics work.
- [ ] Status output works.
- [ ] JSON output is valid where supported.

## Safety

- [ ] Destructive commands require confirmation.
- [ ] Secrets are redacted.
- [ ] Restore validates backup before destructive action.
- [ ] Upgrade creates/verifies backup before migration.
- [ ] Inventory writes are atomic.
- [ ] Concurrency locks exist.
- [ ] Proxy configuration is tested before reload.
- [ ] Unsupported architectures are not advertised as supported.

## Compatibility

- [ ] `deploy/deploy.sh` still works.
- [ ] `deploy/dhis2.yml` still works directly.
- [ ] existing tags still work.
- [ ] existing variables still work.
- [ ] current inventory format still works.
- [ ] existing backup role still works.
- [ ] WireGuard behavior is preserved.
- [ ] monitoring behavior is preserved.
- [ ] Doris behavior is not regressed.
- [ ] integration role behavior is preserved.

## Quality

- [ ] shellcheck passes.
- [ ] Bash syntax checks pass.
- [ ] pytest passes.
- [ ] ansible-lint passes.
- [ ] yamllint passes.
- [ ] Ansible syntax checks pass.
- [ ] Molecule tests pass where applicable.
- [ ] new CLI tests pass.
- [ ] no disabled existing tests without justification.
- [ ] documentation updated.
- [ ] changelog/release notes included.

---

# 52. Required Pre-PR Manual Validation

Before opening the final upstream PR, run a complete validation on real or representative infrastructure.

Recommended matrix:

```text
Environment 1:
  Single physical host
  LXD
  proxy + postgres + hmis + monitor

Environment 2:
  Deployment/controller VM
  proxy VM
  DHIS2 VM
  PostgreSQL VM
  monitor VM
  ansible_connection=ssh

Environment 3:
  Hybrid
  PostgreSQL over SSH
  DHIS2/proxy using LXD
  monitoring over SSH
```

For each environment validate:

```text
deploy
redeploy
status
doctor
instance restart
backup
backup verification
restore test
proxy test/reload
TLS status
database status
logs
monitoring
upgrade where safe
```

Repeated deployment MUST show expected Ansible idempotency.

---

# 53. Required No-Regression Evidence in the PR Description

The final PR description SHOULD include a compatibility table such as:

| Existing Function | Before PR | After PR | Regression |
|---|---:|---:|---:|
| LXD deployment | PASS | PASS | None |
| SSH deployment | PASS | PASS | None |
| Hybrid deployment | PASS | PASS | None |
| PostgreSQL install | PASS | PASS | None |
| DHIS2 instance install | PASS | PASS | None |
| Nginx proxy | PASS | PASS | None |
| Apache2 proxy | PASS | PASS | None |
| OpenResty | PASS | PASS | None |
| Backup | PASS | PASS | None |
| Monitoring | PASS | PASS | None |
| WireGuard | PASS | PASS | None |
| Doris | PASS | PASS | None |
| Integration | PASS | PASS | None |

Attach or summarize test logs without exposing secrets.

---

# 54. Pull Request Structure Recommendation

To make upstream review manageable, the fork MAY use multiple internal commits while ultimately presenting one complete PR.

Recommended commit grouping:

```text
1. cli: add shared command runtime and installer
2. inventory: add safe inventory management and validation
3. deploy: add architecture-aware deploy commands
4. instance: add lifecycle management
5. postgres: add database administration command
6. backup: add backup management
7. restore: add safe database restore orchestration
8. upgrade: add controlled upgrade workflow
9. proxy/tls: add operational commands
10. diagnostics: add logs, status and doctor
11. services: add monitor/vpn/doris/integration/vault commands
12. tests: add regression and CLI coverage
13. docs: add CLI and migration documentation
```

Avoid one unreviewable monolithic commit.

---

# 55. Definition of Done

The implementation is complete only when:

1. every in-scope top-level command is implemented or explicitly marked unsupported with documented reason;
2. existing Ansible workflows continue to operate;
3. LXD, SSH, and hybrid deployments have been validated;
4. no destructive action can occur accidentally through default CLI behavior;
5. backup and restore are production-safe;
6. upgrades include backup, migration monitoring, and post-upgrade verification;
7. diagnostics identify the most common DHIS2, Tomcat, PostgreSQL, proxy, connectivity, memory, and monitoring failures;
8. security-sensitive values are protected;
9. automated tests cover new functionality and legacy compatibility;
10. documentation is complete;
11. CI passes;
12. manual regression testing passes;
13. release notes clearly identify additions, compatibility behavior, and known limitations;
14. Docker and Kubernetes are not represented as supported unless actually implemented and tested;
15. configuration-only deployments do not unnecessarily redeploy the WAR or restart unaffected services;
16. existing `dhis.conf` and PostgreSQL custom configuration can be safely preserved;
17. multi-instance operations are scoped so one instance does not unnecessarily disrupt another;
18. proxy/TLS changes preserve last-known-good configurations until validation succeeds;
19. support bundles and configuration diffs redact secrets;
20. the final upstream pull request can reasonably demonstrate **no known regression** across the currently supported deployment architectures and core roles.

---



# 57. Additional Command Gap Analysis and Required Enhancements

The following gaps were identified after reviewing the current deployment roles, operational documentation, service-management documentation, LXD administration documentation, PostgreSQL implementation, WAR deployment workflow, monitoring, alerting, and WireGuard implementation.

These requirements extend the command families defined earlier in this document. They are intended to close operational gaps without replacing or regressing existing Ansible behavior.

---

## 57.1 `dhis2-deploy` — Additional Gaps

The deployment command requires stronger protection against unintended application, configuration, package, and service changes during routine re-runs.

### Additional required subcommands/options

```text
dhis2-deploy show
dhis2-deploy diff
dhis2-deploy snapshot
dhis2-deploy validate
dhis2-deploy components
dhis2-deploy history
dhis2-deploy resume
```

Recommended execution selectors:

```text
--only COMPONENT
--skip COMPONENT
--limit HOST_OR_GROUP
--preserve-dhis-conf
--merge-dhis-conf
--replace-dhis-conf
--preserve-postgres-conf
--allow-package-upgrades
--no-package-upgrades
--skip-war-deploy
--skip-restart
```

### Deployment configuration drift

`dhis2-deploy diff` MUST be able to compare, where practical:

```text
inventory desired values
current dhis.conf
current PostgreSQL DHIS2 configuration
proxy configuration
Tomcat configuration
monitoring configuration
TLS mode/certificate identity
deployed DHIS2 version
configured DHIS2 version
```

Secret values MUST be redacted.

The command SHOULD classify changes as:

```text
SAFE
RESTART REQUIRED
SERVICE INTERRUPTION
DESTRUCTIVE
SECRET CHANGE
UNKNOWN
```

### Deployment snapshot

Before a materially mutating deployment, the implementation SHOULD be able to create an operational snapshot containing:

```text
inventory copy
selected host_vars/group_vars
dhis.conf metadata or encrypted/protected copy
PostgreSQL DHIS2 configuration
proxy configuration
Tomcat overrides
currently deployed DHIS2 version
Java version
PostgreSQL version
service states
TLS certificate metadata
```

Sensitive files MUST retain restrictive permissions.

### Component-level execution

Operators MUST be able to deploy or reconcile one component without unnecessarily touching unrelated services.

Examples:

```bash
dhis2-deploy apply --only database
dhis2-deploy apply --only proxy
dhis2-deploy apply --only monitoring
dhis2-deploy apply --only instance --instance hmis
dhis2-deploy apply --skip monitoring
```

The CLI SHOULD map these to canonical tags/plays rather than introducing duplicate deployment logic.

### Package upgrade safety

The existing PostgreSQL installation tasks include operating-system package upgrade behavior. Routine component reconciliation MUST NOT unexpectedly perform broad package upgrades unless that behavior is explicitly retained as part of an existing legacy path or approved for the requested action.

The new CLI SHOULD provide explicit package-management intent:

```bash
dhis2-deploy apply --no-package-upgrades
dhis2-deploy apply --allow-package-upgrades
```

The default for an already-running production environment SHOULD favor minimizing unrelated package changes.

This MUST be implemented without breaking direct legacy playbook behavior unless the upstream project agrees to change it.

### WAR deployment safety

The current application deployment workflow can remove the exploded Tomcat application directory before extracting a replacement WAR.

The CLI MUST therefore distinguish:

```text
configuration-only deployment
application reconciliation
WAR deployment
DHIS2 version upgrade
```

A configuration-only deployment MUST NOT delete or re-extract the current web application.

Recommended:

```bash
dhis2-deploy apply --skip-war-deploy
dhis2-instance war deploy hmis ...
```

WAR replacement MUST occur only when required by explicit operator intent or validated version/artifact change.

### Service restart control

Deployment MUST identify whether a proposed change requires:

```text
no restart
reload only
application restart
database restart
proxy reload
full host/container restart
```

Recommended:

```bash
dhis2-deploy plan --show-restarts
```

The implementation SHOULD avoid unnecessary restarts.

---

## 57.2 `dhis2-host` — Additional Gaps

Existing documentation leaves several host-level operations to manual `systemctl`, `lxc`, `apt`, networking, and filesystem commands.

Add:

```text
dhis2-host services
dhis2-host ports
dhis2-host disk
dhis2-host memory
dhis2-host cpu
dhis2-host time
dhis2-host updates
dhis2-host reboot-required
dhis2-host reboot
dhis2-host network
dhis2-host listeners
```

### `services`

Must report relevant infrastructure services, including as applicable:

```text
tomcat
postgresql
nginx
apache2
openresty
munin
prometheus
grafana
zabbix
wireguard
alertmanager
integration services
```

It SHOULD provide:

```bash
dhis2-host services status HOST
dhis2-host services restart HOST SERVICE
```

Service restart MUST require explicit target service and host.

### `ports` / `listeners`

Must identify:

```text
listening address
port
process/service
expected exposure
unexpected public exposure
```

This should integrate with `dhis2-security audit`.

### `disk`

Must report:

```text
filesystem capacity
free space
inode use
largest relevant DHIS2/PostgreSQL paths
LXD storage-pool capacity where applicable
```

It SHOULD warn before deployments/upgrades/restores if capacity is below safe thresholds.

### `time`

Must validate:

```text
timezone
NTP synchronization
clock synchronization status
```

Time drift can affect TLS, logs, sessions, distributed systems, and troubleshooting and therefore SHOULD be part of preflight.

### `updates`

Must support a read-only mode:

```bash
dhis2-host updates check
```

Package installation/upgrades MUST remain separate from read-only checks.

### Reboot

`dhis2-host reboot` MUST:

- identify running critical services;
- warn of interruption;
- optionally drain/stop the application cleanly;
- require confirmation;
- wait for host connectivity to return;
- run post-reboot health verification.

---

## 57.3 LXD Management Gap

The repository documents manual LXD administration but the proposed CLI does not yet expose it.

Add an LXD-focused namespace under `dhis2-host` rather than creating another top-level command unless maintainers prefer a dedicated command.

Required:

```text
dhis2-host lxd list
dhis2-host lxd show
dhis2-host lxd start
dhis2-host lxd stop
dhis2-host lxd restart
dhis2-host lxd exec
dhis2-host lxd storage
dhis2-host lxd network
dhis2-host lxd snapshots
```

Recommended:

```text
dhis2-host lxd snapshot
dhis2-host lxd restore-snapshot
```

### Safety

Snapshot support MUST clearly state whether the snapshot includes:

```text
application container filesystem
database container filesystem
database-consistent state
```

A filesystem/container snapshot MUST NOT be presented as a substitute for a validated PostgreSQL logical or physical backup unless database consistency is guaranteed.

---

## 57.4 `dhis2-inventory` — Additional Gaps

Add:

```text
dhis2-inventory lint
dhis2-inventory diff
dhis2-inventory backup
dhis2-inventory restore
dhis2-inventory export
dhis2-inventory resolve
dhis2-inventory template
dhis2-inventory secrets
```

### `resolve`

Must show effective values after considering:

```text
inventory host values
group variables
host variables
defaults
CLI overrides
```

Example:

```bash
dhis2-inventory resolve hmis
```

Sensitive values MUST be redacted.

This is essential for troubleshooting Ansible precedence problems.

### `diff`

Should compare:

```text
current inventory
previous inventory backup
generated/template inventory
```

### `secrets`

Must detect obvious plaintext credentials or secret-like values and recommend supported secure storage.

It MUST NOT print discovered secret values.

---

## 57.5 `dhis2-instance` — Additional Gaps

Add:

```text
dhis2-instance version
dhis2-instance system-info
dhis2-instance config
dhis2-instance war
dhis2-instance jvm
dhis2-instance threads
dhis2-instance resources
dhis2-instance endpoint
dhis2-instance database
dhis2-instance maintenance
```

### Configuration management

Required:

```text
dhis2-instance config show
dhis2-instance config validate
dhis2-instance config diff
dhis2-instance config backup
dhis2-instance config preserve
dhis2-instance config merge
dhis2-instance config replace
```

Secrets MUST be redacted in `show` and `diff`.

### WAR management

Required:

```text
dhis2-instance war status
dhis2-instance war deploy
dhis2-instance war verify
dhis2-instance war backup
dhis2-instance war rollback
```

`war status` SHOULD report:

```text
configured version
running version
artifact path
artifact checksum
artifact timestamp
Tomcat version
Java version
```

`war deploy` MUST NOT be conflated with a full upgrade unless database migrations and upgrade protections are intentionally invoked.

### Application endpoint checks

Add:

```bash
dhis2-instance endpoint check hmis
```

Checks SHOULD distinguish:

```text
TCP reachable
HTTP reachable
HTTP status
redirect behavior
application startup page/API reachable
expected base path
```

### JVM diagnostics

Recommended:

```text
dhis2-instance jvm status
dhis2-instance jvm memory
dhis2-instance threads summary
```

If thread dumps or heap dumps are implemented:

- they MUST be opt-in;
- heap dumps MUST check disk space first;
- heap dumps MAY contain sensitive data and MUST receive restrictive permissions;
- support bundles MUST not include heap dumps by default.

### Maintenance mode

`dhis2-instance maintenance` SHOULD support:

```text
status
enable
disable
```

If maintenance mode is implemented at the proxy layer, the CLI MUST preserve a controlled administrative access path where required and MUST restore the original proxy configuration safely.

---

## 57.6 `dhis2-db` — Additional Gaps

Add:

```text
dhis2-db health
dhis2-db ownership
dhis2-db roles
dhis2-db extensions
dhis2-db hba
dhis2-db bloat
dhis2-db long-running
dhis2-db blocking
dhis2-db transactions
dhis2-db tables
dhis2-db indexes
dhis2-db config diff
dhis2-db config validate
dhis2-db config apply
dhis2-db config reload
dhis2-db config restart
```

### PostgreSQL configuration preservation

The existing PostgreSQL role deliberately avoids forcing replacement of an existing `dhispg.conf`.

The new CLI MUST preserve that no-regression behavior unless the operator explicitly requests a configuration update.

Recommended modes:

```bash
dhis2-db config apply --preserve
dhis2-db config apply --merge
dhis2-db config apply --replace
```

Default for an existing production database SHOULD be `preserve` or `merge`, not unconditional replacement.

### HBA management

Add:

```text
dhis2-db hba show
dhis2-db hba validate
dhis2-db hba add
dhis2-db hba remove
```

Changes MUST:

- create a backup;
- avoid duplicate rules;
- validate target database/user/CIDR;
- reload PostgreSQL only after successful validation.

### Ownership checks

`dhis2-db ownership` SHOULD detect application objects not owned by the expected DHIS2 database owner.

Provide a safe repair plan before any ownership change.

### Extensions

Must report required/installed extensions such as PostGIS where applicable.

The command MUST not automatically remove unknown extensions.

### Bloat and maintenance diagnostics

`bloat`, `tables`, and `indexes` SHOULD help identify:

```text
large tables
large indexes
dead tuples
high bloat candidates
missing recent analyze/vacuum indicators
```

The command MUST make clear where results are estimates.

### Config reload versus restart

The CLI MUST distinguish PostgreSQL settings that can be reloaded from those requiring restart.

A config plan SHOULD state the required action before applying changes.

---

## 57.7 `dhis2-backup` — Additional Gaps

Add:

```text
dhis2-backup manifest
dhis2-backup checksum
dhis2-backup test
dhis2-backup export
dhis2-backup config
dhis2-backup files
dhis2-backup full
```

### Backup manifest

Every backup SHOULD have a manifest containing non-secret metadata such as:

```text
instance
database
database owner
PostgreSQL version
DHIS2 version
backup type
format
compression
timestamp
size
checksum
source host
tool version
```

### Configuration backup

A complete recovery backup SHOULD optionally include:

```text
dhis.conf
Tomcat overrides
proxy configuration
inventory snapshot
PostgreSQL custom config
certificate metadata
application artifact metadata
```

Secret-containing configuration files MUST be protected and SHOULD support encryption.

### Restore test

Recommended:

```bash
dhis2-backup test BACKUP
```

A test SHOULD restore into an isolated temporary database/environment where feasible and perform basic validation.

A checksum-only verification MUST not be described as a full restore test.

### Encryption

If backup encryption is implemented:

- use a documented, standard mechanism;
- do not invent custom cryptography;
- protect key material separately;
- document recovery/key-escrow requirements.

---

## 57.8 `dhis2-restore` — Additional Gaps

Add:

```text
dhis2-restore plan
dhis2-restore ownership
dhis2-restore dry-run
dhis2-restore clone
dhis2-restore config
```

### Restore plan

Before execution, show:

```text
source backup
backup format
source PostgreSQL version where known
target PostgreSQL version
source database
target database
source owner
target owner
estimated disk requirement
application stop requirement
objects to be replaced
ownership action
post-restore validation
```

### Clone

Recommended:

```bash
dhis2-restore clone production training --backup BACKUP
```

Clone MUST make it difficult to accidentally point the cloned instance at production-only integrations or external systems.

The implementation SHOULD support post-clone safety hooks for:

```text
server.base.url
outbound integrations
email
SMS
external APIs
scheduled jobs
```

Any automatic disabling behavior MUST be explicit and documented.

### PostgreSQL version compatibility

Restore MUST validate obvious incompatibilities between dump/restore tools and target PostgreSQL versions.

It MUST use the target-compatible PostgreSQL client tools when required.

### Disk-space validation

The restore command MUST consider:

```text
compressed backup size
estimated expanded data size
temporary space
WAL growth
index creation
```

A simple comparison to compressed backup size is insufficient.

---

## 57.9 `dhis2-upgrade` — Additional Gaps

Add:

```text
dhis2-upgrade stage
dhis2-upgrade precheck
dhis2-upgrade dependencies
dhis2-upgrade artifact
dhis2-upgrade logs
dhis2-upgrade verify
dhis2-upgrade resume
```

### Staging

`stage` SHOULD download and verify the target WAR without modifying the running application.

Example:

```bash
dhis2-upgrade stage hmis --to 2.43.2
```

This allows maintenance windows to begin with required artifacts already available.

### Dependency checks

`dependencies` MUST report compatibility/installed versions for:

```text
Java
Tomcat
PostgreSQL
Ubuntu
PostGIS
```

where the project has a maintained compatibility matrix.

### Upgrade resume

An interrupted upgrade SHOULD write sufficient state to determine:

```text
last completed step
backup path
old artifact path
target artifact path
whether database migration started
current application state
```

`resume` MUST NOT blindly re-run destructive steps.

### Multi-instance environments

Upgrade commands SHOULD support:

```text
one instance
selected instances
serial upgrade
all instances
```

For shared PostgreSQL hosts, resource impact MUST be considered.

Recommended:

```bash
dhis2-upgrade run --all --serial 1
```

### Artifact verification

WAR downloads SHOULD use:

- HTTPS;
- checksum verification when authoritative checksums are available;
- size/non-empty checks at minimum.

The previous working artifact SHOULD be retained until post-upgrade health checks pass.

---

## 57.10 `dhis2-proxy` — Additional Gaps

Add:

```text
dhis2-proxy health
dhis2-proxy listeners
dhis2-proxy certificates
dhis2-proxy logs
dhis2-proxy access
dhis2-proxy maintenance
dhis2-proxy backup
dhis2-proxy diff
```

### Upstream health

Must test each configured DHIS2 upstream directly from the proxy host.

This helps distinguish:

```text
public DNS/TLS failure
proxy failure
upstream network failure
Tomcat/DHIS2 failure
```

### Config backup and atomicity

Before modifying proxy configuration:

- back up affected configuration;
- render/write atomically;
- execute syntax/config test;
- reload only after successful validation;
- roll back if reload fails.

### Maintenance response

If proxy maintenance mode is implemented, it SHOULD support a configurable maintenance response without deleting the original upstream configuration.

---

## 57.11 `dhis2-tls` — Additional Gaps

Add:

```text
dhis2-tls inspect
dhis2-tls chain
dhis2-tls csr
dhis2-tls backup
dhis2-tls expiry
dhis2-tls rotate
```

### Chain validation

`chain` MUST validate:

```text
certificate/private-key match
certificate chain
hostname/SAN
expiry
issuer
```

### CSR generation

If supported:

```bash
dhis2-tls csr INSTANCE --subject ...
```

Private keys MUST be generated with secure permissions and MUST never be printed.

### Rotation

Certificate rotation MUST:

- preserve the previous certificate/key until validation succeeds;
- test proxy configuration;
- reload safely;
- verify HTTPS after reload.

---

## 57.12 `dhis2-monitor` — Additional Gaps

Add:

```text
dhis2-monitor health
dhis2-monitor alerts
dhis2-monitor test-alert
dhis2-monitor silence
dhis2-monitor unsilence
dhis2-monitor retention
dhis2-monitor storage
dhis2-monitor endpoints
```

These operations MUST only be enabled where supported by the configured monitoring/alerting stack.

### Alert testing

`test-alert` SHOULD verify end-to-end routing without exposing credentials.

Possible checks:

```text
Prometheus/monitor source
Alertmanager
configured contact point
Glowroot forwarder where enabled
```

### Alert silence management

If Alertmanager is configured:

```bash
dhis2-monitor silence ...
dhis2-monitor unsilence ...
```

should expose safe operational control.

Silences MUST have:

```text
creator
reason
duration/expiry
target matcher
```

### Monitoring storage

Must report storage growth/capacity for Prometheus/Grafana/Zabbix data where applicable.

---

## 57.13 `dhis2-logs` — Additional Gaps

Add:

```text
dhis2-logs list
dhis2-logs size
dhis2-logs rotate
dhis2-logs bundle
dhis2-logs export
dhis2-logs redact
```

### Diagnostic bundle

`bundle` SHOULD gather selected troubleshooting data into a support archive.

Recommended contents:

```text
service status
recent Tomcat/DHIS2 logs
recent PostgreSQL logs
proxy logs
relevant journal entries
Ansible failure summary
system resource snapshot
network/listener snapshot
configuration metadata
version information
```

By default it MUST NOT include:

```text
database dumps
private keys
vault passwords
raw dhis.conf passwords
alerting tokens
full environment variable dumps containing secrets
heap dumps
```

The bundle MUST perform secret redaction.

---

## 57.14 `dhis2-doctor` — Additional Gaps

Add:

```text
dhis2-doctor config
dhis2-doctor storage
dhis2-doctor services
dhis2-doctor tls
dhis2-doctor backup
dhis2-doctor upgrade-readiness
dhis2-doctor snapshot
dhis2-doctor compare
```

### Configuration consistency checks

`config` SHOULD cross-check:

```text
DHIS2 connection URL
database host
database port
database name
database user
proxy upstream
server.base.url
fqdn
TLS hostname
monitoring target
WireGuard service address where applicable
```

Sensitive credentials MUST only be checked for consistency, never displayed.

### Upgrade readiness

`upgrade-readiness` SHOULD combine:

```text
backup recency/validity
disk capacity
database health
application health
dependency versions
target artifact availability
configuration preservation mode
known restart requirements
```

### Snapshot/compare

A doctor snapshot SHOULD allow comparison of operational state before and after:

```text
deployment
upgrade
restore
configuration change
incident
```

Comparison MUST focus on operational metadata and avoid leaking secrets.

---

## 57.15 `dhis2-status` — Additional Gaps

Add options:

```text
--watch
--details
--services
--resources
--versions
--health-only
```

Recommended:

```bash
dhis2-status --watch 5
```

The implementation MUST avoid creating heavy database/API load in watch mode.

---

## 57.16 `dhis2-security` — Additional Gaps

Add:

```text
dhis2-security ports
dhis2-security tls
dhis2-security database
dhis2-security config
dhis2-security packages
dhis2-security report
```

### Public exposure checks

Must identify when infrastructure services are listening beyond intended networks.

Examples:

```text
PostgreSQL
Prometheus
Grafana
Munin
Glowroot
Alertmanager/forwarder
Doris administrative endpoints
```

The tool MUST understand intentional public DHIS2 HTTP/HTTPS exposure versus infrastructure service exposure.

### Configuration permissions

Must validate permissions/ownership for:

```text
dhis.conf
PostgreSQL credential files
TLS private keys
WireGuard private keys
alerting secrets
backup credentials
vault-related files
```

### Security reports

Recommended:

```bash
dhis2-security report --json
```

Findings SHOULD use severity levels:

```text
INFO
LOW
MEDIUM
HIGH
CRITICAL
```

Severity definitions MUST be documented.

---

## 57.17 `dhis2-vpn` — Additional Gaps

Add:

```text
dhis2-vpn handshake
dhis2-vpn config
dhis2-vpn export-peer
dhis2-vpn revoke-peer
dhis2-vpn routes
dhis2-vpn firewall
dhis2-vpn data-plane
```

### Peer export

Human peer configuration contains private key material.

Export MUST:

- require explicit peer name;
- use restrictive file permissions;
- avoid logging file contents;
- warn that possession grants VPN access.

### Revoke

Revocation MUST remove the peer from the hub and safely reload WireGuard.

### Data-plane verification

Where `wireguard_data_plane` is enabled, the CLI MUST verify that application-to-database/service traffic actually resolves/routes over the intended WireGuard address rather than merely checking that the tunnel exists.

---

## 57.18 `dhis2-doris` — Additional Gaps

Add:

```text
dhis2-doris version
dhis2-doris resources
dhis2-doris frontend
dhis2-doris backend
dhis2-doris catalogs
dhis2-doris connectivity
dhis2-doris logs
```

### PostgreSQL catalog/bridge validation

The command SHOULD determine and report whether a configured PostgreSQL catalog is:

```text
external/federated access
materialized/imported data
another configured integration mode
```

It MUST not inaccurately describe a JDBC catalog as copying all source PostgreSQL data when it is functioning as an external catalog/bridge.

---

## 57.19 `dhis2-integration` — Additional Gaps

Add:

```text
dhis2-integration logs
dhis2-integration health
dhis2-integration config
dhis2-integration enable
dhis2-integration disable
dhis2-integration test
```

Integration service definitions SHOULD expose common metadata:

```text
service name
systemd service
listen port
target DHIS2 instance
configuration path
health check
log source
secret references
```

Removing an integration MUST NOT delete application data or credentials unless explicitly requested.

---

## 57.20 `dhis2-vault` — Additional Gaps

Add:

```text
dhis2-vault list
dhis2-vault validate
dhis2-vault rotate
dhis2-vault permissions
dhis2-vault references
```

### Secret references

`references` SHOULD report where a logical secret is consumed without revealing its value.

Example:

```text
database:hmis
  used by:
    PostgreSQL role
    hmis dhis.conf
    backup configuration
```

### Rotation

Secret rotation MUST be transactional where multiple components share a credential.

For example, database password rotation MUST coordinate:

1. protected new secret creation;
2. PostgreSQL role update;
3. `dhis.conf` update;
4. application restart/reconnect;
5. validation;
6. rollback procedure if validation fails.

It MUST NOT rotate only one side of a shared credential.

---

# 58. New Cross-Cutting Requirement — Configuration Drift Management

The toolset SHOULD provide a consistent concept of:

```text
desired configuration
observed configuration
drift
```

At minimum, drift detection SHOULD cover:

```text
dhis.conf
PostgreSQL DHIS2 configuration
Tomcat overrides
proxy configuration
inventory-defined service endpoints
TLS identity
deployed DHIS2 version
Java version
PostgreSQL version
```

Drift detection MUST be read-only.

A drift report SHOULD state whether the source of truth is:

```text
inventory
managed template
existing preserved configuration
operator-managed external configuration
```

The tool MUST NOT overwrite operator-managed configuration solely because drift was detected.

---

# 59. New Cross-Cutting Requirement — Change Planning

Every high-impact mutating command SHOULD support a planning phase.

Examples:

```bash
dhis2-deploy plan
dhis2-db config diff
dhis2-restore plan
dhis2-upgrade plan
dhis2-proxy diff
dhis2-instance config diff
```

Plans SHOULD show:

```text
files changed
services restarted/reloaded
database actions
network/firewall changes
configuration values changed, with secrets redacted
estimated interruption
backup/snapshot actions
rollback capability
```

---

# 60. New Cross-Cutting Requirement — Operational State Capture

Before high-risk operations, the CLI SHOULD capture:

```text
service states
versions
health state
database connectivity
application endpoint state
available disk/memory
current configuration checksums
```

After the operation, the same checks SHOULD be repeated and compared.

This applies especially to:

```text
deploy
restore
upgrade
database configuration change
proxy/TLS change
VPN lockdown
host reboot
```

---

# 61. New Cross-Cutting Requirement — Restart Minimization

The tool MUST distinguish between:

```text
no action
reload
restart
reboot
```

and use the least disruptive action sufficient for the requested change.

Examples:

- valid Nginx configuration change -> reload;
- reloadable PostgreSQL parameter -> reload;
- non-reloadable PostgreSQL parameter -> restart after warning/approval;
- unchanged `dhis.conf` -> no Tomcat restart solely because the deployment command ran.

Unnecessary service interruption MUST be considered a regression.

---

# 62. New Cross-Cutting Requirement — Multi-Instance Safety

Where multiple DHIS2 instances share:

```text
one PostgreSQL host
one proxy
one monitoring server
one LXD host
```

operations targeting one instance MUST avoid disrupting unrelated instances.

Examples:

- restarting `hmis` MUST NOT restart `training`;
- deleting one proxy route MUST NOT remove other upstreams;
- restoring one database MUST NOT terminate sessions for unrelated databases unless unavoidable and explicitly reported;
- upgrading one instance MUST not replace another instance's WAR;
- config changes must be scoped appropriately.

This MUST be included in regression testing.

---

# 63. New Cross-Cutting Requirement — Generated File Ownership and Permissions

Every generated or modified file MUST have explicit expected ownership and mode.

At minimum this applies to:

```text
dhis.conf
database credential files
backup credentials
TLS private keys
WireGuard private keys/client configs
alerting secrets
inventory
vault password references
diagnostic bundles
temporary restore files
```

Tests SHOULD verify permissions for sensitive files.

---

# 64. New Cross-Cutting Requirement — Temporary File Safety

Temporary files containing secrets or configuration MUST:

- be created with `mktemp` or equivalent safe facility;
- have restrictive permissions before content is written;
- be deleted on success/failure using traps/finalizers;
- not be stored under predictable world-readable locations;
- not be left behind after interrupted operations where reasonably avoidable.

---

# 65. New Cross-Cutting Requirement — Service Discovery

The CLI SHOULD discover deployed service names rather than hardcode historical assumptions where possible.

For example, Tomcat may vary by supported DHIS2/Ubuntu combination.

The CLI SHOULD resolve:

```text
Tomcat service/version
PostgreSQL cluster/version
proxy service
monitoring service
```

from inventory and observed state.

Hardcoding `tomcat9` in the operator-facing CLI MUST be avoided where the deployment supports other Tomcat versions.

---

# 66. New Cross-Cutting Requirement — Dependency and Compatibility Matrix

A maintained compatibility source SHOULD define supported combinations of:

```text
DHIS2
Java
Tomcat
PostgreSQL
PostGIS
Ubuntu
architecture
```

Commands that depend on compatibility MUST read from the same source rather than embedding different rules in multiple scripts.

Applicable commands:

```text
dhis2-deploy preflight
dhis2-instance create
dhis2-upgrade compatibility
dhis2-doctor upgrade-readiness
```

---

# 67. New Cross-Cutting Requirement — Support Bundle

A standardized troubleshooting bundle SHOULD be available through:

```bash
dhis2-doctor bundle
```

or:

```bash
dhis2-logs bundle
```

The bundle SHOULD include a manifest describing:

```text
collection timestamp
tool version
inventory/environment identifier
hosts queried
files/commands collected
redaction status
failed collection steps
```

The tool MUST clearly warn operators to review the bundle before sharing externally.

---

# 68. New Cross-Cutting Requirement — Recovery Artifacts

Before replacing important configuration or application artifacts, maintain recoverable copies.

At minimum:

```text
dhis.conf
PostgreSQL DHIS2 config
pg_hba.conf changes
proxy configuration
Tomcat overrides
WAR artifact
TLS certificate/key pair
inventory
```

Retention policy MUST prevent unbounded accumulation.

Recovery artifacts containing secrets MUST be protected.

---

# 69. Additional Regression Scenarios

The following scenarios MUST be added to the no-regression test plan.

## Scenario I — Configuration-only deployment

Given a healthy existing DHIS2 instance:

```bash
dhis2-deploy apply --skip-war-deploy --preserve-dhis-conf
```

MUST NOT:

- remove the exploded application;
- replace the WAR;
- regenerate the database password;
- alter `dhis.conf`;
- unnecessarily restart Tomcat.

## Scenario J — PostgreSQL custom configuration preservation

Given an operator-maintained existing `dhispg.conf`, a normal deployment MUST NOT overwrite it unless explicit merge/replace behavior is requested.

## Scenario K — Shared proxy multi-instance safety

Removing or changing one instance route MUST leave all unrelated instance routes operational.

## Scenario L — Shared PostgreSQL multi-instance safety

A maintenance operation on one DHIS2 database MUST not terminate or alter unrelated instance databases by default.

## Scenario M — No-op idempotent deployment

Running the same desired configuration twice SHOULD result in no material changes on the second run.

No unnecessary:

```text
password rotation
WAR extraction
service restart
proxy reload
database restart
firewall duplication
```

should occur.

## Scenario N — Failed proxy configuration

A generated invalid proxy configuration MUST fail syntax validation and MUST NOT replace/reload the last-known-good active configuration.

## Scenario O — Failed TLS replacement

If a new certificate does not match the private key or hostname, the active valid certificate MUST remain in use.

## Scenario P — Interrupted upgrade

An interrupted upgrade MUST retain enough state to report whether:

```text
backup completed
WAR changed
database migration started
application restarted
health validation completed
```

and MUST not falsely report success.

## Scenario Q — Insufficient restore disk

Restore MUST fail before destructive replacement if required capacity is clearly insufficient.

## Scenario R — Secret redaction

Human output, JSON output, logs, diffs, and support bundles MUST not reveal configured passwords/tokens/private keys.

## Scenario S — LXD snapshot warning

A container snapshot MUST not be represented as a verified database backup unless database-consistency guarantees are explicitly met.

## Scenario T — Package upgrade isolation

A routine instance configuration operation MUST not unexpectedly trigger unrelated OS package upgrades under the new CLI's safe production mode.

---

# 70. Updated Command Coverage Matrix

The implementation SHOULD ultimately provide the following coverage.

| Command | Core responsibilities |
|---|---|
| `dhis2-deploy` | initialize, preflight, plan, diff, apply, verify, snapshot, history, resume |
| `dhis2-host` | bootstrap, SSH, sudo, services, resources, networking, updates, reboot, LXD |
| `dhis2-inventory` | validate, lint, resolve, mutate, diff, backup/restore, secret detection |
| `dhis2-instance` | lifecycle, health, config, WAR, JVM, endpoint, maintenance |
| `dhis2-db` | lifecycle, activity, locks, tuning, config, HBA, roles, ownership, bloat |
| `dhis2-backup` | database/files/full backup, verify, manifest, checksum, retention, test |
| `dhis2-restore` | plan, validate, restore, ownership, clone, post-restore verification |
| `dhis2-upgrade` | releases, compatibility, staging, backup, execution, resume, rollback |
| `dhis2-proxy` | routes, config, diff, health, maintenance, logs, safe reload |
| `dhis2-tls` | inspect, verify, issue, CSR, install, renew, rotate, expiry |
| `dhis2-monitor` | health, targets, exporters, dashboards, alerts, silences, storage |
| `dhis2-logs` | query, follow, size, rotation, export, redacted diagnostic bundle |
| `dhis2-doctor` | cross-stack diagnostics, readiness, snapshots, comparison, bundle |
| `dhis2-status` | concise environment health/status overview |
| `dhis2-security` | exposure, permissions, secrets, TLS, packages, security report |
| `dhis2-vpn` | peers, handshakes, export/revoke, routes, lockdown, data plane |
| `dhis2-doris` | installation, health, FE/BE, resources, catalogs, PostgreSQL connectivity |
| `dhis2-integration` | lifecycle, config, health, test, logs |
| `dhis2-vault` | secret storage, validation, references, permissions, coordinated rotation |

---

# 71. Additional Pull Request Acceptance Criteria

Add the following mandatory checks before the complete PR is submitted:

## Configuration preservation

- [ ] Existing `dhis.conf` is preserved by safe redeployment mode.
- [ ] Existing PostgreSQL `dhispg.conf` is not overwritten unexpectedly.
- [ ] Existing database credentials remain stable.
- [ ] Configuration-only deployment does not redeploy the WAR.
- [ ] No-op deployment does not unnecessarily restart services.
- [ ] Config diffs redact secrets.

## Application deployment

- [ ] WAR deployment is explicitly scoped.
- [ ] Existing working WAR is retained for recovery until verification succeeds.
- [ ] Version/artifact checksum can be inspected.
- [ ] Failed WAR deployment does not report success.

## Host/LXD

- [ ] Host resource and service checks work for LXD and SSH deployments.
- [ ] LXD container operations target only the requested container.
- [ ] LXD snapshots are not misrepresented as validated database backups.
- [ ] Reboot workflow performs post-reboot verification.

## PostgreSQL

- [ ] Config reload/restart requirements are correctly distinguished.
- [ ] HBA changes are backed up and validated.
- [ ] Ownership checks work.
- [ ] Multi-database hosts are handled safely.
- [ ] Memory/capacity diagnostics account for cgroup/container limits.

## Proxy/TLS

- [ ] Proxy config is tested before reload.
- [ ] Last-known-good proxy config is recoverable.
- [ ] TLS certificate/key matching is validated before activation.
- [ ] Failed certificate rotation leaves the previous valid certificate active.

## Monitoring/alerts

- [ ] Configured monitoring stack is detected correctly.
- [ ] Alert testing does not disclose credentials.
- [ ] Alert silences have explicit reason and expiry where supported.

## Diagnostics

- [ ] Support bundle redacts sensitive data.
- [ ] `dhis2-doctor` checks configuration consistency.
- [ ] Upgrade-readiness identifies backup, disk, health, and dependency problems.
- [ ] Snapshot/compare can identify meaningful before/after state changes.

## Multi-instance

- [ ] Instance-specific operations do not disrupt unrelated instances.
- [ ] Shared proxy operations preserve other routes.
- [ ] Shared PostgreSQL operations preserve unrelated databases/connections where possible.
- [ ] Monitoring updates preserve unrelated targets.

---

# 72. Documentation Update Requirements for the New Gaps

The final documentation MUST include a command reference that documents every supported subcommand identified in Sections 57–71.

In addition to the documentation files already required, add or expand:

```text
docs/CLI-Configuration-Preservation.md
docs/CLI-Host-and-LXD.md
docs/CLI-PostgreSQL-Operations.md
docs/CLI-WAR-Management.md
docs/CLI-Multi-Instance-Safety.md
docs/CLI-Diagnostic-Bundles.md
docs/CLI-Change-Planning.md
```

Every command page SHOULD show:

```text
Purpose
Syntax
Required arguments
Optional arguments
Read-only versus mutating behavior
Services/files affected
Restart/reload behavior
Backup/recovery behavior
Examples
Exit codes
Architecture limitations
Security considerations
No-regression considerations
```

The documentation MUST explicitly explain that:

1. normal redeployment can preserve `dhis.conf`;
2. database passwords are not regenerated by default;
3. PostgreSQL custom configuration is preserved unless explicitly changed;
4. configuration-only deployment does not need to redeploy the WAR;
5. LXD snapshots are not automatically equivalent to database backups;
6. direct Ansible workflows remain supported;
7. safe CLI modes are intended to reduce unintended production changes.




# 73. Existing/Older Database Detection and Controlled Automatic DHIS2 Database Upgrade

## 73.1 Current behavior and gap

The existing deployment implementation determines the running DHIS2 application version from the deployed application artifact and can automatically deploy a newer DHIS2 WAR when `dhis2_auto_upgrade=true`.

However, this is not sufficient to safely handle the following operational case:

```text
1. An existing or restored DHIS2 PostgreSQL database is older than the target DHIS2 application version.
2. `dhis.conf` is pointed at that database.
3. `deploy.sh` or the new deployment CLI is executed.
4. The new application starts.
5. DHIS2/Flyway automatically attempts database migrations during application startup.
```

Although DHIS2 is expected to execute its schema migrations when starting against an older compatible database, the deployment tooling currently does not provide a complete controlled workflow that:

- identifies the database as an existing/older DHIS2 database;
- determines the apparent schema/application lineage where possible;
- confirms the requested target DHIS2 version;
- creates and verifies a pre-migration backup;
- validates free storage;
- validates PostgreSQL/Java/Tomcat compatibility;
- blocks unsupported or suspicious upgrade jumps;
- records whether Flyway migration actually started;
- monitors migration completion;
- distinguishes an ordinary redeploy from a database-changing upgrade;
- provides safe failure and restore guidance.

Therefore, **simply pointing to an old database and running `deploy.sh` MUST NOT be treated as a sufficiently safe automatic upgrade procedure.**

The new CLI MUST add explicit controls.

---

## 73.2 Database upgrade policy

The deployment framework MUST introduce a database migration policy.

Recommended variable:

```yaml
dhis2_database_upgrade_mode: detect
```

Supported values:

```text
refuse
detect
prompt
auto
force
```

### `refuse`

The application MUST NOT be started with a database that appears to require migration.

The tool MUST stop before WAR activation/application startup and report:

```text
Database migration required.
Current/observed database lineage: <value or unknown>
Target DHIS2 version: <target>
Database migration policy: REFUSE
```

This is the safest production mode.

### `detect`

The tool MUST inspect the database and application state.

If no migration appears necessary, deployment may continue.

If a migration may be required, the command MUST stop and provide a migration/upgrade plan unless an explicit upgrade command or override is supplied.

This SHOULD be the recommended default for production through the new CLI.

### `prompt`

The tool MUST detect the condition, generate the upgrade plan, and request explicit operator approval before proceeding.

### `auto`

The tool MAY automatically proceed only after all mandatory safety gates pass.

`auto` MUST NOT mean "start the application and hope Flyway succeeds."

It MUST perform the full controlled upgrade workflow defined below.

### `force`

This is a break-glass mode.

It MAY bypass selected detection or compatibility blocks but MUST:

- require an explicit flag;
- display a strong warning;
- require `--yes` or interactive confirmation;
- still create a backup unless separately overridden with an even more explicit unsafe flag;
- log the override;
- never be the default.

---

# 74. Database Upgrade Detection Requirements

The tool SHOULD inspect multiple signals because no single indicator may be reliable across all historical DHIS2 versions.

Potential detection sources include:

```text
Flyway schema history
DHIS2 application/schema metadata
known migration table state
database object/version markers
currently running application version, if available
backup manifest metadata, if the database came from dhis2-backup
operator-provided source version
```

The implementation MUST NOT fabricate a precise source DHIS2 version when it cannot be determined reliably.

It SHOULD report:

```text
Source DHIS2 version: 2.40.x       [CONFIRMED]
```

or:

```text
Source DHIS2 version: approximately 2.40 lineage [INFERRED]
```

or:

```text
Source DHIS2 version: UNKNOWN
```

Unknown source version MUST trigger additional caution.

---

# 75. New `dhis2-deploy` Database Upgrade Options

Add the following options:

```text
--database-upgrade-mode refuse|detect|prompt|auto|force
--allow-db-migrations
--no-db-migrations
--source-dhis2-version VERSION
--target-dhis2-version VERSION
--backup-before-migration
--no-backup-before-migration
--verify-backup
--migration-timeout DURATION
--monitor-migrations
--restore-on-failure
```

Recommended production examples:

```bash
dhis2-deploy apply \
  --instance hmis \
  --database-upgrade-mode detect
```

Controlled automatic upgrade:

```bash
dhis2-deploy apply \
  --instance hmis \
  --database-upgrade-mode auto \
  --backup-before-migration \
  --verify-backup
```

Explicitly prohibit migrations:

```bash
dhis2-deploy apply \
  --instance hmis \
  --no-db-migrations
```

---

# 76. New `dhis2-upgrade database` Workflow

A dedicated database-aware upgrade command MUST be provided.

Recommended syntax:

```bash
dhis2-upgrade database hmis --to 2.43.2
```

or:

```bash
dhis2-upgrade run hmis --to 2.43.2 --include-database
```

The workflow MUST perform the following stages.

## Stage 1 — Resolve target

Determine:

```text
instance
database host
database name
database owner
current WAR/application version
target DHIS2 version
Java version
Tomcat version
PostgreSQL version
```

## Stage 2 — Inspect database

Determine where possible:

```text
database exists
database size
current connection activity
source DHIS2/schema lineage
Flyway history state
failed/incomplete Flyway entries
required extensions
database ownership
```

## Stage 3 — Compatibility

Validate:

```text
source → target DHIS2 upgrade path
target Java compatibility
target Tomcat compatibility
PostgreSQL compatibility
PostGIS compatibility
OS support
```

If the project cannot authoritatively validate a particular historical upgrade path, it MUST state that limitation and require explicit operator approval rather than assume safety.

## Stage 4 — Capacity

Validate:

```text
database host free disk
backup destination free disk
temporary space
expected migration/index/WAL headroom
application host free disk
```

## Stage 5 — Backup

Unless explicitly disabled in a break-glass mode:

```text
create pre-upgrade database backup
create backup manifest
calculate checksum
verify backup format
record backup path
```

For production automatic upgrade, backup verification MUST be mandatory.

## Stage 6 — Configuration

Validate:

```text
dhis.conf points to intended database
connection.username
database ownership
target server.base.url
preserved database password
```

The upgrade MUST NOT generate a new database password merely because an older database has been attached.

## Stage 7 — Maintenance

Optionally:

```text
enable maintenance mode
stop application
prevent new writes
terminate only necessary target-database sessions
```

## Stage 8 — Stage WAR

Download/copy and verify target WAR without yet declaring success.

## Stage 9 — Start migration

Start the target DHIS2 application in a controlled manner.

Record that database migration has started.

## Stage 10 — Monitor

Monitor:

```text
Tomcat startup
DHIS2 startup
Flyway execution
migration errors
database errors
OOM
disk exhaustion
application health
```

The command MUST NOT rely solely on `systemctl active`.

## Stage 11 — Verify

After startup:

```text
confirm application responds
confirm running DHIS2 version
confirm expected database connectivity
check Flyway history for failure
check application logs for fatal startup errors
check proxy endpoint
```

## Stage 12 — Finish

Disable maintenance mode and record:

```text
source version/lineage
target version
backup path
migration duration
result
warnings
```

---

# 77. `deploy.sh` Compatibility and Upgrade Safety

The legacy `deploy.sh` MUST remain supported.

However, because it is a broad legacy deployment entry point, the implementation SHOULD add safe compatibility options without breaking current invocation.

Recommended:

```bash
sudo ./deploy.sh
```

continues to behave as documented for legacy users.

Additional flags SHOULD be introduced:

```bash
sudo ./deploy.sh --database-upgrade-mode detect
sudo ./deploy.sh --database-upgrade-mode auto
sudo ./deploy.sh --no-db-migrations
sudo ./deploy.sh --preserve-dhis-conf
sudo ./deploy.sh --skip-war-deploy
```

The script SHOULD pass these options into the same shared implementation used by `dhis2-deploy`.

The implementation SHOULD avoid maintaining two separate upgrade engines.

Eventually:

```text
deploy.sh
```

may become a compatibility wrapper around:

```text
dhis2-deploy apply
```

while preserving historical behavior.

---

# 78. New Database Attachment Workflow

A distinct operation SHOULD be provided for attaching an existing DHIS2 database to an instance.

Recommended:

```bash
dhis2-instance database attach hmis \
  --database hmiscurrent \
  --host postgres
```

Options:

```text
--owner
--preserve-credentials
--source-dhis2-version
--upgrade-mode
--read-only-check
```

Recommended workflow:

```bash
dhis2-instance database inspect hmiscurrent --host postgres

dhis2-instance database attach hmis \
  --database hmiscurrent \
  --host postgres \
  --upgrade-mode detect
```

The attach command MUST:

- verify the database exists;
- verify the configured owner/user;
- preserve existing credentials unless explicitly changed;
- test connectivity;
- determine whether migration may be required;
- NOT immediately start a newer application against the database if migration policy blocks it.

This makes attaching/restoring an old database a deliberate operation instead of a hidden side effect of editing `dhis.conf`.

---

# 79. Failed Migration Handling

A failed migration MUST be treated as a first-class failure state.

The CLI MUST record:

```text
backup path
target WAR
old WAR
migration start time
last observed Flyway migration
Tomcat status
database status
relevant log locations
```

The command MUST NOT automatically attempt arbitrary SQL repairs.

It SHOULD offer safe next actions such as:

```text
inspect logs
inspect Flyway history
restore pre-upgrade database
restore previous application artifact
leave failed environment stopped for investigation
```

Automatic database restore on failure MAY be supported only if:

- the pre-upgrade backup was successfully verified;
- no ambiguity exists about the target database;
- operator explicitly enabled the behavior.

Recommended:

```bash
dhis2-upgrade database hmis \
  --to 2.43.2 \
  --restore-on-failure
```

For production, automatic restore SHOULD remain opt-in.

---

# 80. Database Upgrade Regression Scenarios

Add the following tests.

## Scenario U — Old database attached, migrations refused

Given:

```text
target application = newer DHIS2
database = older DHIS2 schema
mode = refuse
```

Expected:

- application is not started against the database;
- database is not modified;
- operator receives a clear upgrade requirement.

## Scenario V — Old database detection

In `detect` mode:

- source lineage is inspected;
- backup is not automatically created unless upgrade starts;
- upgrade plan is shown;
- database remains unchanged.

## Scenario W — Controlled automatic migration

In `auto` mode:

- compatibility passes;
- capacity passes;
- backup is created;
- backup is verified;
- application starts;
- Flyway is monitored;
- final version/health is verified.

## Scenario X — Failed migration

On migration failure:

- command exits non-zero;
- success is not reported;
- backup path is displayed;
- old artifact remains available;
- recovery steps are produced;
- unrelated databases are untouched.

## Scenario Y — Existing database credentials

Attaching an old database with an existing application database role MUST NOT cause automatic password rotation unless explicitly requested.

## Scenario Z — Unknown database lineage

When source DHIS2 version cannot be reliably established:

- tool reports `UNKNOWN`;
- automatic migration is blocked by default;
- operator must provide source version or explicit override.

---

# 81. Distributed Deployment — Location of the `dhis2-*` Commands

## 81.1 Architectural rule

For distributed deployments, the **complete `dhis2-*` command suite MUST be installed on the Ansible deployment/controller host only by default.**

Example architecture:

```text
                    +----------------------------------+
                    | Deployment / Ansible Controller  |
                    |                                  |
                    | /opt/dhis2-server-tools          |
                    | /usr/local/bin/dhis2-*           |
                    | inventory                        |
                    | secrets                          |
                    | execution logs                   |
                    +----------------+-----------------+
                                     |
                              SSH / Ansible
                    +----------------+-----------------+
                    |                |                 |
                    v                v                 v
               +---------+      +---------+       +---------+
               | Proxy VM|      | DHIS2 VM|       | PG VM   |
               |         |      |         |       |         |
               | nginx   |      | Tomcat  |       |Postgres |
               +---------+      +---------+       +---------+
                                      |
                                  other VMs
```

The operator runs:

```bash
dhis2-status
dhis2-doctor
dhis2-db status
dhis2-instance restart hmis
dhis2-proxy test
```

**on the controller**, not on the managed VMs.

The CLI resolves the inventory and executes the required operation remotely.

---

# 82. Why Commands Must Not Be Distributed Across Every VM

Installing the full administration suite on every VM would create several problems:

- duplicated inventory;
- duplicated configuration;
- duplicated secrets;
- inconsistent tool versions;
- unclear source of truth;
- risk of operators running orchestration from the wrong server;
- more packages and attack surface on production hosts;
- harder upgrades;
- divergent logs;
- difficulty coordinating operations involving multiple VMs.

For example:

```bash
dhis2-instance restart hmis
```

may require knowledge of:

```text
DHIS2 VM
proxy VM
monitoring VM
database host
instance inventory settings
```

Therefore it belongs on the controller.

Similarly:

```bash
dhis2-upgrade run hmis
```

coordinates database backup, application deployment, monitoring, proxy/maintenance behavior and health checks across multiple machines.

It MUST run from the orchestration/control plane.

---

# 83. Controller Installation Layout

Recommended distributed-controller installation:

```text
/opt/dhis2-server-tools/
├── bin/
├── lib/
├── deploy/
├── docs/
└── VERSION

/etc/dhis2-server-tools/
├── config
└── environments/

/var/lib/dhis2-server-tools/
├── state/
├── locks/
├── history/
└── snapshots/

/var/log/dhis2-server-tools/
└── ...

/opt/ansible/secrets/
└── ...

/usr/local/bin/
├── dhis2-deploy
├── dhis2-host
├── dhis2-inventory
├── dhis2-instance
├── dhis2-db
├── dhis2-backup
├── dhis2-restore
├── dhis2-upgrade
├── dhis2-proxy
├── dhis2-tls
├── dhis2-monitor
├── dhis2-logs
├── dhis2-doctor
├── dhis2-security
├── dhis2-vpn
├── dhis2-doris
├── dhis2-integration
├── dhis2-vault
└── dhis2-status
```

Only the controller requires the complete repository/toolset.

---

# 84. Managed VM Requirements

Managed VMs SHOULD contain only what the deployed service needs plus standard remote-management prerequisites.

Typical requirements:

```text
SSH server
Python 3
sudo/become capability
service-specific packages
Ansible-created service/configuration files
```

Example:

### Proxy VM

```text
nginx/apache2/openresty
TLS files
monitoring agent/exporter where configured
WireGuard where configured
```

### DHIS2 VM

```text
Java
Tomcat
DHIS2 application
Glowroot/monitoring agent where configured
WireGuard where configured
```

### PostgreSQL VM

```text
PostgreSQL
PostGIS
monitoring exporter
backup tooling
WireGuard where configured
```

The full CLI suite SHOULD NOT be installed on these nodes by default.

---

# 85. Optional Lightweight Remote Helper

If future functionality genuinely requires a reusable node-side helper, it MAY be introduced as a separate package/script, for example:

```text
dhis2-node
```

This MUST NOT contain full orchestration logic.

Possible responsibilities:

```text
service status collection
local health probe
local configuration checksum
log collection
resource collection
safe service action requested by controller
```

However, Ansible modules and standard Linux commands SHOULD be preferred where sufficient.

A remote helper MUST NOT maintain a separate inventory or copy controller secrets.

---

# 86. Local Command Mode

Some administrators may SSH into a managed node and want local diagnostics.

A carefully limited mode MAY be supported:

```bash
dhis2-doctor --local
dhis2-status --local
dhis2-logs --local
```

If implemented, either:

1. the commands are intentionally installed as a small diagnostics-only package; or
2. they are executed through the controller with:

```bash
dhis2-host exec HOST ...
```

The project SHOULD NOT require installing the entire control-plane CLI merely to get local diagnostics.

---

# 87. Controller High Availability and Recovery

Because the controller becomes the administration entry point, its configuration MUST be recoverable.

Back up:

```text
inventory
host_vars
group_vars
tool configuration
secret references
encrypted secrets/vault material
execution state/history as required
```

The controller MUST NOT be the only place where database backups themselves exist unless deliberately configured that way.

A controller loss MUST NOT affect runtime operation of:

```text
DHIS2
PostgreSQL
proxy
monitoring
```

Managed services must continue operating independently after deployment.

---

# 88. Multiple Environments From One Controller

The CLI SHOULD support one controller managing multiple DHIS2 environments.

Recommended:

```text
/etc/dhis2-server-tools/environments/
  production/
  staging/
  training/
```

or project-local equivalent.

Commands SHOULD support:

```bash
dhis2-status --environment production
dhis2-status --environment staging

dhis2-deploy apply --environment production
```

Equivalent short form MAY be:

```bash
dhis2-status -e production
```

The selected environment MUST be shown clearly before destructive actions.

Example:

```text
Environment: production
Instance: hmis
Database: hmis
Database host: postgres
```

This reduces the risk of executing production operations against the wrong inventory.

---

# 89. Distributed CLI Regression Requirements

Add the following.

## Scenario AA — Controller-only CLI

For an SSH/distributed deployment:

- `dhis2-*` commands exist on controller;
- commands do not need to exist on proxy/DHIS2/PostgreSQL VMs;
- normal remote operations succeed through Ansible/SSH.

## Scenario AB — Remote node has no repository

A managed VM without the cloned `dhis2-server-tools` repository MUST still be fully manageable.

## Scenario AC — Controller unavailable

Stopping/removing access to the controller MUST NOT stop already-running production services.

## Scenario AD — Mixed operating targets

One controller command MUST correctly coordinate separate proxy, application, PostgreSQL and monitoring hosts without copying the complete CLI to each host.

## Scenario AE — Environment isolation

Commands targeting `production` MUST not read or modify the `staging` inventory/state and vice versa.

---

# 90. Updated Recommended Installation Model

## Single-host LXD

Install the complete suite on the LXD host/controller:

```text
Physical host:
  dhis2-* CLI
  Ansible
  inventory
  LXD

Containers:
  proxy
  postgres
  hmis
  monitor
```

Do not install the full CLI in each container.

## Distributed SSH

Install the complete suite only on the deployment VM:

```text
Deployment VM:
  dhis2-* CLI
  Ansible
  inventory
  secrets

Remote VMs:
  service workloads only
```

## Hybrid

Install the complete suite on the controller/LXD host or dedicated deployment VM.

It controls both:

```text
local LXD containers
remote SSH VMs
```

The CLI MUST resolve the per-host `ansible_connection` automatically.

---

# 91. Additional Acceptance Criteria — Database Upgrade and Distributed CLI

## Database upgrade

- [ ] Attaching an old database does not cause an uncontrolled migration by default.
- [ ] Database migration policy supports `refuse`, `detect`, `prompt`, `auto`, and break-glass `force`.
- [ ] `auto` performs backup and verification before schema migration.
- [ ] Existing database password is preserved.
- [ ] Unknown source database lineage blocks automatic migration by default.
- [ ] Flyway migration is monitored and failure is detected.
- [ ] Failed migration never reports deployment success.
- [ ] Recovery information contains the verified pre-upgrade backup path.
- [ ] Unrelated databases on the same PostgreSQL host remain unaffected.
- [ ] `deploy.sh` can expose the migration policy without creating a second upgrade implementation.

## Distributed deployment

- [ ] Full `dhis2-*` suite is installed on the controller only by default.
- [ ] Managed VMs do not require a local clone of the repository.
- [ ] Managed VMs do not require local copies of the complete CLI.
- [ ] Controller commands transparently operate against SSH-managed hosts.
- [ ] Hybrid LXD/SSH hosts are handled from the same controller.
- [ ] Runtime services continue when the controller is unavailable.
- [ ] Multiple environments can be isolated on the same controller.


# 56. Final Implementation Position

The recommended implementation is an **evolution of the existing project, not a rewrite**.

The existing Ansible roles remain the authoritative configuration engine.

The new `dhis2-*` layer becomes the stable operator interface for:

```text
deployment
host preparation
inventory
instance lifecycle
PostgreSQL
backup
restore
upgrade
proxy
TLS
monitoring
logs
diagnostics
security
VPN
Doris
integrations
vault/secrets
status
```

The most important rule for the fork is:

> **Add capability without invalidating the current operational model.**

Every implementation decision should therefore be assessed against three questions:

1. Does the new command expose or improve an existing capability?
2. Does the existing direct Ansible workflow continue to work?
3. Can we prove the change is safe through automated and manual regression tests?

If all three cannot be answered confidently, the change should not be included in the final no-regression pull request without further isolation, compatibility handling, or test coverage.
