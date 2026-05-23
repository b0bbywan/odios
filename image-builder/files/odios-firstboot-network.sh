#!/usr/bin/env bash
# odios-firstboot-network.sh — Network-dependent post cloud-init fixups
# Runs once after network-online + avahi-daemon are up. Discovers the
# snapcast server via snapclientmpris and injects the snapweb URL into
# odio-api's config so the UI can link to it.
set -euo pipefail

MARKER="/var/lib/odios/firstboot-network-done"
ODIOS_USER="odio"
ODIOS_HOME="/home/${ODIOS_USER}"
ODIO_API_CONF="${ODIOS_HOME}/.config/odio-api/config.yaml"

echo "odios-firstboot-network: started at $(date)"

# ─── Discover snapweb URL and inject into odio-api config ───────────────────

if ! command -v snapclientmpris &>/dev/null; then
    echo "odios-firstboot-network: snapclientmpris not installed, skipping snapweb discovery"
elif [[ ! -f "$ODIO_API_CONF" ]]; then
    echo "odios-firstboot-network: ${ODIO_API_CONF} not found, skipping snapweb discovery"
else
    echo "odios-firstboot-network: discovering snapweb URL via snapclientmpris..."
    discover_output=$(runuser -u "$ODIOS_USER" -- snapclientmpris --discover 2>&1 || true)
    # Match `snapweb:` anchored at line start, allow zero-or-more spaces (mirrors
    # the ansible-side guard in roles/odio_api/tasks/main.yml), keep only the
    # first match (-m1) so multiple snapcast servers can't produce a multi-line
    # value that would later corrupt the YAML edit.
    snapweb_url=$(printf '%s\n' "$discover_output" \
        | grep -m1 -oE '^snapweb:[[:space:]]*[^[:space:]]+' \
        | sed -E 's/^snapweb:[[:space:]]*//' || true)
    if [[ -z "$snapweb_url" ]]; then
        echo "odios-firstboot-network: no snapweb URL discovered, output was:"
        echo "$discover_output" | sed 's/^/  /'
    elif [[ ! "$snapweb_url" =~ ^https?://[^[:space:]]+$ ]]; then
        echo "odios-firstboot-network: discarding invalid snapweb URL '${snapweb_url}', output was:"
        echo "$discover_output" | sed 's/^/  /'
        snapweb_url=""
    fi
    if [[ -n "$snapweb_url" ]]; then
        echo "odios-firstboot-network: snapweb URL = ${snapweb_url}"
        runuser -u "$ODIOS_USER" -- env SNAPWEB_URL="$snapweb_url" \
            yq -yi '(.systemd.user[] | select(.name == "snapclient.service")).url = env.SNAPWEB_URL' \
            "$ODIO_API_CONF"
        echo "odios-firstboot-network: restarting odio-api..."
        runuser -u "$ODIOS_USER" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$ODIOS_USER")" \
            systemctl --user restart odio-api.service || true
    fi
fi

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
echo "odios-firstboot-network: done"
