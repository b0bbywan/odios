#!/usr/bin/env bash
# provision.sh — Download odios release and run Ansible inside chroot

provision_image() {
    local rootfs="$1"
    local version="$2"

    # Resolve download URL (matches install.sh logic)
    local download_url
    if [[ "$version" == "latest" ]]; then
        log_info "Fetching latest release info..."
        download_url=$(wget -qO- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
            | grep '"browser_download_url"' \
            | grep '\.tar\.gz' \
            | head -1 \
            | cut -d'"' -f4)
    elif [[ "$version" == pr-* ]]; then
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/odio-dev.tar.gz"
    else
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/odio-${version}.tar.gz"
    fi

    if [[ -z "$download_url" ]]; then
        log_error "Could not resolve download URL for version '${version}'"
        exit 1
    fi

    log_info "Downloading odios release: ${download_url}"
    if ! wget --tries=3 -O "$rootfs/tmp/odios.tar.gz" "$download_url"; then
        rm -f "$rootfs/tmp/odios.tar.gz"
        log_error "Failed to download release archive (version '${version}' may not exist)"
        exit 1
    fi
    if ! tar tzf "$rootfs/tmp/odios.tar.gz" &>/dev/null; then
        rm -f "$rootfs/tmp/odios.tar.gz"
        log_error "Downloaded file is not a valid tar.gz archive"
        exit 1
    fi

    # Build extra vars flags
    local extra_vars_flags=""
    for var in "${ANSIBLE_EXTRA_VARS[@]}"; do
        extra_vars_flags+=" -e ${var}"
    done

    # Read odios version stamped into the archive at build time (matches install.sh)
    local odios_version
    odios_version=$(tar xzOf "$rootfs/tmp/odios.tar.gz" VERSION 2>/dev/null | tr -d '[:space:]' || true)
    if [[ -z "$odios_version" ]]; then
        log_error "VERSION file missing from archive — cannot stamp odio_version"
        exit 1
    fi
    extra_vars_flags+=" -e odio_version=${odios_version}"

    log_info "Running Ansible playbook inside chroot (odio_version=${odios_version})..."
    chroot "$rootfs" /bin/bash -e <<PROVISION
set -euo pipefail
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
mkdir -p /tmp/odios
tar xzf /tmp/odios.tar.gz -C /tmp/odios
cd /tmp/odios

PYTHONPATH="vendor" python3 vendor/bin/ansible-playbook \\
    -i ansible/inventory/localhost.yml \\
    ansible/playbook.yml \\
    ${extra_vars_flags} \\
    --connection=local
PROVISION

    log_info "Installing firstboot script and vendor-data..."
    cp "$SCRIPT_DIR/files/odios-firstboot.sh" "$rootfs/usr/local/bin/odios-firstboot.sh"
    chmod 755 "$rootfs/usr/local/bin/odios-firstboot.sh"
    cp "$SCRIPT_DIR/files/vendor-data" "$rootfs/boot/firmware/vendor-data"

    log_info "Purging unnecessary packages..."
    local purge_list
    purge_list=$(chroot "$rootfs" dpkg -l "${PURGE_PACKAGES[@]}" 2>/dev/null \
        | awk '/^ii/{print $2}' || true)
    if [[ -n "$purge_list" ]]; then
        # shellcheck disable=SC2086  # word splitting intended
        chroot "$rootfs" apt-get purge --auto-remove -y $purge_list
        log_info "Purged: ${purge_list//$'\n'/ }"
    else
        log_info "No purgeable packages found"
    fi

    log_info "Upgrading system packages..."
    chroot "$rootfs" /bin/bash -e <<'UPGRADE'
set -euo pipefail
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
apt-get update
apt-get upgrade --auto-remove -y
UPGRADE

    log_info "Cleaning up chroot..."
    chroot "$rootfs" /bin/bash -e <<'CLEANUP'
set -euo pipefail
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -f /var/log/*.log
rm -f /var/log/apt/*
rm -f /root/.bash_history
rm -f /home/odio/.bash_history
rm -f /var/lib/systemd/random-seed

# Force SSH host key regeneration on first boot
rm -f /etc/ssh/ssh_host_*
CLEANUP

    log_info "Chroot cleanup done"
}
