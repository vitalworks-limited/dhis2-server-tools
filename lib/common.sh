# shellcheck shell=bash
# Shared helpers for the dhis2-* CLI family.
# Sourced by every bin/dhis2-* command.

# Resolve the project root for both installed and in-tree execution.
_dhis2_cli_resolve_root() {
    if [[ -n "${DHIS2_TOOLS_HOME:-}" && -d "${DHIS2_TOOLS_HOME}" ]]; then
        printf '%s\n' "${DHIS2_TOOLS_HOME}"
        return 0
    fi
    local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local dir
    dir=$(cd "$(dirname "$(readlink -f "$src" 2>/dev/null || echo "$src")")/.." && pwd)
    printf '%s\n' "$dir"
}

DHIS2_CLI_ROOT="${DHIS2_CLI_ROOT:-$(_dhis2_cli_resolve_root)}"
export DHIS2_CLI_ROOT

# Load every library file. Order matters only for logging/output which are
# referenced by the others.
# shellcheck source=./logging.sh
. "${DHIS2_CLI_ROOT}/lib/logging.sh"
# shellcheck source=./output.sh
. "${DHIS2_CLI_ROOT}/lib/output.sh"
# shellcheck source=./config.sh
. "${DHIS2_CLI_ROOT}/lib/config.sh"
# shellcheck source=./inventory.sh
. "${DHIS2_CLI_ROOT}/lib/inventory.sh"
# shellcheck source=./validation.sh
. "${DHIS2_CLI_ROOT}/lib/validation.sh"
# shellcheck source=./ansible.sh
. "${DHIS2_CLI_ROOT}/lib/ansible.sh"
# shellcheck source=./privilege.sh
. "${DHIS2_CLI_ROOT}/lib/privilege.sh"
# shellcheck source=./locks.sh
. "${DHIS2_CLI_ROOT}/lib/locks.sh"

# Documented exit codes - section 7.1.
# shellcheck disable=SC2034  # consumed by sourcing bin/dhis2-* scripts
readonly DHIS2_EXIT_OK=0
# shellcheck disable=SC2034
readonly DHIS2_EXIT_FAILURE=1
# shellcheck disable=SC2034
readonly DHIS2_EXIT_USAGE=2
# shellcheck disable=SC2034
readonly DHIS2_EXIT_PREFLIGHT=3
# shellcheck disable=SC2034
readonly DHIS2_EXIT_CONNECTIVITY=4
# shellcheck disable=SC2034
readonly DHIS2_EXIT_ANSIBLE=5
# shellcheck disable=SC2034
readonly DHIS2_EXIT_HEALTH=6
# shellcheck disable=SC2034
readonly DHIS2_EXIT_PARTIAL=7
# shellcheck disable=SC2034
readonly DHIS2_EXIT_SAFETY=8
# shellcheck disable=SC2034
readonly DHIS2_EXIT_LOCK=9

# Version — kept in sync with repository tags.
DHIS2_CLI_VERSION="$(cat "${DHIS2_CLI_ROOT}/VERSION" 2>/dev/null || echo "0.0.0-dev")"
export DHIS2_CLI_VERSION

# Default globals - overridden by argument parsing. Exported so sourced
# scripts can consume them without shellcheck SC2034 false positives.
export DHIS2_OPT_JSON=false
export DHIS2_OPT_QUIET=false
export DHIS2_OPT_VERBOSE=false
export DHIS2_OPT_NO_COLOR=false
export DHIS2_OPT_YES=false
export DHIS2_OPT_CHECK=false
export DHIS2_OPT_DIFF=false
export DHIS2_OPT_INVENTORY=""
export DHIS2_OPT_LIMIT=""
export DHIS2_OPT_INSTANCE=""
export DHIS2_OPT_HOST=""
export DHIS2_OPT_USER=""
export DHIS2_OPT_CONNECTION=""
export DHIS2_OPT_ENVIRONMENT=""

# dhis2_cli_parse_globals <args...>
# Consumes documented common options and sets DHIS2_CLI_REMAINING to the
# remaining positional/subcommand arguments. Callers should read it as:
#   dhis2_cli_parse_globals "$@"; set -- "${DHIS2_CLI_REMAINING[@]}"
DHIS2_CLI_REMAINING=()
dhis2_cli_parse_globals() {
    DHIS2_CLI_REMAINING=()
    while (( $# )); do
        case "$1" in
            --json) DHIS2_OPT_JSON=true ;;
            --quiet|-q) DHIS2_OPT_QUIET=true ;;
            --verbose|-v) DHIS2_OPT_VERBOSE=true ;;
            --no-color) DHIS2_OPT_NO_COLOR=true ;;
            --yes|-y) DHIS2_OPT_YES=true ;;
            --check) DHIS2_OPT_CHECK=true ;;
            --diff) DHIS2_OPT_DIFF=true ;;
            --inventory) DHIS2_OPT_INVENTORY="${2:-}"; shift ;;
            --inventory=*) DHIS2_OPT_INVENTORY="${1#*=}" ;;
            --limit) DHIS2_OPT_LIMIT="${2:-}"; shift ;;
            --limit=*) DHIS2_OPT_LIMIT="${1#*=}" ;;
            --instance) DHIS2_OPT_INSTANCE="${2:-}"; shift ;;
            --instance=*) DHIS2_OPT_INSTANCE="${1#*=}" ;;
            --host) DHIS2_OPT_HOST="${2:-}"; shift ;;
            --host=*) DHIS2_OPT_HOST="${1#*=}" ;;
            --user) DHIS2_OPT_USER="${2:-}"; shift ;;
            --user=*) DHIS2_OPT_USER="${1#*=}" ;;
            --connection) DHIS2_OPT_CONNECTION="${2:-}"; shift ;;
            --connection=*) DHIS2_OPT_CONNECTION="${1#*=}" ;;
            --environment|-e) DHIS2_OPT_ENVIRONMENT="${2:-}"; shift ;;
            --environment=*) DHIS2_OPT_ENVIRONMENT="${1#*=}" ;;
            --version)
                printf 'dhis2-server-tools %s\n' "$DHIS2_CLI_VERSION"
                exit 0
                ;;
            *) DHIS2_CLI_REMAINING+=("$1") ;;
        esac
        shift || true
    done
    if [[ "$DHIS2_OPT_NO_COLOR" == true || -n "${DHIS2_NO_COLOR:-}" ]]; then
        dhis2_output_disable_color
    fi
    return 0
}

# Confirmation prompt for destructive actions - section 33.
# Usage: dhis2_cli_confirm "message" "expected-input-to-proceed"
dhis2_cli_confirm() {
    local message="$1"
    local expected="${2:-}"
    if [[ "$DHIS2_OPT_YES" == true ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        dhis2_log_error "Refusing destructive action: stdin not a terminal and --yes not supplied."
        exit "$DHIS2_EXIT_SAFETY"
    fi
    if [[ -n "$expected" ]]; then
        printf '%s\nType "%s" to continue: ' "$message" "$expected" >&2
        local reply=""
        read -r reply || true
        if [[ "$reply" != "$expected" ]]; then
            dhis2_log_error "Confirmation did not match. Aborting."
            exit "$DHIS2_EXIT_SAFETY"
        fi
    else
        printf '%s [y/N]: ' "$message" >&2
        local reply=""
        read -r reply || true
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            dhis2_log_error "Aborting at operator request."
            exit "$DHIS2_EXIT_SAFETY"
        fi
    fi
}

# Trap wrapper so sensitive temp files are cleaned up.
dhis2_cli_register_tempdir() {
    local td
    td=$(mktemp -d -t dhis2cli.XXXXXX)
    chmod 700 "$td"
    # shellcheck disable=SC2064
    trap "rm -rf '$td'" EXIT HUP INT TERM
    printf '%s\n' "$td"
}

# Prints the usage text embedded in a bin/dhis2-* script between the markers
# `# usage: <<EOF` and `# EOF`. Fallback: show short default message.
dhis2_cli_show_help() {
    local script="$1"
    awk '/^# USAGE_START/{flag=1;next} /^# USAGE_END/{flag=0} flag{sub(/^# ?/,""); print}' "$script"
}