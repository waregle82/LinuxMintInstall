#!/bin/bash
set -euo pipefail

# =============================================================================
# Universal udev + systemd-mount Drive Automounter for Linux Mint
# Automatically mounts any arbitrary SATA, NVMe, USB, or SD storage partition
# under /media/<LABEL_or_UUID> at boot (pre-login) and on hotplug.
# =============================================================================

RULE_FILE="/etc/udev/rules.d/99-universal-automount.rules"
HELPER_BIN="/usr/local/sbin/universal-automount"
STATE_DIR="/run/universal-automount"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
TARGET_GID="$(id -g "$TARGET_USER" 2>/dev/null || echo 1000)"

record_status() {
    local status="$1" cat="$2" item="$3"
    if declare -F record_op >/dev/null 2>&1; then
        record_op "$status" "$cat" "$item"
    fi
}

select_action_gui() {
    python3 - <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

dlg = Gtk.Dialog(
    title="Universal Drive Automounter (udev + systemd-mount)",
    flags=Gtk.DialogFlags.MODAL,
)
dlg.set_position(Gtk.WindowPosition.CENTER)
dlg.set_default_size(520, 320)

dlg.add_button("Skip / Cancel", 99)
ok_btn = dlg.add_button("Apply", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
dlg.set_default_response(Gtk.ResponseType.OK)

box = dlg.get_content_area()
box.set_spacing(12)
box.set_margin_top(16)
box.set_margin_bottom(16)
box.set_margin_start(18)
box.set_margin_end(18)

header = Gtk.Label()
header.set_xalign(0.0)
header.set_line_wrap(True)
header.set_markup(
    "<b>Universal SATA &amp; USB Drive Automounter</b>\n"
    "<span size='small'>Automatically mounts any unconfigured SATA, NVMe, USB, or SD partition "
    "to <b>/media/&lt;Label-or-UUID&gt;</b> at boot (before login) and on hotplug, while skipping "
    "drives already managed in <b>/etc/fstab</b>.</span>"
)
box.pack_start(header, False, False, 0)

rb_install = Gtk.RadioButton.new_with_label_from_widget(
    None, "Install / Enable Universal Drive Automounter (Recommended)"
)
rb_install.set_active(True)
box.pack_start(rb_install, False, False, 4)

rb_remove = Gtk.RadioButton.new_with_label_from_widget(
    rb_install, "Uninstall / Disable Universal Drive Automounter"
)
box.pack_start(rb_remove, False, False, 4)

dlg.show_all()
resp = dlg.run()
action = "install" if rb_install.get_active() else "remove"
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)

print(action)
PY
}

install_automounter() {
    echo "Checking filesystem support packages (ntfs-3g, exfatprogs)..."
    local missing_pkgs=()
    for pkg in ntfs-3g exfatprogs; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if (( ${#missing_pkgs[@]} > 0 )); then
        echo "Installing ${missing_pkgs[*]}..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_pkgs[@]}"
    fi

    echo "Writing helper script to ${HELPER_BIN}..."
    sudo tee "$HELPER_BIN" >/dev/null <<EOF
#!/bin/bash
set -euo pipefail

ACTION="\${1:-}"
DEVNAME="\${2:-}"
DEVPATH="/dev/\${DEVNAME}"
STATE_DIR="${STATE_DIR}"
DEFAULT_UID="${TARGET_UID}"
DEFAULT_GID="${TARGET_GID}"

[[ -z "\$ACTION" || -z "\$DEVNAME" ]] && exit 0
mkdir -p "\$STATE_DIR"

sanitize_name() {
    printf '%s' "\$1" | tr -cs 'A-Za-z0-9._-' '_' | sed 's/^_\\+//; s/_\\+\$//'
}

do_add() {
    [[ -b "\$DEVPATH" ]] || exit 0

    # 1. Skip if already mounted anywhere
    if findmnt -rn -S "\$DEVPATH" >/dev/null 2>&1; then
        exit 0
    fi

    # 2. Skip if explicitly managed in /etc/fstab (root, /boot/efi, /home, custom mounts)
    if findmnt -rn --fstab -S "\$DEVPATH" >/dev/null 2>&1; then
        exit 0
    fi

    # 3. Verify block device contains a mountable filesystem
    local fs_usage fs_type fs_label fs_uuid
    fs_usage="\$(blkid -o value -s USAGE "\$DEVPATH" 2>/dev/null || true)"
    fs_type="\$(blkid -o value -s TYPE "\$DEVPATH" 2>/dev/null || true)"

    [[ "\$fs_usage" == "filesystem" && -n "\$fs_type" ]] || exit 0
    case "\$fs_type" in
        swap|LVM2_member|linux_raid_member|crypto_LUKS|zfs_member)
            exit 0
            ;;
    esac

    fs_label="\$(blkid -o value -s LABEL "\$DEVPATH" 2>/dev/null || true)"
    fs_uuid="\$(blkid -o value -s UUID "\$DEVPATH" 2>/dev/null || true)"

    local raw_name=""
    if [[ -n "\$fs_label" ]]; then
        raw_name="\$fs_label"
    elif [[ -n "\$fs_uuid" ]]; then
        raw_name="\$fs_uuid"
    else
        raw_name="\$DEVNAME"
    fi

    local clean_name
    clean_name="\$(sanitize_name "\$raw_name")"
    [[ -z "\$clean_name" ]] && clean_name="\$DEVNAME"

    local mount_point="/media/\${clean_name}"
    if mountpoint -q "\$mount_point" 2>/dev/null; then
        mount_point="/media/\${clean_name}_\${DEVNAME}"
    fi

    local mount_opts="defaults,nofail"
    case "\$fs_type" in
        vfat|exfat|ntfs|ntfs3)
            mount_opts="uid=\${DEFAULT_UID},gid=\${DEFAULT_GID},umask=0022,nofail"
            ;;
        ext2|ext3|ext4|btrfs|xfs)
            mount_opts="defaults,noatime,nofail"
            ;;
    esac

    printf '%s\n' "\$mount_point" > "\${STATE_DIR}/\${DEVNAME}"

    /usr/bin/systemd-mount \\
        --no-block \\
        --automount=no \\
        --collect \\
        --description="Universal Automount (\$DEVNAME)" \\
        --options="\$mount_opts" \\
        "\$DEVPATH" "\$mount_point"
}

do_remove() {
    local recorded_mp=""
    if [[ -f "\${STATE_DIR}/\${DEVNAME}" ]]; then
        recorded_mp="\$(cat "\${STATE_DIR}/\${DEVNAME}" 2>/dev/null || true)"
        rm -f "\${STATE_DIR}/\${DEVNAME}"
    fi

    /usr/bin/systemd-umount "\$DEVPATH" >/dev/null 2>&1 || true

    if [[ -n "\$recorded_mp" ]]; then
        /usr/bin/systemd-umount "\$recorded_mp" >/dev/null 2>&1 || true
        if [[ -d "\$recorded_mp" ]] && ! mountpoint -q "\$recorded_mp" 2>/dev/null; then
            rmdir "\$recorded_mp" 2>/dev/null || true
        fi
    fi
}

case "\$ACTION" in
    add)    do_add ;;
    remove) do_remove ;;
esac
EOF
    sudo chmod 0755 "$HELPER_BIN"

    echo "Installing udev rule to ${RULE_FILE}..."
    sudo tee "$RULE_FILE" >/dev/null <<'EOF'
# Universal SATA, NVMe, USB, and SD Block Partition Automounter
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*|nvme[0-9]*n[0-9]*p[0-9]*|mmcblk[0-9]*p[0-9]*", ENV{ID_FS_USAGE}=="filesystem", RUN+="/usr/local/sbin/universal-automount add %k"
ACTION=="remove", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*|nvme[0-9]*n[0-9]*p[0-9]*|mmcblk[0-9]*p[0-9]*", RUN+="/usr/local/sbin/universal-automount remove %k"
EOF
    sudo chmod 0644 "$RULE_FILE"

    # Disable Cinnamon's auto-open file manager popup on hotplug while keeping media handling clean
    if command -v gsettings >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" || -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        gsettings set org.cinnamon.desktop.media-handling automount-open false 2>/dev/null || true
    fi

    echo "Reloading udev rules and mounting any currently attached unmounted drives..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=block --action=add

    echo "[OK] Universal udev drive automounter enabled."
    record_status "PASS" "System Config" "Universal udev Drive Automounter (Enabled)"
}

remove_automounter() {
    echo "Removing universal udev drive automounter..."
    sudo rm -f "$RULE_FILE" "$HELPER_BIN"
    sudo rm -rf "$STATE_DIR"
    sudo udevadm control --reload-rules
    echo "[OK] Universal udev drive automounter removed."
    record_status "PASS" "System Config" "Universal udev Drive Automounter (Removed)"
}

ACTION=""
case "${1:-}" in
    --install|--yes|-y)
        ACTION="install"
        ;;
    --remove|--uninstall)
        ACTION="remove"
        ;;
    "")
        rc=0
        ACTION=$(select_action_gui) || rc=$?
        if [[ $rc -eq 99 ]]; then
            echo "[SKIP] User skipped Universal Drive Automounter setup."
            exit 99
        elif [[ $rc -ne 0 ]]; then
            echo "[FAIL] Automounter dialog exited with code $rc."
            exit "$rc"
        fi
        ;;
    *)
        echo "Usage: $0 [--install|--remove]" >&2
        exit 1
        ;;
esac

if [[ "$ACTION" == "install" ]]; then
    install_automounter
else
    remove_automounter
fi

exit 0
