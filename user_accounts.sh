#!/bin/bash
set -uo pipefail

LOGFILE="/home/david/install_log.txt"
exec > >(tee -a "$LOGFILE") 2>&1

record_status() {
    local status="$1" cat="$2" item="$3"
    if declare -F record_op >/dev/null 2>&1; then
        record_op "$status" "$cat" "$item"
    fi
}

# Predefined users list
users=("drew" "sarah" "leslie")

rc=0
SELECTED=$(python3 - "${users[@]}" <<'PY'
import re
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

preset_users = sys.argv[1:]
USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")

class UserSelector(Gtk.Dialog):
    def __init__(self):
        super().__init__(
            title="Select Users to Add",
            modal=True,
            destroy_with_parent=True,
        )
        self.set_position(Gtk.WindowPosition.CENTER)

        height = 240 + (len(preset_users) * 38)
        display = Gdk.Display.get_default()
        if display and display.get_n_monitors() > 0:
            workarea = display.get_monitor(0).get_workarea()
            height = min(height, int(workarea.height * 0.85))
        self.set_default_size(540, max(360, height))

        self.add_button("Skip / Cancel", 99)
        ok_btn = self.add_button("Create Selected", Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)

        box = self.get_content_area()
        box.set_spacing(10)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(14)
        box.set_margin_end(14)

        header = Gtk.Label()
        header.set_xalign(0)
        header.set_markup("<b>Select Secondary User Accounts to Create</b>")
        box.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.master_check = Gtk.CheckButton(label="Select All")
        self.master_check.connect("toggled", self.on_master_toggled)
        toolbar.pack_start(self.master_check, False, False, 0)

        self.count_label = Gtk.Label(label=f"0 of {len(preset_users)} selected")
        toolbar.pack_end(self.count_label, False, False, 0)
        box.pack_start(toolbar, False, False, 0)

        self.store = Gtk.ListStore(bool, str)
        for u in preset_users:
            self.store.append([False, u])

        tree = Gtk.TreeView(model=self.store)
        tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        toggle = Gtk.CellRendererToggle()
        toggle.set_property("xpad", 8)
        toggle.connect("toggled", self.on_row_toggled)
        col_check = Gtk.TreeViewColumn("Add", toggle, active=0)
        col_check.set_fixed_width(58)
        col_check.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        tree.append_column(col_check)

        user_renderer = Gtk.CellRendererText()
        user_renderer.set_property("xpad", 10)
        user_renderer.set_property("ypad", 6)
        user_renderer.set_property("weight", Pango.Weight.BOLD)
        col_user = Gtk.TreeViewColumn("Username", user_renderer, text=1)
        col_user.set_expand(True)
        tree.append_column(col_user)

        tree.connect("row-activated", self.on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_shadow_type(Gtk.ShadowType.IN)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)

        # Custom username input row
        custom_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.custom_entry = Gtk.Entry()
        self.custom_entry.set_placeholder_text("Add custom username (e.g. alex)")
        self.custom_entry.set_hexpand(True)
        self.custom_entry.connect("activate", self.on_add_custom)

        add_btn = Gtk.Button(label="Add User")
        add_btn.connect("clicked", self.on_add_custom)

        custom_box.pack_start(self.custom_entry, True, True, 0)
        custom_box.pack_start(add_btn, False, False, 0)
        box.pack_start(custom_box, False, False, 0)

        self.status_lbl = Gtk.Label()
        self.status_lbl.set_xalign(0)
        self.status_lbl.set_no_show_all(True)
        box.pack_start(self.status_lbl, False, False, 0)

        self.show_all()

    def _set_status(self, msg, is_error=True):
        color = "#c01c28" if is_error else "#26a269"
        self.status_lbl.set_markup(f"<span foreground='{color}'>{msg}</span>")
        self.status_lbl.show()

    def on_add_custom(self, _widget):
        raw = self.custom_entry.get_text().strip()
        if not raw:
            self._set_status("Enter a username before clicking Add User.")
            return
        if not USERNAME_RE.match(raw):
            self._set_status(
                "Invalid username. Use lowercase letters, digits, '_' or '-', starting with a letter or '_' (max 32 chars)."
            )
            return

        existing = [r[1] for r in self.store]
        if raw in existing:
            for r in self.store:
                if r[1] == raw:
                    r[0] = True
            self.custom_entry.set_text("")
            self.sync_state()
            self._set_status(f"'{raw}' is already in the list and has been checked.", is_error=False)
            return

        self.store.append([True, raw])
        self.custom_entry.set_text("")
        self.sync_state()
        self._set_status(f"Added '{raw}' and selected it for creation.", is_error=False)

    def sync_state(self):
        total = len(self.store)
        checked = sum(1 for r in self.store if r[0])
        self.count_label.set_text(f"{checked} of {total} selected")
        self.master_check.handler_block_by_func(self.on_master_toggled)
        if checked == 0:
            self.master_check.set_inconsistent(False)
            self.master_check.set_active(False)
        elif checked == total:
            self.master_check.set_inconsistent(False)
            self.master_check.set_active(True)
        else:
            self.master_check.set_inconsistent(True)
        self.master_check.handler_unblock_by_func(self.on_master_toggled)

    def on_master_toggled(self, widget):
        widget.set_inconsistent(False)
        state = widget.get_active()
        for r in self.store:
            r[0] = state
        self.sync_state()

    def on_row_toggled(self, _r, path):
        self.store[path][0] = not self.store[path][0]
        self.sync_state()

    def on_row_activated(self, _t, path, _c):
        self.store[path][0] = not self.store[path][0]
        self.sync_state()

dlg = UserSelector()
resp = dlg.run()
selected = [r[1] for r in dlg.store if r[0]] if resp == Gtk.ResponseType.OK else []
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)
if not selected:
    sys.exit(99)

print(" ".join(selected))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped account creation."
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "Error opening user selector dialog (code $rc)."
    exit $rc
fi

if [[ -z "$SELECTED" ]]; then
    echo "No users selected. Skipping."
    exit 99
fi

prompt_new_user_password() {
    local target_user="$1"
    python3 - "$target_user" <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

username = sys.argv[1]

dlg = Gtk.Dialog(
    title=f"Set Password for {username}",
    modal=True,
    destroy_with_parent=True,
)
dlg.set_default_size(420, -1)
dlg.set_position(Gtk.WindowPosition.CENTER)
dlg.add_button("Cancel", Gtk.ResponseType.CANCEL)
ok_btn = dlg.add_button("Set Password", Gtk.ResponseType.OK)
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
lbl.set_markup(f"Enter a new login password for user <b>{GLib.markup_escape_text(username)}</b>:")
box.pack_start(lbl, False, False, 0)

pw1 = Gtk.Entry()
pw1.set_visibility(False)
pw1.set_invisible_char("•")
pw1.set_placeholder_text("New password")
box.pack_start(pw1, False, False, 0)

pw2 = Gtk.Entry()
pw2.set_visibility(False)
pw2.set_invisible_char("•")
pw2.set_placeholder_text("Confirm password")
pw2.set_activates_default(True)
box.pack_start(pw2, False, False, 0)

err_lbl = Gtk.Label()
err_lbl.set_xalign(0)
box.pack_start(err_lbl, False, False, 0)

dlg.show_all()
err_lbl.hide()
pw1.grab_focus()

while True:
    resp = dlg.run()
    if resp != Gtk.ResponseType.OK:
        dlg.destroy()
        sys.exit(1)
    p1 = pw1.get_text()
    p2 = pw2.get_text()
    if not p1:
        err_lbl.set_markup("<span foreground='red'>Password cannot be empty.</span>")
        err_lbl.show()
        continue
    if p1 != p2:
        err_lbl.set_markup("<span foreground='red'>Passwords do not match. Try again.</span>")
        err_lbl.show()
        pw2.set_text("")
        pw2.grab_focus()
        continue
    dlg.destroy()
    print(p1)
    sys.exit(0)
PY
}

failed_count=0
echo "Creating selected user account(s)..."

for user in $SELECTED; do
    if id "$user" &>/dev/null; then
        echo "User $user already exists. Skipping..."
        record_status "SKIPPED" "User Account" "$user (already exists)"
        continue
    fi

    echo "Creating user account for $user..."
    if ! sudo useradd -m -s /bin/bash "$user"; then
        echo "❌ Failed to create user account for $user."
        record_status "FAIL" "User Account" "$user (useradd failed)"
        ((failed_count++))
        continue
    fi

    user_pw=""
    if user_pw=$(prompt_new_user_password "$user"); then
        if printf '%s:%s\n' "$user" "$user_pw" | sudo chpasswd; then
            echo "✅ Created account and set password for $user."
            record_status "PASS" "User Account" "$user"
        else
            echo "❌ Failed to set password for $user."
            record_status "FAIL" "User Account" "$user (chpasswd failed)"
            ((failed_count++))
        fi
        unset user_pw
    else
        echo "❌ Password setup cancelled for $user (account left locked)."
        record_status "FAIL" "User Account" "$user (password cancelled)"
        ((failed_count++))
    fi
done

echo "Disabling root password for security purposes..."
if ! sudo passwd -l root; then
    echo "❌ Failed to lock root password."
    record_status "FAIL" "Security" "Lock root password"
    ((failed_count++))
else
    record_status "PASS" "Security" "Lock root password"
fi

if (( failed_count > 0 )); then
    echo "❌ Completed with $failed_count user account error(s)."
    exit 1
fi

echo "✅ All selected user accounts configured successfully."
