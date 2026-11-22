#!/bin/bash
set -euo pipefail

record_op() {
    local status="$1" category="$2" item="$3"
    if [[ -n "${OPERATIONS_FILE:-}" ]]; then
        printf '%s|%s|%s|%s\n' "${CURRENT_SCRIPT:-repo_upgrade.sh}" "$status" "$category" "$item" >> "$OPERATIONS_FILE"
    fi
}

echo "Upgrading installed packages..."
if sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
    record_op "PASS" "APT" "Upgrade installed packages"
else
    record_op "FAIL" "APT" "Upgrade installed packages"
    echo "Failed to upgrade installed packages."
    exit 1
fi

echo "Removing unused dependencies..."
if sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y; then
    record_op "PASS" "APT" "Autoremove unused dependencies"
else
    record_op "FAIL" "APT" "Autoremove unused dependencies"
    echo "Failed to remove unused dependencies."
    exit 1
fi

echo "Package upgrades and cleanup complete."
exit 0
