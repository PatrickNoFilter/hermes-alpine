---
name: external-project-setup
description: "Evaluate and set up external open-source projects (monorepos, multi-package apps) for local use."
tags:
  - setup
  - monorepo
  - npm
  - python
  - devops
---

# External Project Setup

Evaluate and bootstrap external open-source projects from clone to running locally. Covers multi-package monorepos, Next.js/Vite/Electron apps, and anything using npm workspaces.

## Triggers

- User asks to install, setup, clone, or run an external project
- User shares a GitHub repo and asks to try it
- User asks if a project can integrate with Hermes

## Workflow

1. **Evaluate first (REQUIRED)** — Always assess a repo before committing time to setup. Use the compatibility checklist in `references/compatibility-checklist.md`.

   Quick eval pattern (curl, not browser):
   ```bash
   # Metadata — stars, language, license, description
   curl -s https://api.github.com/repos/OWNER/REPO | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"★ {d['stargazers_count']:,} | {d.get('language','?')} | {d.get('license',{}).get('spdx_id','?')}\\\n{d.get('description','')}\")"

   # README — features, requirements, setup steps
   curl -s https://raw.githubusercontent.com/OWNER/REPO/main/README.md | head -100
   ```

   Key assessment dimensions (see checklist for full detail):
   - **ARM64 compatibility** — native binary? source-buildable? Pure Python/JS/Go?
   - **Resource footprint** — ML downloads? GPU required? RAM usage? (8GB, no GPU, PRoot)
   - **Budget** — Free/open-source? Paid API? Subscription?
   - **Overlap** — Duplicates existing Hermes skills/tools? Check skills list.
   - **Value gap** — What does it enable that we currently can't do?

   Report a clear verdict: **Worth it** / **Skip** / **Maybe later** with reasoning.

   Report capabilities and whether it can integrate with Hermes before investing in setup.

2. **Clone with submodules** — Always use `--recurse-submodules` if the README mentions submodules or monorepo packages.
3. **Install deps** — Run the project's setup/install command. If it hangs or times out, break it into steps: `npm install` first (with 5-10 min timeout), then build commands separately.
4. **Fix build issues** — See pitfalls below for common monorepo failures.
5. **Start the server** — Try the dev server. If it crashes, try alternative entry points (vite vs next vs electron).
6. **Report status** — Tell the user what is running, on what port, and what they need (API keys, etc.).

## Pitfalls

### 1. npm Workspace Hoisting — devDependencies invisible in subpackages

**Symptom:** `sh: 1: tailwindcss: not found` (or any CLI tool) during `npm run build` in a workspace subpackage, even though it is listed in that subpackage devDependencies.

**Root cause:** npm workspaces hoist shared dependencies to the root node_modules. But subpackage build scripts run from the subpackage directory and cannot always find binaries that live only at root level. The binary may not exist at root if no root-level package.json devDep references it.

**Fix:** Explicitly install the missing devDep in the affected subpackage:

```bash
cd <repo-root>/packages/<subpackage>
npm install --include=dev tailwindcss@3 postcss autoprefixer
```

Then re-run the full build from root. If build:packages fails on the third subpackage, fix each one sequentially. Each install may take 1-2 minutes.

### 2. Stale node_modules causing ENOTEMPTY

**Symptom:** `ENOTEMPTY: directory not empty, rename` during npm install, and `rm -rf node_modules` also hangs or fails.

**Fix:** Rename then delete:

```bash
mv node_modules node_modules_old
rm -rf node_modules_old
```

Or for subpackage node_modules:

```bash
find <path>/node_modules -depth -delete
```

If even that fails, just mv it away — npm will create fresh node_modules.

### 3. Vite not found despite being a devDependency

**Symptom:** `Cannot find package vite imported from .../vite.config.mjs` even after npm install.

**Root cause:** npm workspace hoisting may place vite in root node_modules, but the temp config file path cannot resolve it. Or hoisting skipped it entirely.

**Fix:** Try installing vite explicitly at root:

```bash
npm install --save-dev vite@5
```

If that still does not work, use `npx vite` which resolves from the local package store.

### 4. Next.js uv_interface_addresses crash in containers

**Symptom:** `NodeError [SystemError]: uv_interface_addresses returned Unknown system error 13` when running `next dev`.

**Context:** Happens in containers, PRoot environments, Android/Termux, or restricted environments where network interface enumeration is restricted.

**Workarounds (try in order):**

1. `npx next dev -H 0.0.0.0 -p 3000` — sometimes bypasses the issue
2. `NODE_ENV=development npx next dev -H 127.0.0.1 -p 3000` — avoids auto-detection
3. Try the Vite entry point instead: `npx vite --host 0.0.0.0 --port 3000`
4. Build and serve: `npx next build && npx next start -H 0.0.0.0 -p 3000`

If all fail, the project may need to run outside this environment. Report the specific error to the user.

### 5. Long npm install times in large monorepos

npm install in large monorepos with many workspace packages can take 5-7+ minutes. Always use background mode with notify_on_complete=true for npm install commands in monorepos. Do not poll or wait in short intervals.

## Quick assessment template

After cloning and before building, quickly assess the project:

```bash
# Check package.json scripts
cat package.json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  {k}: {v}') for k,v in d.get('scripts',{}).items()]"

# Check workspaces
cat package.json | python3 -c "import sys,json; d=json.load(sys.stdin); print('Workspaces:', d.get('workspaces','none'))"

# Check if submodules exist
git submodule status
```

## Python Projects

For Python-based external projects (CLIs, web UIs, servers) that do NOT use Node.js or Docker.

### Pre-checks

```bash
# What Python is available?
which python3 && python3 --version

# Is the system Python externally-managed (PEP 668)?
python3 -c "import sys; print('externally-managed' if hasattr(sys, 'EXTERNALLY_MANAGED') else 'system pip ok')"

# Look for an existing project venv to reuse
ls -la /usr/local/lib/*/venv/bin/python3 2>/dev/null
```

### Workflow: Fresh Install (Python, no Node/Docker)

Used when user says "install from GitHub, direct Python, no Node, no Docker":

1. **Kill old processes** — Check for leftover daemons on the target port:
   ```bash
   fuser -k <port>/tcp 2>/dev/null || true
   pkill -f "server.py|bootstrap.*<port>" 2>/dev/null || true
   ```
   Also remove stale PID files (`rm -f <project-dir>/*.pid`).

2. **Wipe old state** — Remove the old project directory AND any `.hermes/<component>` state dir:
   ```bash
   rm -rf /path/to/project ~/.hermes/<state-dir>
   ```

3. **Clone fresh** — Use the correct branch (check GitHub default, often `master`):
   ```bash
   git clone --depth 1 --branch <branch> <repo-url> /path/to/project
   ```

4. **Configure environment** — Create a `.env` file in the project root (read by startup scripts):
   ```
   HERMES_WEBUI_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python3
   HERMES_WEBUI_AGENT_DIR=/usr/local/lib/hermes-agent
   HERMES_WEBUI_HOST=127.0.0.1
   HERMES_WEBUI_PORT=<port>
   ```

   Key env vars for Hermes-integrated projects:
   - `HERMES_WEBUI_AGENT_DIR` — path to Hermes agent installation
   - `HERMES_WEBUI_PYTHON` — the Hermes venv Python (3.11.x, has all deps)
   - `HERMES_WEBUI_HOST=127.0.0.1` — bind to localhost only (no password needed)
   - `HERMES_WEBUI_PORT` — port to serve on

   **Pitfall:** `.env` is read by `start.sh`/`bootstrap.py` but NOT by `server.py` directly. If running `server.py` raw, export vars explicitly.

5. **Check Python interpreter** — Use the Hermes venv Python if the system Python is externally-managed:
   ```bash
   /usr/local/lib/hermes-agent/venv/bin/python3 -c "import yaml"  # verify deps available
   ```

6. **Start** — Use the project's daemon script if available:
   ```bash
   cd /path/to/project
   HERMES_WEBUI_PYTHON=/usr/local/lib/hermes-agent/venv/bin/python3 bash ctl.sh start
   ```

   **Pitfall:** Avoid raw `terminal(background=true)` with `server.py` directly — it often hangs (process sleeps, never binds). Use the project's own daemonization (`ctl.sh`, `start.sh`, etc.) instead.

7. **Verify** — Check port binding and health:
   ```bash
   sleep 3  # give the daemon time to bind
   ss -tlnp 2>/dev/null | grep <port>
   curl -s -o /dev/null -w "HTTP %{http_code}" http://127.0.0.1:<port>/health
   # or for the main page:
   curl -s http://127.0.0.1:<port>/ | head -5
   ```

8. **Check service status** (if project provides status command):
   ```bash
   cd /path/to/project && bash ctl.sh status
   ```

### Python-Specific Pitfalls

#### 1. System Python externally managed (PEP 668)

**Symptom:** `error: externally-managed-environment` when running `pip install` directly on system Python.

**Fix:** Use the Hermes agent venv Python instead:
```bash
/usr/local/lib/hermes-agent/venv/bin/python3 -m pip install <pkg>
```
Or set `HERMES_WEBUI_PYTHON` so the project's bootstrap picks the right interpreter.

#### 2. Port already in use from stale process

**Symptom:** `OSError: [Errno 98] Address already in use`; or `[ctl] Bound: ...` but port doesn't appear in `ss`.

**Root cause:** Old server process lingering from a prior session. The PID file may point to an already-dead process, while the old process still holds the port.

**Fix:** Thorough cleanup before restart:
```bash
fuser -k <port>/tcp 2>/dev/null
pkill -f "server.py" 2>/dev/null
pkill -f "bootstrap" 2>/dev/null
sleep 1
rm -f /root/.hermes/<state-dir>/*.pid /root/.hermes/<state-dir>/*.log
```

#### 3. Background process runner hangs with raw server.py

**Symptom:** Using `terminal(background=true)` to start `server.py` directly results in a sleeping process that never binds to the port.

**Root cause:** The Hermes background runner doesn't fully emulate the TTY/server semantics that threaded HTTP servers expect on this platform.

**Fix:** Always use the project's own daemonization script (`ctl.sh start`, `start.sh`, etc.) when available. These scripts handle fork/exec, PID files, and log redirection properly.

#### 4. Missing Python dependencies for optional features

**Symptom:** Warnings like `[!!] Warning: Hermes agent found but missing modules: {requests, httpx}` at startup.

**Impact:** Usually non-fatal — the server starts but certain plugins/features won't work. The server often attempts auto-install from `requirements.txt` as a fallback.

**Fix:** Pre-install known missing deps using the Hermes venv Python:
```bash
/usr/local/lib/hermes-agent/venv/bin/python3 -m pip install requests httpx aiohttp
```
