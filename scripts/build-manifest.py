#!/usr/bin/env python3
"""Build manifest.json from per-role vars/main.yml files.

Usage: build-manifest.py <odios_version> <roles_dir> <output_path>

`catalog` describes the roles that carry <role>_description/_group/_services for
odioctl, unless <role>_catalog is false; opt_in says the role is off unless
asked for, required (<role>_required) that odioctl must not offer to disable it,
and archs, only when <role>_archs is set, lists the dpkg architectures it
installs on. label (<role>_label) is the name the user knows it by, when not
the role's own. features, only when <role>_features is set, maps each feature
of the role to its description, and label when it has one.
"""
import json
import os
import sys
from typing import Any

import yaml

CATALOG_KEYS = ("description", "group", "services")


def opt_in(role: str, role_vars: dict[str, Any], defaults: dict[str, Any]) -> bool:
    # install_<role> settles it when group_vars holds a literal; a derived one
    # (the audioserver pair) is a Jinja string, so the role declares it itself.
    if f"{role}_opt_in" in role_vars:
        return bool(role_vars[f"{role}_opt_in"])
    return defaults.get(f"install_{role}") is False


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
        # A role can carry catalog metadata before odioctl can model it;
        # <role>_catalog: false holds it back until then.
        if role_vars.get(f"{role}_catalog", True) and any(
            f"{role}_{k}" in role_vars for k in CATALOG_KEYS
        ):
            catalog[role] = {
                "description": role_vars.get(f"{role}_description", ""),
                "group": role_vars.get(f"{role}_group", ""),
                "services": role_vars.get(f"{role}_services", []),
                "opt_in": opt_in(role, role_vars, defaults),
                "required": bool(role_vars.get(f"{role}_required", False)),
            }
            if f"{role}_label" in role_vars:
                catalog[role]["label"] = role_vars[f"{role}_label"]
            if f"{role}_archs" in role_vars:
                catalog[role]["archs"] = role_vars[f"{role}_archs"]
            if f"{role}_features" in role_vars:
                catalog[role]["features"] = {
                    name: {"description": meta.get("description", "")}
                    | ({"label": meta["label"]} if "label" in meta else {})
                    for name, meta in role_vars[f"{role}_features"].items()
                }

    manifest = {"odios": version, "roles": roles, "catalog": catalog}
    with open(output, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
