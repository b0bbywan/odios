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
CURRENT_USER="${USER:-$(id -un)}"   # resilient to unset USER (docker exec, cron, …)

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
        echo -e "${YELLOW}⚠ PipeWire is installed — it will conflict with PulseAudio for the current user '${CURRENT_USER}'.${NC}"
        echo -e "${YELLOW}  Tip: use a dedicated user (e.g. 'odio') to avoid this.${NC}"
        echo ""
    fi

    read -rp "Target user [${CURRENT_USER}]: " TARGET_USER
    TARGET_USER="${TARGET_USER:-${CURRENT_USER}}"

    if $pipewire_installed && [[ "$TARGET_USER" == "${CURRENT_USER}" ]]; then
        read -rp "  ⚠ PipeWire conflict with '$TARGET_USER' — continue anyway? [y/N]: " _pw_confirm
        [[ $(bool "${_pw_confirm:-N}") == "true" ]] || { echo -e "${RED}Aborting.${NC}"; exit 1; }
    fi

    if id "$TARGET_USER" &>/dev/null; then
        echo -e "${YELLOW}⚠ User '$TARGET_USER' already exists — existing config files will be backed up.${NC}"
    else
        echo -e "${GREEN}✓ User '$TARGET_USER' will be created.${NC}"
    fi

    echo ""
    read -rp "Install PulseAudio? [Y/n]: "                 INSTALL_PULSEAUDIO
    read -rp "Install Bluetooth? [Y/n]: "                  INSTALL_BLUETOOTH
    read -rp "Install MPD? [Y/n]: "                        INSTALL_MPD
    read -rp "Install MPD disc player? [Y/n]: "            INSTALL_MPD_DISCPLAYER
    read -rp "Install Odio API? [Y/n]: "                   INSTALL_ODIO_API
    read -rp "Install Shairport Sync (AirPlay)? [Y/n]: "   INSTALL_SHAIRPORT_SYNC
    read -rp "Install Snapcast client? [Y/n]: "            INSTALL_SNAPCLIENT
    read -rp "Install UPnP/DLNA renderer? [Y/n]: "         INSTALL_UPMPDCLI
    read -rp "Install myMPD (web UI)? [Y/n]: "             INSTALL_MYMPD
    read -rp "Install Spotifyd (Spotify Connect)? [Y/n]: " INSTALL_SPOTIFYD
    read -rp "Install branding (odio-motd login banner, hushlogin)? [Y/n]: " INSTALL_BRANDING

    if [[ "${INSTALL_UPMPDCLI:-Y}" != "n" && "${INSTALL_UPMPDCLI:-Y}" != "N" ]]; then
        echo ""
        echo -e "${BLUE}Streaming plugins (upmpdcli) — Qobuz/Tidal need credentials added to ~/.config/upmpdcli/upmpdcli.conf after install${NC}"
        read -rp "Install Qobuz support? [Y/n]: "  INSTALL_QOBUZ
        read -rp "Install Tidal support? [Y/n]: "  INSTALL_TIDAL
        read -rp "Install UPnP web radios? [Y/n]: " INSTALL_UPNPWEBRADIOS
    fi

    if [[ "${INSTALL_MPD,,}" == "n" && "${INSTALL_MPD_DISCPLAYER,,}" == "y" ]] && command -v mpd &>/dev/null; then
        local detected_conf=""
        [[ -f "/home/${TARGET_USER}/.config/mpd/mpd.conf" ]] && detected_conf="/home/${TARGET_USER}/.config/mpd/mpd.conf"
        [[ -z "$detected_conf" && -f /etc/mpd.conf ]] && detected_conf="/etc/mpd.conf"

        echo ""
        echo -e "${BLUE}External MPD${NC}"
        read -rp "MPD config path [${detected_conf}]: " MPD_CONF_PATH
        MPD_CONF_PATH="${MPD_CONF_PATH:-$detected_conf}"
    fi
    echo ""
}

prompt_for_config() {
    [[ "$INSTALL_MODE" == "live" && -z "${TARGET_USER:-}" ]] && ask_config

    TARGET_USER="${TARGET_USER:-${CURRENT_USER}}"
    MPD_MUSIC_DIRECTORY="${MPD_MUSIC_DIRECTORY:-}"
    MPD_CONF_PATH="${MPD_CONF_PATH:-}"
    INSTALL_PULSEAUDIO="${INSTALL_PULSEAUDIO:-Y}"
    INSTALL_BLUETOOTH="${INSTALL_BLUETOOTH:-Y}"
    INSTALL_MPD="${INSTALL_MPD:-Y}"
    INSTALL_ODIO_API="${INSTALL_ODIO_API:-Y}"
    INSTALL_MPD_DISCPLAYER="${INSTALL_MPD_DISCPLAYER:-Y}"
    INSTALL_SHAIRPORT_SYNC="${INSTALL_SHAIRPORT_SYNC:-Y}"
    INSTALL_SNAPCLIENT="${INSTALL_SNAPCLIENT:-Y}"
    INSTALL_UPMPDCLI="${INSTALL_UPMPDCLI:-Y}"
    INSTALL_MYMPD="${INSTALL_MYMPD:-Y}"
    INSTALL_TIDAL="${INSTALL_TIDAL:-Y}"
    INSTALL_QOBUZ="${INSTALL_QOBUZ:-Y}"
    INSTALL_SPOTIFYD="${INSTALL_SPOTIFYD:-Y}"
    INSTALL_UPNPWEBRADIOS="${INSTALL_UPNPWEBRADIOS:-Y}"
    INSTALL_BRANDING="${INSTALL_BRANDING:-Y}"

    # Smart-upgrade hint: odio-upgrade exports RUN_<role>=N for roles whose
    # target version matches the installed version. Internal-only — fresh
    # installs never set these, so RUN_X collapses to INSTALL_X.
    RUN_PULSEAUDIO="${RUN_PULSEAUDIO:-$INSTALL_PULSEAUDIO}"
    RUN_BLUETOOTH="${RUN_BLUETOOTH:-$INSTALL_BLUETOOTH}"
    RUN_MPD="${RUN_MPD:-$INSTALL_MPD}"
    RUN_ODIO_API="${RUN_ODIO_API:-$INSTALL_ODIO_API}"
    RUN_MPD_DISCPLAYER="${RUN_MPD_DISCPLAYER:-$INSTALL_MPD_DISCPLAYER}"
    RUN_SHAIRPORT_SYNC="${RUN_SHAIRPORT_SYNC:-$INSTALL_SHAIRPORT_SYNC}"
    RUN_SNAPCLIENT="${RUN_SNAPCLIENT:-$INSTALL_SNAPCLIENT}"
    RUN_UPMPDCLI="${RUN_UPMPDCLI:-$INSTALL_UPMPDCLI}"
    RUN_SPOTIFYD="${RUN_SPOTIFYD:-$INSTALL_SPOTIFYD}"
    RUN_BRANDING="${RUN_BRANDING:-$INSTALL_BRANDING}"
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}✗ Cannot detect OS (missing /etc/os-release)${NC}"
        return 1
    fi
    # shellcheck source=/dev/null
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

}

NEEDS_BECOME_PASS=false

check_sudo() {
    if sudo -n true 2>/dev/null; then
        echo -e "${GREEN}✓ Sudo access available${NC}"
        return 0
    fi
    echo -e "${YELLOW}⚠ This script requires sudo access${NC}"
    if sudo true; then
        NEEDS_BECOME_PASS=true
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
    local pkgs=()
    python3 -c 'import jinja2' 2>/dev/null      || pkgs+=(python3-jinja2)
    python3 -c 'import cryptography' 2>/dev/null || pkgs+=(python3-cryptography)

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        echo -e "${BLUE}Installing ${pkgs[*]}...${NC}"
        local y; [[ "$INSTALL_MODE" == "image" ]] && y="-y" || y=""
        sudo apt-get update -qq
        sudo apt-get install $y "${pkgs[@]}"
        echo -e "${GREEN}✓ ${pkgs[*]} installed${NC}"
    else
        echo -e "${GREEN}✓ python3-jinja2 and python3-cryptography available${NC}"
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
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${ODIOS_VERSION}/odio-dev.tar.gz"
    else
        download_url="https://github.com/${GITHUB_REPO}/releases/download/${ODIOS_VERSION}/odio-${ODIOS_VERSION}.tar.gz"
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

    local extra_vars
    extra_vars=$(cat <<EOF
{
  ${optional_vars}
  "odio_version":           "$(cat "${WORK_DIR}/VERSION" 2>/dev/null || echo "unknown")",
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
  "install_mympd":          $(bool "$INSTALL_MYMPD"),
  "install_tidal":          $(bool "$INSTALL_TIDAL"),
  "install_qobuz":          $(bool "$INSTALL_QOBUZ"),
  "install_upnpwebradios":  $(bool "$INSTALL_UPNPWEBRADIOS"),
  "install_mpd_discplayer": $(bool "$INSTALL_MPD_DISCPLAYER"),
  "install_branding":       $(bool "$INSTALL_BRANDING"),
  "run_pulseaudio":         $(bool "$RUN_PULSEAUDIO"),
  "run_bluetooth":          $(bool "$RUN_BLUETOOTH"),
  "run_mpd":                $(bool "$RUN_MPD"),
  "run_odio_api":           $(bool "$RUN_ODIO_API"),
  "run_spotifyd":           $(bool "$RUN_SPOTIFYD"),
  "run_shairport_sync":     $(bool "$RUN_SHAIRPORT_SYNC"),
  "run_snapclient":         $(bool "$RUN_SNAPCLIENT"),
  "run_upmpdcli":           $(bool "$RUN_UPMPDCLI"),
  "run_mpd_discplayer":     $(bool "$RUN_MPD_DISCPLAYER"),
  "run_branding":           $(bool "$RUN_BRANDING")
}
EOF
)

    local t_start t_end elapsed
    t_start=$(date +%s)

    local become_flag=""
    $NEEDS_BECOME_PASS && become_flag="--ask-become-pass"

    # shellcheck disable=SC2086
    PYTHONPATH="${WORK_DIR}/vendor" \
        python3 "${WORK_DIR}/vendor/bin/ansible-playbook" \
        -i "${WORK_DIR}/ansible/inventory/localhost.yml" \
        "${WORK_DIR}/ansible/playbook.yml" \
        ${become_flag} \
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
