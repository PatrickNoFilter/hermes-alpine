# Diagnosing silent SIGKILL during post-update restart

**STATUS (2026-06-02): RESOLVED.** The bug is the **cpuset:/top-app
cgroup kill window** (Android lmkd kills any new python3 process
spawned within ~10s of the old process's exit in the same cgroup —
broader than just `os.execv`). Fix: replace the in-place `os.execv`
in `api/updates.py._schedule_restart()` with `os.fork()` +
`os.setsid()` in child + `time.sleep(15)` in child +
`os.execvp("ctl.sh", ["start"])` + `os._exit(0)` in parent. The
full code, diagnostic evolution, and 2-verified end-to-end tests
are documented in Section C of the main `SKILL.md`. The playbook
below is kept as a historical reference of HOW the diagnosis was
reached — most of it is now annotated with what we learned.

## Symptom

After `POST /api/updates/apply` returns 200, the webui goes silent
for **minutes** before the cron watchdog restarts it. The shim in
`/tmp/hermes-webui-shim/` has an `install.json` for the old PID and
a new `install.json` for the cron-restarted PID, with **no
`signal.json` / `exception.json` / `atexit.json` from the post-execv
process in between**. A 4-minute gap with no log entries from the
old process and no log entries from any new process is the
diagnostic fingerprint.

The execv happens (2s after apply, per the daemon thread), the new
process image is supposed to start, but **the new process never
serves a request** and never writes a shim marker. The user sees
"doesn't go back online" and the cron watchdog eventually brings
the process back at a fresh PID.

This is a different layer from SIGPIPE (Section B of the main
SKILL.md). The SIGPIPE fix prevents *one* cause of silent death;
the silent-SIGKILL mystery is a *separate* cause that happens to
produce a similar "4 min down" symptom and is **not prevented by
either** the execv fix or the SIGPIPE fix.

## Why the shim can't help here

SIGKILL is untrappable by design — the kernel doesn't run any
user-space code on SIGKILL, so no signal handler, no atexit hook,
and no try/except can produce a marker. The "absence of a marker
after install" is itself the canonical evidence of an untrappable
death (the same fingerprint the original shim design uses for OOM
kills), but it can't tell us *who* sent the SIGKILL or *why*.

## Suspected causes (in order of likelihood on Termux+PRoot/aarch64)

1. **Termux background-app killer (Android side)**
   Android sends SIGKILL to apps in the background when memory is
   tight. Termux is just another Android app. If the user
   backgrounded Termux to do something else while the update was
   in flight, the update's execv'd child may have been killed when
   the OS trimmed background processes. The 4-min downtime lines
   up: ~3 min for the user to background, ~1 min for the OS to
   decide the webui is reclaimable.

2. **cgroup memory limit**
   If Termux/PRoot places the container under a cgroup with
   `memory.max` set, exceeding it triggers SIGKILL (older kernels)
   or SIGTERM-then-SIGKILL (newer kernels, the OOM-killer path).
   Cheap to check (`cat /proc/self/cgroup`,
   `cat /sys/fs/cgroup/.../memory.max`) and easy to verify with
   a memory sample from the watcher.

3. **OOM killer (kernel side)**
   The kernel's OOM killer sends SIGKILL to the highest-oom-score
   process when memory is exhausted. `dmesg` would normally show
   the kill, but `dmesg` is not accessible from inside a PRoot
   container. Memory samples from `/proc/PID/status.VmRSS` over
   time will reveal unbounded growth; a stable VmRSS rules this
   out.

4. **A C-level crash in the new code**
   If the new code calls into a C extension (numpy, lxml, etc.)
   and hits a fatal error there, Python can't write a marker. Less
   likely than the above three, but worth keeping in mind.

5. **The PRoot container itself being suspended**
   Android sometimes puts Termux's PRoot into a freeze. When it
   thaws, processes may have been SIGKILLed. Hard to detect
   without external observability.

## Diagnostic playbook — cheapest first

### Step 1: Check current cgroup + resource limits (one-shot, 10s)

```bash
# cgroup membership of THIS shell — applies to the webui too
cat /proc/self/cgroup

# any cgroup memory limit?
find /sys/fs/cgroup -name "memory.max" 2>/dev/null | head -5 | \
  xargs -I {} sh -c 'echo "{}: $(cat {} 2>/dev/null || echo N/A)"'

# shell-level resource limits
ulimit -a

# the webui process specifically
PID=$(cat /root/.hermes/webui.pid 2>/dev/null)
[ -n "$PID" ] && cat /proc/$PID/limits 2>/dev/null | head -20
```

If `memory.max` is set to a small value (e.g. `536870912` = 512 MB),
**that is almost certainly the killer**. The fix is either
raising the limit (if you have permission) or reducing the webui's
memory footprint.

### Step 2: Add memory sampling to the watcher (5 min)

The watcher script `scripts/event-watcher.py` already samples
VmRSS / VmPeak / VmSize / State on every poll. Run it BEFORE the
next update. If VmRSS grows unbounded (e.g. 50 MB -> 500 MB -> 1 GB
over the post-update window), it's an OOM. If it stays flat and
the process still dies, it's not OOM.

### Step 3: strace-through-execv (10 min, definitive) — **CONFIRMED USELESS for cgroup-kill case**

**Update (2026-06-02):** strace-through-execv is **NOT** a
definitive diagnostic for this bug. Empirically: the strace
log was 0 bytes after a real SIGKILL event. The kernel kills
the new process *before* strace writes its first line (strace
prints to its log only after the first syscall returns; the
kill happens during the execve/dynamic loader window, before
any syscall completes). The kill is *faster* than strace's
own write path. **The 3-state lifecycle markers (pre-execv +
first-line + install shim) are the correct diagnostic**, not
strace. See Section C of the main SKILL.md for the final
fix; the code below is preserved for historical reference of
what we tried.

The code below is the env-gated strace branch that was
added to `_schedule_restart()` for diagnosis. It is no
longer in the live code path — it was removed when Path A
(os.fork + setsid + execvp ctl.sh + 15s sleep) replaced the
in-place execv entirely.

The gold standard. The cleaner pattern is to make the strace
routing **env-var-gated** so the patch is non-invasive and can
stay in the codebase. Add a strace branch to
`_schedule_restart()` in `api/updates.py` that fires only when
`HERMES_WEBUI_STRACE_EXECV=1` is in the environment:

```python
with _apply_lock:
    _wait_until_restart_safe()
    try:
        # Diagnostic path: route execv through strace when
        # HERMES_WEBUI_STRACE_EXECV=1 is set in the environment.
        # Captures every syscall of the new process from the very
        # first instruction. Off by default — the env var must be
        # set in the ctl.sh start environment for the trace to fire.
        _strace_on = os.environ.get('HERMES_WEBUI_STRACE_EXECV') == '1'
        _strace_path = '/usr/bin/strace'
        if _strace_on and os.path.exists(_strace_path):
            _strace_log = os.environ.get(
                'HERMES_WEBUI_STRACE_LOG',
                '/tmp/hermes-webui-shim/strace-execv.log',
            )
            # -f: follow forks (the python3 child of strace)
            # -ttt: microsecond timestamps; -T: per-syscall duration
            # -s 256: limit string-arg capture so the log doesn't
            #         grow without bound
            _strace_argv = (
                [_strace_path, '-f', '-ttt', '-T', '-s', '256',
                 '-o', _strace_log, '--', sys.executable]
                + sys.argv
            )
            os.execv(_strace_path, _strace_argv)
        else:
            os.execv(sys.executable, [sys.executable] + sys.argv)
    except Exception:
        os._exit(0)  # existing last-resort branch
```

**Toggle the diagnostic via the project's `.env`** (the one
`ctl.sh` reads via `_load_repo_dotenv_preserving_env`):

```bash
# Add to /root/hermes-webui/.env for the duration of diagnosis
HERMES_WEBUI_STRACE_EXECV=1
HERMES_WEBUI_STRACE_LOG=/tmp/hermes-webui-shim/strace-execv.log
```

Then `bash ctl.sh restart` — the env vars are inherited by the
new python process (bootstrap.py mutates `os.environ` and execv
preserves it, see `bootstrap.py:411`). Once the next user-driven
update fires `_schedule_restart()`, the new process comes up
under strace. The trace file lands next to the diag shim markers
in `/tmp/hermes-webui-shim/`.

**The strace overhead (~10%) is fine for a one-time capture.**
The env-var gate means you can leave the patch in place and flip
the trace on/off without code changes — just edit `.env` and
restart. No "revert the diagnostic" step needed. After the
diagnosis lands, set `HERMES_WEBUI_STRACE_EXECV=` (empty) in
`.env` and restart to go back to plain execv.

After the next update, the trace file will reveal:

- **OOM**: the last `mmap()` or `brk()` that pushed the process
  over the limit, then `+++ killed by SIGKILL +++` from the
  kernel.
- **cgroup**: same as OOM but with cgroup-specific syscalls
  (`memfd_create`, `process_mrelease`, `cgroup1.*` etc.).
- **Termux / manual kill**: a `kill(SIGKILL, ...)` from outside
  the process (strace shows the sender's PID if attached to the
  parent first).
- **C-level crash**: a `--- SIGSEGV / SIGBUS / SIGABRT ---` line
  with the offending address.

**Note on process shape**: with strace active, the new "webui"
process IS strace, with python3 as its child. `pgrep server.py`
no longer matches the pidfile PID — use the pidfile itself or
`pgrep -P <strace_pid>` to find python3. The diag shim still
writes markers from the python3 child, and the install marker
shows the python3 PID, not the strace PID. Cron watchdog and
`ctl.sh restart` still work correctly because they track the
pidfile (the strace outer process), and strace with `-f` exits
when its child dies.

### Step 4: coredump configuration (medium-term)

If the new code has any C-level crash, a coredump would let you
debug it offline. Configure once:

```bash
# In /root/hermes-webui/ctl.sh start, before execv:
ulimit -c unlimited
echo '/tmp/core.%e.%p.%t' > /proc/sys/kernel/core_pattern
# (the > /proc write needs CAP_SYS_ADMIN — if it fails, the
# default core_pattern is fine, just note the path)
```

This is a long-term improvement, not a quick diagnostic. Worth
doing once and leaving in place.

## What to do once you have the diagnosis

**Update (2026-06-02):** Diagnosis landed — the table below is
historical. The fix is in `api/updates.py._schedule_restart()`:
os.fork + setsid in child + 15s sleep in child + execvp ctl.sh
+ _exit(0) in parent. Full code and verification in Section C
of the main SKILL.md.

| Diagnosis | Fix |
|---|---|
| cgroup `memory.max` | Raise the limit, or reduce webui footprint |
| OOM in new code | Fix the leak; or set a memory budget watchdog |
| Termux killing us | Use a foreground notification to keep Termux alive; or run updates while Termux is foregrounded |
| New code C-crash | Debug from coredump; revert the bad commit if urgent |
| **cpuset:/top-app lmkd kill window** *(this is the actual cause)* | **os.fork + setsid + 15s sleep + execvp ctl.sh + _exit — see Section C** |
| Unknown | File the `await bind()` PR; the user's "doesn't go back online" is what we need to fix at the application layer regardless |

## The `await bind()` follow-up PR (deferred)

The maintainer of `nesquena/hermes-webui` flagged this as
in-scope on PR #3395 (execv fix, LGTM at 2026-06-02 14:13 UTC).
Their exact framing was: *the response shouldn't return 200
until the new process has actually bound port 8787* — closing
the gap where the user reloads at 2.5s, sees "offline," and the
supervisor catches it 4 min later.

The implementation is non-trivial (fork+execv so the parent can
keep the request handler open and poll for bind readiness) and
the maintainer agreed to defer. If the silent-SIGKILL diagnosis
turns out to be one of the cgroup/OOM/Termux causes above, the
`await bind()` PR is **still worth filing** because it gives the
user a clear "restart complete" signal at the application layer
even when the OS-level death is opaque. If the diagnosis turns
out to be a code-level crash in the new code, the PR is less
urgent (the new code is the real problem, not the bind timing).

## Capturing the next event — operational pattern

The "set up watcher, trigger event, post-mortem from log"
pattern is reusable for any intermittent failure. The
`scripts/event-watcher.py` script is the template; the analysis
workflow is:

1. Take a baseline (`/api/updates/check` + process list + shim
   marker count).
2. Start the watcher in the background:
   `python3 scripts/event-watcher.py &`
3. Trigger the event (in this case, click Update Now in the
   browser).
4. Wait for the event to complete (watcher will show
   `MARKER COUNT: ...` and `HEALTH CHANGED: ...` entries).
5. Stop the watcher (`kill -TERM %1`).
6. Cross-reference the watcher's event log with the shim
   markers, the webui log, and the cron watchdog log.
7. Diagnose from the union of all four sources.
