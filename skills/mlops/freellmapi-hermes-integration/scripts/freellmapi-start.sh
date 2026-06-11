#!/usr/bin/env bash
# FreeLLMAPI auto-start + health checker
set -e

SERVER_DIR="$HOME/freellmapi/server"
PORT=3001
LOG="/tmp/freellmapi.log"

# Check if already running
if curl -sf --connect-timeout 2 "http://localhost:$PORT/api/ping" > /dev/null 2>&1; then
    exit 0
fi

# Start it
cd "$SERVER_DIR"
nohup npx tsx src/index.ts > "$LOG" 2>&1 &
echo "freellmapi started (pid $!)" >> "$LOG"
