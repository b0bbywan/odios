  <p align="center">
    <a href="https://odio.love">
      <img src="https://odio.love/logo.png" alt="odio" width="160" /> 
    </a>   
  </p>
  <h1 align="center">odios</h1>
  <p align="center"><em>Turns a Raspberry Pi or any Debian-based Linux into a multi-source audio streamer.</em></p>
  <p align="center">
    <a href="https://github.com/b0bbywan/odios/releases"><img src="https://img.shields.io/github/v/release/b0bbywan/odios?include_prereleases" alt="Release" /></a>
    <a href="https://github.com/b0bbywan/odios/blob/main/LICENSE"><img src="https://img.shields.io/github/license/b0bbywan/odios" alt="License" /></a>   
    <a href="https://github.com/b0bbywan/odios/actions/workflows/release.yml"><img src="https://github.com/b0bbywan/odios/actions/workflows/release.yml/badge.svg" alt="Build" /></a>
    <a href="https://github.com/sponsors/b0bbywan"><img src="https://img.shields.io/github/sponsors/b0bbywan?label=Sponsor&logo=GitHub" alt="GitHub Sponsors" /></a>
  </p>
  <p align="center">
    <a href="https://docs.odio.love/guides/bluetooth/"><img src="https://img.shields.io/badge/Bluetooth-0082FC?logo=bluetooth&logoColor=white" alt="Bluetooth" /></a>
    <a href="https://docs.odio.love/guides/airplay/"><img src="https://img.shields.io/badge/AirPlay-000000?logo=apple&logoColor=white" alt="AirPlay" /></a>
    <a href="https://docs.odio.love/guides/spotify/"><img src="https://img.shields.io/badge/Spotify%20Connect-1DB954?logo=spotify&logoColor=white" alt="Spotify Connect" /></a>
    <a href="https://docs.odio.love/guides/dlna/"><img src="https://img.shields.io/badge/UPnP%20%2F%20DLNA-447799" alt="UPnP / DLNA" /></a>
    <a href="https://docs.odio.love/guides/mpd/"><img src="https://img.shields.io/badge/MPD-F18D00" alt="MPD" /></a>
    <a href="https://docs.odio.love/guides/snapcast/"><img src="https://img.shields.io/badge/Multi--room-5B21B6" alt="Multi-room" /></a>
    <a href="https://docs.odio.love/guides/tidal-qobuz/"><img src="https://img.shields.io/badge/Tidal%20%26%20Qobuz-000000" alt="Tidal &amp; Qobuz" /></a>
    <a href="https://docs.odio.love/guides/network-audio/"><img src="https://img.shields.io/badge/PulseAudio%20TCP-0055AA" alt="PulseAudio TCP" /></a>   
  </p>
  <p align="center">
    Part of the <a href="https://odio.love">odio</a> project — <a href="https://docs.odio.love/">Full documentation</a>.
  </p>
  <p align="center">                          
    <a href="https://www.debian.org/"><img src="https://img.shields.io/badge/Debian-A81D33?logo=debian&logoColor=white" alt="Debian" /></a>  
    <a href="https://go.dev/"><img src="https://img.shields.io/badge/Go-00ADD8?logo=go&logoColor=white" alt="Go" /></a>
    <a href="https://htmx.org/"><img src="https://img.shields.io/badge/htmx-3366CC?logo=htmx&logoColor=white" alt="htmx" /></a>
    <a href="https://tailwindcss.com/"><img src="https://img.shields.io/badge/Tailwind%20CSS-06B6D4?logo=tailwindcss&logoColor=white" alt="Tailwind CSS" /></a>
    <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python" /></a>
    <a href="https://www.ansible.com/"><img src="https://img.shields.io/badge/Ansible-EE0000?logo=ansible&logoColor=white" alt="Ansible" /></a>
    <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash" /></a>
    <a href="https://github.com/features/actions"><img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" /></a>
    <a href="https://svelte.dev/"><img src="https://img.shields.io/badge/Svelte-FF3E00?logo=svelte&logoColor=white" alt="Svelte" /></a>
    <a href="https://astro.build/"><img src="https://img.shields.io/badge/Astro-BC52EE?logo=astro&logoColor=white" alt="Astro" /></a>
    <a href="https://starlight.astro.build/"><img src="https://img.shields.io/badge/Starlight-7C3AED" alt="Starlight" /></a>
  </p> 

# Open-source audiophile distribution for Debian/Ubuntu and Raspberry Pi with native Home Assistant integration.

odios turns a €35 Raspberry Pi into what commercial streamers sell for €300–500: Bluetooth A2DP, AirPlay, Snapcast multi-room, UPnP/DLNA, CD playback with metadata — all in one box, controlled from a web app, no account or subscription required. Other PCs running PulseAudio or PipeWire can also stream directly to it over the network, making it a true whole-home audio sink.

Built on modern foundations: everything runs as unprivileged systemd user services (no root daemons), orchestrated through a unified REST API written in Go. Battle-tested on a Raspberry Pi B+ (armv6l) for over 6 years without reinstall.

Full Home Assistant integration included — odios nodes appear as native media players in your HA dashboard.

[![Home Assistant integration](https://my.home-assistant.io/badges/hacs_repository.svg)](https://my.home-assistant.io/redirect/hacs_repository/?owner=b0bbywan&repository=odio-ha&category=integration)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                odio-pwa (remote)                    │  ← manage multiple nodes from any device
└────────────────────────┬────────────────────────────┘
                         │ HTTP
┌────────────────────────▼────────────────────────────┐
│                    go-odio-api                      │  ← unified REST API + embedded UI
│     systemd · PulseAudio · MPRIS ·  Bluetooth       │
│                                                     │
└──────┬──────────┬──────────┬──────────┬─────────────┘
       │          │          │          │
   PulseAudio   MPD    Shairport    Snapcast
   (network)          Sync         client
   Bluetooth    MPD   (AirPlay)    upmpdcli
   (A2DP)       Disc             (UPnP/DLNA)
               Player
```

Most service run as **systemd user services** — no root daemons, full per-user isolation.

## Components

| Component | Role |
|-----------|------|
| [go-odio-api](https://github.com/b0bbywan/go-odio-api) | REST API + embedded UI, bridges systemd / PulseAudio / MPRIS / D-Bus / Bluetooth Speaker | user |
| [go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) | Automatic CD/USB playback with metadata via MPD | user |
| PulseAudio | Central audio server, routes all sources to the DAC output — other PCs running PulseAudio or PipeWire can stream to it over the network via TCP/Zeroconf (wired connections only) | user |
| MPD | Music Player Daemon (network, CD/USB) | user |
| [mpDris2](https://github.com/b0bbywan/mpDris2) (fork) | MPRIS bridge for MPD with CD cover art support | user |
| [myMPD](https://github.com/jcorporation/myMPD) | Web UI for MPD (default port 8080) | user |
| Shairport Sync | AirPlay receiver | user |
| Snapcast | Multi-room audio client | user |
| upmpdcli | UPnP/DLNA renderer | system |
| Bluetooth | A2DP sink with automatic pairing | system |

## Installation

### Raspberry Pi (pre-built image)

The fastest way to get started on a Raspberry Pi: flash a pre-built image with Raspberry Pi Imager.

1. Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Go to **Options app** > **Content Repository** > **Use custom URL**
3. Enter:
   ```
   https://github.com/b0bbywan/odios/releases/latest/download/odio.rpi-imager-manifest
   ```
4. Select your image, configure hostname/SSH/WiFi/user, and flash

See [image-builder/README.md](image-builder/README.md) for details and manual flashing options.

### Any Debian/Ubuntu system (installer)

```bash
curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/install.sh | bash
```

The installer works on both fresh and existing systems (idempotent, safe to re-run). It prompts for a target user — if the user doesn't exist it is created automatically. Installing for an existing user is supported: config files are backed up before any modification.

See [installer/README.md](installer/README.md) for full installation options, environment variables, and testing.

## Upgrading

Each release installs `odio-check-upgrade` (runs daily via a systemd user timer) and `odio-upgrade`. To apply pending upgrades:

```bash
odio-upgrade                    # upgrade to the latest version reported by odio-check-upgrade
odio-upgrade --version 2026.5.0 # upgrade to a specific version
systemctl --user start odio-upgrade   # same thing, via the installed user unit
```

`odio-upgrade` reads `/var/cache/odio/state.json` (or `~/.cache/odio/state.json` from a pre-rc3 install, or reconstructs from dpkg as a last resort) to preserve the feature selection and role opt-outs across upgrades. Run `odio-upgrade --dry-run --force` to see what would be invoked without running it.

## Recommended clients

| Client | Protocol | Platform |
|--------|----------|----------|
| [odio-pwa](https://odio-pwa.vercel.app/) | odio REST API | Any (browser) |
| [MALP](https://gitlab.com/gateship-one/malp) | MPD | Android |
| [BubbleUPnP](https://bubblesoft.org/bubbleupnp/) | UPnP/DLNA | Android / iOS |


## odio vs Volumio

|  | **odio** | **Volumio** |
|---|---|---|
| **License** | 100% open source | Partially closed source |
| **Price** | Free | Freemium — Premium at €60/year |
| **Account required** | No | Yes |
| **Cloud dependency** | None | Yes (account, Premium, plugins) |
| **Minimum hardware** | **Raspberry Pi B+** (armv6l, 2014) | Raspberry Pi 3 |
| **Music library management** | ❌ Streamer only: use your favorite app | ✅ Built-in library browser |
| **Bluetooth A2DP** | ✅ Included | 💰 Premium only |
| **AirPlay** | ✅ Included | ✅ Free plugin |
| **Spotify Connect** | ✅ Included | ✅ Free plugin |
| **Qobuz** | ✅ Included (via upmpdcli) | 💰 Premium only |
| **Tidal / Tidal Connect** | ✅ Included (via upmpdcli) | 💰 Premium only |
| **UPnP/DLNA** | ✅ Included | ✅ Included |
| **Multi-room** | ✅ Included (Snapcast) | 💰 Premium only |
| **CD playback** | ✅ Included with metadata | 💰 Premium only |
| **Network audio sink** | ✅ PulseAudio/PipeWire TCP (wired) | ❌ Not supported |
| **Home Assistant** | Native integration | Unofficial community plugin |
| **Voice assistant / AI** | Via Home Assistant | 💰 CORRD (Premium) |
| **Embedded UI** | Lightweight HTMX/Tailwind | Node.js/React |
| **Multi-node remote** | Svelte PWA (install from browser, no store) | Native mobile app (iOS/Android) |
| **Architecture** | User session, PulseAudio/PipeWire, Golang | System session, ALSA, Node.js |
| **System philosophy** | Linux-native modular stack | Appliance-style distribution |
| **Debian base** | Trixie (stable) | Bookworm (oldstable) |
| **Installation** | Image flash (Pi) or `curl \| bash` (any Debian/Ubuntu) | Image flash |
| **Upgrade** | `odio-upgrade` | OTA updates / Reflash between major versions |
| **Long-term stability** | No reinstall between Buster and Trixie | Reflash between major versions |

## Related projects

- [odio-pwa](https://github.com/b0bbywan/odio-pwa) — Progressive Web App to control multiple odios nodes ([live](https://odio-pwa.vercel.app/))
- [odio-ha](https://github.com/b0bbywan/odio-ha) — Full Home Assistant integration: odios nodes appear as native HA media players and can be mapped to official integrations to inherit their full capabilities
- [go-odio-api](https://github.com/b0bbywan/go-odio-api) — REST API and embedded UI
- [go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) — CD/USB player daemon

## License

This project is licensed under the BSD 2-Clause License — see [LICENSE](LICENSE).

The installer distribution (`odio-*.tar.gz`) includes [ansible-core](https://github.com/ansible/ansible), which is licensed under the GNU General Public License v3.0. A copy of that license is included in the archive under `licenses/ANSIBLE-LICENSE-GPLv3`.

The odios playbooks and scripts are independent works that invoke ansible-core as an external tool and are not subject to the GPL.
