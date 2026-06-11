#!/usr/bin/env python3
"""Unit tests for the odio_progress ansible callback.

Drives the v2_* hooks with mocked play/task/stats objects and asserts the
ODIO_PROGRESS events emitted via the (mocked) display.
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(
    0,
    str(Path(__file__).resolve().parents[1] / "installer/ansible/callback_plugins"),
)
import odio_progress as op


def _role(name: str) -> MagicMock:
    r = MagicMock()
    r.get_name.return_value = name
    return r


def _play(roles: list[str], run_vars: dict[str, bool] | None = None) -> MagicMock:
    play = MagicMock()
    play.get_roles.return_value = [_role(n) for n in roles]
    vm = play.get_variable_manager.return_value
    vm.get_vars.return_value = {f"run_{k}": v for k, v in (run_vars or {}).items()}
    return play


def _task(role_name: str | None) -> MagicMock:
    t = MagicMock()
    t._role = _role(role_name) if role_name is not None else None
    return t


def _stats(changed: int = 0, failed: bool = False) -> MagicMock:
    s = MagicMock()
    s.changed = {"localhost": changed} if changed else {}
    s.failures = {"localhost": 1} if failed else {}
    s.dark = {}
    return s


class _Base(unittest.TestCase):
    def setUp(self) -> None:
        # Redirect the status mirror into a throwaway dir.
        self._dir = tempfile.mkdtemp()
        self._status = str(Path(self._dir) / "status.json")
        self._orig_status = op.STATUS_PATH
        op.STATUS_PATH = self._status
        self.cb = op.CallbackModule()
        self.cb._display = MagicMock()

    def tearDown(self) -> None:
        op.STATUS_PATH = self._orig_status
        shutil.rmtree(self._dir, ignore_errors=True)

    def events(self) -> list[dict[str, object]]:
        out = []
        for call in self.cb._display.display.call_args_list:
            line = call.args[0]
            self.assertTrue(line.startswith(op.PREFIX))
            out.append(json.loads(line[len(op.PREFIX):]))
        return out

    def start(self, roles: list[str]) -> None:
        self.cb.v2_playbook_on_play_start(_play(roles, {r: True for r in roles}))
        self.cb._display.reset_mock()  # drop the begin event for progress tests


class BeginTests(_Base):
    def test_begin_lists_only_running_roles(self):
        play = _play(["common", "mpd", "spotifyd"],
                     {"common": True, "mpd": True, "spotifyd": False})
        self.cb.v2_playbook_on_play_start(play)
        self.assertEqual(
            self.events(),
            [{"event": "begin", "total": 2, "roles": ["common", "mpd"]}],
        )

    def test_missing_run_var_defaults_to_running(self):
        self.cb.v2_playbook_on_play_start(_play(["common", "mpd"]))
        self.assertEqual(self.events()[0]["roles"], ["common", "mpd"])

    def test_get_roles_failure_yields_empty_plan(self):
        play = MagicMock()
        play.get_variable_manager.side_effect = RuntimeError
        self.cb.v2_playbook_on_play_start(play)
        self.assertEqual(
            self.events(), [{"event": "begin", "total": 0, "roles": []}],
        )


class ProgressTests(_Base):
    def test_one_progress_per_role_in_order(self):
        self.start(["common", "mpd"])
        self.cb.v2_playbook_on_task_start(_task("common"), False)
        self.cb.v2_playbook_on_task_start(_task("common"), False)  # same role
        self.cb.v2_playbook_on_task_start(_task("mpd"), False)
        self.assertEqual(self.events(), [
            {"event": "progress", "percent": 0, "current": 1, "step": "common"},
            {"event": "progress", "percent": 50, "current": 2, "step": "mpd"},
        ])

    def test_handler_reentry_does_not_double_count(self):
        self.start(["common", "mpd"])
        self.cb.v2_playbook_on_task_start(_task("common"), False)
        self.cb.v2_playbook_on_task_start(_task("mpd"), False)
        self.cb._display.reset_mock()
        self.cb.v2_playbook_on_task_start(_task("common"), False)  # handler flush
        self.assertEqual(self.events(), [])

    def test_role_not_in_plan_is_ignored(self):
        self.start(["common", "mpd"])
        self.cb.v2_playbook_on_task_start(_task("spotifyd"), False)
        self.assertEqual(self.events(), [])

    def test_roleless_task_is_ignored(self):
        self.start(["common"])
        self.cb.v2_playbook_on_task_start(_task(None), False)
        self.assertEqual(self.events(), [])


class EndTests(_Base):
    def test_end_success(self):
        self.cb.v2_playbook_on_stats(_stats(changed=3, failed=False))
        self.assertEqual(
            self.events()[-1],
            {"event": "end", "success": True, "changed": 3},
        )

    def test_end_failure_sets_success_false(self):
        self.cb.v2_playbook_on_stats(_stats(changed=1, failed=True))
        self.assertFalse(self.events()[-1]["success"])


class StatusFileTests(_Base):
    def test_latest_event_mirrored_to_status_file(self):
        self.cb.v2_playbook_on_play_start(_play(["mpd"], {"mpd": True}))
        with open(self._status) as f:
            self.assertEqual(json.load(f)["event"], "begin")


if __name__ == "__main__":
    unittest.main()
