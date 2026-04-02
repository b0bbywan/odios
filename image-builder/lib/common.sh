#!/usr/bin/env bash
# common.sh — Logging, error handling, cleanup trap, privilege checks

log_info()  { echo "[$(date +%H:%M:%S)] INFO: $*" >&2; }
log_warn()  { echo "[$(date +%H:%M:%S)] WARN: $*" >&2; }
log_error() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (or via sudo)"
        exit 1
    fi
}

check_deps() {
    local missing=()
    local required_bins=(qemu-arm-static qemu-aarch64-static parted
                         resize2fs e2fsck dumpe2fs xz wget fuser)

    for bin in "${required_bins[@]}"; do
        if ! command -v "$bin" &>/dev/null; then
            missing+=("$bin")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing binaries: ${missing[*]}"
        log_error "On Debian/Ubuntu: sudo apt-get install -y qemu-user-static binfmt-support parted e2fsprogs xz-utils wget psmisc"
        log_error "On Fedora: sudo dnf install qemu-user-static parted e2fsprogs xz wget psmisc"
        exit 1
    fi
}

check_disk_space() {
    local dir="$1"
    local avail_kb
    avail_kb=$(df --output=avail "$dir" 2>/dev/null | tail -1 | tr -d ' ')
    if [[ -n "$avail_kb" ]] && [[ "$avail_kb" -lt 5242880 ]]; then
        log_warn "Less than 5 GB free on $(df --output=target "$dir" | tail -1). Build may fail."
    fi
}

cleanup() {
    log_info "Cleaning up..."

    if [[ -n "${ROOTFS:-}" ]]; then
        fuser -k "$ROOTFS" 2>/dev/null || true
        sleep 1
        sync

        # Restore resolv.conf
        if [[ -f "$ROOTFS/etc/resolv.conf.bak" ]]; then
            mv "$ROOTFS/etc/resolv.conf.bak" "$ROOTFS/etc/resolv.conf" 2>/dev/null || true
        fi

        # Remove qemu binary
        rm -f "$ROOTFS/usr/bin/qemu-arm-static" 2>/dev/null || true
        rm -f "$ROOTFS/usr/bin/qemu-aarch64-static" 2>/dev/null || true

        # Unmount in reverse order
        umount "$ROOTFS/dev/pts"      2>/dev/null || true
        umount "$ROOTFS/dev"          2>/dev/null || true
        umount "$ROOTFS/sys"          2>/dev/null || true
        umount "$ROOTFS/proc"         2>/dev/null || true
        umount "$ROOTFS/boot/firmware" 2>/dev/null || true
        umount "$ROOTFS"              2>/dev/null || true
    fi

    if [[ -n "${LOOP:-}" ]]; then
        losetup -d "$LOOP" 2>/dev/null || true
    fi
}
