# shellcheck shell=bash
# Operation locks - section 31.

# dhis2_lock_acquire <lock-name>
# Uses mkdir atomicity. Stale locks older than DHIS2_LOCK_STALE_SECONDS
# (default 3600) are reclaimed with a warning.
dhis2_lock_acquire() {
    local name="$1"
    local dir
    dir=$(dhis2_config_lock_dir)
    local lock="$dir/$name.lock"
    local stale="${DHIS2_LOCK_STALE_SECONDS:-3600}"
    if mkdir "$lock" 2>/dev/null; then
        echo "$$" > "$lock/pid"
        date -u +%s > "$lock/ts"
        _DHIS2_HELD_LOCK="$lock"
        # shellcheck disable=SC2064
        trap "dhis2_lock_release '$name'" EXIT HUP INT TERM
        return 0
    fi
    # Stale detection
    if [[ -f "$lock/ts" ]]; then
        local age now ts
        now=$(date -u +%s)
        ts=$(cat "$lock/ts" 2>/dev/null || echo "$now")
        age=$(( now - ts ))
        if (( age > stale )); then
            dhis2_log_warn "Reclaiming stale lock '$name' (age ${age}s)"
            rm -rf "$lock"
            dhis2_lock_acquire "$name"
            return $?
        fi
    fi
    dhis2_log_error "Operation lock '$name' is held by another process."
    return "$DHIS2_EXIT_LOCK"
}

dhis2_lock_release() {
    local name="$1"
    local dir
    dir=$(dhis2_config_lock_dir)
    rm -rf "$dir/$name.lock" 2>/dev/null || true
}
