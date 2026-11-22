#!/bin/bash
set -uo pipefail

# =============================================================================
# ACCOUNTSERVICE USER AVATARS CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AVATAR_DIR="${AVATAR_DIR:-/mnt/david/_config/icons/family}"

record_op() {
    local status="$1" category="$2" item="$3"
    if [[ -n "${OPERATIONS_FILE:-}" ]]; then
        printf '%s|%s|%s|%s\n' "${CURRENT_SCRIPT:-user_avatars.sh}" "$status" "$category" "$item" >> "$OPERATIONS_FILE"
    fi
}

get_system_users() {
    awk -F: '
        $3 >= 1000 && $1 != "nobody" && $7 !~ /(nologin|false|sync|halt|shutdown)$/ {
            print $1
        }
    ' /etc/passwd
}

mapfile -t ALL_USERS < <(get_system_users)

if [[ ${#ALL_USERS[@]} -eq 0 ]]; then
    echo "No regular system user accounts found in /etc/passwd."
    record_op "SKIPPED" "User Avatar" "No eligible system users"
    exit 99
fi

select_users_gui() {
    python3 - "$AVATAR_DIR" "${ALL_USERS[@]}" <<'PY'
import os
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

avatar_dir = sys.argv[1]
users = sys.argv[2:]

def find_avatar(username):
    for ext in (".png", ".jpg", ".jpeg", ".webp"):
        p = os.path.join(avatar_dir, f"{username}{ext}")
        if os.path.isfile(p):
            return p
    return ""

dlg = Gtk.Dialog(
    title="Select Users for Login Avatars",
    modal=True,
    destroy_with_parent=True,
)
dlg.set_position(Gtk.WindowPosition.CENTER)
dlg.set_border_width(12)

row_h = 36
chrome_h = 185
desired_h = chrome_h + (len(users) * row_h)
desired_w = 600

max_h = 800
display = Gdk.Display.get_default()
if display is not None:
    mon = display.get_primary_monitor() or display.get_monitor(0)
    if mon is not None:
        wa = mon.get_workarea()
        max_h = int(wa.height * 0.85)
        desired_w = min(desired_w, int(wa.width * 0.90))

dlg.set_default_size(desired_w, max(340, min(desired_h, max_h)))

dlg.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
ok_btn = dlg.add_button("Apply Avatars", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
ok_btn.set_sensitive(False)
dlg.set_default_response(Gtk.ResponseType.OK)

box = dlg.get_content_area()
box.set_spacing(10)

header = Gtk.Label()
header.set_xalign(0)
header.set_markup(
    f"<b>Select System Users to Configure Login Avatars</b>\n"
    f"<span size='small'>Looking for <b>&lt;username&gt;.png</b> (or image) in <b>{avatar_dir}</b>.</span>"
)
box.pack_start(header, False, False, 0)

toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
master_check = Gtk.CheckButton(label="Select All")
count_label = Gtk.Label(label=f"0 of {len(users)} selected")
count_label.set_xalign(1)
toolbar.pack_start(master_check, False, False, 0)
toolbar.pack_end(count_label, False, False, 0)
box.pack_start(toolbar, False, False, 0)

# [selected, username, avatar_file_status]
store = Gtk.ListStore(bool, str, str)
for u in users:
    found = find_avatar(u)
    status_txt = os.path.basename(found) if found else "Not found in folder"
    store.append([False, u, status_txt])

tree = Gtk.TreeView(model=store)
tree.set_headers_visible(True)
tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

toggle = Gtk.CellRendererToggle()
toggle.set_property("xpad", 8)
col_chk = Gtk.TreeViewColumn("Apply", toggle, active=0)
col_chk.set_fixed_width(64)
col_chk.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
tree.append_column(col_chk)

r_user = Gtk.CellRendererText()
r_user.set_property("xpad", 10)
r_user.set_property("ypad", 6)
r_user.set_property("weight", Pango.Weight.BOLD)
col_user = Gtk.TreeViewColumn("Username", r_user, text=1)
col_user.set_min_width(160)
tree.append_column(col_user)

r_file = Gtk.CellRendererText()
r_file.set_property("xpad", 10)
r_file.set_property("ypad", 6)
col_file = Gtk.TreeViewColumn("Avatar Source", r_file, text=2)
col_file.set_expand(True)
tree.append_column(col_file)

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

if resp != Gtk.ResponseType.OK or not selected:
    sys.exit(99)

for item in selected:
    print(item)
PY
}

find_user_avatar() {
    local username="$1"
    local ext
    for ext in png jpg jpeg webp; do
        if [[ -f "${AVATAR_DIR}/${username}.${ext}" ]]; then
            printf '%s\n' "${AVATAR_DIR}/${username}.${ext}"
            return 0
        fi
    done
    return 1
}

rc=0
SELECTED_OUTPUT=$(select_users_gui) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped avatar selection."
    record_op "SKIPPED" "User Avatar" "All users"
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "Error: Avatar selection dialog failed (code $rc)."
    exit "$rc"
fi

mapfile -t SELECTED_USERS <<< "$SELECTED_OUTPUT"
if [[ ${#SELECTED_USERS[@]} -eq 0 ]]; then
    echo "No users selected. Skipping."
    exit 99
fi

sudo mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users

failed_count=0
updated_count=0

for user in "${SELECTED_USERS[@]}"; do
    avatar_img="$(find_user_avatar "$user" || true)"
    local_icon="/var/lib/AccountsService/icons/${user}"
    account_file="/var/lib/AccountsService/users/${user}"

    if [[ -n "$avatar_img" && -f "$avatar_img" ]]; then
        echo "Updating avatar for user: $user (from $avatar_img)"
        if sudo cp "$avatar_img" "$local_icon" && sudo bash -c "cat > '$account_file' <<EOF
[User]
Icon=$local_icon
EOF"; then
            record_op "PASS" "User Avatar" "$user"
            ((updated_count++))
        else
            echo "[✘] Failed to update avatar for user: $user"
            record_op "FAIL" "User Avatar" "$user"
            ((failed_count++))
        fi
    else
        echo "⚠️  Avatar for user '$user' not found in $AVATAR_DIR"
        record_op "FAIL" "User Avatar" "$user (missing source)"
        ((failed_count++))
    fi
done

sudo systemctl restart accounts-daemon.service

if (( failed_count > 0 )); then
    echo "⚠️  Avatar update completed with $failed_count missing/failed item(s)."
    exit 1
fi

echo "✅ Avatar update complete ($updated_count updated)."
exit 0
