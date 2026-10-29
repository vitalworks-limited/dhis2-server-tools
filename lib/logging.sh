# shellcheck shell=bash
# Logging primitives. All human messages go to stderr so --json output
# on stdout remains parseable.

DHIS2_LOG_LEVEL="${DHIS2_LOG_LEVEL:-info}"
DHIS2_LOG_DIR="${DHIS2_LOG_DIR:-}"

_dhis2_log_level_rank() {
    case "$1" in
        debug) echo 10 ;;
        info)  echo 20 ;;
        warn)  echo 30 ;;
        error) echo 40 ;;
        *)     echo 20 ;;
    esac
}

_dhis2_log_emit() {
    local level="$1"; shift
    local msg="$*"
    local want_rank cur_rank
    want_rank=$(_dhis2_log_level_rank "$level")
    cur_rank=$(_dhis2_log_level_rank "$DHIS2_LOG_LEVEL")
    (( want_rank < cur_rank )) && return 0
    local ts
    ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local upper="${level^^}"
    printf '[%s] %s %s\n' "$ts" "$upper" "$msg" >&2
    if [[ -n "$DHIS2_LOG_DIR" ]]; then
        mkdir -p "$DHIS2_LOG_DIR" 2>/dev/null && \
            printf '[%s] %s %s\n' "$ts" "$upper" "$msg" >> "$DHIS2_LOG_DIR/cli.log"
    fi
}

dhis2_log_debug() { _dhis2_log_emit debug "$*"; }
dhis2_log_info()  { [[ "${DHIS2_OPT_QUIET:-false}" == true ]] || _dhis2_log_emit info  "$*"; }
dhis2_log_warn()  { _dhis2_log_emit warn  "$*"; }
dhis2_log_error() { _dhis2_log_emit error "$*"; }

# dhis2_log_audit <command> <args-json> <result>
# Appends an audit record for mutating operations - section 30.
dhis2_log_audit() {
    local cmd="$1" args="$2" result="$3"
    local dir="${DHIS2_AUDIT_DIR:-$DHIS2_LOG_DIR}"
    [[ -z "$dir" ]] && dir="/var/log/dhis2-server-tools"
    mkdir -p "$dir" 2>/dev/null || return 0
    local f="$dir/audit.ndjson"
    local ts user host
    ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
    host=$(hostname 2>/dev/null || echo unknown)
    printf '{"ts":"%s","user":"%s","controller":"%s","command":"%s","args":%s,"result":"%s"}\n' \
        "$ts" "$user" "$host" "$cmd" "$args" "$result" >> "$f" 2>/dev/null || true
}

# Redact common secret-looking tokens from a stream passing through stdin.
dhis2_log_redact() {
    sed -E \
        -e 's/(password[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1***REDACTED***/Ig' \
        -e 's/(token[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1***REDACTED***/Ig' \
        -e 's/(secret[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1***REDACTED***/Ig' \
        -e 's/(encryption\.password[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1***REDACTED***/Ig' \
        -e 's/(connection\.password[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1***REDACTED***/Ig' \
        -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----/***REDACTED-PRIVATE-KEY***/g'
}