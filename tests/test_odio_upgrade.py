#!/usr/bin/env python3
"""Unit tests for odio-upgrade's state-reconstruction logic.

Covers the three input shapes the upgrade script must handle:
  - no state.json → state_from_dpkg + backfill
  - state.json without features/roles_excluded (rc1/rc2) → backfill
  - full current-schema state.json → identity through backfill

Run with: python3 -m unittest tests.test_odio_upgrade
"""
import importlib.machinery
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

_SCRIPT = Path(__file__).resolve().parents[1] / "installer/ansible/roles/upgrade/files/odio-upgrade"
_spec = importlib.util.spec_from_loader(
    "odio_upgrade",
    importlib.machinery.SourceFileLoader("odio_upgrade", str(_SCRIPT)),
)
ou = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ou)


class DeriveInstallEnvTests(unittest.TestCase):
    def test_installed_role_maps_to_Y(self):
        env = ou.derive_install_env({"roles": {"pulseaudio": "x"}})
        self.assertEqual(env["INSTALL_PULSEAUDIO"], "Y")

    def test_excluded_role_maps_to_N(self):
        env = ou.derive_install_env({"roles": {}, "roles_excluded": ["spotifyd"]})
        self.assertEqual(env["INSTALL_SPOTIFYD"], "N")

    def test_role_absent_from_both_is_not_emitted(self):
        # Opt-out semantic: anything not in roles/roles_excluded is left unset
        # so install.sh's own defaults (Y for optionals in upgrade-era releases)
        # take over. That's how a role added after this script was written
        # self-installs on upgrade.
        env = ou.derive_install_env({"roles": {}, "roles_excluded": []})
        self.assertNotIn("INSTALL_BRANDING", env)
        self.assertNotIn("INSTALL_MPD", env)

    def test_feature_absent_from_both_is_not_emitted(self):
        env = ou.derive_install_env(
            {"roles": {}, "features": {}, "features_excluded": []}
        )
        self.assertNotIn("INSTALL_TIDAL", env)

    def test_excluded_feature_maps_to_N(self):
        env = ou.derive_install_env(
            {"roles": {}, "features": {}, "features_excluded": ["tidal"]}
        )
        self.assertEqual(env["INSTALL_TIDAL"], "N")

    def test_feature_in_features_maps_to_Y(self):
        env = ou.derive_install_env({"roles": {}, "features": {"tidal": True}})
        self.assertEqual(env["INSTALL_TIDAL"], "Y")

    def test_branding_role_maps_to_install_branding(self):
        env = ou.derive_install_env({"roles": {"branding": "x"}})
        self.assertEqual(env["INSTALL_BRANDING"], "Y")

    def test_empty_state_emits_nothing(self):
        # No information in state.json → no INSTALL_* keys; install.sh's own
        # defaults govern every flag. This is the contract that lets the local
        # script stay agnostic to roles added by future releases.
        self.assertEqual(ou.derive_install_env({}), {})


class BackfillStateTests(unittest.TestCase):
    def _call(self, state, *, branding=False, tidal=False, qobuz=False, webradios=False):
        motd_path = "/home/u/.local/bin/odio-motd"
        pkg_map = {
            "upmpdcli-tidal": tidal,
            "upmpdcli-qobuz": qobuz,
            "upmpdcli-radios": webradios,
        }
        with patch.object(ou, "_dpkg_installed", side_effect=lambda p: pkg_map.get(p, False)):
            with patch("os.path.isfile", side_effect=lambda p: p == motd_path and branding):
                return ou.backfill_state(state, "u")

    def test_rc1_rc2_state_gets_excluded_roles_and_detected_features(self):
        # rc1/rc2 state only carries `roles`. Backfill must add roles_excluded,
        # promote dpkg-detected features into `features`, and detect the
        # branding role via the odio-motd file. Undetected features are left
        # out of both lists — pure opt-out makes them Y at derive time.
        state = {"roles": {"pulseaudio": "x", "bluetooth": "x", "odio_api": "x"}}
        result = self._call(state, branding=True, tidal=True)

        self.assertIn("branding", result["roles"])
        expected_excluded = sorted(
            set(ou._ROLE_PACKAGES) - {"pulseaudio", "bluetooth", "odio_api"}
        )
        self.assertEqual(result["roles_excluded"], expected_excluded)
        self.assertEqual(result["features"], ["tidal"])
        self.assertEqual(result["features_excluded"], [])

    def test_legacy_dict_features_migrate_to_list_and_excluded(self):
        # Old state.json used {name: bool} for features — True entries become
        # the new features list, False entries move into features_excluded so
        # derive_install_env keeps honoring the opt-out under the new schema.
        state = {
            "roles": {"upmpdcli": "x"},
            "roles_excluded": [],
            "features": {"tidal": True, "qobuz": False, "upnpwebradios": False},
        }
        result = self._call(state)
        self.assertEqual(result["features"], ["tidal"])
        self.assertEqual(result["features_excluded"], ["qobuz", "upnpwebradios"])

    def test_full_state_preserved(self):
        # Current-schema state.json → backfill is a no-op for populated fields.
        state = {
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
        state = {"roles": {"pulseaudio": "x"}, "features": ["tidal"]}
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
        state = {
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
        state = {"roles": {"pulseaudio": "x"}, "features": {"motd": True, "tidal": False}}
        result = self._call(state, branding=True)
        self.assertNotIn("motd", result["features"])
        self.assertNotIn("motd", result["features_excluded"])
        self.assertIn("tidal", result["features_excluded"])
        self.assertIn("branding", result["roles"])


class StateFromDpkgTests(unittest.TestCase):
    def test_roles_reconstructed_from_dpkg(self):
        installed = {"pulseaudio", "bluez", "mpd", "shairport-sync", "odio-api"}
        with patch.object(ou, "_dpkg_installed", side_effect=lambda p: p in installed):
            with patch("os.path.isfile", return_value=False):
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
        with patch.object(ou, "_dpkg_installed", return_value=False):
            with patch("os.path.isfile", side_effect=lambda p: p == motd_path):
                state = ou.state_from_dpkg("u")
        self.assertIn("branding", state["roles"])
        # branding is never auto-excluded — pure opt-out at derive time picks it up.
        self.assertNotIn("branding", state["roles_excluded"])

    def test_dpkg_detected_features_land_in_features(self):
        # Roles + feature packages co-install — the same dpkg pass picks both up.
        installed = {"upmpdcli", "upmpdcli-qobuz", "upmpdcli-tidal"}
        with patch.object(ou, "_dpkg_installed", side_effect=lambda p: p in installed):
            with patch("os.path.isfile", return_value=False):
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
        state = {
            "roles": {r: "x" for r in ou._ROLE_PACKAGES},
            "roles_excluded": [],
            "features": {"qobuz": True, "tidal": True},
            "features_excluded": [],
        }
        pkg_map = {"upmpdcli-qobuz": True, "upmpdcli-tidal": True}
        with patch.object(ou, "_dpkg_installed",
                          side_effect=lambda p: pkg_map.get(p, False)):
            with patch("os.path.isfile", return_value=False):
                state = ou.backfill_state(state, "u")
        env = ou.derive_install_env(state)
        self.assertEqual(env["INSTALL_QOBUZ"], "Y")
        self.assertEqual(env["INSTALL_TIDAL"], "Y")
        self.assertNotIn("INSTALL_UPNPWEBRADIOS", env)  # install.sh default Y
        self.assertNotIn("INSTALL_BRANDING", env)        # install.sh default Y


class ResolveTargetUserTests(unittest.TestCase):
    def test_invoking_user_with_odio_api_config_is_returned_silently(self):
        # If the invoking user already has ~/.config/odio-api/, no prompt.
        with patch.object(ou.os.path, "expanduser", return_value="/home/alice/.config/odio-api"):
            with patch.object(ou.os.path, "isdir", return_value=True):
                with patch("builtins.input", side_effect=AssertionError("should not prompt")):
                    self.assertEqual(ou.resolve_target_user("alice"), "alice")

    def test_prompt_default_odio_when_invoking_user_has_no_config(self):
        with patch.object(ou.os.path, "expanduser", return_value="/nonexistent"):
            with patch.object(ou.os.path, "isdir", return_value=False):
                with patch("builtins.input", return_value=""):
                    with patch.object(ou.pwd, "getpwnam") as gp:
                        self.assertEqual(ou.resolve_target_user("alice"), "odio")
                        gp.assert_called_with("odio")

    def test_prompt_reasks_until_user_exists(self):
        responses = iter(["bogus", "odio"])
        existing = {"odio"}

        def fake_getpwnam(name):
            if name in existing:
                return object()
            raise KeyError(name)

        with patch.object(ou.os.path, "expanduser", return_value="/nonexistent"):
            with patch.object(ou.os.path, "isdir", return_value=False):
                with patch("builtins.input", side_effect=lambda *_: next(responses)):
                    with patch.object(ou.pwd, "getpwnam", side_effect=fake_getpwnam):
                        self.assertEqual(ou.resolve_target_user("alice"), "odio")


if __name__ == "__main__":
    unittest.main()
