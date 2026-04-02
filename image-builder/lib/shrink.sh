#!/usr/bin/env bash
# shrink.sh — Minimize image size and compress with xz

shrink_image() {
    local loop="$1"
    local image_path="$2"

    log_info "Zeroing free blocks for better compression..."
    zerofree "${loop}p2"

    log_info "Shrinking filesystem..."
    e2fsck -fy "${loop}p2"
    resize2fs -M "${loop}p2"

    # Read new filesystem size
    local block_count block_size fs_bytes
    block_count=$(dumpe2fs -h "${loop}p2" 2>/dev/null | awk '/Block count:/{print $3}')
    block_size=$(dumpe2fs -h "${loop}p2" 2>/dev/null | awk '/Block size:/{print $3}')
    fs_bytes=$((block_count * block_size))

    # Calculate new partition end
    local p2_start sector_size safety_margin p2_end_sector
    p2_start=$(partx -g -o START -s -n 2 "$loop" | tr -d ' ')
    sector_size=512
    # 16 MiB safety margin
    safety_margin=$((16 * 1024 * 1024 / sector_size))
    p2_end_sector=$(( p2_start + (fs_bytes / sector_size) + safety_margin ))

    log_info "Resizing partition (end sector: ${p2_end_sector})..."
    echo Yes | parted ---pretend-input-tty "$loop" resizepart 2 "${p2_end_sector}s"

    # Detach loop device
    losetup -d "$loop"
    LOOP=""  # Prevent double-detach in cleanup

    # Truncate the image file
    local truncate_bytes=$(( (p2_end_sector + 1) * sector_size ))
    log_info "Truncating image to $(( truncate_bytes / 1024 / 1024 )) MiB..."
    truncate -s "$truncate_bytes" "$image_path"

    # Compress
    log_info "Compressing with xz (level ${XZ_COMPRESSION_LEVEL}, threads ${XZ_THREADS})..."
    xz "-${XZ_COMPRESSION_LEVEL}" "-T${XZ_THREADS}" "$image_path"

    log_info "Compression complete: ${image_path}.xz"
}
