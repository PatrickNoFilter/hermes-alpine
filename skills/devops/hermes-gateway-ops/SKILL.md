---
name: hermes-gateway-ops
description: "Hermes Gateway lifecycle: platform setup, startup, troubleshooting, and persistence. Covers Telegram, Discord, Slack, WhatsApp, Signal, Matrix, and other messaging platform adapters."
version: 1.0.0
author: Hermes Agent
tags: [hermes, gateway, telegram, discord, messaging, platform, troubleshooting, setup]
hermes:
  tags: [hermes, gateway, troubleshooting, devops]
---

# Hermes Gateway Operations

Gateway lifecycle management — diagnosing failures, configuring platforms, and ensuring persistence.

## Diagnostic Flow

When user reports gateway issues, follow this sequence:

1. **Check status:** `hermes gateway status`
2. **Read logs:** `tail -50 ~/.hermes/logs/gateway.log`
3. **Check platforms config:** `grep -A5 'platforms:' ~/.hermes/config.yaml`
4. **Check .env tokens:** `grep -E 'TOKEN|_KEY' ~/.hermes/.env | grep -v '^#'`

## Gateway Exit Code 0 — No Platforms Configured

The most common "gateway exited" cause. `platforms: {}` in config.yaml means nothing to run.

```
# Symptoms:
#   error: gateway exited (0)
#   Gateway starts then immediately stops

# Fix:
hermes config set platforms.<name>.enabled true   # e.g. platforms.telegram.enabled
hermes gateway run
```

Exit code 0 is NOT an error — it means the gateway started, found no platforms, and exited gracefully.

## Platform Setup (Telegram as canonical example)

1. **Create bot** — message `@botFather` → `/newbot` → get token
2. **Set token** — `TELEGRAM_BOT_TOKEN=<token>` in `~/.hermes/.env` (uncomment existing line)
3. **Set allowed users** — `TELEGRAM_ALLOWED_USERS=<user_id>` in `.env`
   - Get ID via `@userinfobot` on Telegram
   - Without this, ALL users are denied access (warning in logs)
4. **Enable platform** — `hermes config set platforms.telegram.enabled true`
5. **Start gateway** — `hermes gateway run`

Other platforms follow the same pattern: token in `.env`, enable in config, start.

## Modifying .env Safely

**DO NOT** use `sed` for uncommenting or editing `.env` lines — it's fragile with variable names and can silently corrupt them.

**Preferred approaches (in order):**
1. `hermes config set KEY VALUE` — for config.yaml settings
2. Direct line replacement with exact variable name in sed: `sed -i 's|^# VAR=.*|VAR=value|' ~/.hermes/.env`
3. Python `open()` + `write()` — for complex multi-line edits

**`execute_code` cannot access `.env` or `config.yaml`** — these are protected credential files. Use `terminal()` instead.

## Persistence Without systemd

On hosts without systemd (containers, WSL without systemd, PRoot/Termux):

| Method | Start | Survives logout? | Auto-restart? |
|--------|-------|-------------------|---------------|
| `hermes gateway run` (foreground) | Terminal | No | No |
| `tmux new-session -d -s gw 'hermes gateway run'` | Terminal | Yes (if tmux stays) | No |
| `nohup hermes gateway run &` | Terminal | No (SIGHUP kills) | No |
| cron watchdog + nohup | Cron | Yes | Yes |
| systemd service | Boot | Yes | Yes |

### PRoot / Termux environments

PRoot (Android/Termux) does **not** run systemd as PID 1. `systemctl --user` fails with:
```
Failed to connect to user scope bus via local transport:
$DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined
```

No `$XDG_RUNTIME_DIR` means no user bus, no systemd user services, no `loginctl enable-linger`. The fix is **cron + nohup + watchdog**:

```bash
# 1. Install cron (if not present)
apt-get install -y cron
cron   # PRoot doesn't auto-start cron — run manually

# 2. Create a service controller script (see references/service-controller-template.sh)
# Installs to /usr/local/bin/<service>-ctl

# 3. Set up crontab
crontab -e
# Add:
@reboot /usr/local/bin/hermes-gw-ctl start >> /var/log/hermes-gw-cron.log 2>&1
*/5 * * * * /usr/local/bin/hermes-gw-ctl status 2>&1 | grep -q 'NOT running' && /usr/local/bin/hermes-gw-ctl start >> /var/log/hermes-gw-cron.log 2>&1
```

The watchdog cron entry checks every 5 minutes and restarts if the health endpoint is down. This survives `dpkg` updates, process crashes, and reboots.

**Verify it's working:**
```bash
hermes-gw-ctl status     # should show "running"
curl -fsS http://127.0.0.1:8787/health   # or whatever port
```

### Real Linux (systemd available)

```bash
sudo loginctl enable-linger $USER
hermes gateway install   # creates systemd user service
systemctl --user enable --now hermes-gateway.service
```

### tmux (quick and dirty)

```bash
tmux new-session -d -s hermes-gw 'hermes gateway run'
tmux attach -t hermes-gw       # reattach
tmux kill-session -t hermes-gw # kill
```

## Common Log Patterns

| Log message | Meaning |
|-------------|---------|
| `gateway exited (0)` | No platforms configured — see above |
| `No user allowlists configured` | No `TELEGRAM_ALLOWED_USERS` or `GATEWAY_ALLOW_ALL_USERS` |
| `Connecting to telegram...` | Normal startup sequence |
| `Connected to Telegram (polling mode)` | Telegram adapter is live |
| `Received SIGTERM` | Graceful shutdown (manual kill or service stop) |

## See Also

- `hermes-agent` skill for full CLI reference and config options
- Platform-specific docs: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/
