#!/usr/bin/env bash
# Hermes WebUI watchdog — silent check & restart if down
set -e

HOST="127.0.0.1"
PORT="8787"
WEBUI_DIR="/root/hermes-webui"
PYTHON="/usr/local/lib/hermes-agent/venv/bin/python3"

# Check if port is listening
if ! curl -sf "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    # Try restart
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
# else: silent — nothing to report
