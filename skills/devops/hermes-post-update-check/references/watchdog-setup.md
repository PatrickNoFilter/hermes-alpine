# Hermes WebUI Watchdog — Cron-Based Auto-Recovery

## Why

`hermes update` kills the running webui process. Without a watchdog, the user must manually restart every time. A cron-based watchdog with `no_agent=true` checks port 8787 every 5 minutes and auto-restarts if down.

## The Reliable Pattern: `no_agent=true` + Bash Script

The **agent-based** cron (default, `no_agent=false`) uses an LLM call every tick and may have recurring-execution quirks with `repeat: "once"`. The **script-based** cron (`no_agent=true`) runs the script directly — no LLM cost, no scheduling quirks, silent when healthy.

### 1. Create the watchdog script

Save as `~/.hermes/scripts/hermes-webui-watchdog.sh`:

```bash
#!/usr/bin/env bash
set -e

HOST="127.0.0.1"
PORT="8787"
WEBUI_DIR="/root/hermes-webui"
PYTHON="/usr/local/lib/hermes-agent/venv/bin/python3"

# Check if port is listening
if ! curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    cd "$WEBUI_DIR"
    HERMES_WEBUI_PYTHON="$PYTHON" HERMES_WEBUI_HOST="$HOST" bash ctl.sh start >/dev/null 2>&1
    # Retry up to 10 times (20s total) — server can take a while to bind
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        if curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
            echo "[watchdog] hermes-webui was down — restarted successfully (PID $(cat /root/.hermes/webui.pid 2>/dev/null))"
            exit 0
        fi
    done
    echo "[watchdog] hermes-webui was down — restart FAILED after 20s"
fi
# else: silent — nothing to report (watchdog pattern)
```

Make executable: `chmod +x ~/.hermes/scripts/hermes-webui-watchdog.sh`

### 2. Create the cron job

```bash
cronjob action=create \
  name="hermes-webui watchdog" \
  schedule="5m" \
  no_agent=true \
  script="hermes-webui-watchdog.sh"
```

This creates a cron job that runs the bash script every 5 minutes with no LLM involvement. When the webui is healthy, the script outputs nothing (silent). When it restarts, it sends one notification.

### 3. Verify

```bash
# Test manually (server healthy → silent, exit 0)
bash ~/.hermes/scripts/hermes-webui-watchdog.sh

# Check cron is active
hermes cron list | grep webui
```

## How the Retry Loop Works

The hermes-webui server (Python `http.server.ThreadingHTTPServer`) can take 3–20 seconds to bind after `ctl.sh start`. A naive `sleep 3; curl ...` check will falsely report failure. The loop:

- Tries `curl` every 2 seconds
- Exits with success on the first `HTTP 200`
- After 10 attempts (20s total), reports failure

This covers the normal startup variance without excessive latency.

## Design Rationale

| Aspect | Choice | Why |
|--------|--------|-----|
| `no_agent=true` | Yes | No LLM cost, no token waste, reliable recurring execution |
| Script location | `~/.hermes/scripts/` | Standard Hermes script directory, auto-available to cron |
| Silent when healthy | Yes | Watchdog pattern — only report state changes |
| Retry loop | 10 × 2s | Server binding is unpredictable; single check false-fails |
| `set -e` | Yes | Fail fast on unexpected errors (curl, cd, missing files) |

## Removing the Watchdog

```bash
hermes cron list                     # find the job_id
cronjob action=remove job_id=<id>   # remove it
```
