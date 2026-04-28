#!/bin/bash
set -e

# Run from the project root regardless of where the script is invoked from,
# so relative paths (build context, docker cp source) stay stable.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
        docker build ${pflags} -t "${REMOTE_IMAGE}" -f tests/Dockerfile.test .
    else
        echo "=== Pulling image ==="
        # shellcheck disable=SC2086
        docker pull ${pflags} "${REMOTE_IMAGE}" || {
            echo "Pull failed, falling back to local build..."
            # shellcheck disable=SC2086
            docker build ${pflags} -t "${REMOTE_IMAGE}" -f tests/Dockerfile.test .
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

    echo "=== Waiting for container ==="
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

odio_upgrade_url() {
    local tag="$1"
    if [[ "$tag" == "latest" ]]; then
        echo "https://github.com/${GITHUB_REPO}/releases/latest/download/odio-upgrade"
    else
        echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/odio-upgrade"
    fi
}

run_odio_upgrade() {
    local tag="$1"
    local install_mode="${2:-image}"
    local url
    url=$(odio_upgrade_url "$tag")

    echo "=== curl odio-upgrade (${url}) → run as odio (target=${tag}, mode=${install_mode}) ==="
    docker exec -u odio -e INSTALL_MODE="${install_mode}" "${CONTAINER_NAME}" bash -c "
        curl -fsSL '${url}' -o /tmp/odio-upgrade &&
        chmod +x /tmp/odio-upgrade &&
        /tmp/odio-upgrade --version '${tag}' --force
    "
}

run_odio_upgrade_embedded() {
    local tag="$1"
    local install_mode="${2:-image}"

    echo "=== embedded /usr/local/bin/odio-upgrade → run as odio (target=${tag}, mode=${install_mode}) ==="
    docker exec -u odio -e INSTALL_MODE="${install_mode}" "${CONTAINER_NAME}" \
        /usr/local/bin/odio-upgrade --version "${tag}" --force
}

# Real-release path: odio.love/manifest.json drives the target via odio-check-upgrade,
# then `systemctl --user start odio-upgrade.service` runs the unit (no --version arg).
# Only valid when the published manifest already points at TAG (post-release tag pushes).
run_odio_upgrade_systemctl() {
    local tag="$1"
    local install_mode="${2:-image}"

    echo "=== odio-check-upgrade + systemctl --user start odio-upgrade.service (target=${tag}, mode=${install_mode}) ==="
    docker exec -u odio -e INSTALL_MODE="${install_mode}" "${CONTAINER_NAME}" bash -c '
        set -e
        /usr/local/bin/odio-check-upgrade || true
        latest=$(python3 -c "import json; print(json.load(open(\"/var/cache/odio/upgrades.json\"))[\"latest\"])")
        if [[ "$latest" != "'"${tag}"'" ]]; then
            echo "ERROR: odio.love manifest reports latest=$latest, expected '"${tag}"'" >&2
            exit 1
        fi
        systemctl --user start --wait odio-upgrade.service
    '
}

assert_state_schema() {
    local target="$1"
    # Pipe the script via stdin so we don't rely on a writable/persistent path
    # in the container (/tmp is tmpfs + systemd-tmpfiles-managed on some baseline
    # images, which can race with docker cp).
    docker exec -i -u odio "${CONTAINER_NAME}" python3 - "$target" \
        < tests/assert_state_schema.py
}

run_install() {
    local tag="$1"
    local exec_user="${2:-}"          # empty = root
    local install_mode="${3:-image}"  # image (default) | live
    local url
    url=$(install_sh_url "$tag")

    local user_flag=()
    [[ -n "$exec_user" ]] && user_flag=(-u "$exec_user")

    echo "=== curl | bash ${exec_user:+as $exec_user }(${url}) [mode=${install_mode}] ==="
    docker exec "${user_flag[@]}" "${CONTAINER_NAME}" \
      env \
        INSTALL_MODE="${install_mode}" \
        TARGET_USER=odio \
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
        echo "  install [TAG]      - Test install.sh as user odio (sudo)"
        echo "  install-root [TAG] - Test install.sh as root, TARGET_USER=odio"
        echo "                       TAG examples: latest, pr-2, 2026.3.0"
        echo "  upgrade B T        - Upgrade from baseline tag B to target tag T (INSTALL_MODE=live)"
        echo "  upgrade-from-image T - Upgrade to target T on REMOTE_IMAGE (pre-provisioned baseline) via curl"
        echo "  upgrade-from-image-embedded T - Same, but uses the baseline's /usr/local/bin/odio-upgrade"
        echo "  upgrade-from-image-systemctl T - Same, but via systemctl --user start odio-upgrade.service"
        echo "                       (T must already be reported as latest by odio.love/manifest.json)"
        exit 0
        ;;
    esac
    shift
done

case "${1:-}" in
  shell|rerun|clean|install|install-root|upgrade|upgrade-from-image|upgrade-from-image-embedded|upgrade-from-image-systemctl)
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
# On native x86 we keep -u odio to also exercise the sudo escalation path.
# When running as root, target_user must be passed explicitly (defaults to
# ansible_user_id which would be root, blocked by the playbook guard).
ansible_exec_user() {
    [[ -z "${PLATFORM}" ]] && echo "-u odio" || true
}

ansible_extra_flags() {
    [[ -n "${PLATFORM}" ]] && echo "-e target_user=odio -e install_mode=image" || true
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
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"
    ;;

  clean)
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Cleaned."
    ;;

  install)
    start_container
    run_install "${1:-latest}" odio
    echo "=== Done ==="
    ;;

  install-root)
    start_container
    run_install "${1:-latest}"
    echo "=== Done ==="
    ;;

  upgrade)
    BASELINE="${1:?baseline tag required (e.g. 2026.4.0rc3)}"
    TARGET="${2:?target tag required (e.g. pr-42 or 2026.4.1rc2)}"

    start_container

    echo "=== [upgrade] Installing baseline ${BASELINE} (image mode) ==="
    run_install "${BASELINE}" odio

    echo "=== [upgrade] Upgrading to ${TARGET} via odio-upgrade (image mode) ==="
    run_odio_upgrade "${TARGET}"

    echo "=== [upgrade] Asserting state.json reflects ${TARGET} ==="
    assert_state_schema "${TARGET}"
    echo "=== Done ==="
    ;;

  upgrade-from-image|upgrade-from-image-embedded|upgrade-from-image-systemctl)
    TARGET="${1:?target tag required (e.g. pr-42 or 2026.4.1rc2)}"

    # The whole point of upgrade-from-image* is to test the upgrade code path on
    # a pre-provisioned baseline. Falling back to a fresh Dockerfile.test build
    # would silently test an install, not an upgrade — refuse up front.
    echo "=== [${ACTION}] Verifying baseline image ${REMOTE_IMAGE} ==="
    # shellcheck disable=SC2046
    if ! docker pull $(platform_flags) "${REMOTE_IMAGE}"; then
        cat >&2 <<EOF

ERROR: baseline image ${REMOTE_IMAGE} not available.

  • If it doesn't exist yet, build and push it:
      docker login ghcr.io
      ./scripts/img-to-docker.sh <BASELINE_TAG> <ARCH>

  • If it exists but is private, authenticate:
      docker login ghcr.io

Refusing to fall back to a Dockerfile.test rebuild — that would silently
test a fresh container, not an upgrade.
EOF
        exit 1
    fi

    start_container

    echo "=== [${ACTION}] Upgrading to ${TARGET} (image mode) ==="
    case "${ACTION}" in
      upgrade-from-image)           run_odio_upgrade           "${TARGET}" ;;
      upgrade-from-image-embedded)  run_odio_upgrade_embedded  "${TARGET}" ;;
      upgrade-from-image-systemctl) run_odio_upgrade_systemctl "${TARGET}" ;;
    esac

    echo "=== [${ACTION}] Asserting state.json reflects ${TARGET} ==="
    assert_state_schema "${TARGET}"
    echo "=== Done ==="
    ;;
esac
