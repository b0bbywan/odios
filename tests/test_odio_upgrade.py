#!/usr/bin/env python3
"""Unit tests for odio-upgrade's state-reconstruction logic.

Covers the three input shapes the upgrade script must handle:
  - no state.json → state_from_dpkg + backfill
  - state.json without features/roles_excluded (rc1/rc2) → backfill
  - full current-schema state.json → identity through backfill

Run with: python3 -m unittest tests.test_odio_upgrade
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

# Make the upgrade-role's source directory importable so we can grab
# odio_upgrade and its TypedDicts directly. Mirrors mypy's `mypy_path`.
sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "installer/ansible/roles/upgrade/files"),
)
import odio_upgrade as ou
from odio_upgrade import Manifest, State, StateLegacy


def _state(
    *,
    roles: dict[str, str] | None = None,
    roles_excluded: list[str] | None = None,
    features: list[str] | None = None,
    features_excluded: list[str] | None = None,
    odios: str | None = None,
    release_history: list[str] | None = None,
) -> State:
    """Build a post-backfill State for tests that bypass backfill_state.
    Tests of legacy-shape inputs (features-as-dict, etc.) live in BackfillStateTests.
    """
    out: State = {
        "roles": roles if roles is not None else {},
        "roles_excluded": roles_excluded if roles_excluded is not None else [],
        "features": features if features is not None else [],
        "features_excluded": features_excluded if features_excluded is not None else [],
    }
    if odios is not None:
        out["odios"] = odios
    if release_history is not None:
        out["release_history"] = release_history
    return out


class DeriveInstallEnvTests(unittest.TestCase):
    def test_installed_role_maps_to_Y(self):
        env = ou.derive_install_env(_state(roles={"pulseaudio": "x"}))
        self.assertEqual(env["INSTALL_PULSEAUDIO"], "Y")

    def test_excluded_role_maps_to_N(self):
        env = ou.derive_install_env(_state(roles_excluded=["spotifyd"]))
        self.assertEqual(env["INSTALL_SPOTIFYD"], "N")

    def test_role_absent_from_both_is_not_emitted(self):
        # Opt-out semantic: anything not in roles/roles_excluded is left unset
        # so install.sh's own defaults (Y for optionals in upgrade-era releases)
        # take over. That's how a role added after this script was written
        # self-installs on upgrade.
        env = ou.derive_install_env(_state())
        self.assertNotIn("INSTALL_BRANDING", env)
        self.assertNotIn("INSTALL_MPD", env)

    def test_feature_absent_from_both_is_not_emitted(self):
        env = ou.derive_install_env(_state())
        self.assertNotIn("INSTALL_TIDAL", env)

    def test_excluded_feature_maps_to_N(self):
        env = ou.derive_install_env(_state(features_excluded=["tidal"]))
        self.assertEqual(env["INSTALL_TIDAL"], "N")

    def test_feature_in_features_maps_to_Y(self):
        env = ou.derive_install_env(_state(features=["tidal"]))
        self.assertEqual(env["INSTALL_TIDAL"], "Y")

    def test_branding_role_maps_to_install_branding(self):
        env = ou.derive_install_env(_state(roles={"branding": "x"}))
        self.assertEqual(env["INSTALL_BRANDING"], "Y")

    def test_empty_state_emits_nothing(self):
        # No information in state.json → no INSTALL_* keys; install.sh's own
        # defaults govern every flag. This is the contract that lets the local
        # script stay agnostic to roles added by future releases.
        self.assertEqual(ou.derive_install_env(_state()), {})


class BackfillStateTests(unittest.TestCase):
    def _call(
        self,
        state: StateLegacy,
        *,
        branding: bool = False,
        tidal: bool = False,
        qobuz: bool = False,
        webradios: bool = False,
    ) -> State:
        motd_path = "/home/u/.local/bin/odio-motd"
        pkg_map = {
            "upmpdcli-tidal": tidal,
            "upmpdcli-qobuz": qobuz,
            "upmpdcli-radios": webradios,
        }
        with (
            patch.object(ou, "_dpkg_installed", side_effect=lambda p: pkg_map.get(p, False)),
            patch("os.path.isfile", side_effect=lambda p: p == motd_path and branding),
        ):
            return ou.backfill_state(state, "u")

    def test_rc1_rc2_state_gets_excluded_roles_and_detected_features(self):
        # rc1/rc2 state only carries `roles`. Backfill must add roles_excluded,
        # promote dpkg-detected features into `features`, and detect the
        # branding role via the odio-motd file. Undetected features are left
        # out of both lists — pure opt-out makes them Y at derive time.
        state: StateLegacy = {"roles": {"pulseaudio": "x", "bluetooth": "x", "odio_api": "x"}}
        result = self._call(state, branding=True, tidal=True)

        self.assertIn("branding", result["roles"])
        expected_excluded = sorted(
            set(ou._ROLE_PACKAGES) - {"pulseaudio", "bluetooth", "odio_api"}
        )
        self.assertEqual(result["roles_excluded"], expected_excluded)
        self.assertEqual(result["features"], ["tidal"])
        self.assertEqual(result["features_excluded"], [])

    def test_real_world_rc2_user_minimal_install(self):
        # Verbatim state.json from a real rc2 user (PR #52 feedback): kept
        # core (pulseaudio, bluetooth, odio_api, branding) plus shairport_sync,
        # opted out of mpd / mpd_discplayer / snapclient / spotifyd / upmpdcli.
        # mympd didn't exist in 2026.4.1rc2 — added in 2026.4.2b2 as a sub-
        # feature of mpd. After the refactor, mympd lives in features, not
        # roles, so it must not appear in roles_excluded and (since the user
        # opted out of mpd) must not get installed regardless of INSTALL_MYMPD.
        state: StateLegacy = {
            "install_mode": "live",
            "odios": "2026.4.1rc2",
            "roles": {
                "bluetooth": "2026.4.0rc5",
                "branding": "2026.4.1rc2",
                "common": "2026.4.0rc6",
                "odio_api": "2026.4.0rc7",
                "pulseaudio": "2026.4.0rc7",
                "shairport_sync": "2026.4.1rc1",
            },
        }
        result = self._call(state)

        self.assertEqual(
            sorted(result["roles_excluded"]),
            ["mpd", "mpd_discplayer", "snapclient", "spotifyd", "upmpdcli"],
        )
        self.assertNotIn("mympd", result["roles_excluded"])
        self.assertNotIn("mympd", result.get("roles") or {})
        self.assertEqual(result["features"], [])
        self.assertEqual(result["features_excluded"], [])

    def test_legacy_dict_features_migrate_to_list_and_excluded(self):
        # Old state.json used {name: bool} for features — True entries become
        # the new features list, False entries move into features_excluded so
        # derive_install_env keeps honoring the opt-out under the new schema.
        state: StateLegacy = {
            "roles": {"upmpdcli": "x"},
            "roles_excluded": [],
            "features": {"tidal": True, "qobuz": False, "upnpwebradios": False},
        }
        result = self._call(state)
        self.assertEqual(result["features"], ["tidal"])
        self.assertEqual(result["features_excluded"], ["qobuz", "upnpwebradios"])

    def test_full_state_preserved(self):
        # Current-schema state.json → backfill is a no-op for populated fields.
        state: StateLegacy = {
            "roles": {"pulseaudio": "x", "branding": "x"},
            "roles_excluded": ["spotifyd"],
            "features": [],
            "features_excluded": ["tidal", "qobuz", "upnpwebradios"],
        }
        result = self._call(state, branding=False, tidal=True)  # disk lies — state wins
        self.assertEqual(result["roles_excluded"], ["spotifyd"])
        self.assertEqual(result["features"], [])
        self.assertEqual(
            result["features_excluded"], ["qobuz", "tidal", "upnpwebradios"]
        )
        self.assertIn("branding", result["roles"])

    def test_partial_features_filled_but_not_overwritten(self):
        # A state that knows about one feature shouldn't see it toggled by
        # dpkg; dpkg-detected features are added; undetected ones stay absent
        # (pure opt-out → Y at derive time, not forced N here).
        state: StateLegacy = {"roles": {"pulseaudio": "x"}, "features": ["tidal"]}
        result = self._call(state, tidal=False, qobuz=True)
        self.assertIn("tidal", result["features"])   # preserved (state wins over dpkg)
        self.assertIn("qobuz", result["features"])   # from dpkg
        self.assertNotIn("upnpwebradios", result["features"])
        self.assertEqual(result["features_excluded"], [])

    def test_undetected_feature_not_added_to_excluded(self):
        # Regression for the PR #49 bug: upnpwebradios was absent from dpkg on
        # an install that never opted in, and backfill used to force it into
        # features_excluded → `INSTALL_UPNPWEBRADIOS=N` on every upgrade. Under
        # pure opt-out, an undetected feature must stay out of both lists so
        # derive_install_env can default it to Y.
        state: StateLegacy = {
            "roles": {"upmpdcli": "x"},
            "roles_excluded": [],
            "features": [],
            "features_excluded": [],
        }
        result = self._call(state, tidal=False, qobuz=False, webradios=False)
        self.assertEqual(result["features"], [])
        self.assertEqual(result["features_excluded"], [])

    def test_stale_motd_feature_key_is_dropped(self):
        # Pre-refactor state.json had features.motd — it's now the branding
        # role, so the stale feature key gets pruned on backfill and does not
        # leak into features_excluded either.
        state: StateLegacy = {
            "roles": {"pulseaudio": "x"},
            "features": {"motd": True, "tidal": False},
        }
        result = self._call(state, branding=True)
        self.assertNotIn("motd", result["features"])
        self.assertNotIn("motd", result["features_excluded"])
        self.assertIn("tidal", result["features_excluded"])
        self.assertIn("branding", result["roles"])


class StateFromDpkgTests(unittest.TestCase):
    def test_roles_reconstructed_from_dpkg(self):
        installed = {"pulseaudio", "bluez", "mpd", "shairport-sync", "odio-api"}
        with (
            patch.object(ou, "_dpkg_installed", side_effect=lambda p: p in installed),
            patch("os.path.isfile", return_value=False),
        ):
            state = ou.state_from_dpkg("u")
        self.assertIn("pulseaudio", state["roles"])
        self.assertIn("bluetooth", state["roles"])  # bluez → bluetooth role
        self.assertIn("mpd", state["roles"])
        self.assertIn("shairport_sync", state["roles"])
        self.assertIn("odio_api", state["roles"])
        # Non-detected roles fall into roles_excluded (except branding — see below).
        self.assertIn("spotifyd", state["roles_excluded"])
        self.assertIn("snapclient", state["roles_excluded"])

    def test_branding_detected_via_motd_file(self):
        motd_path = "/home/u/.local/bin/odio-motd"
        with (
            patch.object(ou, "_dpkg_installed", return_value=False),
            patch("os.path.isfile", side_effect=lambda p: p == motd_path),
        ):
            state = ou.state_from_dpkg("u")
        self.assertIn("branding", state["roles"])
        # branding is never auto-excluded — pure opt-out at derive time picks it up.
        self.assertNotIn("branding", state["roles_excluded"])

    def test_dpkg_detected_features_land_in_features(self):
        # Roles + feature packages co-install — the same dpkg pass picks both up.
        installed = {"upmpdcli", "upmpdcli-qobuz", "upmpdcli-tidal"}
        with (
            patch.object(ou, "_dpkg_installed", side_effect=lambda p: p in installed),
            patch("os.path.isfile", return_value=False),
        ):
            state = ou.state_from_dpkg("u")
        self.assertEqual(state["features"], ["qobuz", "tidal"])
        self.assertEqual(state["features_excluded"], [])


class BackfillDeriveIntegrationTests(unittest.TestCase):
    """End-to-end: what install.sh would actually receive for a given state.json."""

    def test_pr49_regression_unlisted_feature_left_to_install_sh_default(self):
        # Reproduces the PR #49 user report: state.json has qobuz + tidal
        # opted in, features_excluded is empty, and upnpwebradios + branding
        # are absent everywhere. Under the new contract derive_install_env
        # leaves them unset so install.sh's own (Y) defaults install them —
        # which is how a flag the local script doesn't know about still
        # self-installs on upgrade.
        legacy: StateLegacy = {
            "roles": {r: "x" for r in ou._ROLE_PACKAGES},
            "roles_excluded": [],
            "features": {"qobuz": True, "tidal": True},
            "features_excluded": [],
        }
        pkg_map = {"upmpdcli-qobuz": True, "upmpdcli-tidal": True}
        with (
            patch.object(ou, "_dpkg_installed", side_effect=lambda p: pkg_map.get(p, False)),
            patch("os.path.isfile", return_value=False),
        ):
            state = ou.backfill_state(legacy, "u")
        env = ou.derive_install_env(state)
        self.assertEqual(env["INSTALL_QOBUZ"], "Y")
        self.assertEqual(env["INSTALL_TIDAL"], "Y")
        self.assertNotIn("INSTALL_UPNPWEBRADIOS", env)  # install.sh default Y
        self.assertNotIn("INSTALL_BRANDING", env)        # install.sh default Y


class ResolveTargetUserTests(unittest.TestCase):
    def test_invoking_user_with_odio_api_config_is_returned_silently(self):
        # If the invoking user already has ~/.config/odio-api/, no prompt.
        with (
            patch.object(ou.os.path, "expanduser", return_value="/home/alice/.config/odio-api"),
            patch.object(ou.os.path, "isdir", return_value=True),
            patch("builtins.input", side_effect=AssertionError("should not prompt")),
        ):
            self.assertEqual(ou.resolve_target_user("alice"), "alice")

    def test_prompt_default_odio_when_invoking_user_has_no_config(self):
        with (
            patch.object(ou.os.path, "expanduser", return_value="/nonexistent"),
            patch.object(ou.os.path, "isdir", return_value=False),
            patch("builtins.input", return_value=""),
            patch.object(ou.pwd, "getpwnam") as gp,
        ):
            self.assertEqual(ou.resolve_target_user("alice"), "odio")
            gp.assert_called_with("odio")

    def test_prompt_reasks_until_user_exists(self):
        responses = iter(["bogus", "odio"])
        existing = {"odio"}

        def fake_getpwnam(name):
            if name in existing:
                return object()
            raise KeyError(name)

        with (
            patch.object(ou.os.path, "expanduser", return_value="/nonexistent"),
            patch.object(ou.os.path, "isdir", return_value=False),
            patch("builtins.input", side_effect=lambda *_: next(responses)),
            patch.object(ou.pwd, "getpwnam", side_effect=fake_getpwnam),
        ):
            self.assertEqual(ou.resolve_target_user("alice"), "odio")


class ParseVersionTests(unittest.TestCase):
    def test_final_release_compares_above_rc(self):
        # 2026.5.0 > 2026.5.0rc1 > 2026.5.0b1 > 2026.5.0a1 — the phase axis
        # is what lets odio-upgrade tell "ship-ready" from "iterating".
        self.assertGreater(ou.parse_version("2026.5.0"), ou.parse_version("2026.5.0rc1"))
        self.assertGreater(ou.parse_version("2026.5.0rc1"), ou.parse_version("2026.5.0b1"))
        self.assertGreater(ou.parse_version("2026.5.0b1"), ou.parse_version("2026.5.0a1"))

    def test_dev_commits_break_ties_within_a_phase(self):
        # build-manifest stamps `<base>-<N>-g<sha>` on commits past the tag —
        # smart-upgrade must treat those as newer than the bare tag.
        self.assertGreater(
            ou.parse_version("2026.5.0b1-3-gabc1234"),
            ou.parse_version("2026.5.0b1"),
        )

    def test_unparseable_returns_lowest_tuple(self):
        # state.json from the dpkg fallback writes "legacy" — must always
        # compare below any valid version so smart-upgrade re-runs the role.
        self.assertEqual(ou.parse_version("legacy"), (0,))
        self.assertLess(ou.parse_version("legacy"), ou.parse_version("2026.4.0a1"))

    def test_equal_versions_are_equal(self):
        self.assertEqual(ou.parse_version("2026.5.0"), ou.parse_version("2026.5.0"))


class IsDowngradeTests(unittest.TestCase):
    def test_target_below_state_is_downgrade(self):
        self.assertTrue(ou._is_downgrade("2026.4.0", "2026.5.0"))

    def test_target_above_state_is_not_downgrade(self):
        self.assertFalse(ou._is_downgrade("2026.5.0", "2026.4.0"))

    def test_target_equal_state_is_not_downgrade(self):
        self.assertFalse(ou._is_downgrade("2026.5.0", "2026.5.0"))

    def test_no_state_odios_is_not_downgrade(self):
        # rc1/rc2 state.json predates the odios field — let install.sh decide.
        self.assertFalse(ou._is_downgrade("2026.5.0", None))

    def test_latest_target_is_not_downgrade(self):
        # "latest" parses to (0,); refuse-on-parse-miss would be wrong here.
        self.assertFalse(ou._is_downgrade("latest", "2026.5.0"))

    def test_unparseable_state_is_not_downgrade(self):
        # dpkg-rebuilt state.odios may be "legacy" — let install.sh resolve.
        self.assertFalse(ou._is_downgrade("2026.5.0", "legacy"))

    def test_git_describe_state_compares_correctly(self):
        # build-manifest stamps `<base>-<N>-g<sha>` past a tag; a target on
        # the bare tag is older than the dev-commit suffix.
        self.assertTrue(ou._is_downgrade("2026.5.0b1", "2026.5.0b1-3-gabc1234"))


class ManifestUrlTests(unittest.TestCase):
    def test_latest_uses_releases_latest_path(self):
        self.assertEqual(
            ou.manifest_url("latest"),
            f"https://github.com/{ou.GITHUB_REPO}/releases/latest/download/manifest.json",
        )

    def test_specific_version_uses_release_tag(self):
        self.assertEqual(
            ou.manifest_url("2026.5.0"),
            f"https://github.com/{ou.GITHUB_REPO}/releases/download/2026.5.0/manifest.json",
        )

    def test_pr_prerelease_uses_pr_tag(self):
        # PR pre-releases tag as `pr-<N>` — odio-upgrade must hit that asset.
        self.assertEqual(
            ou.manifest_url("pr-42"),
            f"https://github.com/{ou.GITHUB_REPO}/releases/download/pr-42/manifest.json",
        )


class FetchManifestTests(unittest.TestCase):
    def test_returns_parsed_json_on_success(self):
        body = b'{"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}'
        fake = MagicMock()
        fake.__enter__.return_value.read.return_value = body
        with patch.object(ou.urllib.request, "urlopen", return_value=fake):
            result = ou.fetch_manifest("https://example.invalid/manifest.json")
        self.assertEqual(result, {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}})

    def test_returns_none_on_network_failure(self):
        # Per the issue contract: any fetch failure falls back to "run all
        # roles" by returning None — derive_run_env emits no RUN_X overrides,
        # so install.sh's defaults take over.
        with patch.object(ou.urllib.request, "urlopen", side_effect=OSError("boom")):
            self.assertIsNone(ou.fetch_manifest("https://example.invalid/manifest.json"))


class DeriveRunEnvTests(unittest.TestCase):
    @staticmethod
    def _state(
        roles: dict[str, str],
        excluded: list[str] | None = None,
        odios: str | None = None,
    ) -> State:
        return _state(roles=roles, roles_excluded=excluded, odios=odios)

    @staticmethod
    def _manifest(roles: dict[str, str], odios: str = "2026.5.0") -> Manifest:
        return {"odios": odios, "roles": roles}

    def _install_env(self, **flags: str) -> dict[str, str]:
        # Convenience: only set INSTALL_<ROLE>=N for excluded roles, mirroring
        # derive_install_env's actual output (Y/absent/N).
        return {f"INSTALL_{r.upper()}": v for r, v in flags.items()}

    def test_no_manifest_returns_empty(self):
        # Manifest fetch failed → emit nothing → install.sh defaults to
        # RUN_X=INSTALL_X for every role (today's behaviour).
        self.assertEqual(
            ou.derive_run_env(self._state({"mpd": "2026.5.0"}), None, {}),
            {},
        )

    def test_unchanged_role_emits_run_n(self):
        state = self._state({"mpd": "2026.5.0"})
        manifest = self._manifest({"mpd": "2026.5.0"})
        env = ou.derive_run_env(state, manifest, self._install_env(mpd="Y"))
        self.assertEqual(env.get("RUN_MPD"), "N")

    def test_bumped_role_is_not_emitted(self):
        # Asymmetric contract: only N is exported. A bumped role gets no
        # RUN_X key — install.sh's RUN_X=${RUN_X:-$INSTALL_X} default keeps
        # it Y so the role runs.
        state = self._state({"mpd": "2026.4.0"})
        manifest = self._manifest({"mpd": "2026.5.0"})
        env = ou.derive_run_env(state, manifest, self._install_env(mpd="Y"))
        self.assertNotIn("RUN_MPD", env)

    def test_excluded_role_is_skipped(self):
        # User excluded the role (INSTALL_X=N already gates it). Whether or
        # not its version matches is irrelevant — don't emit a run flag.
        state = self._state({}, excluded=["spotifyd"])
        manifest = self._manifest({"spotifyd": "0.4.4"})
        env = ou.derive_run_env(state, manifest, self._install_env(spotifyd="N"))
        self.assertNotIn("RUN_SPOTIFYD", env)

    def test_role_new_in_target_is_not_emitted(self):
        # Role exists in target manifest but missing from state.json (a new
        # role added in this release). installed=None → no RUN_X=N → install.sh
        # default Y → role runs and gets installed for the first time.
        state = self._state({"mpd": "2026.5.0"})
        manifest = self._manifest({"mpd": "2026.5.0", "spotifyd": "0.4.4"})
        env = ou.derive_run_env(state, manifest, self._install_env(mpd="Y"))
        self.assertNotIn("RUN_SPOTIFYD", env)

    def test_role_missing_from_manifest_is_not_emitted(self):
        # Out-of-scope per issue (deinstall on upgrade). Make sure we don't
        # accidentally emit RUN_X=N which would suppress a role the user has
        # on the box and might still need to maintain.
        state = self._state({"snapclient": "0.27.0"})
        manifest = self._manifest({})
        env = ou.derive_run_env(state, manifest, self._install_env(snapclient="Y"))
        self.assertNotIn("RUN_SNAPCLIENT", env)

    def test_common_emission_is_overridden_by_install_sh(self):
        # `derive_run_env` itself emits RUN_COMMON=N for an unchanged common
        # — the loop has no special case. install.sh hard-sets RUN_COMMON=Y
        # *after* sourcing odio-upgrade's env, which guarantees common (and
        # therefore the single playbook-wide apt update) always runs. We
        # only document the python-side behaviour here; the install.sh
        # override is the actual invariant.
        state = self._state({"common": "2026.5.0"})
        manifest = self._manifest({"common": "2026.5.0"})
        env = ou.derive_run_env(state, manifest, {})
        self.assertEqual(env.get("RUN_COMMON"), "N")

    def test_emits_n_for_every_unchanged_role(self):
        # Sanity: when every installed role matches the manifest, every
        # role gets RUN_X=N — the maximum-skip case the feature exists for.
        roles = {"mpd": "2026.5.0", "odio_api": "2026.5.0", "upgrade": "2026.5.0"}
        install_env = {f"INSTALL_{r.upper()}": "Y" for r in roles}
        env = ou.derive_run_env(
            self._state(roles), self._manifest(roles), install_env
        )
        for role in roles:
            self.assertEqual(env[f"RUN_{role.upper()}"], "N", role)

    def test_legacy_version_string_is_treated_as_outdated(self):
        # state_from_dpkg writes "legacy" when no real version info exists.
        # parse_version("legacy") → (0,) → always less than the manifest
        # version → role re-runs (no RUN_X=N emitted).
        state = self._state({"mpd": "legacy"})
        manifest = self._manifest({"mpd": "2026.5.0"})
        env = ou.derive_run_env(state, manifest, self._install_env(mpd="Y"))
        self.assertNotIn("RUN_MPD", env)

    def test_role_ahead_of_state_odios_re_runs(self):
        # PR-iteration trap: role bumped to 2026.5.0b1 on a previous PR run,
        # state.odios stayed at the pre-tag dev describe. Manifest still says
        # 2026.5.0b1 (no second bump allowed within the same PR), so the bare
        # target == installed comparison would skip — but `installed` is ahead
        # of state.odios, meaning the role file is in flight. Force re-run.
        state = self._state(
            {"bluetooth": "2026.5.0b1"},
            odios="2026.4.2b2-8-g6375a44",
        )
        manifest = self._manifest({"bluetooth": "2026.5.0b1"})
        env = ou.derive_run_env(state, manifest, self._install_env(bluetooth="Y"))
        self.assertNotIn("RUN_BLUETOOTH", env)

    def test_role_at_or_below_state_odios_still_skips_when_unchanged(self):
        # Release path: after a tag, state.odios catches up so every role's
        # recorded version is <= state.odios. Smart-upgrade must keep skipping
        # unchanged roles in that regime.
        state = self._state(
            {"shairport_sync": "2026.4.1rc1"},
            odios="2026.4.2b2",
        )
        manifest = self._manifest({"shairport_sync": "2026.4.1rc1"})
        env = ou.derive_run_env(state, manifest, self._install_env(shairport_sync="Y"))
        self.assertEqual(env.get("RUN_SHAIRPORT_SYNC"), "N")

    def test_state_without_odios_falls_back_to_target_vs_installed(self):
        # dpkg-rebuilt states have no `odios` field. The extra guard must
        # not regress the existing target == installed → skip behaviour.
        state = self._state({"mpd": "2026.5.0"})  # no odios
        manifest = self._manifest({"mpd": "2026.5.0"})
        env = ou.derive_run_env(state, manifest, self._install_env(mpd="Y"))
        self.assertEqual(env.get("RUN_MPD"), "N")


class LoadStateTests(unittest.TestCase):
    def _opts(self, state: str | None = None) -> ou.ApplyOptions:
        return ou.ApplyOptions(state=state)

    def test_opts_state_valid_returns_path_state_and_target_user(self):
        raw: StateLegacy = {
            "odios": "2026.4.0",
            "roles": {"mpd": "2026.4.0"},
            "target_user": "alice",
        }
        with (
            patch.object(ou, "_read_state_file", return_value=raw),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = ou._load_state(self._opts(state="/etc/odio/state.json"))
        assert result is not None
        path, state, user = result
        self.assertEqual(path, "/etc/odio/state.json")
        self.assertEqual(user, "alice")
        self.assertEqual(state["roles"], {"mpd": "2026.4.0"})

    def test_opts_state_unreadable_returns_none_and_writes_to_stderr(self):
        err = io.StringIO()
        with (
            patch.object(ou, "_read_state_file", side_effect=OSError("boom")),
            contextlib.redirect_stderr(err),
        ):
            result = ou._load_state(self._opts(state="/missing"))
        self.assertIsNone(result)
        self.assertIn("Error reading /missing", err.getvalue())

    def test_opts_state_without_target_user_falls_back_to_invoking_user(self):
        # rc1/rc2 state.json predates target_user — must not crash and must
        # fall back to whoever is running the upgrade.
        raw: StateLegacy = {"odios": "2026.4.0", "roles": {}}
        with (
            patch.object(ou, "_read_state_file", return_value=raw),
            patch.object(ou, "_invoking_user", return_value="bob"),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = ou._load_state(self._opts(state="/p"))
        assert result is not None
        _, _, user = result
        self.assertEqual(user, "bob")

    def test_no_opts_state_uses_find_state_and_its_target_user(self):
        raw: StateLegacy = {"odios": "2026.4.0", "roles": {"mpd": "2026.4.0"}}
        with (
            patch.object(ou, "find_state", return_value=("/p", raw, "alice")),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = ou._load_state(self._opts())
        assert result is not None
        path, _, user = result
        self.assertEqual(path, "/p")
        self.assertEqual(user, "alice")

    def test_no_opts_state_and_no_state_file_falls_back_to_dpkg(self):
        # find_state returns (None, None, None) → reconstruct from dpkg with
        # the resolved (possibly prompted) target_user. state_path is None so
        # the caller knows to write upgrades.json to the system path.
        rebuilt: State = {
            "roles": {"mpd": "x"},
            "roles_excluded": [],
            "features": [],
            "features_excluded": [],
        }
        with (
            patch.object(ou, "find_state", return_value=(None, None, None)),
            patch.object(ou, "_invoking_user", return_value="alice"),
            patch.object(ou, "resolve_target_user", return_value="odio"),
            patch.object(ou, "state_from_dpkg", return_value=rebuilt),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = ou._load_state(self._opts())
        assert result is not None
        path, state, user = result
        self.assertIsNone(path)
        self.assertEqual(user, "odio")
        self.assertEqual(state["roles"], {"mpd": "x"})


class BuildApplyEnvTests(unittest.TestCase):
    def test_skipped_roles_are_listed_and_run_n_emitted(self):
        state = _state(roles={"mpd": "2026.5.0"}, odios="2026.5.0")
        manifest: Manifest = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        out = io.StringIO()
        with (
            patch.object(ou, "fetch_manifest", return_value=manifest),
            contextlib.redirect_stdout(out),
        ):
            env = ou._build_apply_env(state, "2026.5.0", "alice", "/nonexistent/upgrades.json")
        self.assertEqual(env["TARGET_USER"], "alice")
        self.assertEqual(env["ODIOS_VERSION"], "2026.5.0")
        self.assertEqual(env.get("RUN_MPD"), "N")
        self.assertIn("skipping unchanged roles: mpd", out.getvalue())

    def test_no_manifest_logs_unavailable_and_emits_no_run_overrides(self):
        state = _state(roles={"mpd": "2026.4.0"}, odios="2026.4.0")
        out = io.StringIO()
        with (
            patch.object(ou, "fetch_manifest", return_value=None),
            contextlib.redirect_stdout(out),
        ):
            env = ou._build_apply_env(state, "2026.5.0", "alice", "/nonexistent/upgrades.json")
        self.assertNotIn("RUN_MPD", env)
        self.assertIn("manifest unavailable", out.getvalue())

    def test_all_roles_bumped_logs_running_everything(self):
        state = _state(roles={"mpd": "2026.4.0"}, odios="2026.4.0")
        manifest: Manifest = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        out = io.StringIO()
        with (
            patch.object(ou, "fetch_manifest", return_value=manifest),
            contextlib.redirect_stdout(out),
        ):
            env = ou._build_apply_env(state, "2026.5.0", "alice", "/nonexistent/upgrades.json")
        self.assertNotIn("RUN_MPD", env)
        self.assertIn("all roles bumped", out.getvalue())


class ComputeRoleUpgradesTests(unittest.TestCase):
    @staticmethod
    def _manifest(roles: dict[str, str]) -> Manifest:
        return {"odios": "2026.5.0", "roles": roles}

    @staticmethod
    def _legacy(roles: dict[str, str]) -> StateLegacy:
        return {"roles": roles}

    def test_role_with_newer_manifest_version_is_listed(self):
        upgrades = ou._compute_role_upgrades(
            self._legacy({"mpd": "2026.4.0"}),
            self._manifest({"mpd": "2026.5.0"}),
        )
        self.assertEqual(
            upgrades,
            [{"name": "mpd", "installed": "2026.4.0", "available": "2026.5.0"}],
        )

    def test_role_unchanged_is_excluded(self):
        upgrades = ou._compute_role_upgrades(
            self._legacy({"mpd": "2026.5.0"}),
            self._manifest({"mpd": "2026.5.0"}),
        )
        self.assertEqual(upgrades, [])

    def test_role_with_older_manifest_version_is_excluded(self):
        # Downgrade is not an "upgrade" — keep it out of the report so the
        # CLI summary doesn't lie about what's pending.
        upgrades = ou._compute_role_upgrades(
            self._legacy({"mpd": "2026.5.0"}),
            self._manifest({"mpd": "2026.4.0"}),
        )
        self.assertEqual(upgrades, [])

    def test_role_missing_from_manifest_is_excluded(self):
        upgrades = ou._compute_role_upgrades(
            self._legacy({"snapclient": "0.27.0"}),
            self._manifest({}),
        )
        self.assertEqual(upgrades, [])

    def test_results_are_sorted_alphabetically(self):
        upgrades = ou._compute_role_upgrades(
            self._legacy({"zzz": "2026.4.0", "aaa": "2026.4.0"}),
            self._manifest({"zzz": "2026.5.0", "aaa": "2026.5.0"}),
        )
        self.assertEqual([u["name"] for u in upgrades], ["aaa", "zzz"])


class BuildUpgradesReportTests(unittest.TestCase):
    def test_upgrade_available_when_a_role_is_bumped(self):
        state: StateLegacy = {"odios": "2026.5.0", "roles": {"mpd": "2026.4.0"}}
        report = ou._build_upgrades_report(
            state, {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}},
        )
        self.assertTrue(report["upgrade_available"])
        self.assertEqual(report["current"], "2026.5.0")
        self.assertEqual(report["latest"], "2026.5.0")
        self.assertEqual(len(report["roles"]), 1)

    def test_upgrade_available_when_only_odios_is_bumped(self):
        # Installer-only releases (umbrella metadata, no role bumps) must
        # still surface as an upgrade — that's the OR in upgrade_available.
        state: StateLegacy = {"odios": "2026.4.0", "roles": {"mpd": "2026.5.0"}}
        report = ou._build_upgrades_report(
            state, {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}},
        )
        self.assertTrue(report["upgrade_available"])
        self.assertEqual(report["roles"], [])

    def test_up_to_date_when_neither_odios_nor_roles_bumped(self):
        state: StateLegacy = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        report = ou._build_upgrades_report(
            state, {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}},
        )
        self.assertFalse(report["upgrade_available"])
        self.assertEqual(report["roles"], [])

    def test_full_manifest_is_cached_alongside_delta(self):
        # `roles` stays delta-only (consumed by odio-motd in the {name,
        # installed, available} shape); the full target manifest is cached
        # under `manifest` so `apply` skips refetching.
        state: StateLegacy = {"odios": "2026.4.0", "roles": {"mpd": "2026.4.0"}}
        manifest: Manifest = {
            "odios": "2026.5.0",
            "roles": {"mpd": "2026.5.0", "spotifyd": "0.4.4"},
        }
        report = ou._build_upgrades_report(state, manifest)
        self.assertEqual(report["manifest"], manifest)
        self.assertEqual([r["name"] for r in report["roles"]], ["mpd"])
        # motd contract: each delta entry must keep the {name, installed,
        # available} keys in that exact shape — odio-motd reads them by
        # name and breaks silently if the field set drifts.
        for entry in report["roles"]:
            self.assertEqual(set(entry.keys()), {"name", "installed", "available"})


class ResolveManifestTests(unittest.TestCase):
    def _upgrades_file(self, payload: dict[str, Any]) -> str:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(payload, f)
            self.addCleanup(os.unlink, f.name)
            return f.name

    def test_returns_cached_manifest_on_version_match(self):
        # Daily check has cached the target manifest in upgrades.json.
        # `apply` for that version must reuse it without a network call.
        manifest = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        path = self._upgrades_file({"latest": "2026.5.0", "manifest": manifest})
        with patch.object(ou, "fetch_manifest") as fetch:
            result = ou._resolve_manifest("2026.5.0", path)
        fetch.assert_not_called()
        self.assertEqual(result, manifest)

    def test_falls_back_to_fetch_on_version_mismatch(self):
        # Cached entry advertises a different `latest` than the requested
        # version (e.g. user passed --version explicitly) — go to network.
        cached = {"odios": "2026.4.0", "roles": {}}
        target = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        path = self._upgrades_file({"latest": "2026.4.0", "manifest": cached})
        with patch.object(ou, "fetch_manifest", return_value=target) as fetch:
            result = ou._resolve_manifest("2026.5.0", path)
        fetch.assert_called_once()
        self.assertEqual(result, target)

    def test_falls_back_to_fetch_when_file_missing(self):
        # Fresh install before the daily timer fires — no upgrades.json on
        # disk. Resolver must not raise; it transparently fetches.
        target = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        with patch.object(ou, "fetch_manifest", return_value=target) as fetch:
            result = ou._resolve_manifest("2026.5.0", "/nonexistent/upgrades.json")
        fetch.assert_called_once()
        self.assertEqual(result, target)

    def test_falls_back_to_fetch_when_manifest_field_absent(self):
        # Pre-cache vintage upgrades.json (no `manifest` key) — treat as a
        # cache miss rather than crashing on the missing field.
        path = self._upgrades_file({"latest": "2026.5.0", "roles": []})
        target = {"odios": "2026.5.0", "roles": {"mpd": "2026.5.0"}}
        with patch.object(ou, "fetch_manifest", return_value=target) as fetch:
            result = ou._resolve_manifest("2026.5.0", path)
        fetch.assert_called_once()
        self.assertEqual(result, target)


class VerifyChecksTests(unittest.TestCase):
    def test_features_known_passes_for_subset(self):
        s = _state(features=["tidal"], features_excluded=["qobuz"])
        self.assertIsNone(ou._check_features_known(s))

    def test_features_known_flags_unknown(self):
        s = _state(features=["tidal", "bogus"])
        err = ou._check_features_known(s)
        assert err is not None
        self.assertIn("bogus", err)

    def test_features_no_overlap_passes_for_disjoint(self):
        s = _state(features=["tidal"], features_excluded=["qobuz"])
        self.assertIsNone(ou._check_features_no_overlap(s))

    def test_features_no_overlap_flags_collision(self):
        s = _state(features=["tidal"], features_excluded=["tidal"])
        err = ou._check_features_no_overlap(s)
        assert err is not None
        self.assertIn("tidal", err)

    def test_history_matches_passes_when_last_equals_odios(self):
        s = _state(odios="2026.5.0", release_history=["2026.4.0", "2026.5.0"])
        self.assertIsNone(ou._check_history_matches_odios(s))

    def test_history_matches_passes_when_history_absent(self):
        # dpkg-reconstructed states have no history yet — not an error.
        s = _state(odios="2026.5.0")
        self.assertIsNone(ou._check_history_matches_odios(s))

    def test_history_matches_flags_drift(self):
        s = _state(odios="2026.5.0", release_history=["2026.4.0"])
        err = ou._check_history_matches_odios(s)
        assert err is not None
        self.assertIn("2026.4.0", err)
        self.assertIn("2026.5.0", err)

    def test_expected_version_release_tag_exact_match(self):
        s = _state(odios="2026.5.0")
        self.assertIsNone(ou._check_expected_version(s, "2026.5.0"))

    def test_expected_version_release_tag_mismatch(self):
        s = _state(odios="2026.4.2b2")
        err = ou._check_expected_version(s, "2026.5.0")
        assert err is not None
        self.assertIn("2026.4.2b2", err)

    def test_expected_version_pr_accepts_git_describe(self):
        s = _state(odios="2026.4.2b2-20-g7c1f6c4")
        self.assertIsNone(ou._check_expected_version(s, "pr-56"))

    def test_expected_version_pr_rejects_garbage_string(self):
        s = _state(odios="not-a-version")
        err = ou._check_expected_version(s, "pr-56")
        assert err is not None
        self.assertIn("not-a-version", err)


if __name__ == "__main__":
    unittest.main()
