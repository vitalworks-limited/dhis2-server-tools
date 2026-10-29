# shellcheck shell=bash
# Thin Ansible execution wrapper. Preserves per-host connection selection
# and existing tag semantics.

dhis2_ansible_cfg() {
    local deploy_dir
    deploy_dir=$(dhis2_config_deploy_dir)
    printf '%s\n' "$deploy_dir/ansible.cfg"
}

# dhis2_ansible_playbook <playbook-relative-to-deploy> [extra args ...]
dhis2_ansible_playbook() {
    local playbook="$1"; shift || true
    local deploy_dir inv
    deploy_dir=$(dhis2_config_deploy_dir)
    inv=$(dhis2_config_resolve_inventory)
    local -a args=()
    [[ "${DHIS2_OPT_CHECK:-false}" == true ]] && args+=(--check)
    [[ "${DHIS2_OPT_DIFF:-false}"  == true ]] && args+=(--diff)
    [[ "${DHIS2_OPT_VERBOSE:-false}" == true ]] && args+=(-v)
    [[ -n "${DHIS2_OPT_LIMIT:-}" ]] && args+=(--limit "$DHIS2_OPT_LIMIT")
    [[ -n "${DHIS2_OPT_USER:-}"  ]] && args+=(--user  "$DHIS2_OPT_USER")
    # Allow callers to inject extra args.
    (
        cd "$deploy_dir" || exit "$DHIS2_EXIT_FAILURE"
        ANSIBLE_CONFIG="$(dhis2_ansible_cfg)" \
        ansible-playbook -i "$inv" "$playbook" "${args[@]}" "$@"
    )
    local rc=$?
    if (( rc != 0 )); then
        dhis2_log_error "Ansible execution failed (rc=$rc) running $playbook"
        return "$DHIS2_EXIT_ANSIBLE"
    fi
}

# Run the canonical dhis2.yml with specific tags.
dhis2_ansible_run_tags() {
    local tags="$1"; shift || true
    dhis2_ansible_playbook dhis2.yml --tags "$tags" "$@"
}

# dhis2_ansible_adhoc <host-or-group> <module> [args...]
dhis2_ansible_adhoc() {
    local target="$1"; local module="$2"; shift 2 || true
    local deploy_dir inv
    deploy_dir=$(dhis2_config_deploy_dir)
    inv=$(dhis2_config_resolve_inventory)
    (
        cd "$deploy_dir" || exit "$DHIS2_EXIT_FAILURE"
        ANSIBLE_CONFIG="$(dhis2_ansible_cfg)" \
        ansible -i "$inv" "$target" -m "$module" "$@"
    )
}

# dhis2_ansible_shell <host> <command>
dhis2_ansible_shell() {
    local host="$1"; shift
    dhis2_ansible_adhoc "$host" shell -a "$*" -o
}

# Collect host facts without side effects.
dhis2_ansible_facts() {
    local host="$1"
    dhis2_ansible_adhoc "$host" setup
}

# dhis2_ansible_syntax <playbook>
dhis2_ansible_syntax() {
    local playbook="$1"
    local deploy_dir inv
    deploy_dir=$(dhis2_config_deploy_dir)
    inv=$(dhis2_config_resolve_inventory)
    (
        cd "$deploy_dir" || exit "$DHIS2_EXIT_FAILURE"
        ANSIBLE_CONFIG="$(dhis2_ansible_cfg)" \
        ansible-playbook -i "$inv" "$playbook" --syntax-check
    )
}
