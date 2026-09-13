#!/usr/bin/env bash
# Verify that every role whose files changed vs <base> has had its
# <role>_version bumped in vars/main.yml, and carries the catalog fields
# odioctl reads from the manifest.
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
bumped=()
touched=()

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
  touched+=("$role")

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
  else
    bumped+=("$role:$cur")
  fi
done

if [[ ${#drift[@]} -gt 0 ]]; then
  echo "Roles modified without bumping <role>_version in vars/main.yml:" >&2
  printf '  - %s\n' "${drift[@]}" >&2
  exit 1
fi

# All bumped roles in this branch must share the same target version
# (the version of the release we're cutting). Pick the max as the target
# and flag any role bumped to a lower version.
if [[ ${#bumped[@]} -gt 0 ]]; then
  target=$(printf '%s\n' "${bumped[@]}" | cut -d: -f2 | sort -V | tail -1)
  misaligned=()
  for entry in "${bumped[@]}"; do
    [[ "${entry#*:}" == "$target" ]] || misaligned+=("${entry%:*} (${entry#*:}, expected $target)")
  done
  if [[ ${#misaligned[@]} -gt 0 ]]; then
    echo "Roles bumped to a version below the branch target ($target):" >&2
    printf '  - %s\n' "${misaligned[@]}" >&2
    exit 1
  fi
fi

# Catalog fields (build-manifest.py) on every modified role odioctl lists: opt-in
# roles (install_<role> in group_vars) and infra ones; pipewire must stay out.
# groups mirrors odioctl's components.Groups, which ignores any other value.
if [[ ${#touched[@]} -gt 0 ]]; then
  groups="Audio Playback Streaming System"
  defaults="installer/ansible/group_vars/all/main.yml"
  incomplete=()
  for role in "${touched[@]}"; do
    if [[ "$role" != common && "$role" != upgrade ]] && ! grep -q "^install_${role}:" "$defaults"; then
      continue
    fi
    vars_file="$roles_dir/$role/vars/main.yml"
    missing=()
    desc=$(awk -v k="${role}_description:" '$1==k {sub(/^[^:]*:[[:space:]]*/, ""); gsub(/"/, ""); print}' "$vars_file")
    [[ -n "$desc" ]] || missing+=("${role}_description")
    group=$(awk -v k="${role}_group:" '$1==k {gsub(/"/, "", $2); print $2}' "$vars_file")
    [[ -n "$group" && " $groups " == *" $group "* ]] || missing+=("${role}_group")
    grep -q "^${role}_services:" "$vars_file" || missing+=("${role}_services")
    [[ ${#missing[@]} -eq 0 ]] || incomplete+=("$role: ${missing[*]}")
  done
  if [[ ${#incomplete[@]} -gt 0 ]]; then
    echo "Modified roles missing catalog fields in vars/main.yml (group: $groups; services may be []):" >&2
    printf '  - %s\n' "${incomplete[@]}" >&2
    exit 1
  fi
fi

echo "✓ All modified roles have bumped versions and catalog fields"
