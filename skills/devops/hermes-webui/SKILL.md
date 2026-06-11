---
name: hermes-webui
description: Operate and troubleshoot the Hermes Web UI (nesquena/hermes-webui) — startup, crash diagnosis, dependency fixes, env vars, and common pitfalls. Covers the separate webui project at /root/hermes-webui (port 8787), NOT the built-in Hermes dashboard (port 9119).
---

# Hermes Web UI

The Hermes Web UI is a separate project ([nesquena/hermes-webui](https://github.com/nesquena/hermes-webui)) that provides full CLI-parity web access to the Hermes agent. It lives at `/root/hermes-webui/`.

## Required Environment Variables

| Variable | Value | Why |
|----------|-------|-----|
| `HERMES_WEBUI_AGENT_DIR` | `/usr/local/lib/hermes-agent` | Agent auto-discovery in `api/config.py` doesn't check `/usr/local/lib/` — only `/usr/local/`, `/opt/`, etc. Without this, `run_agent.py` isn't found and agent features break. |
| `HERMES_WEBUI_HOST` | `127.0.0.1` (local-only) or `0.0.0.0` (LAN) | **`127.0.0.1`** — local only, safe, no auth needed. Reachable from PRoot itself and SSH tunnels. **`0.0.0.0`** — reachable from Android host browser on the same WiFi. Only use `0.0.0.0` if you need LAN access; pair with `HERMES_WEBUI_PASSWORD`. |
| `HERMES_WEBUI_PYTHON` | `/usr/local/lib/hermes-agent/venv/bin/python` | System `python3` lacks the `dotenv` module required by `run_agent.py`. The agent's venv Python has all dependencies. The server will serve HTML but agent features silently fail without this. |

## Startup

### Using the wrapper script (recommended)
```bash
cd /root/hermes-webui && bash start-webui.sh
```

### Manual start (background process)
```bash
cd /root/hermes-webui && \
HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent \
HERMES_WEBUI_HOST=0.0.0.0 \
/usr/local/lib/hermes-agent/venv/bin/python server.py
```

### Startup script location
`/root/hermes-webui/start-webui.sh` — sets all env vars and launches the server.

## Restarting the Server

When switching config (e.g. changing `HERMES_WEBUI_HOST`), the old process still holds the port. You'll see `OSError: [Errno 98] Address already in use`.

### Safe kill procedure

```bash
# 1. Kill the old server process
pkill -f "server.py"   # NOT -9 — avoid killing the agent shell

# 2. Wait for port to release
sleep 2

# 3. Verify port is free
timeout 3 python3 -c "
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('127.0.0.1', 8787))
    print('Port 8787 is FREE')
    s.close()
except OSError:
    print('Port 8787 still in use — wait or kill manually')
"

# 4. Start the new server
/root/hermes-webui/start-webui.sh
```

### Pitfalls

- **Do NOT use `pkill -9 -f "server.py"`** in PRoot/Termux — the `-9` and broad `-f` pattern can match the agent's own Python process, killing the agent shell (exit code -9 / SIGKILL).
- **Do NOT use `pgrep -f "server.py"`** to FIND the webui PID. The `-f` flag matches against the full command line, so it matches the calling shell whose command string contains `"server.py"` as a literal argument. If you then `kill -9` the matched PID, you SIGKILL your own terminal session. Safe alternatives:
  ```bash
  PID=$(cat /root/.hermes/webui.pid)            # best: ctl.sh writes the PID file
  PID=$(lsof -tiTCP:8787 -sTCP:LISTEN)          # good: by listening port
  PID=$(lsof -tiTCP:8787 -sTCP:LISTEN | head -1)  # port-based: targets ONLY webui, unlike pgrep -x python which matches ANY python process
  ```
- **`fuser -k 8787/tcp` may not work** reliably inside PRoot. Use the Python `SO_REUSEADDR` check above instead.
- **If you changed `start-webui.sh`**, ensure the old server is fully dead first — background processes stick around even after shell exits.

## Diagnostics

### Is the server running?
```bash
timeout 3 python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
r = s.connect_ex(('127.0.0.1', 8787))
print('Port 8787:', 'OPEN' if r == 0 else 'CLOSED')
s.close()
"
```

### Check the server log
```bash
tail -50 /tmp/hermes-webui.log
```

### Verify startup configuration
Look for the `Hermes Web UI -- startup config` block in the log:
- `agent dir   : /usr/local/lib/hermes-agent  [ok]` — agent found
- `python      : /usr/local/lib/hermes-agent/venv/bin/python` — correct Python in use
- `host:port   : 0.0.0.0:8787` — accessible from LAN; `127.0.0.1:8787` — local-only

### "Why did it die?" — check the diag-shim markers
The local checkout has a signal-trap shim installed
(`api/diag_shim.py`, see `hermes-webui-self-update-bug` skill's
`references/diag-shim.md`). When the server dies, look in
`/tmp/hermes-webui-shim/`:

| Files present | Meaning |
|---------------|---------|
| Only `*-install.json` (no signal/exception/atexit after it) | Untrappable death — SIGKILL, OOM, container suspend, or manual `kill -9`. The 3 most-likely culprits on Termux+PRoot are listed in `hermes-webui-self-update-bug` section B. |
| `*-signal.json` with `signal_name: SIGTERM` (etc.) | Caught a catchable signal. The marker has the full stack and every thread's stack. |
| `*-exception.json` with `exception_type` | `serve_forever` raised. The marker has the full traceback. |
| `*-atexit.json` | Normal interpreter shutdown. |

The shim is the **canonical post-mortem tool** — supersedes the
older "add try/except in main()" workaround.

## Common Failures & Fixes

### Server starts then dies quickly
**Symptom**: Port closes after a few requests. Log shows `No module named 'dotenv'` / `ModuleNotFoundError: No module named 'run_agent'`.

**Cause**: Server runs with system `python3` that lacks Hermes agent dependencies (dotenv, etc.).

**Fix**: Always use the agent's venv Python:
```bash
export HERMES_WEBUI_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python
```
Or launch via the wrapper script.

### "Could not find the Hermes agent directory"
**Cause**: `_discover_agent_dir()` in `api/config.py` searches standard paths (`/usr/local/hermes-agent`, `/opt/hermes-agent`) but NOT `/usr/local/lib/hermes-agent`.

**Fix**: Set `HERMES_WEBUI_AGENT_DIR` explicitly:
```bash
export HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent
```

### "Still offline" / can't reach from Android browser
**Cause**: Server bound to `127.0.0.1` inside PRoot — not accessible from Android host.

**Fix**: Bind to all interfaces:
```bash
export HERMES_WEBUI_HOST=0.0.0.0
```

### Security: no-password warning
When binding to `0.0.0.0`, the server prints a WARNING about no password. Anyone on the same network can access the Web UI. Set a password via:
```bash
export HERMES_WEBUI_PASSWORD=<your-password>
```
Or in the Hermes config `password` setting.

## Watchdog / Auto-Restart

The webui can die silently after an update restart on Termux+PRoot
(Android cgroup kill window — see `hermes-webui-self-update-bug` skill
Section C). A watchdog catches this and restores it automatically.

### Primary method: cronjob + no_agent script (preferred)

Uses Hermes' built-in cron scheduler with `no_agent=True` — zero LLM
cost, shell-level check, only speaks when it restarted.

**Script** (`~/.hermes/scripts/webui-watchdog.sh`):

```bash
#!/usr/bin/env bash
PORT=8787
CTL="/root/hermes-webui/ctl.sh"
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
  if ! pgrep -f "bootstrap\.py\|server\.py.*$PORT" > /dev/null 2>&1; then
    bash "$CTL" start
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] webui was down — restarted"
  else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] webui process exists but port $PORT not responding — killing stale"
    bash "$CTL" stop 2>/dev/null
    sleep 2
    bash "$CTL" start
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] webui restarted (stale process)"
  fi
fi
```

**Register**:

```bash
cronjob action=create name=webui-watchdog schedule="every 1m" \
  no_agent=true script=webui-watchdog.sh
```

Key points:
- **1-minute interval** — 5 minutes is too slow for post-update recovery
  on PRoot; the cgroup kill window is ~10s, so a 1-min check catches
  it and restores within 60s
- `no_agent=True` means zero LLM tokens — the script runs as a shell
  process, its stdout delivered verbatim only when non-empty
- Handles two failure states: (a) process dead → `ctl.sh start`,
  (b) process alive but port dead → kill stale + restart
- Stays **completely silent when healthy** — no output means no
  delivery to the user

### Fallback: bash loop watchdog (gateway unavailable)

When the Hermes Gateway cron scheduler can't run (PRoot/Termux,
containers without systemd), cron jobs won't fire — `hermes cron
status` shows "Gateway is not running — cron jobs will NOT fire".

Use a bash loop instead:

```bash
#!/bin/bash
# /root/hermes-webui/watchdog-loop.sh
HOST="127.0.0.1"
PORT="8787"
WEBUI_DIR="/root/hermes-webui"
LOG_FILE="/tmp/hermes-webui-watchdog.log"
PID_FILE="/tmp/hermes-webui-watchdog.pid"

echo $$ > "$PID_FILE"

while true; do
    if ! curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
        echo "[$(date)] WebUI DOWN — restarting..." >> "$LOG_FILE"
        cd "$WEBUI_DIR"
        bash ctl.sh start >> "$LOG_FILE" 2>&1
        sleep 20  # 8-10s for PRoot bind + buffer
        if curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
            echo "[$(date)] WebUI restarted successfully" >> "$LOG_FILE"
        else
            echo "[$(date)] WebUI restart FAILED" >> "$LOG_FILE"
        fi
    fi
    sleep 60  # 1-min interval
done
```

Launch via:
```bash
terminal(background=true, command="bash /root/hermes-webui/watchdog-loop.sh")
process(action='poll', session_id='proc_...')
```

### When to use which

| Method | Best for |
|--------|----------|
| **cronjob + no_agent script** (preferred) | Gateway is running (standard setup) |
| Bash loop watchdog (above) | PRoot, containers, any env without gateway |
| Both (redundant) | Production |

### Restart via ctl.sh (the correct way)

For manual restart or from a watchdog script, always use `ctl.sh`, not raw `server.py`:

```bash
cd /root/hermes-webui && bash ctl.sh start
```

`ctl.sh` handles:
- Sourcing `.env` (preserving existing env vars)
- Finding the right Python (`HERMES_WEBUI_PYTHON` → `python3` → `python`)
- Writing PID file and state
- Preventing duplicate starts
- Logging to `${HERMES_HOME}/webui.log`

### Common pitfalls

- **Cron job with `repeat: "once"` only fires once** — always set `repeat: "forever"` for recurring checks, or omit `repeat` for default-forever on recurring schedules.
- **`hermes gateway` must be running** for cron jobs to fire. If `hermes cron status` says "Gateway is not running", the scheduler isn't running — use the bash loop instead.
- **The watchdog script must use the server's own `.env` file** — either via `ctl.sh` (recommended) or by sourcing it explicitly. Without `HERMES_WEBUI_AGENT_DIR`, agent features will silently fail on restart.
- **`sleep 5` after restart is too short on PRoot** — the webui takes 8-10s to bind 127.0.0.1:8787 on Termux+PRoot (vs ~1s on x86_64). The watchdog's post-restart grace must be `sleep 20` minimum, otherwise it logs `restart FAILED` and waits another 5 minutes. A healthy restart looks like:
  ```bash
  bash ctl.sh start
  sleep 20  # 8-10s PRoot bind + 10s buffer
  curl -fsS --max-time 3 http://127.0.0.1:8787/health >/dev/null
  ```
- **`/usr/local/bin/hermes-webui-ctl` is dead code — do not use it.** Two parallel controllers exist for the same server and don't talk to each other:
  - `/usr/local/bin/hermes-webui-ctl` checks `/tmp/hermes-webui.pid` and tries to launch `start.sh` (neither exists; the real PID is in `/root/.hermes/webui.pid` and the real launcher is `ctl.sh`). Its `status` will ALWAYS say "NOT running" even when the webui is up, and its `start` always fails silently. **If you find a snippet in old notes/cron entries referencing it, replace with `bash /root/hermes-webui/ctl.sh`.**

### crond itself can die silently in PRoot

The system cron daemon (`crond`) is not safe in Termux+PRoot. It can be killed by the container/runtime without leaving anything in the logs, leaving every crontab line — including your webui watchdog — silently unfired. Symptom: webui has been down for hours, restart attempts also missing, no obvious cause.

**First diagnostic whenever webui is unexpectedly down:**

```bash
pgrep -x cron || service cron start
```

If `pgrep -x cron` returns nothing, crond itself is the problem (not the webui). `service cron start` recovers it.

**Defensive crontab pattern: have cron watch itself.** Add this to your user crontab (`crontab -e`) on any PRoot box:

```cron
# Make sure crond itself is alive every 15 min (defensive — Termux+PRoot sometimes
# kills crond silently after the container idles)
*/15 * * * * pgrep -x cron >/dev/null || service cron start >> /root/.hermes/webui-cron.log 2>&1
```

This converts crond going-missing from a silent multi-hour outage into a self-healing 15-minute blip.

### Minimal working crontab (Termux+PRoot, user crontab via `crontab -`)

```cron
SHELL=/bin/bash
PATH=/root/.hermes/scripts:/usr/local/bin:/usr/bin:/bin
WEBUI=/root/hermes-webui

# 1. Start webui on boot/reboot
@reboot cd $WEBUI && bash ctl.sh start >> /root/.hermes/webui-cron.log 2>&1

# 2. Watchdog: every 5 min, restart if /health is unreachable.
#    Test the port directly with curl — DO NOT pipe `hermes-webui-ctl status`
#    through grep (that script is dead code, see pitfalls above).
*/5 * * * * cd $WEBUI && (curl -fsS --max-time 3 http://127.0.0.1:8787/health >/dev/null 2>&1 || (echo "[$(date -Is)] WebUI DOWN — restarting" >> /root/.hermes/webui-cron.log && bash ctl.sh restart >> /root/.hermes/webui-cron.log 2>&1))

# 3. Make sure crond itself is alive every 15 min
*/15 * * * * pgrep -x cron >/dev/null || service cron start >> /root/.hermes/webui-cron.log 2>&1
```

The `bash ctl.sh restart` is preferred over `start` because if the previous server is in a half-dead state holding the port, `restart` will stop-then-start and avoid `Address already in use`.

## Post-Update Restart Fix (local patch)

The webui can die silently after clicking "Update Now" on Termux+PRoot.
This is caused by Android's `cpuset:/top-app` cgroup killing the new
Python process within ~10s of the old one exiting during the
`os.execv()` restart. **A local patch has been applied** to
`api/updates.py` `_schedule_restart()` — replaces `os.execv()` with a
detached spawn via `os.fork()` + `os.setsid()` + `os.execvp()` into
`ctl.sh start`.

### Local patch status

The maintainer rejected the equivalent PR (#3407) for lacking a
platform gate. **This is a permanent local patch; it will be
overwritten on every `git pull`.** However, re-application is now
**fully automated** — no manual steps needed after an update.

### Auto-reapply pipeline (triple coverage)

The patch survives git pulls through three layers:

1. **Git post-merge hook** (`/root/hermes-webui/.git/hooks/post-merge`) — fires after every `git pull`, runs the reapply script
2. **`_reapply_local_fix()` in `api/updates.py`** — called from both `apply_update()` and `apply_force_update()` after stash-pop and after fetch+reset, so both update paths re-apply the fix before `_schedule_restart()` fires
3. **Shell script** (`~/.hermes/scripts/reapply-webui-fix.sh`) — standalone fallback, can be run manually anytime

The reapply script uses the same `patch` mechanism from Section C
of `hermes-webui-self-update-bug` but runs automatically via
post-merge hook + in-process call.

Note: there's also a **`fork` remote** configured pointing to
`PatrickNoFilter/hermes-webui` (the PR #3407 author's fork) with
an access token. The master branch tracks `origin` (official
nesquena repo), but the fork remote exists for reference.

### How the restart fix works

1. `os.fork()` creates a child with its own PID in the cgroup hierarchy — Android's cgroup killer can't reach it
2. `os.setsid()` detaches from parent's session — no SIGHUP on parent exit
3. `os.execvp()` into `ctl.sh start` (same path watchdog uses, provably survives cgroup transition)
4. Parent calls `os._exit(0)` immediately — child is independent

### When watchdog alone isn't enough

The 1-min watchdog catches post-update deaths within ~60s. With the
fork patch, the restart completes in ~3-5s. Both should be active
for resilience: if the patch gets clobbered by a git pull, the
watchdog still recovers within a minute.

## Key Files

| File | Purpose |
|------|---------|
| `/root/hermes-webui/server.py` | Entry point |
| `/root/hermes-webui/api/config.py` | Agent discovery, env var loading, Python detection |
| `/root/hermes-webui/bootstrap.py` | Bootstrap entry (used by ctl.sh) |
| `/root/hermes-webui/ctl.sh` | Daemon lifecycle: start/stop/restart/status |
| `/root/hermes-webui/start-webui.sh` | Wrapper script with correct env vars |
| `/root/hermes-webui/watchdog-loop.sh` | Bash loop watchdog (for PRoot / no-gateway envs) |
| `/root/hermes-webui/.env` | Environment variables (sourced by ctl.sh) |
| `/tmp/hermes-webui.log` | Server log (stdout+stderr) |
| `/tmp/hermes-webui-watchdog.log` | Watchdog loop log |
| `/root/.hermes/scripts/hermes-webui-watchdog.sh` | Cron watchdog script (no_agent: true, for gateway-based envs) |
| `/root/.hermes/webui` | State directory (PID file, ctl state) |
| `/usr/local/lib/hermes-agent/venv/bin/python` | Hermes agent's venv Python (has all deps) |

## See also

- `references/webui-down-recovery.md` — Step-by-step runbook for "webui is down" diagnosis, with a decision tree and the crond/execv-wedge/port-in-use quick checks.
- `hermes-webui-self-update-bug` skill, `references/diag-shim.md` — the signal-trap shim is the canonical "why did it die?" tool. It supersedes the dmesg + manual `try/except` workaround for the silent-death-after-restart bug.
