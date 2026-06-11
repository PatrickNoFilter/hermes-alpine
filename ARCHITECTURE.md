# Architecture — hermes-alpine

This document describes the design decisions, module layout, and constraints
of the hermes-alpine ecosystem packaging repository.

## Purpose

hermes-alpine is an installer/distribution layer for the Hermes Agent ecosystem.
It does NOT reimplement Hermes Agent — it packages, configures, and wires
together the upstream components so they work out of the box on Alpine Linux.

## Layer model

```
  Hermes Agent (upstream, cloned fresh)
       ↑
  hermes-alpine scripts/
       │
  ├─ setup-ecosystem.sh   Auto-detects distro, installs system deps & Agent
  ├─ install-skills.sh    Symlinks skills/   → ~/.hermes/skills/
  ├─ install-plugins.sh   Symlinks plugins/  → ~/.hermes/plugins/
  ├─ configure-mcp.py     Merges MCP servers → ~/.hermes/config.yaml
  ├─ verify-integration.sh  Post-install health check
  └─ update-external.sh   Update npm/Python/RTK deps
```

### Design principles

1. **Non-destructive**: Skills and plugins are symlinked, not copied. Re-running
   `setup-ecosystem.sh` upgrades in place without overwriting user config.
2. **Idempotent**: Every script can be run multiple times safely. MCP config
   merging checks for existing entries before appending.
3. **Distro-adaptive**: `setup-ecosystem.sh` detects Alpine (apk), Debian/Ubuntu
   (apt), Fedora (dnf), and Arch (pacman) and adjusts commands accordingly.
4. **Symlink-first**: Repo → `~/.hermes/skills/` links avoid duplication and
   make `git pull` immediately reflect skill updates.
5. **Backup-safe**: `configure-mcp.py` backs up `config.yaml` before editing.
6. **Dry-run everywhere**: Every write operation supports `--dry-run` for review.

## File inventory

```
hermes-alpine/
├── skills/                        # 129 skills
│   ├── apple/                     #   5 skills
│   ├── autonomous-ai-agents/      #   5
│   ├── creative/                  #   26
│   ├── data-science/              #   1
│   ├── devops/                    #   15
│   ├── email/                     #   1
│   ├── gaming/                    #   2
│   ├── github/                    #   6
│   ├── mcp/                       #   1
│   ├── media/                     #   5
│   ├── mlops/                     #   3
│   ├── note-taking/               #   1
│   ├── productivity/              #   10
│   ├── red-teaming/               #   1
│   ├── research/                  #   7
│   ├── security/                  #   1
│   ├── smart-home/                #   1
│   ├── social-media/              #   1
│   ├── software-development/      #   15
│   ├── dogfood/                   #   (standalone)
│   ├── firecrawl*/                #   17 standalone skills
│   └── (other standalone)         #   yuanbao, scrapling, playwright, etc.
├── plugins/
│   ├── hermes-lcm/                # Lossless Context Management
│   │   ├── plugin.yaml            #   Hermes plugin manifest
│   │   ├── __init__.py            #   Plugin entry point
│   │   ├── dag.py                 #   DAG-based context engine
│   │   ├── engine.py              #   Context compression engine (~189 KB)
│   │   ├── store.py               #   Storage backend
│   │   ├── tools.py               #   Tool definitions (~75 KB)
│   │   └── ...                    #   30+ supporting modules
│   └── rtk-rewrite/
│       ├── plugin.yaml
│       └── __init__.py            #   pre_tool_call hook for RTK rewrite
├── scripts/
│   ├── setup-ecosystem.sh         # One-shot installer
│   ├── install-skills.sh          # Skill symlinker
│   ├── install-plugins.sh         # Plugin symlinker
│   ├── configure-mcp.py           # MCP config merger (Python, YAML-aware)
│   ├── verify-integration.sh      # 9-point health check
│   ├── update-external.sh         # Dep updater (npm, pip, RTK, DeepLX, …)
│   ├── notion-mcp.sh              # Notion MCP server wrapper
│   └── slm-mcp.sh                 # SuperLocalMemory MCP server wrapper
├── config.yaml.example            # Hermes config template with MCP servers
├── Makefile                       # Build lifecycle CLI
├── package.json                   # npm MCP packages
├── requirements.txt               # Python deps
├── requirements-mcp.txt           # Python MCP SDK
├── Dockerfile                     # Container build
├── docker-compose.yml             # Base compose
├── docker-compose.two-container.yml
├── docker-compose.three-container.yml
├── docker_init.bash               # Container init script
├── start.sh                       # Entry point
├── ctl.sh                         # Daemon lifecycle
├── bootstrap.py                   # WebUI launcher
├── server.py                      # WebUI server
├── mcp_server.py                  # MCP server (largest Python file, ~23 KB)
├── AGENTS.md                      # AI assistant instructions
├── ARCHITECTURE.md                # This file
├── CONTRIBUTING.md                # Contributor guide
└── .github/                       # Issue/PR templates, CI workflows
```

## Skill categories vs standalone skills

Skills are organized two ways:

- **Categorized** — in `skills/<category>/<name>/SKILL.md` (19 categories).
  The `install-skills.sh` script preserves this structure in `~/.hermes/skills/`.
  Hermes Agent scans the `~/.hermes/skills/` tree at session start and loads
  all SKILL.md files it finds.

- **Standalone** — in `skills/<name>/SKILL.md` (22 skills). These don't have a
  category subdirectory and are typically external or utility skills (firecrawl
  variants, yuanbao, scrapling, etc.).

## MCP server integration

MCP servers defined in `config.yaml.example` under `mcp_servers:`:

```yaml
mcp_servers:
  codegraph:            # Code graph analysis (npm global)
  context-mode:         # Context management (npx)
  firecrawl:            # Web scraping (npx)
  notion:               # Notion API (bash wrapper → node)
  superlocalmemory:     # Local vector store (bash wrapper → python)
```

The `configure-mcp.py` script:
1. Parses `config.yaml.example` to extract ecosystem server blocks
2. Checks `~/.hermes/config.yaml` for existing `mcp_servers:` section
3. Adds missing servers (or overwrites with `--force`)
4. Leaves non-ecosystem servers (user-customized) untouched
5. Backs up original config before modifying

## CI/CD pipeline

See `.github/workflows/ci.yml` — runs on push/PR to main:

- **shellcheck** — lint all shell scripts
- **YAML lint** — validate config files
- **Python lint** — ruff check + format on Python scripts
- **Script validation** — bash syntax check, Python compile
- **Config validation** — verify skill counts in README, validate
  `config.yaml.example` and MCP server completeness
- **Docker build** — verify Docker image builds successfully

## Constraints

- **Alpine primary target**: Shell scripts must be BusyBox ash compatible.
  Avoid bashisms (`[[ ]]`, `<<<`, arrays). Use `[ ]`, `printf`, POSIX patterns.
- **Python 3.11+**: The upstream Hermes Agent requires Python 3.11+. Alpine 3.21
  ships Python 3.14. The `pyproject.toml` `requires-python` pin is patched
  during installation.
- **No bundler/framework**: Like Hermes Agent, the ecosystem scripts use stdlib
  or simple shell. No webpack, no build step.
- **Symlinks for updates**: Skills are symlinked so `git pull` + `make install-skills`
  is a no-op (symlinks point to repo). To remove a skill, delete the symlink.
- **Safe credentials**: `.env`, `config.yaml`, `*.bak` are all in `.gitignore`.
  Never commit live API keys.
