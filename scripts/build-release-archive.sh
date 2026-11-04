#!/bin/bash
# Build the installer archive (playbooks + vendored ansible-core + manifest.json)
# that install.sh and the image builder download from the GitHub release.
# ansible-core and its deps come from the `vendor` group of uv.lock; needs uv.
#
# Usage: build-release-archive.sh [--name <archive>] [--output <dir>] [<version>]
#   <version>          stamped into VERSION and manifest.json
#                      (default: git describe of HEAD)
#   --name <archive>   archive file name (default: odio-<version>.tar.gz)
#   --output <dir>     where the archive and manifest.json land (default: output)
#
# Env:
#   GNU_EMAIL  written to group_vars/all/secrets.yml when set

set -euo pipefail

NAME=""
OUTPUT="output"
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --name)   NAME="${2:?--name needs a value}"; shift ;;
        --output) OUTPUT="${2:?--output needs a value}"; shift ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --long --always --match='[0-9][0-9][0-9][0-9].*' HEAD)}"
NAME="${NAME:-odio-${VERSION}.tar.gz}"

STAGING=$(mktemp -d)
trap 'rm -rf "${STAGING}"' EXIT

echo "=== Vendoring the uv.lock vendor group ==="
uv export --quiet --frozen --only-group vendor --no-emit-project \
    --no-emit-package cryptography --no-emit-package cffi --no-emit-package pycparser \
    -o "${STAGING}/requirements.txt"
uv pip install --quiet --target="${STAGING}/vendor" --no-deps --require-hashes \
    -r "${STAGING}/requirements.txt"
rm "${STAGING}/requirements.txt"

find "${STAGING}/vendor" -name '*.so' -delete
find "${STAGING}/vendor" -depth -type d \( -name '__pycache__' -o -name '*.dist-info' \) \
    -exec rm -rf {} +
echo "Vendor size: $(du -sh "${STAGING}/vendor" | cut -f1)"

echo "=== Assembling ${NAME} (${VERSION}) ==="
mkdir -p "${STAGING}/licenses"
cp licences/ANSIBLE-LICENSE-GPLv3 "${STAGING}/licenses/ANSIBLE-LICENSE-GPLv3"
cp LICENSE "${STAGING}/licenses/ODIOS-LICENSE-BSD2"

cp -r installer/ansible "${STAGING}/ansible"
find "${STAGING}/ansible" -depth -type d -name '__pycache__' -exec rm -rf {} +
if [[ -n "${GNU_EMAIL:-}" ]]; then
    echo "mpd_discplayer_gnu_email: \"${GNU_EMAIL}\"" \
        > "${STAGING}/ansible/group_vars/all/secrets.yml"
fi

echo "${VERSION}" > "${STAGING}/VERSION"

# PyYAML comes with the vendored ansible-core
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="${STAGING}/vendor" ./scripts/build-manifest.py \
    "${VERSION}" "${STAGING}/ansible/roles" "${STAGING}/manifest.json"

mkdir -p "${OUTPUT}"
tar czf "${OUTPUT}/${NAME}" -C "${STAGING}" ansible vendor licenses VERSION manifest.json
cp "${STAGING}/manifest.json" "${OUTPUT}/manifest.json"

echo "Archive: ${OUTPUT}/${NAME} ($(du -sh "${OUTPUT}/${NAME}" | cut -f1))"
