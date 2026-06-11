"""Emit structured install/upgrade progress for odio-api to consume.

Prints one `ODIO_PROGRESS=<json>` line per milestone to stdout, captured by
journald when run under odio-upgrade.service; odio-api reads it back from the
journal (no status file on disk).

Event schema (the contract odio-api parses): a generic begin/progress/end
core, enriched with ansible-flavoured fields a generic consumer can ignore.
The ordered steps are the running roles bracketed by synthetic "setup"
(pre_tasks: facts, become, state read) and "finalize" (post_tasks: write
state, restart, health-check) so those phases aren't dead air.
  {"event": "begin",    "total": N, "roles": ["setup", .., "finalize"]}
  {"event": "progress", "percent": P, "current": i, "step": "mpd"}
  {"event": "end",      "success": true|false, "changed": N}
"""
from __future__ import annotations

import json
from typing import Literal, TypedDict

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = """
  name: odio_progress
  type: notification
  short_description: structured install/upgrade progress for odio-api
  description: Emits one ODIO_PROGRESS JSON line per step to stdout.
  requirements:
    - enable in configuration (callbacks_enabled)
"""

PREFIX = "ODIO_PROGRESS="
SETUP = "setup"
FINALIZE = "finalize"


class BeginEvent(TypedDict):
    event: Literal["begin"]
    total: int
    roles: list[str]


class ProgressEvent(TypedDict):
    event: Literal["progress"]
    percent: int
    current: int
    step: str


class EndEvent(TypedDict):
    event: Literal["end"]
    success: bool
    changed: int


Event = BeginEvent | ProgressEvent | EndEvent


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "odio_progress"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self._plan: list[str] = []
        self._total: int = 0
        self._seen: set[str] = set()
        self._current: int = 0
        self._finalize_done: bool = False

    def _emit(self, payload: Event) -> None:
        self._display.display(PREFIX + json.dumps(payload, sort_keys=True))

    def _progress(self, step: str) -> None:
        self._current += 1
        percent = round(100 * (self._current - 1) / self._total) if self._total else 0
        self._emit(ProgressEvent(
            event="progress", percent=percent, current=self._current, step=step,
        ))

    def v2_playbook_on_play_start(self, play):
        # The roles that will actually run are exactly those whose run_<name>
        # var is truthy (install.sh / odio-upgrade derive these). Order follows
        # the playbook's role list, so index i/N is meaningful.
        try:
            variables = play.get_variable_manager().get_vars(play=play)
            roles = [
                r.get_name() for r in play.get_roles()
                if variables.get(f"run_{r.get_name()}", True)
            ]
        except Exception:
            roles = []
        self._plan = roles
        # Steps = the roles bracketed by synthetic setup/finalize markers.
        steps = [SETUP, *roles, FINALIZE]
        self._total = len(steps)
        self._emit(BeginEvent(event="begin", total=self._total, roles=steps))
        # setup is deterministic (the pre_tasks run right after play start), so
        # emit it here rather than depend on a pre_task existing.
        self._progress(SETUP)

    def v2_playbook_on_task_start(self, task, is_conditional):
        role = getattr(task, "_role", None)
        name = role.get_name() if role else None
        if name is None:
            # First roleless task once every planned role is done = post_tasks
            # starting → finalize (shown while restart/health-check run). Fires
            # once; if there are no post_tasks, on_stats emits it as a fallback.
            if not self._finalize_done and self._seen \
                    and len(self._seen) == len(self._plan):
                self._finalize_done = True
                self._progress(FINALIZE)
            return
        # First task of each planned role emits one progress event, in encounter
        # order (== playbook order). Handlers re-entering a finished role at
        # flush time are already in _seen, so they don't double-count.
        if name in self._plan and name not in self._seen:
            self._seen.add(name)
            self._progress(name)

    def v2_playbook_on_stats(self, stats):
        # Guarantee finalize even when the playbook has no post_tasks (so the
        # step advertised in begin is always delivered before end).
        if not self._finalize_done:
            self._finalize_done = True
            self._progress(FINALIZE)
        failed = bool(stats.failures or stats.dark)
        changed = sum(stats.changed.values())
        self._emit(EndEvent(event="end", success=not failed, changed=changed))
