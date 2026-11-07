#!/usr/bin/env bash
# Publish SHA256SUMS for the given assets of a release, from the digests
# GitHub computes at upload.
#
# Usage: release-sha256sums.sh <tag> <asset>...   (needs GH_TOKEN and GH_REPO)
set -euo pipefail

tag="$1"
shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gh api "repos/${GH_REPO}/releases/tags/${tag}" \
    --jq '.assets[] | "\(.digest // "")  \(.name)"' > "${work}/assets"

for name in "$@"; do
    line=$(awk -v n="$name" '$2 == n' "${work}/assets")
    if [[ "$line" != sha256:* ]]; then
        echo "${name}: not on release ${tag} or no sha256 digest" >&2
        exit 1
    fi
    echo "${line#sha256:}"
done | LC_ALL=C sort -k2 > "${work}/SHA256SUMS"

cat "${work}/SHA256SUMS"
gh release upload "$tag" "${work}/SHA256SUMS" --clobber
