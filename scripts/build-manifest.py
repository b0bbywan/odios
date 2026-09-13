#!/usr/bin/env python3
"""Build manifest.json from per-role vars/main.yml files.

Usage: build-manifest.py <odios_version> <roles_dir> <output_path>

`catalog` describes the roles that carry <role>_description/_group/_services for
odioctl; opt_in is true when group_vars defaults install_<role> to false, and
archs, only when <role>_archs is set, lists the dpkg architectures it installs on.
"""
import json
import os
import sys
from typing import Any

import yaml

CATALOG_KEYS = ("description", "group", "services")


def load(path: str) -> dict[str, Any]:
    with open(path) as f:
        data: dict[str, Any] = yaml.safe_load(f) or {}
    return data


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    version, roles_dir, output = sys.argv[1:]
    defaults = load(os.path.join(roles_dir, os.pardir, "group_vars", "all", "main.yml"))
    roles: dict[str, str] = {}
    catalog: dict[str, dict[str, Any]] = {}

    for role in sorted(os.listdir(roles_dir)):
        vars_file = os.path.join(roles_dir, role, "vars", "main.yml")
        if not os.path.isfile(vars_file):
            continue
        role_vars = load(vars_file)
        if f"{role}_version" not in role_vars:
            continue
        roles[role] = str(role_vars[f"{role}_version"])
        if any(f"{role}_{k}" in role_vars for k in CATALOG_KEYS):
            catalog[role] = {
                "description": role_vars.get(f"{role}_description", ""),
                "group": role_vars.get(f"{role}_group", ""),
                "services": role_vars.get(f"{role}_services", []),
                "opt_in": defaults.get(f"install_{role}") is False,
            }
            if f"{role}_archs" in role_vars:
                catalog[role]["archs"] = role_vars[f"{role}_archs"]

    manifest = {"odios": version, "roles": roles, "catalog": catalog}
    with open(output, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
