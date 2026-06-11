# hermes-alpine

Hermes Agent ecosystem setup — MCP packages, skills, plugins, and runtime scripts — packaged for Alpine Linux.

## What this repo provides

- MCP npm packages (`@notionhq/notion-mcp-server`, `superlocalmemory`, `codegraph`, `agentmemory`)
- Python MCP runtime (`mcp` package)
- Skills (~60+) and plugins for the Hermes Agent
- `setup-ecosystem.sh` — one-shot installer for the entire ecosystem
- `hermes-agent` cloned fresh from [nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent)

## Quick install (one-liner, no clone needed)

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickNoFilter/hermes-alpine/main/scripts/setup-ecosystem.sh | bash
```

The script:
1. Auto-detects your distro (Alpine / Debian / Ubuntu / Fedora / Arch)
2. Installs all system build deps
3. Sets up Python venv + pip + build toolchain
4. Installs Python runtime deps (`requirements.txt`) and MCP package (`requirements-mcp.txt`)
5. Installs npm packages (`package.json`)
6. Clones `hermes-agent` from upstream `nousresearch/hermes-agent`
7. Installs `hermes-agent` in editable mode and symlinks the `hermes` CLI to `~/.local/bin/`

To update: re-run the same command.

---

## Full clone (if you want the repo too)

```bash
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine
./scripts/setup-ecosystem.sh
```

Then `git pull` inside `hermes-alpine/` to update.

---

## After install

```bash
# 1. Add hermes to PATH (add to ~/.bashrc to persist)
export PATH="$HOME/.local/bin:$PATH"

# 2. Configure (copy example and add your API keys)
cp config.yaml.example ~/.hermes/config.yaml
nano ~/.hermes/config.yaml

# 3. Start Hermes
hermes
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
- **hermes-agent** is cloned fresh from upstream on each run (shallow, `--depth=1`)
- **Alpine-specific**: Use `apk` instead of `apt`. See `scripts/post-update-termux.sh` for Alpine-specific pip fixes.

## Skills structure

Each skill lives in `skills/<skill-name>/SKILL.md`. Load with:
```
/skill <skill-name>
```