#!/usr/bin/env python3
"""Print `name==version` for packages pinned in uv.lock, for pip installs run without uv.

Usage: lock-pin.py [--hashes] <package>...

--hashes appends the hashes of the package's files, for pip --require-hashes.
"""
import sys
import tomllib
from pathlib import Path

LOCK = Path(__file__).resolve().parent.parent / "uv.lock"


def main() -> int:
    args = sys.argv[1:]
    hashes = "--hashes" in args
    names = [a for a in args if a != "--hashes"]
    if not names:
        print(__doc__, file=sys.stderr)
        return 2

    with LOCK.open("rb") as f:
        packages = {p["name"]: p for p in tomllib.load(f)["package"]}

    for name in names:
        package = packages.get(name)
        if package is None:
            print(f"{name}: not in {LOCK.name}", file=sys.stderr)
            return 1
        line = f"{name}=={package['version']}"
        if hashes:
            files = [*package.get("wheels", [])]
            if "sdist" in package:
                files.append(package["sdist"])
            line += "".join(f" --hash={f['hash']}" for f in files)
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
