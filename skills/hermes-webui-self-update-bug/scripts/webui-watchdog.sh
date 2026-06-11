#!/usr/bin/env bash
# Silent watchdog for hermes-webui on Termux+PRoot
# Designed for cronjob with no_agent=True — produces output only on restart
#
# Usage:
#   cronjob action=create name=webui-watchdog schedule="every 5m" \
#     no_agent=true script=webui-watchdog.sh
#
# Keeps quiet when healthy; only reports when it had to restart.

PORT=8787
CTL="/root/hermes-webui/ctl.sh"
LOG="/root/.hermes/webui.log"

# Check if port is responding
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
  # Check if process exists but port is dead (stale PID)
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
