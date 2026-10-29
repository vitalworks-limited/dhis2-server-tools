# shellcheck shell=bash
# Inventory parsing helpers for the current INI inventory format.
#
# These helpers prefer `ansible-inventory` where available (it understands
# the full inventory, host_vars, group_vars) and fall back to parsing the
# INI file directly for environments without Ansible installed yet.

# Returns 0 if ansible-inventory is usable, 1 otherwise.
_dhis2_inv_have_ansible_inventory() {
    command -v ansible-inventory >/dev/null 2>&1
}

# Prints JSON representation of the inventory to stdout.
dhis2_inventory_json() {
    local inv
    inv="$(dhis2_config_resolve_inventory)"
    if _dhis2_inv_have_ansible_inventory; then
        ansible-inventory -i "$inv" --list 2>/dev/null
    else
        _dhis2_inv_parse_ini_to_json "$inv"
    fi
}

# Prints a flat list of hosts.
dhis2_inventory_hosts() {
    local inv
    inv="$(dhis2_config_resolve_inventory)"
    if _dhis2_inv_have_ansible_inventory; then
        ansible-inventory -i "$inv" --list 2>/dev/null \
          | python3 -c 'import json,sys; d=json.load(sys.stdin); hs=d.get("_meta",{}).get("hostvars",{}); print("\n".join(sorted(hs.keys())))'
    else
        awk '
            /^\[.*\]/ { in_section=1; next }
            /^#/ || /^[[:space:]]*$/ { next }
            in_section { print $1 }
        ' "$inv" | sort -u
    fi
}

# Returns hosts in a given group (one per line).
dhis2_inventory_group_hosts() {
    local group="$1"
    local inv
    inv="$(dhis2_config_resolve_inventory)"
    if _dhis2_inv_have_ansible_inventory; then
        ansible-inventory -i "$inv" --list 2>/dev/null \
          | python3 -c "import json,sys; d=json.load(sys.stdin); g=d.get('$group',{}); print('\n'.join(g.get('hosts',[])))"
    else
        awk -v g="$group" '
            /^\[/ { section=substr($0,2,length($0)-2); next }
            section==g && !/^#/ && NF>0 { print $1 }
        ' "$inv"
    fi
}

# Pretty-prints inventory host variables for a host, with secrets redacted.
dhis2_inventory_host_vars_redacted() {
    local host="$1"
    local inv
    inv="$(dhis2_config_resolve_inventory)"
    if _dhis2_inv_have_ansible_inventory; then
        ansible-inventory -i "$inv" --host "$host" 2>/dev/null \
          | dhis2_log_redact
    else
        awk -v h="$host" '$1==h { for (i=2;i<=NF;i++) print $i }' "$inv" \
          | dhis2_log_redact
    fi
}

# Simple INI → JSON parser used when Ansible is not installed yet.
_dhis2_inv_parse_ini_to_json() {
    local file="$1"
    python3 - "$file" <<'PY'
import json, re, sys
path = sys.argv[1]
groups = {}
section = None
with open(path) as f:
    for raw in f:
        line = raw.split('#',1)[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r'^\[(.+)\]$', line.strip())
        if m:
            section = m.group(1).strip()
            if ':' in section:
                base, kind = section.split(':',1)
                groups.setdefault(base, {})
                groups[base][kind] = {} if kind=='vars' else []
            else:
                groups.setdefault(section, {'hosts': [], 'vars': {}, 'children': []})
            continue
        if section is None:
            continue
        parts = line.strip().split()
        if ':' in section:
            base, kind = section.split(':',1)
            if kind == 'vars':
                k,_,v = parts[0].partition('=')
                groups[base]['vars'][k] = v
            elif kind == 'children':
                groups[base]['children'].append(parts[0])
        else:
            host = parts[0]
            hv = {}
            for kv in parts[1:]:
                if '=' in kv:
                    k,_,v = kv.partition('=')
                    hv[k]=v
            groups[section]['hosts'].append(host)
            groups.setdefault('_meta', {}).setdefault('hostvars', {})[host] = hv
print(json.dumps(groups, indent=2))
PY
}

# Safe inventory writes: creates a timestamped backup, writes atomically,
# re-reads to validate, rolls back on failure. - section 13.3
dhis2_inventory_safe_write() {
    local src="$1" dest="$2"
    local backup
    backup="${dest}.$(date -u +%Y%m%d-%H%M%S).bak"
    [[ -f "$dest" ]] && cp -p "$dest" "$backup"
    local tmp
    tmp="$(mktemp "${dest}.XXXXXX")"
    cat "$src" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$dest"
    if ! dhis2_inventory_validate_syntax "$dest"; then
        dhis2_log_error "Validation failed - rolling back from $backup"
        [[ -f "$backup" ]] && mv -f "$backup" "$dest"
        return 1
    fi
    dhis2_log_info "Wrote inventory (backup: $backup)"
}

dhis2_inventory_validate_syntax() {
    local inv="$1"
    if _dhis2_inv_have_ansible_inventory; then
        ansible-inventory -i "$inv" --list >/dev/null
    else
        _dhis2_inv_parse_ini_to_json "$inv" >/dev/null
    fi
}
