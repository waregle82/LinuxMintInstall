#!/usr/bin/env python3
import datetime
import getpass
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango

# ==============================================================================
# EMBEDDED SCRIPT MANIFEST (Edit execution order & descriptions right here)
# Format: "script_filename.sh | Short description shown in checklist"
# ==============================================================================
SCRIPT_MANIFEST = [
    "remote_smb.sh | Configure and mount remote SMB network shares",
    "automount_drives.sh | Configure universal udev automounting for SATA and USB drives",
    "repo_add.sh | Add third-party PPAs and external APT repositories",
    "repo_update.sh | Refresh APT package lists",
    "repo_upgrade.sh | Upgrade installed packages and remove unused dependencies",
    "install_deb.sh | Select and install native .deb packages via APT",
    "install_direct.sh | Download and install direct-download .deb apps",
    "install_debget.sh | Install applications managed through deb-get",
    "install_flatpak.sh | Select and install Flatpak applications from Flathub",
    "install_appimage.sh | Select, download, and integrate AppImage applications",
    "install_fonts.sh | Install Nerd Fonts, Google Fonts, and system font packs",
    "install_conky.sh | Configure MSI X870E sensors & Jellyfin API key for Conky",
    "user_accounts.sh | Create local family user accounts and set passwords",
    "user_avatars.sh | Configure AccountsService user login avatars",
    "uninstall.sh | Remove unwanted default pre-installed applications",
]

MAX_LOG_FILES = 5


class ScriptRunnerApp(Gtk.Window):
    def __init__(self, base_dir: Path, script_dir: Path, valid_scripts: list, missing_scripts: list):
        super().__init__(title="Linux Mint Post-Install Script Runner")
        self.base_dir = base_dir
        self.script_dir = script_dir
        self.valid_scripts = valid_scripts
        self.missing_scripts = missing_scripts

        self.log_dir = Path.home() / ".install_logs"
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self._rotate_logs()

        self.run_ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        self.log_file = self.log_dir / f"{self.run_ts}_scripts_run.log"

        self.proc = None
        self.cancelled = False
        self.dry_run = False
        self.keepalive_stop = threading.Event()
        self.keepalive_thread = None
        self.sudo_authenticated = False
        self._sudo_password = None
        self.results = []
        self.ops_records = []
        self.selected_queue = []

        self._configure_window_geometry()
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(12)
        self.connect("delete-event", self._on_window_delete)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(150)
        self.add(self.stack)

        self._build_selection_page()
        self._build_execution_page()
        self._build_summary_page()

        self.stack.set_visible_child_name("select")
        self.show_all()

        if self.missing_scripts:
            self._show_missing_warning()

    def _configure_window_geometry(self):
        row_count = max(len(self.valid_scripts), 6)
        desired_h = 185 + (row_count * 38)
        desired_w = 720

        display = Gdk.Display.get_default()
        if display:
            monitor = display.get_primary_monitor() or display.get_monitor(0)
            if monitor:
                workarea = monitor.get_workarea()
                max_h = int(workarea.height * 0.85)
                max_w = int(workarea.width * 0.85)
                desired_h = min(desired_h, max_h)
                desired_w = min(desired_w, max_w)

        self.set_default_size(desired_w, desired_h)

    def _rotate_logs(self):
        logs = sorted(
            self.log_dir.glob("*_scripts_run.log"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        for old_log in logs[MAX_LOG_FILES - 1 :]:
            try:
                old_log.unlink()
            except OSError:
                pass

    # --------------------------------------------------------------------------
    # PAGE 1: SCRIPT SELECTION
    # --------------------------------------------------------------------------
    def _build_selection_page(self):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        header = Gtk.Label()
        header.set_markup(
            "<span size='large' weight='bold'>Linux Mint Post-Install Setup</span>\n"
            "<span size='small'>Select the setup scripts you want to execute in order:</span>"
        )
        header.set_xalign(0.0)
        vbox.pack_start(header, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.select_all_cb = Gtk.CheckButton(label="Select All")
        self.select_all_cb.set_active(False)
        self.select_all_handler = self.select_all_cb.connect("toggled", self._on_select_all_toggled)
        toolbar.pack_start(self.select_all_cb, False, False, 0)

        self.dry_run_cb = Gtk.CheckButton(label="Dry Run (simulate without making changes)")
        self.dry_run_cb.set_active(False)
        toolbar.pack_start(self.dry_run_cb, False, False, 0)

        self.count_label = Gtk.Label(label=f"0 of {len(self.valid_scripts)} selected")
        self.count_label.set_xalign(1.0)
        toolbar.pack_end(self.count_label, False, False, 0)
        vbox.pack_start(toolbar, False, False, 0)

        # ListStore: [selected (bool), order (int), script_name (str), description (str)]
        self.store = Gtk.ListStore(bool, int, str, str)
        for idx, (script_name, desc) in enumerate(self.valid_scripts, start=1):
            self.store.append([False, idx, script_name, desc])

        self.treeview = Gtk.TreeView(model=self.store)
        self.treeview.set_headers_visible(True)
        self.treeview.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        toggle_renderer = Gtk.CellRendererToggle()
        toggle_renderer.connect("toggled", self._on_row_toggled)
        col_check = Gtk.TreeViewColumn("Run", toggle_renderer, active=0)
        col_check.set_fixed_width(50)
        self.treeview.append_column(col_check)

        num_renderer = Gtk.CellRendererText()
        col_num = Gtk.TreeViewColumn("#", num_renderer, text=1)
        col_num.set_fixed_width(40)
        self.treeview.append_column(col_num)

        name_renderer = Gtk.CellRendererText()
        name_renderer.set_property("weight", Pango.Weight.BOLD)
        col_name = Gtk.TreeViewColumn("Script", name_renderer, text=2)
        col_name.set_min_width(180)
        self.treeview.append_column(col_name)

        desc_renderer = Gtk.CellRendererText()
        desc_renderer.set_property("ellipsize", Pango.EllipsizeMode.END)
        col_desc = Gtk.TreeViewColumn("Description", desc_renderer, text=3)
        col_desc.set_expand(True)
        self.treeview.append_column(col_desc)

        self.treeview.connect("row-activated", self._on_row_activated)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_shadow_type(Gtk.ShadowType.IN)
        scrolled.add(self.treeview)
        vbox.pack_start(scrolled, True, True, 0)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        quit_btn = Gtk.Button(label="Quit")
        quit_btn.connect("clicked", lambda *_: self._cleanup_and_quit())
        btn_box.pack_end(quit_btn, False, False, 0)

        self.run_btn = Gtk.Button(label="Run Selected")
        self.run_btn.get_style_context().add_class("suggested-action")
        self.run_btn.set_sensitive(False)
        self.run_btn.connect("clicked", self._on_run_clicked)
        btn_box.pack_end(self.run_btn, False, False, 0)

        vbox.pack_start(btn_box, False, False, 0)
        self.stack.add_named(vbox, "select")

    def _on_row_activated(self, treeview, path, column):
        self._toggle_row(path)

    def _on_row_toggled(self, renderer, path_str):
        self._toggle_row(Gtk.TreePath.new_from_string(path_str))

    def _toggle_row(self, path):
        it = self.store.get_iter(path)
        current = self.store.get_value(it, 0)
        self.store.set_value(it, 0, not current)
        self._sync_selection_state()

    def _on_select_all_toggled(self, button):
        target = button.get_active()
        button.set_inconsistent(False)
        for row in self.store:
            row[0] = target
        self._sync_selection_state(update_master=False)

    def _sync_selection_state(self, update_master=True):
        total = len(self.store)
        selected = sum(1 for row in self.store if row[0])
        self.count_label.set_text(f"{selected} of {total} selected")
        self.run_btn.set_sensitive(selected > 0)

        if update_master:
            self.select_all_cb.handler_block(self.select_all_handler)
            if selected == 0:
                self.select_all_cb.set_active(False)
                self.select_all_cb.set_inconsistent(False)
            elif selected == total:
                self.select_all_cb.set_active(True)
                self.select_all_cb.set_inconsistent(False)
            else:
                self.select_all_cb.set_active(False)
                self.select_all_cb.set_inconsistent(True)
            self.select_all_cb.handler_unblock(self.select_all_handler)

    def _show_missing_warning(self):
        msg = "The following scripts listed in SCRIPT_MANIFEST were not found in:\n"
        msg += f"{self.script_dir}\n\n" + "\n".join(f"• {s}" for s in self.missing_scripts)
        dlg = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK,
            text="Missing Scripts Detected",
        )
        dlg.format_secondary_text(msg)
        dlg.run()
        dlg.destroy()

    # --------------------------------------------------------------------------
    # SUDO AUTHENTICATION & KEEP-ALIVE
    # --------------------------------------------------------------------------
    def _prompt_sudo_password(self) -> bool:
        user = getpass.getuser()
        for attempt in range(1, 4):
            dlg = Gtk.Dialog(
                title="Administrator Authentication Required",
                transient_for=self,
                modal=True,
            destroy_with_parent=True,
            )
            dlg.add_button("Cancel", Gtk.ResponseType.CANCEL)
            ok_btn = dlg.add_button("Authenticate", Gtk.ResponseType.OK)
            ok_btn.get_style_context().add_class("suggested-action")
            dlg.set_default_response(Gtk.ResponseType.OK)
            dlg.set_default_size(440, 190)

            box = dlg.get_content_area()
            box.set_border_width(14)
            box.set_spacing(10)

            err_note = (
                "\n<span foreground='#e01b24' weight='bold'>Incorrect password. Please try again.</span>"
                if attempt > 1
                else ""
            )
            lbl = Gtk.Label()
            lbl.set_markup(
                f"<b>Administrator privileges are required to run your selected scripts.</b>\n\n"
                f"Enter the password for <b>{GLib.markup_escape_text(user)}</b>. Your session "
                f"will remain authenticated while scripts run and revoke automatically when finished."
                f"{err_note}"
            )
            lbl.set_line_wrap(True)
            lbl.set_xalign(0.0)
            box.pack_start(lbl, False, False, 0)

            entry = Gtk.Entry()
            entry.set_visibility(False)
            entry.set_activates_default(True)
            entry.set_placeholder_text("Password")
            box.pack_start(entry, False, False, 0)

            dlg.show_all()
            entry.grab_focus()
            resp = dlg.run()
            pwd = entry.get_text()
            dlg.destroy()

            if resp != Gtk.ResponseType.OK:
                pwd = ""
                del pwd
                return False

            try:
                res = subprocess.run(
                    ["sudo", "-S", "-v"],
                    input=(pwd + "\n").encode("utf-8"),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=15,
                )
                valid = res.returncode == 0
            except Exception:
                valid = False

            if valid:
                self.sudo_authenticated = True
                self._sudo_password = pwd
                pwd = ""
                del pwd
                return True

            pwd = ""
            del pwd

        return False

    def _start_sudo_keepalive(self):
        self.keepalive_stop.clear()

        def _loop():
            while not self.keepalive_stop.wait(45.0):
                try:
                    subprocess.run(
                        ["sudo", "-n", "-v"],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=10,
                    )
                except Exception:
                    pass

        self.keepalive_thread = threading.Thread(target=_loop, daemon=True)
        self.keepalive_thread.start()

    def _stop_sudo_keepalive(self):
        self.keepalive_stop.set()
        if self.keepalive_thread and self.keepalive_thread.is_alive():
            self.keepalive_thread.join(timeout=1.0)
        self.keepalive_thread = None

    def revoke_sudo_session(self):
        self._stop_sudo_keepalive()
        self._sudo_password = None
        if self.sudo_authenticated:
            try:
                subprocess.run(
                    ["sudo", "-k"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                )
            except Exception:
                pass
            self.sudo_authenticated = False

    # --------------------------------------------------------------------------
    # PAGE 2: EXECUTION & LIVE CONSOLE
    # --------------------------------------------------------------------------
    def _build_execution_page(self):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        self.exec_status_lbl = Gtk.Label()
        self.exec_status_lbl.set_xalign(0.0)
        vbox.pack_start(self.exec_status_lbl, False, False, 0)

        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_show_text(True)
        vbox.pack_start(self.progress_bar, False, False, 0)

        self.console_buf = Gtk.TextBuffer()
        self.console_view = Gtk.TextView(buffer=self.console_buf)
        self.console_view.set_editable(False)
        self.console_view.set_cursor_visible(False)
        self.console_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.console_view.modify_font(Pango.FontDescription("Monospace 9"))

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_shadow_type(Gtk.ShadowType.IN)
        scrolled.add(self.console_view)
        vbox.pack_start(scrolled, True, True, 0)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.cancel_btn = Gtk.Button(label="Cancel Run")
        self.cancel_btn.get_style_context().add_class("destructive-action")
        self.cancel_btn.connect("clicked", self._on_cancel_clicked)
        btn_box.pack_end(self.cancel_btn, False, False, 0)
        vbox.pack_start(btn_box, False, False, 0)

        self.stack.add_named(vbox, "execute")

    def _append_console(self, text: str):
        if not self.console_buf or not self.console_view:
            return False
        end_iter = self.console_buf.get_end_iter()
        self.console_buf.insert(end_iter, text)
        mark = self.console_buf.create_mark(None, self.console_buf.get_end_iter(), False)
        self.console_view.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)
        self.console_buf.delete_mark(mark)
        return False

    def _on_run_clicked(self, button):
        queue = [(row[2], row[3]) for row in self.store if row[0]]
        if not queue:
            return

        self.dry_run = self.dry_run_cb.get_active()
        if not self.dry_run and not self._prompt_sudo_password():
            return

        self.selected_queue = queue
        self.cancelled = False
        self.results = []
        self.ops_records = []
        self.console_buf.set_text("")
        self.cancel_btn.set_sensitive(True)
        self.progress_bar.set_fraction(0.0)
        self.progress_bar.set_text("Starting...")

        self.run_ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        self.log_file = self.log_dir / f"{self.run_ts}_scripts_run.log"
        self._rotate_logs()

        self.stack.set_visible_child_name("execute")
        worker = threading.Thread(target=self._execute_scripts, daemon=True)
        worker.start()

    def _on_cancel_clicked(self, button):
        self.cancelled = True
        self.cancel_btn.set_sensitive(False)
        GLib.idle_add(self._append_console, "\n[!] Cancellation requested by user...\n")
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
            except Exception:
                pass

    def _build_shim_dir(self, tmp_dir: Path, ops_file: Path) -> Path:
        shim_dir = tmp_dir / "shims"
        shim_dir.mkdir(parents=True, exist_ok=True)
        real_sudo = shutil.which("sudo") or "/usr/bin/sudo"

        helper_script = tmp_dir / "log_op.sh"
        helper_code = """#!/bin/bash
status="$1"
label="$2"
if [ -n "${OPERATIONS_FILE:-}" ]; then
    printf '%s|%s|%s\n' "${CURRENT_SCRIPT:-unknown}" "$status" "$label" >> "$OPERATIONS_FILE"
fi
"""
        helper_script.write_text(helper_code, encoding="utf-8")
        helper_script.chmod(0o755)

        askpass_script = shim_dir / "askpass.sh"
        askpass_code = """#!/usr/bin/env python3
import sys
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

prompt_text = sys.argv[1] if len(sys.argv) > 1 else "Enter administrator password:"

dlg = Gtk.Dialog(
    title="Administrator Authentication Required",
    modal=True,
    destroy_with_parent=True,
)
dlg.add_button("Cancel", Gtk.ResponseType.CANCEL)
ok_btn = dlg.add_button("Authenticate", Gtk.ResponseType.OK)
ok_btn.get_style_context().add_class("suggested-action")
dlg.set_default_response(Gtk.ResponseType.OK)
dlg.set_default_size(420, 150)
dlg.set_position(Gtk.WindowPosition.CENTER)

box = dlg.get_content_area()
box.set_border_width(14)
box.set_spacing(10)

lbl = Gtk.Label(label=prompt_text)
lbl.set_line_wrap(True)
lbl.set_xalign(0.0)
box.pack_start(lbl, False, False, 0)

entry = Gtk.Entry()
entry.set_visibility(False)
entry.set_activates_default(True)
entry.set_placeholder_text("Password")
box.pack_start(entry, False, False, 0)

dlg.show_all()
entry.grab_focus()
resp = dlg.run()
pwd = entry.get_text()
dlg.destroy()

if resp != Gtk.ResponseType.OK:
    pwd = ""
    del pwd
    sys.exit(1)

sys.stdout.write(pwd + "\n")
sys.stdout.flush()
pwd = ""
del pwd
"""
        askpass_script.write_text(askpass_code, encoding="utf-8")
        askpass_script.chmod(0o755)

        sudo_shim = shim_dir / "sudo"
        sudo_code = f"""#!/bin/bash
REAL_SUDO="{real_sudo}"
export SUDO_ASKPASS="{askpass_script}"
PRESERVE_VARS="OPERATIONS_FILE,CURRENT_SCRIPT,PATH,SUDO_ASKPASS,RUNNER_SUDO_PASS"

# Do not intercept help/version flags
case " $* " in
    *" -h "*|*" --help "*|*" -V "*|*" --version "*)
        exec "$REAL_SUDO" --preserve-env="$PRESERVE_VARS" "$@"
        ;;
esac

# Refresh cached credential non-interactively if needed using the session password
if ! "$REAL_SUDO" -n true >/dev/null 2>&1; then
    if [ -n "${{RUNNER_SUDO_PASS:-}}" ]; then
        printf '%s\n' "$RUNNER_SUDO_PASS" | "$REAL_SUDO" -S -v >/dev/null 2>&1 || true
    fi
fi

if "$REAL_SUDO" -n true >/dev/null 2>&1; then
    exec "$REAL_SUDO" --preserve-env="$PRESERVE_VARS" "$@"
else
    case " $* " in
        *" -S "*|*" --stdin "*)
            exec "$REAL_SUDO" --preserve-env="$PRESERVE_VARS" "$@"
            ;;
        *)
            exec "$REAL_SUDO" -A --preserve-env="$PRESERVE_VARS" "$@"
            ;;
    esac
fi
"""
        sudo_shim.write_text(sudo_code, encoding="utf-8")
        sudo_shim.chmod(0o755)
        return shim_dir

    def _execute_scripts(self):
        self._start_sudo_keepalive()
        total = len(self.selected_queue)
        raw_output_lines = []

        tmp_root = Path(tempfile.mkdtemp(prefix="mint_runner_"))
        ops_file = tmp_root / "operations.log"
        ops_file.touch()

        try:
            shim_dir = self._build_shim_dir(tmp_root, ops_file)

            for idx, (script_name, desc) in enumerate(self.selected_queue, start=1):
                if self.cancelled:
                    self.results.append((script_name, "CANCELLED", "0.0s", desc))
                    continue

                script_path = self.script_dir / script_name
                GLib.idle_add(
                    self.exec_status_lbl.set_markup,
                    f"<b>Running ({idx}/{total}):</b> {GLib.markup_escape_text(script_name)} — {GLib.markup_escape_text(desc)}",
                )
                GLib.idle_add(self.progress_bar.set_fraction, (idx - 1) / total)
                GLib.idle_add(self.progress_bar.set_text, f"{idx - 1} / {total} completed")

                banner = f"\n{'=' * 72}\n[{idx}/{total}] {script_name} — {desc}\n{'=' * 72}\n"
                raw_output_lines.append(banner)
                GLib.idle_add(self._append_console, banner)

                env = os.environ.copy()
                env["PATH"] = f"{shim_dir}:{env.get('PATH', '')}"
                env["OPERATIONS_FILE"] = str(ops_file)
                env["CURRENT_SCRIPT"] = script_name
                env["SUDO_ASKPASS"] = str(shim_dir / "askpass.sh")
                if self._sudo_password:
                    env["RUNNER_SUDO_PASS"] = self._sudo_password

                t0 = time.monotonic()
                try:
                    self.proc = subprocess.Popen(
                        [str(script_path)],
                        cwd=str(self.base_dir),
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                    )

                    assert self.proc.stdout is not None
                    for line in self.proc.stdout:
                        raw_output_lines.append(line)
                        GLib.idle_add(self._append_console, line)

                    rc = self.proc.wait()
                except Exception as exc:
                    err_line = f"[ERROR] Failed to launch {script_name}: {exc}\n"
                    raw_output_lines.append(err_line)
                    GLib.idle_add(self._append_console, err_line)
                    rc = 1
                finally:
                    self.proc = None

                elapsed = f"{time.monotonic() - t0:.1f}s"

                if self.cancelled:
                    status = "CANCELLED"
                elif rc == 0:
                    status = "PASS"
                elif rc == 99:
                    status = "SKIPPED"
                else:
                    status = f"FAIL (code {rc})"

                self.results.append((script_name, status, elapsed, desc))
                footer = f"\n>>> Finished {script_name}: {status} ({elapsed})\n"
                raw_output_lines.append(footer)
                GLib.idle_add(self._append_console, footer)

            GLib.idle_add(self.progress_bar.set_fraction, 1.0)
            GLib.idle_add(self.progress_bar.set_text, f"{total} / {total} processed")

            if ops_file.exists():
                for line in ops_file.read_text(encoding="utf-8", errors="replace").splitlines():
                    parts = line.split("|")
                    if len(parts) == 2:
                        self.ops_records.append(("subscript", parts[0].strip(), parts[1].strip()))
                    elif len(parts) >= 3:
                        self.ops_records.append((parts[0].strip(), parts[1].strip(), "|".join(parts[2:]).strip()))

            self._write_final_log(raw_output_lines)

        finally:
            self.revoke_sudo_session()
            shutil.rmtree(tmp_root, ignore_errors=True)
            GLib.idle_add(self._show_summary_page)

    def _write_final_log(self, raw_output_lines: list):
        passed = sum(1 for _, st, _, _ in self.results if st == "PASS")
        skipped = sum(1 for _, st, _, _ in self.results if st == "SKIPPED")
        failed = sum(1 for _, st, _, _ in self.results if st.startswith("FAIL"))
        cancelled = sum(1 for _, st, _, _ in self.results if st == "CANCELLED")

        lines = [
            "=" * 78,
            f"LINUX MINT POST-INSTALL RUN REPORT — {self.run_ts}",
            f"Scripts: {passed} PASSED | {failed} FAILED | {skipped} SKIPPED | {cancelled} CANCELLED",
            "=" * 78,
            "",
            f"{'STATUS':<16} {'TIME':<8} {'SCRIPT':<24} DESCRIPTION",
            "-" * 78,
        ]
        for script_name, status, dur, desc in self.results:
            lines.append(f"{status:<16} {dur:<8} {script_name:<24} {desc}")

        if self.ops_records:
            op_pass = sum(1 for _, st, _ in self.ops_records if st == "PASS")
            op_fail = sum(1 for _, st, _ in self.ops_records if st == "FAIL")
            op_skip = sum(1 for _, st, _ in self.ops_records if st == "SKIPPED")
            lines.extend([
                "",
                "=" * 78,
                f"INDIVIDUAL OPERATIONS ({op_pass} PASSED | {op_fail} FAILED | {op_skip} SKIPPED)",
                "=" * 78,
                f"{'STATUS':<12} {'SOURCE':<22} OPERATION",
                "-" * 78,
            ])
            for src, st, op_name in self.ops_records:
                lines.append(f"{st:<12} {src:<22} {op_name}")

        lines.extend([
            "",
            "=" * 78,
            "FULL EXECUTION OUTPUT",
            "=" * 78,
        ])
        lines.extend(raw_output_lines)

        self.log_file.write_text("\n".join(lines), encoding="utf-8")

    # --------------------------------------------------------------------------
    # PAGE 3: SUMMARY REPORT
    # --------------------------------------------------------------------------
    def _build_summary_page(self):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        self.sum_header = Gtk.Label()
        self.sum_header.set_xalign(0.0)
        vbox.pack_start(self.sum_header, False, False, 0)

        # [badge, duration, script_name, description]
        self.sum_store = Gtk.ListStore(str, str, str, str)
        sum_tree = Gtk.TreeView(model=self.sum_store)
        sum_tree.set_grid_lines(Gtk.TreeViewGridLines.HORIZONTAL)

        for idx, (title, width, expand) in enumerate([
            ("Result", 145, False),
            ("Time", 70, False),
            ("Script", 180, False),
            ("Description", 250, True),
        ]):
            r = Gtk.CellRendererText()
            if idx in (0, 2):
                r.set_property("weight", Pango.Weight.BOLD)
            col = Gtk.TreeViewColumn(title, r, text=idx)
            col.set_min_width(width)
            col.set_expand(expand)
            sum_tree.append_column(col)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_shadow_type(Gtk.ShadowType.IN)
        scrolled.add(sum_tree)
        vbox.pack_start(scrolled, True, True, 0)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        view_log_btn = Gtk.Button(label="View Full Log")
        view_log_btn.connect("clicked", self._on_view_log_clicked)
        btn_box.pack_start(view_log_btn, False, False, 0)

        open_dir_btn = Gtk.Button(label="Open Logs Folder")
        open_dir_btn.connect("clicked", self._on_open_logs_folder)
        btn_box.pack_start(open_dir_btn, False, False, 0)

        close_btn = Gtk.Button(label="Close")
        close_btn.connect("clicked", lambda *_: self._cleanup_and_quit())
        btn_box.pack_end(close_btn, False, False, 0)

        back_btn = Gtk.Button(label="Back to Selection")
        back_btn.connect("clicked", self._on_back_to_selection)
        btn_box.pack_end(back_btn, False, False, 0)

        vbox.pack_start(btn_box, False, False, 0)
        self.stack.add_named(vbox, "summary")

    def _show_summary_page(self):
        self.sum_store.clear()
        passed = sum(1 for _, st, _, _ in self.results if st == "PASS")
        skipped = sum(1 for _, st, _, _ in self.results if st == "SKIPPED")
        failed = sum(1 for _, st, _, _ in self.results if st.startswith("FAIL"))
        cancelled = sum(1 for _, st, _, _ in self.results if st == "CANCELLED")

        self.sum_header.set_markup(
            f"<span size='large' weight='bold'>Execution Complete</span> — "
            f"<b>{passed}</b> Passed, <b>{failed}</b> Failed, <b>{skipped}</b> Skipped, <b>{cancelled}</b> Cancelled\n"
            f"<span size='small'>Log saved to: {GLib.markup_escape_text(str(self.log_file))}</span>"
        )

        for script_name, status, dur, desc in self.results:
            if status == "PASS":
                badge = f"✅ {status}"
            elif status == "SKIPPED":
                badge = f"⏭️ {status}"
            elif status.startswith("FAIL"):
                badge = f"❌ {status}"
            else:
                badge = f"⚠️ {status}"
            self.sum_store.append([badge, dur, script_name, desc])

        self.stack.set_visible_child_name("summary")
        return False

    def _on_back_to_selection(self, button):
        self.console_buf.set_text("")
        self.progress_bar.set_fraction(0.0)
        self.progress_bar.set_text("")
        for row in self.store:
            row[0] = False
        self._sync_selection_state(update_master=True)
        self.stack.set_visible_child_name("select")

    def _on_view_log_clicked(self, button):
        dlg = Gtk.Dialog(
            title=f"Run Log — {self.log_file.name}",
            transient_for=self,
            modal=True,
            destroy_with_parent=True,
        )
        dlg.add_button("Close", Gtk.ResponseType.CLOSE)
        dlg.set_default_size(760, 540)

        box = dlg.get_content_area()
        box.set_border_width(10)

        buf = Gtk.TextBuffer()
        if self.log_file.exists():
            buf.set_text(self.log_file.read_text(encoding="utf-8", errors="replace"))

        tv = Gtk.TextView(buffer=buf)
        tv.set_editable(False)
        tv.set_cursor_visible(False)
        tv.modify_font(Pango.FontDescription("Monospace 10"))

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        sw.set_shadow_type(Gtk.ShadowType.IN)
        sw.add(tv)
        box.pack_start(sw, True, True, 0)

        dlg.show_all()
        dlg.run()
        dlg.destroy()

    def _on_open_logs_folder(self, button):
        try:
            subprocess.Popen(["xdg-open", str(self.log_dir)])
        except Exception:
            pass

    def _on_window_delete(self, widget, event):
        self._cleanup_and_quit()
        return False

    def _cleanup_and_quit(self):
        self.cancelled = True
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.terminate()
            except Exception:
                pass
        self.revoke_sudo_session()
        Gtk.main_quit()


def default_description(script_name: str) -> str:
    stem = re.sub(r"^\d+[-_]*", "", Path(script_name).stem)
    return stem.replace("_", " ").replace("-", " ").title()


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    script_dir = base_dir / "scripts"

    if not script_dir.is_dir():
        dlg = Gtk.MessageDialog(
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Scripts Directory Not Found",
        )
        dlg.format_secondary_text(
            f"Expected a 'scripts/' subdirectory next to {Path(__file__).name}:\n{script_dir}"
        )
        dlg.run()
        dlg.destroy()
        return 1

    valid_scripts = []
    missing_scripts = []

    for entry in SCRIPT_MANIFEST:
        if "|" in entry:
            raw_name, raw_desc = entry.split("|", 1)
            s_name = raw_name.strip()
            s_desc = raw_desc.strip() or default_description(s_name)
        else:
            s_name = entry.strip()
            s_desc = default_description(s_name)

        if not s_name:
            continue

        s_path = script_dir / s_name
        if s_path.is_file():
            try:
                s_path.chmod(s_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            except OSError:
                pass
            valid_scripts.append((s_name, s_desc))
        else:
            missing_scripts.append(s_name)

    if not valid_scripts:
        dlg = Gtk.MessageDialog(
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="No Executable Scripts Found",
        )
        dlg.format_secondary_text(
            f"None of the scripts listed in SCRIPT_MANIFEST were found in:\n{script_dir}"
        )
        dlg.run()
        dlg.destroy()
        return 1

    app = ScriptRunnerApp(base_dir, script_dir, valid_scripts, missing_scripts)
    signal.signal(signal.SIGINT, lambda *_: app._cleanup_and_quit())
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
