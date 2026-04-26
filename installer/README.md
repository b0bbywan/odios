# Audio Streaming System Installer

Ansible-based "curl | bash" installer to set up a complete audio/multimedia system on Debian/Ubuntu.

## Components

### Core (enabled by default, can be disabled)
- **PulseAudio** - Audio server with network streaming (TCP + Zeroconf, wired only)
- **Bluetooth Audio** - Authentication agent and automatic connection
- **MPD** - Music Player Daemon with USB, CD/DVD and network support
- **Odio API** - REST control interface

### Optional (disabled by default)
- **Shairport Sync** - AirPlay receiver
- **Snapcast** - Multi-room audio client
- **myMPD** - Web UI for MPD (default port 8080)
- **UPnP/DLNA** - Renderer for UPnP application control, with optional Qobuz and Tidal support (packages only — credentials are configured manually post-install in `~/.config/upmpdcli/upmpdcli.conf`).
- **MPD DiscPlayer** - CD/USB support for MPD

## Fresh install vs existing system

The installer is fully idempotent — it can be run on a fresh system or an existing one, and re-run safely at any time to update or repair the installation.

### Existing system — user recommendation

If you are installing on a system that already has a configured user, it is strongly recommended to target a **dedicated user** for odios. The playbook creates it automatically if it doesn't exist — the installer will confirm this at startup:

```
Target user [pi]: odio
✓ User 'odio' will be created.
```

If you install for an existing user, the installer warns you upfront:

```
Target user [pi]:
⚠ Installing for current user 'pi' — existing config files will be backed up before modification.
```

### Config file handling

When the installer modifies a configuration file that already exists, it **automatically creates a backup** before applying changes:

- If the file is modified: a backup is saved as `<config>.bak` (e.g. `/etc/shairport-sync.conf.bak`)
- If the file ends up identical: no backup is kept

This applies to: `/etc/bluetooth/main.conf`, `/etc/shairport-sync.conf`, `/etc/default/snapclient`, `~/.config/upmpdcli/upmpdcli.conf`, and `~/.config/mpd/mpd.conf` (modified by both the `mpd` and `mpd_discplayer` roles).

## Requirements

- OS: Debian 13, Ubuntu 22.04+, or Raspberry Pi OS (Trixie)
- Architecture: ARM (armv6l, armv7l, aarch64) or x86_64
- Python 3.10+
- `python3-cryptography` (present by default on Debian/Ubuntu)
- `python3-jinja`
- `curl`
- Sudo access (or root)
- Internet connection
- 50 MB free disk space in `/tmp`

## Installation

### Current user (with sudo)

```bash
curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/install.sh | bash
```

The installer interactively prompts for the target user and optional components.

### As root for a specific user

```bash
TARGET_USER=pi curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/install.sh | sudo bash
```

### Non-interactive (automation)

All configuration variables can be passed as environment variables — if set, prompts are skipped:

```bash
TARGET_USER=pi \
INSTALL_SHAIRPORT_SYNC=y \
INSTALL_SNAPCLIENT=y \
INSTALL_UPMPDCLI=y \
INSTALL_MPD_DISCPLAYER=y \
curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/install.sh | bash
```

| Variable                 | Default       | Description                          |
|--------------------------|---------------|--------------------------------------|
| `TARGET_USER`            | `$USER`       | System user for the services         |
| `TARGET_HOSTNAME`        | *(unchanged)* | Hostname (optional)                  |
| `MPD_MUSIC_DIRECTORY`    | `/media/USB`  | MPD music library path               |
| `MPD_CONF_PATH`          | *(detected)*  | Path to external mpd.conf (when `INSTALL_MPD=n` + `INSTALL_MPD_DISCPLAYER=y`) ⚠ experimental |
| `INSTALL_PULSEAUDIO`     | `Y`           | PulseAudio + network streaming (wired only) |
| `INSTALL_BLUETOOTH`      | `Y`           | Bluetooth A2DP sink                  |
| `INSTALL_MPD`            | `Y`           | Music Player Daemon                  |
| `INSTALL_ODIO_API`       | `Y`           | REST control API                     |
| `INSTALL_SHAIRPORT_SYNC` | `N`           | AirPlay receiver                     |
| `INSTALL_SNAPCLIENT`     | `N`           | Snapcast client                      |
| `INSTALL_UPMPDCLI`       | `N`           | UPnP/DLNA renderer                   |
| `INSTALL_MYMPD`          | `N`           | myMPD web UI                         |
| `INSTALL_MPD_DISCPLAYER` | `N`           | CD/DVD support                       |
| `INSTALL_SPOTIFYD`       | `N`           | Spotify Connect                      |
| `INSTALL_QOBUZ`          | `N`           | upmpdcli Qobuz plugin (credentials: manual, see `upmpdcli.conf`) |
| `INSTALL_TIDAL`          | `N`           | upmpdcli Tidal plugin (credentials: manual, see `upmpdcli.conf`) |
| `INSTALL_UPNPWEBRADIOS`  | `N`           | upmpdcli web radio plugins (Radio Browser, Radio Paradise, …) |
| `INSTALL_BRANDING`       | `N`           | odio login banner (`odio-motd`, `.hushlogin`) |
| `ODIOS_VERSION`          | `latest`      | Version to install (`pr-2`, `2026.3.0`, …) |

### Specific version or pre-release

Releases follow the `YYYY.M.patch` format (e.g. `2026.3.0`). Pre-releases use suffixes: `2026.3.0a1` (alpha), `2026.3.0b1` (beta), `2026.3.0rc1` (release candidate).

```bash
# Stable version
ODIOS_VERSION=2026.3.0 curl -fsSL https://github.com/b0bbywan/odios/releases/download/2026.3.0/install.sh | bash

# Beta
ODIOS_VERSION=2026.3.0b1 curl -fsSL https://github.com/b0bbywan/odios/releases/download/2026.3.0b1/install.sh | bash

# PR pre-release
ODIOS_VERSION=pr-5 curl -fsSL https://github.com/b0bbywan/odios/releases/download/pr-5/install.sh | bash
```

## Upgrading

Each install ships two helpers in `/usr/local/bin`:

- **`odio-check-upgrade`** — compares the local state against the published manifest and refreshes `/var/cache/odio/upgrades.json`. Wired to a systemd user timer (daily, random delay) so the login banner / PWA can surface the result.
- **`odio-upgrade`** — re-invokes `install.sh` for the target version with the `INSTALL_*` flags derived from the saved state. No argument = upgrade to whatever `upgrades.json` reports as latest.

```bash
odio-upgrade                      # upgrade to the latest published version
odio-upgrade --version 2026.5.0   # target a specific release
odio-upgrade --dry-run --force    # print what would be invoked, do nothing
systemctl --user start odio-upgrade   # same, via the installed user unit (log in journalctl)
```

### Bootstrapping from a release asset

`odio-upgrade` is also published as a standalone asset on every release, so installs that predate it (≤ rc2, no helper in `/usr/local/bin`) can run it directly:

```bash
curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/odio-upgrade -o /tmp/odio-upgrade
chmod +x /tmp/odio-upgrade
/tmp/odio-upgrade                 # reconstructs state from disk, then upgrades to latest
```

The subsequent upgrade installs the helper, so this bootstrap is needed only once.

### How state is preserved

Upgrades honor the previous feature selection by reading `~/.cache/odio/state.json`:

| Field               | Meaning                                                             |
|---------------------|---------------------------------------------------------------------|
| `roles`             | Role → version of every role that was installed                     |
| `roles_excluded`    | Roles the user opted out of (kept off on upgrade)                   |
| `features`          | Opt-in sub-flags (e.g. `tidal`, `qobuz`, `upnpwebradios`)           |
| `features_excluded` | Sub-flags the user opted out of (kept off on upgrade)               |

Only entries in `roles_excluded` / `features_excluded` map to `INSTALL_*=N`. Everything else — whether listed in `roles`/`features` or absent from both (new release, schema gap, malformed state.json) — maps to `INSTALL_*=Y`. Upgrades are pure opt-out: `install.sh`'s built-in defaults don't apply, only the explicit exclusions do.

`odio-upgrade` transparently backfills the newer fields for installs that predate them (rc1/rc2 state, or pre-rc3 installs with no state at all), using filesystem / dpkg introspection. Run with `--dry-run` to inspect.

### Opting out before upgrade

To keep a role or sub-flag off on the next upgrade, open `~/.cache/odio/state.json` in your editor and add its name to the matching `_excluded` list. Example — skipping the `branding` role and `upnpwebradios` feature:

```diff
 {
   ...
   "roles_excluded": [
-
+    "branding"
   ],
   "features_excluded": [
-
+    "upnpwebradios"
   ]
 }
```

Then:

```bash
odio-upgrade --dry-run --force   # verify the derived INSTALL_* flags
odio-upgrade                      # apply
```

Removing an entry from the list opts back in — the next upgrade sees it as unlisted and re-installs it.

## Architecture

### How it works

1. `install.sh` is downloaded and executed (`curl | bash`)
2. It checks prerequisites (OS, arch, Python 3.10+, cryptography, curl, sudo, disk space, systemd)
3. It downloads the release archive from GitHub into `/tmp`
4. It runs **vendored** ansible-core from the archive (no Ansible installation required)
5. The playbook configures the system and starts the services
6. Temporary files are cleaned up

### Release archive

The archive (`odio-{version}.tar.gz`) contains:

```
ansible/        — playbooks and roles
vendor/         — vendored ansible-core (pure Python, no native extensions)
licenses/       — licenses (GPLv3 ansible-core, BSD-2 odios)
VERSION
```

`python3-cryptography` is the only native dependency not included — it is provided by the system.

### Project structure

```
installer/
├── install.sh                   # curl|bash entry point (published as-is)
└── ansible/
    ├── playbook.yml             # Main playbook
    ├── inventory/localhost.yml
    ├── group_vars/all.yml       # Default variables
    ├── tasks/
    │   ├── backup_conf_before.yml      # Shared: snapshot config before changes
    │   ├── backup_conf_after.yml       # Shared: promote/discard backup after changes
    │   ├── systemd_enable_user.yml     # Shared: enable a user service (live + image_build)
    │   ├── systemd_disable_system.yml  # Shared: disable + stop a system service
    │   └── systemd_enable_system.yml   # Shared: enable + start a system service
    └── roles/
        ├── common/              # System prerequisites + linger
        ├── pulseaudio/          # PulseAudio + network streaming (wired only, PipeWire conflict handling)
        ├── pipewire/            # PipeWire + pipewire-pulse (experimental, not yet exposed)
        ├── bluetooth/           # Bluetooth audio (A2DP)
        ├── mpd/                 # Music Player Daemon
        ├── odio_api/            # REST control API
        ├── shairport_sync/      # AirPlay (optional)
        ├── snapclient/          # Snapcast (optional)
        ├── upmpdcli/            # UPnP/DLNA (optional)
        ├── mympd/               # myMPD web UI (optional)
        ├── mpd_discplayer/      # CD/DVD player (optional)
        │   └── tasks/
        │       └── validate_external_mpd.yml  # Fail-fast validation for external MPD
        └── spotifyd/            # Spotify Connect (optional, disabled)
```

## Using mpd_discplayer with an existing MPD ⚠ experimental

By default, `mpd_discplayer` is designed to work alongside MPD managed by odios. It is also possible to install it against a pre-existing MPD installation (`INSTALL_MPD=n` + `INSTALL_MPD_DISCPLAYER=y`), but this mode is **experimental**.

In this case the installer will:
1. Auto-detect your `mpd.conf` (`~/.config/mpd/mpd.conf` then `/etc/mpd.conf`), or use `MPD_CONF_PATH` if provided
2. Extract `music_directory` from it to configure `mpd-discplayer`
3. Append the required blocks (`cdio_paranoia`, `playlist_plugin`, `neighbors`) to your existing config — your original file is backed up as `mpd.conf.bak` beforehand

**Requirements for external MPD:**
- Must use the `database { plugin "simple" }` block format — legacy `db_file` directive is not supported and will cause a fail-fast error with a migration guide

This mode has not been extensively tested across MPD configurations. Feedback welcome.

## Testing

### Run the playbook directly

```bash
./tests/test.sh               # pull image from GHCR + run playbook (ansible installed via pip)
./tests/test.sh rerun         # re-run playbook without restarting the container
./tests/test.sh shell         # shell into the container
./tests/test.sh clean         # remove the container
./tests/test.sh --build       # force local image build instead of pulling from GHCR
```

### Full curl|bash installer test

Tests `install.sh` from a GitHub release inside a systemd container:

```bash
# As user odio (sudo) — standard user case
./tests/test.sh install pr-5

# As root with TARGET_USER=odio — system installation case
./tests/test.sh install-root pr-5

# Against the latest stable release
./tests/test.sh install latest
```

The `--build` flag works with all actions:

```bash
./tests/test.sh --build install pr-5
```

### Service verification

```bash
systemctl --user status pulseaudio pulse-tcp mpd

pactl list modules | grep -E "tcp|zeroconf"

mpc status
```

### Upgrade testing (CI)

The `test-upgrade` job in `release.yml` validates that an existing odios install can be upgraded to the PR's version via `curl | bash`. To match the real-world semantic (an odios system is already running on a Pi when the user upgrades), the test uses a **pre-provisioned baseline Docker image** built from a published SD-card `.img.xz` — not a fresh install of the baseline.

The baseline is tracked by the repo variable `UPGRADE_BASELINE_TAG` (Settings → Variables), default `2026.4.0rc3`. When it is bumped, the corresponding Docker image must be (re)built once and pushed to GHCR.

**Auto path (preferred, once the workflow lives on `main`):**

Actions → "Build test-baseline image" → **Run workflow**. Matrix currently builds `arm64` on a native arm64 runner. Output: `ghcr.io/b0bbywan/odios/test-baseline:<TAG>-<arch>`.

**Manual path (local build, required for the first time the feature lands on `main` and the workflow is not yet registered by GitHub):**

```bash
# Requires: docker, sudo, xz-utils, util-linux, jq
docker login ghcr.io -u <your-github-user>     # needs a PAT with write:packages

./scripts/img-to-docker.sh 2026.4.0rc3 arm64
```

The script downloads the SD image directly from the matching release, mounts its rootfs partition, tars it, and `docker import`s it with a systemd entrypoint matching `Dockerfile.test` — tagged as `ghcr.io/<repo>/test-baseline:<TAG>-<ARCH>`. Approach inspired by [vascoguita/raspios-docker](https://github.com/vascoguita/raspios-docker).

## Troubleshooting

### `python3-cryptography` not found

```bash
sudo apt install python3-cryptography
```

### Services not starting

```bash
journalctl --user -u pulseaudio -u mpd -f

systemctl --user restart pulseaudio pulse-tcp mpd
```

### "XDG_RUNTIME_DIR not set" error

```bash
loginctl show-user $USER | grep Linger
sudo loginctl enable-linger $USER
```

### MPD cannot find the music directory

When MPD is managed by odios (`INSTALL_MPD=y`), the music directory defaults to `/media/USB`. Override it with:

```bash
MPD_MUSIC_DIRECTORY=/mnt/music curl -fsSL ... | bash
```

When using an external MPD (`INSTALL_MPD=n` + `INSTALL_MPD_DISCPLAYER=y`), the path is auto-detected from your existing `mpd.conf` — no override needed.

To verify the directory exists with correct permissions:

```bash
ls -la /media/USB
# Should be: drwxrwxr-x user audio
```

## References

- [Ansible](https://docs.ansible.com/)
- [go-odio-api](https://github.com/b0bbywan/go-odio-api)
- [go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer)
- [PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/)
- [PipeWire](https://pipewire.org/)
- [MPD — Music Player Daemon](https://www.musicpd.org/doc/)
- [Shairport Sync](https://github.com/mikebrady/shairport-sync)
- [Snapcast](https://github.com/badaix/snapcast)
- [upmpdcli](https://www.lesbonscomptes.com/upmpdcli/)
- [Spotifyd](https://github.com/Spotifyd/spotifyd)
- [Project Repository](https://github.com/b0bbywan/odios)
