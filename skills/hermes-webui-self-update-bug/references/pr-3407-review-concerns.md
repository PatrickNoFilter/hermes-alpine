# PR #3407 — Open Review Concerns

**PR**: https://github.com/nesquena/hermes-webui/pull/3407
**Branch**: `PatrickNoFilter:diag/observability-and-robustness` → `nesquena:master`
**Scope at time of review (2026-06-02 17:06 UTC)**: 11 commits, 6 files, +585/-20

The contributor (PatrickNoFilter) explicitly offered to split the PR
into Group 1 (3 commits, SIGPIPE trio, ship-now) and Group 2+3
(8 commits, cgroup fix + markers + changelog). Recommend accepting
the split — matches the "one PR, one logical change" precedent
set by #3395's LGTM.

## D.1 `os.fork()` in a multi-threaded Python process

**Severity**: real risk, latent deadlock under load.

The `_schedule_restart` patch does `os.fork()` while the parent has
≥3 live threads (MainThread in `serve_forever`, gateway-watcher,
plus N request threads). CPython: only the calling thread survives
in the child; any non-MainThread mutex held at fork is permanently
locked in the child.

The 15s sleep in the child runs *between* `os.setsid()` and
`os.execvp()` while the child is a forked single-threaded process.
If any internal CPython lock was held at fork time (buffered I/O
from a request thread's `socket.send()`, a `threading.Lock` in a
daemon, etc.), the child can deadlock before `execvp` ever runs.
The skill's Section C documents the fix without ever noting this
risk.

**Why the existing verification doesn't catch it**: the 2 real-
update tests in Section C happened during low-traffic windows.
The risk surfaces when a request thread is mid-`send()` at the
exact moment `os.fork()` is called from the update thread.

**Mitigations** (pick one):
1. **Spawn a tiny single-threaded helper** that does the
   `setsid + sleep + execvp`. Run it via
   `subprocess.Popen([sys.executable, helper_path, ...])` from
   the old process — the fork then happens in a *fresh*
   interpreter with no other threads. Accept the
   Popen-dies-with-parent failure mode and recover via cron.
2. **Document explicitly in `api/updates.py`** why the
   multi-threaded fork is acceptable for this specific code
   path. Must argue the post-fork child has no I/O between
   `setsid` and `execvp` AND that no other thread holds a
   non-thread-local lock at the moment of fork (impossible
   to guarantee without instrumentation).

Recommend option (1). The helper script pattern is the same
one `cron` already uses (single-threaded `bash ctl.sh start`),
so the failure mode is well-understood and recoverable.

## D.2 The 15s sleep is a workaround, not a fix

**Severity**: magic number with no instrumentation.

The PR body calls 15s "the actual fix" but it's a timing
workaround for Android's `cpuset:/top-app` lmkd killing any new
python3 process within ~10s of the old process's exit in the
same cgroup.

**Problems**:
- If a future Android version, kernel, or lmkd config changes
  the ~10s window (longer OR shorter), the fix silently breaks.
- There's no `{pid}-post-sleep.json` marker, so post-mortem
  can't distinguish "sleep was sufficient" from "got lucky."
- The PR body doesn't enumerate alternatives considered.

**Fix**:
1. Add a `{pid}-003-post-sleep.json` marker immediately before
   `execvp` in the fork child. This lets post-mortem verify the
   sleep was actually sufficient (if the new process starts
   cleanly with a post-sleep marker but dies soon after, the
   sleep was sufficient but something else is wrong; if
   post-sleep fires but the new process never installs, the
   sleep wasn't enough and we need a longer delay).
2. Reword the PR body: "The fix" → "The workaround (15s timing
   on current Termux+PRoot; root cause is lmkd cgroup behavior
   we don't control)."
3. Add an `os.environ` check: if `HERMES_WEBUI_CGROUP_RESTART`
   is unset, skip the fork+sleep and rely entirely on the cron
   watchdog (the 5-min recovery the skill says "provably
   survives"). This gives operators an escape hatch if the
   15s timing turns out to be wrong on a specific device.

**Alternatives not considered in the PR**:
- (a) Swap the new PID to a different cgroup before exec via
  `/proc/self/cgroup` manipulation. Requires CAP_SYS_ADMIN
  and doesn't work in PRoot anyway, but worth documenting
  why it was rejected.
- (b) `prctl(PR_SET_PDEATHSIG, 0)` + `setsid` + drop cgroup
  via `cgexec` if installed. `cgexec` not available on
  Termux+PRoot, so this is a no-op there — but on standard
  Linux servers it's the right answer.
- (c) Skip the in-app restart entirely and rely on the cron
  watchdog's 5-min recovery. Slowest but most robust. The
  skill's Section C says this "provably survives" the cgroup
  transition. A 5-min downtime for a manual `Update Now` is
  acceptable; ~20s of fake-out activity that's just
  re-implementing the watchdog path in-app is not obviously
  better.

## D.3 The diag shim is always-on in production

**Severity**: production cost + persistence.

`api/diag_shim.py` runs at every server startup with no opt-out.
The try/except makes it safe, but:

- **No log rotation.** A busy server can write hundreds of MB
  of marker JSON to `/tmp/hermes-webui-shim/` over months.
- **`/tmp` is unreliable.** On reboot or tmpfs-clean, all
  evidence is lost. Worse, on Termux `/tmp` is the same
  filesystem as the user data partition, so a full disk
  silently breaks the diag system without anyone noticing.
- **No max-count or max-age cleanup.** A long-running server
  accumulates thousands of marker files.

**Recommend**:
1. Opt-in via `HERMES_WEBUI_DIAG=1` env var, default off.
   Same observability when you need it, lower production
   cost when you don't.
2. Home in `~/.hermes/webui-shim/` instead of `/tmp/`.
   Per-user, persistent across reboots, not subject to
   tmpfs-clean.
3. Add a `MAX_MARKER_FILES = 1000` constant; on install(),
   trim to the most recent N files (sort by mtime, unlink
   the rest).
4. On SIGTERM/SIGINT, delete the install marker so a future
   "absent marker" reading doesn't get confused with an
   untrappable death.

## D.4 Marker file naming uses magic numbers

**Severity**: maintainability, future-proofing.

`{pid}-000-pre-execv.json` and `{pid}-001-first-line.json`
implicitly encode ordering via the `000`/`001` prefix. Adding
a "second-line" marker in the future would force a renumbering
of existing markers, breaking any log analyzer or post-mortem
script that depends on the filename.

**Fix**: drop the prefix. The PID is already in the path, and
the order is preserved by the timestamp-based filenames
(`<ms>-<counter>-*.json`) already used by the diag shim. Use:
- `{pid}-pre-execv.json`
- `{pid}-first-line.json`
- `{pid}-post-sleep.json` (the new one from D.2)

## D.5 User-side scripts in upstream repo

**Severity**: scope creep, repo pollution.

`start-webui.sh` (6 lines) and `watchdog-loop.sh` (27 lines)
hard-code `/root/hermes-webui` and `127.0.0.1:8787`. These are
user-specific deploy scripts, not part of the webui server.

**Fix**: move them to this skill's `scripts/` directory (or
`hermes-webui-self-update-bug/scripts/` in the local checkout).
The upstream repo should not have user-specific paths baked
into shell scripts.

## D.6 PR body is 8KB — too long for a reviewer

**Severity**: review ergonomics.

A maintainer doing a first pass will bounce off this.
Suggested restructure for the PR body:

- **TL;DR** (3-4 lines) — what, why, risk
- **Changes** (table of 11 commits, one line each)
- **Verification** (one short paragraph + the 2 real-update
  timestamps as evidence)
- **Risks & known limitations** (the 15s timing magic
  number, the fork-in-multithreaded-process)
- **Out of scope / followups** (the things explicitly
  deferred: argv-shape frozen guard in #3395, cron `*/1`
  tightening, etc.)

Move the per-commit deep-dive, the production log fingerprint,
and the diagnostic-evolution narrative to a linked gist or
this skill's references.

## Suggested comment for the PR

> Thanks for the thorough PR — the production verification is
> genuinely good, and the 3-state marker table is the right
> abstraction. Two requests before merge:
>
> 1. **Split into PR-A (Group 1, 3 commits) and PR-B (Group 2+3,
>    8 commits).** PR-A is shippable as-is — the SIGPIPE trio is
>    a standard Python HTTP server pattern and the shim is a
>    well-disciplined observability tool. PR-B needs the
>    concerns in the linked reference addressed first.
>
> 2. **For PR-B specifically**, the `os.fork()` in a
>    multi-threaded process (D.1) and the 15s magic number
>    with no instrumentation (D.2) are the two issues I'd
>    want to see resolved. The helper-script-via-Popen
>    pattern from D.1 mitigation (1) and the
>    `{pid}-post-sleep.json` marker from D.2 fix #1 are the
>    smallest changes that close the gaps.
>
> The other points (D.3-D.6) are nice-to-haves — not blockers
> for me. Full breakdown in the linked reference.

---

## E. Actual Maintainer Review — nesquena-hermes (2026-06-02 18:23 UTC)

**Review URL**: `https://github.com/nesquena/hermes-webui/pull/3407#pullrequestreview-4605799643`

### Verdict

- **Group 1 (SIGPIPE fix, 3 commits)**: **APPROVED — ship-worthy.**
- **Group 2 (cgroup-kill restart, 6 commits)**: **BLOCKED — must be gated before merge.**
- **Group 3 (CHANGELOG, 2 commits)**: Blocked with Group 2.

### E.1 Critical: no platform gate on fork+ctl.sh restart (Docker breakage)

**Severity: CONTAINER DEATH.** The fork+sleep+execvp(ctl.sh start)+_exit(0)
path in `api/updates.py` applies **unconditionally** — no `_is_termux()`
check, no `uname`, no `sys.platform` guard.

**Docker lifecycle**: `python server.py` is a child of `docker_init.bash`
(PID 1). When the parent calls `os._exit(0)`, `docker_init.bash` (which
runs `exec python server.py` at line ~457) falls through to `ok_exit`,
causing PID 1 to exit and the **container to die**. The forked child that
was supposed to exec `ctl.sh start` never gets a chance — the kernel
kills it when the container stops.

Additionally, Docker never launches via `ctl.sh` at all — it runs
`python server.py` directly through `docker_init.bash`. So
`execvp(ctl.sh start)` in the fork child hits the wrong process
management path even if the container stayed alive.

**Fix required**:

```python
# Old (unconditional):
ctl_path = os.path.join(REPO_ROOT, 'ctl.sh')
_child_pid = os.fork()
if _child_pid == 0:
    try: os.setsid()
    except: pass
    time.sleep(15)
    try: os.execvp(ctl_path, [ctl_path, 'start'])
    except: os._exit(1)
time.sleep(0.3)
os._exit(0)

# New (gated):
if _is_termux() or os.environ.get('HERMES_WEBUI_RESTART_VIA_CTL'):
    ctl_path = os.path.join(REPO_ROOT, 'ctl.sh')
    _child_pid = os.fork()
    if _child_pid == 0:
        try: os.setsid()
        except: pass
        time.sleep(15)
        try: os.execvp(ctl_path, [ctl_path, 'start'])
        except: os._exit(1)
    time.sleep(0.3)
    os._exit(0)
else:
    # Standard re-exec (Docker/systemd/launchd)
    if getattr(sys, "frozen", False):
        os.execv(sys.executable, sys.argv)
    else:
        os.execv(sys.executable, [sys.executable] + sys.argv)
```

**How to detect Termux in server.py**:
```python
def _is_termux() -> bool:
    """Return True if running under Termux on Android."""
    # Termux sets $PREFIX=/data/data/com.termux/files/usr
    # and TERMINUX_VERSION is also reliable.
    return bool(os.environ.get("TERMINUX_VERSION")) or \
           (os.environ.get("PREFIX", "").startswith(
               "/data/data/com.termux"))
```

### E.2 Non-critical observations from the review

- **Commit `191cf6b3`** correctly prevents the diag shim from
  re-defaulting SIGPIPE to Term: writes the marker, re-arms
  `SIG_IGN`, returns without re-raising. This was caught by the
  shim itself during a real update test (PID 12029, 14:03 UTC) —
  the shim's generic `_signal_handler` was undoing the fix. Good
  regression catch.
- The **Docker breakage** also implies that `os.fork()` in a
  multi-threaded process (D.1) is not a concern for Docker users
  — the fork path won't run, the standard `os.execv` will.
- The reviewer noted the author (`PatrickNoFilter`) has not
  responded or pushed new commits as of the review timestamp.
- The reviewer split recommendation (PR-A / PR-B) aligns with
  the self-review in Section D. The maintainer explicitly called
  the SIGPIPE trio "ship-worthy" and the cgroup fix "needs gating
  before merge."

### E.3 Current PR status (as of 2026-06-03)

- **State**: Open. **Merged**: False. **Mergeable**: False (conflicts).
- Last activity: Review at 2026-06-02T18:23:13Z.
- Author has not responded or pushed new commits.
- The **local checkout** (`/root/hermes-webui/`) has the full
  11-commit PR on branch `pr-3407`, with `master` (43 new commits,
  v0.51.213–v0.51.230) merged in and conflicts resolved:
  - `api/updates.py` conflict: retained PR's fork+ctl.sh approach
    (HEAD) over master's `sys.frozen` execv guard (the gating
    concern from E.1 is still unaddressed in the local code).
  - `CHANGELOG.md` conflict: PR's [Unreleased] on top, master's
    new releases below.
- The **fork+ctl.sh path is currently live** on the running WebUI
  (PID 17239). It works on Termux (validated in test 3 and 4
  during the PR's development). It would **break Docker** if
  deployed upstream without the gate.

---

**References**:
- Section D in `SKILL.md` (the inline version of the self-review concerns)
- Section C of the umbrella skill — the 4-stage diagnostic evolution
- The PR itself: https://github.com/nesquena/hermes-webui/pull/3407
- Comment `4605799643` on PR #3407 (the maintainer's review)
- `references/restart-window-markers.md` — the 3-state decision table
  that this PR implements
- `references/test-suite-guard-regression.md` — test-suite guard
  regression when `_schedule_restart()` changed to fork+exit+execvp
