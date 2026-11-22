#!/bin/bash
set -euo pipefail

record_op() {
    local status="$1" category="$2" item="$3"
    if [[ -n "${OPERATIONS_FILE:-}" ]]; then
        printf '%s|%s|%s|%s\n' "${CURRENT_SCRIPT:-repo_update.sh}" "$status" "$category" "$item" >> "$OPERATIONS_FILE"
    fi
}

echo "Updating APT package lists..."
if sudo DEBIAN_FRONTEND=noninteractive apt-get update; then
    record_op "PASS" "APT" "Update package lists"
    echo "APT package lists updated."
else
    record_op "FAIL" "APT" "Update package lists"
    echo "Failed to update APT package lists."
    exit 1
fi

exit 0
