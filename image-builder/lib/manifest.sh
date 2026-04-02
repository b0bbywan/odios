#!/usr/bin/env bash
# manifest.sh — Generate manifest fragment for Pi Imager integration

generate_manifest_entry() {
    local output_dir="$1"
    local version="$2"
    local arch="$3"

    local xz_name="odios-${version}-${arch}.img.xz"
    local xz_path="${output_dir}/${xz_name}"
    local entry_path="${output_dir}/odios-${version}-${arch}.json"

    if [[ ! -f "$xz_path" ]]; then
        log_error "Cannot generate manifest entry: ${xz_path} not found"
        return 1
    fi

    local download_sha256 download_size
    download_sha256=$(sha256sum "$xz_path" | awk '{print $1}')
    download_size=$(stat -c%s "$xz_path")

    if [[ -z "${EXTRACT_SHA256:-}" ]] || [[ -z "${EXTRACT_SIZE:-}" ]]; then
        log_warn "Uncompressed image checksums not available, manifest entry will be incomplete"
        EXTRACT_SHA256=""
        EXTRACT_SIZE=0
    fi

    local devices architecture
    case "$arch" in
        armhf)
            devices='["pi1-32bit", "pi2-32bit", "pi3-32bit"]'
            architecture="armhf"
            ;;
        arm64)
            devices='["pi3-64bit", "pi4-64bit", "pi5-64bit"]'
            architecture="arm64"
            ;;
    esac

    local release_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${xz_name}"
    local release_date
    release_date=$(date +%Y-%m-%d)

    log_info "Generating manifest entry: ${entry_path}"
    cat > "$entry_path" <<EOF
{
  "name": "odio (${arch})",
  "description": "Audiophile streaming distribution for Raspberry Pi",
  "url": "${release_url}",
  "icon": "https://beta.odio.love/favicon.svg",
  "website": "https://beta.odio.love",
  "release_date": "${release_date}",
  "extract_size": ${EXTRACT_SIZE},
  "extract_sha256": "${EXTRACT_SHA256}",
  "image_download_size": ${download_size},
  "image_download_sha256": "${download_sha256}",
  "init_format": "cloudinit-rpi",
  "architecture": "${architecture}",
  "devices": ${devices}
}
EOF

    log_info "Manifest entry generated"
}
