#!/usr/bin/env python3
"""
Background event watcher for hermes-webui (or any long-lived process).

Polls a /health endpoint, the PID file, the shim marker directory,
and the SIGPIPE disposition. Logs every state change with millisecond
timestamps. Designed to be started BEFORE a known event (update
click, restart, etc.) and reviewed AFTER.

Usage:
    python3 scripts/event-watcher.py
        # logs to /tmp/hermes-webui-shim/event-watch.log
        # prints to stdout
        # stop with Ctrl-C (SIGINT) or kill -TERM

Outputs:
    /tmp/hermes-webui-shim/event-watch.log — append-only event log
    stdout — same content (handy for `tail -f`)

State changes that are logged (not the steady state):
    - HEALTH CHANGED:   ('up',200) -> ('down', URLError) etc.
    - PIDFILE CHANGED:  31984 -> 31987 (server restarted)
    - MARKER COUNT:     13 -> 14 (a new shim marker appeared)
                        — also lists the kind/pid/signal of the
                          last 3 markers
    - SIGPIPE DISP:     SIG_IGN -> SIG_DFL (handler was overridden)
                        — important for catching shim regressions

The watcher itself adds 1 file to the marker dir
(event-watch.log, NOT a .json marker) which is why the
"marker count" baseline includes that log file.

Configuration (edit the constants below):
    HEALTH_URL       — what to poll
    PIDFILE          — where the server writes its PID
    SHIM_DIR         — where the diag shim writes markers
    POLL_INTERVAL_S  — 1 second is fine for events that take
                       minutes; bump to 0.5 for tighter capture
"""

import os
import sys
import time
import ctypes
import urllib.request
import urllib.error
import json
from datetime import datetime, timezone

# === Config — adjust to your deployment ===
HEALTH_URL = "http://127.0.0.1:8787/health"
PIDFILE = "/root/.hermes/webui.pid"
SHIM_DIR = "/tmp/hermes-webui-shim"
POLL_INTERVAL_S = 1.0
# ==========================================


def ts() -> str:
    n = datetime.now(timezone.utc)
    return f"{n.strftime('%H:%M:%S')}.{n.microsecond // 1000:03d}"


def log(line: str) -> None:
    line = f"[{ts()}] {line}"
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")
    print(line, flush=True)


def check_health() -> tuple:
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=1) as r:
            return ("up", r.status)
    except urllib.error.HTTPError as e:
        return ("http", e.code)
    except Exception as e:
        return ("down", type(e).__name__)


def get_pid() -> int | None:
    try:
        with open(PIDFILE) as f:
            return int(f.read().strip())
    except Exception:
        return None


def pid_alive(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def count_markers() -> int:
    try:
        return len(os.listdir(SHIM_DIR))
    except Exception:
        return -1


def sigpipe_disposition() -> str:
    """Use sigaction() directly — /proc/PID/status.SigIgn can lie
    when a Python signal-handler-wrapper is in play."""
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)

        class sa_t(ctypes.Structure):
            _fields_ = [
                ("sa_handler", ctypes.c_void_p),
                ("sa_mask", ctypes.c_ulong * 16),
                ("sa_flags", ctypes.c_int),
                ("sa_restorer", ctypes.c_void_p),
            ]

        old = sa_t()
        libc.sigaction(13, None, ctypes.byref(old))
        SIG_DFL, SIG_IGN = 0, 1
        if old.sa_handler == SIG_DFL:
            return "SIG_DFL"
        if old.sa_handler == SIG_IGN:
            return "SIG_IGN"
        return f"handler:{hex(old.sa_handler)}"
    except Exception:
        return "?"


def get_mem(pid: int) -> str | None:
    """VmRSS / VmPeak / VmSize / State of the given PID.
    Returns a single-line summary, or None on read failure."""
    try:
        out = []
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith(("VmRSS:", "VmPeak:", "VmSize:", "State:")):
                    out.append(line.strip())
        if not out:
            return None
        return "  ".join(out)
    except Exception:
        return None


# === Main loop ===
LOG_PATH = f"{SHIM_DIR}/event-watch.log"

try:
    open(LOG_PATH, "w").close()  # truncate on start
except Exception as e:
    print(f"[event-watcher] cannot open {LOG_PATH}: {e}", file=sys.stderr)
    sys.exit(1)

log(f"=== event watcher started (PID {os.getpid()}) ===")
log(f"HEALTH_URL={HEALTH_URL}  PIDFILE={PIDFILE}  SHIM_DIR={SHIM_DIR}")

baseline_pid = get_pid()
log(
    f"baseline: pidfile={baseline_pid} "
    f"pid_alive={pid_alive(baseline_pid)} "
    f"markers={count_markers()} "
    f"sigpipe={sigpipe_disposition()}"
)

prev_health = check_health()
prev_pid = baseline_pid
prev_markers = count_markers()
prev_sigpipe = sigpipe_disposition()
prev_mem = get_mem(baseline_pid) if baseline_pid else None
log(
    f"initial:  health={prev_health}  pid={prev_pid}  "
    f"markers={prev_markers}  sigpipe={prev_sigpipe}"
)
if prev_mem:
    log(f"memory:   {prev_mem}")
log("--- watching (Ctrl-C to stop) ---")

try:
    while True:
        time.sleep(POLL_INTERVAL_S)
        h = check_health()
        p = get_pid()
        m = count_markers()
        s = sigpipe_disposition()
        mem = get_mem(p) if p else None

        if h != prev_health:
            log(f"HEALTH CHANGED:   {prev_health} -> {h}")
            prev_health = h
        if p != prev_pid:
            log(f"PIDFILE CHANGED:  {prev_pid} -> {p}")
            prev_pid = p
        if m != prev_markers:
            log(f"MARKER COUNT:     {prev_markers} -> {m}")
            try:
                markers = sorted(os.listdir(SHIM_DIR))
                for mk in markers[-3:]:
                    if mk.endswith(".json"):
                        try:
                            with open(f"{SHIM_DIR}/{mk}") as f:
                                d = json.load(f)
                            log(
                                f"   marker: {mk}  "
                                f"kind={d.get('kind')}  "
                                f"pid={d.get('pid')}  "
                                f"signal={d.get('signal_name', d.get('reason', '?'))}"
                            )
                        except Exception:
                            pass
            except Exception:
                pass
            prev_markers = m
        if s != prev_sigpipe:
            log(f"SIGPIPE DISP:     {prev_sigpipe} -> {s}")
            prev_sigpipe = s
        if mem != prev_mem and mem is not None:
            log(f"MEM (pid {p}):  {mem}")
            prev_mem = mem
except KeyboardInterrupt:
    log("=== watcher stopped (KeyboardInterrupt) ===")
except Exception as e:
    log(f"=== watcher stopped (error: {e!r}) ===")
