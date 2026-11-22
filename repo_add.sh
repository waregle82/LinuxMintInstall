#!/bin/bash
set -uo pipefail

LOGFILE="$HOME/repo_add_log.txt"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"
}

select_repos_gui() {
  python3 - <<'PY'
import sys
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, Pango

REPOS = [
    ("claude-desktop", "Claude Desktop", "https://downloads.claude.ai/claude-desktop/apt/stable"),
    ("fastfetch", "Fastfetch", "ppa:zhangsongcui3371/fastfetch"),
    ("netbird", "NetBird", "https://pkgs.netbird.io/debian"),
    ("obs-studio", "OBS Studio", "ppa:obsproject/obs-studio"),
    ("sublime-text", "Sublime Text & Merge", "https://download.sublimetext.com/ apt/stable/"),
    ("ulauncher", "ULauncher", "ppa:agornostal/ulauncher"),
    ("variety", "Variety", "ppa:variety/stable"),
    ("wgtunnel", "WG Tunnel", "https://apt.wgtunnel.com"),
]

Gtk.init([])
win = Gtk.Dialog(title="Select 3rd-Party Repositories to Add", flags=Gtk.DialogFlags.MODAL)
win.set_position(Gtk.WindowPosition.CENTER)
win.set_border_width(12)

row_h = 34
chrome_h = 165
desired_h = chrome_h + len(REPOS) * row_h
desired_w = 640
display = Gdk.Display.get_default()
if display:
    mon = display.get_primary_monitor() or display.get_monitor(0)
    if mon:
        wa = mon.get_workarea()
        desired_h = min(desired_h, int(wa.height * 0.80))
        desired_w = min(desired_w, int(wa.width * 0.85))
win.set_default_size(desired_w, max(320, desired_h))

win.add_button("Skip / Cancel", Gtk.ResponseType.CANCEL)
ok_btn = win.add_button("Add Selected", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
win.set_default_response(Gtk.ResponseType.OK)

area = win.get_content_area()
area.set_spacing(10)

header = Gtk.Label()
header.set_xalign(0)
header.set_markup("<b>Choose third-party repositories to configure:</b>")
area.pack_start(header, False, False, 0)

toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
master = Gtk.CheckButton(label="Select All")
count_lbl = Gtk.Label(label=f"0 of {len(REPOS)} selected")
toolbar.pack_start(master, False, False, 0)
toolbar.pack_end(count_lbl, False, False, 0)
area.pack_start(toolbar, False, False, 0)

store = Gtk.ListStore(bool, str, str, str)
for key, name, url in REPOS:
    store.append([False, name, url, key])

def sync():
    total = len(store)
    checked = sum(1 for r in store if r[0])
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
    sync()

master.connect("toggled", on_master)

tree = Gtk.TreeView(model=store)
tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

r_tog = Gtk.CellRendererToggle()
r_tog.set_property("xpad", 8)
r_tog.connect("toggled", lambda _r, p: (store[p].__setitem__(0, not store[p][0]), sync()))
c_tog = Gtk.TreeViewColumn("Add", r_tog, active=0)
c_tog.set_fixed_width(54)
c_tog.set_sizing(Gtk.TreeViewColumnSizing.FIXED)
tree.append_column(c_tog)

r_name = Gtk.CellRendererText()
r_name.set_property("xpad", 10)
r_name.set_property("ypad", 5)
r_name.set_property("weight", Pango.Weight.BOLD)
c_name = Gtk.TreeViewColumn("Repository", r_name, text=1)
c_name.set_min_width(160)
tree.append_column(c_name)

r_url = Gtk.CellRendererText()
r_url.set_property("xpad", 10)
r_url.set_property("ypad", 5)
c_url = Gtk.TreeViewColumn("Source / PPA", r_url, text=2)
c_url.set_expand(True)
tree.append_column(c_url)

tree.connect("row-activated", lambda _t, p, _c: (store[p].__setitem__(0, not store[p][0]), sync()))

scroll = Gtk.ScrolledWindow()
scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
scroll.set_shadow_type(Gtk.ShadowType.IN)
scroll.add(tree)
area.pack_start(scroll, True, True, 0)

sync()
win.show_all()
resp = win.run()
selected = [r[3] for r in store if r[0]]
win.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)
if not selected:
    sys.exit(99)
print(" ".join(selected))
PY
}

rc=0
SELECTED=$(select_repos_gui) || rc=$?

if [[ $rc -eq 99 ]]; then
  log "User skipped repository selection."
  exit 99
elif [[ $rc -ne 0 ]]; then
  log "[ERROR] Repository selection dialog failed (code $rc)."
  exit "$rc"
fi

if [[ -z "$SELECTED" ]]; then
  log "No repositories selected. Skipping."
  exit 99
fi

failed_count=0

ensure_apt_prereqs() {
  for pkg in ca-certificates curl gnupg wget; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq >>"$LOGFILE" 2>&1
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >>"$LOGFILE" 2>&1 || true
    fi
  done
}

add_ppa_repo() {
  local repo="$1"
  local name="$2"
  local tries=3
  local count=0

  log "Adding $name repository: $repo"

  while (( count < tries )); do
    if sudo add-apt-repository -y "$repo" >>"$LOGFILE" 2>&1; then
      log "[OK] Successfully added $name repository."
      return 0
    else
      ((count++))
      log "[WARN] Failed to add $name repository. Retrying ($count/$tries)..."
      sleep $((count * 5))
    fi
  done

  log "[FAIL] Failed to add $name repository after $tries attempts."
  ((failed_count++))
  return 1
}

add_signed_apt_repo() {
  local name="$1"
  local key_url="$2"
  local keyring="$3"
  local repo_line="$4"
  local list_file="$5"
  local source_label="$6"
  local tries=3
  local count=0

  log "Adding $name repository: $source_label"
  ensure_apt_prereqs

  while (( count < tries )); do
    if curl -fsSL "$key_url" | sudo gpg --dearmor --yes -o "$keyring" >>"$LOGFILE" 2>&1 \
      && echo "$repo_line" | sudo tee "$list_file" >/dev/null; then
      sudo chmod 644 "$keyring" "$list_file"
      log "[OK] Successfully added $name repository."
      declare -F record_op >/dev/null && record_op "PASS" "APT Repo" "$source_label"
      return 0
    else
      ((count++))
      log "[WARN] Failed to add $name repository. Retrying ($count/$tries)..."
      sleep $((count * 5))
    fi
  done

  log "[FAIL] Failed to add $name repository after $tries attempts."
  declare -F record_op >/dev/null && record_op "FAIL (code 1)" "APT Repo" "$source_label"
  ((failed_count++))
  return 1
}

log "Starting to add selected 3rd-party repositories..."

for item in $SELECTED; do
  case "$item" in
    claude-desktop)
      add_signed_apt_repo \
        "Claude Desktop" \
        "https://downloads.claude.ai/claude-desktop/key.asc" \
        "/usr/share/keyrings/claude-desktop-archive-keyring.gpg" \
        "deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.gpg] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        "/etc/apt/sources.list.d/claude-desktop.list" \
        "https://downloads.claude.ai/claude-desktop/apt/stable" || true
      ;;
    fastfetch)
      add_ppa_repo "ppa:zhangsongcui3371/fastfetch" "Fastfetch" || true
      ;;
    netbird)
      add_signed_apt_repo \
        "NetBird" \
        "https://pkgs.netbird.io/debian/public.key" \
        "/usr/share/keyrings/netbird-archive-keyring.gpg" \
        "deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main" \
        "/etc/apt/sources.list.d/netbird.list" \
        "https://pkgs.netbird.io/debian" || true
      ;;
    obs-studio)
      add_ppa_repo "ppa:obsproject/obs-studio" "OBS Studio" || true
      ;;
    sublime-text)
      add_signed_apt_repo \
        "Sublime Text & Merge" \
        "https://download.sublimetext.com/sublimehq-pub.gpg" \
        "/usr/share/keyrings/sublimehq-pub.gpg" \
        "deb [signed-by=/usr/share/keyrings/sublimehq-pub.gpg] https://download.sublimetext.com/ apt/stable/" \
        "/etc/apt/sources.list.d/sublime-text.list" \
        "https://download.sublimetext.com/ apt/stable/" || true
      ;;
    ulauncher)
      add_ppa_repo "ppa:agornostal/ulauncher" "ULauncher" || true
      ;;
    variety)
      add_ppa_repo "ppa:variety/stable" "Variety" || true
      ;;
    wgtunnel)
      add_signed_apt_repo \
        "WG Tunnel" \
        "https://apt.wgtunnel.com/wgtunnel-archive-keyring.asc" \
        "/usr/share/keyrings/wgtunnel-archive-keyring.gpg" \
        "deb [signed-by=/usr/share/keyrings/wgtunnel-archive-keyring.gpg] https://apt.wgtunnel.com stable main" \
        "/etc/apt/sources.list.d/wgtunnel.list" \
        "https://apt.wgtunnel.com" || true
      ;;
  esac
done

if (( failed_count > 0 )); then
  log "[ERROR] $failed_count repository addition(s) failed."
  exit 1
fi

log "[OK] All selected repository additions complete."
exit 0
