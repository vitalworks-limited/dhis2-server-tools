# shellcheck shell=bash
# Privilege helpers - section 9.

dhis2_privilege_is_root() { [[ $EUID -eq 0 ]]; }

dhis2_privilege_has_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

dhis2_privilege_has_lxd() {
    getent group lxd 2>/dev/null | grep -qE "(^lxd:.*:.*:.*(\s|,|^)${USER}(\s|,|$))" || \
        id -nG 2>/dev/null | tr ' ' '\n' | grep -qx lxd
}

dhis2_privilege_require() {
    local what="$1"
    case "$what" in
        root)
            if ! dhis2_privilege_is_root; then
                dhis2_log_error "This operation requires root. Re-run with sudo."
                exit "$DHIS2_EXIT_SAFETY"
            fi
            ;;
        sudo)
            if ! (dhis2_privilege_is_root || dhis2_privilege_has_sudo); then
                dhis2_log_error "sudo (passwordless) or root is required for this operation."
                exit "$DHIS2_EXIT_SAFETY"
            fi
            ;;
        lxd)
            if ! (dhis2_privilege_is_root || dhis2_privilege_has_lxd); then
                dhis2_log_error "LXD group membership (or root) required: usermod -aG lxd \$USER"
                exit "$DHIS2_EXIT_SAFETY"
            fi
            ;;
    esac
}
