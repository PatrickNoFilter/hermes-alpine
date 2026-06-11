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

## Quick install (one-liner, no clone needed)

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickNoFilter/hermes-alpine/main/scripts/setup-ecosystem.sh | sudo bash
```

That's it. The script auto-detects your distro (Alpine / Debian / Ubuntu / Fedora / Arch), installs all system deps, Python venv, pip packages, npm packages, and Hermes Agent — in the correct order.

To update later, just re-run the same command.

---

## Full clone (if you want the repo too)

```bash
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine
chmod +x scripts/setup-ecosystem.sh
sudo ./scripts/setup-ecosystem.sh
```

Then `git pull` to update.

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

## After install

```bash
# 1. Configure
cp config.yaml.example ~/.hermes/config.yaml
nano ~/.hermes/config.yaml   # fill in your API keys

# 2. Activate venv
source venv/bin/activate

# 3. Start Hermes
hermes
```

---

## Key notes

- **Never commit `config.yaml`, `.env`, or any file with live credentials** — all are excluded via `.gitignore`
- **Runtime directories** (`sessions/`, `memories/`, `cache/`, `logs/`, `state.db`, `auth.json`) are excluded — recreate fresh on the new machine
- **Alpine-specific**: Use `apk` instead of `apt`. See `scripts/post-update-termux.sh` for Alpine-specific pip fixes.

## Skills structure

Each skill lives in `skills/<skill-name>/SKILL.md`. Load with:
```
/skill <skill-name>
```