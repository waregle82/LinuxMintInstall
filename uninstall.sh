#!/bin/bash
set -uo pipefail

LOGFILE="/home/david/install_log.txt"

record_status() {
    local status="$1" cat="$2" item="$3"
    if declare -F record_op >/dev/null 2>&1; then
        record_op "$status" "$cat" "$item"
    fi
}

default_packages=(
  "thunderbird"
  "celluloid"
  "transmission-gtk"
  "hypnotix"
  "mpv"
  "rhythmbox"
)

rc=0
GUI_OUT=$(python3 - <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

pkgs = ["thunderbird", "celluloid", "transmission-gtk", "hypnotix", "mpv", "rhythmbox"]

class UninstallSelector(Gtk.Dialog):
    def __init__(self):
        super().__init__(title="Uninstall Unwanted Applications", flags=Gtk.DialogFlags.MODAL)
        self.set_position(Gtk.WindowPosition.CENTER)

        height = 240 + (len(pkgs) * 38)
        display = Gdk.Display.get_default()
        if display and display.get_n_monitors() > 0:
            workarea = display.get_monitor(0).get_workarea()
            height = min(height, int(workarea.height * 0.85))
        self.set_default_size(560, max(360, height))

        self.add_button("Skip / Cancel", 99)
        ok_btn = self.add_button("Remove Selected", Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class("destructive-action")
        self.set_default_response(Gtk.ResponseType.OK)

        box = self.get_content_area()
        box.set_spacing(10)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(14)
        box.set_margin_end(14)

        header = Gtk.Label()
        header.set_xalign(0)
        header.set_markup("<b>Select Applications/Packages to Purge</b>")
        box.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.master_check = Gtk.CheckButton(label="Select All")
        self.master_check.connect("toggled", self.on_master_toggled)
        toolbar.pack_start(self.master_check, False, False, 0)

        self.count_label = Gtk.Label(label=f"0 of {len(pkgs)} selected")
        toolbar.pack_end(self.count_label, False, False, 0)
        box.pack_start(toolbar, False, False, 0)

        self.store = Gtk.ListStore(bool, str)
        for p in pkgs:
            self.store.append([False, p])

        tree = Gtk.TreeView(model=self.store)
        tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        toggle = Gtk.CellRendererToggle()
        toggle.set_property("xpad", 8)
        toggle.connect("toggled", self.on_row_toggled)
        col_check = Gtk.TreeViewColumn("Purge", toggle, active=0)
        col_check.set_fixed_width(64)
        col_check.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        tree.append_column(col_check)

        pkg_r = Gtk.CellRendererText()
        pkg_r.set_property("xpad", 10)
        pkg_r.set_property("ypad", 6)
        pkg_r.set_property("weight", Pango.Weight.BOLD)
        col_pkg = Gtk.TreeViewColumn("Package Name", pkg_r, text=1)
        col_pkg.set_expand(True)
        tree.append_column(col_pkg)

        tree.connect("row-activated", self.on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_shadow_type(Gtk.ShadowType.IN)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)

        extra_lbl = Gtk.Label(label="Additional packages to purge (space-separated, optional):")
        extra_lbl.set_xalign(0)
        box.pack_start(extra_lbl, False, False, 0)

        self.extra_entry = Gtk.Entry()
        self.extra_entry.set_placeholder_text("e.g. hexchat hypnotix rhythmbox")
        self.extra_entry.set_activates_default(True)
        box.pack_start(self.extra_entry, False, False, 0)

        self.show_all()

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

dlg = UninstallSelector()
resp = dlg.run()
selected = [r[1] for r in dlg.store if r[0]] if resp == Gtk.ResponseType.OK else []
extra = dlg.extra_entry.get_text().strip().split() if resp == Gtk.ResponseType.OK else []
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)

all_targets = []
for p in selected + extra:
    if p and p not in all_targets:
        all_targets.append(p)

if not all_targets:
    sys.exit(99)

print(" ".join(all_targets))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped package removal."
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "❌ Uninstall selector dialog error (code $rc)."
    exit $rc
fi

failed_count=0
removed_any=0

for pkg in $GUI_OUT; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "Purging package: $pkg..." | tee -a "$LOGFILE"
        if sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" 2>&1 | tee -a "$LOGFILE"; then
            echo "✅ Removed $pkg." | tee -a "$LOGFILE"
            record_status "PASS" "APT Purge" "$pkg"
            removed_any=1
        else
            echo "❌ Failed to purge $pkg." | tee -a "$LOGFILE"
            record_status "FAIL" "APT Purge" "$pkg"
            ((failed_count++))
        fi
    else
        echo "⏭️ Package $pkg is not installed. Skipping." | tee -a "$LOGFILE"
        record_status "SKIPPED" "APT Purge" "$pkg (not installed)"
    fi
done

if (( removed_any == 1 )); then
    echo "Running autoremove..." | tee -a "$LOGFILE"
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>&1 | tee -a "$LOGFILE"; then
        echo "❌ apt-get autoremove failed." | tee -a "$LOGFILE"
        ((failed_count++))
    fi
fi

if (( failed_count > 0 )); then
    echo "❌ Package removal finished with $failed_count error(s)." | tee -a "$LOGFILE"
    exit 1
fi

echo "✅ Package removal completed successfully." | tee -a "$LOGFILE"
