#!/bin/bash
set -e

# Run from the project root regardless of where the script is invoked from,
# so relative paths (build context, docker cp source) stay stable.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTAINER_NAME="odios-test"
GITHUB_REPO="b0bbywan/odios"
GITHUB_RELEASE_BASE_URL="https://github.com/${GITHUB_REPO}/releases"

_DEFAULT_TAG="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo latest)"
REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/${GITHUB_REPO}/test:${_DEFAULT_TAG}}"
PLATFORM="${PLATFORM:-}"  # e.g. linux/arm64, linux/arm/v7, linux/arm/v6
BUILD_LOCAL=false

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Bash snippet to prepend to any `docker exec -u <user> bash -c` body that
# needs to talk to `systemd --user@<user>`. `docker exec` doesn't open a PAM
# session, so XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS aren't set; and linger
# brings the user manager up async after PID1, so we may also race start_container.
USER_SYSTEMD_PRELUDE='
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    for _ in $(seq 1 30); do
        [[ -S "$XDG_RUNTIME_DIR/systemd/private" ]] && break
        sleep 0.5
    done
'

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
        echo "${GITHUB_RELEASE_BASE_URL}/latest/download/install.sh"
    else
        echo "${GITHUB_RELEASE_BASE_URL}/download/${tag}/install.sh"
    fi
}

odio_upgrade_url() {
    local tag="$1"
    if [[ "$tag" == "latest" ]]; then
        echo "${GITHUB_RELEASE_BASE_URL}/latest/download/odio_upgrade.py"
    else
        echo "${GITHUB_RELEASE_BASE_URL}/download/${tag}/odio_upgrade.py"
    fi
}

run_odio_upgrade_fetch() {
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

# Create a non-target_user with NOPASSWD sudo. Shared by the install/
# upgrade variants that exercise the path where the invoker is not the
# target_user.
setup_other_user() {
    local user="$1"
    echo "=== Setting up ${user} (NOPASSWD sudo) ==="
    docker exec "${CONTAINER_NAME}" bash -c "
        useradd -m -s /bin/bash ${user} &&
        echo '${user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${user}
    "
}

# Validates that a non-target_user member of the `users` + `odio` groups
# can trigger an upgrade by running odio-upgrade directly (no sudo prefix).
# The odio group grants read on /var/lib/odio/state.json, install.sh's
# internal sudo handles the privileged bits via /etc/sudoers.d. Pre-
# creates the `odio` group because baselines that predate this PR don't
# have it yet.
run_odio_upgrade_fetch_as_other_user() {
    local tag="$1"
    local install_mode="${2:-image}"
    local user="bob"
    local url
    url=$(odio_upgrade_url "$tag")

    setup_other_user "${user}"
    echo "=== Adding ${user} to users + odio groups ==="
    docker exec "${CONTAINER_NAME}" bash -c "
        groupadd -f odio &&
        usermod -aG users,odio ${user}
    "

    echo "=== curl odio-upgrade (${url}) → run as ${user} (target=${tag}, mode=${install_mode}) ==="
    docker exec -u "${user}" -e INSTALL_MODE="${install_mode}" "${CONTAINER_NAME}" bash -c "
        curl -fsSL '${url}' -o /tmp/odio-upgrade &&
        chmod +x /tmp/odio-upgrade &&
        /tmp/odio-upgrade --version '${tag}' --force
    "
}

# Validates that a non-target_user with NOPASSWD sudo can run install.sh
# for TARGET_USER=odio. install.sh's internal `sudo apt-get` and the
# playbook's `become` both rely on the invoker's sudo; the playbook
# creates the odio user/group itself.
run_install_as_other_user() {
    local tag="$1"
    local user="bob"
    setup_other_user "${user}"
    run_install "${tag}" "${user}" image "${@:2}"
}

# Real-release path: odio.love/manifest.json drives the target via
# `odio-upgrade check`, then `systemctl --user start odio-upgrade.service`
# runs the unit (no --version arg). Only valid when the published manifest
# already points at TAG (post-release tag pushes).
run_odio_upgrade_systemctl() {
    local install_mode="${1:-live}"

    echo "=== odio-upgrade check + systemctl --user start odio-upgrade.service (mode=${install_mode}) ==="
    docker exec -u odio -e INSTALL_MODE="${install_mode}" "${CONTAINER_NAME}" bash -c "${USER_SYSTEMD_PRELUDE}"'
        systemctl --user start --wait odio-check-upgrade.service || systemctl --user start --wait odio-upgrade.service
    '
}

assert_state_schema() {
    local target="$1"
    # Pipe the PR's odio_upgrade.py via stdin: when an upgrade fails to
    # replace /usr/local/bin/odio-upgrade (baseline binary lacks `verify`,
    # or the upgrade itself errored), running it directly would obscure
    # the real failure with "unrecognized arguments: verify".
    docker exec -i -u odio "${CONTAINER_NAME}" python3 - verify --expected-version "$target" \
        < installer/ansible/roles/upgrade/files/odio_upgrade.py
}

run_install() {
    local tag="$1"
    local exec_user="${2:-}"          # empty = root
    local install_mode="${3:-image}"  # image (default) | live
    local extra_env=()                # remaining args: KEY=VAL pairs forwarded to env(1)
    if (( $# > 3 )); then
        shift 3
        extra_env=("$@")
    fi
    local url
    url=$(install_sh_url "$tag")

    local user_flag=()
    [[ -n "$exec_user" ]] && user_flag=(-u "$exec_user")

    echo "=== curl | bash ${exec_user:+as $exec_user }(${url}) [mode=${install_mode}${extra_env:+ extra: ${extra_env[*]}}] ==="
    docker exec "${user_flag[@]}" "${CONTAINER_NAME}" \
      env \
        INSTALL_MODE="${install_mode}" \
        TARGET_USER=odio \
        ODIOS_VERSION="${tag}" \
        "${extra_env[@]}" \
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
        echo "  install [TAG]               - Test install.sh as user odio (sudo)"
        echo "  install-root [TAG]          - Test install.sh as root, TARGET_USER=odio"
        echo "  install-as-other-user [TAG] - Test install.sh as bob (NOPASSWD sudoer), TARGET_USER=odio"
        echo "  test-as-other-user          - Run playbook directly as bob (live mode) → exercises become_for_target_user paths"
        echo "                                TAG examples: latest, pr-2, 2026.3.0"
        echo "  upgrade B T        - Upgrade from baseline tag B to target tag T (INSTALL_MODE=live)"
        echo "  upgrade-from-image-fetch T     - Upgrade to T on REMOTE_IMAGE — curls odio-upgrade from the T release first"
        echo "  upgrade-from-image-embedded T  - Same, but uses the baseline's /usr/local/bin/odio-upgrade"
        echo "  upgrade-from-image-systemctl   - Same, but via systemctl --user start odio-upgrade.service"
        echo "                                   (target driven by odio.love/manifest.json — no arg)"
        exit 0
        ;;
    esac
    shift
done

case "${1:-}" in
  shell|rerun|rerun-as-other-user|clean|install|install-root|install-as-other-user|test|test-as-other-user|upgrade|upgrade-from-image-fetch|upgrade-from-image-embedded|upgrade-from-image-systemctl|upgrade-from-image-fetch-as-other-user)
    ACTION="$1"
    shift
    ;;
  *)
    ACTION="test"
    ;;
esac

install_ansible() {
    echo "=== Installing ansible-core + mitogen ==="
    docker exec "${CONTAINER_NAME}" \
      pip3 install --break-system-packages --quiet "ansible-core==2.19.*" "mitogen==0.3.49"
}

# Enable Mitogen on the direct playbook path (test/rerun) via env vars, like
# install.sh — resolves the strategy dir; emits nothing if mitogen is absent.
mitogen_exec_env() {
    local dir
    dir=$(docker exec "${CONTAINER_NAME}" python3 -c \
      'import os, ansible_mitogen; print(os.path.join(os.path.dirname(ansible_mitogen.__file__), "plugins", "strategy"))' \
      2>/dev/null) || return 0
    [[ -n "$dir" ]] && echo "-e ANSIBLE_STRATEGY=mitogen_linear -e ANSIBLE_STRATEGY_PLUGINS=${dir}"
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
    docker exec $(ansible_exec_user) $(mitogen_exec_env) "${CONTAINER_NAME}" \
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
    docker exec $(ansible_exec_user) $(mitogen_exec_env) "${CONTAINER_NAME}" \
      ansible-playbook -i inventory/localhost.yml /opt/odios/ansible/playbook.yml \
        $(ansible_extra_flags) \
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"
    ;;

  rerun-as-other-user)
    echo "=== Re-running playbook as bob ==="
    # shellcheck disable=SC2046
    docker exec -u bob $(mitogen_exec_env) "${CONTAINER_NAME}" \
      ansible-playbook -i inventory/localhost.yml /opt/odios/ansible/playbook.yml \
        -e target_user=odio \
        -e install_mode=live \
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"
    ;;

  clean)
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Cleaned."
    ;;

  install)
    BASELINE="${1:-latest}"
    shift || true
    start_container
    # Remaining args are forwarded as KEY=VAL env to install.sh (e.g.
    # INSTALL_MPD=N), used by scripts/build-baseline-amd64.sh variants.
    run_install "${BASELINE}" odio image "$@"
    echo "=== Done ==="
    ;;

  install-root)
    start_container
    run_install "${1:-latest}"
    echo "=== Done ==="
    ;;

  install-as-other-user)
    BASELINE="${1:-latest}"
    shift || true
    start_container
    run_install_as_other_user "${BASELINE}" "$@"
    echo "=== Done ==="
    ;;

  test-as-other-user)
    start_container
    install_ansible
    setup_other_user bob

    echo "=== Running playbook as bob (target_user=odio, install_mode=live) ==="
    # shellcheck disable=SC2046
    docker exec -u bob $(mitogen_exec_env) "${CONTAINER_NAME}" \
      ansible-playbook -v -i inventory/localhost.yml \
        /opt/odios/ansible/playbook.yml \
        -e target_user=odio \
        -e install_mode=live \
        -e "mpd_discplayer_gnu_email=test@example.com" \
        "$@"

    echo "=== Done ==="
    ;;

  upgrade)
    BASELINE="${1:?baseline tag required (e.g. 2026.4.0rc3)}"
    TARGET="${2:?target tag required (e.g. pr-42 or 2026.4.1rc2)}"

    start_container

    echo "=== [upgrade] Installing baseline ${BASELINE} (image mode) ==="
    run_install "${BASELINE}" odio

    echo "=== [upgrade] Upgrading to ${TARGET} via odio-upgrade (image mode) ==="
    run_odio_upgrade_fetch "${TARGET}"

    echo "=== [upgrade] Asserting state.json reflects ${TARGET} ==="
    assert_state_schema "${TARGET}"
    echo "=== Done ==="
    ;;

  upgrade-from-image-fetch|upgrade-from-image-embedded|upgrade-from-image-systemctl|upgrade-from-image-fetch-as-other-user)
    TARGET="${1:?target tag required (e.g. pr-42 or 2026.4.1rc2)}"

    # systemctl path drives the upgrade target via odio.love/manifest.json,
    # so it can only validate after CI's publish-manifest job has caught up.
    # Skip cleanly when the published `latest` doesn't match TARGET — the
    # alternative is asserting against whatever was promoted last and
    # falsely failing on every fresh tag.
    if [[ "${ACTION}" == "upgrade-from-image-systemctl" ]]; then
        published_latest=$(curl -fsSL https://odio.love/manifest.json | jq -r '.odios' 2>/dev/null || echo "")
        if [[ "${published_latest}" != "${TARGET}" ]]; then
            echo "=== [${ACTION}] SKIPPED — odio.love reports latest=${published_latest:-?}, target=${TARGET} (re-run after CI publish-manifest) ==="
            exit 0
        fi
    fi

    # The whole point of upgrade-from-image-* is to test the upgrade code path on
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
      upgrade-from-image-fetch)              run_odio_upgrade_fetch              "${TARGET}" ;;
      upgrade-from-image-embedded)           run_odio_upgrade_embedded           "${TARGET}" ;;
      upgrade-from-image-systemctl)          run_odio_upgrade_systemctl                       ;;
      upgrade-from-image-fetch-as-other-user) run_odio_upgrade_fetch_as_other_user "${TARGET}" ;;
    esac

    echo "=== [${ACTION}] Asserting state.json reflects ${TARGET} ==="
    assert_state_schema "${TARGET}"
    echo "=== Done ==="
    ;;
esac
