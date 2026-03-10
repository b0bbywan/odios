#!/bin/bash
set -e

CONTAINER_NAME="odios-test"
GITHUB_REPO="b0bbywan/odios"
_DEFAULT_TAG="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo latest)"
REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/${GITHUB_REPO}/test:${_DEFAULT_TAG}}"
BUILD_LOCAL=false

# ─── Helpers ──────────────────────────────────────────────────────────────────

resolve_image() {
    if [[ "${BUILD_LOCAL}" == "true" ]]; then
        echo "=== Building image locally ==="
        docker build -t "${REMOTE_IMAGE}" -f Dockerfile.test .
    else
        echo "=== Pulling image ==="
        docker pull "${REMOTE_IMAGE}" || {
            echo "Pull failed, falling back to local build..."
            docker build -t "${REMOTE_IMAGE}" -f Dockerfile.test .
        }
    fi
}

start_container() {
    resolve_image

    echo "=== Starting container with systemd ==="
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --privileged \
      --cgroupns=host \
      --user root \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      "${REMOTE_IMAGE}"

    echo "=== Waiting for systemd ==="
    sleep 3
}

install_sh_url() {
    local tag="$1"
    if [[ "$tag" == "latest" ]]; then
        echo "https://github.com/${GITHUB_REPO}/releases/latest/download/install.sh"
    else
        echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/install.sh"
    fi
}

run_install() {
    local tag="$1"
    local exec_user="${2:-}"  # empty = root
    local url
    url=$(install_sh_url "$tag")

    local user_flag=()
    [[ -n "$exec_user" ]] && user_flag=(-u "$exec_user")

    echo "=== curl | bash ${exec_user:+as $exec_user }(${url}) ==="
    docker exec "${user_flag[@]}" "${CONTAINER_NAME}" \
      env \
        TARGET_USER=odios \
        INSTALL_SPOTIFYD=Y \
        INSTALL_SHAIRPORT_SYNC=Y \
        INSTALL_SNAPCLIENT=Y \
        INSTALL_UPMPDCLI=Y \
        INSTALL_TIDAL=Y \
        INSTALL_MPD_DISCPLAYER=Y \
        ODIOS_VERSION="${tag}" \
      bash -c "curl -fsSL '${url}' | bash"
}

# ─── Actions ──────────────────────────────────────────────────────────────────

while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --build) BUILD_LOCAL=true ;;
      --help|-h)
        echo "Usage: $0 [--build] [action] [args...]"
        echo ""
        echo "  --build            - Force local image build instead of pulling from GHCR"
        echo ""
        echo "  test               - Pull/build + start + run playbook directly (default)"
        echo "  shell              - Shell into running container"
        echo "  rerun              - Re-run playbook without restart"
        echo "  clean              - Remove container"
        echo "  install [TAG]      - Test install.sh as user odios (sudo)"
        echo "  install-root [TAG] - Test install.sh as root, TARGET_USER=odios"
        echo "                       TAG examples: latest, pr-2, 2026.3.0"
        exit 0
        ;;
    esac
    shift
done

case "${1:-}" in
  shell|rerun|clean|install|install-root)
    ACTION="$1"
    shift
    ;;
  *)
    ACTION="test"
    ;;
esac

install_ansible() {
    echo "=== Installing ansible-core ==="
    docker exec "${CONTAINER_NAME}" \
      pip3 install --break-system-packages --quiet "ansible-core==2.19.*"
}

case "${ACTION}" in
  test)
    start_container
    install_ansible

    echo "=== Running playbook ==="
    docker exec -u odios "${CONTAINER_NAME}" \
      ansible-playbook -v -i inventory/localhost.yml \
        /opt/odios/ansible/playbook.yml \
        -e "install_shairport_sync=true" \
        -e "install_upmpdcli=true" \
        -e "install_tidal=true" \
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
        -e "install_spotifyd=true" \
        -e "qobuz_user=test@example.com" \
        -e "qobuz_pass=boguspassword" \
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"

    echo "=== Done ==="
    ;;

  shell)
    docker exec -it -u odios "${CONTAINER_NAME}" bash
    ;;

  rerun)
    echo "=== Re-running playbook ==="
    docker exec -u odios "${CONTAINER_NAME}" \
      ansible-playbook -i inventory/localhost.yml /opt/odios/ansible/playbook.yml \
        -e "install_shairport_sync=true" \
        -e "install_upmpdcli=true" \
        -e "install_tidal=true" \
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
        -e "install_spotifyd=true" \
        -e "qobuz_user=test@example.com" \
        -e "qobuz_pass=boguspassword" \
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"
    ;;

  clean)
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Cleaned."
    ;;

  install)
    start_container
    run_install "${1:-latest}" odios
    echo "=== Done ==="
    ;;

  install-root)
    start_container
    run_install "${1:-latest}"
    echo "=== Done ==="
    ;;
esac
