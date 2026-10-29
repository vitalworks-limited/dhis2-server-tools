# shellcheck shell=bash
# Pre-flight validation building blocks.

dhis2_validate_ubuntu_release() {
    if [[ ! -f /etc/os-release ]]; then
        echo "unknown-os:cannot-read-/etc/os-release"
        return 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        echo "unsupported-distro:${ID:-unknown}"
        return 1
    fi
    local v="${VERSION_ID//./}"
    if (( 10#$v < 2004 )); then
        echo "unsupported-release:${VERSION_ID}"
        return 1
    fi
    echo "ubuntu:${VERSION_ID}"
}

dhis2_validate_ansible_present() {
    command -v ansible-playbook >/dev/null 2>&1
}

dhis2_validate_python_present() {
    command -v python3 >/dev/null 2>&1
}

dhis2_validate_lxd_present() {
    command -v lxc >/dev/null 2>&1 || command -v lxd >/dev/null 2>&1
}

dhis2_validate_ufw_active() {
    if ! command -v ufw >/dev/null 2>&1; then
        echo "ufw-missing"
        return 1
    fi
    local s
    s=$(ufw status 2>/dev/null | awk '/Status:/ {print $2}')
    if [[ "$s" != "active" ]]; then
        echo "ufw-$s"
        return 1
    fi
    echo "ufw-active"
}

dhis2_validate_inventory_duplicates() {
    local inv="$1"
    local dupes
    dupes=$(awk '
        /^\[.*\]/ { next }
        /^#/ || NF==0 { next }
        { print $1 }
    ' "$inv" | sort | uniq -d)
    if [[ -n "$dupes" ]]; then
        echo "$dupes"
        return 1
    fi
    return 0
}

# Verify referenced database_host values resolve to real inventory hosts.
dhis2_validate_database_refs() {
    local inv="$1"
    local -a hosts
    mapfile -t hosts < <(awk '
        /^\[.*\]/ { next }
        /^#/ || NF==0 { next }
        { print $1 }
    ' "$inv" | sort -u)
    local -a bad=()
    local ref
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        local found=false
        local h
        for h in "${hosts[@]}"; do
            [[ "$h" == "$ref" ]] && { found=true; break; }
        done
        $found || bad+=("$ref")
    done < <(awk '
        /^\[.*\]/ { next }
        {
            for (i=1;i<=NF;i++) if ($i ~ /^database_host=/) { split($i,a,"="); print a[2] }
        }
    ' "$inv" | sort -u)
    if (( ${#bad[@]} )); then
        printf 'unresolved:%s\n' "${bad[@]}"
        return 1
    fi
    return 0
}

# Check SSH reachability for hosts that use ansible_connection=ssh.
dhis2_validate_ssh_reachability() {
    local inv="$1"
    local -a bad=()
    while IFS= read -r line; do
        local host ip
        host=$(echo "$line" | awk '{print $1}')
        ip=$(echo "$line" | grep -oE 'ansible_host=[^ ]+' | cut -d= -f2 || true)
        [[ -z "$ip" ]] && ip="$host"
        if ! command -v nc >/dev/null 2>&1 || ! nc -z -w 3 "$ip" 22 >/dev/null 2>&1; then
            bad+=("$host")
        fi
    done < <(awk '/ansible_connection=ssh/ && !/^#/' "$inv")
    if (( ${#bad[@]} )); then
        printf 'ssh-unreachable:%s\n' "${bad[@]}"
        return 1
    fi
    return 0
}

# Returns the configured proxy choice (defaults to nginx).
dhis2_validate_proxy_choice() {
    local inv="$1"
    local p
    p=$(awk -F= '/^[[:space:]]*proxy[[:space:]]*=/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' "$inv")
    [[ -z "$p" ]] && p="nginx"
    case "$p" in
        nginx|apache2|openresty) echo "$p"; return 0 ;;
        *) echo "invalid:$p"; return 1 ;;
    esac
}
