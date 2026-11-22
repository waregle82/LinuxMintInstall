#!/bin/bash
set -u

CONKY_DIR="$HOME/.config/conky"
JF_ENV="$CONKY_DIR/jellyfin.env"
DEFAULT_JF_URL="http://172.24.34.8:8096"
failed_ops=0

record_op() {
    local status="$1"
    local name="$2"
    if [ -n "${OPERATIONS_FILE:-}" ]; then
        printf '%s|%s\n' "$status" "$name" >> "$OPERATIONS_FILE"
    fi
}

echo "=== Configuring MSI X870E Sensors & Jellyfin Environment ==="

# 1. Register MSI MAG X870E Tomahawk Super I/O sensor module (nct6683)
if echo "nct6683" | sudo tee /etc/modules-load.d/nct6683.conf >/dev/null; then
    if sudo modprobe nct6683 2>/dev/null || sudo modprobe nct6683 force=1 2>/dev/null; then
        echo "[OK] Registered and loaded nct6683 sensor module."
        record_op "PASS" "Configure nct6683 motherboard sensor module"
    else
        echo "[WARN] Registered nct6683 for boot; live modprobe requires reboot."
        record_op "PASS" "Configure nct6683 module (takes effect after reboot)"
    fi
else
    echo "[ERROR] Failed to write /etc/modules-load.d/nct6683.conf"
    record_op "FAIL" "Configure nct6683 motherboard sensor module"
    ((failed_ops++))
fi

# 2. Prompt for Jellyfin URL & API Key via native GTK3 dialog and write ~/.config/conky/jellyfin.env
mkdir -p "$CONKY_DIR"

existing_url="$DEFAULT_JF_URL"
existing_key=""
if [ -f "$JF_ENV" ]; then
    parsed_url=$(awk -F'=' '/^JELLYFIN_URL=/ {gsub(/^["'\'']|["'\'']$/, "", $2); print $2; exit}' "$JF_ENV")
    parsed_key=$(awk -F'=' '/^JELLYFIN_API_KEY=/ {gsub(/^["'\'']|["'\'']$/, "", $2); print $2; exit}' "$JF_ENV")
    [ -n "$parsed_url" ] && existing_url="$parsed_url"
    [ -n "$parsed_key" ] && existing_key="$parsed_key"
fi

rc=0
PROMPT_OUT=$(EXISTING_URL="$existing_url" EXISTING_KEY="$existing_key" python3 - <<'PY'
import os
import sys
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

class JellyfinEnvDialog(Gtk.Dialog):
    def __init__(self, default_url: str, default_key: str):
        super().__init__(title="Conky Jellyfin Configuration", flags=0)
        self.set_default_size(460, 230)
        self.set_border_width(14)
        self.set_position(Gtk.WindowPosition.CENTER)

        self.add_button("Skip", 99)
        ok_btn = self.add_button("Save Credentials", Gtk.ResponseType.OK)
        ok_btn.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)

        box = self.get_content_area()
        box.set_spacing(10)

        header = Gtk.Label()
        header.set_markup("<b>Jellyfin Now Playing Integration</b>")
        header.set_xalign(0.0)
        box.pack_start(header, False, False, 0)

        desc = Gtk.Label(
            label="Enter your Jellyfin server URL and API key (Dashboard -> API Keys).\n"
                  "Stored privately in ~/.config/conky/jellyfin.env (chmod 600)."
        )
        desc.set_xalign(0.0)
        desc.set_line_wrap(True)
        box.pack_start(desc, False, False, 0)

        grid = Gtk.Grid(column_spacing=10, row_spacing=8)
        grid.set_margin_top(4)

        lbl_url = Gtk.Label(label="Server URL:")
        lbl_url.set_xalign(0.0)
        self.entry_url = Gtk.Entry()
        self.entry_url.set_text(default_url)
        self.entry_url.set_hexpand(True)

        lbl_key = Gtk.Label(label="API Key:")
        lbl_key.set_xalign(0.0)
        self.entry_key = Gtk.Entry()
        self.entry_key.set_text(default_key)
        self.entry_key.set_placeholder_text("Paste Jellyfin API key here")
        self.entry_key.set_visibility(False)
        self.entry_key.set_activates_default(True)
        self.entry_key.set_hexpand(True)

        self.chk_show = Gtk.CheckButton(label="Show API key")
        self.chk_show.connect("toggled", lambda btn: self.entry_key.set_visibility(btn.get_active()))

        grid.attach(lbl_url, 0, 0, 1, 1)
        grid.attach(self.entry_url, 1, 0, 1, 1)
        grid.attach(lbl_key, 0, 1, 1, 1)
        grid.attach(self.entry_key, 1, 1, 1, 1)
        grid.attach(self.chk_show, 1, 2, 1, 1)

        box.pack_start(grid, True, True, 0)
        self.show_all()

dlg = JellyfinEnvDialog(
    os.environ.get("EXISTING_URL", "http://172.24.34.8:8096"),
    os.environ.get("EXISTING_KEY", ""),
)
resp = dlg.run()
url_val = dlg.entry_url.get_text().strip()
key_val = dlg.entry_key.get_text().strip()
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    sys.exit(99)

print(f"{url_val}\t{key_val}")
PY
) || rc=$?

if [ "$rc" -eq 99 ]; then
    if [ ! -f "$JF_ENV" ]; then
        cat <<EOF > "$JF_ENV"
# Jellyfin server URL and API key (Dashboard -> API Keys)
JELLYFIN_URL="$DEFAULT_JF_URL"
JELLYFIN_API_KEY=""
EOF
        chmod 600 "$JF_ENV"
    fi
    echo "[SKIP] Skipped Jellyfin API key prompt."
    record_op "SKIPPED" "Prompt for Jellyfin API key"
elif [ "$rc" -ne 0 ]; then
    echo "[ERROR] Jellyfin prompt dialog exited with code $rc."
    record_op "FAIL" "Prompt for Jellyfin API key"
    ((failed_ops++))
else
    IFS=$'\t' read -r input_url input_key <<< "$PROMPT_OUT"
    [ -z "$input_url" ] && input_url="$DEFAULT_JF_URL"
    # Strip any accidental double quotes to keep env syntax valid
    input_url=${input_url//\"/}
    input_key=${input_key//\"/}

    if printf '# Jellyfin server URL and API key (Dashboard -> API Keys)\nJELLYFIN_URL="%s"\nJELLYFIN_API_KEY="%s"\n' "$input_url" "$input_key" > "$JF_ENV" && chmod 600 "$JF_ENV"; then
        if [ -n "$input_key" ]; then
            echo "[OK] Saved Jellyfin URL and API key to $JF_ENV (chmod 600)."
            record_op "PASS" "Save Jellyfin API key to jellyfin.env"
        else
            echo "[OK] Saved Jellyfin URL (blank API key) to $JF_ENV."
            record_op "SKIPPED" "Save Jellyfin API key (left blank)"
        fi
    else
        echo "[ERROR] Failed to write $JF_ENV."
        record_op "FAIL" "Save Jellyfin API key to jellyfin.env"
        ((failed_ops++))
    fi
fi

if [ "$failed_ops" -gt 0 ]; then
    exit 1
fi
exit 0
