<div align="center">
  <h1>Linux Mint Post-Install Script Runner</h1>
  <p><strong>A modular Python 3 + GTK3 setup orchestrator for clean Linux Mint installations</strong></p>
  <p>
    <code>Linux Mint 22.x (Cinnamon / X11)</code> &bull;
    <code>Python 3 + GTK3</code> &bull;
    <code>Bash Worker Suite</code> &bull;
    <code>Auto-Rotating Logs</code>
  </p>
</div>

<hr>

<details open>
<summary><h2>✨ Overview &amp; Architecture</h2></summary>

<p><code>install_python.py</code> provides a single graphical interface to select, authenticate, monitor, and audit a modular suite of post-installation Bash scripts on a clean Linux Mint workstation.</p>

<table>
  <thead>
    <tr>
      <th>Feature</th>
      <th>Implementation</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Three-Stage GTK3 UI</strong></td>
      <td><strong>Selection</strong> checklist &rarr; <strong>Execution</strong> live monospace console &amp; progress bar &rarr; <strong>Summary</strong> status table with log viewer.</td>
    </tr>
    <tr>
      <td><strong>Single <code>sudo</code> Lifecycle</strong></td>
      <td>Prompts once via native GTK dialog, passes <code>SUDO_ASKPASS</code> (<code>askpass.sh</code>) and <code>RUNNER_SUDO_PASS</code> to child scripts, maintains credentials with a 45-second <code>sudo -n -v</code> keep-alive loop, and clears cached credentials while revoking via <code>sudo -k</code> on exit or cancel.</td>
    </tr>
    <tr>
      <td><strong>Centralized Log Rotation</strong></td>
      <td>Writes timestamped reports to <code>~/.install_logs/YYYYMMDD-HHMMSS_scripts_run.log</code> (combining summary, per-item <code>OPERATIONS_FILE</code> records, and full console output) while retaining only the <strong>5 most recent runs</strong>.</td>
    </tr>
    <tr>
      <td><strong>Graceful Skip &amp; Error Tracking</strong></td>
      <td>Treats exit code <code>0</code> as <code>PASS</code>, exit code <code>99</code> (cancelled sub-dialog) as <code>SKIPPED</code>, and any non-zero error code as <code>FAIL</code>.</td>
    </tr>
    <tr>
      <td><strong>Auto-Executable Permissions</strong></td>
      <td>Automatically applies <code>chmod +x</code> to every valid script discovered in <code>./scripts/</code> at startup.</td>
    </tr>
    <tr>
      <td><strong>Dry Run Simulation</strong></td>
      <td>Provides a <strong>Dry Run (simulate without making changes)</strong> checkbox on the selection screen to preview script execution paths, working directories, and executable status without prompting for <code>sudo</code> or running scripts.</td>
    </tr>
  </tbody>
</table>

</details>

<hr>

<details open>
<summary><h2>📂 Directory Layout</h2></summary>

<pre><code>post-install/
├── install_python.py        # Main GTK3 orchestrator &amp; log manager
└── scripts/                 # Modular worker scripts executed in manifest order
    ├── remote_smb.sh
    ├── automount_drives.sh
    ├── repo_add.sh
    ├── repo_update.sh
    ├── repo_upgrade.sh
    ├── install_deb.sh
    ├── install_direct.sh
    ├── install_debget.sh
    ├── install_flatpak.sh
    ├── install_appimage.sh
    ├── install_fonts.sh
    ├── install_conky.sh
    ├── user_accounts.sh
    ├── user_avatars.sh
    └── uninstall.sh</code></pre>

</details>

<hr>

<details open>
<summary><h2>🔄 Helper Scripts Pipeline</h2></summary>

<p>Scripts execute sequentially in the exact order defined in <code>SCRIPT_MANIFEST</code> inside <code>install_python.py</code>:</p>

<table>
  <thead>
    <tr>
      <th>Script</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>remote_smb.sh</code></td>
      <td>Configure and mount remote SMB network shares</td>
    </tr>
    <tr>
      <td><code>automount_drives.sh</code></td>
      <td>Configure universal udev automounting for SATA and USB drives</td>
    </tr>
    <tr>
      <td><code>repo_add.sh</code></td>
      <td>Add third-party PPAs and external APT repositories</td>
    </tr>
    <tr>
      <td><code>repo_update.sh</code></td>
      <td>Refresh APT package lists</td>
    </tr>
    <tr>
      <td><code>repo_upgrade.sh</code></td>
      <td>Upgrade installed packages and remove unused dependencies</td>
    </tr>
    <tr>
      <td><code>install_deb.sh</code></td>
      <td>Select and install native .deb packages via APT</td>
    </tr>
    <tr>
      <td><code>install_direct.sh</code></td>
      <td>Download and install direct-download .deb apps</td>
    </tr>
    <tr>
      <td><code>install_debget.sh</code></td>
      <td>Install applications managed through deb-get</td>
    </tr>
    <tr>
      <td><code>install_flatpak.sh</code></td>
      <td>Select and install Flatpak applications from Flathub</td>
    </tr>
    <tr>
      <td><code>install_appimage.sh</code></td>
      <td>Select, download, and integrate AppImage applications</td>
    </tr>
    <tr>
      <td><code>install_fonts.sh</code></td>
      <td>Install Nerd Fonts, Google Fonts, and system font packs</td>
    </tr>
    <tr>
      <td><code>install_conky.sh</code></td>
      <td>Configure MSI X870E sensors &amp; Jellyfin API key for Conky</td>
    </tr>
    <tr>
      <td><code>user_accounts.sh</code></td>
      <td>Create local family user accounts and set passwords</td>
    </tr>
    <tr>
      <td><code>user_avatars.sh</code></td>
      <td>Configure AccountsService user login avatars</td>
    </tr>
    <tr>
      <td><code>uninstall.sh</code></td>
      <td>Remove unwanted default pre-installed applications</td>
    </tr>
  </tbody>
</table>

</details>

<hr>

<details open>
<summary><h2>📦 Included Software Manifests</h2></summary>

<details>
<summary><strong>3rd-Party Repositories (<code>repo_add.sh</code> — 8 sources)</strong></summary>
<br>
<table>
  <thead>
    <tr>
      <th>Repository</th>
      <th>Source / PPA</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Claude Desktop</strong></td>
      <td><code>https://downloads.claude.ai/claude-desktop/apt/stable</code></td>
    </tr>
    <tr>
      <td><strong>Fastfetch</strong></td>
      <td><code>ppa:zhangsongcui3371/fastfetch</code></td>
    </tr>
    <tr>
      <td><strong>NetBird</strong></td>
      <td><code>https://pkgs.netbird.io/debian</code></td>
    </tr>
    <tr>
      <td><strong>OBS Studio</strong></td>
      <td><code>ppa:obsproject/obs-studio</code></td>
    </tr>
    <tr>
      <td><strong>Sublime Text &amp; Merge</strong></td>
      <td><code>https://download.sublimetext.com/ apt/stable/</code></td>
    </tr>
    <tr>
      <td><strong>ULauncher</strong></td>
      <td><code>ppa:agornostal/ulauncher</code></td>
    </tr>
    <tr>
      <td><strong>Variety</strong></td>
      <td><code>ppa:variety/stable</code></td>
    </tr>
    <tr>
      <td><strong>WG Tunnel</strong></td>
      <td><code>https://apt.wgtunnel.com</code></td>
    </tr>
  </tbody>
</table>
</details>

<br>

<details>
<summary><strong>Native <code>.deb</code> Packages (<code>install_deb.sh</code> — 62 packages)</strong></summary>
<br>
<table>
  <thead>
    <tr>
      <th>Package</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td><code>7zip</code></td><td>High-compression file archiver and command-line utility</td></tr>
    <tr><td><code>alsa-scarlett-gui</code></td><td>Graphical mixer and routing control for Focusrite Scarlett USB interfaces</td></tr>
    <tr><td><code>blender</code></td><td>3D modeling, animation, rendering, and video editing suite</td></tr>
    <tr><td><code>calibre</code></td><td>E-book library manager, reader, and format converter</td></tr>
    <tr><td><code>claude-desktop</code></td><td>Official Anthropic Claude desktop client for Linux</td></tr>
    <tr><td><code>conky-all</code></td><td>Lightweight desktop system monitor widget engine</td></tr>
    <tr><td><code>curl</code></td><td>Command-line tool for transferring data over URLs</td></tr>
    <tr><td><code>darktable</code></td><td>Open-source photography workflow and RAW image developer</td></tr>
    <tr><td><code>dosbox</code></td><td>x86 MS-DOS emulator for classic games and legacy software</td></tr>
    <tr><td><code>fastfetch</code></td><td>Fast system information fetcher for terminal summaries</td></tr>
    <tr><td><code>gimp</code></td><td>GNU Image Manipulation Program for photo retouching and graphics</td></tr>
    <tr><td><code>git</code></td><td>Distributed version control system</td></tr>
    <tr><td><code>gparted</code></td><td>Graphical disk partition editor</td></tr>
    <tr><td><code>grsync</code></td><td>GTK graphical front-end for rsync file synchronization</td></tr>
    <tr><td><code>handbrake</code></td><td>Open-source multi-format video transcoder</td></tr>
    <tr><td><code>htop</code></td><td>Interactive terminal process viewer and system monitor</td></tr>
    <tr><td><code>iperf3</code></td><td>Network bandwidth and throughput measurement tool</td></tr>
    <tr><td><code>jq</code></td><td>Lightweight command-line JSON processor</td></tr>
    <tr><td><code>lm-sensors</code></td><td>Hardware temperature, voltage, and fan sensor monitoring utilities</td></tr>
    <tr><td><code>lsb-release</code></td><td>Linux Standard Base distribution identification utility</td></tr>
    <tr><td><code>ncdu</code></td><td>NCurses-based interactive disk usage analyzer</td></tr>
    <tr><td><code>nemo-image-converter</code></td><td>Nemo file manager extension to resize and rotate images</td></tr>
    <tr><td><code>netbird</code></td><td>WireGuard-based zero-trust overlay network client</td></tr>
    <tr><td><code>netbird-ui</code></td><td>Desktop system tray interface for NetBird</td></tr>
    <tr><td><code>network-manager-openconnect-gnome</code></td><td>NetworkManager GUI plugin for Cisco AnyConnect / OpenConnect VPNs</td></tr>
    <tr><td><code>nmap</code></td><td>Network discovery and security auditing scanner</td></tr>
    <tr><td><code>numlockx</code></td><td>Utility to control NumLock state at X11 session startup</td></tr>
    <tr><td><code>obs-studio</code></td><td>Video recording and live streaming studio software</td></tr>
    <tr><td><code>openarena</code></td><td>Fast-paced open-source arena first-person shooter</td></tr>
    <tr><td><code>openconnect</code></td><td>Open-source SSL VPN client compatible with Cisco AnyConnect</td></tr>
    <tr><td><code>openlp</code></td><td>Church worship presentation and lyric projection software</td></tr>
    <tr><td><code>plank</code></td><td>Lightweight, clean desktop application dock</td></tr>
    <tr><td><code>playerctl</code></td><td>Command-line controller for MPRIS media players</td></tr>
    <tr><td><code>preload</code></td><td>Adaptive readahead daemon that speeds up application launch times</td></tr>
    <tr><td><code>qemu-system-x86</code></td><td>Full-system x86/x86_64 machine emulator and virtualizer</td></tr>
    <tr><td><code>remmina</code></td><td>Remote desktop client supporting RDP, VNC, SSH, and SPICE</td></tr>
    <tr><td><code>remmina-plugin-rdp</code></td><td>Remote Desktop Protocol (RDP) plugin for Remmina</td></tr>
    <tr><td><code>samba</code></td><td>SMB/CIFS file and print sharing server for Windows/Linux networks</td></tr>
    <tr><td><code>scribus</code></td><td>Open-source desktop publishing and page layout application</td></tr>
    <tr><td><code>simplescreenrecorder</code></td><td>Screen capture and desktop video recording tool</td></tr>
    <tr><td><code>solaar</code></td><td>Device manager for Logitech Unifying, Bolt, and Lightspeed receivers</td></tr>
    <tr><td><code>ssh</code></td><td>OpenSSH client and server metapackage for secure remote access</td></tr>
    <tr><td><code>steam-devices</code></td><td>udev rules for Steam Controllers, VR headsets, and gamepads</td></tr>
    <tr><td><code>steam-installer</code></td><td>Installer package for the Valve Steam gaming client</td></tr>
    <tr><td><code>sublime-merge</code></td><td>Git client and merge tool from the makers of Sublime Text</td></tr>
    <tr><td><code>sublime-text</code></td><td>Fast, extensible code and text editor</td></tr>
    <tr><td><code>tlp</code></td><td>Automated laptop power management and battery optimization daemon</td></tr>
    <tr><td><code>tlp-rdw</code></td><td>TLP Radio Device Wizard for automatic Wi-Fi/Bluetooth switching</td></tr>
    <tr><td><code>traceroute</code></td><td>Network diagnostic tool for tracing packet routes</td></tr>
    <tr><td><code>ttf-mscorefonts-installer</code></td><td>Installer for core Microsoft TrueType web fonts</td></tr>
    <tr><td><code>ubuntu-restricted-extras</code></td><td>Common multimedia codecs, MP3/DVD playback support, and fonts</td></tr>
    <tr><td><code>ulauncher</code></td><td>Keyboard-driven application launcher for Linux</td></tr>
    <tr><td><code>variety</code></td><td>Automatic desktop wallpaper changer and downloader</td></tr>
    <tr><td><code>virt-manager</code></td><td>Desktop GUI for managing libvirt/KVM virtual machines</td></tr>
    <tr><td><code>vlc</code></td><td>Cross-platform multimedia player supporting virtually all formats</td></tr>
    <tr><td><code>wget</code></td><td>Non-interactive command-line network file downloader</td></tr>
    <tr><td><code>wgtunnel</code></td><td>WireGuard tunnel management client with auto-tunneling support</td></tr>
    <tr><td><code>wine</code></td><td>Compatibility layer for running Windows applications on Linux</td></tr>
    <tr><td><code>wireguard</code></td><td>Fast, modern kernel-space VPN metapackage</td></tr>
    <tr><td><code>wireguard-tools</code></td><td>Command-line utilities (<code>wg</code>, <code>wg-quick</code>) for WireGuard</td></tr>
    <tr><td><code>x11-utils</code></td><td>X11 diagnostic and window inspection utilities (<code>xprop</code>, <code>xwininfo</code>)</td></tr>
    <tr><td><code>xrdp</code></td><td>Open-source Remote Desktop Protocol (RDP) server for Linux</td></tr>
  </tbody>
</table>
</details>

<br>

<details>
<summary><strong>Direct-Install Applications &amp; Binaries (<code>install_direct.sh</code> — 6 apps)</strong></summary>
<br>
<table>
  <thead>
    <tr>
      <th>Application</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Brave Browser</strong></td>
      <td>Privacy-focused Chromium web browser with built-in ad and tracker blocking</td>
    </tr>
    <tr>
      <td><strong>Deb-get</strong></td>
      <td><code>apt-get</code> style CLI utility for installing and updating 3rd-party vendor <code>.deb</code> packages</td>
    </tr>
    <tr>
      <td><strong>Input Remapper</strong></td>
      <td>GUI tool to remap keyboard, mouse, and gamepad buttons and macros (installed from latest GitHub <code>.deb</code>)</td>
    </tr>
    <tr>
      <td><strong>Joplin</strong></td>
      <td>Open-source Markdown note-taking and to-do application with sync support</td>
    </tr>
    <tr>
      <td><strong>OpenAudible</strong></td>
      <td>Cross-platform desktop manager for downloading and converting Audible audiobooks</td>
    </tr>
    <tr>
      <td><strong>OuDedetai</strong></td>
      <td>FaithLife Logos Bible Software Linux installer &amp; Wine manager (saved to <code>~/Apps/oudedetai</code>)</td>
    </tr>
  </tbody>
</table>
</details>

<br>

<details>
<summary><strong>Flatpak Applications (<code>install_flatpak.sh</code> — 23 apps)</strong></summary>
<br>
<table>
  <thead>
    <tr>
      <th>Application</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td><strong>Angry IP Scanner</strong></td><td>Fast network IP address and port scanner</td></tr>
    <tr><td><strong>Bitwarden</strong></td><td>Open-source cross-platform password manager</td></tr>
    <tr><td><strong>Bottles</strong></td><td>Managed Wine prefixes for running Windows software and games</td></tr>
    <tr><td><strong>CPU-X</strong></td><td>System profiling and hardware specification viewer</td></tr>
    <tr><td><strong>Cryptomator</strong></td><td>Client-side encryption tool for cloud storage folders</td></tr>
    <tr><td><strong>Dropbox</strong></td><td>Cloud file synchronization and desktop storage client</td></tr>
    <tr><td><strong>Emoji Mart</strong></td><td>Searchable desktop emoji picker utility</td></tr>
    <tr><td><strong>Flameshot</strong></td><td>Feature-rich screenshot capture and annotation tool</td></tr>
    <tr><td><strong>Gear Lever</strong></td><td>Desktop manager for organizing and integrating AppImages</td></tr>
    <tr><td><strong>Google Earth Pro</strong></td><td>3D globe, satellite imagery, and geographic mapping suite</td></tr>
    <tr><td><strong>Heroic Games Launcher</strong></td><td>Open-source launcher for Epic Games, GOG, and Amazon Prime Gaming</td></tr>
    <tr><td><strong>Input Leap</strong></td><td>Software KVM switch for sharing one keyboard and mouse across multiple PCs</td></tr>
    <tr><td><strong>Jellyfin Desktop</strong></td><td>Native desktop media player client for Jellyfin servers</td></tr>
    <tr><td><strong>Kdenlive</strong></td><td>Non-linear multi-track video editor</td></tr>
    <tr><td><strong>LocalSend</strong></td><td>Cross-platform local network file sharing over Wi-Fi/LAN</td></tr>
    <tr><td><strong>Minecraft</strong></td><td>Official Minecraft Java &amp; Bedrock launcher</td></tr>
    <tr><td><strong>OTPClient</strong></td><td>GTK+ two-factor authentication (TOTP/HOTP) token manager</td></tr>
    <tr><td><strong>Pika Backup</strong></td><td>Simple BorgBackup-powered scheduled folder backup tool</td></tr>
    <tr><td><strong>PrusaSlicer</strong></td><td>3D printing G-code generator and model slicer</td></tr>
    <tr><td><strong>Resources</strong></td><td>Modern system resource and process monitor</td></tr>
    <tr><td><strong>Signal</strong></td><td>End-to-end encrypted desktop messaging client</td></tr>
    <tr><td><strong>Warehouse</strong></td><td>Graphical manager for Flatpak apps, remotes, and user data</td></tr>
    <tr><td><strong>Wireshark</strong></td><td>Deep packet inspection and network protocol analyzer</td></tr>
  </tbody>
</table>
</details>

<br>

<details>
<summary><strong>AppImage Applications (<code>install_appimage.sh</code> — 1 app)</strong></summary>
<br>
<table>
  <thead>
    <tr>
      <th>Application</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Scrcpy GUI</strong></td>
      <td>Graphical interface for <code>scrcpy</code> Android screen mirroring and device control (saved to <code>~/Apps</code>)</td>
    </tr>
  </tbody>
</table>
</details>

</details>

<hr>

<details open>
<summary><h2>🚀 Usage &amp; Customization</h2></summary>

<h3>Prerequisites</h3>
<p><strong>None on Linux Mint.</strong> Python 3, PyGObject GTK3 bindings (<code>python3-gi</code>, <code>gir1.2-gtk-3.0</code>), <code>sudo</code>, <code>curl</code>, and <code>wget</code> are all pre-installed out of the box.</p>

<h3>Launch the Orchestrator</h3>
<pre><code>chmod +x install_python.py
./install_python.py</code></pre>

<h3>Customizing Scripts or Software Lists</h3>
<table>
  <thead>
    <tr>
      <th>Goal</th>
      <th>Where to Edit</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Reorder, add, or remove setup stages</td>
      <td><code>SCRIPT_MANIFEST</code> at the top of <code>install_python.py</code></td>
    </tr>
    <tr>
      <td>Add or remove 3rd-party PPAs / APT repos</td>
      <td><code>REPOS</code> inside <code>scripts/repo_add.sh</code></td>
    </tr>
    <tr>
      <td>Add or remove native <code>.deb</code> packages</td>
      <td><code>PACKAGE_MANIFEST</code> inside <code>scripts/install_deb.sh</code></td>
    </tr>
    <tr>
      <td>Add or remove direct-install apps / binaries</td>
      <td><code>DIRECT_MANIFEST</code> inside <code>scripts/install_direct.sh</code></td>
    </tr>
    <tr>
      <td>Add or remove Flathub Flatpaks</td>
      <td><code>FLATPAK_MANIFEST</code> inside <code>scripts/install_flatpak.sh</code></td>
    </tr>
    <tr>
      <td>Add or remove GitHub AppImages</td>
      <td><code>APPIMAGE_MANIFEST</code> inside <code>scripts/install_appimage.sh</code></td>
    </tr>
    <tr>
      <td>Add or remove SMB shares (<code>david</code>, <code>isos</code>, <code>roms</code>, <code>HOUSESHARE</code>, <code>shield</code>, <code>prusa</code>, <code>eveleighpro</code>, <code>data</code>; <code>media</code> and <code>downloads</code> removed; Nemo bookmarks enabled without start menu shortcuts)</td>
      <td><code>ALL_SHARES</code> inside <code>scripts/remote_smb.sh</code></td>
    </tr>
  </tbody>
</table>

</details>

<hr>

<details open>
<summary><h2>❓ FAQ</h2></summary>

<details>
<summary><strong>Can I run an individual helper script standalone without <code>install_python.py</code>?</strong></summary>
<p>Yes. Every script inside <code>scripts/</code> is self-contained, checks for required dependencies (such as <code>curl</code>, <code>wget</code>, or <code>flatpak</code>), and launches its own native GTK3 selection dialog when run directly (for example, <code>./scripts/install_deb.sh</code>).</p>
</details>

<br>

<details>
<summary><strong>What happens if I click "Skip / Cancel" inside one of the sub-script popups?</strong></summary>
<p>Each interactive helper script exits with status code <code>99</code> when cancelled. <code>install_python.py</code> recognizes exit code <code>99</code> as <code>SKIPPED</code> rather than a failure and moves cleanly to the next selected script in the queue.</p>
</details>

<br>

<details>
<summary><strong>Is it safe to re-run the installer on a system that already has some packages installed?</strong></summary>
<p>Yes. <code>install_deb.sh</code> compares installed package versions against candidate APT versions using <code>dpkg --compare-versions</code> and skips up-to-date packages, <code>install_flatpak.sh</code> skips already-installed Flathub IDs, and <code>repo_add.sh</code> overwrites keyrings/source files idempotently.</p>
</details>

<br>

<details>
<summary><strong>How are my <code>sudo</code> credentials handled during and after a run?</strong></summary>
<p>Your password is validated via <code>sudo -S -v</code>, forwarded to worker scripts via <code>RUNNER_SUDO_PASS</code> alongside a generated <code>SUDO_ASKPASS</code> (<code>askpass.sh</code>) helper for GUI fallback prompts, refreshed every 45 seconds by a background keep-alive thread, and cleared from memory with <code>sudo -k</code> executed in a <code>finally:</code> block when the run finishes, is cancelled, or the window closes.</p>
</details>

<br>

<details>
<summary><strong>What does the Dry Run option do?</strong></summary>
<p>Checking <strong>Dry Run (simulate without making changes)</strong> skips the <code>sudo</code> password prompt and simulates each selected script in the queue—logging the target script path, working directory, and executable check (<code>DRY RUN</code> status) to the live console and run report without modifying your system.</p>
</details>

<br>

<details>
<summary><strong>Where are logs stored, and how many are kept?</strong></summary>
<p>All run logs are stored in <code>~/.install_logs/</code> named <code>YYYYMMDD-HHMMSS_scripts_run.log</code>. The orchestrator automatically deletes older log files so that at most the <strong>5 most recent runs</strong> are retained on disk.</p>
</details>

</details>

<hr>

<details open>
<summary><h2>🩺 Troubleshooting</h2></summary>

<table>
  <thead>
    <tr>
      <th>Symptom / Issue</th>
      <th>Cause &amp; Resolution</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>"Missing Scripts Detected" warning at launch</strong></td>
      <td>A filename listed in <code>SCRIPT_MANIFEST</code> does not exist inside <code>./scripts/</code>. Either add the missing script to <code>./scripts/</code> or comment out its line in <code>install_python.py</code>.</td>
    </tr>
    <tr>
      <td><strong><code>apt-get</code> fails with <code>Could not get lock /var/lib/dpkg/lock-frontend</code></strong></td>
      <td>Linux Mint's Update Manager (<code>mintupdate</code>) or unattended-upgrades is running in the background. Wait for it to finish, then click <strong>Back to Selection</strong> and re-run the failed script.</td>
    </tr>
    <tr>
      <td><strong><code>ttf-mscorefonts-installer</code> hangs or fails during <code>install_deb.sh</code></strong></td>
      <td>SourceForge mirror timeouts can stall the EULA font download. Re-run <code>install_deb.sh</code> (which retries up to 3 times) or run <code>sudo dpkg --configure -a</code> in a terminal.</td>
    </tr>
    <tr>
      <td><strong>GitHub release download fails in <code>install_direct.sh</code> or <code>install_appimage.sh</code></strong></td>
      <td>Temporary network drop or GitHub rate-limiting on unauthenticated release page scraping. Wait a minute and re-run just that script from the checklist.</td>
    </tr>
    <tr>
      <td><strong>Newly installed AppImage or <code>OuDedetai</code> doesn't appear in the Cinnamon menu right away</strong></td>
      <td>Cinnamon caches <code>.desktop</code> entries briefly. Press <code>Ctrl+Alt+Esc</code> to restart Cinnamon or log out and back in to refresh the application menu.</td>
    </tr>
    <tr>
      <td><strong><code>Permission denied</code> when launching <code>./install_python.py</code></strong></td>
      <td>Run <code>chmod +x install_python.py</code> once before executing. (Scripts inside <code>./scripts/</code> are marked executable automatically by the runner.)</td>
    </tr>
  </tbody>
</table>

</details>
