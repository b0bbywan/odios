#!/bin/bash
set -e

CONTAINER_NAME="odios-test"
IMAGE_NAME="odios-test"
GITHUB_REPO="b0bbywan/odios"

# ─── Helpers ──────────────────────────────────────────────────────────────────

start_container() {
    echo "=== Building image ==="
    docker build -t "${IMAGE_NAME}" -f Dockerfile.test .

    echo "=== Starting container with systemd ==="
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --privileged \
      --cgroupns=host \
      --user root \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      "${IMAGE_NAME}"

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
        INSTALL_SPOTIFYD=N \
        INSTALL_SHAIRPORT_SYNC=Y \
        INSTALL_SNAPCLIENT=Y \
        INSTALL_UPMPDCLI=Y \
        INSTALL_MPD_DISCPLAYER=Y \
        ODIOS_VERSION="${tag}" \
      bash -c "curl -fsSL '${url}' | bash"
}

# ─── Actions ──────────────────────────────────────────────────────────────────

case "$1" in
  shell|rerun|clean|install|install-root)
    ACTION="$1"
    shift
    ;;
  --help|-h)
    echo "Usage: $0 [test|shell|rerun|clean|install|install-root] [args...]"
    echo ""
    echo "  test               - Build + start + run playbook directly (default)"
    echo "  shell              - Shell into running container"
    echo "  rerun              - Re-run playbook without rebuild"
    echo "  clean              - Remove container"
    echo "  install [TAG]      - Test install.sh as user odios (sudo)"
    echo "  install-root [TAG] - Test install.sh as root, TARGET_USER=odios"
    echo "                       TAG examples: latest, pr-2, v1.0.0"
    exit 0
    ;;
  *)
    ACTION="test"
    ;;
esac

case "${ACTION}" in
  test)
    start_container

    echo "=== Running playbook ==="
    docker exec -u odios "${CONTAINER_NAME}" \
      ansible-playbook -v -i inventory/localhost.yml \
        /opt/odios/ansible/playbook.yml \
        -e "install_shairport_sync=true" \
        -e "install_upmpdcli=true" \
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
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
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
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
