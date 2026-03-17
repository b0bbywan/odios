#!/bin/bash
set -e

CONTAINER_NAME="odios-test"
GITHUB_REPO="b0bbywan/odios"
_DEFAULT_TAG="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo latest)"
REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/${GITHUB_REPO}/test:${_DEFAULT_TAG}}"
PLATFORM="${PLATFORM:-}"  # e.g. linux/arm64, linux/arm/v7, linux/arm/v6
BUILD_LOCAL=false

# ─── Helpers ──────────────────────────────────────────────────────────────────

platform_flags() {
    [[ -n "${PLATFORM}" ]] && echo "--platform ${PLATFORM}" || true
}

resolve_image() {
    local pflags; pflags=$(platform_flags)
    if [[ "${BUILD_LOCAL}" == "true" ]]; then
        echo "=== Building image locally ==="
        # shellcheck disable=SC2086
        docker build ${pflags} -t "${REMOTE_IMAGE}" -f Dockerfile.test .
    else
        echo "=== Pulling image ==="
        # shellcheck disable=SC2086
        docker pull ${pflags} "${REMOTE_IMAGE}" || {
            echo "Pull failed, falling back to local build..."
            # shellcheck disable=SC2086
            docker build ${pflags} -t "${REMOTE_IMAGE}" -f Dockerfile.test .
        }
    fi
}

start_container() {
    resolve_image

    local pflags; pflags=$(platform_flags)
    echo "=== Starting container with systemd${PLATFORM:+ ($PLATFORM)} ==="
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    # shellcheck disable=SC2086
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --privileged \
      --cgroupns=host \
      --user root \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      ${pflags} \
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
        INSTALL_MODE=image \
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
        echo "  Env vars:"
        echo "    PLATFORM           - Docker platform (e.g. linux/arm64, linux/arm/v7, linux/arm/v6)"
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

# Under QEMU user-mode, sudo setuid is not honoured — run ansible as root.
# On native x86 we keep -u odios to also exercise the sudo escalation path.
# When running as root, target_user must be passed explicitly (defaults to
# ansible_user_id which would be root, blocked by the playbook guard).
ansible_exec_user() {
    [[ -z "${PLATFORM}" ]] && echo "-u odios" || true
}

ansible_extra_flags() {
    [[ -n "${PLATFORM}" ]] && echo "-e target_user=odios -e install_mode=image" || true
}

case "${ACTION}" in
  test)
    start_container
    install_ansible

    echo "=== Running playbook ==="
    # shellcheck disable=SC2046
    docker exec $(ansible_exec_user) "${CONTAINER_NAME}" \
      ansible-playbook -v -i inventory/localhost.yml \
        /opt/odios/ansible/playbook.yml \
        $(ansible_extra_flags) \
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
    # shellcheck disable=SC2046
    docker exec -it $(ansible_exec_user) "${CONTAINER_NAME}" bash
    ;;

  rerun)
    echo "=== Re-running playbook ==="
    # shellcheck disable=SC2046
    docker exec $(ansible_exec_user) "${CONTAINER_NAME}" \
      ansible-playbook -i inventory/localhost.yml /opt/odios/ansible/playbook.yml \
        $(ansible_extra_flags) \
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
