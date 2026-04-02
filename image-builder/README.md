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
sudo apt-get install -y qemu-user-static binfmt-support parted \
  e2fsprogs xz-utils wget psmisc
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
2. **Prepare** — copy, grow by 2G, losetup, resize partition
3. **Chroot** — mount filesystems, set up QEMU user-mode emulation
4. **Provision** — download odios release archive, run Ansible playbook (`install_mode=image`)
5. **Verify** — check `init_resize` is present in `cmdline.txt` for first-boot auto-expand
6. **Shrink** — `resize2fs -M`, truncate image to minimum size + 16 MiB margin
7. **Compress** — `xz` the final image

## Flashing

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash the `.img.xz` file to an SD card. Pi Imager handles user creation, SSH, and WiFi configuration — the image does not ship with any default credentials.

On first boot, the partition auto-expands to fill the SD card.

## Updating base images

Edit `config.sh` with new URLs and SHA256 checksums from:
https://downloads.raspberrypi.com/raspios_lite_arm64/images/
https://downloads.raspberrypi.com/raspios_lite_armhf/images/

The `.sha256` file in each release directory contains the checksum.
