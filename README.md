# hermes-alpine

Full Hermes Agent ecosystem — hermes-agent code, skills, plugins, and runtime scripts — packaged for migration from Ubuntu to Alpine Linux.

## What's included

```
hermes-alpine/
├── hermes-agent/       # Main agent codebase (from ~/hermes-webui/)
├── skills/             # All custom skills (~60+)
├── plugins/            # hermes-lcm, rtk-rewrite
├── scripts/            # Runtime helper scripts
├── config.yaml.example # Sanitized config template
├── requirements.txt    # Python runtime dependencies
├── requirements-mcp.txt # Python MCP package
├── package.json        # NPM MCP packages
└── .gitignore          # Excludes all runtime & credential files
```

---

## Quick install (one-shot)

```bash
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine
chmod +x scripts/setup-ecosystem.sh
sudo -S -p '' ./scripts/setup-ecosystem.sh
```

This installs everything in the correct dependency order — system deps → Node.js → Python venv → Python packages → npm packages → Hermes Agent.

**Supported distros:** Alpine, Debian/Ubuntu, Fedora, Arch (auto-detected)

For custom paths:
```bash
HERMES_SRC=~/hermes-alpine VENV=~/.hermes/venv ./scripts/setup-ecosystem.sh
```

---

## Manual setup (step-by-step)

```bash
# 1. Install system deps
apk add python3 py3-pip git nodejs npm

# 2. Clone
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine

# 3. Copy and edit config
cp config.yaml.example ~/.hermes/config.yaml
nano ~/.hermes/config.yaml   # fill in your API keys

# 4. Install Python deps
pip install -r requirements.txt
pip install -r requirements-mcp.txt

# 5. Install npm deps
npm install

# 6. Bootstrap
cd hermes-agent
python3 bootstrap.py
```

---

## MCP packages included

| Package | Purpose |
|---|---|
| `@notionhq/notion-mcp-server` | Notion API integration |
| `superlocalmemory` | Local memory/vector store |
| `@colbymchenry/codegraph` | Code graph analysis |
| `@agentmemory/agentmemory` | Agent memory system |
| `mcp` (Python) | MCP SDK |

---

## Key notes

- **Never commit `config.yaml`, `.env`, or any file with live credentials** — all are excluded via `.gitignore`
- **Runtime directories** (`sessions/`, `memories/`, `cache/`, `logs/`, `state.db`, `auth.json`) are excluded — recreate fresh on the new machine
- **Alpine-specific**: Use `apk` instead of `apt`. Python `venv` preferred over `.venv` auto-detection. See `scripts/post-update-termux.sh` for Alpine-specific pip fixes.

## Skills structure

Each skill lives in `skills/<skill-name>/SKILL.md`. Load with:
```
/skill <skill-name>
```
