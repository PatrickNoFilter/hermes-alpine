# Test-Suite Guard Regression — `os.execv` → `os.fork()/os._exit()/os.execvp()`

## The problem

PR #3407 changed `_schedule_restart()` from `os.execv()` to
`os.fork()` + `os.setsid()` + `time.sleep(15)` + `os.execvp(ctl.sh)`
+ `os._exit(0)`. The existing test-suite guards only cover
`os.execv()` — the new code paths are fully unguarded, creating
a silent test-suite corruption risk.

## The existing guards

### `tests/conftest.py` (line 232-260)

Installs a permanent session-wide no-op on `os.execv`:

```python
_real_execv = os.execv
def _pytest_session_safe_execv(_exe, _args):
    return None
os.execv = _pytest_session_safe_execv
```

Purpose: daemon threads spawned by `_schedule_restart()` can fire
after monkeypatch teardown, re-execing the real `os.execv` and
restarting the entire pytest process. The permanent guard prevents
this.

### `tests/test_pytest_execv_guard.py` (2 tests)

- `test_conftest_installs_permanent_execv_guard` — asserts
  `os.execv.__name__ == '_pytest_session_safe_execv'`
- `test_safe_execv_returns_none_does_not_exec` — asserts the
  wrapper returns `None` instead of executing

## What's missing — the new code paths

The new `_schedule_restart()` uses **four** syscalls that the
guards don't cover:

| Syscall | What it does | Test-suite risk |
|---------|-------------|-----------------|
| `os.fork()` | Creates a child process with copy-on-write memory | Forks pytest midway through test execution — two processes running the same test runner |
| `os._exit(0)` | Terminates the process immediately (no atexit, no cleanup) | Kills the pytest process without cleanup — no test failure, just silent death |
| `os.setsid()` | Detaches from parent session (in child) | Harmless in a forked context |
| `os.execvp()` | Replaces process image (in child) | Replaces the forked child with `ctl.sh start` — runs actual WebUI startup during tests |

Additionally, `server.py` module-level code runs at import time:

- `_write_first_line_marker()` — writes to `/tmp/hermes-webui-shim/`
- `signal.signal(signal.SIGPIPE, signal.SIG_IGN)` — changes
  process-level signal disposition
- In `main()`: `_install_diag()` writes an install marker to
  `/tmp/hermes-webui-shim/`

Any test that imports server.py or starts the server triggers
these side effects.

## The failing test

`tests/test_update_banner_fixes.py::test_schedule_restart_is_nonblocking`
(line 347):

```python
def test_schedule_restart_is_nonblocking(self, monkeypatch):
    import api.updates as upd

    execv_called = []
    def fake_execv(exe, args):
        execv_called.append((exe, args))

    import os as _os
    monkeypatch.setattr(_os, 'execv', fake_execv)

    start = time.monotonic()
    upd._schedule_restart(delay=0.05)
    elapsed = time.monotonic() - start

    assert elapsed < 0.5
    time.sleep(0.2)
    assert execv_called, "_schedule_restart must eventually call os.execv"
```

With the new code:
- `monkeypatch.setattr(_os, 'execv', ...)` patches the test
  module's `os.execv` — but the daemon thread's `_do()` does
  `import os` *inside the function*, getting a new local reference
  to the real `os` module that the monkeypatch doesn't reach
- The daemon thread calls `os.fork()` → forks pytest
- The parent thread calls `os._exit(0)` → kills the pytest process
- The child thread calls `os.setsid()` + `time.sleep(15)` + 
  `os.execvp(ctl.sh start)` → runs the actual WebUI
- `execv_called` is never populated → assertion fails (if the
  process survived long enough to reach it)

## What to add to conftest.py

```python
# ── Permanent os.fork/os._exit/os.execvp guard for the pytest session ───
_real_exit = os._exit
def _pytest_session_safe_exit(code):
    return None  # never let a daemon thread kill pytest
os._exit = _pytest_session_safe_exit

_real_fork = os.fork
def _pytest_session_safe_fork():
    return -1  # return error so daemon thread falls through harmlessly
os.fork = _pytest_session_safe_fork

_real_execvp = os.execvp
def _pytest_session_safe_execvp(file, args):
    return -1  # drop on the floor
os.execvp = _pytest_session_safe_execvp
```

## And update `test_pytest_execv_guard.py`

The test should also verify the new guards are installed:

```python
def test_conftest_installs_permanent_fork_guard():
    import os
    assert os.fork.__name__ == '_pytest_session_safe_fork'

def test_conftest_installs_permanent_exit_guard():
    import os
    assert os._exit.__name__ == '_pytest_session_safe_exit'

def test_safe_fork_returns_neg_one():
    import os
    assert os.fork() == -1  # never actually forks

def test_safe_exit_does_not_exit():
    import os
    result = os._exit(0)
    assert result is None
```

## How to prevent this class of regression in future reviews

When a PR touches these files, always verify the guard coverage:

1. **`api/updates.py`** — `_schedule_restart()` calls
   `os.execv()` / `os.execvp()` / `os.fork()` / `os._exit()`
2. **`server.py`** — module-level `_write_first_line_marker()`,
   `signal.signal(SIGPIPE, SIG_IGN)`, and `_install_diag()`
3. **`api/diag_shim.py`** — `install()` writes markers,
   `signal.signal()` on 12+ signals

Search pattern for the review:

```bash
grep -rn 'os\.fork\|os\._exit\|os\.execvp\|signal\.signal\|os\.execv' \
  api/updates.py api/diag_shim.py server.py
```

Then check `tests/conftest.py` for matching guards:

```bash
grep -n 'os\.fork\|os\._exit\|os\.execvp\|os\.execv' tests/conftest.py
```

If the list doesn't match, the conftest.needs updating.

## Related

- `references/restart-window-markers.md` — the 3-state marker
  system that runs at import time and triggers signal handlers
- `SKILL.md` Section C — the `os.fork()` fix rationale and
  the multi-threaded-fork risk
- `SKILL.md` Section D.1 — the multi-threaded fork review concern
