<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-8-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

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

odios turns a €35 Raspberry Pi into what commercial streamers sell for €300–500: Bluetooth A2DP (in & out), AirPlay, Snapcast multi-room, UPnP/DLNA, CD playback with metadata — all in one box, controlled from a web app, no account or subscription required. Other PCs running PulseAudio or PipeWire can also stream directly to it over the network, making it a true whole-home audio sink.

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
| [Spotifyd](https://github.com/Spotifyd/spotifyd) | Spotify Connect receiver | user |
| Snapcast | Multi-room audio client | user |
| upmpdcli | UPnP/DLNA renderer | user |
| Bluetooth | A2DP sink with automatic pairing, plus audio output to Bluetooth speakers/headphones | system |

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

Each release installs `/usr/local/bin/odio-upgrade` with two subcommands: `check` runs daily via a systemd user timer and refreshes `/var/cache/odio/upgrades.json`; `apply` performs the upgrade.

```bash
odio-upgrade                    # alias of `apply` — upgrade to the latest reported version
odio-upgrade apply --version 2026.5.0 # target a specific version
odio-upgrade apply --reinstall  # re-run every role in full (repair a broken install)
odio-upgrade apply --progress   # emit structured progress events for odio-api
```

`odio-upgrade` reads `/var/lib/odio/state.json` (or rebuilds from dpkg as a last resort) to preserve the feature selection and role opt-outs across upgrades. Run `odio-upgrade --dry-run --force` to see what would be invoked without running it. Use `--reinstall` to force every role through a full first-install pass (bypassing the smart-upgrade skips) when an install needs repairing. Use `--progress` to emit structured `ODIO_PROGRESS` JSON lines (one per role and phase) to stdout for odio-api to display, without altering the normal output.

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
| **Minimum hardware** | **Raspberry Pi B** (armv6l, 2012) | Raspberry Pi 3 |
| **Music library management** | ✅ Via myMPD (web UI) | ✅ Built-in library browser |
| **Bluetooth A2DP** | ✅ Included | 💰 Premium only |
| **Bluetooth output (speakers/headphones)** | ✅ Included | ⚠️ Community plugin only |
| **AirPlay** | ✅ Included | ✅ Free plugin |
| **Spotify Connect** | ✅ Included | ✅ Free plugin |
| **Qobuz** | ✅ Included (via upmpdcli) | 💰 Premium only |
| **Tidal / Tidal Connect** | ✅ Included (via upmpdcli) | 💰 Premium only |
| **UPnP/DLNA** | ✅ Included | ✅ Included |
| **Web radios** | ✅ Included (upmpdcli + myMPD) | ✅ Included |
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
| **Upgrade** | `odio-upgrade` or reflash | OTA updates / Reflash between major versions |

## Related projects

- [odio-pwa](https://github.com/b0bbywan/odio-pwa) — Progressive Web App to control multiple odios nodes ([live](https://odio-pwa.vercel.app/))
- [odio-ha](https://github.com/b0bbywan/odio-ha) — Full Home Assistant integration: odios nodes appear as native HA media players and can be mapped to official integrations to inherit their full capabilities
- [go-odio-api](https://github.com/b0bbywan/go-odio-api) — REST API and embedded UI
- [go-mpd-discplayer](https://github.com/b0bbywan/go-mpd-discplayer) — CD/USB player daemon

## License

This project is licensed under the BSD 2-Clause License — see [LICENSE](LICENSE).

The installer distribution (`odio-*.tar.gz`) includes [ansible-core](https://github.com/ansible/ansible), which is licensed under the GNU General Public License v3.0. A copy of that license is included in the archive under `licenses/ANSIBLE-LICENSE-GPLv3`.

The odios playbooks and scripts are independent works that invoke ansible-core as an external tool and are not subject to the GPL.

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://odio.love"><img src="https://avatars.githubusercontent.com/u/9570397?v=4?s=100" width="100px;" alt="b0bbywan"/><br /><sub><b>b0bbywan</b></sub></a><br /><a href="https://github.com/b0bbywan/odios/issues?q=author%3Ab0bbywan" title="Bug reports">🐛</a> <a href="#blog-b0bbywan" title="Blogposts">📝</a> <a href="https://github.com/b0bbywan/odios/commits?author=b0bbywan" title="Code">💻</a> <a href="#content-b0bbywan" title="Content">🖋</a> <a href="#data-b0bbywan" title="Data">🔣</a> <a href="https://github.com/b0bbywan/odios/commits?author=b0bbywan" title="Documentation">📖</a> <a href="#design-b0bbywan" title="Design">🎨</a> <a href="#example-b0bbywan" title="Examples">💡</a> <a href="#ideas-b0bbywan" title="Ideas, Planning, & Feedback">🤔</a> <a href="#infra-b0bbywan" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#maintenance-b0bbywan" title="Maintenance">🚧</a> <a href="#platform-b0bbywan" title="Packaging/porting to new platform">📦</a> <a href="#projectManagement-b0bbywan" title="Project Management">📆</a> <a href="#question-b0bbywan" title="Answering Questions">💬</a> <a href="#research-b0bbywan" title="Research">🔬</a> <a href="https://github.com/b0bbywan/odios/pulls?q=is%3Apr+reviewed-by%3Ab0bbywan" title="Reviewed Pull Requests">👀</a> <a href="#security-b0bbywan" title="Security">🛡️</a> <a href="#tool-b0bbywan" title="Tools">🔧</a> <a href="https://github.com/b0bbywan/odios/commits?author=b0bbywan" title="Tests">⚠️</a> <a href="#tutorial-b0bbywan" title="Tutorials">✅</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/pbattino"><img src="https://avatars.githubusercontent.com/u/13657236?v=4?s=100" width="100px;" alt="Paolo Battino"/><br /><sub><b>Paolo Battino</b></sub></a><br /><a href="https://github.com/b0bbywan/odios/issues?q=author%3Apbattino" title="Bug reports">🐛</a> <a href="https://github.com/b0bbywan/odios/commits?author=pbattino" title="Documentation">📖</a> <a href="#example-pbattino" title="Examples">💡</a> <a href="#ideas-pbattino" title="Ideas, Planning, & Feedback">🤔</a> <a href="#research-pbattino" title="Research">🔬</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sm0kingm4n"><img src="https://avatars.githubusercontent.com/u/17809362?v=4?s=100" width="100px;" alt="Frankie Bigslave"/><br /><sub><b>Frankie Bigslave</b></sub></a><br /><a href="#ideas-sm0kingm4n" title="Ideas, Planning, & Feedback">🤔</a> <a href="#research-sm0kingm4n" title="Research">🔬</a> <a href="#tutorial-sm0kingm4n" title="Tutorials">✅</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://kollnig.net"><img src="https://avatars.githubusercontent.com/u/5175206?v=4?s=100" width="100px;" alt="Konrad Kollnig"/><br /><sub><b>Konrad Kollnig</b></sub></a><br /><a href="https://github.com/b0bbywan/odios/issues?q=author%3Akasnder" title="Bug reports">🐛</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/matsvitt"><img src="https://avatars.githubusercontent.com/u/872892?v=4?s=100" width="100px;" alt="Matthias Vitt"/><br /><sub><b>Matthias Vitt</b></sub></a><br /><a href="https://github.com/b0bbywan/odios/issues?q=author%3Amatsvitt" title="Bug reports">🐛</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/andrum993"><img src="https://avatars.githubusercontent.com/u/137400510?v=4?s=100" width="100px;" alt="andrum993"/><br /><sub><b>andrum993</b></sub></a><br /><a href="https://github.com/b0bbywan/odios/issues?q=author%3Aandrum993" title="Bug reports">🐛</a> <a href="#ideas-andrum993" title="Ideas, Planning, & Feedback">🤔</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Thomas-O"><img src="https://avatars.githubusercontent.com/u/6567035?v=4?s=100" width="100px;" alt="Thomas-O"/><br /><sub><b>Thomas-O</b></sub></a><br /><a href="#ideas-Thomas-O" title="Ideas, Planning, & Feedback">🤔</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/voterpublic"><img src="https://avatars.githubusercontent.com/u/112673643?v=4?s=100" width="100px;" alt="voterpublic"/><br /><sub><b>voterpublic</b></sub></a><br /><a href="#doc-voterpublic" title="Documentation">📖</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
