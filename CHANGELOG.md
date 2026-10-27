# Changelog

Notable changes per release. Full notes, install commands and credits on [GitHub releases](https://github.com/b0bbywan/odios/releases).

## [2026.10.0b3](https://github.com/b0bbywan/odios/releases/tag/2026.10.0b3) - 2026-10-25

Security release, background in the [October 2026 security note](https://github.com/b0bbywan/odios/discussions/104).

- Security: the local screen distrusts eMudhra's compromised CAs (CVE-2026-111943, odio-kiosk 2.0.1)
- Security: arm64 SD images get Raspberry Pi kernel and firmware updates through unattended-upgrades
- upmpdcli served from apt.odio.love: installs and upgrades work again while lesbonscomptes.com is down (#105)
- `mpd-discplayer --eject` for drives without an eject button (#98)
- USB drives plugged in before boot are mounted and indexed at startup (#98)
- CD cache (`.disc-cuer`) hidden from the MPD library (#98, #103)
- Fixed: USB drive lost after a reboot with `MountConfig: mpd` (#98)
- Fixed: features recorded as installed while their parent component wasn't
- Updates: odio-kiosk 2.0.1, go-mpd-discplayer 0.9.0, upmpdcli 1.9.17

## [2026.10.0b2](https://github.com/b0bbywan/odios/releases/tag/2026.10.0b2) - 2026-10-18

- Physical remotes: IR receivers, GPIO buttons, HDMI-CEC, Bluetooth and USB remotes drive playback and volume (#99)
- Faster boot on single-core boards: on a Pi B+, session up in 1min10 (was 1min34), MPD in 52s (was 85s) (#101)
- Snapcast: MPRIS playback position and seek
- Settings page: Audio HAT section, **Reset** gives the Pi's own audio back
- Quieter Snapcast and Qobuz Connect logs (#97)
- Fixed: HATs with an EEPROM (HiFiBerry, IQaudIO...) loaded twice
- Fixed: odio-api failing to start at boot when the network or audio server wasn't ready
- SD images based on Raspberry Pi OS 2026-10-06
- Updates: odioctl 0.4.1, odio-api 0.18.1, snapclientmpris 1.3.0

## [2026.10.0b1](https://github.com/b0bbywan/odios/releases/tag/2026.10.0b1) - 2026-10-05

- Disabling a component now stops its services and undoes its hooks on the next **Apply** (packages and config are kept)
- Settings page moved into the odio web UI (`:8018/ui/admin/`), port 8021 closed
- PipeWire audio server, experimental: `AUDIOSERVER=pipewire` at install
- Attached screen runs odio-kiosk (Qt 6 / Chromium 122) as `odio-kiosk@odio.service`, migrated on upgrade
- Components catalog: labels and descriptions, required components can't be disabled
- Shairport Sync on the session bus, now shown in the dashboard (#91)
- Login banner is now `odioctl motd` (faster)
- Fixed: a re-enabled component could stay stopped
- Fixed: a failed upgrade was recorded as done
- Upgrade note: components disabled before this release keep running; enable, apply, disable, apply to stop them
- Updates: odioctl 0.4.0, odio-api 0.17.4, odio-kiosk 2.0.0, myMPD 26.0.0

## [2026.9.0b2](https://github.com/b0bbywan/odios/releases/tag/2026.9.0b2) - 2026-09-18

- Display on an attached screen (fbrowser-kiosk), optional, amd64 and arm64, experimental
- Each release publishes its components catalog: new components reach the settings page without an odioctl upgrade
- Qobuz sign-in from the settings page
- Fixed: odio UI rendering on the local screen's older Chromium
- Fixed: running services shown as stopped when started alongside odio-api
- Updates: odioctl 0.3.1, odio-api 0.17.3, qbzd 2.1.2

## [2026.9.0b1](https://github.com/b0bbywan/odios/releases/tag/2026.9.0b1) - 2026-09-10

- Settings page (port 8021): add components, pick the DAC overlay, reboot
- Qobuz Connect (qbzd), optional, experimental
- Qobuz and Tidal sign-in from the settings page, no more SSH
- Components can be added after install
- `odioctl` replaces `odio-upgrade` (`odioctl upgrade apply`, `components`, `dac`)
- Fixed: volume slider on Bluetooth sources
- Fixed: Tidal not showing up after install
- Fixed: Kodi missing from the player list
- Fixed: a paused and muted app could not be unmuted
- Updates: odioctl 0.2.2, odio-api 0.17.1, qbzd 2.1.0

## [2026.7.0rc2](https://github.com/b0bbywan/odios/releases/tag/2026.7.0rc2) - 2026-07-24

Supersedes 2026.7.0rc1, whose upgrade failed in the mpd role.

- Tracklist end to end: MPRIS `TrackList` in mpd2mpris, odio-api endpoints and SSE event
- Tracklist view in the UI: jump to a track, remove tracks, fullscreen covers
- mpDris2 fork renamed mpd2mpris (`mpd2mpris.service`)
- Fixed: `mpd2mpris.service` failing to enable on upgrade. If rc1 already failed, reboot or run `systemctl --user daemon-reload` first
- Updates: mpd2mpris 0.13.0, odio-api 0.16.1, mpd-discplayer 0.8.0

## [2026.6.0b2](https://github.com/b0bbywan/odios/releases/tag/2026.6.0b2) - 2026-06-24

- Upgrade from the odio UI or Home Assistant (odio-api 0.15.1)
- Upgrade progress streamed over odio-api's unix socket, with the failure cause on error
- `odio-upgrade --progress` turned on automatically when odio-api is present
- Fixed: missing user `daemon-reload` after installing user units on upgrade

## [2026.6.0b1](https://github.com/b0bbywan/odios/releases/tag/2026.6.0b1) - 2026-06-13

- Bluetooth audio output: scan, connect, dashboard section (odio-api 0.14.0)
- Remote cover art: MusicBrainz, iTunes, Deezer, Radio Browser, WebradioDB (mpDris2 0.11.0)
- `odio-upgrade --progress` and `--reinstall`
- Faster upgrades: only changed components re-run, first-install steps skipped, faster apt on SD cards
- Fixed: user unit files chowned through the image-mode symlink

## [2026.5.0b3](https://github.com/b0bbywan/odios/releases/tag/2026.5.0b3) - 2026-05-25

- odio-api 0.13.0: HTMX transport controls, collapsible player cards, PWA promo, MPRIS fixes
- mpDris2 0.10.0: asyncio rewrite, no polling, D-Bus activated
- snapclientmpris 1.2.0: MPRIS bridge for the Snapcast client
- mpd: optional user-provided config drop-in
- myMPD home shortcuts (Webradio, Artists, Albums, Odio)
- Fixed: timers and sockets installed in the right systemd target folder

## [2026.5.0b2](https://github.com/b0bbywan/odios/releases/tag/2026.5.0b2) - 2026-05-14

Includes 2026.5.0b1, whose fresh installs failed (#58).

- Smart upgrade: `odio-upgrade {check, apply, verify}`, only components whose version changed re-run
- `state.json` moved to `/var/lib/odio/state.json`
- Downgrade guard: `apply` refuses an older release
- Upgrades can be run by a sudoer in the `odio` group
- odio-api 0.12.0: drop-in configs in `~/.config/odio-api/conf.d/`
- Fixed: myMPD, Tidal, Qobuz and web radios follow their parent component's choice
- Fixed: odio-api and mpd require a minimum version instead of an exact one (#58)

## [2026.4.2b2](https://github.com/b0bbywan/odios/releases/tag/2026.4.2b2) - 2026-04-29

- myMPD web UI, optional, odio-themed, with WebradioDB web radios
- SD images auto-apply Debian security updates
- Optional components default to yes in install prompts
- `state.json` keeps the history of installed releases
- mpDris2 installed from apt.odio.love
- Fixed: missing `tidalapi` for upmpdcli Tidal

## [2026.4.2b1](https://github.com/b0bbywan/odios/releases/tag/2026.4.2b1) - 2026-04-27

- In-place upgrades: `odio-upgrade` helper and `upgrade` role
- Post-install health check
- Login banner opt-in via `install_branding`
- apt.odio.love packages kept up to date on re-runs
- Fixed: `pulse-tcp` hardening, missing `acl` package, graphical session detection in image mode

## [2026.4.1rc2](https://github.com/b0bbywan/odios/releases/tag/2026.4.1rc2) - 2026-04-21

- Login banner opt-in (`install_motd`, off by default)
- Fixed: version comparison for untagged builds in the upgrade checker
- Fixed: upgrade state refreshed at the end of install

## [2026.4.1rc1](https://github.com/b0bbywan/odios/releases/tag/2026.4.1rc1) - 2026-04-18

- Web radios through upmpdcli plugins, thanks to @pbattino, first external contributor
- Login banner showing available component updates
- `manifest.json` published with each release
- Pre-built images stamped with their version
- Fixed: shairport-sync config is idempotent

## [2026.4.0rc7](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc7) - 2026-04-13

- Config backups for mpd-discplayer, odio-api and spotifyd before updates
- PulseAudio TCP disabled over Wi-Fi (odio failed to start on wireless); AirPlay and Snapcast unaffected
- Fixed: redundant pulse address in local setups, missing cloud-init group

## [2026.4.0rc6](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc6) - 2026-04-07

- Project renamed `odio`
- mpd uses the b0bbywan/mpDris2 fork
- Fixed: polkit rules directory permissions

## [2026.4.0rc5](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc5) - 2026-04-05

- Fixed: snapclient player set in the unit file

## [2026.4.0rc4](https://github.com/b0bbywan/odios/releases/tag/2024.4.0rc4) - 2026-04-04

Tagged `2024.4.0rc4` by mistake.

- shairport-sync config moved to the user config directory
- Fixed: missing `pi-bluetooth` on Raspberry Pi 3 armhf

## [2026.4.0rc3](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc3) - 2026-04-04

- Pre-built Raspberry Pi images, built by CI on every release
- Persistent systemd journal
- Fixed: image-mode installs (unit symlinks, user systemd folders, polkit and udev rules)

## [2026.4.0rc2](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc2) - 2026-04-01

- Fixed: polkit rule for udisks mounts from mpd

## [2026.4.0rc1](https://github.com/b0bbywan/odios/releases/tag/2026.4.0rc1) - 2026-03-31

- mpDris2 auto-restarts and depends on `mpd.service`
- Fixed: services started by handlers only

## [2026.3.0b8](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b8) - 2026-03-28

- Fixed: shairport-sync D-Bus config reload

## [2026.3.0b7](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b7) - 2026-03-28

- mpDris2 enabled by default
- Fixed: odio-api `CanPowerOff` capability

## [2026.3.0b6](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b6) - 2026-03-23

- spotifyd installed from apt.odio.love
- Bluetooth rfkill and polkit rules on headless systems only

## [2026.3.0b5](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b5) - 2026-03-20

- Fixed: upmpdcli defaults

## [2026.3.0b4](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b4) - 2026-03-20

- Installer asks for the sudo password when needed, new default answers
- Fixed: odio-api restarts with full state, rfkill in the base install

## [2026.3.0b3](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b3) - 2026-03-19

- Bluetooth radios unblocked with rfkill
- Packages installed without recommends
- Fixed: mpd config, PipeWire conflict detection

## [2026.3.0b2](https://github.com/b0bbywan/odios/releases/tag/2026.3.0.b2) - 2026-03-19

Tagged `2026.3.0.b2` by mistake.

- Config for odio-api 0.9.1

## [2026.3.0b1](https://github.com/b0bbywan/odios/releases/tag/2026.3.0b1) - 2026-03-18

First beta.

- Fixed: odio-api power capability, YAML config formatting, snapclient unit, installer name

## [2026.3.0a6](https://github.com/b0bbywan/odios/releases/tag/2026.3.0a6) - 2026-03-18

- Fixed: PipeWire user services stopped before masking, Python interpreter pinned

## [2026.3.0a5](https://github.com/b0bbywan/odios/releases/tag/2026.3.0a5) - 2026-03-18

- `python3-cryptography` installed automatically
- Fixed: no `apt-get -y` in interactive mode, `curl | bash` path

## [2026.3.0a4](https://github.com/b0bbywan/odios/releases/tag/2026.3.0a4) - 2026-03-17

- Spotify Connect (spotifyd)
- PipeWire role, experimental
- More streaming services in upmpdcli, now a user service
- gnudb account for mpd-discplayer
- ARM testing via QEMU, `image_build` mode
- Fixed: `root` refused as target user, coexistence with a pre-installed PipeWire

## [2026.3.0a3](https://github.com/b0bbywan/odios/releases/tag/2026.3.0a3) - 2026-03-09

- Fixed: missing user groups (audio, bluetooth...)

## [2026.3.0a2](https://github.com/b0bbywan/odios/releases/tag/2026.3.0a2) - 2026-03-09

First public alpha.

- MPD with CD and USB auto-play (go-mpd-discplayer)
- PulseAudio as a network audio server
- Bluetooth A2DP sink, AirPlay (Shairport Sync), Snapcast client, UPnP/DLNA (upmpdcli)
- go-odio-api REST API and web UI, Home Assistant integration
- Services run as systemd user services
