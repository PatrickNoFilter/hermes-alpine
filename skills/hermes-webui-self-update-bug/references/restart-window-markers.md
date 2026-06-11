# Restart-window markers — the 3-state decision table for SIGKILL localization

The shim in `api/diag_shim.py` catches *catchable* signals and
*Python exceptions* in the dying process. It cannot catch SIGKILL
or OOM-kill by design (those don't run user-space code), so the
"absence of a marker" was previously the only evidence — and that
told us the kill was untrappable but not *where* in the new
process's life it happened.

**The new markers close that gap.** Two new file writes bracket
the kill window so we can localize it to one of three states.

## The three markers (chronological)

| # | Marker | Written by | When | Naming |
|---|---|---|---|---|
| 0 | `pre-execv` | `api/updates.py._write_pre_execv_marker()` | OLD process, first line inside `with _apply_lock:` in `_schedule_restart()` (after `time.sleep(delay)`, before `_wait_until_restart_safe()`), with per-file `os.fsync()` | `<pid>-000-pre-execv.json` (PID-based) |
| 1 | `first-line` | `server.py._write_first_line_marker()` (top of file, before any other import) | NEW process, very first executable statement, with per-file `os.fsync()` | `<pid>-001-first-line.json` (PID-based) |
| 2 | `install` | `api/diag_shim.install()` | NEW process, inside `main()` after the heavy imports complete | `<ms_timestamp>-<counter:03d>-install.json` (timestamp-based) |

**Critical naming-convention note:** the new pre-execv and
first-line markers are **PID-based** (`<pid>-<seq>-<kind>.json`).
The existing `install`, `signal`, `exception`, `atexit` markers
from diag_shim are **timestamp-based** (`<ms_timestamp>-<counter>-<kind>.json`).
The diagnostic script (below) has to handle both conventions. Easy
to miss and the cause of "where's the install marker?" confusion
on first run.

## The 3-state decision table

After the next post-update restart that goes silent, check the
shim dir and apply this table:

| pre-execv | first-line | install | Diagnosis |
|---|---|---|---|
| ✓ | — | — | **Kill in execve() / dynamic loader.** Extremely rare — would mean a broken interpreter, bad LD_LIBRARY_PATH, or a kernel rejection. `dmesg` (inaccessible from PRoot) would have details. `strace` on the parent pre-execv would have details. |
| ✓ | ✓ | — | **Kill in Python startup.** Something between line 7 of server.py and `install()` is killing the process. Most likely: a bad import (C-extension crash, missing shared lib, syntax error after a botched update). `exception.json` would have been written if the import raised — its absence means the import didn't even get a chance to raise (e.g. `dlopen` failed). |
| ✓ | ✓ | ✓ (no further markers) | **Kill is post-shim-load.** This is the original mystery confirmed. The new process loaded all imports, installed its signal/atexit handlers, and *then* died untrappably. From here: deploy the 10ms `/proc` watcher to catch `State=` / `SigPnd` on the dying process, or check the cgroup/memory limits in `silent-sigkill-diagnosis.md` Step 1. |

The 3-state table is the answer to "where in the new process's
life did the silent death happen?" — once you know that, the
fixable suspects narrow to a handful.

## Why this is the right design (and what it was chosen over)

Two other approaches were considered and rejected:

- **10ms /proc polling during the restart window** — passive
  observer; would catch `State=D` (uninterruptible sleep on IO)
  or `SigPnd` bit 9 (SIGKILL pending). Useful for Phase B but
  not needed for Phase A because the marker-based approach
  localizes the kill to a window, and 10ms polling during a
  window that may be sub-millisecond is racy.
- **Pre/post strace-through-execv** — already exists, gated by
  `HERMES_WEBUI_STRACE_EXECV=1`. Useful for syscall-level detail
  within a window, but the strace log is empty for kills faster
  than strace's first write. The marker approach is strictly
  stronger for narrowing the window; strace is the second-level
  tool once you know which window to look at.

The pre-marker is the critical new piece: without it, "did the old
process commit to restarting?" is ambiguous (it could have died
during the `time.sleep(delay)` or the git pull). With it, the
absence of pre-marker = the kill is in the OLD process, which is a
different bug.

## End-to-end verification (run this on a normal ctl.sh restart)

```bash
# 1. Snapshot the shim dir state before
SHIM=/tmp/hermes-webui-shim
ls -lt $SHIM/*.json | head -5

# 2. Restart
bash /root/hermes-webui/ctl.sh restart
# expect:
#   [ctl] Stopping Hermes WebUI (PID <old>)
#   [ctl] Stopped
#   [ctl] Started Hermes WebUI (PID <new>)
#   [ctl] Bound: 127.0.0.1:8787
#   [ctl] Log: /root/.hermes/webui.log

# 3. Wait for the imports to complete (typically 7-10s on Termux+PRoot)
sleep 12

# 4. Verify the new PID is up
NEW_PID=$(cat /root/.hermes/webui.pid)
curl -fsS http://127.0.0.1:8787/health
# expect: {"status":"ok", ...}

# 5. Verify all three markers for the new PID landed
ls -la $SHIM/${NEW_PID}-001-first-line.json
# expect: -rw-r--r-- 1 root root 307 <date> .../2947-001-first-line.json
ls -lt $SHIM/*-001-install.json | head -1
# expect: most recent <ms_timestamp>-001-install.json with "pid": <NEW_PID>

# 6. cat the markers and verify pid matches $NEW_PID
cat $SHIM/${NEW_PID}-001-first-line.json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['pid']==${NEW_PID} and d['kind']=='first-line'; print('first-line OK')"
LATEST_INSTALL=$(ls -t $SHIM/*-001-install.json | head -1)
cat $LATEST_INSTALL | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['pid']==${NEW_PID} and d['kind']=='install'; print('install OK')"
```

If all three checks pass, the diagnostic chain is live and the
next post-update silent death will be localizable.

## The /health-during-imports pitfall

The ctl.sh script's bootstrap banner prints:

```
[bootstrap] Starting Hermes Web UI on http://127.0.0.1:8787 (foreground mode: --foreground)
...
Hermes Web UI listening on http://127.0.0.1:8787
```

**before** the `exec python server.py`. So the port is *not
actually bound* during the first ~8s of any restart (the time it
takes Python to import everything). During that window:

- `/health` will return connection-refused (curl error 7)
- The new PID is alive (`ps -p $NEW_PID` shows it, status `S<l`)
- The first-line marker exists, the install marker does not yet
- A watchdog that probes /health during this window will see
  "down" and try to start a *second* process

This is **not a problem in the current setup** because ctl.sh
checks for an existing PID before starting. But if the watchdog
ever changes to /health-only probing, this 8s window will
cause spurious double-starts.

**Workaround if you ever need sub-second readiness signaling**:
`kill -0 $NEW_PID && [ -f $SHIM/${NEW_PID}-002-install.json ]` —
PID is alive AND the install marker has landed means the new
process is past the import window and ready to serve.

## Marker write discipline (reference for any new marker)

Every marker write in this codebase must:

1. Be wrapped in `try/except` — a marker write failure must never
   prevent the restart or the startup.
2. Use `os.fsync(f.fileno())` (per-file), **not** `os.sync()`
   (full-system). `os.sync()` can block for seconds on a slow
   filesystem and would itself appear as a hang.
3. Use only stdlib for any marker at the top of server.py, so a
   broken `api.*` import can never be the reason the marker fails
   to write.
4. Carry enough fields for a future agent to disambiguate which
   process wrote it: `kind`, `ts` (ISO8601 UTC), `pid`, `ppid`,
   `argv`, `executable`, `frozen`.

## Files

- `api/updates.py` — `_SHIM_DIR` constant (line ~56), `_write_pre_execv_marker()` function (~80 lines), call site in `_schedule_restart()` (line ~1116, first line inside `with _apply_lock:`), env-gated strace-through-execv (existing, in the same `with` block)
- `server.py` — first-line marker block at the very top (after the docstring, before any import). Function `_write_first_line_marker()` and the call `_write_first_line_marker()` immediately after the docstring.
- `/root/hermes-webui/.env` — `HERMES_WEBUI_STRACE_EXECV=1` and `HERMES_WEBUI_STRACE_LOG=/tmp/hermes-webui-shim/strace-execv.log` (leave on during diagnosis, remove when done)
- `/tmp/hermes-webui-shim/` — all markers land here
