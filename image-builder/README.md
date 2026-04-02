# odios Image Builder

Build flashable `.img.xz` images for Raspberry Pi from the official Pi OS Lite base image, with odios pre-installed via the existing Ansible playbook.

The builder runs on x86_64 Debian/Ubuntu (local machine or GitHub Actions runner). It uses loopback mount + chroot + qemu-user-static to provision the image.

## Targets

| Architecture | Base image | Output |
|---|---|---|
| armhf (32-bit) | Raspberry Pi OS Lite (Trixie) armhf | `odios-<version>-armhf.img.xz` |
| arm64 (64-bit) | Raspberry Pi OS Lite (Trixie) arm64 | `odios-<version>-arm64.img.xz` |

## Dependencies

```bash
# Debian/Ubuntu
sudo apt-get install -y qemu-user-static binfmt-support parted \
  e2fsprogs xz-utils wget psmisc zerofree

# Fedora
sudo dnf install qemu-user-static parted e2fsprogs xz wget psmisc zerofree
```

## Usage

```
Usage: sudo ./image-builder/build.sh <command> [options]

Commands:
  build       Build an image
  clean       Remove work directory and temp files

Build options:
  --arch <armhf|arm64>       Target architecture (required)
  --version <version>        odios version tag (required)
  --workdir <path>           Working directory (default: /tmp/odios-build)
  --output <path>            Output directory (default: ./output)
  --keep                     Don't delete workdir after build (for debugging)
  --skip-download            Reuse previously downloaded base image from workdir
  --skip-shrink              Skip shrink step (faster builds for testing)
```

### Examples

```bash
# Build a release image
sudo ./image-builder/build.sh build --arch arm64 --version 2026.3.0

# Build from a PR pre-release
sudo ./image-builder/build.sh build --arch armhf --version pr-5

# Fast iteration: keep workdir and skip shrink
sudo ./image-builder/build.sh build --arch arm64 --version 2026.3.0 --keep --skip-shrink

# Rebuild without re-downloading the base image
sudo ./image-builder/build.sh build --arch arm64 --version 2026.3.0 --skip-download

# Clean up
sudo ./image-builder/build.sh clean --workdir /tmp/odios-build
```

## Build pipeline

1. **Download** Pi OS Lite base image, verify SHA256
2. **Prepare** -- copy, grow by 2G, losetup, resize partition
3. **Chroot** -- mount filesystems, set up QEMU user-mode emulation
4. **Provision** -- download odios release archive, run Ansible playbook (`install_mode=image`)
5. **Firstboot** -- install `odios-firstboot.service` (updates service names if hostname changes)
6. **Upgrade** -- `apt-get upgrade` to ship with latest packages
7. **Verify** -- check `init_resize` is present in `cmdline.txt` for first-boot auto-expand
8. **Shrink** -- `resize2fs -M`, truncate image to minimum size + 16 MiB margin
9. **Compress** -- `xz` the final image
10. **Manifest** -- generate `.rpi-imager-manifest` for Pi Imager integration

## Flashing with Raspberry Pi Imager

The CI produces a combined `odios.rpi-imager-manifest` uploaded to each release. This manifest points Pi Imager directly to the image download URLs on GitHub, so there is no need to download images manually -- Pi Imager handles the download and flashing.

Cloud-init customization (hostname, SSH, WiFi, user creation) is fully supported via the manifest, as Pi OS Trixie includes cloud-init natively.

### Using the manifest (recommended)

1. Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Go to **Options app** > **Content Repository** > **Use custom URL**
3. Enter the manifest URL:
   ```
   https://github.com/b0bbywan/odios/releases/latest/download/odios.rpi-imager-manifest
   ```
4. The available images appear in the OS list
5. Configure hostname, SSH, WiFi, and user, then flash

**User configuration**: All odios services run under the `odio` system user. To connect via SSH, you can either:
- Create a separate user through Pi Imager's customization screen (recommended)
- Reuse the `odio` user by setting its password in Pi Imager

### Without the manifest

Pi Imager 2.0+ does not offer customization for images loaded via "Use custom" directly (missing metadata, [rpi-imager#1302](https://github.com/raspberrypi/rpi-imager/issues/1302)). Two alternatives:

**cloud-init manually**: Download and flash the `.img.xz` from the GitHub release, then mount the boot partition and create `user-data` and `network-config` files:

```yaml
# user-data (on boot partition)
#cloud-config
hostname: myhost
users:
  - name: myuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: changeme
ssh_pwauth: true
```

```yaml
# network-config (on boot partition)
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      access-points:
        "MySSID":
          password: "MyPassword"
```

**Pi Imager CLI**:

```bash
rpi-imager --cli \
  --cloudinit-userdata user-data \
  --cloudinit-networkconfig network-config \
  odios-<version>-<arch>.img.xz /dev/sdX
```

## First boot

On first boot:
- **Partition auto-expands** to fill the SD card (Pi OS `init_resize`)
- **cloud-init** applies user configuration (hostname, SSH, WiFi, user)
- **odios-firstboot** ensures the `odio` user has the required groups (`audio`, `bluetooth`, `input`, etc.) and updates service names if the hostname was changed
- **SSH host keys** are regenerated

All services (MPD, Spotifyd, Shairport-sync, upmpdcli, etc.) run as the `odio` user via systemd user units.

Default hostname is `odio`. If changed via cloud-init or Pi Imager, the firstboot service automatically updates Bluetooth adapter name, Spotifyd device name, and upmpdcli friendly name to match.

## Updating base images

Edit `config.sh` with new URLs and SHA256 checksums from:
- https://downloads.raspberrypi.com/raspios_lite_arm64/images/
- https://downloads.raspberrypi.com/raspios_lite_armhf/images/

The `.sha256` file in each release directory contains the checksum.
