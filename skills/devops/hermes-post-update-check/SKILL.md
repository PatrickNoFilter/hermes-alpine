---
name: hermes-post-update-check
description: "Post-update health check: verify all Hermes components, audit external tools/plugins/MCP servers, and update what's outdated."
tags: [hermes, update, health-check, mcp, plugins, maintenance]
---

# Hermes Post-Update Health Check

Run this after `hermes update` or when the user says "check all functions" / "verify everything" after an update.

## Trigger

- User says "check all functions", "verify everything", "health check" after updating
- User says "update hermes, check all tools"
- After running `hermes update` manually

## Workflow

### Phase 0: Hermes WebUI (if installed)

Check if the webui is alive:
```bash
curl -s http://127.0.0.1:8787/health
```
- **200 OK** → webui is running, verify watchdog cron is active
- **Connection refused** → webui is down. Start or troubleshoot:
  ```bash
  cd ~/hermes-webui && bash ctl.sh start     # first start
  cd ~/hermes-webui && bash ctl.sh restart   # after update
  ```
  See `references/hermes-webui-restart.md` → "Common failure: server not running" for diagnosis.

`hermes update` kills the running webui process. Restart it:

```bash
cd ~/hermes-webui && bash ctl.sh restart
```

**After restarting, verify the watchdog cron is active** — otherwise the webui will die again on the next update:

```bash
hermes cron list | grep -q webui && echo "watchdog active" || echo "NO WATCHDOG — see references/watchdog-setup.md"
```
See `references/watchdog-setup.md` to create or re-create the watchdog if missing.

If bootstrap fails with `Python environment cannot import both WebUI dependencies and Hermes Agent`, the `.env` is missing or wrong. Fix:

```bash
cat > ~/hermes-webui/.env <<'EOF'
HERMES_WEBUI_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python3
HERMES_WEBUI_HOST=0.0.0.0
HERMES_WEBUI_PORT=8787
HERMES_HOME=/root/.hermes
EOF
cd ~/hermes-webui && bash ctl.sh restart
```

Verify: `curl -s http://127.0.0.1:8787/health`

See `references/hermes-webui-restart.md` for full troubleshooting.

### Phase 1: Core System (run in parallel)

```bash
hermes --version                    # Version + up-to-date status
hermes tools list                   # All toolsets + enabled/disabled
hermes config check                 # Config version + API key status
hermes sessions stats               # Session DB size + message count
hermes cron list                    # Scheduled jobs
hermes memory status                # Memory provider status
hermes status --all                 # Full status overview
```

Note: `hermes doctor` often times out (30s+). Skip it — `hermes status --all` covers the same ground faster.

### Phase 2: MCP Servers

```bash
hermes mcp list                     # Server status table
```

Verify each server shows `✓ enabled`. Common servers:
- `context-mode` — auto-updates via npx each run
- `agentmemory` — auto-updates via npx each run
- `codegraph` — installed via npm globally, needs manual update

### Phase 3: External Components Audit

**Step 1 — Find externals:**

```bash
# External plugins (non-builtin)
ls ~/.hermes/plugins/
cat ~/.hermes/plugins/*/plugin.yaml 2>/dev/null

# External skills (non-builtin)
hermes skills list | grep -v builtin

# MCP servers from config
cat ~/.hermes/config.yaml | grep -A 20 'mcp_servers:'
```

**Step 2 — Check each external for updates:**

| Component | How to check | How to update |
|---|---|---|
| npm MCP servers (context-mode, agentmemory) | Auto-latest via npx | No action needed (auto-update) |
| npm global packages (codegraph) | `npm -g ls <pkg>` + `npm view <pkg> version` | `npm -g install <pkg>@latest` |
| Standalone binaries (rtk) | Check GitHub releases: `curl -s https://api.github.com/repos/<org>/<repo>/releases/latest` | Re-download binary |
| Local plugins | Check `plugin.yaml` version | Manual update from source |
| Local skills | Check SKILL.md content | Manual update |

**Step 3 — Update:**

Use the unified update script (covers npm + pip + RTK in one pass):

```bash
bash ~/.hermes/scripts/update-external.sh
```

For individual package updates (debugging specific failures), see the companion skill `update-hermes-external` which documents update commands per package manager.

### Phase 4: Report

Present a table with columns: Component | Before | After | Status.

Group into: ✅ Updated, ✅ Already Latest, ℹ️ Local/Custom (no updates).

## Pitfalls

### Pre-update: `hermes update` itself fails

- **PRoot/UV hardlink — `hermes update` fails with `Operation not permitted (os error 1)`** — the uv package manager tries to hardlink from its build cache, which Termux PRoot doesn't support. Instead of relying on the built-in `hermes update` command's pip step, re-run the install manually after the git pull phase completes:

  1. Let `hermes update` fail (the git pull succeeds; only the pip install step fails).
  2. Clear the stale uv cache: `rm -rf /root/.cache/uv/builds-v0`
  3. Re-run the install: `cd /usr/local/lib/hermes-agent && UV_LINK_MODE=copy VIRTUAL_ENV=/usr/local/lib/hermes-agent/venv uv pip install -e .`
  4. Run `hermes config migrate` if config version changed.
  5. Proceed with the normal post-update check phases below.

  The key env vars are `UV_LINK_MODE=copy` (forces copy instead of hardlink) and `VIRTUAL_ENV=/usr/local/lib/hermes-agent/venv` (points uv to the Hermes venv).

- **`hermes doctor` times out** — use `hermes status --all` instead
- **npm ENOTEMPTY error** on global update — delete the stale `.codegraph-*` temp dir first, then retry
- **npx-based MCP servers** always get latest — don't waste time checking their versions manually
- **rtk** is a standalone Rust binary installed to `~/.local/bin/rtk` — it has no self-update command, check GitHub releases
- **codegraph** symlink points into `~/.hermes/node/lib/` — the npm global prefix is non-standard, don't use system npm paths
- **hermes-webui dies on `hermes update`** — the update kills the running process; always restart with `ctl.sh restart` after updating. If bootstrap fails with Python env conflict, create `.env` with `HERMES_WEBUI_PYTHON` pointing to the Hermes agent venv (`/usr/local/lib/hermes-agent/venv/bin/python3`) and `HERMES_HOME=/root/.hermes` for agent features
- **hermes-webui hangs after update** — browser caches old service worker causing SSE reconnect loop (#3103). User must clear service worker in DevTools → Application → Service Workers → Unregister, then hard reload
- **hermes-webui self-restart fails in PRoot** — the webui's `/api/updates/apply` calls `os.execv()` which silently fails in PRoot environments. Always use `ctl.sh restart` instead of relying on the webui's self-update restart mechanism
- **Restart is not enough — set up a watchdog cron** — just restarting the webui after an update means it dies again on the next update. Install a `no_agent=true` cron job with a bash script that checks port 8787 every 5 minutes and auto-restarts. See `references/watchdog-setup.md`.
- **Watchdog script needs retry logic** — the hermes-webui server can take >3s (up to 20s) to bind after `ctl.sh start`. A single `sleep 3; curl` check will falsely report failure. Use a loop: try every 2s for up to 20s.
- **`cronjob` with agent-based (no_agent=false) recurring jobs may not recur** — the `repeat: "once"` field can prevent proper recurring execution even with a recurring schedule like `5m`. Use `no_agent=true` with a self-contained bash script for watchdogs; the script **IS** the job and recurs reliably. Agent-based cron is fine for one-shot or summary tasks but not for service supervision.

## Key Paths

| Component | Path |
|---|---|
| Config | `~/.hermes/config.yaml` |
| Plugins | `~/.hermes/plugins/` |
| Skills | `~/.hermes/skills/` |
| MCP config | `~/.hermes/config.yaml` → `mcp_servers:` |
| npm global (hermes) | `~/.hermes/node/lib/node_modules/` |
| rtk binary | `~/.local/bin/rtk` |
| hermes-webui repo | `~/hermes-webui/` |
| hermes-webui .env | `~/hermes-webui/.env` |
| hermes-webui PID file | `~/.hermes/webui.pid` |
| hermes-webui log | `~/.hermes/webui.log` |
