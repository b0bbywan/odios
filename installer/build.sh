#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
BOOTSTRAP_TEMPLATE="${SCRIPT_DIR}/bootstrap.sh"
OUTPUT_FILE="${SCRIPT_DIR}/install.sh"

echo "Building Audio Streaming System Installer..."
echo ""

# Check if ansible directory exists
if [[ ! -d "$ANSIBLE_DIR" ]]; then
    echo "ERROR: Ansible directory not found at $ANSIBLE_DIR"
    exit 1
fi

# Check if bootstrap template exists
if [[ ! -f "$BOOTSTRAP_TEMPLATE" ]]; then
    echo "ERROR: Bootstrap template not found at $BOOTSTRAP_TEMPLATE"
    exit 1
fi

# Create tarball of Ansible playbook
echo "→ Creating playbook archive..."
tar -czf /tmp/playbook.tar.gz -C "${ANSIBLE_DIR}" .

# Encode tarball as base64
echo "→ Encoding playbook..."
PLAYBOOK_B64=$(base64 -w 0 /tmp/playbook.tar.gz)

# Generate installer script
echo "→ Generating installer script..."
cp "${BOOTSTRAP_TEMPLATE}" "${OUTPUT_FILE}"

# Replace __PLAYBOOK_ARCHIVE__ marker with encoded playbook
# Use a temporary file to avoid sed issues with large strings
cat > /tmp/playbook_embed.txt << 'EMBED_EOF'
    cat << 'PLAYBOOK_EOF' | base64 -d | tar -xzf - -C "${TEMP_DIR}"
EMBED_EOF
echo "${PLAYBOOK_B64}" >> /tmp/playbook_embed.txt
echo "PLAYBOOK_EOF" >> /tmp/playbook_embed.txt

# Now replace the marker in the output file
awk '
    /# __PLAYBOOK_ARCHIVE__/ {
        system("cat /tmp/playbook_embed.txt")
        next
    }
    { print }
' "${BOOTSTRAP_TEMPLATE}" > "${OUTPUT_FILE}"

chmod +x "${OUTPUT_FILE}"
rm /tmp/playbook.tar.gz /tmp/playbook_embed.txt

echo ""
echo "✓ Installer generated successfully!"
echo ""
echo "  Output file: ${OUTPUT_FILE}"
echo "  File size:   $(du -h ${OUTPUT_FILE} | cut -f1)"
echo "  SHA256:      $(sha256sum ${OUTPUT_FILE} | cut -d' ' -f1)"
echo ""
echo "To use the installer:"
echo "  bash ${OUTPUT_FILE}"
echo ""
