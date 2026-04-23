#!/bin/bash
# Build the test-baseline Docker image from a published odios SD-card image.
#
# Downloads odios-<TAG>-<ARCH>.img.xz from the GitHub release, extracts the
# rootfs partition (assumed p2, RPi layout), imports it with the systemd
# entrypoint used by Dockerfile.test, and pushes the resulting image as
# ghcr.io/<repo>/test-baseline:<TAG>-<ARCH>.
#
# Approach inspired by https://github.com/vascoguita/raspios-docker.
#
# Usage: img-to-docker.sh <baseline-tag> <arch>
#   <baseline-tag>  e.g. 2026.4.0rc3
#   <arch>          arm64 | armhf
#
# Env:
#   GITHUB_REPOSITORY  owner/repo (auto-detected from git remote if unset)

set -euo pipefail

TAG="${1:?usage: img-to-docker.sh <baseline-tag> <arch>}"
ARCH="${2:?usage: img-to-docker.sh <baseline-tag> <arch>}"

case "${ARCH}" in
  arm64) PLATFORM="linux/arm64" ;;
  armhf) PLATFORM="linux/arm/v7" ;;
  *) echo "Unsupported arch: ${ARCH} (expected arm64 or armhf)" >&2; exit 2 ;;
esac

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "${REPO}" ]]; then
    REPO=$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null \
        | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+?)(\.git)?$|\1|')
fi
[[ -n "${REPO}" ]] || { echo "Cannot determine repo (set GITHUB_REPOSITORY)" >&2; exit 2; }

IMG_NAME="odio-${TAG}-${ARCH}.img.xz"
IMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${IMG_NAME}"
IMAGE_REF="ghcr.io/${REPO}/test-baseline:${TAG}-${ARCH}"

WORK_DIR=$(mktemp -d)
trap 'cleanup' EXIT

LOOP_DEV=""
MOUNT_DIR=""

cleanup() {
    set +e
    [[ -n "${MOUNT_DIR}" && -d "${MOUNT_DIR}" ]] && sudo umount "${MOUNT_DIR}" 2>/dev/null
    [[ -n "${LOOP_DEV}" ]] && sudo losetup -d "${LOOP_DEV}" 2>/dev/null
    [[ -d "${WORK_DIR}" ]] && sudo rm -rf "${WORK_DIR}"
}

echo "=== Downloading ${IMG_NAME} ==="
IMG_XZ="${WORK_DIR}/${IMG_NAME}"
curl -fsSL -o "${IMG_XZ}" "${IMG_URL}"

echo "=== Decompressing ==="
IMG="${WORK_DIR}/${IMG_NAME%.xz}"
xz -dc "${IMG_XZ}" > "${IMG}"

echo "=== Locating rootfs partition (p2) ==="
ROOT_OFFSET=$(sfdisk --json "${IMG}" | jq -r '.partitiontable.partitions[1].start * 512')
echo "Offset: ${ROOT_OFFSET} bytes"

LOOP_DEV=$(sudo losetup -f --show -o "${ROOT_OFFSET}" "${IMG}")
echo "Loop device: ${LOOP_DEV}"

MOUNT_DIR="${WORK_DIR}/rootfs"
mkdir "${MOUNT_DIR}"
sudo mount "${LOOP_DEV}" "${MOUNT_DIR}"

# Simulate what rpi-imager does on first boot: grant passwordless sudo to the
# target user. The SD image rootfs doesn't include this by itself — rpi-imager
# injects it via cloud-init/user-data based on the flasher's choices. Without
# it, the test-baseline user can't invoke sudo (needed by install.sh upgrade).
echo "=== Injecting test-baseline sudoers drop-in for 'odio' ==="
echo 'odio ALL=(ALL) NOPASSWD:ALL' | sudo tee "${MOUNT_DIR}/etc/sudoers.d/010-test-baseline-odio" > /dev/null
sudo chmod 0440 "${MOUNT_DIR}/etc/sudoers.d/010-test-baseline-odio"

# Strip systemd units that can't start in a container (no /dev/kmsg, no
# kernel-level fs tooling, no udev rw, no TPM, …). The raspbian rootfs is
# heavier than a stock debian base, so plain Dockerfile.test-style cleanup
# is not enough — sysinit.target.wants/ here holds ~20 services that fail
# and block the whole boot chain (sysinit → basic → sockets → dbus.socket).
# We wipe all *.service symlinks from sysinit.target.wants (keeping the
# .mount/.path/.automount units that are harmless in a container), mask
# the network-wait-online services, and re-seed multi-user.target.wants
# with just dbus + logind — same minimum reached by Dockerfile.test.
echo "=== Stripping container-hostile systemd units ==="
sudo rm -f \
    "${MOUNT_DIR}"/lib/systemd/system/multi-user.target.wants/* \
    "${MOUNT_DIR}"/etc/systemd/system/*.wants/* \
    "${MOUNT_DIR}"/lib/systemd/system/local-fs.target.wants/* \
    "${MOUNT_DIR}"/lib/systemd/system/sockets.target.wants/*udev* \
    "${MOUNT_DIR}"/lib/systemd/system/sockets.target.wants/*initctl* \
    "${MOUNT_DIR}"/lib/systemd/system/systemd-update-utmp*

# Services in sysinit.target.wants that the container can't satisfy.
sudo find "${MOUNT_DIR}/lib/systemd/system/sysinit.target.wants/" \
    -maxdepth 1 -type l -name '*.service' -delete 2>/dev/null || true

# Mask network-wait-online services (they spin forever without a routable
# interface), plus a few rpi-specific units that have no meaning here.
for unit in \
    systemd-networkd-wait-online.service \
    NetworkManager-wait-online.service \
    systemd-firstboot.service \
    first-boot-complete.target \
    rpi-resize.service \
    rpi-eeprom-update.service \
    rpi-usb-gadget-ics.service \
    userconfig.service \
    cloud-init.target \
    cloud-init-main.service \
    cloud-init-local.service \
    cloud-init-network.service \
    cloud-final.service \
    cloud-config.service \
    cloud-config.target \
; do
    sudo ln -sf /dev/null "${MOUNT_DIR}/etc/systemd/system/${unit}"
done

sudo ln -sf /lib/systemd/system/systemd-logind.service \
    "${MOUNT_DIR}/lib/systemd/system/multi-user.target.wants/systemd-logind.service"
sudo ln -sf /lib/systemd/system/dbus.service \
    "${MOUNT_DIR}/lib/systemd/system/multi-user.target.wants/dbus.service"

echo "=== Importing rootfs into Docker as ${IMAGE_REF} (platform=${PLATFORM}) ==="
sudo tar -C "${MOUNT_DIR}" --numeric-owner -c . | docker import \
    --platform "${PLATFORM}" \
    -c 'CMD ["/lib/systemd/systemd"]' \
    -c 'STOPSIGNAL SIGRTMIN+3' \
    -c "LABEL org.opencontainers.image.source=https://github.com/${REPO}" \
    - "${IMAGE_REF}"

echo "=== Pushing ${IMAGE_REF} ==="
docker push "${IMAGE_REF}"

echo "=== Done ==="
