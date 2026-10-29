# Testing the dhis2-* CLI

Three layers of automated tests ship with the project.

## 1. CLI smoke tests — `tests/cli/run_cli_tests.sh`

Fast, dependency-free bash tests that verify:

- every `bin/dhis2-*` command responds to `--help` with exit 0
- `--version` prints the expected banner
- unknown subcommands exit `2` (invalid argument)
- `dhis2-deploy architectures` lists the five architectures and marks
  `docker` / `kubernetes` as **NOT IMPLEMENTED** (section 11.2)
- `--json` output is parseable JSON on commands that advertise it
- `dhis2-inventory validate` accepts the shipped template inventory
- `dhis2-logs redact` strips `connection.password=...` style tokens
  (scenario R)

Run locally:

```bash
bash tests/cli/run_cli_tests.sh
```

CI runs this on every push.

## 2. Regression scenarios — `tests/regression/run_scenarios.sh`

Encodes **every** scenario named in sections 40, 69, 80, and 89 of the
implementation requirements document (A through AE) as a mock-mode
assertion. The mock-mode run is self-contained — it does not need a
real deployment — and produces a Markdown compatibility table at
`tests/regression/last-run.md` matching the shape required by section
53.

Mock mode results (33 scenarios):

| Section | Scenarios covered |
| ------- | ----------------- |
| 40      | A, B, C, D, E, E1, E2, E3, F, G, H |
| 69      | I, J, K, L, M, N, O, P, Q, R, S, T |
| 80      | U, V, W, X, Y, Z |
| 89      | AA, AB, AC, AD, AE |

Run locally:

```bash
bash tests/regression/run_scenarios.sh
cat tests/regression/last-run.md
```

Live mode (requires a real inventory and controller with Ansible
installed):

```bash
export DHIS2_REGRESSION_LIVE=1
export DHIS2_INVENTORY=/path/to/production/inventory
bash tests/regression/run_scenarios.sh
```

## 3. Molecule scenarios — `molecule/`

Container-based integration tests runnable in CI and locally with
Docker. Three scenarios, all gated on CI:

- `molecule/cli-smoke` — installs the CLI with `install.sh` inside an
  Ubuntu 22.04 container, runs the CLI smoke tests and the regression
  mock-mode run end-to-end.
- `molecule/dhis-conf-preservation` — proves scenarios **E1 / E2 / E3**
  mechanically. Seeds an operator-maintained `/opt/dhis2/dhis.conf`,
  runs the preserve / merge / replace branches of the role, and
  asserts byte-for-byte invariants after each phase.
- `molecule/upgrade-monitor-migrations` — proves the Flyway monitoring
  task implements scenario **X** (failure never reports success) and
  **P** (interrupted upgrade state captured). Feeds three different
  mock `catalina.out` contents into the role task.

Run a single scenario locally:

```bash
pip install ansible molecule molecule-docker pytest-testinfra
molecule test -s cli-smoke
molecule test -s dhis-conf-preservation
molecule test -s upgrade-monitor-migrations
```

## 4. Pre-PR manual validation matrix

The following must additionally be exercised on real infrastructure
before an upstream pull request is opened. These cannot run in CI.
See section 52 of the implementation requirements document.

| Environment | Architecture | Scope |
| ----------- | ------------ | ----- |
| 1 | Single LXD host | proxy + postgres + hmis + monitor on LXD |
| 2 | Distributed SSH | separate controller / proxy / app / db / monitor VMs |
| 3 | Hybrid | PostgreSQL over SSH + DHIS2/proxy on LXD + monitor over SSH |

For each environment:

```bash
dhis2-deploy preflight
dhis2-deploy plan
dhis2-deploy apply
dhis2-status
dhis2-doctor
dhis2-instance restart hmis
dhis2-backup create hmis
dhis2-backup verify /var/backups/dhis2/...
dhis2-restore plan --backup /var/backups/... --instance hmis
dhis2-proxy test
dhis2-proxy reload
dhis2-tls status
dhis2-db status
dhis2-logs hmis --lines 50
dhis2-upgrade plan hmis --to 2.43.2
```

Repeated `dhis2-deploy apply` must show expected Ansible idempotency
(no changes on the second run).

## Reporting

Attach `tests/regression/last-run.md` and the Molecule junit.xml
artifacts to the pull-request description.
