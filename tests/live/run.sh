#!/usr/bin/env bash
# Live round-trip for `dhis2-deploy migrate boombox-to-lxd`. Not run
# on GitHub-hosted runners — see tests/live/README.md.
#
# Env:
#   DHIS2_LIVE_HOST      ssh target (ubuntu@host). If unset, uses Vagrant.
#   DHIS2_LIVE_UBUNTU    22.04 (default) or 24.04 — Vagrant only.
#   DHIS2_LIVE_INSTANCES space-separated list. Default: "hmis".
#   DHIS2_LIVE_ROTATE    1 to add --rotate-db-password to the execute.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TS=$(date -u +%Y%m%d-%H%M%S)
OUT="$HERE/out/$TS"
mkdir -p "$OUT"

INSTANCES=${DHIS2_LIVE_INSTANCES:-hmis}
ROTATE=${DHIS2_LIVE_ROTATE:-0}

log() { printf '[live] %s\n' "$*" >&2; }

# Pick execution target: direct SSH or Vagrant.
if [[ -n "${DHIS2_LIVE_HOST:-}" ]]; then
    run() { ssh -o StrictHostKeyChecking=no "$DHIS2_LIVE_HOST" "$@"; }
    push() { scp -o StrictHostKeyChecking=no -r "$1" "$DHIS2_LIVE_HOST:$2"; }
else
    pushd "$HERE" >/dev/null
    log "vagrant up (ubuntu ${DHIS2_LIVE_UBUNTU:-22.04})"
    vagrant up --provision
    run() { vagrant ssh -c "$*"; }
    push() { vagrant ssh -c "sudo cp -r /opt/dhis2-tools-src $2"; }
    popd >/dev/null
fi

log "Installing dhis2-server-tools in guest"
run "cd /opt/dhis2-tools-src && sudo ./install.sh"

log "Initialising boombox inventory"
_init_args="--architecture boombox --mode workshop"
for i in $INSTANCES; do _init_args+=" --instance $i"; done
run "sudo dhis2-deploy init $_init_args"

log "Deploying boombox"
run "sudo dhis2-deploy apply" | tee "$OUT/deploy.log"

log "Snapshotting pre-migration status + inserting fixture"
run "sudo dhis2-status" | tee "$OUT/pre-migrate-status.txt"
for i in $INSTANCES; do
    run "sudo -u postgres psql -d $i -c \"CREATE TABLE IF NOT EXISTS dhis2_live_fixture(id int PRIMARY KEY, val text); INSERT INTO dhis2_live_fixture SELECT g, 'row-'||g FROM generate_series(1,1000) g ON CONFLICT DO NOTHING; SELECT count(*) FROM dhis2_live_fixture;\"" \
        | tee "$OUT/fixture-pre-$i.txt"
done

log "Running --detect-drift (no changes)"
run "sudo dhis2-deploy migrate boombox-to-lxd --detect-drift" | tee "$OUT/drift.txt"

log "Running --dry-run (no changes)"
run "sudo dhis2-deploy migrate boombox-to-lxd --dry-run" | tee "$OUT/plan.txt"

_exec_args="--execute --yes"
for i in $INSTANCES; do _exec_args+=" --instance $i"; done
[[ "$ROTATE" == "1" ]] && _exec_args+=" --rotate-db-password"

log "Executing migration: $_exec_args"
run "sudo dhis2-deploy migrate boombox-to-lxd $_exec_args" | tee "$OUT/execute.log"

log "Verifying post-migration state"
run "sudo dhis2-status" | tee "$OUT/post-migrate-status.txt"
for i in $INSTANCES; do
    run "sudo dhis2-instance health $i --retry 30 --interval 10" | tee "$OUT/health-$i.txt"
done

log "Verifying fixture rows survived the restore"
fail=0
for i in $INSTANCES; do
    post=$(run "sudo lxc exec postgres -- sudo -u postgres psql -At -d $i -c 'SELECT count(*) FROM dhis2_live_fixture'" | tr -d ' \r')
    echo "$i: $post" | tee -a "$OUT/fixture-check.txt"
    if [[ "$post" != "1000" ]]; then
        log "FIXTURE FAIL $i: expected 1000, got $post"
        fail=1
    fi
done

if (( fail != 0 )); then
    log "Live round-trip FAILED. Logs: $OUT"
    exit 1
fi

log "Live round-trip PASS. Logs: $OUT"
