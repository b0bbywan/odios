#!/bin/bash
if [[ ! -t 0 ]]; then
    SELF=$(mktemp)
    cat > "$SELF"
    if { true </dev/tty; } 2>/dev/null; then
        exec bash "$SELF" "$@" </dev/tty
    else
        exec bash "$SELF" "$@"
    fi
fi

set -euo pipefail

GITHUB_REPO="b0bbywan/odios"
ODIOS_VERSION="${ODIOS_VERSION:-latest}"
INSTALL_MODE="${INSTALL_MODE:-live}"

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

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
║                 odio Streamer Installer                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

# ─── Config prompts ───────────────────────────────────────────────────────────

ask_config() {
    echo -e "${BLUE}Configuration${NC}"
    echo ""

    local pipewire_installed=false
    dpkg -l pipewire 2>/dev/null | grep -q '^ii' && pipewire_installed=true

    if $pipewire_installed; then
        echo -e "${YELLOW}⚠ PipeWire is installed — it will conflict with PulseAudio for the current user '$USER'.${NC}"
        echo -e "${YELLOW}  Tip: use a dedicated user (e.g. 'odios') to avoid this.${NC}"
        echo ""
    fi

    read -p "Target user [$USER]: " TARGET_USER
    TARGET_USER="${TARGET_USER:-$USER}"

    if $pipewire_installed && [[ "$TARGET_USER" == "$USER" ]]; then
        read -p "  ⚠ PipeWire conflict with '$USER' — continue anyway? [y/N]: " _pw_confirm
        [[ "${_pw_confirm,,}" == "y" ]] || { echo -e "${RED}Aborting.${NC}"; exit 1; }
    fi

    if id "$TARGET_USER" &>/dev/null; then
        echo -e "${YELLOW}⚠ User '$TARGET_USER' already exists — existing config files will be backed up.${NC}"
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

    if [[ "${INSTALL_UPMPDCLI,,}" == "y" ]]; then
        echo ""
        echo -e "${BLUE}Streaming services (upmpdcli) — leave blank to skip${NC}"
        read -p "Qobuz username: "  QOBUZ_USER
        if [[ -n "$QOBUZ_USER" ]]; then
            read -sp "Qobuz password: " QOBUZ_PASS
            echo ""
        fi
        read -p "Install Tidal support? [y/N]: " INSTALL_TIDAL
    fi

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
    [[ "$INSTALL_MODE" == "live" ]] && ask_config

    TARGET_USER="${TARGET_USER:-$USER}"
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
    INSTALL_TIDAL="${INSTALL_TIDAL:-N}"
    INSTALL_SPOTIFYD="${INSTALL_SPOTIFYD:-N}"
    QOBUZ_USER="${QOBUZ_USER:-}"
    QOBUZ_PASS="${QOBUZ_PASS:-}"
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}✗ Cannot detect OS (missing /etc/os-release)${NC}"
        return 1
    fi
    source /etc/os-release
    if [[ "$ID" =~ ^(debian|ubuntu|raspbian)$ ]]; then
        echo -e "${GREEN}✓ OS: $ID $VERSION_ID${NC}"
    else
        echo -e "${YELLOW}⚠ Unsupported OS: $ID (expected debian/ubuntu/raspbian)${NC}"
    fi
}

check_arch() {
    local arch
    arch=$(uname -m)
    if [[ "$arch" =~ ^(armv6l|armv7l|aarch64|x86_64)$ ]]; then
        echo -e "${GREEN}✓ Architecture: $arch${NC}"
    else
        echo -e "${RED}✗ Unsupported architecture: $arch${NC}"
        return 1
    fi
}

check_python() {
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}✗ python3 not found (required)${NC}"
        return 1
    fi

    local py_major py_minor
    py_major=$(python3 -c 'import sys; print(sys.version_info.major)')
    py_minor=$(python3 -c 'import sys; print(sys.version_info.minor)')
    if [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
        echo -e "${RED}✗ Python 3.10+ required (found ${py_major}.${py_minor})${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Python ${py_major}.${py_minor}${NC}"

    if ! python3 -c 'import cryptography' 2>/dev/null; then
        echo -e "${RED}✗ python3-cryptography not found (install: sudo apt install python3-cryptography)${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ python3-cryptography available${NC}"
}

check_sudo() {
    if sudo -n true 2>/dev/null; then
        echo -e "${GREEN}✓ Sudo access available${NC}"
        return 0
    fi
    echo -e "${YELLOW}⚠ This script requires sudo access${NC}"
    if sudo true; then
        echo -e "${GREEN}✓ Sudo access granted${NC}"
    else
        echo -e "${RED}✗ Cannot obtain sudo access${NC}"
        return 1
    fi
}

check_disk() {
    local available
    available=$(df /tmp | tail -1 | awk '{print $4}')
    if [[ $available -gt 51200 ]]; then
        echo -e "${GREEN}✓ Disk space: $((available / 1024)) MB available in /tmp${NC}"
    else
        echo -e "${RED}✗ Insufficient disk space (need 50 MB, have $((available / 1024)) MB)${NC}"
        return 1
    fi
}

preflight_checks() {
    local errors=0
    echo -e "${BLUE}Running pre-flight checks...${NC}"

    check_os     || ((errors++))
    check_arch   || ((errors++))
    check_python || ((errors++))
    check_sudo   || ((errors++))
    check_disk   || ((errors++))

    if command -v curl &>/dev/null; then
        echo -e "${GREEN}✓ curl available${NC}"
    else
        echo -e "${RED}✗ curl not found (required to download archive)${NC}"
        ((errors++))
    fi

    if command -v systemctl &>/dev/null; then
        echo -e "${GREEN}✓ Systemd available${NC}"
    else
        echo -e "${RED}✗ systemd not found (required for service management)${NC}"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Pre-flight checks failed with $errors error(s). Aborting.${NC}"
        exit 1
    fi
    echo ""
}

# ─── Dependencies ─────────────────────────────────────────────────────────────

install_dependencies() {
    if ! python3 -c 'import jinja2' 2>/dev/null; then
        echo -e "${BLUE}Installing python3-jinja2...${NC}"
        sudo apt-get update -qq
        sudo apt-get install -y python3-jinja2
        echo -e "${GREEN}✓ python3-jinja2 installed${NC}"
    else
        echo -e "${GREEN}✓ python3-jinja2 available${NC}"
    fi
    echo ""
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
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${ODIOS_VERSION}/odios-${ODIOS_VERSION}.tar.gz"
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

bool() { [[ "${1,,}" == "y" ]] && echo "true" || echo "false"; }

run_playbook() {
    echo -e "${BLUE}Running Ansible playbook...${NC}"
    echo ""

    local optional_vars=""
    [[ -n "${TARGET_HOSTNAME:-}" ]]   && optional_vars+="\"target_hostname\": \"${TARGET_HOSTNAME}\","
    [[ -n "${MPD_MUSIC_DIRECTORY}" ]] && optional_vars+="\"mpd_music_directory\": \"${MPD_MUSIC_DIRECTORY}\","
    [[ -n "${MPD_CONF_PATH}" ]]       && optional_vars+="\"mpd_conf_path\": \"${MPD_CONF_PATH}\","
    [[ -n "${QOBUZ_USER}" ]]          && optional_vars+="\"qobuz_user\": \"${QOBUZ_USER}\", \"qobuz_pass\": \"${QOBUZ_PASS}\","

    local extra_vars
    extra_vars=$(cat <<EOF
{
  ${optional_vars}
  "install_mode":           "${INSTALL_MODE}",
  "target_user":            "${TARGET_USER}",
  "install_pulseaudio":     $(bool "$INSTALL_PULSEAUDIO"),
  "install_bluetooth":      $(bool "$INSTALL_BLUETOOTH"),
  "install_mpd":            $(bool "$INSTALL_MPD"),
  "install_odio_api":       $(bool "$INSTALL_ODIO_API"),
  "install_spotifyd":       $(bool "$INSTALL_SPOTIFYD"),
  "install_shairport_sync": $(bool "$INSTALL_SHAIRPORT_SYNC"),
  "install_snapclient":     $(bool "$INSTALL_SNAPCLIENT"),
  "install_upmpdcli":       $(bool "$INSTALL_UPMPDCLI"),
  "install_tidal":          $(bool "$INSTALL_TIDAL"),
  "install_mpd_discplayer": $(bool "$INSTALL_MPD_DISCPLAYER")
}
EOF
)

    local t_start t_end elapsed
    t_start=$(date +%s)

    PYTHONPATH="${WORK_DIR}/vendor" \
        python3 "${WORK_DIR}/vendor/bin/ansible-playbook" \
        -i "${WORK_DIR}/ansible/inventory/localhost.yml" \
        "${WORK_DIR}/ansible/playbook.yml" \
        -e "${extra_vars}"

    t_end=$(date +%s)
    elapsed=$((t_end - t_start))
    echo ""
    echo -e "${BLUE}Playbook completed in $((elapsed / 60))m $((elapsed % 60))s${NC}"
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────

cleanup() {
    [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]] || return 0
    echo -e "${BLUE}Cleaning up...${NC}"
    rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    display_banner
    echo ""
    prompt_for_config
    preflight_checks
    install_dependencies
    download_archive
    run_playbook

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
