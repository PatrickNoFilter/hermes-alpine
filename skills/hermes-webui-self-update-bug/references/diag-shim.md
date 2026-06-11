# Diag shim — observability for unexplained webui deaths

The `api/diag_shim.py` module in `/root/hermes-webui` is a **pure
observability layer** that answers one question: *why did the server
die?* It does not change server behavior — every handler either
writes a marker and re-raises the default disposition (for signals)
or logs an exception marker and re-raises (for serve_forever
exceptions). All install/wrap calls are inside `try/except Exception`
so a shim bug can never break the server.

## How it's wired

Two-line edit in `api/server.py` `main()`, just before `_serve()`:

```python
try:
    from api.diag_shim import install as _install_diag, wrap_serve_forever as _wrap_serve
    _install_diag()
    _serve = _wrap_serve(httpd.serve_forever, label="httpd.serve_forever")
except Exception as _diag_err:
    sys.stderr.write(f"[diag_shim] install failed: {_diag_err}\n")
    _serve = httpd.serve_forever
```

`install()` registers 12 signal handlers (everything except
`SIGKILL` / `SIGSTOP` / `SIGTSTP` which are untrappable at the
kernel level). `wrap_serve_forever()` wraps the call with a
try/except that writes an exception marker and re-raises. An
`atexit` hook also writes a marker on normal interpreter shutdown.

## Marker file format

All markers live in `/tmp/hermes-webui-shim/`. Filename pattern:

```
<epoch_ms>-<sequence>-<kind>.json
```

Example: `1780407266089-001-install.json`

Three `kind` values:

### `install` — written on shim load

Proves the shim was active in the dying process. The presence of
`install` with **no subsequent** `signal` / `exception` / `atexit`
marker is the **canonical evidence of an untrappable death** (SIGKILL
/ OOM / Android activity manager).

Fields: `ts`, `pid`, `ppid`, `uptime_seconds`, `argv`, `executable`,
`frozen: false|true`, `fd_count`, `signals` (list of registered
signal names).

### `signal` — written from a signal handler

Proves the process received a specific signal. The `signal_name` and
`signal_number` are the smoking gun. The `stack` shows where the
process was parked (usually `serve_forever → selector.select`).
`threads` lists every live thread with its own stack.

Fields: `kind: signal`, `signal_number`, `signal_name`, `stack` (up
to 2 KB), `threads: [{name, ident, daemon, is_alive, stack}, ...]`,
plus all `install` fields.

### `exception` — written from `wrap_serve_forever`

Proves `serve_forever` raised. `exception_type` + `exception_message`
+ full traceback. Wrapped for `Exception`, `KeyboardInterrupt`, and
`SystemExit` separately — the latter two are re-raised cleanly so
the shim never changes shutdown behavior.

Fields: `kind: exception`, `exception_type`, `exception_message`,
`label` (e.g. `httpd.serve_forever`), `stack` (full traceback), plus
all `install` fields.

### `atexit` — written from interpreter shutdown

Proves a normal exit (someone called `sys.exit`, an unhandled
exception unwound through main, or `httpd.shutdown()`). Has all
`install` fields.

## Diagnostic decision tree

After the next webui death, run **in order**:

```bash
SHIM=/tmp/hermes-webui-shim
LATEST_INSTALL=$(ls -t $SHIM/*-install.json | head -1)

# 1. Was the shim active? (Almost always yes if the install marker exists.)
test -n "$LATEST_INSTALL" && echo "SHIM WAS ACTIVE"

# 2. What kind of death?
ls -t $SHIM/ | head -3
#   -install.json   → shim was loaded
#   -signal.json    → caught a signal (open it, check signal_name)
#   -exception.json → serve_forever raised (open it, read traceback)
#   -atexit.json    → normal exit (rare for a "silent" death)
#   (nothing after install) → untrappable death (SIGKILL / OOM)
```

If you see only `install.json` from the dying process with no
`signal`/`exception`/`atexit` from the same `<epoch_ms>` prefix →
**the death was untrappable**. On Termux+PRoot this is the most
common case, and the most likely culprits are:

1. Android's activity manager SIGKILLing the Termux process when
   the user backgrounds the app to use another app
2. The container itself being suspended / OOM-killed by the host
3. A manual `kill -9` from a parent process (e.g. a watchdog or
   debugging session)

The shim can't capture data on a SIGKILL because the kernel doesn't
run any user-space code on SIGKILL — but the **absence** of a marker
is itself the diagnostic.

## Test procedure (canonical validation)

The shim was validated with three manual tests. Re-run them after
any change to `api/diag_shim.py` or the wiring in `server.py`:

```bash
# Clear baseline
rm -rf /tmp/hermes-webui-shim
cd /root/hermes-webui && bash ctl.sh start
sleep 3
PID=$(cat /root/.hermes/webui.pid)         # READ THE PID FILE — see pitfall
ls /tmp/hermes-webui-shim/                 # expect: <ms>-001-install.json

# Test 1: SIGTERM (catchable signal)
kill -TERM $PID
sleep 2
ls /tmp/hermes-webui-shim/                 # expect: signal.json with signal_name=SIGTERM

# Test 2: Exception in serve_forever
python3 -c "
import sys; sys.path.insert(0, '/root/hermes-webui')
from api.diag_shim import wrap_serve_forever
wrap_serve_forever(lambda: (_ for _ in ()).throw(RuntimeError('test')))()
"
# expect: exception.json with exception_type=RuntimeError

# Test 3: SIGKILL (untrappable — proves absence is meaningful)
cd /root/hermes-webui && bash ctl.sh start
sleep 3
PID=$(cat /root/.hermes/webui.pid)
kill -9 $PID
sleep 2
ls /tmp/hermes-webui-shim/                 # expect: install.json, NO signal/exception
```

## Safe-PID-lookup pitfall (CRITICAL)

**Never use `pgrep -f "server.py"`** to find the webui PID. The `-f`
flag matches against the full command line, so it matches the
*calling shell* whose command string contains `"server.py"` as a
literal argument. If you then `kill -9` the matched PID, you SIGKILL
your own terminal session and the process you're trying to test.

Safe alternatives, in preference order:

```bash
# Best: read the PID file that ctl.sh writes
PID=$(cat /root/.hermes/webui.pid)

# Good: lsof on the listening port
PID=$(lsof -tiTCP:8787 -sTCP:LISTEN)

# OK: pgrep with an exact name match (no -f)
PID=$(pgrep -x python)         # or: pidof python

# AVOID: pgrep -f "server.py" — matches the calling shell too
```

This pitfall is in the same family as the existing
`pkill -9 -f server.py` warning in the main `hermes-webui` skill —
both stem from broad `-f` patterns matching your own command line
under PRoot where process boundaries blur.

## Production catch — SIGPIPE in the wild (2026-06-02)

The shim's first real-world success. 161 seconds after start (PID
6706, on the production install), the server died. The
`/tmp/hermes-webui-shim/` dir contained:

```
1780407266089-001-install.json   548B    ← shim loaded into PID 6706
1780407427360-002-signal.json    13.8K   ← THE DEATH
```

The signal marker (`13.8K` — about 4× the size of the manual
SIGTERM test marker at `3.1K`, because there were 5 active
`process_request_thread`s plus gateway-watcher in the snapshot):

```json
{
  "kind": "signal",
  "ts": "2026-06-02T13:37:07.361011+00:00",
  "pid": 6706,
  "ppid": 1,
  "uptime_seconds": 161.272,
  "signal_number": 13,
  "signal_name": "SIGPIPE",
  "fd_count": 17,
  "stack": "serve_forever → selector.select (MainThread, idle in epoll)",
  "threads": [
    "MainThread (in serve_forever → selector.select)",
    "gateway-watcher (in time.sleep, normal idle)",
    "Thread-2/3/5/6/7 process_request_thread"
  ]
}
```

**What the log showed in the 7 seconds before the death:**

```
13:36:58Z  GET /api/models        ms: 12930.2
13:36:58Z  GET /api/session ...   ms: 10636.3
13:37:00Z  GET /api/updates/check ms: 20524.4   ← 20.5s slow request
13:37:07Z  SIGPIPE
```

`/api/updates/check` was 20.5s in (presumably blocked on a git
remote call), the browser gave up, the connection closed, the
server tried to write the response, the kernel sent SIGPIPE,
Python's default `SIG_DFL→terminate` killed the process. The
`/health` endpoint went unreachable. The watchdog (which was
silently down because crond had also died in PRoot) didn't
restart it.

**Lesson embedded into the skill:** SIGPIPE is the dominant silent
death cause for Python HTTP servers, NOT OOM/Android/Activity
Manager. The fix is `signal.signal(signal.SIGPIPE, signal.SIG_IGN)`
at the top of `server.py` — one line, no behavior change for
well-behaved clients, and it converts "client closed mid-response"
from a process killer into a recoverable `BrokenPipeError` that
the request handler can swallow. See the main SKILL.md Section B.1
for the patch and verification steps.

**Lesson about cron in PRoot:** This same death would have been
self-healing within 5 minutes IF the crond watchdog was alive. It
wasn't — `pgrep -x cron` returned empty. The skill `hermes-webui`
already documents this and includes the `*/15 * * * *` defensive
crontab line that re-arms crond. Apply it on any PRoot install.

## Where it lives and how to ship changes

- **Local checkout**: `/root/hermes-webui/api/diag_shim.py` (~271
  lines after the SIGPIPE special-case in commit `191cf6b3`)
- **Branch**: `diag/observability-and-robustness` on the
  `PatrickNoFilter/hermes-webui` fork
- **PR**: #3407 against `nesquena/hermes-webui`
- **Commits in this branch** (3 total — the canonical sequence):
  - `301de49c` — diag shim itself (the module + install/signal/atexit
    handlers + wrap_serve_forever)
  - `11e81fc9` — `server.py` top-of-module
    `signal.signal(signal.SIGPIPE, signal.SIG_IGN)` (the one-line
    protection the shim preserves; see "SIGPIPE special-case" below)
  - `191cf6b3` — the shim's SIGPIPE special-case (the third commit
    that fixed the bug where the shim's re-raise path undid the
    server.py protection)

To add a new signal handler, edit the `signals` list at the top of
`install()` and add an entry to the `signals` field in the install
marker so the test still validates it. To capture a new failure
mode, add a new `kind` constant and a new write call — the marker
filename is auto-derived from the kind string.

## The SIGPIPE special-case — required, not optional

The shim's `_signal_handler` is generic for all catchable signals:
write the marker → restore `SIG_DFL` → re-raise via `os.kill`. That
path is correct for SIGTERM/SIGINT/SIGQUIT (we want the process to
die after we know why), but **wrong for SIGPIPE**. If the shim
re-raises SIGPIPE, it undoes the `SIG_IGN` set by `server.py` at
module import time and the process dies anyway. The two fixes have
to be designed together, not added independently.

The current shim special-cases SIGPIPE in `_signal_handler`:

```python
if signum == signal.SIGPIPE:
    try:
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    except Exception:
        pass
    return
# ...all other signals: re-raise with default disposition as before
```

Without this special case, deploying the shim alongside the SIGPIPE
fix is actively worse than deploying either alone — the shim
overrides `SIG_IGN` (signal handlers are last-writer-wins in
`signal.signal`) and the re-raise path kills the process. This was
the exact regression that committed `191cf6b3` to fix.

**Generalized pattern to remember**: any time a signal handler is
added to a process that already has `SIG_IGN` on some signal, the
handler will replace `SIG_IGN` (last-writer-wins). If the handler
re-raises the signal, it undoes the protection. The fix is to make
the handler re-establish the intended disposition (`SIG_IGN` or
whatever the rest of the code chose) and `return` without
re-raising — for that specific signal only. Audit any signal
handler library for this pattern before relying on `SIG_IGN` in
the same process.

## Why not just `try/except BaseException` in main()?

The shim answers more than just "did serve_forever raise." It also
answers:

- Was the process killed by a signal? (Which one, while doing what?)
- Did the process die normally? (atexit)
- Was the shim itself even loaded? (install)
- What was every thread doing at the moment of death?

A `try/except BaseException` in `main()` catches category-2 from
the silent-death analysis (async task crash in serve_forever) but
captures **none** of: signals, OOM kills, container suspensions, or
manual `kill -9`. The shim is the union of all four. The shim's
`try/except` re-raises everything, so the only behavior change is
adding 1-2 file writes on the death path — nothing about the live
server changes.
