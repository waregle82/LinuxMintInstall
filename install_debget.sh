#!/bin/bash
set -uo pipefail

# =============================================================================
# DEB-GET PACKAGES (Alphabetized)
# Format: "Display Name | package_name | Short description"
# =============================================================================
DEBGET_MANIFEST=(
    "FreeShow | freeshow | Church presentation software"
    "Insync | insync | Cloud storage sync tool"
    "Raspberry Pi Imager | rpi-imager | Raspberry Pi SD creation tool"
)

if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl
fi

# Ensure deb-get is installed
if ! command -v deb-get >/dev/null 2>&1; then
    echo "[!] Installing deb-get..."
    curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get
    if ! command -v deb-get >/dev/null 2>&1; then
        echo "[✘] Failed to install deb-get. Exiting."
        exit 1
    fi
fi

# Build manifest payload for GTK3 selector
manifest_payload=""
for entry in "${DEBGET_MANIFEST[@]}"; do
    [[ -z "$entry" || "$entry" =~ ^[[:space:]]*# ]] && continue
    manifest_payload+="$entry"$'\n'
done

rc=0
SELECTED=$(MANIFEST_DATA="$manifest_payload" python3 - <<'PY'
import os
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

items = []
for line in os.environ.get("MANIFEST_DATA", "").splitlines():
    parts = [p.strip() for p in line.split("|")]
    if len(parts) >= 3 and parts[1]:
        items.append((parts[0], parts[1], parts[2]))

if not items:
    sys.exit(99)

win = Gtk.Dialog(title="Select deb-get Applications", flags=Gtk.DialogFlags.MODAL)
win.set_position(Gtk.WindowPosition.CENTER)

height = min(max(240 + len(items) * 38, 340), 720)
display = Gdk.Display.get_default()
if display and display.get_primary_monitor():
    wa = display.get_primary_monitor().get_workarea()
    height = min(height, int(wa.height * 0.85))
win.set_default_size(640, height)

win.add_button("Skip / Cancel", 99)
ok_btn = win.add_button("Install Selected", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
ok_btn.set_sensitive(False)

box = win.get_content_area()
box.set_spacing(10)
box.set_margin_top(14)
box.set_margin_bottom(14)
box.set_margin_start(16)
box.set_margin_end(16)

header = Gtk.Label()
header.set_xalign(0)
header.set_markup("<b>Choose applications to install via deb-get:</b>")
box.pack_start(header, False, False, 0)

toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
master = Gtk.CheckButton(label="Select All")
count_lbl = Gtk.Label(label=f"0 of {len(items)} selected")
toolbar.pack_start(master, False, False, 0)
toolbar.pack_end(count_lbl, False, False, 0)
box.pack_start(toolbar, False, False, 0)

store = Gtk.ListStore(bool, str, str, str)
for name, pkg, desc in items:
    store.append([False, name, pkg, desc])

tree = Gtk.TreeView(model=store)
tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

def sync_state():
    checked = sum(1 for r in store if r[0])
    total = len(store)
    count_lbl.set_text(f"{checked} of {total} selected")
    ok_btn.set_sensitive(checked > 0)
    master.handler_block_by_func(on_master)
    if checked == 0:
        master.set_inconsistent(False)
        master.set_active(False)
    elif checked == total:
        master.set_inconsistent(False)
        master.set_active(True)
    else:
        master.set_inconsistent(True)
    master.handler_unblock_by_func(on_master)

def on_master(btn):
    btn.set_inconsistent(False)
    state = btn.get_active()
    for r in store:
        r[0] = state
    sync_state()

def on_toggle(_r, path):
    store[path][0] = not store[path][0]
    sync_state()

def on_activate(_t, path, _c):
    store[path][0] = not store[path][0]
    sync_state()

master.connect("toggled", on_master)
tree.connect("row-activated", on_activate)

r_chk = Gtk.CellRendererToggle()
r_chk.set_property("xpad", 8)
r_chk.connect("toggled", on_toggle)
c_chk = Gtk.TreeViewColumn("Run", r_chk, active=0)
c_chk.set_fixed_width(55)
c_chk.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
tree.append_column(c_chk)

r_name = Gtk.CellRendererText()
r_name.set_property("xpad", 10)
r_name.set_property("ypad", 6)
r_name.set_property("weight", Pango.Weight.BOLD)
c_name = Gtk.TreeViewColumn("Application", r_name, text=1)
c_name.set_min_width(190)
tree.append_column(c_name)

r_desc = Gtk.CellRendererText()
r_desc.set_property("xpad", 10)
r_desc.set_property("ypad", 6)
c_desc = Gtk.TreeViewColumn("Description", r_desc, text=3)
c_desc.set_expand(True)
tree.append_column(c_desc)

scroll = Gtk.ScrolledWindow()
scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
scroll.set_shadow_type(Gtk.ShadowType.IN)
scroll.add(tree)
box.pack_start(scroll, True, True, 0)

win.show_all()
resp = win.run()
chosen = [r[2] for r in store if r[0]] if resp == Gtk.ResponseType.OK else []
win.destroy()

if resp != Gtk.ResponseType.OK or not chosen:
    sys.exit(99)

print(" ".join(chosen))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped deb-get installation."
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "Dialog error (code $rc)."
    exit $rc
fi

install_package() {
    local pkg="$1"
    echo "Installing ${pkg}..."

    for attempt in 1 2 3; do
        if sudo env -u DISPLAY DEBIAN_FRONTEND=noninteractive deb-get install "$pkg"; then
            if [[ "$pkg" == "insync" ]]; then
                pkill -f "insync" 2>/dev/null || true
            fi
            echo "[✓] $pkg installed successfully."
            return 0
        else
            echo "[✘] Attempt $attempt failed for $pkg. Retrying..."
            sleep 2
        fi
    done

    echo "[✘] $pkg failed after 3 attempts."
    return 1
}

failed_count=0
for pkg in $SELECTED; do
    if ! install_package "$pkg"; then
        ((failed_count++))
    fi
done

if (( failed_count > 0 )); then
    echo "[✘] $failed_count deb-get package(s) failed to install."
    exit 1
fi

echo "[✓] All selected deb-get packages installed successfully."
exit 0
