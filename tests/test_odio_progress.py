#!/usr/bin/env python3
"""Unit tests for the odio_progress ansible callback.

Drives the v2_* hooks with mocked play/task/stats objects and asserts the
ODIO_PROGRESS events emitted via the (mocked) display.
"""
import json
import sys
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
        self.cb = op.CallbackModule()
        self.cb._display = MagicMock()

    def events(self) -> list[dict[str, object]]:
        out = []
        for call in self.cb._display.display.call_args_list:
            line = call.args[0]
            self.assertTrue(line.startswith(op.PREFIX))
            out.append(json.loads(line[len(op.PREFIX):]))
        return out

    def start(self, roles: list[str]) -> None:
        self.cb.v2_playbook_on_play_start(_play(roles, {r: True for r in roles}))
        self.cb._display.reset_mock()  # drop begin + setup; focus on role progress


class BeginTests(_Base):
    def test_begin_lists_running_roles_bracketed_by_markers(self):
        play = _play(["common", "mpd", "spotifyd"],
                     {"common": True, "mpd": True, "spotifyd": False})
        self.cb.v2_playbook_on_play_start(play)
        self.assertEqual(
            self.events()[0],
            {"event": "begin", "total": 4,
             "roles": ["setup", "common", "mpd", "finalize"]},
        )

    def test_missing_run_var_defaults_to_running(self):
        self.cb.v2_playbook_on_play_start(_play(["common", "mpd"]))
        self.assertEqual(
            self.events()[0]["roles"], ["setup", "common", "mpd", "finalize"],
        )

    def test_get_roles_failure_yields_setup_finalize_only(self):
        play = MagicMock()
        play.get_variable_manager.side_effect = RuntimeError
        self.cb.v2_playbook_on_play_start(play)
        self.assertEqual(
            self.events()[0],
            {"event": "begin", "total": 2, "roles": ["setup", "finalize"]},
        )


class ProgressTests(_Base):
    def test_full_sequence_setup_roles_finalize(self):
        # play_start emits begin + setup; roles then post_tasks drive the rest.
        self.cb.v2_playbook_on_play_start(
            _play(["common", "mpd"], {"common": True, "mpd": True}))
        self.cb.v2_playbook_on_task_start(_task(None), False)      # other pre task
        self.cb.v2_playbook_on_task_start(_task("common"), False)
        self.cb.v2_playbook_on_task_start(_task("common"), False)  # same role
        self.cb.v2_playbook_on_task_start(_task("mpd"), False)
        self.cb.v2_playbook_on_task_start(_task(None), False)      # finalize
        self.cb.v2_playbook_on_task_start(_task(None), False)      # other post task
        self.assertEqual(self.events(), [
            {"event": "begin", "total": 4,
             "roles": ["setup", "common", "mpd", "finalize"]},
            {"event": "progress", "percent": 0, "current": 1, "step": "setup"},
            {"event": "progress", "percent": 25, "current": 2, "step": "common"},
            {"event": "progress", "percent": 50, "current": 3, "step": "mpd"},
            {"event": "progress", "percent": 75, "current": 4, "step": "finalize"},
        ])

    def test_finalize_waits_for_all_roles(self):
        self.start(["common", "mpd"])
        self.cb.v2_playbook_on_task_start(_task("common"), False)  # 1 of 2 roles
        self.cb._display.reset_mock()
        self.cb.v2_playbook_on_task_start(_task(None), False)      # mid-stream roleless
        self.assertEqual(self.events(), [])                       # no premature finalize

    def test_no_pre_post_tasks_still_brackets(self):
        # Only role tasks: setup comes from play_start, finalize from the
        # on_stats fallback. Both bookends still delivered.
        self.cb.v2_playbook_on_play_start(
            _play(["common", "mpd"], {"common": True, "mpd": True}))
        self.cb.v2_playbook_on_task_start(_task("common"), False)
        self.cb.v2_playbook_on_task_start(_task("mpd"), False)
        self.cb.v2_playbook_on_stats(_stats(changed=2))
        self.assertEqual(self.events(), [
            {"event": "begin", "total": 4,
             "roles": ["setup", "common", "mpd", "finalize"]},
            {"event": "progress", "percent": 0, "current": 1, "step": "setup"},
            {"event": "progress", "percent": 25, "current": 2, "step": "common"},
            {"event": "progress", "percent": 50, "current": 3, "step": "mpd"},
            {"event": "progress", "percent": 75, "current": 4, "step": "finalize"},
            {"event": "end", "success": True, "changed": 2},
        ])

    def test_empty_plan_emits_setup_finalize_only(self):
        self.cb.v2_playbook_on_play_start(_play([], {}))
        self.cb.v2_playbook_on_stats(_stats())
        self.assertEqual(self.events(), [
            {"event": "begin", "total": 2, "roles": ["setup", "finalize"]},
            {"event": "progress", "percent": 0, "current": 1, "step": "setup"},
            {"event": "progress", "percent": 50, "current": 2, "step": "finalize"},
            {"event": "end", "success": True, "changed": 0},
        ])

    def test_finalize_not_double_emitted(self):
        # Fired by a post_task already → the on_stats fallback must not repeat it.
        self.start(["common"])
        self.cb.v2_playbook_on_task_start(_task("common"), False)
        self.cb.v2_playbook_on_task_start(_task(None), False)      # finalize
        self.cb._display.reset_mock()
        self.cb.v2_playbook_on_stats(_stats())
        self.assertEqual(
            self.events(), [{"event": "end", "success": True, "changed": 0}],
        )

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


if __name__ == "__main__":
    unittest.main()
