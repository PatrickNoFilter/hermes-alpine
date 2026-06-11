# Hermes WebUI / Dashboard Reference

## Two Distinct Web UIs

### 1. Built-in Dashboard (shipped with Hermes Agent)

**Location:** `/usr/local/lib/hermes-agent/web/`

**Tech Stack:**
- Frontend: Node.js + TypeScript + Vite (React)
- Backend: Python (part of Hermes Agent)
- Dependencies: `package.json` + `requirements.txt`

**Start Command:**
```shell
hermes dashboard
# Options:
#   --port PORT      Port (default 9119)
#   --host HOST      Host (default 127.0.0.1)
#   --tui            Embed chat terminal via WebSocket
#   --insecure       Bind to 0.0.0.0 (DANGEROUS)
#   --skip-build     Serve existing dist/ without rebuild
#   --stop           Stop all running dashboards
#   --status         List running dashboards
```

**Features:**
- Config management (model, provider, API keys)
- Session browsing and management
- Settings and preferences
- Light/dark theme support

**Build Status:**
- `node_modules/` present (npm dependencies installed)
- No `dist/` folder (running in dev mode or needs `npm run build`)

### 2. Separate Project (nesquena/hermes-webui)

**Repository:** https://github.com/nesquena/hermes-webui

**Tech Stack:**
- Backend: Python (server.py)
- Frontend: Vanilla JavaScript (no framework, no build step)
- Deployment: Docker or direct Python

**Start Commands:**
```shell
# Docker (recommended)
docker compose up -d
# OR
docker pull ghcr.io/nesquena/hermes-webui:latest
docker run -d -p 127.0.0.1:8787:8787 ghcr.io/nesquena/hermes-webui:latest

# Local
pip install -r requirements.txt
python server.py
```

**Features:**
- Full CLI parity (everything from terminal works in UI)
- Three-panel layout (sessions, chat, workspace)
- Dark/light themes
- Workspace file browser with inline preview
- SSH tunnel access support

**Key Differences from Built-in:**
| Aspect | Built-in Dashboard | nesquena/hermes-webui |
|--------|-------------------|----------------------|
| Tech | Node.js/TypeScript | Python/Vanilla JS |
| Features | Config, sessions | Full CLI parity |
| Deployment | `hermes dashboard` | Docker or Python |
| Memory | ~330MB native | ~1080MB Docker |

## Common Issues

### Dashboard won't start
- Check if port is in use: `lsof -i :9119`
- Verify Node.js installed: `node --version`
- Check dependencies: `cd /usr/local/lib/hermes-agent/web && npm install`

### Dashboard accessible but features missing
- Built-in dashboard has limited features vs nesquena/hermes-webui
- For full experience, install the separate project

### Docker issues (nesquena/hermes-webui)
- Docker not installed: `curl -fsSL https://get.docker.com | sh`
- Permission denied: `sudo usermod -aG docker $USER` (logout/login)
- Port conflict: use `--port` flag or stop other services

## Development

### Building the built-in dashboard
```shell
cd /usr/local/lib/hermes-agent/web
npm install          # Install dependencies
npm run build        # Build for production
npm run dev          # Start dev server
```

### Contributing to nesquena/hermes-webui
```shell
git clone https://github.com/nesquena/hermes-webui
cd hermes-webui
pip install -r requirements.txt
python server.py     # Start development server
```
