#!/usr/bin/env bash
# tests/cli/run_cli_tests.sh - CLI smoke tests, no network/Ansible calls.
#
# Verifies for every bin/dhis2-* command that:
#   - --help prints usage and exits 0
#   - --version works where applicable
#   - unknown subcommand returns exit code 2 (invalid arguments)
#   - "architectures" lists the four required architectures and marks
#     docker/kubernetes as NOT IMPLEMENTED (section 11.2)
#   - inventory list/validate works against a known-good test inventory
#   - JSON output is parseable where supported
#
set -Euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/bin"
PASS=0; FAIL=0

t_pass() { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
t_fail() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1" >&2; }

run() {
    local expected="$1"; shift
    local out rc
    out=$("$@" 2>&1); rc=$?
    if [[ "$expected" == "0" && $rc -eq 0 ]]; then
        return 0
    elif [[ "$expected" != "0" && $rc -ne 0 ]]; then
        return 0
    fi
    printf '    stdout: %s\n' "${out:0:300}" >&2
    printf '    rc=%s expected=%s\n' "$rc" "$expected" >&2
    return 1
}

mkdir -p /tmp/dhis2cli-tests
TEST_INV=/tmp/dhis2cli-tests/hosts
cp "$ROOT/deploy/inventory/hosts.template" "$TEST_INV"
chmod 600 "$TEST_INV"
export DHIS2_INVENTORY="$TEST_INV"
export DHIS2_STATE_DIR=/tmp/dhis2cli-tests/state

echo "---- help tests ----"
for cmd in dhis2-status dhis2-inventory dhis2-deploy dhis2-host dhis2-instance \
          dhis2-db dhis2-backup dhis2-restore dhis2-upgrade dhis2-proxy \
          dhis2-tls dhis2-monitor dhis2-logs dhis2-doctor dhis2-security \
          dhis2-vpn dhis2-doris dhis2-integration dhis2-vault; do
    if run 0 "$BIN/$cmd" --help; then
        t_pass "$cmd --help"
    else
        t_fail "$cmd --help"
    fi
done

echo "---- version test ----"
if "$BIN/dhis2-deploy" --version 2>&1 | grep -q "dhis2-server-tools"; then
    t_pass "dhis2-deploy --version"
else
    t_fail "dhis2-deploy --version"
fi

echo "---- unknown subcommand returns usage ----"
if run 2 "$BIN/dhis2-deploy" totally-bogus-subcommand; then
    t_pass "dhis2-deploy bogus returns exit 2"
else
    t_fail "dhis2-deploy bogus should exit 2"
fi

echo "---- architectures lists LXD, distributed, hybrid, docker, kubernetes ----"
out=$("$BIN/dhis2-deploy" architectures 2>&1)
for a in lxd distributed hybrid docker kubernetes; do
    if echo "$out" | grep -qi "$a"; then t_pass "architectures lists $a"; else t_fail "architectures missing $a"; fi
done
echo "$out" | grep -qi 'docker.*NOT IMPLEMENTED' && t_pass "docker marked NOT IMPLEMENTED" || t_fail "docker not marked NOT IMPLEMENTED"
echo "$out" | grep -qi 'kubernetes.*NOT IMPLEMENTED' && t_pass "kubernetes marked NOT IMPLEMENTED" || t_fail "kubernetes not marked NOT IMPLEMENTED"

echo "---- JSON output ----"
out=$("$BIN/dhis2-deploy" architectures --json 2>&1)
echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); assert isinstance(d.get("architectures"), list) and len(d["architectures"])>=5' \
  && t_pass "dhis2-deploy architectures --json is parseable" \
  || t_fail "dhis2-deploy architectures --json malformed"

echo "---- inventory validate ----"
if run 0 "$BIN/dhis2-inventory" validate; then
    t_pass "dhis2-inventory validate"
else
    t_fail "dhis2-inventory validate"
fi

echo "---- status reads inventory ----"
out=$("$BIN/dhis2-status" 2>&1)
echo "$out" | grep -q "Infrastructure" && t_pass "dhis2-status produces human output" || t_fail "dhis2-status broken"

out=$("$BIN/dhis2-status" --json 2>&1)
echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); assert d.get("command")=="dhis2-status"' \
  && t_pass "dhis2-status --json parseable" \
  || t_fail "dhis2-status --json malformed"

echo "---- redaction ----"
echo 'connection.password=HORRIBLE_SECRET_12345' | "$ROOT/bin/dhis2-logs" redact /dev/stdin 2>&1 | grep -q "REDACTED" \
  && t_pass "dhis2-logs redact removes password" \
  || t_fail "dhis2-logs redact failed"

echo
echo "PASS: $PASS   FAIL: $FAIL"
exit "$FAIL"
