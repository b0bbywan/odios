#!/usr/bin/env bash
# odios-firstboot.sh — Post cloud-init fixups for odios images
set -euo pipefail

IMAGE_HOSTNAME="odio"
CURRENT_HOSTNAME=$(hostname)
ODIOS_USER="odio"
ODIOS_HOME="/home/${ODIOS_USER}"

# Required groups for odios services
ODIOS_GROUPS="audio,users,input,plugdev,bluetooth,rfkill,cdrom"

RESTART_BLUETOOTH=false

echo "odios-firstboot: started at $(date)"
echo "odios-firstboot: IMAGE_HOSTNAME=${IMAGE_HOSTNAME}"
echo "odios-firstboot: CURRENT_HOSTNAME=${CURRENT_HOSTNAME}"
echo "odios-firstboot: ODIOS_HOME=${ODIOS_HOME}"

# ─── Restore odios user groups (cloud-init may have reset them) ──────────────

if id "$ODIOS_USER" &>/dev/null; then
    echo "odios-firstboot: ensuring ${ODIOS_USER} is in required groups..."
    usermod -aG "$ODIOS_GROUPS" "$ODIOS_USER"
    echo "odios-firstboot: groups set: $(id "$ODIOS_USER")"
else
    echo "odios-firstboot: WARNING - user ${ODIOS_USER} does not exist"
fi

# ─── Unblock bluetooth ──────────────────────────────────────────────────────

if command -v rfkill &>/dev/null && rfkill list bluetooth | grep -q "Soft blocked: yes"; then
    echo "odios-firstboot: unblocking bluetooth..."
    rfkill unblock bluetooth
    RESTART_BLUETOOTH=true
else
    echo "odios-firstboot: bluetooth not blocked, skipping rfkill"
fi

# ─── Update service names if hostname changed ───────────────────────────────

if [[ "$CURRENT_HOSTNAME" != "$IMAGE_HOSTNAME" ]]; then
    echo "odios-firstboot: hostname changed to '${CURRENT_HOSTNAME}', updating service configs..."

    # Bluetooth: /etc/bluetooth/main.conf
    if [[ -f /etc/bluetooth/main.conf ]]; then
        echo "odios-firstboot: updating bluetooth Name..."
        sed -i "s/^Name = ${IMAGE_HOSTNAME}$/Name = ${CURRENT_HOSTNAME}/" /etc/bluetooth/main.conf
        echo "odios-firstboot: bluetooth result: $(grep '^Name' /etc/bluetooth/main.conf)"
        RESTART_BLUETOOTH=true
    else
        echo "odios-firstboot: /etc/bluetooth/main.conf not found"
    fi

    # Spotifyd: ~/.config/spotifyd/spotifyd.conf
    SPOTIFYD_CONF="${ODIOS_HOME}/.config/spotifyd/spotifyd.conf"
    if [[ -f "$SPOTIFYD_CONF" ]]; then
        echo "odios-firstboot: updating spotifyd device_name..."
        sed -i "s/^device_name = \"${IMAGE_HOSTNAME}\"$/device_name = \"${CURRENT_HOSTNAME}\"/" "$SPOTIFYD_CONF"
        echo "odios-firstboot: spotifyd result: $(grep '^device_name' "$SPOTIFYD_CONF")"
    else
        echo "odios-firstboot: ${SPOTIFYD_CONF} not found"
    fi

    # upmpdcli: ~/.config/upmpdcli/upmpdcli.conf
    UPMPDCLI_CONF="${ODIOS_HOME}/.config/upmpdcli/upmpdcli.conf"
    if [[ -f "$UPMPDCLI_CONF" ]]; then
        echo "odios-firstboot: updating upmpdcli avfriendlyname..."
        sed -i "s/^avfriendlyname = UpMpd\/AV-${IMAGE_HOSTNAME}$/avfriendlyname = UpMpd\/AV-${CURRENT_HOSTNAME}/" "$UPMPDCLI_CONF"
        echo "odios-firstboot: upmpdcli result: $(grep '^avfriendlyname' "$UPMPDCLI_CONF")"
    else
        echo "odios-firstboot: ${UPMPDCLI_CONF} not found"
    fi
else
    echo "odios-firstboot: hostname unchanged (${CURRENT_HOSTNAME}), skipping config updates"
fi

# ─── Restart bluetooth if needed ───────────────────────────────────────────

if [[ "$RESTART_BLUETOOTH" == true ]] && systemctl is-active --quiet bluetooth; then
    echo "odios-firstboot: restarting bluetooth..."
    systemctl restart bluetooth
fi

echo "odios-firstboot: done"
