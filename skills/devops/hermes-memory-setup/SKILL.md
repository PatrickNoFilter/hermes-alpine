---
name: hermes-memory-setup
description: "Install, configure, and troubleshoot Hermes memory providers — local (holographic) and cloud-backed (supermemory, hindsight, honcho, mem0, etc.). Covers the distinction between MCP memory servers and Hermes memory provider plugins."
version: 1.0.0
author: Hermes Agent
tags: [hermes, memory, setup, configuration, providers, holographic]
---

# Hermes Memory Provider Setup

Hermes has two separate memory systems:

1. **Memory Provider** (this skill) — a Hermes plugin registered via `hermes memory setup` that auto-indexes observations, provides tools like `fact_store`/`memory_search`, and integrates into the agent loop.
2. **MCP Memory Server** — an external MCP server (e.g. `agentmemory` MCP) connected via `hermes mcp add`. These are standalone tools you call manually; Hermes does NOT auto-write observations to them.

Only ONE memory provider can be active at a time (set in `config.yaml → memory.provider`). The built-in memory is always active as fallback.

## Quick Reference

| Provider | Auth | Setup command | Status |
|----------|------|---------------|--------|
| **holographic** | None (local SQLite + HRR vectors) | `hermes memory setup holographic` | ✅ Available |
| supermemory | SUPERMEMORY_API_KEY | `hermes memory setup supermemory` | Needs API key |
| hindsight | HINDSIGHT_API_KEY / local | `hermes memory setup hindsight` | Needs API key or local setup |
| honcho | HONCHO_API_KEY or base_url | `hermes memory setup honcho` | Needs config |
| mem0 | MEM0_API_KEY | `hermes memory setup mem0` | Needs API key |
| openviking | OPENVIKING_ENDPOINT (API key optional) | `hermes memory setup openviking` | Needs endpoint |
| retaindb | RETAINDB_API_KEY | `hermes memory setup retaindb` | Needs API key |
| byterover | API key | `hermes memory setup byterover` | Needs API key |

## Commands

```bash
# List available providers + current status
hermes memory status

# Install & activate a provider
hermes memory setup <provider_name>

# Switch provider (installs & activates)
hermes memory setup holographic  # zero-config local

# Providers are installed as Hermes plugins, NOT via `hermes plugins install`
# Use `hermes memory setup`, not `hermes plugins install <name>`
```

## Provider Details

### Holographic (local, no API key)

The only truly zero-config provider. Fully offline, uses SQLite + optional numpy for HRR vectors.

**Architecture:**
- SQLite DB at `~/.hermes/memory_store.db`
- HRR (Holographic Reduced Representations) — phase vectors (1024-dim) via SHA-256
- Extra tools: `fact_store` (add/search/probe/reason/contradict), `fact_feedback`
- Hybrid retrieval: FTS5 (40%) + Jaccard (30%) + HRR (30%)

**Capacity limits (HRR SNR):**
- HRR bundles all facts in a category into one memory bank vector
- SNR = √(dim / n_items) where dim = 1024 (default)
- SNR < 2.0 when n_items > 256 → retrieval noise increases
- At 512+ items per category, HRR component (30%) degrades noticeably
- FTS5 (40%) and Jaccard (30%) are NOT affected by HRR capacity — retrieval still works, just the HRR-weighted results get noisier
- SQLite has no practical row limit — only disk space

**Direct Python access (bulk operations):**
The `fact_store` tool only exposes single-fact operations. For bulk import/export/queries, call the store directly via `execute_code`:

```python
import sys, os
sys.path.insert(0, '/usr/local/lib/hermes-agent')
os.environ['HERMES_HOME'] = '/root/.hermes'

from plugins.memory.holographic.store import MemoryStore
from plugins.memory.holographic.retrieval import FactRetriever

store = MemoryStore()
retriever = FactRetriever(store=store)

# Bulk add
fid = store.add_fact(content="...", category="project", tags="tag1,tag2")

# Hybrid search (FTS5 + Jaccard + HRR)
results = retriever.search("query here", limit=10)

# List everything
all_facts = store.list_facts(limit=100)
```

**Config (in config.yaml under `plugins.hermes-memory-store`):**
```yaml
plugins:
  hermes-memory-store:
    db_path: $HERMES_HOME/memory_store.db
    auto_extract: true           # auto-extract facts at session end
    default_trust: 0.5
    min_trust_threshold: 0.3
    hrr_dim: 1024
    temporal_decay_half_life: 0  # days, 0 = disabled
```

**Trust scoring:** facts rated `helpful` → +0.05, `unhelpful` → -0.10. Facts below `min_trust_threshold` hidden from results.

### Supermemory (cloud, requires API key)

Cloud-backed memory via supermemory.ai. Install with `hermes memory setup supermemory`, then set `SUPERMEMORY_API_KEY` in `.env`.

### Hindsight (cloud or local)

Three modes:
- `cloud` — needs HINDSIGHT_API_KEY
- `local_external` — needs local hindsight server URL
- `local_embedded` — local mode, needs LLM provider selection (interactive curses UI)

The setup is interactive — requires TTY for API key/picker prompts.

## Memory Layering — All Three Can Coexist

Hermes has **three independent memory layers** that can run simultaneously without conflict:

```
┌─────────────────────────────────────┐
│ 1. Native memory tool (ALWAYS ON)   │
│    ~/.hermes/memories/              │
│    Injected every turn ~2.2K chars  │
│    Best for: compact preferences,   │
│    environment facts, corrections   │
├─────────────────────────────────────┤
│ 2. Memory Provider (ONE active)     │
│    Holographic / supermemory / etc. │
│    Auto-index via lifecycle hooks   │
│    Best for: structured fact store, │
│    vector/HRR search, trust scoring │
├─────────────────────────────────────┤
│ 3. External plugins/skills (MANY)   │
│    agent-memory-skill, Honcho, etc. │
│    Separate DB, independent tools   │
│    Best for: authority lanes,       │
│    entity graph, conflict detection │
└─────────────────────────────────────┘
```

**Key: they DON'T conflict** because each has a separate storage backend:

| Layer | Storage | Injected? |
|-------|---------|-----------|
| Native memory | `~/.hermes/memories/` (JSON files) | ✅ Every turn |
| MemoryProvider | Provider-specific DB (e.g. `memory_store.db`) | ❌ Via tools only |
| Plugin/Skill | Plugin-specific DB (separate file) | ❌ Via tools only |

### Holographic — Auto-Extraction Limitations

Despite being the MemoryProvider, holographic's auto-extraction is **minimal**:

| Hook | Behavior | Default |
|------|----------|---------|
| `sync_turn()` | **`pass`** — no per-turn auto-save | Always off |
| `on_session_end()` | Regex-only: detects "I prefer/like/use…" and "we decided/chose…" patterns | `auto_extract: false` |
| `on_memory_write()` | Mirrors native `memory` tool calls → saves same content as fact in holographic DB | ✅ Always on |

To enable the limited auto-extraction at session end:
```yaml
plugins:
  hermes-memory-store:
    auto_extract: true    # regex-only, session-end only
```

The regex patterns are basic — technical facts ("server runs Ubuntu"), entity names, and user corrections are NOT auto-detected. Facts must be saved explicitly via `fact_store(action='add')`.

### Memory Injection at Session Start — Token Cost

Holographic already injects relevant memories **per-turn** via `prefetch()` — searches DB using user's message as query, returns top 5 facts as `<memory-context>` block. But the **first turn of a new session** gets no memory context (no query yet), only a short system prompt notice.

| Scenario | Tokens/turn | What's injected |
|---|---|---|
| **Current** (system_prompt_block only) | ~40-80 | "Active. N facts." stat |
| **Inject top facts at session start** | ~300-800 | 5-10 facts with content |
| **Native memory** (built-in, always on) | ~400-600 | User profile + memory tool entries |
| **Combined: native + holographic facts** | ~700-1400 | All of the above |

To inject top facts at session start, modify `HolographicMemoryProvider.system_prompt_block()` in `__init__.py`:

```python
def system_prompt_block(self) -> str:
    if not self._store:
        return ""
    try:
        facts = self._store.list_facts(limit=5)
        if not facts:
            return ""
        lines = [f"- [{f.get('category','?')}] {f.get('content','')}" for f in facts]
        return "## Holographic Memory\\n" + "\\n".join(lines)
    except Exception:
        return ""
```

## External MCP Memory System — SuperLocalMemory V3

**SuperLocalMemory V3** (`slm`) is a standalone local-first memory system that runs as an MCP server alongside Hermes. Unlike Hermes Memory Providers, it's NOT auto-wired into the agent loop — you call its tools manually via MCP (`mcp_superlocalmemory_*`).

**Architecture:** SLM V3 uses 4-channel retrieval (semantic, BM25, temporal, entity-graph). On ARM64 without PyTorch, it falls back to BM25-only mode.

### Quick Setup (ARM64 / Termux PRoot)

```bash
# 1. Install via npm global
npm i -g superlocalmemory

# 2. Setup mode A (Local Guardian — zero LLM, fully offline)
slm setup       # Answer prompts for Mode A

# 3. Disable embedding (no PyTorch on ARM64 → avoid timeout/crashes)
# Patch config directly:
slm config set retrieval.embedding.provider none   # if fails, edit config.json
# And guard the embedding service:
# In src/superlocalmemory/core/embeddings.py ~line 198:
#   if self._config.provider == "none": return False

# 4. Install deps — split across system apt (heavy) + Termux pip3 (niche)
apt install -y python3-numpy python3-scipy python3-networkx
pip3 install vaderSentiment rank-bm25 --no-deps

# 5. Test
slm doctor     # 5 pass, 4 warnings = acceptable for Mode A
slm remember "test memory"
slm recall "test"    # BM25-only, instant
```

### MCP Server Integration

**Step 1 — Create venv for MCP SDK (avoids ARM64 build issues):**
```bash
uv venv --python 3.14 /root/.hermes/slm-env
UV_LINK_MODE=copy uv pip install mcp --python /root/.hermes/slm-env/bin/python
```

**Step 2 — Wrapper script (`/root/.hermes/scripts/slm-mcp.sh`):**
```bash
#!/bin/bash
export PATH="/root/.hermes/node/bin:$PATH"
SLM_PKG=/root/.hermes/node/lib/node_modules/superlocalmemory
PYTHONPATH="$SLM_PKG/src" exec /root/.hermes/slm-env/bin/python -m superlocalmemory.cli.main mcp
```

**Step 3 — Register with Hermes:**
```bash
hermes mcp add superlocalmemory --command bash --args "/root/.hermes/scripts/slm-mcp.sh"
# Answer 'Y' to overwrite + 'Y' to enable all 33 tools
```

**Step 4 — Restart Hermes.** Tools appear as `mcp_superlocalmemory_remember`, `mcp_superlocalmemory_recall`, etc.

### Available MCP Tools (33 total)

| Category | Tools |
|----------|-------|
| **Core memory** | `remember`, `recall`, `search`, `fetch`, `list_recent`, `delete_memory`, `update_memory`, `forget` |
| **Session** | `session_init`, `session_close`, `observe`, `report_outcome`, `report_feedback` |
| **Mesh (cross-session)** | `mesh_summary`, `mesh_peers`, `mesh_send`, `mesh_inbox`, `mesh_state`, `mesh_lock`, `mesh_events`, `mesh_status` |
| **Maintenance** | `get_status`, `set_mode`, `run_maintenance`, `consolidate_cognitive`, `get_soft_prompts` |
| **Behavioral evolution** | `log_tool_event`, `get_assertions`, `reinforce_assertion`, `contradict_assertion`, `evolve_skill`, `skill_health`, `skill_lineage` |

### ARM64 Constraints

| Issue | Workaround |
|-------|------------|
| **PyTorch / sentence-transformers** | No ARM64 wheel; build from source fails. → Mode A with BM25 fallback |
| **pydantic-core** | Native Rust extension, can't `pip3 install`. → Use system `apt install python3-pydantic` |
| **mcp pip package** | Pulls pydantic-core which fails on Termux pip3. → Install in venv via `uv` |
| **orjson** | Native build fails in PRoot (hardlink issue). → Accept warning, not critical |
| **Embedding worker timeout** | Spawns PyTorch subprocess → hangs for 180s. → Patch `provider: none` in config + source code guard on `is_available` |
| **rank-bm25 pip install** | Tries to build numpy dependency from source. → `--no-deps` flag, uses system numpy via PYTHONPATH |
| **Dual Python bridge** | System `python3.14` (heavy deps via apt) + Termux `python3.13` (niche deps via pip3). Bridge via `PYTHONPATH` in wrapper |

### Hermes Memory Stack — All Layers

```text
Hermes Memory Stack (can all coexist):
├── Native memory tool       (always-on, ~2.2K chars injected per turn)
├── Holographic provider     (one active provider, structured fact store)
├── Fact Store               (entity resolution + trust scoring)
├── Skills                   (procedural memory)
├── Session DB (FTS5)        (transcript search)
└── 🆕 SuperLocalMemory MCP  (BM25 + temporal + entity graph)
     ├── Mode A (Zero-LLM)   ← Recommended for ARM64
     ├── BM25 fallback       ← Active when no embeddings
     └── 33 MCP tools        ← Manual invocation
```

### Pitfalls

- **`hermes config set mcp_servers.X.args` stores as JSON string**, not YAML list. Always use `hermes mcp add` for proper YAML format.
- **MCP wrapper must use bash not sh** on Ubuntu/Debian (sh → dash, no `source` support). Use `.` instead of `source`.
- **`write_file` mangles `${VAR}` to `***`** in wrapper scripts. Use `patch` to restore variable expansion after writing.
- **MCP server connections persist for agent process lifetime.** Restart Hermes after config changes.
- **SLM MCP is NOT a Hermes Memory Provider.** Hermes won't auto-write observations to it. Call its tools explicitly.

See [references/slm-v3-arm64.md](references/slm-v3-arm64.md) for exact error transcripts and ARM64-specific reproduction steps.

## Backup & Sync — Holographic → Notion Cold Storage

Holographic facts are stored locally in SQLite (`memory_store.db`). For persistence across device loss or long-term archival, sync to Notion Hermes Vault is recommended.

### Pattern: no_agent cron + Python script

The pattern uses a `no_agent=True` cron job running a Python script every 1h. No LLM cost — the script runs headless and only triggers on new facts.

**Script:** `scripts/holographic-to-notion-sync.py` — deployed at `~/.hermes/scripts/sync-holographic-to-notion.py`

**Cron job (no_agent, every 1h):**
```yaml
name: holographic-to-notion-sync
schedule: every 1h
script: sync-holographic-to-notion.py
no_agent: true
deliver: local
```

**What the script does:**
1. Reads all facts from `memory_store.db` via `MemoryStore.list_facts()`
2. Tracks last synced `fact_id` in a state file (`~/.hermes/state/holographic_notion_sync.json`)
3. Finds or creates a `Holographic Memory` heading on the Notion Hermes Vault page
4. Appends new facts as bulleted list items in batches of 10
5. Deduplicates by checking existing block plain_text on the page

**Setup:**
```bash
# 1. Ensure NOTION_API_KEY is in ~/.hermes/.env
grep NOTION_API_KEY ~/.hermes/.env

# 2. Initial manual sync
python3 ~/.hermes/scripts/sync-holographic-to-notion.py

# 3. Create cron job (no_agent mode — no LLM cost)
# Use cronjob(action='create') with:
#   name: holographic-to-notion-sync
#   schedule: every 1h
#   script: sync-holographic-to-notion.py
#   no_agent: true
#   deliver: local
```

**Limitations:**
- Notion API rate limits: 3 req/s per integration. Script batches 10 blocks/call.
- 2000 char per rich_text item ceiling — longer facts are truncated in the script (unlikely for normal holographic facts).
- No delete/update sync — only append. If a fact is removed from holographic, the Notion copy stays.
- No bidirectional sync — hot store = holographic (fast, local), cold archive = Notion (slow, cloud).

**Alternative use:** The script can also be run on-demand (`python3 ~/.hermes/scripts/sync-holographic-to-notion.py`) to back up before `memory reset` operations.

See [references/notion-sync-pipeline.md](references/notion-sync-pipeline.md) for script internals, env variable discovery, and dedup strategy.

## Troubleshooting

| Symptom | Diagnosis |
|---------|-----------|
| `hermes memory setup <name>` says "not found" | Provider doesn't exist. Check spelling, or the name might be an MCP server not a memory provider |
| Provider shows "not available ✗" after install | Missing required env vars. Run `hermes memory status` to see which |
| Provider stuck "available" but no tools | Try `/reset` (new session) to reload memory provider |
| `hermes plugins install <name>` fails with "invalid identifier" | Memory providers use `hermes memory setup`, not `hermes plugins install`. Those are different systems |
| agentmemory MCP running but empty | agentmemory is an MCP server, NOT a Hermes memory provider. Hermes won't auto-index to it. Use its MCP tools manually (`mcp_agentmemory_memory_*`) |
| `fact_store` tool not appearing after switching provider | Provider is activated mid-session. The `fact_store`/`fact_feedback` tools are registered at session start. Use `/reset` to start a new session |

## Community Plugins

See [references/community-plugins.md](references/community-plugins.md) for third-party Hermes memory plugins discovered via GitHub search. Includes local-first options (agent-memory-skill, MemPalace) and cloud/API-based (Sibyl-Memory, LanceDB, Exabase, hy-memory).
