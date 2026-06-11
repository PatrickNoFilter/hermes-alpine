# Context Mode — Context Window Optimization MCP Server

**Repo:** https://github.com/mksglu/context-mode
**Site:** https://context-mode.com
**npm:** `context-mode`

## What It Does

Context window optimization for AI coding agents. Core philosophy: **"Think-in-Code"** — run tool output in sandboxed subprocesses so the raw data never enters your conversation. Only derived summaries come back.

- Sandboxes terminal/file/API output → raw bytes stay out of context
- Auto-indexes large output into FTS5 knowledge base (BM25 retrieval)
- 12 language runtimes in sandbox (JS, TS, Python, Shell, Ruby, Go, Rust, PHP, Perl, R, Elixir, C#)
- Batch execution with auto-index + inline queries (`ctx_batch_execute`)
- Web fetching → markdown → auto-indexed (`ctx_fetch_and_index`)
- Session memory (auto-captured decisions, errors, plans, blockers)
- Insight dashboard for session analytics (port 4747)

## Installation

```bash
npm install -g context-mode
```

Binary lands at `/root/.hermes/node/lib/node_modules/context-mode/` (Hermes-bundled Node.js). The npm global binary is auto-detected by Hermes's MCP config via `command: context-mode`.

## Hermes MCP Config

Add to `~/.hermes/config.yaml` under `mcp_servers:`:

```yaml
  context-mode:
    command: context-mode
    args: []
    connect_timeout: 30
    timeout: 120
```

Already installed and active in this environment.

## Key MCP Tools

| Tool | Purpose |
|------|---------|
| `ctx_execute` | Run code in sandbox, only stdout enters context |
| `ctx_execute_file` | Process a file's content in sandbox without reading it into context |
| `ctx_batch_execute` | Run multiple commands + auto-index + answer queries in one round trip |
| `ctx_fetch_and_index` | Fetch URL → markdown → auto-index, raw bytes never in context |
| `ctx_index` | Store content in FTS5 knowledge base for on-demand retrieval |
| `ctx_search` | Multi-strategy search across indexed content + session auto-memory |
| `ctx_stats` | Context consumption statistics (bytes saved, tool breakdown) |
| `ctx_doctor` | Diagnose installation health |

## ARM64 Compatibility

Fully native ARM64 — pure Node.js/TypeScript, zero native dependencies. Installs and runs on Termux+PRoot with no compilation needed.

## Usage Pattern

The "Think-in-Code" pattern replaces reading raw output with code that derives an answer:

```
# Instead of: read file → 47KB into context
ctx_execute_file(path="huge.log", language="javascript",
  code="FILE_CONTENT.split('\\n').filter(l => /ERROR/.test(l)).length")

# Instead of: curl API → 200KB JSON into context
ctx_execute(language="javascript",
  code="const r = await fetch(url); const j = await r.json(); console.log(j.length)")
```

Only `console.log()` output enters the conversation — the raw bytes stay in the sandbox.
