---
name: hermes-webui-self-update-bug
description: "hermes-webui silent death — THREE distinct bugs. (A) execv argv shape in api/updates.py — frozen-vs-source divergence; PR #3395 fix. (B) SIGPIPE on http.server mid-response close — signal.signal(SIGPIPE, SIG_IGN); PR #3407 fix. (C) cpuset:/top-app lmkd kills new python3 in same cgroup within ~10s of old exit (broader than execv) — fork+setsid+sleep(15)+execvp(ctl.sh) in api/updates.py; PR #3407 fix. Includes 3-state marker decision table, signal-name tree, multi-threaded-fork pitfall, opt-in shim question, 15s timing magic-number concerns."
---

# hermes-webui self-update → "offline" bugs

Two distinct failure modes can present as "WebUI stuck offline after
Update Now." They look similar from the browser but are different
bugs at different layers. Diagnose which one before fixing.

## A. The `os.execv` argv bug — only on frozen/packaged builds

### Symptom (frozen-binary deploys only)
The new process starts but never reaches `bind()`. `/health` stays
unreachable indefinitely. PID file shows a process alive but the
listening port is dead.

### Root cause
`api/updates.py` `_schedule_restart()` (around line 1052) does:

```python
os.execv(sys.executable, [sys.executable] + sys.argv)
```

`os.execv(path, argv)` runs `path` and uses `argv[1]` as the script
to run. In a **frozen/packaged build** (PyInstaller, zipapp, etc.),
`sys.argv[0] == sys.executable == <binary>`, so
`[sys.executable] + sys.argv` becomes `[binary, binary, ...]` — the
interpreter treats the binary itself as the "script," recursively
re-execs from the new image, and never reaches `bind()`.

In a **source checkout** (`python server.py` via `bootstrap.py` /
`ctl.sh` / `start.sh`), `sys.argv[0]` is the SCRIPT path and
`sys.executable` is the interpreter — `[sys.executable] + sys.argv` is
the canonical CPython re-exec idiom and is **correct**. Dropping the
prefix here is the bug, not the fix.

A flat one-line swap (`sys.argv` for everything) is wrong for
source-checkout deploys: the new process won't reach `bind()` either,
because the interpreter treats `"<abs>/server.py"` as the program
name and finds no script argument, falling back to stdin, hitting
EOF on the daemon, and exiting.

### Correct fix (handle both deployments)

```python
if getattr(sys, "frozen", False):
    # Frozen/packaged: argv[0] is the binary, pass argv as-is.
    os.execv(sys.executable, sys.argv)
else:
    # Source checkout launched as `python server.py`: argv[0] is the
    # script, must include sys.executable as argv[0] for the interpreter.
    os.execv(sys.executable, [sys.executable] + sys.argv)
```

Keep the existing `try/except os._exit(0)` last-resort branch intact.

### PR / issue pointers
- **PR #3395** open on `nesquena/hermes-webui` from
  `PatrickNoFilter:fix/updates-self-restart-execv`:
  https://github.com/nesquena/hermes-webui/pull/3395
  - **Scope**: 1 commit (`da7eaf34`), 1 file (`api/updates.py`,
    +30/-3), the `sys.frozen` execv guard only.
  - Maintainer ([nesquena](https://github.com/nesquena)) reviewed
    and approved with **LGTM** at 2026-06-02 14:13 UTC. Their
    comment thread traced the actual `bootstrap.py:449` launch
    path and confirmed the source-checkout path
    (`[sys.executable] + sys.argv`) is correct, while the frozen
    case only diverges for PyInstaller/zipapp builds. One PR, one
    logical change.
  - Body rewritten to match the actual code (was stale, described
    the wrong "flat swap" fix). Maintainer said "Good catch
    reverting the flat one-liner" and called the comment block
    "genuinely useful — keep it."
- **PR #3407** open on `nesquena/hermes-webui` from
  `PatrickNoFilter:diag/observability-and-robustness`:
  https://github.com/nesquena/hermes-webui/pull/3407
  - **Current scope (as of 2026-06-02 17:06 UTC)**: 11 commits,
    6 files (+585/-20). Started as a 3-commit SIGPIPE trio,
    expanded with 8 commits for a **separate** silent-death
    pattern (the Termux+PRoot cgroup-kill window — see
    Section C). Group breakdown:
      - **Group 1 (3 commits, original)**: SIGPIPE — one-line
        `server.py` fix + diag shim + shim-doesn't-undo-fix.
        Affects every HTTP-server deployment, not just
        Termux+PRoot. **Merge-ready.**
      - **Group 2 (6 commits, added)**: pre-execv + first-line
        + install markers, strace-through-execv (opt-in via
        `HERMES_WEBUI_STRACE_EXECV=1`), and the
        `os.fork()+setsid()+sleep(15)+execvp(ctl.sh)` cgroup-
        kill-window fix. Termux+PRoot-specific. **Needs the
        review concerns in Section D below addressed before
        merge.**
      - **Group 3 (2 commits)**: CHANGELOG entries.
  - The contributor has explicitly offered to **split the PR**:
    Group 1 as PR-A (3 commits, ship-now) and Group 2+3 as
    PR-B (8 commits). Recommend accepting — matches the
    "one PR, one logical change" precedent set by #3395's LGTM.
  - The diag shim (`api/diag_shim.py`, +270 lines) caught the
    production SIGPIPE death that motivated the whole
    investigation, then caught the shim-undoing-fix regression
    (PID 12029, 14:03 UTC) that motivated the third commit.
- A 10-min cron watchdog (`pr-monitor-3395.sh` +
  `pr-monitor-3407.sh`) pings on PR state change; silent on
  no-change.

### Local patch
- The local checkout in this box runs the proper `if sys.frozen`
  guard (master for `frozen=False` takes the canonical source path).
- After editing `api/*.py`, **MUST** clear the bytecode cache or the
  running interpreter will keep loading stale bytecode:
  ```bash
  rm -f /root/hermes-webui/api/__pycache__/updates.cpython-*.pyc
  bash /root/hermes-webui/ctl.sh restart
  ```

### Verification smoke test
`scripts/verify_execv_argv.py` exercises both the broken
(`[sys.executable] + sys.argv`) and fixed (`sys.argv`) shapes and
confirms which one recurses vs which one runs the script once and
exits. Run it on the deployment's Python before/after a code change
to confirm the local interpreter behaves the way the fix assumes.

## B. Silent death after restart — separate bug, different layer

### Symptom (source-checkout deploys, intermittent)
The new process DOES start and DOES serve a few requests (the
existing browser tab polls `/health`, `/api/settings`, static
assets, all 200). Then within ~30-90 seconds, the process is gone.
No traceback, no shutdown log, no signal handler output, no
`Address already in use`, no OOM in dmesg. `VmRSS` was tiny
(17 MB on a 7.5 GB box with 2.8 GB available). `PPid=1` (reparented
to init). `Threads=2`.

The user sees: update succeeds → ~1s of normal responses → browser
flips to **"Hermes is unreachable"** → stays there.

### What it is NOT
- Not the `os.execv` bug (the new process actually served requests
  and bound the port fine).
- Not OOM (memory was fine, no OOM kill in dmesg).
- Not EADDRINUSE (would have been a hard crash at startup with a
  traceback; we see it in the log occasionally from earlier manual
  restarts, not from the in-app path).
- Not a watchdog issue (cron-based watchdog is working — caught and
  restarted within 5 min on first occurrence).

### What it actually is — confirmed SIGPIPE (not untrappable)

The first production catch with the diag shim present (2026-06-02,
13:37 UTC) revealed the actual cause is **SIGPIPE** (signal 13), NOT
an untrappable kill. The marker on disk:

```
1780407427360-002-signal.json
{
  "kind": "signal",
  "signal_number": 13,
  "signal_name": "SIGPIPE",
  "stack": "...serve_forever → selector.select...",
  "threads": [
    "MainThread (in serve_forever)",
    "gateway-watcher (in time.sleep)",
    "Thread-2/3/5/6/7 process_request_thread"  ← 5 active requests
  ]
}
```

**Root cause**: Python's `http.server` family defaults `SIGPIPE` to
**terminate**. The `signal` module's default disposition is `SIG_DFL`,
which for SIGPIPE means "kill the process." When any client closes
the connection mid-response (browser tab close, mobile background,
network drop, slow request killed), the kernel sends SIGPIPE to the
writing thread. The default disposition fires before Python can
convert it to a `BrokenPipeError`, and the entire process is gone.

**Log fingerprint before the death** (from the same case):

```
13:36:58Z  GET /api/models        ms: 12930.2
13:36:58Z  GET /api/session ...   ms: 10636.3
13:37:00Z  GET /api/updates/check ms: 20524.4   ← 20.5s slow request
13:37:07Z  SIGPIPE
```

A long-running request (`/api/updates/check` in this case, hitting
git during the update check) is the trigger. The client gives up,
the server tries to write to a closed socket, the kernel sends
SIGPIPE, the process dies.

### The one-line fix

Add at the top of `server.py`, before any HTTP serving code:

```python
import signal
# Default SIGPIPE disposition is SIG_DFL→terminate. For an HTTP
# server we want BrokenPipeError from socket.send() instead of
# process death, so a client closing the connection mid-response
# just causes that request to fail.
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
```

This is the standard Python HTTP server pattern (gunicorn, waitress,
Flask dev server all do this internally). It does NOT change
behavior for well-behaved clients; it only converts
"client-disconnected-mid-response" from a process killer into a
recoverable exception that the request handler can swallow.

### Why the speculation about Android/Activity Manager was wrong

The 3 originally-listed culprits (Activity Manager SIGKILL, async
task crash, container pause) would have produced an **untrappable**
death — i.e. NO `signal` marker, just `install` with nothing after
it. The fact that we caught `SIGPIPE` specifically rules all three
out for *this* case. They may still cause deaths occasionally
(SIGKILL can also reach the process via the kernel), but they're
**not** the dominant cause — SIGPIPE is.

### How to verify the fix is working

After adding the SIGPIPE ignore:

```bash
# 1. Restart
cd /root/hermes-webui && bash ctl.sh start
sleep 3
PID=$(cat /root/hermes-webui.pid)  # if missing, see safe-PID pattern in references/diag-shim.md

# 2. Open a long-running request in one terminal
curl -v --max-time 60 http://127.0.0.1:8787/api/updates/check

# 3. In another terminal, kill the curl mid-flight
kill -PIPE $(lsof -tiTCP:8787 -sTCP:ESTABLISHED) 2>/dev/null

# 4. Check the server is still up
curl -fsS --max-time 3 http://127.0.0.1:8787/health
# expect: 200 OK (server is still running, just dropped the broken request)
```

If the server dies despite the SIG_IGN, the cause is NOT SIGPIPE —
go back to the diag shim markers and check what else might be
killing it.

### How to diagnose next time

**A signal-trap shim is now installed in the local checkout**
(`api/diag_shim.py`, originally committed as `56eaff6e` on
`fix/updates-self-restart-execv`, now at commit `301de49c` on
`diag/observability-and-robustness` on the fork — see PR #3407).
It writes JSON markers to `/tmp/hermes-webui-shim/` on install, on
every catchable signal, on `serve_forever` exception, and on normal
atexit — and **the absence of any marker after an `install` marker
is itself the proof of an untrappable death** (SIGKILL / OOM /
container suspend).

After the next webui death:

```bash
SHIM=/tmp/hermes-webui-shim
ls -t $SHIM/ | tail -5
# -install.json   → shim was loaded (proves it was active in this process)
# -signal.json    → signal handler ran (cat it, check signal_name)
# -exception.json → serve_forever raised (cat it, read traceback)
# -atexit.json    → normal exit
# (nothing after install from the same <ms> prefix)
#                  → untrappable death (SIGKILL / OOM / container suspend).
#                    Less common than expected on Termux+PRoot — the
#                    dominant cause is actually SIGPIPE, see Section C
#                    below. Untrappable deaths are rare.
```

**Most likely signal_name in the marker: `SIGPIPE` (number 13).**
This is the default-termination behavior of Python's `http.server`
when a client closes the connection mid-response. Apply the
one-line fix in Section C and the server stops dying on this
pattern. Other plausible signals are `SIGTERM` (manual
restart/shutdown) and `SIGINT` (Ctrl-C), which are NOT deaths and
don't need investigating.

Full reference: `references/diag-shim.md` (marker file format,
test procedure, safe-PID-lookup pattern, design rationale, why this
beats a plain `try/except BaseException` in `main()`).

### How to recover
The cron watchdog at `*/5 * * * *` (set up in `hermes-webui` skill's
"Minimal working crontab") will restart within 5 minutes. If you
need faster recovery, bump the cron to `*/2 * * * *` — the watchdog
calls `bash ctl.sh restart` which is idempotent and safe to run.

If you need the webui up RIGHT NOW:

```bash
bash /root/hermes-webui/ctl.sh stop   # kill any stale PID
sleep 2
cd /root/hermes-webui && bash ctl.sh start
sleep 20                               # 8-10s PRoot bind + buffer
curl -fsS --max-time 3 http://127.0.0.1:8787/health
```

### C. Silent SIGKILL during post-update — RESOLVED (cgroup kill window, fix in api/updates.py)

**Resolution status (local checkout, 2026-06-04):** The fix has been
applied locally at `/root/hermes-webui/api/updates.py`. PR #3407's
Group 2 approach (`os.fork()` + `os.setsid()` + `os.execvp('ctl.sh', ['start'])`)
was rejected upstream for lacking a platform gate — this is a
**permanent local patch**. Re-application is now **fully automated**
via three layers:
- **Git post-merge hook** (`/root/hermes-webui/.git/hooks/post-merge`)
  fires after every `git pull`
- **`_reapply_local_fix()`** in `api/updates.py` is called from both
  `apply_update()` and `apply_force_update()` after the git operation
- **Shell script** (`/root/.hermes/scripts/reapply-webui-fix.sh`) as
  standalone fallback

No manual re-apply needed after updates. If the patch is overwritten,
any of the three layers catches it before the restart fires.

**Summary of the upstream rejection:** The maintainer wants the
fork+ctl.sh path gated behind `_is_termux()` or
`HERMES_WEBUI_RESTART_VIA_CTL=1` to avoid breaking Docker
deployments where `os._exit(0)` kills the container's PID-1.
Until that lands upstream, this is a local-only fix.

**Resolution (2026-06-02):** the silent death is the cgroup
reclassification in `cpuset:/top-app` and `/apps/uid_*/pid_*`
during the in-place `os.execv()` — but **broader than just execv**:
any new python3 process spawned in `cpuset:/top-app` within ~10
seconds of the old process's exit in the same cgroup is at risk.
The cron watchdog naturally waits ~5 min between ticks, well
outside the kill window, which is why watchdog-recovered
processes always survived. The fix is in `api/updates.py`
`_schedule_restart()`: replace the in-place `os.execv()` with
`os.fork()` + `os.setsid()` in the child + `time.sleep(15)` in
the child + `os.execvp("ctl.sh", ["start"])` + `os._exit(0)` in
the parent. Reduces post-update downtime from ~5 min (cron cycle)
to ~15-20 s.

**Diagnostic evolution (4 stages, all on branch
`diag/observability-and-robustness`):**

1. **in-place `os.execv()`** — pre-marker fires, no first-line
   or install from new PID (kernel/loader kill)
2. **`subprocess.Popen(start_new_session=True)` + `os._exit`**
   — child died with parent, watchdog recovered in 37s
3. **`os.fork()` + `os.setsid()` in child + `os.execvp(ctl.sh)`**
   — no delay, new process also killed in same cgroup window
   (~10s after old exit). Confirms the kill is cgroup-window-
   based, not execv-specific
4. **(3) + `time.sleep(15)` in fork child** — NEW PROCESS
   SURVIVES, total downtime ~20s. Verified 2 consecutive
   real-update tests on Termux+PRoot/aarch64

**Fingerprint (pre-fix, the original silent-SIGKILL):**
- `POST /api/updates/apply` returns 200 in ~15s
- ~4 minutes of no log entries from any webui process
- `cron` watchdog detects port down and restarts
- New PID comes up cleanly, no errors, normal operation resumes
- Shim install markers are there for BOTH the old and new
  PIDs, with nothing in between → **untrappable death (SIGKILL)**
- The shim's signal/exception/atexit markers can't help here —
  SIGKILL is untrappable by design. The "absence of marker" is
  itself the evidence.

**Confirmed root cause (2026-06-02):** cgroup reclassification
in `cpuset:/top-app` (Android's top-app cgroup, managed by
`lmkd` low-memory killer) fires within ~10s of the old
process's exit. Triggered by the new process joining the same
cgroup as the just-died parent. This rules strace-through-execv
out as a diagnostic — strace's first write happens after the
kill, log is 0 bytes.

**Why cgroup-kill-target isn't the diag shim's signal handlers:**
SIGKILL is untrappable by design. The diag shim at
`api/diag_shim.py` catches SIGTERM, SIGINT, SIGPIPE, SIGABRT,
SIGFPE, SIGSEGV (and on Python 3.13+ SIGUSR1, SIGUSR2, etc.)
via `signal.signal()` + try/except, but it CANNOT catch
SIGKILL — no Python handler runs, no atexit, no nothing. The
"absence of marker" after an `install` is the proof.

**The fix in api/updates.py (commit `12f322a5` on
`diag/observability-and-robustness`):**

```python
# In _schedule_restart(), inside the _apply_lock context:
_write_pre_execv_marker()       # always, for post-mortem
_wait_until_restart_safe()      # 2s delay so the apply response can return
try:
    ctl_path = os.path.join(REPO_ROOT, 'ctl.sh')
    _child_pid = os.fork()
    if _child_pid == 0:
        # Child branch
        try: os.setsid()
        except Exception: pass
        time.sleep(15)          # outlast the cgroup kill window
        try: os.execvp(ctl_path, [ctl_path, 'start'])
        except Exception: os._exit(1)
    # Parent branch
    time.sleep(0.3)             # let the child complete setsid()
    os._exit(0)                 # true exit, no atexit/signal handlers
except Exception:
    os._exit(0)                 # last-resort: cron watchdog recovers
```

**Why this works:**
- `os.fork()` is the most primitive POSIX spawn — no Python
  interpreter-level races with `_exit` (subprocess.Popen
  tested in stage 2, did NOT survive parent's `_exit`)
- `os.setsid()` in child detaches from parent's session so
  the child doesn't get SIGHUP when the parent dies
- `time.sleep(15)` in child is the key — empirically the
  cpuset:/top-app lmkd window kills any new python3 process
  spawned within ~10s of the old process's exit in the same
  cgroup. 15s puts the new process outside the window
- `os.execvp("ctl.sh", ["start"])` invokes the same code path
  the cron watchdog uses, which provably survives the cgroup
  transition (no in-place execv, brand-new process image
  loaded from scratch)
- `os._exit(0)` in parent: true process exit, no atexit, no
  Python cleanup, no signal handlers. The diag_shim signal/
  atexit markers will NOT fire (intentional — there's nothing
  to learn from a clean os._exit)

**Why 15s and not 5s or 30s:** Empirically, the kill window
is ~10s (the gap between old process exit and the cron
watchdog's next tick when the new process survives). 15s
gives a 50% safety margin. If the kill window is longer than
15s (kill is cgroup-membership-based rather than time-based),
the fallback is to simply not attempt a restart at all and
rely entirely on the cron watchdog — the pre-marker is still
informative as "old process committed to restart at this
exact moment" for any post-mortem analysis.

**Verified end-to-end (2026-06-02, 2 real tests):**
- Test 3: 15788 (OLD) pre-marker 16:44:44 → 16962 (NEW) alive
  16:45:58, uptime 1:47+
- Test 4: 16962 (OLD) pre-marker 16:48:52 → 21597 (NEW) alive
  16:49:26, alive 52s+
- Both new PIDs in SAME cgroup cpuset:/top-app as the dying
  ones → confirms 15s timing, not cgroup escape

**Tradeoff:** ~15-20s post-update downtime (vs the previous
~5min via cron watchdog alone), in exchange for a clean
restart that doesn't require operator intervention.

## D. Open review concerns for PR #3407 (June 2026)

After PR #3407 expanded from 3 → 11 commits, the following
self-review concerns were raised. Resolve before maintainer
merge of Group 2+3.

### D.1 `os.fork()` in a multi-threaded Python process

The `_schedule_restart` patch does `os.fork()` while the parent
has ≥3 live threads (MainThread in `serve_forever`,
gateway-watcher, plus N request threads). CPython: only the
calling thread survives in the child; any non-MainThread mutex
held at fork is permanently locked in the child. The 15s sleep
in the child runs *between* `os.setsid()` and `os.execvp()`
while the child is a forked single-threaded process — if any
internal CPython lock was held at fork time (buffered I/O from
a request thread's `socket.send()`), the child can deadlock
before `execvp` ever runs. The skill's Section C documents the
fix without ever noting this risk.

**Mitigations** (pick one):
1. Spawn a tiny single-threaded helper that does the
   `setsid + sleep + execvp`. Run it via
   `subprocess.Popen([sys.executable, helper_path, ...])` from
   the old process — the fork then happens in a *fresh*
   interpreter with no other threads. Accept the
   Popen-dies-with-parent failure mode and recover via cron.
2. Document explicitly in `api/updates.py` why the
   multi-threaded fork is acceptable for this specific code
   path (must argue the post-fork child has no I/O between
   `setsid` and `execvp`).

### D.2 The 15s sleep is a workaround, not a fix

Magic number with no instrumentation. If a future Android
version or device changes the ~10s cgroup-kill window, the
fix silently breaks. There's no `{pid}-post-sleep.json`
marker, so post-mortem can't tell if the sleep was sufficient
or the process "got lucky."

**Fix**: add a `{pid}-003-post-sleep.json` marker immediately
before `execvp` in the fork child. Also reword the PR body
"The fix" → "The workaround (15s timing on current
Termux+PRoot; root cause is lmkd cgroup behavior we don't
control)."

**Alternatives not considered** in the PR: (a) swap the new
PID to a different cgroup before exec via `/proc/self/cgroup`
manipulation, (b) `prctl(PR_SET_PDEATHSIG, 0)` + `setsid` +
drop cgroup via `cgexec` if available, (c) skip the in-app
restart entirely and rely on the cron watchdog's 5-min
recovery (provably survives, per Section C).

### D.3 The diag shim is always-on in production

`api/diag_shim.py` runs at every startup with no opt-out. No
log rotation; `/tmp` is unreliable (lost on reboot, tmpfs-
cleaned). **Recommend** opt-in via `HERMES_WEBUI_DIAG=1` env
var, default off, home in `~/.hermes/webui-shim/` instead of
`/tmp/`. Same observability, lower production cost, persistent
across reboots.

### D.4 Marker file naming uses magic numbers

`{pid}-000-pre-execv.json` and `{pid}-001-first-line.json`
implicitly encode ordering via the `000`/`001` prefix. Drop
the prefix — the PID is already in the path, and the order is
preserved by timestamp-based filenames (`<ms>-<counter>-*.json`)
already in the same dir. Adding a "second-line" marker in the
future would force a renumbering.

### D.5 User-side scripts in upstream repo

`start-webui.sh` (6 lines) and `watchdog-loop.sh` (27 lines)
hard-code `/root/hermes-webui` and `127.0.0.1:8787`. These
are user-specific deploy scripts, not part of the webui
server. Belongs in this skill (or local notes), not the
upstream repo.

### D.6 PR body is 8KB — too long for a reviewer

### D.7 Test-suite guard regression — no `os.fork()`/`os._exit()`/`os.execvp()` guards in conftest.py

**Severity**: test-suite corruption. Real fork + real exit during pytest.

The existing `tests/conftest.py` installs a permanent no-op on
`os.execv` to prevent daemon threads from `_schedule_restart()` from
re-execing pytest after monkeypatch teardown. The new code in PR #3407
uses `os.fork()` + `os.setsid()` + `time.sleep(15)` + `os.execvp()` +
`os._exit(0)` — none of which are guarded.

Full breakdown: `references/test-suite-guard-regression.md`

## E. Actual Maintainer Review — nesquena-hermes (2026-06-02)

The maintainer reviewed PR #3407 with a clear split verdict:

- **Group 1 (SIGPIPE)**: **APPROVED** — ship-worthy
- **Group 2 (cgroup restart)**: **BLOCKED** — no platform gate breaks
  Docker (PID 1 exits when `os._exit(0)` kills docker_init.bash)

The reviewer's specific fix: gate the fork+ctl.sh path behind
`_is_termux()` or `HERMES_WEBUI_RESTART_VIA_CTL=1`, keep the standard
`os.execv()` for all other deployments. Full breakdown with detector
code and Docker lifecycle details: `references/pr-3407-review-concerns.md`
(Section E).

## Files in this skill
- `scripts/verify_execv_argv.py` — runnable smoke test that exercises
  both execv shapes and proves which one recurses vs runs-and-exits.
  Use it as a one-liner sanity check on the deployment's Python
  before/after a code change.
- `scripts/event-watcher.py` — background state-change watcher for
  the "set up watcher, trigger event, post-mortem from log" pattern.
  Polls /health, PID, shim marker count, SIGPIPE disposition, and
  process memory. Logs every transition with millisecond timestamps.
  Start before any known event, review after.
- `references/diag-shim.md` — observability shim: marker format,
  diagnostic decision tree, canonical 3-test validation procedure
  (SIGTERM / exception / SIGKILL), safe-PID-lookup pattern, and
  why this is better than a `try/except BaseException` in main().
- `references/silent-sigkill-diagnosis.md` — Section C's diagnostic
  playbook: cgroup/limit check, memory sampling, strace-through-
  execv, coredump config, and the operational pattern for capturing
  intermittent events with the watcher.
- `references/restart-window-markers.md` — the **3-state decision
  table** for the silent-SIGKILL: pre-execv + first-line + install
  markers (deployed in PR #3407) narrow the kill to kernel-loader,
  Python-startup, or post-shim-load. Covers the PID-based vs
  timestamp-based marker-naming-convention gotcha, the end-to-end
  verification procedure, the /health-during-imports pitfall (ctl.sh
  prints "listening on" BEFORE exec python — first ~8s /health
  returns connection-refused), and the marker-write discipline
  (try/except + per-file `os.fsync()`, never `os.sync()`).
- `references/pr-3407-review-concerns.md` — the open review issues
  from Section D in standalone form, plus Section E (actual
  maintainer review by nesquena-hermes with Docker breakage
  analysis, platform gate fix, and `_is_termux()` detector code).
  Suitable for paste-into-PR-comment or a maintainer discussion.
- `references/test-suite-guard-regression.md` — test-suite guard
  regression when `_schedule_restart()` changed from `os.execv()`
  to `os.fork()`/`os._exit()`/`os.execvp()`: the conftest.py only
  guards `os.execv`, leaving fork/exit/execvp unguarded, causing
  silent test-suite corruption. Covers the fix, the failing test,
  and the search pattern for future reviews.

## State-verification discipline — don't conflate process, tree, and branch

When reporting what is "live" or "in place" for this codebase, these
three things are DIFFERENT and must be verified independently:

1. **The running process** — what code is it actually executing?
   `cat /root/.hermes/webui.pid` → `pgrep -af server.py` → check
   `/proc/PID/exe` (the on-disk file that was exec'd). Then read
   the install marker to see what `frozen`, `argv`, `executable`,
   and `signals` the process actually has loaded.
2. **The working tree** — `git rev-parse --abbrev-ref HEAD` +
   `git log -1 --format=%H %s`. This is what the next `ctl.sh
   start` will load, but it is NOT necessarily what the current
   process loaded (the process may have started when the tree was
   on a different branch).
3. **The branch tip** — `git rev-parse <branch>`. A commit may exist
  on a branch but be missing from the working tree if the tree is
  on a different branch.

**Real failure from this session**: a branch was created from
`master` and the SIGPIPE fix + shim were added to it, but the
*execv frozen guard* (a separate concern) was committed to a
DIFFERENT branch. The working tree was on the first branch, so a
"readiness check" was attempted that verified the SIGPIPE fix was
in `server.py` and the shim was in `api/diag_shim.py` and the
install marker listed SIGPIPE among the trapped signals — and
then concluded "✅ All 3 fixes live." But the execv guard was on
a different branch, so the running process did not have it. The
bug surfaced a few minutes later when a readiness-check report
said "all 3 live" but the codebase showed otherwise.

**Discipline for "is X live" reports:**

- For each fix being claimed, list the file(s) and the exact
  change. Then verify in three places: working tree has the file
  with the change, the file is in the list of files changed since
  the process started, and (for runtime behavior) the process is
  actually running the working tree's code (not a previously
  loaded copy).
- If a fix is on a different branch than the working tree, it is
  NOT live for the current process. It will be live after the next
  `ctl.sh start` or `git pull` on the right branch.
- Use `git branch --contains <commit>` to ask "which branches have
  this commit?" — fast way to spot "this is on a different
  branch."

## Workarounds (no patch, immediate)

- **The fork+setsid+execvp fix is now auto-reapplied** via post-merge
  hook + `_reapply_local_fix()` call + shell script. No manual steps
  needed after `git pull`. If something clobbers the fix, the watchdog
  (below) recovers within 1 minute.
- **Silent script-based watchdog (recommended)** — uses
  `scripts/webui-watchdog.sh` with `no_agent=True` cron job at
  **every 1m** interval (5m is too slow for post-update recovery).
  Zero LLM cost, stays quiet when healthy. Create with:
  ```
  cronjob action=create name=webui-watchdog schedule="every 1m" \
    no_agent=true script=webui-watchdog.sh
  ```
  The script handles two failure states: (a) process dead → `ctl.sh start`,
  (b) process alive but port dead → kill stale + restart. No Hermes
  token cost, no log noise.
**The signal-trap shim (`api/diag_shim.py`, commit `301de49c` on
`diag/observability-and-robustness`)** is now installed in the
local checkout and ships with the SIGPIPE fix in PR #3407. It
supersedes the "add try/except in main()" workaround — it captures
signals, exceptions, *and* the absence-of-marker-for-untrappable-
deaths in one tool. See `references/diag-shim.md` for the test
procedure and marker format.

**Important interaction: the shim's `_signal_handler` must NOT
re-raise SIGPIPE.** Server.py sets `SIG_IGN` on SIGPIPE at module
import time so a dropped client surfaces as `BrokenPipeError` on
that one request instead of killing the whole server. If the shim
re-raises SIGPIPE (its generic "write marker then re-raise" path),
it undoes that protection and the process dies anyway. The shim
now special-cases SIGPIPE: write the marker, set SIGPIPE back to
`SIG_IGN`, `return` (do not re-raise). This is commit `191cf6b3`
on the same branch, the third commit in PR #3407.