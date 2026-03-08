#!/bin/bash
set -euo pipefail

GITHUB_REPO="b0bbywan/odios"
ODIOS_VERSION="${ODIOS_VERSION:-latest}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORK_DIR=""

# ─── Banner ───────────────────────────────────────────────────────────────────

display_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        Audio Streaming System Installer                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

# ─── Config prompts ───────────────────────────────────────────────────────────

ask_config() {
    echo -e "${BLUE}Configuration${NC}"
    echo ""
    read -p "Target user [$USER]: " TARGET_USER
    TARGET_USER="${TARGET_USER:-$USER}"

    if id "$TARGET_USER" &>/dev/null; then
        if [[ "$TARGET_USER" == "$USER" ]]; then
            echo -e "${YELLOW}⚠ Installing for current user '$TARGET_USER' — existing config files will be backed up before modification.${NC}"
        else
            echo -e "${YELLOW}⚠ User '$TARGET_USER' already exists — existing config files will be backed up before modification.${NC}"
        fi
    else
        echo -e "${GREEN}✓ User '$TARGET_USER' will be created.${NC}"
    fi

    echo ""
    echo -e "${BLUE}Core components${NC}"
    read -p "Install PulseAudio? [Y/n]: "   INSTALL_PULSEAUDIO
    read -p "Install Bluetooth? [Y/n]: "    INSTALL_BLUETOOTH
    read -p "Install MPD? [Y/n]: "          INSTALL_MPD
    read -p "Install Odio API? [Y/n]: "     INSTALL_ODIO_API

    echo ""
    echo -e "${BLUE}Optional components${NC}"
    read -p "Install MPD disc player? [y/N]: "           INSTALL_MPD_DISCPLAYER
    read -p "Install Shairport Sync (AirPlay)? [y/N]: "  INSTALL_SHAIRPORT_SYNC
    read -p "Install Snapcast client? [y/N]: "            INSTALL_SNAPCLIENT
    read -p "Install UPnP/DLNA renderer? [y/N]: "         INSTALL_UPMPDCLI
    read -p "Install Spotifyd (Spotify Connect)? [y/N]: " INSTALL_SPOTIFYD

    if [[ "${INSTALL_MPD,,}" == "n" && "${INSTALL_MPD_DISCPLAYER,,}" == "y" ]] && command -v mpd &>/dev/null; then
        local detected_conf=""
        [[ -f "/home/${TARGET_USER}/.config/mpd/mpd.conf" ]] && detected_conf="/home/${TARGET_USER}/.config/mpd/mpd.conf"
        [[ -z "$detected_conf" && -f /etc/mpd.conf ]] && detected_conf="/etc/mpd.conf"

        echo ""
        echo -e "${BLUE}External MPD${NC}"
        read -p "MPD config path [${detected_conf}]: " MPD_CONF_PATH
        MPD_CONF_PATH="${MPD_CONF_PATH:-$detected_conf}"
    fi
    echo ""
}

prompt_for_config() {
    [[ -t 0 ]] && ask_config

    TARGET_USER="${TARGET_USER:-$USER}"  # fallback for non-interactive mode
    MPD_MUSIC_DIRECTORY="${MPD_MUSIC_DIRECTORY:-}"
    MPD_CONF_PATH="${MPD_CONF_PATH:-}"
    INSTALL_PULSEAUDIO="${INSTALL_PULSEAUDIO:-Y}"
    INSTALL_BLUETOOTH="${INSTALL_BLUETOOTH:-Y}"
    INSTALL_MPD="${INSTALL_MPD:-Y}"
    INSTALL_ODIO_API="${INSTALL_ODIO_API:-Y}"
    INSTALL_MPD_DISCPLAYER="${INSTALL_MPD_DISCPLAYER:-N}"
    INSTALL_SHAIRPORT_SYNC="${INSTALL_SHAIRPORT_SYNC:-N}"
    INSTALL_SNAPCLIENT="${INSTALL_SNAPCLIENT:-N}"
    INSTALL_UPMPDCLI="${INSTALL_UPMPDCLI:-N}"
    INSTALL_SPOTIFYD="${INSTALL_SPOTIFYD:-N}"
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────

preflight_checks() {
    local errors=0

    echo -e "${BLUE}Running pre-flight checks...${NC}"

    # OS
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}✗ Cannot detect OS (missing /etc/os-release)${NC}"
        ((errors++))
    else
        source /etc/os-release
        if [[ "$ID" =~ ^(debian|ubuntu|raspbian)$ ]]; then
            echo -e "${GREEN}✓ OS: $ID $VERSION_ID${NC}"
        else
            echo -e "${YELLOW}⚠ Unsupported OS: $ID (expected debian/ubuntu/raspbian)${NC}"
        fi
    fi

    # Architecture
    local arch
    arch=$(uname -m)
    if [[ "$arch" =~ ^(armv6l|armv7l|aarch64|x86_64)$ ]]; then
        echo -e "${GREEN}✓ Architecture: $arch${NC}"
    else
        echo -e "${RED}✗ Unsupported architecture: $arch${NC}"
        ((errors++))
    fi

    # Python >= 3.10 (required by vendored ansible-core)
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}✗ python3 not found (required)${NC}"
        ((errors++))
    else
        local py_major py_minor
        py_major=$(python3 -c 'import sys; print(sys.version_info.major)')
        py_minor=$(python3 -c 'import sys; print(sys.version_info.minor)')
        if [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
            echo -e "${RED}✗ Python 3.10+ required (found ${py_major}.${py_minor})${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✓ Python ${py_major}.${py_minor}${NC}"
        fi

        # cryptography is excluded from the vendor bundle (native extensions)
        if ! python3 -c 'import cryptography' 2>/dev/null; then
            echo -e "${RED}✗ python3-cryptography not found (install it with: sudo apt install python3-cryptography)${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✓ python3-cryptography available${NC}"
        fi
    fi

    # Sudo
    if sudo -n true 2>/dev/null; then
        echo -e "${GREEN}✓ Sudo access available${NC}"
    else
        echo -e "${YELLOW}⚠ This script requires sudo access${NC}"
        if ! sudo true; then
            echo -e "${RED}✗ Cannot obtain sudo access${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✓ Sudo access granted${NC}"
        fi
    fi

    # curl
    if ! command -v curl &>/dev/null; then
        echo -e "${RED}✗ curl not found (required to download archive)${NC}"
        ((errors++))
    else
        echo -e "${GREEN}✓ curl available${NC}"
    fi

    # Disk space (50 MB in /tmp)
    local available
    available=$(df /tmp | tail -1 | awk '{print $4}')
    if [[ $available -gt 51200 ]]; then
        echo -e "${GREEN}✓ Disk space: $((available / 1024)) MB available in /tmp${NC}"
    else
        echo -e "${RED}✗ Insufficient disk space (need 50 MB, have $((available / 1024)) MB)${NC}"
        ((errors++))
    fi

    # Systemd
    if command -v systemctl &>/dev/null; then
        echo -e "${GREEN}✓ Systemd available${NC}"
    else
        echo -e "${RED}✗ systemd not found (required for service management)${NC}"
        ((errors++))
    fi

    echo ""

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Pre-flight checks failed with $errors error(s). Aborting.${NC}"
        exit 1
    fi
}

# ─── Archive download ─────────────────────────────────────────────────────────

download_archive() {
    WORK_DIR=$(mktemp -d)

    local download_url

    if [[ "$ODIOS_VERSION" == "latest" ]]; then
        echo -e "${BLUE}Fetching latest release info...${NC}"
        download_url=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
            | grep '"browser_download_url"' \
            | grep '\.tar\.gz' \
            | head -1 \
            | cut -d'"' -f4)
    elif [[ "$ODIOS_VERSION" == pr-* ]]; then
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${ODIOS_VERSION}/odios-dev.tar.gz"
    else
        local tag="v${ODIOS_VERSION#v}"
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/odios-${tag}.tar.gz"
    fi

    if [[ -z "$download_url" ]]; then
        echo -e "${RED}✗ Could not resolve archive download URL${NC}"
        exit 1
    fi

    echo -e "${BLUE}Downloading ${download_url}...${NC}"
    curl -fsSL "$download_url" | tar -xzf - -C "$WORK_DIR"

    local version_file="${WORK_DIR}/VERSION"
    if [[ -f "$version_file" ]]; then
        echo -e "${GREEN}✓ Archive extracted ($(cat "$version_file"))${NC}"
    else
        echo -e "${GREEN}✓ Archive extracted${NC}"
    fi
    echo ""
}

# ─── Run playbook ─────────────────────────────────────────────────────────────

run_playbook() {
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    echo ""

    local extra_vars
    local hostname_var="" music_dir_var="" conf_path_var=""
    [[ -n "${TARGET_HOSTNAME:-}" ]]      && hostname_var="\"target_hostname\": \"${TARGET_HOSTNAME}\","
    [[ -n "${MPD_MUSIC_DIRECTORY:-}" ]]  && music_dir_var="\"mpd_music_directory\": \"${MPD_MUSIC_DIRECTORY}\","
    [[ -n "${MPD_CONF_PATH:-}" ]]        && conf_path_var="\"mpd_conf_path\": \"${MPD_CONF_PATH}\","

    extra_vars=$(cat <<EOF
{
  ${hostname_var}
  ${music_dir_var}
  ${conf_path_var}
  "target_user": "${TARGET_USER}",
  "install_pulseaudio": $([ "${INSTALL_PULSEAUDIO,,}" = "y" ] && echo "true" || echo "false"),
  "install_bluetooth": $([ "${INSTALL_BLUETOOTH,,}" = "y" ] && echo "true" || echo "false"),
  "install_mpd": $([ "${INSTALL_MPD,,}" = "y" ] && echo "true" || echo "false"),
  "install_odio_api": $([ "${INSTALL_ODIO_API,,}" = "y" ] && echo "true" || echo "false"),
  "install_spotifyd": $([ "${INSTALL_SPOTIFYD,,}" = "y" ] && echo "true" || echo "false"),
  "install_shairport_sync": $([ "${INSTALL_SHAIRPORT_SYNC,,}" = "y" ] && echo "true" || echo "false"),
  "install_snapclient": $([ "${INSTALL_SNAPCLIENT,,}" = "y" ] && echo "true" || echo "false"),
  "install_upmpdcli": $([ "${INSTALL_UPMPDCLI,,}" = "y" ] && echo "true" || echo "false"),
  "install_mpd_discplayer": $([ "${INSTALL_MPD_DISCPLAYER,,}" = "y" ] && echo "true" || echo "false")
}
EOF
)

    PYTHONPATH="${WORK_DIR}/vendor" \
        python3 "${WORK_DIR}/vendor/bin/ansible-playbook" \
        -i "${WORK_DIR}/ansible/inventory/localhost.yml" \
        "${WORK_DIR}/ansible/playbook.yml" \
        -e "${extra_vars}"
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        echo -e "${BLUE}Cleaning up...${NC}"
        rm -rf "${WORK_DIR}"
    fi
}

trap cleanup EXIT

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    display_banner
    echo ""

    prompt_for_config
    preflight_checks
    download_archive
    run_playbook

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
