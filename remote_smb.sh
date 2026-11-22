#!/bin/bash
set -uo pipefail

# =============================================================================
# REMOTE SMB SHARES CONFIGURATION
# =============================================================================
CREDENTIALS_FILE="${HOME:-/home/david}/.smbcredentials"
MOUNT_BASE="/mnt"
ALL_SHARES=(data david eveleighpro HOUSESHARE isos prusa roms shield)
SERVER_IP="192.168.34.8"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

record_op() {
    local status="$1" category="$2" item="$3"
    if [[ -n "${OPERATIONS_FILE:-}" ]]; then
        printf '%s|%s|%s|%s\n' "${CURRENT_SCRIPT:-remote_smb.sh}" "$status" "$category" "$item" >> "$OPERATIONS_FILE"
    fi
}

# =============================================================================
# 1. GTK3 SMB SHARE SELECTION CHECKLIST
# =============================================================================
select_shares_gui() {
    python3 - "${ALL_SHARES[@]}" <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

shares = sys.argv[1:]

dlg = Gtk.Dialog(
    title="Select SMB Shares to Mount",
    modal=True,
    destroy_with_parent=True,
)
dlg.set_position(Gtk.WindowPosition.CENTER)
dlg.set_border_width(12)

row_h = 36
chrome_h = 185
desired_h = chrome_h + (len(shares) * row_h)
desired_w = 540

max_h = 800
display = Gdk.Display.get_default()
if display is not None:
    mon = display.get_primary_monitor() or display.get_monitor(0)
    if mon is not None:
        wa = mon.get_workarea()
        max_h = int(wa.height * 0.85)
        desired_w = min(desired_w, int(wa.width * 0.90))

dlg.set_default_size(desired_w, max(360, min(desired_h, max_h)))

skip_btn = dlg.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
ok_btn = dlg.add_button("Mount Selected", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
ok_btn.set_sensitive(False)
dlg.set_default_response(Gtk.ResponseType.OK)

box = dlg.get_content_area()
box.set_spacing(10)

header = Gtk.Label()
header.set_xalign(0)
header.set_markup(
    "<b>Select Remote SMB Shares to Mount</b>\n"
    "<span size='small'>Selected shares from <b>192.168.34.8</b> will be configured in /etc/fstab, mounted, and bookmarked in Nemo.</span>"
)
box.pack_start(header, False, False, 0)

toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
master_check = Gtk.CheckButton(label="Select All")
count_label = Gtk.Label(label=f"0 of {len(shares)} selected")
count_label.set_xalign(1)
toolbar.pack_start(master_check, False, False, 0)
toolbar.pack_end(count_label, False, False, 0)
box.pack_start(toolbar, False, False, 0)

store = Gtk.ListStore(bool, str, str)
for s in shares:
    store.append([False, s, f"/mnt/{s}"])

tree = Gtk.TreeView(model=store)
tree.set_headers_visible(True)
tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

toggle = Gtk.CellRendererToggle()
toggle.set_property("xpad", 8)
col_chk = Gtk.TreeViewColumn("Mount", toggle, active=0)
col_chk.set_fixed_width(64)
col_chk.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
tree.append_column(col_chk)

r_name = Gtk.CellRendererText()
r_name.set_property("xpad", 10)
r_name.set_property("ypad", 6)
r_name.set_property("weight", Pango.Weight.BOLD)
col_name = Gtk.TreeViewColumn("Share Name", r_name, text=1)
col_name.set_min_width(180)
tree.append_column(col_name)

r_path = Gtk.CellRendererText()
r_path.set_property("xpad", 10)
r_path.set_property("ypad", 6)
col_path = Gtk.TreeViewColumn("Local Mount Point", r_path, text=2)
col_path.set_expand(True)
tree.append_column(col_path)

def sync_state():
    total = len(store)
    checked = sum(1 for row in store if row[0])
    count_label.set_text(f"{checked} of {total} selected")
    ok_btn.set_sensitive(checked > 0)
    master_check.handler_block_by_func(on_master)
    if checked == 0:
        master_check.set_inconsistent(False)
        master_check.set_active(False)
    elif checked == total:
        master_check.set_inconsistent(False)
        master_check.set_active(True)
    else:
        master_check.set_inconsistent(True)
    master_check.handler_unblock_by_func(on_master)

def on_master(btn):
    btn.set_inconsistent(False)
    state = btn.get_active()
    for row in store:
        row[0] = state
    sync_state()

def on_toggle(_renderer, path):
    store[path][0] = not store[path][0]
    sync_state()

def on_activate(_tree, path, _col):
    store[path][0] = not store[path][0]
    sync_state()

master_check.connect("toggled", on_master)
toggle.connect("toggled", on_toggle)
tree.connect("row-activated", on_activate)

scroll = Gtk.ScrolledWindow()
scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
scroll.set_shadow_type(Gtk.ShadowType.IN)
scroll.add(tree)
box.pack_start(scroll, True, True, 0)

dlg.show_all()
resp = dlg.run()
selected = [row[1] for row in store if row[0]]
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)

if not selected:
    sys.exit(99)

for item in selected:
    print(item)
PY
}

rc=0
SELECTED_OUTPUT=$(select_shares_gui) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped SMB share selection."
    record_op "SKIPPED" "SMB Mount" "All SMB shares"
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "Error: SMB share selection dialog failed (code $rc)."
    exit $rc
fi

mapfile -t SHARES <<< "$SELECTED_OUTPUT"
if [[ ${#SHARES[@]} -eq 0 ]]; then
    echo "No shares selected. Skipping."
    exit 99
fi

echo "Selected ${#SHARES[@]} SMB share(s): ${SHARES[*]}"

# =============================================================================
# 2. ENSURE REQUIRED PACKAGES
# =============================================================================
echo "Checking required packages (cifs-utils, curl)..."
if ! sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq || \
   ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cifs-utils curl >/dev/null 2>&1; then
    echo "Error: Failed to install required packages (cifs-utils, curl)."
    exit 1
fi

# =============================================================================
# 3. GTK3 SMB CREDENTIALS DIALOG
# =============================================================================
prompt_smb_credentials_gui() {
    python3 - "$CREDENTIALS_FILE" "$USER_ID" "$GROUP_ID" <<'PY'
import sys
import subprocess
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

cred_path, uid, gid = sys.argv[1], sys.argv[2], sys.argv[3]

error_msg = ""
while True:
    dlg = Gtk.Dialog(
        title="SMB Network Credentials",
        modal=True,
    destroy_with_parent=True,
    )
    dlg.set_default_size(440, -1)
    dlg.set_position(Gtk.WindowPosition.CENTER)
    dlg.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
    ok_btn = dlg.add_button("Save Credentials", Gtk.ResponseType.OK)
    ok_btn.get_style_context().add_class("suggested-action")
    dlg.set_default_response(Gtk.ResponseType.OK)

    box = dlg.get_content_area()
    box.set_spacing(10)
    box.set_margin_top(14)
    box.set_margin_bottom(14)
    box.set_margin_start(16)
    box.set_margin_end(16)

    lbl = Gtk.Label()
    lbl.set_xalign(0)
    lbl.set_line_wrap(True)
    markup = (
        "<b>Enter SMB Credentials for 192.168.34.8</b>\n"
        "<span size='small'>Credentials will be stored securely (chmod 600) in ~/.smbcredentials.</span>"
    )
    if error_msg:
        markup += f"\n<span foreground='#c01c28'><b>{GLib.markup_escape_text(error_msg)}</b></span>"
    lbl.set_markup(markup)
    box.pack_start(lbl, False, False, 0)

    grid = Gtk.Grid(column_spacing=10, row_spacing=8)
    grid.set_margin_top(6)

    user_entry = Gtk.Entry()
    user_entry.set_placeholder_text("SMB Username")
    user_entry.set_hexpand(True)

    pass_entry = Gtk.Entry()
    pass_entry.set_visibility(False)
    pass_entry.set_invisible_char("•")
    pass_entry.set_placeholder_text("SMB Password")
    pass_entry.set_hexpand(True)

    dom_entry = Gtk.Entry()
    dom_entry.set_text("WORKGROUP")
    dom_entry.set_hexpand(True)
    dom_entry.set_activates_default(True)

    grid.attach(Gtk.Label(label="Username:", xalign=0), 0, 0, 1, 1)
    grid.attach(user_entry, 1, 0, 1, 1)
    grid.attach(Gtk.Label(label="Password:", xalign=0), 0, 1, 1, 1)
    grid.attach(pass_entry, 1, 1, 1, 1)
    grid.attach(Gtk.Label(label="Domain:", xalign=0), 0, 2, 1, 1)
    grid.attach(dom_entry, 1, 2, 1, 1)

    box.pack_start(grid, False, False, 0)
    dlg.show_all()
    user_entry.grab_focus()

    resp = dlg.run()
    u = user_entry.get_text().strip()
    p = pass_entry.get_text()
    d = dom_entry.get_text().strip() or "WORKGROUP"
    dlg.destroy()

    if resp != Gtk.ResponseType.OK:
        sys.exit(99)

    if not u or not p:
        error_msg = "Both username and password are required."
        continue

    content = f"username={u}\npassword={p}\ndomain={d}\n"
    p = ""
    del p

    res = subprocess.run(
        ["sudo", "tee", cred_path],
        input=content,
        text=True,
        stdout=subprocess.DEVNULL,
        check=False,
    )
    content = ""
    del content

    if res.returncode != 0:
        sys.exit(1)

    subprocess.run(["sudo", "chmod", "600", cred_path], check=False)
    subprocess.run(["sudo", "chown", f"{uid}:{gid}", cred_path], check=False)
    sys.exit(0)
PY
}

confirm_overwrite_gui() {
    python3 - "$CREDENTIALS_FILE" <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

dlg = Gtk.MessageDialog(
    modal=True,
    destroy_with_parent=True,
    message_type=Gtk.MessageType.QUESTION,
    buttons=Gtk.ButtonsType.NONE,
    text="Existing SMB Credentials Found",
)
dlg.format_secondary_text(
    f"A credentials file already exists at:\n{sys.argv[1]}\n\n"
    "Would you like to reuse the existing credentials or enter new ones?"
)
dlg.add_button("Cancel", Gtk.ResponseType.CANCEL)
dlg.add_button("Overwrite", Gtk.ResponseType.YES)
use_btn = dlg.add_button("Use Existing", Gtk.ResponseType.NO)
use_btn.get_style_context().add_class("suggested-action")
dlg.set_default_response(Gtk.ResponseType.NO)

resp = dlg.run()
dlg.destroy()

if resp == Gtk.ResponseType.YES:
    sys.exit(10)
elif resp == Gtk.ResponseType.NO:
    sys.exit(0)
else:
    sys.exit(99)
PY
}

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    cred_rc=0
    prompt_smb_credentials_gui || cred_rc=$?
    if [[ $cred_rc -eq 99 ]]; then
        echo "User cancelled SMB credentials entry."
        exit 99
    elif [[ $cred_rc -ne 0 ]]; then
        echo "Error: Failed to save SMB credentials."
        exit 1
    fi
    echo "Created credentials file at $CREDENTIALS_FILE"
else
    ov_rc=0
    confirm_overwrite_gui || ov_rc=$?
    if [[ $ov_rc -eq 10 ]]; then
        cred_rc=0
        prompt_smb_credentials_gui || cred_rc=$?
        if [[ $cred_rc -eq 99 ]]; then
            echo "User cancelled SMB credentials overwrite."
            exit 99
        elif [[ $cred_rc -ne 0 ]]; then
            echo "Error: Failed to overwrite SMB credentials."
            exit 1
        fi
        echo "Updated credentials file at $CREDENTIALS_FILE"
    elif [[ $ov_rc -eq 0 ]]; then
        echo "Using existing credentials file at $CREDENTIALS_FILE"
    else
        echo "User cancelled SMB setup."
        exit 99
    fi
fi

# =============================================================================
# 4. CREATE MOUNT POINTS, UPDATE /etc/fstab, MOUNT & BOOKMARK SELECTED SHARES
# =============================================================================
failed_count=0

for share in "${SHARES[@]}"; do
    mount_point="$MOUNT_BASE/$share"

    # Recover only /mnt/david when it has a stale filesystem/mount handle.
    # Other mount points retain their existing setup behavior.
    if [[ "$share" == "david" ]]; then
        if ! sudo stat "$mount_point" >/dev/null 2>&1; then
            echo "Warning: $mount_point is inaccessible (possible stale handle). Attempting targeted recovery..."
            # Lazy detach is safe to attempt even if mountpoint detection is unreliable.
            sudo umount -l "$mount_point" >/dev/null 2>&1 || true
            # rmdir only removes an empty directory; it will not delete share data.
            sudo rmdir "$mount_point" >/dev/null 2>&1 || true
            if ! sudo mkdir -p "$mount_point" || ! sudo stat "$mount_point" >/dev/null 2>&1; then
                echo "Error: Could not recover mount-point directory $mount_point"
                record_op "FAIL (mount-point recovery)" "SMB Mount" "$share"
                ((failed_count++))
                continue
            fi
            echo "Recovered mount-point directory: $mount_point"
        fi
    else
        if [[ ! -d "$mount_point" ]]; then
            echo "Creating mount point: $mount_point"
            if ! sudo mkdir -p "$mount_point"; then
                echo "Error: Failed to create directory $mount_point"
                record_op "FAIL (mkdir)" "SMB Mount" "$share"
                ((failed_count++))
                continue
            fi
        fi
    fi

    share_path="//${SERVER_IP}/${share,,}"
    fstab_line="${share_path} ${mount_point} cifs credentials=${CREDENTIALS_FILE},uid=${USER_ID},gid=${GROUP_ID},iocharset=utf8,_netdev,nofail,x-systemd.automount 0 0"

    if ! grep -qsE "[[:space:]]${mount_point}[[:space:]]" /etc/fstab; then
        echo "Adding $share to /etc/fstab"
        if ! echo "$fstab_line" | sudo tee -a /etc/fstab >/dev/null; then
            echo "Error: Failed to write $share entry to /etc/fstab"
            record_op "FAIL (fstab)" "SMB Mount" "$share"
            ((failed_count++))
            continue
        fi
    else
        echo "Entry for $mount_point already exists in /etc/fstab, skipping."
    fi
done

echo "Reloading systemd daemon and activating automounts..."
if ! sudo systemctl daemon-reload || ! sudo systemctl restart remote-fs.target; then
    echo "Error: Failed to reload systemd / restart remote-fs.target"
    ((failed_count++))
fi

BOOKMARKS_FILE="${HOME:-/home/david}/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$BOOKMARKS_FILE")"
touch "$BOOKMARKS_FILE"

for share in "${SHARES[@]}"; do
    mount_point="$MOUNT_BASE/$share"
    ls "$mount_point" >/dev/null 2>&1 || true

    if mountpoint -q "$mount_point"; then
        echo "Mounted: $mount_point"
        record_op "PASS" "SMB Mount" "$share ($mount_point)"

        bookmark="file://${mount_point} ${share}"
        if ! grep -qxF "$bookmark" "$BOOKMARKS_FILE"; then
            echo "$bookmark" >> "$BOOKMARKS_FILE"
            echo "Bookmarked in Nemo: $share"
        fi
    else
        echo "Error: Failed to mount $mount_point"
        record_op "FAIL (mount)" "SMB Mount" "$share ($mount_point)"
        ((failed_count++))
    fi
done

sudo chown -R "${USER_ID}:${GROUP_ID}" "$(dirname "$BOOKMARKS_FILE")" 2>/dev/null || true

if [[ $failed_count -gt 0 ]]; then
    echo "Completed with $failed_count SMB error(s)."
    exit 1
fi

echo "All selected SMB shares mounted, bookmarked in Nemo, and configured for automount!"
exit 0
