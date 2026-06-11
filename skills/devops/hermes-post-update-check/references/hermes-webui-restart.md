# Hermes WebUI — Post-Update Restart & Troubleshooting

## Why it breaks

`hermes update` replaces the running Python process. The webui (started via `ctl.sh start`) is a child of that process tree and gets killed. The PID in `~/.hermes/webui.pid` becomes stale.

Additionally, the webui's self-update mechanism (`/api/updates/apply`) calls `os.execv()` to restart itself after a git pull. In PRoot environments (non-standard chroot-like setups), `os.execv()` can fail silently — the process dies but the new process never starts. Always use `ctl.sh restart` instead of relying on the webui's self-restart.

## Quick start / restart

```bash
cd ~/hermes-webui && bash ctl.sh start     # first time
cd ~/hermes-webui && bash ctl.sh restart   # after running
```

## Common failure: server not running at all (port 8787 empty)

**Symptoms:**
- `ss -tlnp | grep 8787` returns nothing
- `curl http://localhost:8787/health` fails
- `cat ~/.hermes/webui.pid` has a stale/nonexistent PID

**Check process:**
```bash
# See if a webui process exists at all
ps aux | grep -E "bootstrap|server\.py|webui" | grep -v grep
# Check the log for clues
tail -20 ~/.hermes/webui.log
```

**Causes & fixes:**

| Cause | Fix |
|-------|-----|
| Server never started | `bash ctl.sh start` |
| Previous process died silently | `bash ctl.sh restart` |
| Stale PID file | `bash ctl.sh stop && bash ctl.sh start` |
| Missing dependencies (system Python) | See "Missing dependencies" below |

### Missing dependencies

When running outside the Hermes agent venv (system Python), install these:

```bash
apt install -y python3-yaml python3-cryptography
```

The Hermes agent venv at `/usr/local/lib/hermes-agent/venv/bin/python3` already has all deps — point `HERMES_WEBUI_PYTHON` there to avoid this.

## Common failure: Python environment conflict

**Error:**
```
[bootstrap] ERROR: Python environment cannot import both WebUI dependencies
and Hermes Agent. Set HERMES_WEBUI_PYTHON to the Hermes Agent venv Python
or install the WebUI requirements into that environment.
```

**Cause:** Missing or incorrect `.env` file. Bootstrap tries to create a separate venv for webui deps, which conflicts with the Hermes agent venv that already has them.

**Fix:** Ensure `.env` exists with the correct paths:

```bash
cat > ~/hermes-webui/.env <<'EOF'
HERMES_WEBUI_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python3
HERMES_WEBUI_HOST=127.0.0.1
HERMES_WEBUI_PORT=8787
HERMES_HOME=/root/.hermes
HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent
EOF
```

Then restart: `cd ~/hermes-webui && bash ctl.sh restart`

### `.env` field reference

| Variable | Purpose | Typical value |
|----------|---------|---------------|
| `HERMES_WEBUI_PYTHON` | Python interpreter to use | `/usr/local/lib/hermes-agent/venv/bin/python3` |
| `HERMES_WEBUI_HOST` | Bind address | `127.0.0.1` (safe) or `0.0.0.0` (network) |
| `HERMES_WEBUI_PORT` | Port to serve on | `8787` |
| `HERMES_HOME` | Hermes state directory for config/sessions/models | `/root/.hermes` |
| `HERMES_WEBUI_AGENT_DIR` | Hermes agent code directory (enables agent features) | `/usr/local/lib/hermes-agent` |
| `HERMES_WEBUI_PASSWORD` | Password to protect non-loopback access | *(set when binding to 0.0.0.0)* |

**Note:** `HERMES_HOME` points to the **state** directory (config/sessions/models). `HERMES_WEBUI_AGENT_DIR` points to the **code** directory (the agent repo). Both are needed for full agent features. Without `HERMES_WEBUI_AGENT_DIR`, the webui starts but shows `agent dir: NOT FOUND [XX]`.

## Post-update browser hang (SSE reconnect loop)

After updating the webui, the browser may hang/freeze. This is caused by cached service workers and the browser's EventSource reconnect loop (issue #3103, fixed in v0.51.165+).

**Symptoms:** UI freezes, constant re-renders, scroll-to-bottom on every reconnect.

**Fix:** Clear the browser's service worker cache:
1. DevTools (F12) → Application → Service Workers → Unregister
2. Hard reload: `Ctrl+Shift+R` (or `Cmd+Shift+R` on Mac)

Or: DevTools → Application → Storage → Clear site data → Reload.

## Verify

```bash
curl -s http://127.0.0.1:8787/health
# Should return {"status":"ok",...}

# Check process is alive:
kill -0 $(cat ~/.hermes/webui.pid) && echo "alive" || echo "dead"

# Check version (should be v0.51.165+ to have #3103 fix):
cd ~/hermes-webui && git describe --tags --always
```

## Key files

| File | Purpose |
|------|---------|
| `~/hermes-webui/.env` | Config (Python path, host, port, password, HERMES_HOME) |
| `~/hermes-webui/ctl.sh` | Start/stop/restart/status daemon manager |
| `~/hermes-webui/start.sh` | Direct foreground start (sources .env) |
| `~/.hermes/webui.pid` | PID of running daemon |
| `~/.hermes/webui.log` | Request log + bootstrap errors |
| `~/.hermes/webui.ctl.env` | Captured env vars from last start |

## Security note

Binding to `0.0.0.0` without a password exposes the filesystem and agent to the network. Always set `HERMES_WEBUI_PASSWORD` in `.env` when using non-loopback binds.
