#!/bin/bash
# Build the amd64 test-baseline by running install.sh in image mode on top of
# the Dockerfile.test container, then `docker commit` + push. amd64 has no
# SD-card image source — img-to-docker.sh doesn't apply — so we layer onto
# the clean Dockerfile.test base instead.
#
# Usage: build-baseline-amd64.sh <baseline-tag>
#   <baseline-tag>  e.g. 2026.4.2b1
#
# Env:
#   GITHUB_REPOSITORY  owner/repo (auto-detected from git remote if unset)

set -euo pipefail

TAG="${1:?usage: build-baseline-amd64.sh <baseline-tag>}"

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "${REPO}" ]]; then
    REPO=$(git -C "$(dirname "$0")/.." remote get-url origin 2>/dev/null \
        | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+?)(\.git)?$|\1|')
fi
[[ -n "${REPO}" ]] || { echo "Cannot determine repo (set GITHUB_REPOSITORY)" >&2; exit 2; }

IMAGE_REF="ghcr.io/${REPO}/test-baseline:${TAG}-amd64"
CONTAINER_NAME="odios-test"

cd "$(dirname "$0")/.."

echo "=== Installing baseline ${TAG} into ${CONTAINER_NAME} ==="
REMOTE_IMAGE="ghcr.io/${REPO}/test:latest" \
    ./tests/test.sh install "${TAG}"

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
