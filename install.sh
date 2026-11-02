#!/usr/bin/env bash
# install.sh - idempotent installer for the dhis2-* CLI family.
#
# Installs the toolset at /opt/dhis2-server-tools and creates
# /usr/local/bin links. Preserves local inventory and existing state.
#
# Usage:
#   sudo ./install.sh              # install from this checkout
#   sudo ./install.sh --prefix /opt/dhis2-server-tools
#   sudo ./install.sh --uninstall  # remove links (keeps data)
#   sudo ./install.sh --version    # print version
#
set -Eeuo pipefail

PREFIX="/opt/dhis2-server-tools"
BINDIR="/usr/local/bin"
ACTION="install"

while (( $# )); do
    case "$1" in
        --prefix) PREFIX="${2:-$PREFIX}"; shift ;;
        --prefix=*) PREFIX="${1#*=}" ;;
        --bindir) BINDIR="${2:-$BINDIR}"; shift ;;
        --bindir=*) BINDIR="${1#*=}" ;;
        --uninstall) ACTION=uninstall ;;
        --version) ACTION=version ;;
        -h|--help)
            awk 'NR>2 && /^#/ {sub(/^# ?/,""); print} /^set/ {exit}' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift || true
done

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$SRC_DIR/VERSION" 2>/dev/null || echo "0.0.0-dev")

if [[ "$ACTION" == version ]]; then
    echo "dhis2-server-tools $VERSION"
    exit 0
fi

if [[ $EUID -ne 0 && "$PREFIX" == /opt* ]]; then
    echo "Installer requires root for prefix $PREFIX. Re-run with sudo." >&2
    exit 1
fi

commands=(
    dhis2-deploy dhis2-host dhis2-inventory dhis2-instance dhis2-db
    dhis2-backup dhis2-restore dhis2-upgrade dhis2-proxy dhis2-tls
    dhis2-monitor dhis2-logs dhis2-doctor dhis2-security dhis2-vpn
    dhis2-doris dhis2-integration dhis2-vault dhis2-status
    dhis2-cluster
)

if [[ "$ACTION" == uninstall ]]; then
    for c in "${commands[@]}"; do
        link="$BINDIR/$c"
        [[ -L "$link" ]] && rm -f "$link"
    done
    # Stop and remove the WAL watchdog timer, leaving its log file in
    # place for operator reference.
    if [[ $EUID -eq 0 ]]; then
        systemctl disable --now dhis2-wal-watchdog.timer 2>/dev/null || true
        rm -f /etc/systemd/system/dhis2-wal-watchdog.service \
              /etc/systemd/system/dhis2-wal-watchdog.timer
        systemctl daemon-reload 2>/dev/null || true
    fi
    echo "Removed symlinks from $BINDIR and the WAL watchdog unit. $PREFIX and state directories left untouched."
    exit 0
fi

# install
echo "Installing dhis2-server-tools $VERSION -> $PREFIX"
mkdir -p "$PREFIX"
# Copy repository tree except transient directories.
rsync -a --delete \
    --exclude '.git' --exclude '.github' --exclude '.idea' \
    --exclude 'log' --exclude 'deploy/log' --exclude 'molecule' \
    "$SRC_DIR"/ "$PREFIX"/

# Protect any existing user inventory under /etc.
mkdir -p /etc/dhis2-server-tools /var/log/dhis2-server-tools /var/lib/dhis2-server-tools
chmod 750 /etc/dhis2-server-tools /var/log/dhis2-server-tools /var/lib/dhis2-server-tools

# WAL Phase 2: install the dhis2-wal-watchdog systemd timer. Runs
# every 5 minutes against the local DB host and exits non-zero when
# any WAL threshold is breached - journald marks the unit as FAILED
# which the operator's existing alerting can catch. See
# docs/CLI-WAL-Operations.md section 'Phase 2 watchdog'.
if [[ -d /etc/systemd/system && $EUID -eq 0 ]]; then
    install -m 0644 "$PREFIX/share/systemd/dhis2-wal-watchdog.service" /etc/systemd/system/
    install -m 0644 "$PREFIX/share/systemd/dhis2-wal-watchdog.timer"   /etc/systemd/system/
    systemctl daemon-reload 2>/dev/null || true
    # Only enable automatically when a [databases] host is reachable
    # from the controller - the watchdog is DB-aware. Operators who
    # want it elsewhere enable manually.
    if command -v dhis2-inventory >/dev/null 2>&1 && \
       dhis2-inventory list 2>/dev/null | grep -q '\[databases\]'; then
        systemctl enable --now dhis2-wal-watchdog.timer 2>/dev/null || true
        echo "  enabled dhis2-wal-watchdog.timer (5-min WAL safety check)"
    else
        echo "  installed dhis2-wal-watchdog.timer (enable with: systemctl enable --now dhis2-wal-watchdog.timer)"
    fi
fi

# Install logrotate for CLI audit + bundle growth (section 30).
if [[ -d /etc/logrotate.d && $EUID -eq 0 ]]; then
    cat >/etc/logrotate.d/dhis2-server-tools <<'EOF'
/var/log/dhis2-server-tools/*.log /var/log/dhis2-server-tools/*.ndjson {
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 root root
}

/var/log/dhis2-server-tools/bundles/*.tgz {
    monthly
    rotate 6
    missingok
    notifempty
    nocreate
    nocompress
}
EOF
    chmod 0644 /etc/logrotate.d/dhis2-server-tools
    echo "  installed /etc/logrotate.d/dhis2-server-tools (weekly audit rotation, 12-week retention)"
fi

# Ensure executable bits on bin/.
chmod -R a+rX "$PREFIX"
find "$PREFIX/bin" -type f -exec chmod 0755 {} +

mkdir -p "$BINDIR"
for c in "${commands[@]}"; do
    link="$BINDIR/$c"
    target="$PREFIX/bin/$c"
    if [[ ! -f "$target" ]]; then
        echo "  skip (not built): $c"
        continue
    fi
    ln -sfn "$target" "$link"
    echo "  linked $link -> $target"
done

echo
echo "Installed. Verify with:  dhis2-deploy --version"
