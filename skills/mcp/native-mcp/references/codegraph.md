# CodeGraph — Semantic Code Intelligence MCP Server

**Repo:** https://github.com/colbymchenry/codegraph
**Docs:** https://colbymchenry.github.io/codegraph/
**npm:** `@colbymchenry/codegraph`

## What It Does

Pre-indexed knowledge graph for codebases — symbol relationships, call graphs, and code structure. Agents query the graph instantly instead of scanning files. ~35% cheaper, ~70% fewer tool calls.

Supports: Claude Code, Cursor, Codex, OpenCode, **Hermes Agent**, Gemini, Antigravity, Kiro.

## Installation

```bash
# Global install (recommended)
npm i -g @colbymchenry/codegraph

# Binary location after install on Hermes's bundled Node.js:
# /root/.hermes/node/lib/node_modules/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-arm64/bin/codegraph
# (platform suffix varies: linux-arm64, linux-x64, darwin-arm64, etc.)

# Symlink to PATH:
ln -sf /root/.hermes/node/lib/node_modules/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-arm64/bin/codegraph /usr/local/bin/codegraph

# Verify:
codegraph --version
```

### Pitfall: npm global binary not on PATH

Hermes's bundled Node.js installs global npm packages under `/root/.hermes/node/lib/node_modules/...` but the binary often doesn't land on `$PATH`. Use `find /root/.hermes/node -name "codegraph" -type f` to locate it, then symlink to `/usr/local/bin/`.

## Hermes MCP Config

Add to `~/.hermes/config.yaml` under `mcp_servers:`:

```yaml
  codegraph:
    command: codegraph
    args:
    - serve
    - --mcp
    connect_timeout: 60
    timeout: 120
```

Or use the interactive installer:
```bash
codegraph install --target hermes --location global --yes
```

### Verify
```bash
hermes mcp list          # should show codegraph ✓ enabled
hermes mcp test codegraph  # should discover 10 tools
```

## 10 MCP Tools

| Tool | Purpose |
|------|---------|
| `codegraph_context` | **PRIMARY** — call first for "how does X work" questions |
| `codegraph_search` | Quick symbol search by name (returns locations) |
| `codegraph_callers` | Find all functions that call a specific symbol |
| `codegraph_callees` | Find all functions a specific symbol calls |
| `codegraph_impact` | Analyze impact radius of changing a symbol |
| `codegraph_node` | Get ONE symbol's details (location, signature, docs) |
| `codegraph_explore` | Source for several related symbols grouped by file |
| `codegraph_status` | Index status and statistics |
| `codegraph_files` | Required for file/folder exploration |
| `codegraph_trace` | Trace call path between two symbols |

## Per-Project Indexing

```bash
cd your-project
codegraph init -i        # initialize + auto-index
codegraph index          # re-index if needed
codegraph sync           # incremental update after changes
```

Index data stored in `.codegraph/` directory (gitignored).

### Preview Config Before Installing

```bash
codegraph install --print-config hermes   # shows exact YAML to add
```

This avoids interactive prompts. Add the output manually under `mcp_servers:` in config.yaml.

### Pick the Right Directory

**Do NOT index `~` or `/` — it indexes everything including node_modules, caches, and system files.** Pick the specific project directory:

```bash
cd /path/to/your/project    # NOT ~
codegraph init -i
```

### Timing by Codebase Size

Actual measured times (ARM64 Linux, single core):

| Files | Phase | Time |
|-------|-------|------|
| 2,512 | Full index (scan + parse + resolve) | **4 min** |
| 18,000+ | Full index | **3+ hours** (abandoned) |

The process has 3 phases:
1. **Scanning** — fast, finds all files
2. **Parsing** — slow, parses code with tree-sitter
3. **Resolving refs** — slowest, resolves imports/references (scales super-linearly)

Run in background: `codegraph index &` or via Hermes background terminal.

## Troubleshooting

### Database Locked / "Could not acquire file lock"

When a codegraph process is killed or crashes, it may leave:
- `/root/.codegraph/codegraph.lock` (or `.codegraph/codegraph.lock` in project dir)
- A stale daemon process (`daemon.pid`, `daemon.sock`)

**Fix:**
```bash
pkill -9 -f "codegraph"        # kill stale processes
rm -f /root/.codegraph/codegraph.lock /root/.codegraph/daemon.pid /root/.codegraph/daemon.sock
codegraph index                # retry
```

### "Failed to index: database is locked"

Same root cause as above. Kill processes, remove lock, retry.

### Another process may be indexing

The lock file prevents concurrent indexing. Wait for the other process to finish, or kill it and remove the lock.

## Uninstall

```bash
codegraph uninstall           # removes MCP config from all agents
codegraph uninit              # removes .codegraph/ index from current project
```
