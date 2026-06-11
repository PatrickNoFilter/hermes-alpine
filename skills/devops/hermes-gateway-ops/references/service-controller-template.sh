#!/bin/bash
# Generic service controller for PRoot/Termux environments
# where systemd user services don't work.
#
# Usage: Copy this script, change the variables below, install to /usr/local/bin/
#
# Install:
#   cp references/service-controller-template.sh /usr/local/bin/myapp-ctl
#   chmod +x /usr/local/bin/myapp-ctl
#
# Crontab:
#   @reboot /usr/local/bin/myapp-ctl start >> /var/log/myapp-cron.log 2>&1
#   */5 * * * * /usr/local/bin/myapp-ctl status 2>&1 | grep -q 'NOT running' && /usr/local/bin/myapp-ctl start >> /var/log/myapp-cron.log 2>&1

# === CONFIGURE THESE ===
SERVICE_NAME="myapp"           # Display name
REPO_DIR="$HOME/myapp"         # App directory
START_CMD="bash start.sh --foreground"  # Command to start
HEALTH_URL="http://127.0.0.1:8080/health"  # Health check endpoint
HEALTH_TIMEOUT=2               # Seconds per health check attempt
HEALTH_RETRIES=30              # Max wait for startup
PIDFILE="/tmp/${SERVICE_NAME}.pid"
LOGFILE="$HOME/.logs/${SERVICE_NAME}.log"
PORT=8080
# === END CONFIGURE ===

start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "$SERVICE_NAME already running (PID $(cat "$PIDFILE"))"
        return 0
    fi

    # Check if port is already in use
    PID=$(fuser $PORT/tcp 2>/dev/null | awk '{print $1}')
    if [ -n "$PID" ]; then
        echo "Port $PORT already in use (PID $PID)"
        return 1
    fi

    echo "Starting $SERVICE_NAME..."
    mkdir -p "$(dirname "$LOGFILE")"
    cd "$REPO_DIR"

    nohup $START_CMD >> "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"

    # Wait for health endpoint
    for i in $(seq 1 $HEALTH_RETRIES); do
        if curl -fsS --max-time $HEALTH_TIMEOUT "$HEALTH_URL" >/dev/null 2>&1; then
            echo "$SERVICE_NAME started (PID $(cat "$PIDFILE"))"
            return 0
        fi
        sleep 1
    done

    echo "WARNING: Server may not be ready. Check $LOGFILE"
    return 0
}

stop() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Stopping $SERVICE_NAME (PID $PID)..."
            kill "$PID"
            sleep 2
            kill -0 "$PID" 2>/dev/null && kill -9 "$PID"
            echo "Stopped."
        else
            echo "Process $PID not running (stale PID file)"
        fi
        rm -f "$PIDFILE"
    else
        echo "No PID file. Killing anything on port $PORT..."
        PID=$(fuser $PORT/tcp 2>/dev/null | awk '{print $1}')
        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null
            echo "Killed PID $PID"
        fi
    fi
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "$SERVICE_NAME is running (PID $(cat "$PIDFILE"))"
        curl -fsS --max-time 2 "$HEALTH_URL" 2>/dev/null && echo
    else
        echo "$SERVICE_NAME is NOT running"
        PID=$(fuser $PORT/tcp 2>/dev/null | awk '{print $1}')
        [ -n "$PID" ] && echo "  (something on port $PORT: PID $PID)"
    fi
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    *)
        echo "Usage: $SERVICE_NAME-ctl {start|stop|restart|status}"
        exit 1
        ;;
esac
