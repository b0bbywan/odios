#!/usr/bin/env bash
# chroot.sh — Mount/unmount bind mounts, qemu-user-static setup

mount_chroot() {
    local loop="$1"
    local rootfs="$2"

    log_info "Mounting chroot filesystems..."

    mkdir -p "$rootfs"
    mount "${loop}p2" "$rootfs"
    mount "${loop}p1" "$rootfs/boot/firmware"
    mount -t proc proc "$rootfs/proc"
    mount -t sysfs sys "$rootfs/sys"
    mount --bind /dev "$rootfs/dev"
    mount --bind /dev/pts "$rootfs/dev/pts"

    # DNS resolution inside chroot
    cp "$rootfs/etc/resolv.conf" "$rootfs/etc/resolv.conf.bak" 2>/dev/null || true
    cp /etc/resolv.conf "$rootfs/etc/resolv.conf"

    log_info "Chroot filesystems mounted"
}

setup_qemu() {
    local arch="$1"
    local rootfs="$2"
    local qemu_bin binfmt_name

    case "$arch" in
        armhf)
            qemu_bin="qemu-arm-static"
            binfmt_name="qemu-arm"
            ;;
        arm64)
            qemu_bin="qemu-aarch64-static"
            binfmt_name="qemu-aarch64"
            ;;
        *)
            log_error "Unknown architecture: $arch"
            exit 1
            ;;
    esac

    # Skip QEMU when running natively (arm64 host building arm64)
    if [[ "$arch" == "arm64" && "$(uname -m)" == "aarch64" ]]; then
        log_info "Native arm64 build detected, skipping QEMU"
        return 0
    fi

    log_info "Setting up QEMU (${qemu_bin})..."
    cp "/usr/bin/${qemu_bin}" "$rootfs/usr/bin/"

    # Verify binfmt handler is registered
    if [[ ! -f "/proc/sys/fs/binfmt_misc/${binfmt_name}" ]]; then
        log_error "binfmt handler '${binfmt_name}' not registered."
        log_error "Try: sudo systemctl restart binfmt-support"
        exit 1
    fi

    # Validate the setup
    if ! chroot "$rootfs" /bin/true 2>/dev/null; then
        log_error "chroot test failed — QEMU/binfmt setup is broken"
        log_error "Check that qemu-user-static and binfmt-support are installed and running"
        exit 1
    fi

    log_info "QEMU setup verified"
}

unmount_chroot() {
    local rootfs="$1"

    log_info "Unmounting chroot filesystems..."

    fuser -k "$rootfs" 2>/dev/null || true
    sync
    sleep 1

    # Restore resolv.conf
    if [[ -f "$rootfs/etc/resolv.conf.bak" ]]; then
        mv "$rootfs/etc/resolv.conf.bak" "$rootfs/etc/resolv.conf" 2>/dev/null || true
    fi

    # Remove qemu binary
    rm -f "$rootfs/usr/bin/qemu-arm-static" 2>/dev/null || true
    rm -f "$rootfs/usr/bin/qemu-aarch64-static" 2>/dev/null || true

    # Unmount in reverse order
    umount "$rootfs/dev/pts"       2>/dev/null || true
    umount "$rootfs/dev"           2>/dev/null || true
    umount "$rootfs/sys"           2>/dev/null || true
    umount "$rootfs/proc"          2>/dev/null || true
    umount "$rootfs/boot/firmware" 2>/dev/null || true
    umount "$rootfs"               2>/dev/null || true

    log_info "Chroot filesystems unmounted"
}
