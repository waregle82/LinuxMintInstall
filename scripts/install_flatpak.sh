#!/bin/bash

LOGFILE="$HOME/flatpak_install_$(date +%Y%m%d_%H%M%S).log"
MAX_CONCURRENT=3
MAX_RETRIES=2

# =============================================================================
# FLATPAK MANIFEST (Alphabetized by Display Name)
# Format: "Display Name | flathub.app.id"
# =============================================================================
FLATPAK_MANIFEST=(
    "Angry IP Scanner | org.angryip.ipscan"
    "Bitwarden | com.bitwarden.desktop"
    "Bottles | com.usebottles.bottles"
    "CPU-X | io.github.thetumultuousunicornofdarkness.cpu-x"
    "Cryptomator | org.cryptomator.Cryptomator"
    "Dropbox | com.dropbox.Client"
    "Emoji Mart | io.github.vemonet.EmojiMart"
    "Flameshot | org.flameshot.Flameshot"
    "Gimp | org.gimp.GIMP"
    "Gear Lever | it.mijorus.gearlever"
    "Google Earth Pro | com.google.EarthPro"
    "Heroic Games Launcher | com.heroicgameslauncher.hgl"
    "Input Leap | io.github.input_leap.input-leap"
    "Jellyfin Desktop | org.jellyfin.JellyfinDesktop"
    "Kdenlive | org.kde.kdenlive"
    "LocalSend | org.localsend.localsend_app"
    "Minecraft | com.mojang.Minecraft"
    "OTPClient | com.github.paolostivanin.OTPClient"
    "Pika Backup | org.gnome.World.PikaBackup"
    "PrusaSlicer | com.prusa3d.PrusaSlicer"
    "Resources | net.nokyan.Resources"
    "Signal | org.signal.Signal"
    "Warehouse | io.github.flattool.Warehouse"
    "Wireshark | org.wireshark.Wireshark"
)

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $1" | tee -a "$LOGFILE"
}

# Launch native GTK3 checklist displaying human-readable application names
rc=0
SELECTED=$(python3 - "${FLATPAK_MANIFEST[@]}" <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

items = []
for entry in sys.argv[1:]:
    entry = entry.strip()
    if not entry or entry.startswith("#"):
        continue
    if "|" in entry:
        name, app_id = [x.strip() for x in entry.split("|", 1)]
    else:
        name, app_id = entry, entry
    items.append((name, app_id))

class FlatpakSelectorDialog(Gtk.Dialog):
    def __init__(self, rows):
        super().__init__(title="Select Flatpak Applications to Install", flags=Gtk.DialogFlags.MODAL)
        self.set_position(Gtk.WindowPosition.CENTER)

        width = 720
        height = min(740, max(440, 190 + min(len(rows), 14) * 34))
        display = Gdk.Display.get_default()
        if display:
            mon = display.get_primary_monitor() or display.get_monitor(0)
            if mon:
                wa = mon.get_workarea()
                height = min(height, int(wa.height * 0.85))
        self.set_default_size(width, height)

        self.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
        self.ok_btn = self.add_button("Install Selected", Gtk.ResponseType.OK)
        self.ok_btn.get_style_context().add_class("suggested-action")
        self.ok_btn.set_sensitive(False)

        box = self.get_content_area()
        box.set_spacing(10)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(14)
        box.set_margin_end(14)

        header = Gtk.Label()
        header.set_xalign(0)
        header.set_markup("<b>Choose Flatpak applications to install from Flathub</b>\n<span size='small'>Already installed Flatpaks will be skipped automatically.</span>")
        box.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.master_check = Gtk.CheckButton(label="Select All")
        self.master_check.connect("toggled", self._on_master_toggled)
        toolbar.pack_start(self.master_check, False, False, 0)

        self.count_label = Gtk.Label(label=f"0 of {len(rows)} selected")
        toolbar.pack_end(self.count_label, False, False, 0)
        box.pack_start(toolbar, False, False, 0)

        self.store = Gtk.ListStore(bool, str, str)
        for name, app_id in rows:
            self.store.append([False, name, app_id])

        tree = Gtk.TreeView(model=self.store)
        tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)
        tree.set_enable_search(True)
        tree.set_search_column(1)

        r_tog = Gtk.CellRendererToggle()
        r_tog.set_property("xpad", 8)
        r_tog.connect("toggled", self._on_row_toggled)
        col_run = Gtk.TreeViewColumn("Install", r_tog, active=0)
        col_run.set_fixed_width(64)
        col_run.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        tree.append_column(col_run)

        r_name = Gtk.CellRendererText()
        r_name.set_property("xpad", 10)
        r_name.set_property("ypad", 5)
        r_name.set_property("weight", Pango.Weight.BOLD)
        col_name = Gtk.TreeViewColumn("Application", r_name, text=1)
        col_name.set_min_width(240)
        tree.append_column(col_name)

        r_id = Gtk.CellRendererText()
        r_id.set_property("xpad", 10)
        r_id.set_property("ypad", 5)
        r_id.set_property("foreground", "#666666")
        col_id = Gtk.TreeViewColumn("Flathub Reference", r_id, text=2)
        col_id.set_expand(True)
        tree.append_column(col_id)

        tree.connect("row-activated", lambda _t, p, _c: self._toggle_path(p))

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_shadow_type(Gtk.ShadowType.IN)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)
        self.show_all()

    def _toggle_path(self, path):
        self.store[path][0] = not self.store[path][0]
        self._sync()

    def _on_row_toggled(self, _r, path):
        self._toggle_path(path)

    def _on_master_toggled(self, widget):
        widget.set_inconsistent(False)
        state = widget.get_active()
        for row in self.store:
            row[0] = state
        self._sync()

    def _sync(self):
        total = len(self.store)
        checked = sum(1 for r in self.store if r[0])
        self.count_label.set_text(f"{checked} of {total} selected")
        self.ok_btn.set_sensitive(checked > 0)
        self.master_check.handler_block_by_func(self._on_master_toggled)
        if checked == 0:
            self.master_check.set_inconsistent(False)
            self.master_check.set_active(False)
        elif checked == total:
            self.master_check.set_inconsistent(False)
            self.master_check.set_active(True)
        else:
            self.master_check.set_inconsistent(True)
        self.master_check.handler_unblock_by_func(self._on_master_toggled)

dlg = FlatpakSelectorDialog(items)
resp = dlg.run()
selected = [f"{r[1]}|{r[2]}" for r in dlg.store if r[0]] if resp == Gtk.ResponseType.OK else None
dlg.destroy()

if selected is None or not selected:
    sys.exit(99)
print("\n".join(selected))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    log "User skipped Flatpak installation."
    exit 99
elif [[ $rc -ne 0 ]]; then
    log "Error displaying Flatpak selector (code $rc)."
    exit $rc
fi

if [[ -z "$SELECTED" ]]; then
    log "No Flatpak applications selected. Skipping."
    exit 99
fi

# Ensure flatpak and Flathub remote exist
if ! command -v flatpak &>/dev/null; then
    log "flatpak not found. Installing flatpak..."
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq || ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y flatpak; then
        log "[FAIL] Failed to install flatpak package."
        exit 1
    fi
fi

if ! flatpak remotes --columns=name 2>/dev/null | grep -qx "flathub"; then
    log "Adding Flathub remote..."
    if ! sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
        log "[FAIL] Failed to add Flathub remote."
        exit 1
    fi
fi

FAIL_FLAG_DIR=$(mktemp -d)
trap 'rm -rf -- "$FAIL_FLAG_DIR"' EXIT

install_flatpak() {
    local app_name="$1"
    local app_id="$2"
    local retries=0

    while (( retries <= MAX_RETRIES )); do
        if flatpak list --app --columns=application 2>/dev/null | grep -qxF "$app_id"; then
            log "[SKIP] $app_name ($app_id) is already installed."
            declare -F record_op >/dev/null 2>&1 && record_op "SKIPPED" "Flatpak Install" "$app_name ($app_id)"
            return 0
        fi

        log "Installing $app_name ($app_id) (attempt $((retries + 1))/$((MAX_RETRIES + 1)))..."
        if sudo flatpak install -y flathub "$app_id" >>"$LOGFILE" 2>&1; then
            log "[OK] $app_name installed successfully."
            return 0
        else
            log "[WARN] Failed to install $app_name ($app_id)."
            ((retries++))
            if (( retries > MAX_RETRIES )); then
                log "[FAIL] Giving up on $app_name ($app_id) after $MAX_RETRIES retries."
                touch "$FAIL_FLAG_DIR/$app_id"
                return 1
            else
                log "Retrying $app_name in 2s..."
                sleep 2
            fi
        fi
    done
}

pids=()
while IFS='|' read -r app_name app_id; do
    [[ -z "$app_id" ]] && continue
    while (( ${#pids[@]} >= MAX_CONCURRENT )); do
        for i in "${!pids[@]}"; do
            if ! kill -0 "${pids[i]}" 2>/dev/null; then
                wait "${pids[i]}" 2>/dev/null || true
                unset 'pids[i]'
            fi
        done
        pids=("${pids[@]}")
        sleep 0.2
    done

    install_flatpak "$app_name" "$app_id" &
    pids+=($!)
done <<< "$SELECTED"

for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done

failed_count=$(find "$FAIL_FLAG_DIR" -maxdepth 1 -type f | wc -l)
if [ "$failed_count" -gt 0 ]; then
    log "[FAIL] $failed_count Flatpak application(s) failed to install. Check $LOGFILE for details."
    exit 1
fi

log "All selected Flatpak installations completed successfully."
exit 0
