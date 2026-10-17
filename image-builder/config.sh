#!/usr/bin/env bash
# config.sh — Constants for odios image builder. No logic, only variables.

# Base image URLs — update these when Pi OS releases change
export PIOS_ARMHF_URL="https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2026-10-06/2026-10-06-raspios-trixie-armhf-lite.img.xz"
export PIOS_ARM64_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-10-06/2026-10-06-raspios-trixie-arm64-lite.img.xz"

export PIOS_ARMHF_SHA256="2c302771f34c67a0b7ae7aa2e0dcdd3eac660504be59193c011ba79d412e1632"
export PIOS_ARM64_SHA256="483db18a48da399b5b7022ffae9a07bc6d99daab30e593aedac09b69ff422843"

# Build parameters
export IMAGE_GROW_SIZE="2G"
export ODIOS_USER="odio"
export XZ_COMPRESSION_LEVEL=9
export XZ_THREADS=0                # 0 = use all available cores

# Extra packages to install on the image (beyond what Ansible deploys).
# Currently: yq (Python kislyuk, jq-syntax) — used by odios-firstboot-network.sh
# to inject the discovered snapweb URL into odio-api's config.yaml.
# shellcheck disable=SC2034  # sourced by build.sh
INSTALL_PACKAGES=(
    yq
)

# Packages to purge from the base image (not needed for headless audio)
# shellcheck disable=SC2034  # sourced by build.sh
PURGE_PACKAGES=(
    # Camera
    rpicam-apps-lite rpicam-apps-core libpisp1
    # Pi Connect remote access
    rpi-connect-lite
    # Wireless regulatory (handled by firmware)
    wireless-regdb
    # Documentation
    man-db manpages
    # Unused hardware support
    modemmanager usb-modeswitch
    # Compilers / debuggers / build tools (not needed on a deployed image)
    cpp g++ gcc gdb make pkg-config pahole
    # Kernel headers
    linux-headers-rpi-2712 linux-headers-rpi-v8 linux-headers-rpi-v7 linux-headers-rpi-v6
    # Debug / trace
    strace
    # Video4Linux (no camera/video use)
    v4l-utils
    # PPP / modem
    ppp
    # Swap (bad for audio latency + SD card wear)
    rpi-swap
)

# GitHub
export GITHUB_REPO="b0bbywan/odios"

# Ansible variables passed during provisioning
# shellcheck disable=SC2034  # sourced by build.sh, arrays can't be exported
# Add "audioserver=pipewire" to build a PipeWire image instead of PulseAudio.
ANSIBLE_EXTRA_VARS=(
    "target_user=${ODIOS_USER}"
    "target_hostname=odio"
    "install_mode=image"
)
