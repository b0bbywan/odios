#!/bin/bash
set -euo pipefail

# Configuration
INSTALLER_VERSION="1.0.0"
MIN_ANSIBLE_VERSION="2.9"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
display_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        Audio Streaming System Installer                  ║
║        Version: 1.0.0                                     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

# Interactive prompts
prompt_for_config() {
    echo -e "${BLUE}Configuration${NC}"
    echo ""

    read -p "Hostname for service advertising [$(hostname)]: " TARGET_HOSTNAME
    TARGET_HOSTNAME=${TARGET_HOSTNAME:-$(hostname)}

    read -p "Target user [$USER]: " TARGET_USER
    TARGET_USER=${TARGET_USER:-$USER}

    echo ""
    echo -e "${BLUE}Optional components${NC}"

    read -p "Install Spotifyd (Spotify Connect)? [y/N]: " INSTALL_SPOTIFYD
    INSTALL_SPOTIFYD=${INSTALL_SPOTIFYD:-N}

    read -p "Install Shairport Sync (AirPlay)? [y/N]: " INSTALL_SHAIRPORT_SYNC
    INSTALL_SHAIRPORT_SYNC=${INSTALL_SHAIRPORT_SYNC:-N}

    read -p "Install Snapcast client? [y/N]: " INSTALL_SNAPCLIENT
    INSTALL_SNAPCLIENT=${INSTALL_SNAPCLIENT:-N}

    read -p "Install UPnP/DLNA renderer? [y/N]: " INSTALL_UPMPDCLI
    INSTALL_UPMPDCLI=${INSTALL_UPMPDCLI:-N}

    read -p "Install MPD disc player? [y/N]: " INSTALL_MPD_DISCPLAYER
    INSTALL_MPD_DISCPLAYER=${INSTALL_MPD_DISCPLAYER:-N}

    echo ""
}

# Pre-flight checks
preflight_checks() {
    local errors=0

    echo -e "${BLUE}Running pre-flight checks...${NC}"

    # OS check
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}✗ ERROR: Cannot detect OS (missing /etc/os-release)${NC}"
        ((errors++))
    else
        source /etc/os-release
        if [[ "$ID" =~ ^(debian|ubuntu|raspbian)$ ]]; then
            echo -e "${GREEN}✓ OS: $ID $VERSION_ID${NC}"
        else
            echo -e "${YELLOW}⚠ WARNING: Unsupported OS: $ID (expected debian/ubuntu/raspbian)${NC}"
        fi
    fi

    # Architecture check
    local arch=$(uname -m)
    if [[ "$arch" =~ ^(armv6l|armv7l|aarch64|x86_64)$ ]]; then
        echo -e "${GREEN}✓ Architecture: $arch${NC}"
    else
        echo -e "${RED}✗ ERROR: Unsupported architecture: $arch${NC}"
        ((errors++))
    fi

    # Sudo check
    if sudo -n true 2>/dev/null; then
        echo -e "${GREEN}✓ Sudo access available${NC}"
    else
        echo -e "${YELLOW}⚠ This script requires sudo access${NC}"
        if ! sudo true; then
            echo -e "${RED}✗ ERROR: Cannot obtain sudo access${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✓ Sudo access granted${NC}"
        fi
    fi

    # Network check
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        echo -e "${GREEN}✓ Network connectivity${NC}"
    else
        echo -e "${YELLOW}⚠ WARNING: Network connectivity issues detected${NC}"
    fi

    # Disk space check
    local available=$(df /tmp | tail -1 | awk '{print $4}')
    if [[ $available -gt 512000 ]]; then
        echo -e "${GREEN}✓ Disk space: $((available/1024)) MB available${NC}"
    else
        echo -e "${RED}✗ ERROR: Insufficient disk space (need 500MB, have $((available/1024))MB)${NC}"
        ((errors++))
    fi

    # Systemd check
    if command -v systemctl &>/dev/null; then
        echo -e "${GREEN}✓ Systemd available${NC}"
    else
        echo -e "${RED}✗ ERROR: systemd not found (required for service management)${NC}"
        ((errors++))
    fi

    echo ""

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Pre-flight checks failed with $errors error(s). Aborting.${NC}"
        exit 1
    fi
}

# Install Ansible
install_ansible() {
    if command -v ansible-playbook &>/dev/null; then
        local version=$(ansible-playbook --version | head -n1 | awk '{print $2}')
        echo -e "${GREEN}✓ Ansible already installed (version $version)${NC}"
        return 0
    fi

    echo -e "${BLUE}Installing Ansible...${NC}"

    if sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible; then
        echo -e "${GREEN}✓ Ansible installed via apt${NC}"
    else
        echo -e "${YELLOW}⚠ Falling back to pip installation${NC}"
        sudo apt-get install -y python3-pip
        sudo pip3 install ansible
        echo -e "${GREEN}✓ Ansible installed via pip${NC}"
    fi
}

# Extract embedded playbook
extract_playbook() {
    TEMP_DIR=$(mktemp -d)
    echo "$TEMP_DIR"

    # This section will be replaced by build.sh with embedded base64 playbook
    # __PLAYBOOK_ARCHIVE__
}

# Run Ansible playbook
run_playbook() {
    local playbook_dir="$1"

    echo -e "${BLUE}Running Ansible playbook...${NC}"
    echo ""

    # Build extra-vars JSON
    local extra_vars=$(cat <<EOF
{
  "target_hostname": "${TARGET_HOSTNAME}",
  "target_user": "${TARGET_USER}",
  "install_spotifyd": $([ "${INSTALL_SPOTIFYD,,}" = "y" ] && echo "true" || echo "false"),
  "install_shairport_sync": $([ "${INSTALL_SHAIRPORT_SYNC,,}" = "y" ] && echo "true" || echo "false"),
  "install_snapclient": $([ "${INSTALL_SNAPCLIENT,,}" = "y" ] && echo "true" || echo "false"),
  "install_upmpdcli": $([ "${INSTALL_UPMPDCLI,,}" = "y" ] && echo "true" || echo "false"),
  "install_mpd_discplayer": $([ "${INSTALL_MPD_DISCPLAYER,,}" = "y" ] && echo "true" || echo "false")
}
EOF
)

    ansible-playbook \
        -i "${playbook_dir}/inventory/localhost.yml" \
        "${playbook_dir}/playbook.yml" \
        -e "${extra_vars}"
}

# Cleanup
cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        echo -e "${BLUE}Cleaning up temporary files...${NC}"
        rm -rf "${TEMP_DIR}"
    fi
}

trap cleanup EXIT

# Main
main() {
    display_banner
    echo ""

    prompt_for_config
    preflight_checks
    install_ansible

    echo ""
    PLAYBOOK_DIR=$(extract_playbook)
    run_playbook "${PLAYBOOK_DIR}"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Services will start automatically on next reboot."
    echo "To start services now, run:"
    echo "  systemctl --user start pulseaudio pulse-tcp mpd"
    echo ""
}

main "$@"
