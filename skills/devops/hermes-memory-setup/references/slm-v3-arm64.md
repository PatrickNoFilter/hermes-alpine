# SuperLocalMemory V3 on ARM64 Termux PRoot — Reproduction Steps

## Environment

- **Device:** Samsung Galaxy A33 (Exynos 1280, ARM64, 8GB RAM)
- **OS:** Termux + PRoot (Ubuntu Noble)
- **Python:** 3.14.4 (system apt) + 3.13.13 (Termux pip)
- **Node:** Hermes-bundled Node.js at `/root/.hermes/node/bin/node`
- **SLM:** v3.5.7 installed via `npm i -g superlocalmemory`

## Step-by-Step Setup (Verified Working)

### 1. Install SLM

```bash
export PATH="/root/.hermes/node/bin:$PATH"
npm i -g superlocalmemory
```

Package installs to `/root/.hermes/node/lib/node_modules/superlocalmemory/`.
Python code lives at `<pkg_root>/src/superlocalmemory/`.
CLI wrapper at `<pkg_root>/bin/slm-npm` — a Node.js script that finds `python3` and runs `-m superlocalmemory.cli.main`.

### 2. Initial Setup

```bash
slm setup
```

Choose **Mode A (Local Guardian)** when prompted. Accept defaults for data dir, profile name.

### 3. Install System Dependencies (apt)

SLM needs numpy, scipy, networkx. These fail to build from source on ARM64 pip. Install via apt:

```bash
apt install -y python3-numpy python3-scipy python3-networkx python3-httpx python3-einops python3-dateutil
```

### 4. Install Niche Dependencies (pip3, Termux)

```bash
pip3 install vaderSentiment rank-bm25 --no-deps
```

**Why `--no-deps`:** rank-bm25 tries to build numpy from source → fails on ARM64 (no wheel, C extensions fail). Since numpy is already installed via apt, `--no-deps` skips the dependency installation.

### 5. Patch Dual Python Bridge

The `slm-npm` wrapper (`/root/.hermes/node/lib/node_modules/superlocalmemory/bin/slm-npm`) runs `python3` but Termux pip installed to python3.13. The wrapper already extends `PYTHONPATH` with Termux site-packages — verify:

```javascript
// In slm-npm, findPython() returns first available. PYTHONPATH is extended:
process.env.PYTHONPATH = [...existingPaths, termuxSitePackages].join(':');
```

If `slm doctor` shows missing Termux-installed packages (vaderSentiment, rank_bm25), the PYTHONPATH bridge isn't working. You can also set it manually:

```bash
export PYTHONPATH="/data/data/com.termux/files/usr/lib/python3.13/site-packages:$PYTHONPATH"
```

### 6. Disable Embedding Worker (Critical for ARM64)

Without this, `slm recall` hangs for 180s trying to spawn a PyTorch embedding worker.

**Config patch:**
```bash
slm config set retrieval.embedding.provider none
# If this key doesn't exist, patch config.json directly:
```

Edit `~/.superlocalmemory/config.json`:
```json
{
  "mode": "a",
  "retrieval": {
    "embedding": {
      "provider": "none"
    },
    "use_cross_encoder": false
  }
}
```

**Source code guard** in `src/superlocalmemory/core/embeddings.py` (~line 198):
```python
@property
def is_available(self) -> bool:
    if self._config.provider == "none":
        return False
    # ... existing checks ...
```

### 7. Verify

```bash
slm doctor        # Expect: 5 pass, 4 WARN (torch, sklearn, fastapi, orjson)
slm remember "Testing SLM on ARM64 with BM25 fallback"
slm recall "test" # Should return instantly with BM25 results
```

### 8. MCP Server Setup

**Create venv** (needed because pip-installed `mcp` package pulls pydantic-core which fails on ARM64 without apt):

```bash
uv venv --python 3.14 /root/.hermes/slm-env
UV_LINK_MODE=copy uv pip install mcp --python /root/.hermes/slm-env/bin/python
```

**Why `UV_LINK_MODE=copy`:** In PRoot, hardlinks across filesystem boundaries fail. This env var forces copy instead.

**Wrapper script** at `/root/.hermes/scripts/slm-mcp.sh`:
```bash
#!/bin/bash
export PATH="/root/.hermes/node/bin:$PATH"
SLM_PKG=/root/.hermes/node/lib/node_modules/superlocalmemory
PYTHONPATH="$SLM_PKG/src" exec /root/.hermes/slm-env/bin/python -m superlocalmemory.cli.main mcp
```

**Register with Hermes:**
```bash
hermes mcp add superlocalmemory --command bash --args "/root/.hermes/scripts/slm-mcp.sh"
```

First prompt: overwrite existing? → `y`
Second prompt: enable all 33 tools? → `Y`

**Restart Hermes** for tools to appear as `mcp_superlocalmemory_*`.

## Error Transcripts

### Embedding worker timeout (180s)
```
Ollama embedder not available (model=nomic-embed-text). Falling back.
# ... 180s timeout ...
EmbeddingService not available — BM25-only mode.
```

**Fix:** Config `provider: none` + source code `is_available` guard.

### pydantic-core ImportError (pip3 install mcp)
```
ModuleNotFoundError: No module named 'pydantic_core'
```

**Fix:** Don't use Termux pip3 for mcp. Use `uv` venv with system python3.14, which has pydantic-core from apt.

### rank-bm25 numpy build failure
```
error: Failed to build numpy from source on ARM64
```

**Fix:** `pip3 install rank-bm25 --no-deps` + system numpy via PYTHONPATH.

### orjson build failure (PRoot)
```
No such file or directory (os error 2) — hardlink in PRoot
```

**Acceptable warning.** Not critical for SLM operation.

### hermes config set args stored as string
```yaml
# After: hermes config set mcp_servers.X.args '["val"]'
args: '["/path/to/script.sh"]'  # YAML string, not list — WRONG

# Required:
args:
- /path/to/script.sh
```

**Fix:** Use `hermes mcp add` instead of `hermes config set` for MCP server args.

## Files Created/Modified

| Path | Purpose |
|------|---------|
| `/root/.hermes/scripts/slm-mcp.sh` | MCP server wrapper (bash → venv python) |
| `/root/.hermes/slm-env/` | Python venv with mcp SDK |
| `/root/.superlocalmemory/config.json` | SLM config (provider: none) |
| `~/.hermes/config.yaml` (mcp_servers.superlocalmemory) | Hermes MCP registration |
| `/root/.hermes/node/lib/node_modules/superlocalmemory/src/superlocalmemory/core/embeddings.py` | Patched `is_available` guard |

## Verification Checklist

- [ ] `slm doctor` — 5 pass, warnings acceptable
- [ ] `slm remember "test"` — exits cleanly
- [ ] `slm recall "test"` — returns results in <2s (no timeout)
- [ ] `.hermes/scripts/slm-mcp.sh` — `echo '{"jsonrpc":"2.0","id":1,"method":"initialize"...}' | bash slm-mcp.sh` returns proper initialize response
- [ ] `hermes mcp list` shows superlocalmemory as connected
