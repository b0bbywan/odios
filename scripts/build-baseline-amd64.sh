#!/bin/bash
# Build the amd64 test-baseline by running install.sh in image mode on top of
# the Dockerfile.test container, then `docker commit` + push. amd64 has no
# SD-card image source — img-to-docker.sh doesn't apply — so we layer onto
# the clean Dockerfile.test base instead.
#
# Usage: build-baseline-amd64.sh [--no-mpd-stack] <baseline-tag>
#   <baseline-tag>     e.g. 2026.4.2b1
#   --no-mpd-stack     install without mpd / mpd-discplayer / upmpdcli;
#                      pushes as test-baseline:<tag>-amd64-no-mpd-stack
#
# Env:
#   GITHUB_REPOSITORY  owner/repo (auto-detected from git remote if unset)

set -euo pipefail

NO_MPD_STACK=false
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --no-mpd-stack) NO_MPD_STACK=true ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

TAG="${1:?usage: build-baseline-amd64.sh [--no-mpd-stack] <baseline-tag>}"

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "${REPO}" ]]; then
    REPO=$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null \
        | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+?)(\.git)?$|\1|')
fi
[[ -n "${REPO}" ]] || { echo "Cannot determine repo (set GITHUB_REPOSITORY)" >&2; exit 2; }

VARIANT_SUFFIX=""
INSTALL_EXTRA_ENV=()
if "${NO_MPD_STACK}"; then
    VARIANT_SUFFIX="-no-mpd-stack"
    INSTALL_EXTRA_ENV=(INSTALL_MPD=N INSTALL_MPD_DISCPLAYER=N INSTALL_UPMPDCLI=N INSTALL_BRANDING=Y INSTALL_SPOTIFYD=Y)
fi

IMAGE_REF="ghcr.io/${REPO}/test-baseline:${TAG}-amd64${VARIANT_SUFFIX}"
CONTAINER_NAME="odios-test"

cd "$(dirname "$0")/.."

echo "=== Installing baseline ${TAG}${VARIANT_SUFFIX:+ (${VARIANT_SUFFIX#-})} into ${CONTAINER_NAME} ==="
REMOTE_IMAGE="ghcr.io/${REPO}/test:latest" \
    ./tests/test.sh install "${TAG}" "${INSTALL_EXTRA_ENV[@]}"

echo "=== Stopping container for clean systemd shutdown ==="
docker stop "${CONTAINER_NAME}"

echo "=== Committing ${IMAGE_REF} ==="
docker commit \
    -c 'CMD ["/lib/systemd/systemd"]' \
    -c 'STOPSIGNAL SIGRTMIN+3' \
    -c "LABEL org.opencontainers.image.source=https://github.com/${REPO}" \
    "${CONTAINER_NAME}" "${IMAGE_REF}"

echo "=== Pushing ${IMAGE_REF} ==="
docker push "${IMAGE_REF}"

echo "=== Cleaning up ==="
docker rm "${CONTAINER_NAME}" >/dev/null

echo "=== Done ==="
