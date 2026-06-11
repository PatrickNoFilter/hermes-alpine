# SuperLocalMemory MCP Server on ARM64 PRoot

Connecting SLM to Hermes as an MCP server on ARM64 Termux+PRoot.

## Architecture

```
Hermes Agent  ←→  MCP (stdio)  ←→  slm-mcp.sh  ←→  venv python  ←→  SLM Python code
                                    bash wrapper       /root/.hermes/slm-env/
```

SLM is an npm package (`npm i -g superlocalmemory`) whose CLI is a Node wrapper that spawns Python. The MCP server runs as a Hermes subprocess via bash wrapper.

## Setup Steps

### 1. Install SLM via npm

```bash
npm i -g superlocalmemory
```

### 2. Create venv for MCP deps

SLM's MCP server needs `mcp` + `pydantic` Python packages. On ARM64 PRoot:

```bash
uv venv --python 3.14 /root/.hermes/slm-env
UV_LINK_MODE=copy uv pip install mcp --python /root/.hermes/slm-env/bin/python
```

**Why `UV_LINK_MODE=copy`:** PRoot doesn't support hardlinks between filesystems. Without this, uv fails with `Failed to copy` / `No such file or directory`.

### 3. Create MCP wrapper script

`/root/.hermes/scripts/slm-mcp.sh`:

```bash
#!/bin/bash
export PATH="/root/.hermes/node/bin:$PATH"
SLM_PKG=/root/.hermes/node/lib/node_modules/superlocalmemory
PYTHONPATH="$SLM_PKG/src" exec /root/.hermes/slm-env/bin/python -m superlocalmemory.cli.main mcp
```

### 4. Register in Hermes config

```bash
hermes mcp add superlocalmemory --command bash --args /root/.hermes/scripts/slm-mcp.sh
# Will ask: overwrite? y / Enable all 33 tools? Y
```

Or pipe answers: `printf 'y\ny\n' | hermes mcp add ...`

### 5. Restart Hermes

MCP connections are established at startup. `exit` → `hermes` to pick up new tools.

## ARM64-Specific Workarounds

### Embedding Worker -> infinite timeout

SLM tries to spawn an embedding worker (sentence-transformers). On ARM64 without PyTorch, it hangs for 180s then times out:

```bash
pkill -f embedding_worker
```

**Permanent fix** — patch `embedding.provider` to `none` and guard `is_available()`:

1. `slm config set` doesn't support `provider: none` key. Patch `config.json` directly:
   ```json
   "embedding": {"provider": "none", ...}
   ```
2. In `src/superlocalmemory/core/embeddings.py` ~line 198:
   ```python
   @property
   def is_available(self):
       if self._config.provider == "none":
           return False
       ...
   ```

### PYTHONPATH Dual Bridge

System Python (`/usr/bin/python3`, via apt) has numpy/scipy/networkx. Termux Python (`python3.13`, via pip3) has vaderSentiment/rank-bm25. SLM's npm wrapper (`slm-npm`) sets PYTHONPATH to include both:

```javascript
const PYTHONPATH = [
    SRC_DIR,
    '/data/data/com.termux/files/usr/lib/python3.13/site-packages',
    process.env.PYTHONPATH || ''
].filter(Boolean).join(':');
```

### MCP dep install summary

| Package | Source | Why |
|---------|--------|-----|
| `pydantic` + `pydantic-core` | `apt install python3-pydantic` | Native Rust extension — pip build fails on ARM64 |
| `mcp` | `uv pip install mcp` in venv | Pure Python wheel, no compilation needed |

## Verification

```bash
# Test MCP server directly
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | bash /root/.hermes/scripts/slm-mcp.sh
# Should return initialize result with 33 tools

# Check Hermes config
hermes mcp list

# Test recall (BM25 only, no embedding timeout)
slm recall "test query"
```

## Available MCP Tools (33 total)

Core memory: `remember`, `recall`, `search`, `fetch`, `list_recent`, `get_status`, `delete_memory`, `update_memory`, `report_outcome`, `set_mode`
Session: `session_init`, `observe`, `report_feedback`, `close_session`
Maintenance: `forget`, `consolidate_cognitive`, `get_soft_prompts`, `run_maintenance`
Mesh: `mesh_summary`, `mesh_peers`, `mesh_send`, `mesh_inbox`, `mesh_state`, `mesh_lock`, `mesh_events`, `mesh_status`
Evolution: `log_tool_event`, `get_assertions`, `reinforce_assertion`, `contradict_assertion`, `evolve_skill`, `skill_health`, `skill_lineage`

## Pitfalls

- **`hermes config set args` stores as YAML string, not list.** Use `hermes mcp add` instead of manual config.yaml edits.
- **Hardlink errors in PRoot:** always use `UV_LINK_MODE=copy` with uv.
- **MCP server needs restart** of Hermes process to pick up new servers (no hot-reload).
- **venv needed** because system pip is PEP 668-managed (no `--system` install allowed).
