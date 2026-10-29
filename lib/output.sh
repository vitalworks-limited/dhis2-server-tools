# shellcheck shell=bash
# Output helpers: colour, tables, JSON emission.

_DHIS2_COLOR_ENABLED=true
if [[ -n "${NO_COLOR:-}" || -n "${DHIS2_NO_COLOR:-}" || ! -t 1 ]]; then
    _DHIS2_COLOR_ENABLED=false
fi

dhis2_output_disable_color() { _DHIS2_COLOR_ENABLED=false; }

_dhis2_color() {
    local code="$1"; shift
    if [[ "$_DHIS2_COLOR_ENABLED" == true ]]; then
        printf '\033[%sm%s\033[0m' "$code" "$*"
    else
        printf '%s' "$*"
    fi
}

dhis2_c_red()    { _dhis2_color '31' "$@"; }
dhis2_c_green()  { _dhis2_color '32' "$@"; }
dhis2_c_yellow() { _dhis2_color '33' "$@"; }
dhis2_c_blue()   { _dhis2_color '34' "$@"; }
dhis2_c_bold()   { _dhis2_color '1'  "$@"; }

# dhis2_json_emit <key=value> ...
# Minimal structured JSON emitter: keys with "=" are k:v pairs. Values are
# treated as JSON literals (numbers/booleans/null) if they match, otherwise
# JSON-stringified.
dhis2_json_emit() {
    local first=true
    printf '{'
    local kv key value
    for kv in "$@"; do
        key="${kv%%=*}"
        value="${kv#*=}"
        if ! $first; then printf ','; fi
        first=false
        printf '"%s":' "$key"
        if [[ "$value" =~ ^(true|false|null|-?[0-9]+(\.[0-9]+)?)$ ]]; then
            printf '%s' "$value"
        elif [[ "$value" =~ ^[\[{].*[\]}]$ ]]; then
            printf '%s' "$value"
        else
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            value="${value//$'\t'/\\t}"
            printf '"%s"' "$value"
        fi
    done
    printf '}\n'
}

# dhis2_output_table "H1|H2|H3" "r1c1|r1c2|r1c3" ...
dhis2_output_table() {
    local header="$1"; shift
    { printf '%s\n' "$header"; printf '%s\n' "$@"; } | column -t -s '|'
}

# Status string helpers for consistent styling.
dhis2_status_ok()   { dhis2_c_green  "$@"; }
dhis2_status_warn() { dhis2_c_yellow "$@"; }
dhis2_status_fail() { dhis2_c_red    "$@"; }