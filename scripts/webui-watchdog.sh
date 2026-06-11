#!/usr/bin/env bash
# Silent watchdog for hermes-webui on Termux+PRoot
# Script for cronjob with no_agent=True — produces output only on restart

PORT=8787
CTL="/root/hermes-webui/ctl.sh"
LOG="/root/.hermes/webui.log"

# Check if port is responding
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
  # Check if process exists but port is dead (stale PID)
  if ! pgrep -f "bootstrap.py.*$PORT" > /dev/null 2>&1; then
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
