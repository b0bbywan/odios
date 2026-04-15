#!/usr/bin/env bash
# Verify that every role whose files changed vs <base> has had its
# <role>_version bumped in vars/main.yml.
#
# Usage: check-role-drift.sh [base_ref]
#   base_ref defaults to the latest release tag (e.g. 2026.4.0rc7).
#
# We compare against the last release tag — not main — because PRs
# can land on main without bumping role versions (or such PRs predate
# the drift check). Comparing to the last tag catches cumulative drift.
set -euo pipefail

base="${1:-$(git describe --tags --abbrev=0 --match='[0-9][0-9][0-9][0-9].*' HEAD)}"
roles_dir="installer/ansible/roles"
drift=()

# A role is in drift when its files differ from <base> but its declared
# version still matches what it was at <base> (or matches <base> itself
# when vars/main.yml didn't exist there yet — bootstrap case).
for d in "$roles_dir"/*/; do
  role=$(basename "$d")
  vars_file="${d}vars/main.yml"
  [[ -f "$vars_file" ]] || continue

  if git diff --quiet "$base"...HEAD -- "$d" ":(exclude)${vars_file}"; then
    continue
  fi

  cur=$(awk -v k="${role}_version:" '$1==k {gsub(/"/,"",$2); print $2}' "$vars_file")
  old=$(git show "$base:$vars_file" 2>/dev/null \
    | awk -v k="${role}_version:" '$1==k {gsub(/"/,"",$2); print $2}' || true)

  if [[ -z "$old" ]]; then
    # Bootstrap: vars/main.yml didn't exist at base. Any value smaller-or-
    # equal to base is wrong because files clearly changed since then.
    if [[ "$cur" == "$base" ]] || printf '%s\n%s\n' "$cur" "$base" | sort -V -C 2>/dev/null; then
      drift+=("$role (declared $cur ≤ $base, but files changed since $base)")
    fi
  elif [[ "$cur" == "$old" ]]; then
    drift+=("$role (still $cur, but files changed since $base)")
  fi
done

if [[ ${#drift[@]} -gt 0 ]]; then
  echo "Roles modified without bumping <role>_version in vars/main.yml:" >&2
  printf '  - %s\n' "${drift[@]}" >&2
  exit 1
fi

echo "✓ All modified roles have bumped versions"
