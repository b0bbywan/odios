#!/usr/bin/env python3
"""Assert /var/cache/odio/state.json matches the shape odio-upgrade reads.

Invoked by test.sh after install/upgrade runs to catch write_state.yml Jinja
regressions (missing features_excluded, False leaking into features, etc.)
without waiting for a full upgrade-with-mismatch round-trip.

Usage: assert_state_schema.py <target-tag>
Exit 0 on success, non-zero (AssertionError) on schema drift.
"""
import json
import re
import sys

KNOWN_FEATURES = {"tidal", "qobuz", "upnpwebradios", "mympd"}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: assert_state_schema.py <target-tag>", file=sys.stderr)
        return 2
    tag = sys.argv[1]
    with open("/var/cache/odio/state.json") as f:
        s = json.load(f)
    assert s.get("target_user"), "state.target_user is missing"

    ver = s.get("odios", "")
    # PR pre-releases ship an archive whose VERSION is a git-describe output
    # like <base>-<N>-g<sha>; release tags match VERSION exactly.
    if tag.startswith("pr-"):
        assert re.match(r"^\d+\.\d+\.\d+.*-g[0-9a-f]+$", ver), \
            f"state.odios={ver!r} is not a git-describe for {tag}"
    else:
        assert ver == tag, f"state.odios={ver!r} expected {tag}"
    assert s.get("roles"), "state.roles is empty"

    feats = s.get("features")
    excl = s.get("features_excluded")
    assert isinstance(feats, list), f"features must be list, got {feats!r}"
    assert isinstance(excl, list), f"features_excluded must be list, got {excl!r}"
    cats = set(feats) | set(excl)
    assert cats <= KNOWN_FEATURES, \
        f"features/features_excluded may only contain {sorted(KNOWN_FEATURES)}, got {sorted(cats)}"
    overlap = set(feats) & set(excl)
    assert not overlap, f"features and features_excluded overlap: {sorted(overlap)}"

    history = s.get("release_history")
    assert isinstance(history, list) and history, \
        f"release_history must be a non-empty list, got {history!r}"
    assert all(isinstance(x, str) for x in history), \
        f"release_history must contain only strings, got {history!r}"
    assert history[-1] == ver, \
        f"release_history[-1]={history[-1]!r} must equal state.odios={ver!r}"

    print(f"state.json OK: {ver} roles={list(s['roles'])} "
          f"features={feats} excluded={excl} history={history}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
