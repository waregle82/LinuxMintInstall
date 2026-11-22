#!/bin/bash
set -uo pipefail

MAX_RETRIES=3
RETRY_DELAY=5

for pkg in curl wget; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo "$pkg not found. Installing..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    fi
done

retry() {
    local n=1
    until [ $n -gt $MAX_RETRIES ]; do
        echo "Attempt $n/$MAX_RETRIES: $*"
        if "$@"; then
            return 0
        fi
        echo "Attempt $n failed. Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        ((n++))
    done
    echo "Command failed after $MAX_RETRIES attempts."
    return 1
}

install_brave() {
    echo "Installing Brave Browser..."
    retry bash -c "curl -fsS https://dl.brave.com/install.sh | sh"
}

install_debget() {
    echo "Installing Deb-get..."
    retry bash -c "curl -fsSL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get"
}

install_input_remapper() {
    echo "Installing Input Remapper (latest GitHub .deb release)..."
    local latest_tag deb_url tmp_deb
    latest_tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/sezanzeb/input-remapper/releases/latest" | awk -F'/tag/' '{print $2}' | tr -d '\r')
    if [[ -z "$latest_tag" ]]; then
        echo "Failed to resolve latest Input Remapper release tag."
        return 1
    fi

    deb_url="https://github.com/sezanzeb/input-remapper/releases/download/${latest_tag}/input-remapper-${latest_tag}.deb"
    tmp_deb=$(mktemp --suffix=.deb)
    if retry wget -q "$deb_url" -O "$tmp_deb"; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
        if retry sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb"; then
            rm -f "$tmp_deb"
            return 0
        fi
    fi
    rm -f "$tmp_deb"
    return 1
}

install_joplin() {
    echo "Installing Joplin..."
    retry bash -c "wget -qO - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash"
}

install_openaudible() {
    echo "Installing OpenAudible..."
    local tmp_deb
    tmp_deb=$(mktemp --suffix=.deb)
    if retry wget -q "https://openaudible.org/latest/OpenAudible_x86_64.deb" -O "$tmp_deb" &&
       retry sudo dpkg -i "$tmp_deb"; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y
        rm -f "$tmp_deb"
        return 0
    fi
    rm -f "$tmp_deb"
    return 1
}

install_oudedetai() {
    echo "Installing OuDedetai to $HOME/Apps..."
    local install_dir="$HOME/Apps"
    local bin_path="$install_dir/oudedetai"
    local desktop_dir="$HOME/.local/share/applications"
    local desktop_file="$desktop_dir/oudedetai.desktop"

    mkdir -p "$install_dir" "$desktop_dir"
    if retry wget -q "https://github.com/FaithLife-Community/OuDedetai/releases/latest/download/oudedetai" -O "$bin_path"; then
        chmod +x "$bin_path"
        cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Name=OuDedetai
Comment=Install and maintain FaithLife Logos Bible Software via Wine
Exec="$bin_path"
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Education;Utility;
StartupNotify=true
DESKTOP
        chmod +x "$desktop_file"
        update-desktop-database "$desktop_dir" 2>/dev/null || true
        return 0
    fi
    rm -f "$bin_path"
    return 1
}

# Format: "Display Name | function_name | Description" (Alphabetized)
DIRECT_MANIFEST=(
    "Brave Browser | install_brave | Privacy-focused web browser"
    "Deb-get | install_debget | apt-get style installer for 3rd-party .deb packages"
    "Input Remapper | install_input_remapper | Input device button and key remapping tool (latest GitHub .deb)"
    "Joplin | install_joplin | Open-source note-taking and to-do application"
    "OpenAudible | install_openaudible | Cross-platform Audible audiobook manager"
    "OuDedetai | install_oudedetai | FaithLife Logos Bible Software installer/manager (~/Apps)"
)

manifest_payload=""
for entry in "${DIRECT_MANIFEST[@]}"; do
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

win = Gtk.Dialog(title="Select Direct-Install Applications", flags=Gtk.DialogFlags.MODAL)
win.set_position(Gtk.WindowPosition.CENTER)

height = min(max(260 + len(items) * 38, 360), 720)
display = Gdk.Display.get_default()
if display and display.get_primary_monitor():
    wa = display.get_primary_monitor().get_workarea()
    height = min(height, int(wa.height * 0.85))
win.set_default_size(680, height)

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
header.set_markup("<b>Choose direct-install applications to install:</b>")
box.pack_start(header, False, False, 0)

toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
master = Gtk.CheckButton(label="Select All")
count_lbl = Gtk.Label(label=f"0 of {len(items)} selected")
toolbar.pack_start(master, False, False, 0)
toolbar.pack_end(count_lbl, False, False, 0)
box.pack_start(toolbar, False, False, 0)

store = Gtk.ListStore(bool, str, str, str)
for name, fn, desc in items:
    store.append([False, name, fn, desc])

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
c_name.set_min_width(180)
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
chosen = [f"{r[1]}|{r[2]}" for r in store if r[0]] if resp == Gtk.ResponseType.OK else []
win.destroy()

if resp != Gtk.ResponseType.OK or not chosen:
    sys.exit(99)

print("\n".join(chosen))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped direct-install applications."
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "Dialog error (code $rc)."
    exit $rc
fi

failed_count=0
while IFS='|' read -r app_name fn_name; do
    [[ -z "$fn_name" ]] && continue
    if "$fn_name"; then
        echo "[✓] $app_name installed successfully."
        declare -F record_op >/dev/null && record_op "PASS" "Direct Install" "$app_name"
    else
        echo "[✘] $app_name failed to install."
        declare -F record_op >/dev/null && record_op "FAIL" "Direct Install" "$app_name"
        ((failed_count++))
    fi
done <<< "$SELECTED"

if (( failed_count > 0 )); then
    echo "[✘] $failed_count direct-install application(s) failed."
    exit 1
fi

echo "[✓] All selected direct-install applications completed."
exit 0
