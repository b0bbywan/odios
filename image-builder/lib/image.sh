#!/usr/bin/env bash
# image.sh — Download, verify, decompress, and prepare the base Pi OS image

download_base_image() {
    local arch="$1"
    local workdir="$2"
    local url sha256 xz_file img_file

    case "$arch" in
        armhf) url="$PIOS_ARMHF_URL"; sha256="$PIOS_ARMHF_SHA256" ;;
        arm64) url="$PIOS_ARM64_URL"; sha256="$PIOS_ARM64_SHA256" ;;
        *) log_error "Unknown architecture: $arch"; exit 1 ;;
    esac

    xz_file="${workdir}/base-${arch}.img.xz"
    img_file="${workdir}/base-${arch}.img"

    if [[ "$SKIP_DOWNLOAD" == "true" ]] && [[ -f "$img_file" ]]; then
        log_info "Reusing existing base image: ${img_file}"
        return 0
    fi

    log_info "Downloading base image for ${arch}..."
    wget -q --show-progress -O "$xz_file" "$url"

    log_info "Verifying checksum..."
    local actual
    actual=$(sha256sum "$xz_file" | awk '{print $1}')
    if [[ "$actual" != "$sha256" ]]; then
        log_error "SHA256 mismatch!"
        log_error "  Expected: ${sha256}"
        log_error "  Got:      ${actual}"
        rm -f "$xz_file"
        exit 1
    fi
    log_info "Checksum OK"

    log_info "Decompressing base image..."
    xz -d "$xz_file"

    # xz -d strips the .xz extension, producing the .img file
    local decompressed="${xz_file%.xz}"
    if [[ "$decompressed" != "$img_file" ]]; then
        mv "$decompressed" "$img_file"
    fi

    log_info "Base image ready: ${img_file}"
}

prepare_image() {
    local arch="$1"
    local workdir="$2"
    local base_img="${workdir}/base-${arch}.img"

    IMAGE_PATH="${workdir}/odio-${arch}.img"

    log_info "Copying base image..."
    cp "$base_img" "$IMAGE_PATH"

    log_info "Growing image by ${IMAGE_GROW_SIZE}..."
    truncate -s "+${IMAGE_GROW_SIZE}" "$IMAGE_PATH"

    log_info "Setting up loop device..."
    LOOP=$(losetup -fP --show "$IMAGE_PATH")
    partprobe "$LOOP"
    udevadm settle 2>/dev/null || true
    log_info "Loop device: ${LOOP}"

    # Verify partition layout: p1=FAT (boot), p2=ext4 (rootfs)
    local p1_type p2_type
    p1_type=$(blkid -o value -s TYPE "${LOOP}p1" 2>/dev/null || true)
    p2_type=$(blkid -o value -s TYPE "${LOOP}p2" 2>/dev/null || true)

    if [[ "$p1_type" != "vfat" ]]; then
        log_error "Partition 1 is not FAT32 (got: ${p1_type:-none}). Unexpected image layout."
        exit 1
    fi
    if [[ "$p2_type" != "ext4" ]]; then
        log_error "Partition 2 is not ext4 (got: ${p2_type:-none}). Unexpected image layout."
        exit 1
    fi

    log_info "Resizing root partition..."
    parted -s "$LOOP" resizepart 2 100%
    e2fsck -fy "${LOOP}p2"
    resize2fs "${LOOP}p2"

    log_info "Image prepared: ${IMAGE_PATH}"
}

verify_auto_expand() {
    local rootfs="$1"

    if [[ -f "$rootfs/boot/firmware/cmdline.txt" ]]; then
        if ! grep -q 'init_resize' "$rootfs/boot/firmware/cmdline.txt"; then
            log_warn "cmdline.txt does not reference init_resize — first-boot partition expansion may not work"
        fi
    else
        log_warn "cmdline.txt not found at $rootfs/boot/firmware/cmdline.txt"
    fi
}
