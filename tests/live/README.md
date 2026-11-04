# Live migration test harness

Mock-mode regression (`tests/regression/run_scenarios.sh`) verifies
every code path in `dhis2-deploy migrate boombox-to-lxd`, but it does
not prove the round-trip works on a real Ubuntu host. This harness
does: it provisions a disposable VM, deploys a boombox, puts fixture
data in, migrates to LXD, and verifies the fixture data on the LXD
side.

**Not wired into the free-tier GitHub Actions matrix** — LXD inside
nested virtualisation on the hosted runners is too flaky to gate PRs
on. Operators with a self-hosted runner can opt in via
`.github/workflows/live-matrix.yml`.

## Prerequisites

- VirtualBox or libvirt
- Vagrant ≥ 2.3
- 8 GB RAM free (the VM asks for 4 GB)
- 25 GB disk free

Alternatively: any Ubuntu 22.04 or 24.04 host where you have `sudo`.
The harness runs the same commands the Vagrantfile would run; set
`DHIS2_LIVE_HOST=<ssh-target>` and skip `vagrant up`.

## Running

```bash
# Default: Ubuntu 22.04 fixture, hmis instance
bash tests/live/run.sh

# Ubuntu 24.04
DHIS2_LIVE_UBUNTU=24.04 bash tests/live/run.sh

# Multi-instance round-trip (the scenario that proves CG works)
DHIS2_LIVE_INSTANCES="hmis training" bash tests/live/run.sh

# With DB password rotation (proves CH)
DHIS2_LIVE_ROTATE=1 bash tests/live/run.sh

# Against an existing SSH target (no Vagrant)
DHIS2_LIVE_HOST=ubuntu@10.0.0.42 bash tests/live/run.sh
```

Each run captures:

- `tests/live/out/<ts>/pre-migrate-status.txt` — `dhis2-status` before
- `tests/live/out/<ts>/plan.txt` — `migrate ... --dry-run` output
- `tests/live/out/<ts>/execute.log` — full `--execute` log
- `tests/live/out/<ts>/post-migrate-status.txt` — `dhis2-status` after
- `tests/live/out/<ts>/fixture-check.txt` — row-count diff on the
  fixture `datavalue` table (must equal zero)

A non-zero fixture diff fails the run.

## Opt-in CI

Add a self-hosted runner labelled `live-lxd`, enable
`.github/workflows/live-matrix.yml` in the repo settings, and the
matrix will run against the next PR touching
`bin/dhis2-deploy`, `deploy/roles/boombox/**`, or
`deploy/roles/create-instance/**`.

Running cost: ~15 min per matrix entry; the default matrix is
Ubuntu 22.04 + 24.04 × single/multi-instance = 4 entries.

## Why not Molecule with LXD-in-Docker?

Tried it, it's flaky. LXD inside Docker inside GitHub Actions needs
`--privileged`, a fuse-overlayfs shim, and the systemd unit still
flaps on a cold-cache pull. Vagrant on a real runner is less clever
and more reliable.
