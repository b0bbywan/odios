#!/usr/bin/env python3
"""Check for and apply odios upgrades.

Two subcommands sharing the same version-comparison code:

  odio-upgrade check
      Compare local state.json against odio.love/manifest.json and refresh
      /var/cache/odio/upgrades.json. Wired to a daily systemd user timer.

  odio-upgrade apply [--version VERSION] [--state PATH] [--dry-run] [--force]
      Locate state.json (system path /var/cache/odio/state.json, or pre-rc3
      ~/.cache/odio/state.json, or rebuild from dpkg as a last resort),
      derive INSTALL_* env vars matching the previous install, fetch the
      target manifest to compute per-role RUN_* skips (smart-upgrade,
      issue #54), then pipe install.sh from the target release into bash.

For backwards compatibility, `odio-upgrade` (no subcommand) defaults to `apply`.

Exit codes:
  check : 0 = up to date, 1 = upgrades available, 2 = error
  apply : 0 = upgraded (or up-to-date without --force), 1 = install.sh failed, 2 = error
"""
import argparse
import contextlib
import json
import os
import pwd
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import TypedDict, cast

GITHUB_REPO = "b0bbywan/odios"
LATEST_MANIFEST_URL = "https://odio.love/manifest.json"

SYSTEM_STATE_PATH = "/var/cache/odio/state.json"
SYSTEM_UPGRADES_PATH = "/var/cache/odio/upgrades.json"

# Roles gated in playbook.yml — these are the only ones that take a `run_X`
# flag. `common` and `upgrade` are always run.
GATED_ROLES = (
    "branding", "pulseaudio", "bluetooth", "mpd", "mpd_discplayer",
    "shairport_sync", "snapclient", "upmpdcli", "spotifyd", "odio_api",
)


class Manifest(TypedDict):
    """Schema of release manifest.json (built by scripts/build-manifest.py)."""
    odios: str
    roles: dict[str, str]


class StateLegacy(TypedDict, total=False):
    """Raw state.json read from disk — every schema vintage rolled up.

    Fields differ across releases:
      rc1/rc2 : odios, install_mode, roles
      rc3     : + roles_excluded, features (was dict {name: bool}), features_excluded
      rc4+    : + target_user, release_history; features migrated to list[str]
    Everything optional so the input boundary stays permissive; backfill_state
    normalizes to State.
    """
    odios: str
    install_mode: str
    target_user: str
    roles: dict[str, str]
    roles_excluded: list[str]
    features: list[str] | dict[str, bool]
    features_excluded: list[str]
    release_history: list[str]


class _StateRequired(TypedDict):
    """Fields backfill_state guarantees on every State."""
    roles: dict[str, str]
    roles_excluded: list[str]
    features: list[str]
    features_excluded: list[str]


class State(_StateRequired, total=False):
    """Post-backfill state. The four collection fields are always set;
    odios / install_mode / target_user / release_history are written by
    ansible's write_state.yml — present when read from a real install,
    absent for fresh dpkg reconstructions until ansible runs.
    """
    odios: str
    install_mode: str
    target_user: str
    release_history: list[str]


class RoleUpgrade(TypedDict):
    """One per-role entry in the upgrades.json `roles` list."""
    name: str
    installed: str
    available: str


class UpgradeReport(TypedDict):
    """Schema of upgrades.json (written by `check`, read by `apply`)."""
    current: str
    latest: str
    upgrade_available: bool
    roles: list[RoleUpgrade]
    checked_at: str


_PRE_PHASES = {"a": 0, "b": 1, "rc": 2}
_VERSION_RE = re.compile(
    r"^(\d+)\.(\d+)\.(\d+)(?:(a|b|rc)(\d+))?(?:-(\d+)-g[0-9a-f]+)?$"
)


def parse_version(v: str) -> tuple[int, ...]:
    m = _VERSION_RE.match(v)
    if not m:
        return (0,)
    year, month, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if m.group(4):
        phase = _PRE_PHASES[m.group(4)]
        pre_num = int(m.group(5))
    else:
        phase = 3
        pre_num = 0
    dev_commits = int(m.group(6)) if m.group(6) else 0
    return (year, month, patch, phase, pre_num, dev_commits)


def _invoking_user() -> str:
    return os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name


def _read_state_file(path: str) -> StateLegacy:
    with open(path) as f:
        return cast(StateLegacy, json.load(f))


def find_state() -> tuple[str | None, StateLegacy | None, str | None]:
    """Locate state.json and return (path, state, target_user).

    Tries the system path first, then the pre-rc3 per-user path of the
    *invoking* user only — never globs /home/* so we don't need root.
    Returns (None, None, None) when the caller must rebuild from dpkg.
    """
    if os.path.isfile(SYSTEM_STATE_PATH):
        state = _read_state_file(SYSTEM_STATE_PATH)
        return SYSTEM_STATE_PATH, state, state.get("target_user")

    user_state = os.path.expanduser("~/.cache/odio/state.json")
    if os.path.isfile(user_state):
        # Pre-rc4 wrote state.json into target_user's own home, so the
        # invoking user reading it is, by construction, the target_user.
        return user_state, _read_state_file(user_state), _invoking_user()

    return None, None, None


# dpkg signals used to reconstruct a state.json when none exists on disk.
# branding has no package — handled separately via the per-user motd script.
_ROLE_PACKAGES = {
    "pulseaudio":     "pulseaudio",
    "bluetooth":      "bluez",
    "mpd":            "mpd",
    "mpd_discplayer": "mpd-discplayer",
    "shairport_sync": "shairport-sync",
    "snapclient":     "snapclient",
    "spotifyd":       "spotifyd",
    "upmpdcli":       "upmpdcli",
    "odio_api":       "odio-api",
}
_FEATURE_PACKAGES = {
    "tidal":         "upmpdcli-tidal",
    "qobuz":         "upmpdcli-qobuz",
    "upnpwebradios": "upmpdcli-radios",
    "mympd":         "mympd",
}


def _dpkg_installed(pkg: str) -> bool:
    try:
        result = subprocess.run(
            ["dpkg-query", "-W", "-f=${Status}", pkg],
            capture_output=True, text=True, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return "install ok installed" in result.stdout


def _detect_features() -> set[str]:
    # Sub-flags inferred from dpkg so they stay truthful after the first
    # state.json rewrite. Without this, a user whose state.json predates the
    # `features` block (rc1/rc2) or the no-state.json era would see
    # active features silently drop on upgrade.
    return {f for f, pkg in _FEATURE_PACKAGES.items() if _dpkg_installed(pkg)}


def _detect_roles(target_user: str) -> dict[str, str]:
    roles = {r: "legacy" for r, pkg in _ROLE_PACKAGES.items() if _dpkg_installed(pkg)}
    if os.path.isfile(f"/home/{target_user}/.local/bin/odio-motd"):
        roles["branding"] = "legacy"
    return roles


def backfill_state(state: StateLegacy, target_user: str) -> State:
    # rc1/rc2 state.json only carries {odios, install_mode, roles}, and pre-rc3
    # installs had motd as a feature rather than its own role. Fill in the
    # newer fields using on-disk detection so `derive_install_env` has the
    # same information it would get from a current state.json.
    roles = dict(state.get("roles") or {})
    if "branding" not in roles and \
            os.path.isfile(f"/home/{target_user}/.local/bin/odio-motd"):
        roles["branding"] = "legacy"
    if "roles_excluded" in state:
        roles_excluded = list(state["roles_excluded"])
    else:
        # Roles introduced after the rc1/rc2 schema era can't have been
        # explicitly excluded by a legacy install — keep them out of the
        # synthesized opt-outs so they fall through to install.sh's Y defaults
        # on upgrade. Extend whenever a new role lands later than the oldest
        # baseline still listed in test-upgrade matrix.
        _post_legacy_roles = {"branding"}
        roles_excluded = sorted(
            set(_ROLE_PACKAGES.keys()) - set(roles.keys()) - _post_legacy_roles
        )

    # Canonical shape: `features: [name]` holds opt-ins, `features_excluded:
    # [name]` holds opt-outs. Anything in neither maps to Y at derive time
    # (pure opt-out) — that's what lets a newly-added feature self-install.
    raw = state.get("features")
    if isinstance(raw, dict):
        features = {k for k, v in raw.items() if v}
        legacy_excluded = {k for k, v in raw.items() if not v}
    else:
        features = set(raw or [])
        legacy_excluded = set()
    features.discard("motd")  # pre-rc3 legacy key — branding is a role now
    features_excluded = (
        set(state.get("features_excluded") or []) | legacy_excluded
    ) - {"motd"}

    features |= _detect_features() - features - features_excluded

    out: State = {
        "roles": roles,
        "roles_excluded": roles_excluded,
        "features": sorted(features),
        "features_excluded": sorted(features_excluded),
    }
    # Preserve the optional metadata fields if the input had them — write_state.yml
    # is the only thing that sets these, so they're absent for dpkg-rebuilt states.
    if "odios" in state:
        out["odios"] = state["odios"]
    if "install_mode" in state:
        out["install_mode"] = state["install_mode"]
    if "target_user" in state:
        out["target_user"] = state["target_user"]
    if "release_history" in state:
        out["release_history"] = state["release_history"]
    return out


def resolve_target_user(invoking: str) -> str:
    # If the invoking user has odio-api configured, they are the target_user.
    if os.path.isdir(os.path.expanduser(f"~{invoking}/.config/odio-api")):
        return invoking
    # Otherwise prompt with `odio` (install.sh's own default) and verify.
    while True:
        answer = input("Target user for upgrade [odio]: ").strip() or "odio"
        try:
            pwd.getpwnam(answer)
            return answer
        except KeyError:
            print(f"  user {answer!r} not found, try again", file=sys.stderr)


def state_from_dpkg(target_user: str) -> State:
    # Last-resort fallback: build a synthetic state from dpkg + branding marker,
    # then run backfill so _excluded fields and features get populated the same
    # way an rc1/rc2 state.json would after migration.
    return backfill_state({"roles": _detect_roles(target_user)}, target_user)


def _print_state_summary(state: State) -> None:
    roles = ", ".join(sorted(state["roles"].keys())) or "(none)"
    excluded = ", ".join(state["roles_excluded"]) or "(none)"
    features = ", ".join(sorted(state["features"])) or "(none)"
    feat_excluded = ", ".join(state["features_excluded"]) or "(none)"
    print(f"  roles:             {roles}", flush=True)
    print(f"  roles_excluded:    {excluded}", flush=True)
    print(f"  features:          {features}", flush=True)
    print(f"  features_excluded: {feat_excluded}", flush=True)


def derive_install_env(state: State) -> dict[str, str]:
    """Return INSTALL_* flags derived from state.json.

    Emits N for everything in the *_excluded lists and Y for everything in
    `roles`/`features`. Anything in neither list is left unset so install.sh's
    own defaults (Y for every optional in upgrade-era releases) take over —
    that's what lets a role added after this script was written self-install.
    """
    env: dict[str, str] = {}
    for role in state["roles_excluded"]:
        env[f"INSTALL_{role.upper()}"] = "N"
    for feature in state["features_excluded"]:
        env[f"INSTALL_{feature.upper()}"] = "N"
    for role in state["roles"]:
        env[f"INSTALL_{role.upper()}"] = "Y"
    for feature in state["features"]:
        env[f"INSTALL_{feature.upper()}"] = "Y"
    return env


def resolve_version(explicit: str | None, upgrades_path: str) -> str:
    if explicit:
        return explicit
    try:
        with open(upgrades_path) as f:
            return json.load(f).get("latest") or "latest"
    except (OSError, json.JSONDecodeError):
        return "latest"


def upgrade_reported(upgrades_path: str) -> bool:
    # Returns True if upgrades.json reports an upgrade is available. If the
    # file is missing or unreadable, returns True so install.sh can decide.
    try:
        with open(upgrades_path) as f:
            return bool(json.load(f).get("upgrade_available"))
    except (OSError, json.JSONDecodeError):
        return True


def install_url(version: str) -> str:
    if version == "latest":
        return f"https://github.com/{GITHUB_REPO}/releases/latest/download/install.sh"
    return f"https://github.com/{GITHUB_REPO}/releases/download/{version}/install.sh"


def manifest_url(version: str) -> str:
    if version == "latest":
        return f"https://github.com/{GITHUB_REPO}/releases/latest/download/manifest.json"
    return f"https://github.com/{GITHUB_REPO}/releases/download/{version}/manifest.json"


def fetch_manifest(url: str) -> Manifest | None:
    """Fetch a manifest.json from `url`.

    Returns None on any error — `apply` callers fall back to skipping the
    per-role diff (install.sh defaults take over, run = install); `check`
    treats None as a hard error and exits 2.
    """
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "odio-upgrade/1"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            return cast(Manifest, json.loads(resp.read()))
    except Exception as e:
        print(f"  warning: could not fetch manifest at {url}: {e}", file=sys.stderr)
        return None


def _role_up_to_date(
    installed: str | None,
    target: str | None,
    state_odios: str | None,
) -> bool:
    """True when the installed role version covers target AND is trustworthy.

    "Trustworthy" = target is at or below state.odios. A target ahead of
    state.odios means the manifest is past the last release certified on this
    box, so the dpkg marker for `installed` was set under conditions we can't
    verify — re-run. At release time target <= state.odios for every role,
    so the guard is a no-op there.
    """
    if not installed or not target:
        return False
    if parse_version(target) > parse_version(installed):
        return False
    return state_odios is None or parse_version(target) <= parse_version(state_odios)


def derive_run_env(
    state: State,
    manifest: Manifest | None,
    install_env: dict[str, str],
) -> dict[str, str]:
    """Return RUN_<role>=N for roles whose target version matches installed.

    Asymmetric: only N is emitted. Anything else falls through to install.sh's
    `RUN_X=${RUN_X:-$INSTALL_X}` default — i.e. RUN matches INSTALL, today's
    behaviour. That keeps the user-facing API as INSTALL_X only; RUN_X is an
    internal optimisation channel.
    """
    if manifest is None:
        return {}

    target_roles = manifest["roles"]
    prior_roles = state["roles"]
    state_odios = state.get("odios")

    env: dict[str, str] = {}
    for role in GATED_ROLES:
        # Skip roles the user explicitly excluded — install.sh's INSTALL_X=N
        # already gates them, so the run flag is irrelevant.
        if install_env.get(f"INSTALL_{role.upper()}") == "N":
            continue
        target = target_roles.get(role)
        installed = prior_roles.get(role)
        if _role_up_to_date(installed, target, state_odios):
            env[f"RUN_{role.upper()}"] = "N"

    # Stale-config trigger: if the install set is going to grow this turn
    # (target manifest adds a role the user hasn't excluded), force odio_api
    # to re-render config.yaml.j2 even if its own version didn't bump.
    excluded = set(state["roles_excluded"])
    new_in_target = (set(target_roles) - set(prior_roles) - excluded) & set(GATED_ROLES)
    if new_in_target:
        env.pop("RUN_ODIO_API", None)

    return env


@dataclass
class ApplyOptions:
    version: str | None = None
    state: str | None = None
    dry_run: bool = False
    force: bool = False


@dataclass
class CheckOptions:
    state: str = SYSTEM_STATE_PATH
    url: str = LATEST_MANIFEST_URL
    output: str = SYSTEM_UPGRADES_PATH


def cmd_apply(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        prog="odio-upgrade apply",
        description=(
            "Re-run install.sh from the target release with INSTALL_X derived "
            "from state.json and RUN_X derived from the per-role manifest diff."
        ),
    )
    p.add_argument(
        "--version",
        help="target version tag (default: latest from upgrades.json)",
    )
    p.add_argument("--state", help="path to state.json (default: auto-detect)")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="print the invocation without running",
    )
    p.add_argument(
        "--force",
        action="store_true",
        help="run even if no upgrade is reported",
    )
    args = p.parse_args(argv)
    return run_apply(ApplyOptions(
        version=args.version,
        state=args.state,
        dry_run=args.dry_run,
        force=args.force,
    ))


def _load_state(opts: ApplyOptions) -> tuple[str | None, State, str] | None:
    """Resolve (state_path, state, target_user) from opts, or None on read error."""
    raw: StateLegacy | None
    state_path: str | None
    target_user: str
    if opts.state:
        state_path = opts.state
        try:
            raw = _read_state_file(state_path)
        except (OSError, json.JSONDecodeError) as e:
            print(f"Error reading {state_path}: {e}", file=sys.stderr)
            return None
        target_user = raw.get("target_user") or _invoking_user()
    else:
        try:
            state_path, raw, found_user = find_state()
        except (OSError, json.JSONDecodeError) as e:
            print(f"Error reading state.json: {e}", file=sys.stderr)
            return None
        target_user = found_user or _invoking_user()

    state: State
    if raw is None:
        target_user = resolve_target_user(_invoking_user())
        state = state_from_dpkg(target_user)
        print(
            f"No state.json — reconstructed from dpkg "
            f"(target_user={target_user}):",
            flush=True,
        )
    else:
        # Older state.json schemas (rc1/rc2) are missing features and
        # roles_excluded — reconstruct them so we don't silently flip active
        # features off or re-install roles the user had excluded.
        original_keys = set(raw.keys())
        state = backfill_state(raw, target_user)
        backfilled = sorted(
            {"roles_excluded", "features", "features_excluded"} - original_keys
        )
        if backfilled:
            print(
                f"state.json missing newer fields — backfilled from disk: "
                f"{', '.join(backfilled)}",
                flush=True,
            )
        else:
            print(f"state.json read from {state_path}:", flush=True)
    _print_state_summary(state)
    return state_path, state, target_user


def _build_apply_env(
    state: State, version: str, target_user: str,
) -> dict[str, str]:
    install_env = derive_install_env(state)
    manifest = fetch_manifest(manifest_url(version))
    run_env = derive_run_env(state, manifest, install_env)
    env_overrides = {
        **install_env,
        **run_env,
        "ODIOS_VERSION": version,
        "TARGET_USER": target_user,
    }

    skipped = sorted(k.removeprefix("RUN_").lower() for k in run_env)
    if skipped:
        print(
            f"  smart-upgrade: skipping unchanged roles: {', '.join(skipped)}",
            flush=True,
        )
    elif manifest is None:
        print("  smart-upgrade: manifest unavailable, running all roles", flush=True)
    else:
        print("  smart-upgrade: all roles bumped, running everything", flush=True)

    return env_overrides


def run_apply(opts: ApplyOptions) -> int:
    loaded = _load_state(opts)
    if loaded is None:
        return 2
    state_path, state, target_user = loaded

    upgrades_path = (
        os.path.join(os.path.dirname(state_path), "upgrades.json")
        if state_path else SYSTEM_UPGRADES_PATH
    )

    if not opts.force and not opts.version \
            and not upgrade_reported(upgrades_path):
        print(
            "No upgrade reported in upgrades.json — use --force to override.",
            flush=True,
        )
        return 0

    version = resolve_version(opts.version, upgrades_path)
    url = install_url(version)
    env_overrides = _build_apply_env(state, version, target_user)

    print(f"Upgrading to {version} via {url}", flush=True)
    print("  env passed to install.sh:", flush=True)
    for k in sorted(env_overrides):
        print(f"    {k}={env_overrides[k]}", flush=True)

    if opts.dry_run:
        print("(dry-run, not invoking)", flush=True)
        return 0

    env = {**os.environ, **env_overrides}
    cmd = ["bash", "-c", f"curl -fsSL {url} | bash"]
    return subprocess.run(cmd, env=env).returncode


def cmd_check(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        prog="odio-upgrade check",
        description=(
            "Compare local state against the remote manifest and "
            "refresh upgrades.json."
        ),
    )
    p.add_argument("--state", default=SYSTEM_STATE_PATH)
    p.add_argument("--url", default=LATEST_MANIFEST_URL)
    p.add_argument("--output", default=SYSTEM_UPGRADES_PATH)
    args = p.parse_args(argv)
    return run_check(CheckOptions(
        state=args.state,
        url=args.url,
        output=args.output,
    ))


def _compute_role_upgrades(
    state: StateLegacy, manifest: Manifest,
) -> list[RoleUpgrade]:
    upgrades: list[RoleUpgrade] = []
    for role, installed in (state.get("roles") or {}).items():
        available = manifest["roles"].get(role)
        if available and parse_version(available) > parse_version(installed):
            upgrades.append({
                "name": role,
                "installed": installed,
                "available": available,
            })
    upgrades.sort(key=lambda r: r["name"])
    return upgrades


def _build_upgrades_report(
    state: StateLegacy, manifest: Manifest,
) -> UpgradeReport:
    upgrades = _compute_role_upgrades(state, manifest)
    current = state.get("odios", "unknown")
    latest = manifest["odios"]
    return {
        "current": current,
        "latest": latest,
        "upgrade_available": bool(upgrades) or (
            parse_version(latest) > parse_version(current)
        ),
        "roles": upgrades,
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def _write_upgrades_report(report: UpgradeReport, output: str) -> None:
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "w") as f:
        json.dump(report, f, indent=2)
        f.write("\n")
    # Default umask gives 0644; explicit chmod so other `users` group members
    # (target_user when the timer runs as them, ansible become_user, etc.)
    # can rewrite this file without needing root.
    with contextlib.suppress(OSError):
        os.chmod(output, 0o664)


def _print_check_summary(report: UpgradeReport) -> None:
    if report["upgrade_available"]:
        print(f"Upgrades available: {report['current']} → {report['latest']}")
        for r in report["roles"]:
            print(f"  {r['name']}: {r['installed']} → {r['available']}")
    else:
        print(f"Up to date ({report['current']})")


def run_check(opts: CheckOptions) -> int:
    try:
        state = _read_state_file(opts.state)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Error reading state: {e}", file=sys.stderr)
        return 2

    manifest = fetch_manifest(opts.url)
    if manifest is None:
        return 2

    report = _build_upgrades_report(state, manifest)
    _write_upgrades_report(report, opts.output)
    _print_check_summary(report)
    return 1 if report["upgrade_available"] else 0


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] == "check":
        return cmd_check(argv[1:])
    # `apply` is the default; the word is optional for back-compat with the
    # legacy odio-upgrade CLI (--version, --force, --dry-run, --state).
    if argv and argv[0] == "apply":
        argv = argv[1:]
    return cmd_apply(argv)


if __name__ == "__main__":
    sys.exit(main())
