# Hermes Web UI (nesquena/hermes-webui) in Termux PRoot

## Overview

The [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) project provides a full web UI for Hermes Agent with CLI parity, workspace browser, and session management. It runs on port 8787 by default.

**Do not confuse with the built-in dashboard** (`hermes dashboard`, port 9119) — they are separate projects with different feature sets.

## Location

Installed at `/root/hermes-webui/` (git clone).

## Starting the Web UI

### With full Hermes agent integration

```bash
cd /root/hermes-webui
HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent \
  HERMES_WEBUI_HOST=0.0.0.0 \
  python3 server.py
```

### Env vars explained

| Env var | Value | Why |
|---------|-------|-----|
| `HERMES_WEBUI_AGENT_DIR` | `/usr/local/lib/hermes-agent` | Points to Hermes Agent source so the Web UI can read sessions, config, and invoke agent features |
| `HERMES_WEBUI_HOST` | `0.0.0.0` (LAN) or `127.0.0.1` (local-only) | `0.0.0.0` binds to all interfaces — required for access from Android host browser (127.0.0.1 is PRoot-only). `127.0.0.1` restricts to local/PRoot — safer, no auth needed. |

### Without env vars (fallback)

The server starts but shows "Could not find the Hermes agent directory" — agent features (session browsing, config editing) will be limited but the UI still serves static pages.

## Access

From Android browser on same WiFi: `http://<device-lan-ip>:8787`

Find the LAN IP:
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

## Dependencies

Minimal: `pip install pyyaml cffi cryptography` (already installed via `requirements.txt`).

## Troubleshooting

- **Can't reach from Android browser** → server bound to 127.0.0.1, restart with `HERMES_WEBUI_HOST=0.0.0.0`
- **Agent features not working** → set `HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent`
- **Port conflict** → set `HERMES_WEBUI_PORT=8788` (or any free port)
