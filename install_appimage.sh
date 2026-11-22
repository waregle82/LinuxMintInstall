#!/bin/bash
set -uo pipefail

record_status() {
    local status="$1" cat="$2" item="$3"
    if declare -F record_op >/dev/null 2>&1; then
        record_op "$status" "$cat" "$item"
    fi
}

# Format: "Display Name | app_slug | github_owner/project | asset_regex | Description"
APPIMAGE_MANIFEST=(
    "Scrcpy GUI | scrcpygui | pizi-0/flutter-scrcpygui | linux-ubuntu.*\.AppImage|linux.*\.AppImage | Graphical interface for scrcpy Android screen mirroring"
)

rc=0
SELECTED_INDICES=$(python3 - <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

items = [
    ("Scrcpy GUI", "Graphical interface for scrcpy Android screen mirroring"),
]

class AppImageSelector(Gtk.Dialog):
    def __init__(self):
        super().__init__(title="Select AppImages to Install", modal=True)
        self.set_position(Gtk.WindowPosition.CENTER)

        height = 195 + (len(items) * 38)
        display = Gdk.Display.get_default()
        if display and display.get_n_monitors() > 0:
            workarea = display.get_monitor(0).get_workarea()
            height = min(height, int(workarea.height * 0.85))
        self.set_default_size(680, max(320, height))

        self.add_button("Skip / Cancel", 99)
        ok_btn = self.add_button("Install Selected", Gtk.ResponseType.OK)
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
        header.set_markup("<b>Select AppImage Applications to Install</b>\n<span size='small'>Downloaded to ~/Apps and integrated into your application menu.</span>")
        box.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.master_check = Gtk.CheckButton(label="Select All")
        self.master_check.connect("toggled", self.on_master_toggled)
        toolbar.pack_start(self.master_check, False, False, 0)

        self.count_label = Gtk.Label(label=f"0 of {len(items)} selected")
        toolbar.pack_end(self.count_label, False, False, 0)
        box.pack_start(toolbar, False, False, 0)

        self.store = Gtk.ListStore(bool, str, str, int)
        for idx, (name, desc) in enumerate(items):
            self.store.append([False, name, desc, idx])

        tree = Gtk.TreeView(model=self.store)
        tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        toggle = Gtk.CellRendererToggle()
        toggle.set_property("xpad", 8)
        toggle.connect("toggled", self.on_row_toggled)
        col_check = Gtk.TreeViewColumn("Install", toggle, active=0)
        col_check.set_fixed_width(64)
        col_check.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        tree.append_column(col_check)

        name_r = Gtk.CellRendererText()
        name_r.set_property("xpad", 10)
        name_r.set_property("ypad", 6)
        name_r.set_property("weight", Pango.Weight.BOLD)
        col_name = Gtk.TreeViewColumn("Application", name_r, text=1)
        col_name.set_min_width(180)
        tree.append_column(col_name)

        desc_r = Gtk.CellRendererText()
        desc_r.set_property("xpad", 10)
        desc_r.set_property("ypad", 6)
        col_desc = Gtk.TreeViewColumn("Description", desc_r, text=2)
        col_desc.set_expand(True)
        tree.append_column(col_desc)

        tree.connect("row-activated", self.on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_shadow_type(Gtk.ShadowType.IN)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)
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

dlg = AppImageSelector()
resp = dlg.run()
selected = [str(r[3]) for r in dlg.store if r[0]] if resp == Gtk.ResponseType.OK else []
dlg.destroy()

if resp != Gtk.ResponseType.OK or not selected:
    sys.exit(99)

print(" ".join(selected))
PY
) || rc=$?

if [[ $rc -eq 99 ]]; then
    echo "User skipped AppImage installation."
    exit 99
elif [[ $rc -ne 0 ]]; then
    echo "❌ AppImage selector dialog error (code $rc)."
    exit $rc
fi

for pkg in curl wget; do
  if ! command -v "$pkg" &> /dev/null; then
    echo "$pkg not found. Installing $pkg..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  fi
done

run_gearlever() {
  if command -v flatpak &>/dev/null && flatpak info it.mijorus.gearlever &>/dev/null; then
    flatpak run it.mijorus.gearlever "$@"
    return $?
  elif command -v gearlever &>/dev/null; then
    gearlever "$@"
    return $?
  fi
  return 1
}

failed_count=0
install_dir="$HOME/Apps"
mkdir -p "$install_dir"

for idx in $SELECTED_INDICES; do
    entry="${APPIMAGE_MANIFEST[$idx]}"
    IFS='|' read -r disp_name app_slug repo regex_list comment <<< "$entry"
    disp_name="${disp_name#"${disp_name%%[![:space:]]*}"}"; disp_name="${disp_name%"${disp_name##*[![:space:]]}"}"
    app_slug="${app_slug#"${app_slug%%[![:space:]]*}"}"; app_slug="${app_slug%"${app_slug##*[![:space:]]}"}"
    repo="${repo#"${repo%%[![:space:]]*}"}"; repo="${repo%"${repo##*[![:space:]]}"}"
    regex_list="${regex_list#"${regex_list%%[![:space:]]*}"}"; regex_list="${regex_list%"${regex_list##*[![:space:]]}"}"
    comment="${comment#"${comment%%[![:space:]]*}"}"; comment="${comment%"${comment##*[![:space:]]}"}"

    BASE_URL="https://github.com/${repo}/releases"
    echo "Fetching latest release info for ${disp_name} (${repo})..."

    latest_tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${BASE_URL}/latest" | awk -F'/tag/' '{print $2}' | tr -d '
')
    if [[ -z "$latest_tag" ]]; then
        echo "❌ Could not resolve latest release tag for ${disp_name}."
        record_status "FAIL" "AppImage" "$disp_name (tag lookup failed)"
        ((failed_count++))
        continue
    fi

    assets_html=$(wget -qO- "${BASE_URL}/expanded_assets/${latest_tag}" || true)
    latest_asset_url=""
    IFS='|' read -ra patterns <<< "$regex_list"
    for pat in "${patterns[@]}"; do
        pat="${pat#"${pat%%[![:space:]]*}"}"
        pat="${pat%"${pat##*[![:space:]]}"}"
        latest_asset_url=$(printf '%s\n' "$assets_html" | grep -oE 'href="[^"]+"' | cut -d'"' -f2 | grep -E "^/${repo}/releases/download/.*${pat}$" | head -n1)
        [[ -n "$latest_asset_url" ]] && break
    done

    if [[ -z "$latest_asset_url" ]]; then
        echo "❌ Could not find a Linux AppImage asset for ${disp_name} (${latest_tag})."
        record_status "FAIL" "AppImage" "$disp_name (asset not found)"
        ((failed_count++))
        continue
    fi

    full_download_url="https://github.com${latest_asset_url}"
    appimage_path="$install_dir/$(basename "$full_download_url")"

    echo "Downloading ${disp_name} to: $appimage_path"
    if ! wget -qO "$appimage_path" "$full_download_url"; then
        echo "❌ Failed to download ${disp_name}."
        rm -f "$appimage_path"
        record_status "FAIL" "AppImage" "$disp_name (download failed)"
        ((failed_count++))
        continue
    fi

    chmod +x "$appimage_path"

    if run_gearlever --help &>/dev/null; then
        echo "Integrating ${disp_name} with Gear Lever..."
        yes | run_gearlever --integrate "$appimage_path" >/dev/null 2>&1 || true
        echo "✅ Installed and integrated ${disp_name} via Gear Lever!"
        record_status "PASS" "AppImage" "$disp_name ($latest_tag)"
    else
        fixed_path="$install_dir/${app_slug}.AppImage"
        mv -f "$appimage_path" "$fixed_path"

        icon_dir="$HOME/.local/share/icons"
        desktop_dir="$HOME/.local/share/applications"
        mkdir -p "$icon_dir" "$desktop_dir"

        icon_path="$icon_dir/${app_slug}.png"
        tmp_extract=$(mktemp -d)
        (
            cd "$tmp_extract" || exit 1
            "$fixed_path" --appimage-extract "*.png" >/dev/null 2>&1 || true
            "$fixed_path" --appimage-extract "usr/share/icons/**/*.png" >/dev/null 2>&1 || true
        )

        extracted_icon=$(find "$tmp_extract" -type f -name "*.png" -printf "%s %p
" 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)
        if [[ -n "$extracted_icon" ]]; then
            cp "$extracted_icon" "$icon_path"
        else
            icon_path="application-x-executable"
        fi
        rm -rf "$tmp_extract"

        desktop_file="$desktop_dir/${app_slug}.desktop"
        cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Name=$disp_name
Comment=$comment
Exec="$fixed_path"
Icon=$icon_path
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
DESKTOP

        chmod +x "$desktop_file"
        update-desktop-database "$desktop_dir" 2>/dev/null || true
        echo "✅ Installed ${disp_name} and added menu entry!"
        record_status "PASS" "AppImage" "$disp_name ($latest_tag)"
    fi
done

if (( failed_count > 0 )); then
    echo "❌ $failed_count AppImage installation(s) failed."
    exit 1
fi

echo "✅ All selected AppImage installations completed."
