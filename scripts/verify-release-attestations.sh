#!/usr/bin/env bash
# Download assets from a release's public URLs and verify their build
# provenance, as a user would.
#
# Usage: verify-release-attestations.sh <tag> <asset>...
#   (needs GH_TOKEN, GH_REPO and GITHUB_REF, the ref the release was built from)
set -euo pipefail

tag="$1"
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for name in "$@"; do
    curl -fsSL -o "${work}/${name}" \
        "https://github.com/${GH_REPO}/releases/download/${tag}/${name}"
    gh attestation verify "${work}/${name}" \
        --repo "$GH_REPO" \
        --signer-workflow "${GH_REPO}/.github/workflows/release.yml" \
        --source-ref "$GITHUB_REF"
done
