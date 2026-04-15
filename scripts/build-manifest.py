#!/usr/bin/env python3
"""Build manifest.json from per-role vars/main.yml files.

Usage: build-manifest.py <odios_version> <roles_dir> <output_path>
"""
import json
import os
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    version, roles_dir, output = sys.argv[1:]
    roles: dict[str, str] = {}

    for role in sorted(os.listdir(roles_dir)):
        vars_file = os.path.join(roles_dir, role, "vars", "main.yml")
        if not os.path.isfile(vars_file):
            continue
        pattern = re.compile(rf'\s*{re.escape(role)}_version:\s*"?([^"\s]+)"?')
        with open(vars_file) as f:
            for line in f:
                m = pattern.match(line)
                if m:
                    roles[role] = m.group(1)
                    break

    manifest = {"odios": version, "roles": roles}
    with open(output, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
