#!/usr/bin/env python3
"""Wrap one or more RPi Imager manifest entries into a single os_list document.

Usage: build-rpi-manifests.py <output_path> <input.json>...

Same script handles both the per-arch case (one entry from build-image's local
output) and the combined case (all per-arch entries downloaded from artifacts).
"""
import json
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    output_path, *inputs = sys.argv[1:]

    entries = []
    for path in inputs:
        with open(path) as f:
            entries.append(json.load(f))

    with open(output_path, "w") as f:
        json.dump({"os_list": entries}, f, indent=2)
        f.write("\n")
    print(f"wrote {output_path} ({len(entries)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
