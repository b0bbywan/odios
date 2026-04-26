#!/usr/bin/env bash
# config.sh — Constants for odios image builder. No logic, only variables.

# Base image URLs — update these when Pi OS releases change
export PIOS_ARMHF_URL="https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2025-12-04/2025-12-04-raspios-trixie-armhf-lite.img.xz"
export PIOS_ARM64_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-lite.img.xz"

export PIOS_ARMHF_SHA256="1b3e49b67b15050a9f20a60267c145e6d468dc9559dd9cd945130a11401a49ff"
export PIOS_ARM64_SHA256="681a775e20b53a9e4c7341d748a5a8cdc822039d8c67c1fd6ca35927abbe6290"

# Build parameters
export IMAGE_GROW_SIZE="2G"
export ODIOS_USER="odio"
export XZ_COMPRESSION_LEVEL=9
export XZ_THREADS=0                # 0 = use all available cores

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
ANSIBLE_EXTRA_VARS=(
    "target_user=${ODIOS_USER}"
    "target_hostname=odio"
    "install_mode=image"
    "install_branding=true"
    "install_spotifyd=true"
    "install_tidal=true"
    "install_qobuz=true"
    "install_upnpwebradios=true"
    "install_mympd=true"
)
