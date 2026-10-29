# shellcheck shell=bash
# Configuration search order - section 8.2.

# Resolve inventory following this order:
#   1. explicit --inventory
#   2. DHIS2_INVENTORY
#   3. $ENV_DIR/inventory/hosts for the requested --environment
#   4. project-local deploy/inventory/hosts
#   5. /etc/dhis2-server-tools/inventory/hosts
dhis2_config_resolve_inventory() {
    local explicit="${DHIS2_OPT_INVENTORY:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s\n' "$explicit"; return 0
    fi
    if [[ -n "${DHIS2_INVENTORY:-}" ]]; then
        printf '%s\n' "$DHIS2_INVENTORY"; return 0
    fi
    if [[ -n "${DHIS2_OPT_ENVIRONMENT:-}" ]]; then
        local envdir="/etc/dhis2-server-tools/environments/${DHIS2_OPT_ENVIRONMENT}"
        if [[ -f "$envdir/inventory/hosts" ]]; then
            printf '%s\n' "$envdir/inventory/hosts"; return 0
        fi
    fi
    if [[ -f "${DHIS2_CLI_ROOT}/deploy/inventory/hosts" ]]; then
        printf '%s\n' "${DHIS2_CLI_ROOT}/deploy/inventory/hosts"; return 0
    fi
    if [[ -f /etc/dhis2-server-tools/inventory/hosts ]]; then
        printf '%s\n' /etc/dhis2-server-tools/inventory/hosts; return 0
    fi
    printf '%s\n' "${DHIS2_CLI_ROOT}/deploy/inventory/hosts"
}

dhis2_config_deploy_dir() {
    if [[ -d "${DHIS2_CLI_ROOT}/deploy" ]]; then
        printf '%s\n' "${DHIS2_CLI_ROOT}/deploy"
    else
        printf '%s\n' "/opt/dhis2-server-tools/deploy"
    fi
}

# State / history / snapshot locations.
dhis2_config_state_dir() {
    local d="${DHIS2_STATE_DIR:-/var/lib/dhis2-server-tools}"
    [[ -w "$(dirname "$d")" ]] 2>/dev/null || d="${HOME}/.local/share/dhis2-server-tools"
    mkdir -p "$d" 2>/dev/null || true
    printf '%s\n' "$d"
}

dhis2_config_lock_dir() {
    local d
    d="$(dhis2_config_state_dir)/locks"
    mkdir -p "$d" 2>/dev/null || true
    printf '%s\n' "$d"
}

dhis2_config_history_dir() {
    local d
    d="$(dhis2_config_state_dir)/history"
    mkdir -p "$d" 2>/dev/null || true
    printf '%s\n' "$d"
}

dhis2_config_snapshot_dir() {
    local d
    d="$(dhis2_config_state_dir)/snapshots"
    mkdir -p "$d" 2>/dev/null || true
    printf '%s\n' "$d"
}
