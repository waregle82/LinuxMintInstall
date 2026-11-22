#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$HOME/install_packages.log"
RETRIES=3

# =============================================================================
# PACKAGE LIST (Alphabetized)
# =============================================================================
PACKAGE_MANIFEST=(
    "7zip"
    "alsa-scarlett-gui"
    "blender"
    "calibre"
    "claude-desktop"
    "conky-all"
    "curl"
    "darktable"
    "dosbox"
    "fastfetch"
    "gimp"
    "git"
    "gparted"
    "grsync"
    "handbrake"
    "htop"
    "iperf3"
    "jq"
    "lm-sensors"
    "lsb-release"
    "ncdu"
    "nemo-image-converter"
    "netbird"
    "netbird-ui"
    "network-manager-openconnect-gnome"
    "nmap"
    "numlockx"
    "obs-studio"
    "openarena"
    "openconnect"
    "openlp"
    "plank"
    "playerctl"
    "preload"
    "qemu-system-x86"
    "remmina"
    "remmina-plugin-rdp"
    "samba"
    "scribus"
    "simplescreenrecorder"
    "solaar"
    "ssh"
    "steam-devices"
    "steam-installer"
    "sublime-merge"
    "sublime-text"
    "tlp"
    "tlp-rdw"
    "traceroute"
    "ttf-mscorefonts-installer"
    "ubuntu-restricted-extras"
    "ulauncher"
    "variety"
    "virt-manager"
    "vlc"
    "wget"
    "wgtunnel"
    "wine"
    "wireguard"
    "wireguard-tools"
    "x11-utils"
    "xrdp"
)

echo "Starting package installation..." | tee -a "$LOGFILE"
echo "Updating package lists..." | tee -a "$LOGFILE"
if ! sudo DEBIAN_FRONTEND=noninteractive apt-get update -y 2>&1 | tee -a "$LOGFILE"; then
  echo "[ERROR] apt-get update failed. Aborting package installation." | tee -a "$LOGFILE"
  exit 1
fi

packages=()
for entry in "${PACKAGE_MANIFEST[@]}"; do
  [[ -z "$entry" || "$entry" =~ ^[[:space:]]*# ]] && continue
  pkg="${entry%%|*}"
  pkg="${pkg#"${pkg%%[![:space:]]*}"}"
  pkg="${pkg%"${pkg##*[![:space:]]}"}"
  packages+=("$pkg")
done

select_packages_gui() {
  python3 - "${packages[@]}" <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

items = sys.argv[1:]
if not items:
    sys.exit(99)

class PackageSelector(Gtk.Dialog):
    def __init__(self):
        super().__init__(title="Select .deb Packages to Install", flags=Gtk.DialogFlags.MODAL)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(12)

        row_h = 34
        chrome_h = 175
        desired_h = chrome_h + len(items) * row_h
        desired_w = 540

        max_h = 850
        display = Gdk.Display.get_default()
        if display:
            mon = display.get_primary_monitor() or display.get_monitor(0)
            if mon:
                wa = mon.get_workarea()
                max_h = int(wa.height * 0.85)
                desired_w = min(desired_w, int(wa.width * 0.85))
        self.set_default_size(desired_w, max(420, min(desired_h, max_h)))

        self.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
        ok_btn = self.add_button("Install Selected", Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)
        self.ok_btn = ok_btn
        self.ok_btn.set_sensitive(False)

        area = self.get_content_area()
        area.set_spacing(10)

        header = Gtk.Label()
        header.set_xalign(0)
        header.set_markup("<b>Select .deb Packages to Install</b>\n<span size='small'>Choose the packages you want APT to install.</span>")
        area.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.master = Gtk.CheckButton(label="Select All")
        self.master.connect("toggled", self._on_master)
        toolbar.pack_start(self.master, False, False, 0)

        self.count_lbl = Gtk.Label(label=f"0 of {len(items)} selected")
        self.count_lbl.set_xalign(1)
        toolbar.pack_end(self.count_lbl, False, False, 0)
        area.pack_start(toolbar, False, False, 0)

        self.store = Gtk.ListStore(bool, str)
        for p in items:
            self.store.append([False, p])

        tree = Gtk.TreeView(model=self.store)
        tree.set_headers_visible(True)
        tree.set_enable_search(True)
        tree.set_search_column(1)
        tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        r_tog = Gtk.CellRendererToggle()
        r_tog.set_property("xpad", 8)
        r_tog.connect("toggled", self._on_toggle)
        c_run = Gtk.TreeViewColumn("Install", r_tog, active=0)
        c_run.set_fixed_width(64)
        c_run.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
        tree.append_column(c_run)

        r_pkg = Gtk.CellRendererText()
        r_pkg.set_property("xpad", 10)
        r_pkg.set_property("ypad", 5)
        r_pkg.set_property("weight", Pango.Weight.BOLD)
        c_pkg = Gtk.TreeViewColumn("Package", r_pkg, text=1)
        c_pkg.set_expand(True)
        tree.append_column(c_pkg)

        tree.connect("row-activated", self._on_activate)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.set_shadow_type(Gtk.ShadowType.IN)
        scroll.add(tree)
        area.pack_start(scroll, True, True, 0)

    def _sync(self):
        total = len(self.store)
        checked = sum(1 for r in self.store if r[0])
        self.count_lbl.set_text(f"{checked} of {total} selected")
        self.ok_btn.set_sensitive(checked > 0)
        self.master.handler_block_by_func(self._on_master)
        if checked == 0:
            self.master.set_inconsistent(False)
            self.master.set_active(False)
        elif checked == total:
            self.master.set_inconsistent(False)
            self.master.set_active(True)
        else:
            self.master.set_inconsistent(True)
        self.master.handler_unblock_by_func(self._on_master)

    def _on_master(self, btn):
        btn.set_inconsistent(False)
        st = btn.get_active()
        for r in self.store:
            r[0] = st
        self._sync()

    def _on_toggle(self, _r, path):
        self.store[path][0] = not self.store[path][0]
        self._sync()

    def _on_activate(self, _t, path, _c):
        self.store[path][0] = not self.store[path][0]
        self._sync()

dlg = PackageSelector()
dlg.show_all()
resp = dlg.run()
chosen = [r[1] for r in dlg.store if r[0]] if resp == Gtk.ResponseType.OK else None
dlg.destroy()

if chosen is None or not chosen:
    sys.exit(99)
print("\n".join(chosen))
PY
}

rc=0
SELECTED=$(select_packages_gui) || rc=$?
if [[ $rc -eq 99 ]]; then
  echo "[SKIP] User skipped .deb package selection." | tee -a "$LOGFILE"
  exit 99
elif [[ $rc -ne 0 ]]; then
  echo "[FAIL] Package selection dialog failed (code $rc)." | tee -a "$LOGFILE"
  exit "$rc"
fi

mapfile -t selected_pkgs <<< "$SELECTED"
if [[ ${#selected_pkgs[@]} -eq 0 ]]; then
  echo "[SKIP] No packages selected." | tee -a "$LOGFILE"
  exit 99
fi

check_version() {
  dpkg-query -W -f='${Version}' "$1" 2>/dev/null || echo ""
}

get_candidate_version() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}'
}

version_ge() {
  dpkg --compare-versions "$1" ge "$2"
}

FAIL_DIR=$(mktemp -d)
trap 'rm -rf "$FAIL_DIR"' EXIT

install_package() {
  local pkg="$1"
  local attempt=1

  while [[ $attempt -le $RETRIES ]]; do
    echo "Installing $pkg (Attempt $attempt/$RETRIES)..." | tee -a "$LOGFILE"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$LOGFILE" 2>&1; then
      echo "[OK] $pkg installed successfully." | tee -a "$LOGFILE"
      return 0
    fi
    echo "[WARN] Failed to install $pkg on attempt $attempt." | tee -a "$LOGFILE"
    ((attempt++))
    sleep 2
  done

  echo "[FAIL] Failed to install $pkg after $RETRIES attempts." | tee -a "$LOGFILE"
  touch "$FAIL_DIR/$pkg"
  return 1
}

to_install=()
for pkg in "${selected_pkgs[@]}"; do
  [[ -z "$pkg" ]] && continue
  installed_version=$(check_version "$pkg")
  candidate_version=$(get_candidate_version "$pkg")

  if [[ -z "$candidate_version" || "$candidate_version" == "(none)" ]]; then
    echo "[WARN] No candidate version found for $pkg; will attempt installation." | tee -a "$LOGFILE"
    to_install+=("$pkg")
    continue
  fi

  if [[ -n "$installed_version" ]] && version_ge "$installed_version" "$candidate_version"; then
    echo "[SKIP] $pkg already installed (version $installed_version >= $candidate_version)." | tee -a "$LOGFILE"
    declare -F record_op >/dev/null && record_op "SKIPPED" "APT Install" "$pkg"
    continue
  fi

  to_install+=("$pkg")
done

if [[ ${#to_install[@]} -eq 0 ]]; then
  echo "[OK] All selected packages are already up to date." | tee -a "$LOGFILE"
  exit 0
fi

echo "Attempting to install ${#to_install[@]} package(s) in one APT transaction..." | tee -a "$LOGFILE"

# A single APT transaction avoids concurrent dpkg/APT lock contention and lets APT
# resolve dependencies for the complete selection at once.
if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${to_install[@]}" >>"$LOGFILE" 2>&1; then
  for pkg in "${to_install[@]}"; do
    echo "[OK] $pkg installed or updated." | tee -a "$LOGFILE"
  done
else
  echo "[WARN] Batch installation failed. Falling back to sequential package installs to isolate failures." | tee -a "$LOGFILE"

  for pkg in "${to_install[@]}"; do
    install_package "$pkg" || true
  done

  failed_count=$(find "$FAIL_DIR" -type f | wc -l)
  if [[ "$failed_count" -gt 0 ]]; then
    echo "[ERROR] $failed_count package(s) failed after sequential retries. Failed packages:" | tee -a "$LOGFILE"
    find "$FAIL_DIR" -type f -printf '%f\\n' | tee -a "$LOGFILE"
    echo "[ERROR] See $LOGFILE for APT details." | tee -a "$LOGFILE"
    exit 1
  fi
fi

echo "[OK] Installation finished cleanly. Check $LOGFILE for details." | tee -a "$LOGFILE"
exit 0
