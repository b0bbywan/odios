# odios

[![Build](https://github.com/b0bbywan/odios/actions/workflows/release.yml/badge.svg)](https://github.com/b0bbywan/odios/actions/workflows/release.yml)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/b0bbywan?label=Sponsor&logo=GitHub)](https://github.com/sponsors/b0bbywan)

### [odio](https://beta.odio.love/) — Open-source audiophile distribution for Debian/Ubuntu and Raspberry Pi with native Home Assistant integration.

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
| PulseAudio | Central audio server, routes all sources to the DAC output — other PCs running PulseAudio or PipeWire can stream to it over the network via TCP/Zeroconf | user |
| MPD | Music Player Daemon (network, CD/USB) | user |
| Shairport Sync | AirPlay receiver | user |
| Snapcast | Multi-room audio client | user |
| upmpdcli | UPnP/DLNA renderer | system |
| Bluetooth | A2DP sink with automatic pairing | system |

## Installation

```bash
curl -fsSL https://github.com/b0bbywan/odios/releases/latest/download/install.sh | bash
```

The installer works on both fresh and existing systems (idempotent, safe to re-run). It prompts for a target user — if the user doesn't exist it is created automatically. Installing for an existing user is supported: config files are backed up before any modification.

See [installer/README.md](installer/README.md) for full installation options, environment variables, and testing.

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
| **Network audio sink** | ✅ PulseAudio/PipeWire TCP | ❌ Not supported |
| **Home Assistant** | Native integration | Unofficial community plugin |
| **Voice assistant / AI** | Via Home Assistant | 💰 CORRD (Premium) |
| **Embedded UI** | Lightweight HTMX/Tailwind | Node.js/React |
| **Multi-node remote** | Svelte PWA (install from browser, no store) | Native mobile app (iOS/Android) |
| **Architecture** | User session, PulseAudio/PipeWire, Golang | System session, ALSA, Node.js |
| **System philosophy** | Linux-native modular stack | Appliance-style distribution |
| **Debian base** | Trixie (stable) | Bookworm (oldstable) |
| **Installation** | One command (`curl \| bash`) | Image flash |
| **Upgrade** | `apt upgrade` | OTA updates / Reflash between major versions |
| **Long-term stability** | No reinstall between Buster and Trixie | Reflash between major versions |

## Related projects

- [odio-pwa](https://github.com/b0bbywan/odio-pwa) — Progressive Web App to control multiple odios nodes ([live](https://odio-pwa.vercel.app/))
- [odio-ha](https://github.com/b0bbywan/odio-ha) — Full Home Assistant integration: odios nodes appear as native HA media players and can be mapped to official integrations to inherit their full capabilities
- [go-odio-api](https://github.com/b0bbywan/go-odio-api) — REST API and embedded UI
- [go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) — CD/USB player daemon

## License

This project is licensed under the BSD 2-Clause License — see [LICENSE](LICENSE).

The installer distribution (`odios-*.tar.gz`) includes [ansible-core](https://github.com/ansible/ansible), which is licensed under the GNU General Public License v3.0. A copy of that license is included in the archive under `licenses/ANSIBLE-LICENSE-GPLv3`.

The odios playbooks and scripts are independent works that invoke ansible-core as an external tool and are not subject to the GPL.
