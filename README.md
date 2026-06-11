# hermes-alpine

Hermes Agent ecosystem — MCP packages, skills, plugins, and runtime scripts — packaged for Alpine Linux (also works on Debian, Fedora, Arch).

## What this repo provides

| Component | Description | Count |
|-----------|-------------|-------|
| 🧠 **Skills** | Hermes Agent skill files | **129** total (107 categorized across 19 categories, 22 standalone) |
| 🔌 **Plugins** | Hermes Agent plugins with tool hooks | **2** (hermes-lcm, rtk-rewrite) |
| 🔧 **MCP servers** | Model Context Protocol server configs | **5** pre-configured servers |
| 📦 **MCP packages** | npm + Python MCP dependencies | 4 npm packages + `mcp` SDK |
| 🚀 **Setup script** | One-shot installer | `scripts/setup-ecosystem.sh` |
| 🔄 **Update helper** | Keep external deps up to date | `scripts/update-external.sh` |

## Quick install (one-liner, no clone needed)

```sh
curl -fsSL https://raw.githubusercontent.com/PatrickNoFilter/hermes-alpine/main/scripts/setup-ecosystem.sh | sh
```

## Full clone

```sh
git clone https://github.com/PatrickNoFilter/hermes-alpine.git ~/hermes-alpine
cd ~/hermes-alpine
./scripts/setup-ecosystem.sh
```

## What the installer does

1. Auto-detects your distro (Alpine / Debian / Fedora / Arch)
2. Installs system build deps (Node.js, Python, Rust, etc.)
3. Sets up Python venv + build toolchain
4. Installs Python runtime deps and MCP package
5. Installs npm packages (notion-mcp-server, superlocalmemory, codegraph, agentmemory)
6. Clones `hermes-agent` from upstream `nousresearch/hermes-agent`
7. Installs `hermes-agent` in editable mode, symlinks `hermes` CLI to `~/.local/bin/`
8. **Symlinks 129 skills** from `skills/` → `~/.hermes/skills/`
9. **Symlinks 2 plugins** from `plugins/` → `~/.hermes/plugins/`
10. **Merges MCP server config** into `~/.hermes/config.yaml`

## After install

```sh
# 1. Add hermes to PATH (add to ~/.profile or ~/.bashrc to persist)
export PATH="$HOME/.local/bin:$PATH"

# 2. Configure (add your API keys)
cp config.yaml.example ~/.hermes/config.yaml
nano ~/.hermes/config.yaml

# 3. Verify integration
./scripts/verify-integration.sh

# 4. Start Hermes
hermes
```

---

## Ecosystem Architecture

```
hermes-alpine/
├── skills/                          # 129 Hermes skills
│   ├── apple/                       #   apple-notes, reminders, findmy, imessage, macos-computer-use
│   ├── autonomous-ai-agents/        #   hermes-agent, claude-code, codex, opencode, kanban-codex-lane
│   ├── creative/                    #   26 skills: excalidraw, ascii-art, manim-video, p5js, …
│   ├── data-science/                #   jupyter-live-kernel
│   ├── devops/                      #   15 skills: hermes-webui, kanban-orchestrator, …
│   ├── email/                       #   himalaya
│   ├── gaming/                      #   minecraft-modpack-server, pokemon-player
│   ├── github/                      #   6 skills: code-review, pr-workflow, issues, …
│   ├── mcp/                         #   native-mcp
│   ├── media/                       #   gif-search, heartmula, songsee, spotify, youtube-content
│   ├── mlops/                       #   huggingface-hub, building-ai-from-scratch, freellmapi
│   ├── note-taking/                 #   obsidian
│   ├── productivity/                #   10 skills: airtable, notion, google-workspace, …
│   ├── red-teaming/                 #   godmode
│   ├── research/                    #   7 skills: arxiv, blogwatcher, llm-wiki, polymarket, …
│   ├── security/                    #   onex
│   ├── smart-home/                  #   openhue
│   ├── social-media/                #   xurl
│   ├── software-development/        #   15 skills: tdd, plan, spike, debugpy, …
│   ├── dogfood/                     #   (standalone skill)
│   ├── firecrawl*/                  #   17 firecrawl skills (standalone)
│   └── (standalone)                 #   yuanbao, scrapling, playwright, oracle-cloud, …
├── plugins/
│   ├── hermes-lcm/                  # Lossless Context Management (DAG engine)
│   └── rtk-rewrite/                 # RTK terminal command rewriting
├── scripts/
│   ├── setup-ecosystem.sh           # One-shot installer (steps 1-10)
│   ├── install-skills.sh            # Symlink skills to ~/.hermes/skills/
│   ├── install-plugins.sh           # Symlink plugins to ~/.hermes/plugins/
│   ├── configure-mcp.py             # Merge MCP servers into config.yaml
│   ├── verify-integration.sh        # Post-install verification
│   ├── update-external.sh           # Update npm + Python MCP + RTK
│   ├── notion-mcp.sh                # Notion MCP server wrapper
│   └── slm-mcp.sh                   # SuperLocalMemory MCP server wrapper
├── config.yaml.example              # Full Hermes config with MCP servers
├── Makefile                         # Build lifecycle targets
├── package.json                     # npm MCP packages
├── requirements.txt                 # Python runtime deps
├── requirements-mcp.txt             # Python MCP SDK
├── AGENTS.md                        # Agent instructions for this repo
├── ARCHITECTURE.md                  # Architecture reference
├── CONTRIBUTING.md                  # Contributor workflow
└── .github/                         # Issue/PR templates, CI workflows
```

## Makefile targets

```sh
make install          # Full install: deps + skills + plugins + MCP config
make install-skills   # Symlink skills only
make install-plugins  # Symlink plugins only
make configure-mcp    # Merge MCP server config
make verify           # Check integration status
make update-external  # Update npm + Python MCP + RTK
make bootstrap        # Full install + verify
```

## MCP servers included

| Server | Command | Purpose |
|--------|---------|---------|
| `codegraph` | `codegraph serve --mcp` | Code graph analysis |
| `context-mode` | `npx -y context-mode` | Context management |
| `firecrawl` | `npx -y firecrawl-mcp` | Web scraping |
| `notion` | `bash scripts/notion-mcp.sh` | Notion API integration |
| `superlocalmemory` | `bash scripts/slm-mcp.sh` | Local memory/vector store |

## Skills by category

| Category | Count | Skills |
|----------|-------|--------|
| `creative` | 26 | architecture-diagram, ascii-art/video, baoyu-*, claude-design, comfyui, excalidraw, humanizer, manim-video, p5js, pixel-art, popular-web-designs, pretext, sketch, songwriting, touchdesigner, translate, *-video-* |
| `software-development` | 15 | tdd, plan, spike, systematic-debugging, debugpy, node-inspect-debugger, code-review, skill-authoring, s6-container-supervision, markitdown, modal-gemma, subagent-driven-dev, writing-plans, *-harness-engineering, *-commands |
| `devops` | 15 | hermes-webui, kanban-orchestrator, kanban-worker, cloakbrowser, external-project-setup, hermes-apk-builder, hermes-gateway-ops, hermes-memory-setup, hermes-post-update-check, hermes-provider-setup, modal-cloud-encode, proot-environment, webhook-subscriptions, update-hermes-* |
| `productivity` | 10 | airtable, google-workspace, linear, maps, nano-pdf, notion, notion-vault-logger, ocr-and-documents, powerpoint, teams-meeting-pipeline |
| `research` | 7 | arxiv, blogwatcher, financial-documentary, last30days, llm-wiki, polymarket, research-paper-writing |
| `github` | 6 | codebase-inspection, github-auth, github-code-review, github-issues, github-pr-workflow, github-repo-management |
| `apple` | 5 | apple-notes, apple-reminders, findmy, imessage, macos-computer-use |
| `autonomous-ai-agents` | 5 | hermes-agent, claude-code, codex, opencode, kanban-codex-lane |
| `media` | 5 | gif-search, heartmula, songsee, spotify, youtube-content |
| `mlops` | 3 | building-ai-from-scratch, freellmapi-hermes-integration, huggingface-hub |
| `gaming` | 2 | minecraft-modpack-server, pokemon-player |
| `data-science` | 1 | jupyter-live-kernel |
| `email` | 1 | himalaya |
| `mcp` | 1 | native-mcp |
| `note-taking` | 1 | obsidian |
| `red-teaming` | 1 | godmode |
| `security` | 1 | onex |
| `smart-home` | 1 | openhue |
| `social-media` | 1 | xurl |

**Standalone flat skills (22):** dogfood, firecrawl (and 16 variants: firecrawl-agent, firecrawl-build*, firecrawl-cli, firecrawl-crawl, firecrawl-download, firecrawl-interact, firecrawl-map, firecrawl-monitor, firecrawl-parse, firecrawl-scrape, firecrawl-search), hermes-webui-self-update-bug, oracle-cloud-ai-infrastructure, playwright-termux-arm64, scrapling, yuanbao

## Plugin reference

### hermes-lcm (Lossless Context Management)

Replaces the built-in ContextCompressor with a DAG-based engine that never drops a message. Based on the LCM paper by Ehrlich & Blackman.

Provides tools: `lcm_grep`, `lcm_load_session`, `lcm_describe`, `lcm_expand`, `lcm_status`, `lcm_doctor`

### rtk-rewrite

Bridges RTK's terminal command rewriting into Hermes via `pre_tool_call` hook. Rewrites terminal commands through `rtk rewrite` before execution. Fails open if `rtk` binary is not in PATH.

## Key notes

- **Never commit `config.yaml`, `.env`, or any file with live credentials** — all are excluded via `.gitignore`
- **hermes-agent** is cloned fresh from upstream on each setup run (shallow, `--depth=1`)
- **Alpine-specific**: Python 3.14 requires patching `requires-python` in hermes-agent's `pyproject.toml` (done by the setup script)
- **Skills are symlinked**, not copied — run `make install-skills` after `git pull` to pick up new skills
- **MCP server config uses `--dry-run`** first so you can review changes before they take effect
- Run `make verify` anytime to check integration health
- See `CONTRIBUTING.md` before opening issues or pull requests

## License

MIT — see LICENSE file.
