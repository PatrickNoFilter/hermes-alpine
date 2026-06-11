#!/usr/bin/env bash
# Re-apply the Termux+PRoot cgroup-kill restart fix if update overwrote it.
# Called by .git/hooks/post-merge or manually after `git pull`.
set -e

UPDATES="api/updates.py"
cd /root/hermes-webui

# Check if fix was overwritten
if grep -q "os.fork() + os.setsid() + os.execvp()" "$UPDATES" 2>/dev/null; then
    # Fix still present, nothing to do
    exit 0
fi

# Check that the old code exists
if grep -q "os.execv(sys.executable" "$UPDATES" 2>/dev/null; then
    echo "[webui-fix] Re-applying cgroup-kill restart patch..."

    # Use Python to do the replacement (avoids fragile sed patterns)
    python3 -c "
import re
with open('$UPDATES') as f:
    c = f.read()

# Replace the old _schedule_restart function
old = '''def _schedule_restart(delay: float = 2.0) -> None:
    \"\"\"Re-exec this process after *delay* seconds.

    Called after a successful update so that the freshly-pulled code is
    loaded on the next request, rather than running with a mix of old and
    new Python modules in sys.modules.

    os.execv() replaces the current process image with a fresh interpreter
    running the same argv — sessions are preserved on disk, the HTTP port
    is reclaimed within the delay window, and the client's own
    ``setTimeout(() => location.reload(), 2500)`` lands after the restart.

    Coordinates with ``_apply_lock``: when the user updates both webui
    and agent, the client POSTs them sequentially.  Without coordination
    the restart timer scheduled by the first update's success would fire
    while the second update's git-pull is still running, killing it mid-
    stream and leaving the second repo in an unknown partial state.
    Blocking on ``_apply_lock`` before ``os.execv`` means a pending
    second update always completes before the restart happens.
    \"\"\"
    import os
    import sys

    def _do():
        import time
        time.sleep(delay)
        # Hold _apply_lock through os.execv so no new update can start between
        # the lock-release and the process replacement.  Any in-flight update
        # finishes first (since it holds the lock), and then the process is
        # replaced while still holding the lock — meaning no new update can
        # sneak in during the brief TOCTOU window that existed with the
        # original acquire-release-execv sequence.
        # Threads die when execv replaces the process image, so the lock is
        # released atomically by the kernel.
        with _apply_lock:
            _wait_until_restart_safe()
            try:
                if getattr(sys, \"frozen\", False):
                    os.execv(sys.executable, sys.argv)
                else:
                    os.execv(sys.executable, [sys.executable] + sys.argv)
            except Exception:
                # Last-resort: if execv fails for any reason, just exit so the
                # process supervisor (start.sh / Docker) restarts us.
                os._exit(0)

    threading.Thread(target=_do, daemon=True).start()'''

new = '''def _schedule_restart(delay: float = 2.0) -> None:
    \"\"\"Re-spawn this process after *delay* seconds via detached ctl.sh.

    Called after a successful update so that the freshly-pulled code is
    loaded on the next request, rather than running with a mix of old and
    new Python modules in sys.modules.

    Why not ``os.execv()``: on Termux+PRoot / Android the Android cgroup
    hierarchy (``cpuset:/top-app``) SIGKILLs the new process image
    sub-millisecond during the kernel execve() transition, before any user
    code runs.  The fix is to spawn a detached ``ctl.sh start`` subprocess
    via ``os.fork()`` + ``os.setsid()`` + ``os.execvp()``, then let the
    old process exit cleanly.  The child has its own PID and is a separate
    task in the cgroup hierarchy, so the parent's cgroup kill window
    doesn't reach it.

    Coordinates with ``_apply_lock``: when the user updates both webui
    and agent, the client POSTs them sequentially.  Without coordination
    the restart timer scheduled by the first update's success would fire
    while the second update's git-pull is still running, killing it mid-
    stream and leaving the second repo in an unknown partial state.
    Blocking on ``_apply_lock`` before spawning the detached starter
    means a pending second update always completes before the restart.
    \"\"\"
    import os
    import subprocess
    import sys
    import time

    def _do():
        time.sleep(delay)
        # Hold _apply_lock through the spawn so no new update can start
        # between the lock-release and the process exit.  Any in-flight
        # update finishes first (since it holds the lock), and then we
        # spawn the detached starter while still holding the lock.
        with _apply_lock:
            _wait_until_restart_safe()
            try:
                # Detached starter: fork, setsid() to detach from parent's
                # cgroup/session, then execvp into ctl.sh start.
                ctl_path = os.path.join(REPO_ROOT, 'ctl.sh')
                _child_pid = os.fork()
                if _child_pid == 0:
                    # Child -- detach from parent session/process group so
                    # the parent can os._exit without sending SIGHUP.
                    os.setsid()
                    os.execvp('bash', ['bash', ctl_path, 'start'])
                    # If execvp fails, _exit so we don't fall through.
                    os._exit(1)
                # Parent -- exit cleanly. The child now runs independently.
                os._exit(0)
            except Exception:
                # Last-resort: if anything fails, just exit so the
                # process supervisor (start.sh / Docker) restarts us.
                os._exit(0)

    threading.Thread(target=_do, daemon=True).start()'''

if old in c:
    c = c.replace(old, new, 1)
    with open('$UPDATES', 'w') as f:
        f.write(c)
    print('[webui-fix] Re-applied cgroup-kill restart fix')
else:
    # Try simpler fallback: replace execv lines
    if 'os.execv(sys.executable' in c:
        print('[webui-fix] WARNING: upstream changed _schedule_restart signature')
        print('[webui-fix] Manual fix needed: edit api/updates.py')
    else:
        print('[webui-fix] Fix already applied, nothing to do')
"
fi
