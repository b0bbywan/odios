"""Emit structured install/upgrade progress for odio-api to consume.

Each milestone goes out two ways: one `ODIO_PROGRESS=<json>` line to stdout
(captured by journald for logs and the CI assertion), and the same JSON object,
newline-delimited and unprefixed, over the unix socket odio-api listens on
(`$XDG_RUNTIME_DIR/odio-api/upgrade.sock`). odio-api opens that socket at boot
and relays each line as an upgrade.info event; the socket is the live channel
(no journal polling). Socket I/O runs on a daemon thread so it never blocks the
playbook: the connection is best-effort and reopened lazily, so a run outside
odio-api just writes stdout, and a drop (odio-api restarting mid-upgrade)
reconnects on the next event so later ones, notably `end`, still get through.

Event schema (the contract odio-api parses): a generic begin/progress/end
core, enriched with ansible-flavoured fields a generic consumer can ignore.
The ordered steps are the running roles bracketed by synthetic "setup"
(pre_tasks: facts, become, state read) and "finalize" (post_tasks: write
state, restart, health-check) so those phases aren't dead air.
  {"event": "begin",    "total": N, "roles": ["setup", .., "finalize"]}
  {"event": "progress", "percent": P, "current": i, "step": "mpd"}
  {"event": "end",      "success": true|false, "changed": N}
On failure, `end` also carries `error` (root-cause message) and `step` (the
step that was running when it failed).
"""
from __future__ import annotations

import contextlib
import json
import os
import queue
import socket
import threading
import time
from typing import Literal, TypedDict

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = """
  name: odio_progress
  type: notification
  short_description: structured install/upgrade progress for odio-api
  description: Emits one JSON event per step to stdout and odio-api's unix socket.
  requirements:
    - enable in configuration (callbacks_enabled)
"""

PREFIX = "ODIO_PROGRESS="
SETUP = "setup"
FINALIZE = "finalize"

# Retry the unsent tail across odio-api's end-of-run restart (~1-2s rebind).
RESEND_ATTEMPTS = 6
RESEND_INTERVAL_S = 0.5


def _socket_path() -> str | None:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        # Under sudo (uid 0) /run/user/0 is never the target_user's socket.
        if os.getuid() == 0:
            return None
        runtime = f"/run/user/{os.getuid()}"
    return os.path.join(runtime, "odio-api", "upgrade.sock")


class BeginEvent(TypedDict):
    event: Literal["begin"]
    total: int
    roles: list[str]


class ProgressEvent(TypedDict):
    event: Literal["progress"]
    percent: int
    current: int
    step: str


class _EndCore(TypedDict):
    event: Literal["end"]
    success: bool
    changed: int


class EndEvent(_EndCore, total=False):
    # error/step present only when success is False (py310: no NotRequired).
    error: str
    step: str


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
        self._step: str = ""
        self._error: str | None = None
        self._error_step: str = ""    # step at failure (frozen before finalize)
        self._finalize_done: bool = False
        # Socket I/O runs on a daemon thread so it never blocks the playbook:
        # _emit just enqueues; the worker owns _sock/_pending (no lock needed)
        # and does all connect/reconnect/send work.
        self._sock: socket.socket | None = None
        self._pending: list[str] = []      # events awaiting (re)delivery
        self._ever_connected: bool = False
        self._warned_no_path: bool = False
        self._queue: queue.Queue[str | None] = queue.Queue()
        self._worker = threading.Thread(target=self._run, daemon=True)
        self._worker.start()

    def _run(self) -> None:
        # Drain the queue until the sentinel; None means "finish and stop".
        while True:
            line = self._queue.get()
            if line is None:
                self._drain_pending()
                self._close()
                return
            self._deliver(line)

    def _connect(self) -> None:
        # Best-effort: no listener (run outside odio-api) leaves progress off.
        # Short timeout so a half-restarted odio-api can't stall the worker.
        path = _socket_path()
        if path is None:
            if not self._warned_no_path:
                self._display.warning(
                    "odio_progress: XDG_RUNTIME_DIR unset under root; "
                    "progress socket disabled")
                self._warned_no_path = True
            return
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(1.0)
            sock.connect(path)
            self._sock = sock
            self._ever_connected = True
        except OSError:
            self._sock = None

    def _send(self, line: str) -> bool:
        if self._sock is None:
            self._connect()
        if self._sock is None:
            return False
        try:
            self._sock.sendall((line + "\n").encode())
            return True
        except OSError:
            self._close()
            return False

    def _flush(self) -> None:
        while self._pending and self._send(self._pending[0]):
            self._pending.pop(0)

    def _deliver(self, line: str) -> None:
        # Buffer + flush so a missed event is resent, not dropped.
        self._pending.append(line)
        self._flush()

    def _drain_pending(self) -> None:
        # Bridge odio-api's end-of-run restart: retry the unsent tail.
        if not self._ever_connected:
            return
        for _ in range(RESEND_ATTEMPTS):
            self._flush()
            if not self._pending:
                return
            time.sleep(RESEND_INTERVAL_S)

    def _close(self) -> None:
        if self._sock is not None:
            with contextlib.suppress(OSError):
                self._sock.close()
            self._sock = None

    def _shutdown(self) -> None:
        # Join covers the resend window so a late `end` still lands.
        self._queue.put(None)
        self._worker.join(timeout=RESEND_ATTEMPTS * RESEND_INTERVAL_S + 1)

    def _emit(self, payload: Event) -> None:
        line = json.dumps(payload, sort_keys=True)
        self._display.display(PREFIX + line)  # stdout (journald, CI capture)
        self._queue.put(line)                  # handed to the background sender

    def _progress(self, step: str) -> None:
        self._current += 1
        self._step = step
        percent = round(100 * (self._current - 1) / self._total) if self._total else 0
        self._emit(ProgressEvent(
            event="progress", percent=percent, current=self._current, step=step,
        ))

    def v2_runner_on_failed(self, result, ignore_errors=False):
        if not ignore_errors:           # a tolerated failure isn't an error
            self._capture_error(result)

    def v2_runner_on_unreachable(self, result):
        self._capture_error(result)

    def _capture_error(self, result) -> None:
        if self._error is not None:     # keep the first failure (root cause)
            return
        r = result._result or {}
        task = result._task.get_name() if result._task else "?"
        msg = r.get("msg") or r.get("stderr") or r.get("exception") or "failed"
        self._error = f"{task}: {msg}".strip()
        self._error_step = self._step

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
        end = EndEvent(event="end", success=not failed, changed=changed)
        if failed and self._error:
            end["error"] = self._error
            end["step"] = self._error_step
        self._emit(end)
        self._shutdown()
