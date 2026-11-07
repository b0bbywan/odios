#!/bin/bash
# Build the installer archive (playbooks + vendored ansible-core + manifest.json)
# that install.sh and the image builder download from the GitHub release.
# ansible-core and its deps come from the `vendor` group of uv.lock; needs uv.
# The build is reproducible: the same commit, version and GNU_EMAIL give the
# same archive, byte for byte.
#
# Usage: build-release-archive.sh [--name <archive>] [--output <dir>] [<version>]
#   <version>          stamped into VERSION and manifest.json (default: the
#                      tag on HEAD, else git describe of HEAD)
#   --name <archive>   archive file name (default: odio-<version>.tar.gz)
#   --output <dir>     where the archive and manifest.json land (default: output)
#
# Env:
#   GNU_EMAIL          written to group_vars/all/secrets.yml when set
#   SOURCE_DATE_EPOCH  timestamp of every entry (default: HEAD's commit date)

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

TAG_MATCH='[0-9][0-9][0-9][0-9].*'
VERSION="${1:-$(git describe --tags --exact-match --match="${TAG_MATCH}" HEAD 2>/dev/null \
    || git describe --tags --long --always --match="${TAG_MATCH}" HEAD)}"
NAME="${NAME:-odio-${VERSION}.tar.gz}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct HEAD)}"

STAGING=$(mktemp -d)
trap 'rm -rf "${STAGING}"' EXIT

echo "=== Vendoring the uv.lock vendor group ==="
uv export --quiet --frozen --only-group vendor --no-emit-project \
    --no-emit-package cryptography --no-emit-package cffi --no-emit-package pycparser \
    -o "${STAGING}/requirements.txt"
# A fixed platform picks the same wheels whatever the host; their native
# extensions are dropped below, the pure-Python fallbacks run anywhere.
uv pip install --quiet --target="${STAGING}/vendor" --no-deps --require-hashes \
    --only-binary=:all: --python-platform=x86_64-manylinux2014 --python-version=3.13 \
    -r "${STAGING}/requirements.txt"
rm "${STAGING}/requirements.txt"

# The installer's console scripts change with its version and carry its interpreter path
rm -rf "${STAGING}/vendor/bin"
mkdir "${STAGING}/vendor/bin"
python3 -I - "${STAGING}/vendor" <<'EOF'
import configparser, glob, os, sys
vendor = sys.argv[1]
for path in sorted(glob.glob(os.path.join(vendor, "*.dist-info", "entry_points.txt"))):
    eps = configparser.ConfigParser()
    eps.optionxform = str
    eps.read(path)
    if not eps.has_section("console_scripts"):
        continue
    for name, target in eps["console_scripts"].items():
        module, func = target.strip().split(":")
        script = os.path.join(vendor, "bin", name)
        with open(script, "w") as f:
            f.write(f"#!/usr/bin/python3\nimport sys\nfrom {module} import {func}\nsys.exit({func}())\n")
        os.chmod(script, 0o755)
EOF

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

# Entry order, timestamps, owners and modes fixed so the bytes do not depend
# on the host, its umask or when the build ran.
mkdir -p "${OUTPUT}"
tar --create --format=gnu --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w' \
    -C "${STAGING}" ansible vendor licenses VERSION manifest.json \
    | gzip -9 --no-name > "${OUTPUT}/${NAME}"
cp "${STAGING}/manifest.json" "${OUTPUT}/manifest.json"

echo "Archive: ${OUTPUT}/${NAME} ($(du -sh "${OUTPUT}/${NAME}" | cut -f1))"
echo "SHA256:  $(sha256sum "${OUTPUT}/${NAME}" | cut -d' ' -f1)"
