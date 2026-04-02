#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/image.sh"
source "$SCRIPT_DIR/lib/chroot.sh"
source "$SCRIPT_DIR/lib/provision.sh"
source "$SCRIPT_DIR/lib/shrink.sh"

# ─── Defaults ────────────────────────────────────────────────────────────────

COMMAND=""
ARCH=""
VERSION=""
WORKDIR="/tmp/odios-build"
OUTPUT_DIR="./output"
KEEP="false"
SKIP_DOWNLOAD="false"
SKIP_SHRINK="false"

# Global state for cleanup trap
LOOP=""
ROOTFS=""
IMAGE_PATH=""

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: sudo $0 <command> [options]

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

Examples:
  sudo $0 build --arch armhf --version 2026.3.0
  sudo $0 build --arch arm64 --version pr-5 --keep
  sudo $0 clean --workdir /tmp/odios-build
EOF
    exit 1
}

# ─── Parse arguments ────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && usage

COMMAND="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)         ARCH="$2"; shift 2 ;;
        --version)      VERSION="$2"; shift 2 ;;
        --workdir)      WORKDIR="$2"; shift 2 ;;
        --output)       OUTPUT_DIR="$2"; shift 2 ;;
        --keep)         KEEP="true"; shift ;;
        --skip-download) SKIP_DOWNLOAD="true"; shift ;;
        --skip-shrink)  SKIP_SHRINK="true"; shift ;;
        *)              log_error "Unknown option: $1"; usage ;;
    esac
done

# ─── Cleanup trap ────────────────────────────────────────────────────────────

trap cleanup EXIT

# ─── Commands ────────────────────────────────────────────────────────────────

case "$COMMAND" in
    build)
        [[ -z "$ARCH" ]] && { log_error "--arch is required"; usage; }
        [[ -z "$VERSION" ]] && { log_error "--version is required"; usage; }

        check_root
        check_deps

        mkdir -p "$WORKDIR"
        check_disk_space "$WORKDIR"

        log_info "Building odios ${VERSION} for ${ARCH}"

        # 1. Download
        download_base_image "$ARCH" "$WORKDIR"

        # 2. Prepare (copy, grow, losetup, resize partition)
        prepare_image "$ARCH" "$WORKDIR"
        # Sets global: LOOP, IMAGE_PATH

        # 3. Mount chroot
        ROOTFS="${WORKDIR}/rootfs"
        mount_chroot "$LOOP" "$ROOTFS"
        setup_qemu "$ARCH" "$ROOTFS"

        # 4. Provision
        provision_image "$ROOTFS" "$VERSION"

        # 5. Verify auto-expand is intact
        verify_auto_expand "$ROOTFS"

        # 6. Unmount (but keep loop attached for shrink)
        unmount_chroot "$ROOTFS"
        ROOTFS=""  # Prevent cleanup from re-unmounting

        # 7. Shrink + compress
        if [[ "$SKIP_SHRINK" != "true" ]]; then
            shrink_image "$LOOP" "$IMAGE_PATH"
            # shrink_image detaches loop and compresses
        else
            losetup -d "$LOOP"
            LOOP=""
            log_info "Compressing (skipping shrink)..."
            xz "-${XZ_COMPRESSION_LEVEL}" "-T${XZ_THREADS}" "$IMAGE_PATH"
        fi

        # 8. Move to output
        mkdir -p "$OUTPUT_DIR"
        FINAL_NAME="odios-${VERSION}-${ARCH}.img.xz"
        mv "${IMAGE_PATH}.xz" "${OUTPUT_DIR}/${FINAL_NAME}"

        log_info "Done: ${OUTPUT_DIR}/${FINAL_NAME}"
        log_info "Size: $(du -h "${OUTPUT_DIR}/${FINAL_NAME}" | cut -f1)"

        # Clean workdir unless --keep
        if [[ "$KEEP" != "true" ]]; then
            rm -rf "$WORKDIR"
        fi
        ;;

    clean)
        log_info "Cleaning ${WORKDIR}..."
        rm -rf "$WORKDIR"
        log_info "Done"
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac
