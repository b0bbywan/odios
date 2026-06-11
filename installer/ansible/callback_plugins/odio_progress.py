"""Emit structured install/upgrade progress for odio-api to consume.

Prints one `ODIO_PROGRESS=<json>` line per milestone to stdout (captured by
journald when run under odio-upgrade.service) and mirrors the latest event to
/var/cache/odio/upgrade-status.json for late-joining / post-restart clients.

Event schema (the contract odio-api parses): a generic begin/progress/end
core, enriched with ansible-flavoured fields a generic consumer can ignore.
  {"event": "begin",    "total": N, "roles": [..]}
  {"event": "progress", "percent": P, "current": i, "step": "mpd"}
  {"event": "end",      "success": true|false, "changed": N}
"""
from __future__ import annotations

import json
import os
from typing import Literal, TypedDict

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = """
  name: odio_progress
  type: notification
  short_description: structured install/upgrade progress for odio-api
  description: Emits ODIO_PROGRESS JSON lines and a status file per role.
  requirements:
    - enable in configuration (callbacks_enabled)
"""

PREFIX = "ODIO_PROGRESS="
STATUS_PATH = "/var/cache/odio/upgrade-status.json"


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
        self._seen: set[str] = set()

    def _emit(self, payload: Event) -> None:
        self._display.display(PREFIX + json.dumps(payload, sort_keys=True))
        self._write_status(payload)

    @staticmethod
    def _write_status(payload: Event) -> None:
        # Best-effort: /var/cache/odio may not exist yet on a fresh install,
        # and the journal already carries every event — never break the run.
        try:
            tmp = STATUS_PATH + ".tmp"
            with open(tmp, "w") as f:
                json.dump(payload, f)
            os.replace(tmp, STATUS_PATH)
        except OSError:
            pass

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
        self._emit(BeginEvent(event="begin", total=len(roles), roles=roles))

    def v2_playbook_on_task_start(self, task, is_conditional):
        # First task of each planned role emits one progress event, in encounter
        # order (== playbook order). Handlers re-entering a finished role at
        # flush time are already in _seen, so they don't double-count.
        role = getattr(task, "_role", None)
        name = role.get_name() if role else None
        if name and name in self._plan and name not in self._seen:
            self._seen.add(name)
            current = len(self._seen)
            total = len(self._plan)
            percent = round(100 * (current - 1) / total) if total else 0
            self._emit(ProgressEvent(
                event="progress", percent=percent, current=current, step=name,
            ))

    def v2_playbook_on_stats(self, stats):
        failed = bool(stats.failures or stats.dark)
        changed = sum(stats.changed.values())
        self._emit(EndEvent(event="end", success=not failed, changed=changed))
