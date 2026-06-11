# Cloud GPU Deployment for GGUF Inference

> Reference file for the `llama-cpp` skill — covers Modal setup, auth, Python 3.14/PRoot workarounds, and specific model deployment examples.

## Modal Overview

[Modal](https://modal.com) is a serverless GPU platform. You write Python locally, it runs on their infra. Free tier: **$30/month compute credits** (no auto-bill).

| GPU | VRAM | Modal cost/hr | Free hours/mo |
|-----|------|--------------|--------------|
| T4 | 16 GB | ~$0.70 | ~42h |
| L40S | 48 GB | ~$1.00 | ~30h |
| A100-40GB | 40 GB | ~$2.50 | ~12h |
| A100-80GB | 80 GB | ~$3.50 | ~8.5h |
| H100 | 80 GB | ~$4.00 | ~7.5h |

## Gemma 4 12B — GGUF Quant Options

From [unsloth/gemma-4-12b-it-GGUF](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF):

| Quant | Size on disk | Fits T4 (16GB)? | Notes |
|-------|-------------|-----------------|-------|
| Q2_K variants | 4.2–4.7 GB | ✅ | Lowest quality, lowest vram |
| Q3_K_M | 5.7 GB | ✅ | Acceptable for many tasks |
| **Q4_K_M** | **7.12 GB** | **✅ Best** | Sweet spot: quality + headroom |
| Q5_K_M | 8.41 GB | ✅ | Better quality, less context headroom |
| Q6_K | 9.79 GB | ✅ | Good quality, limited context |
| Q8_0 | 12.7 GB | ⚠️ Tight | Little room for context |
| BF16 | 23.8 GB | ❌ | Full precision, won't fit T4 |

**Recommended: Q4_K_M** on T4 — leaves ~8 GB for KV cache (plenty for 128K context).

## Modal Setup

### Installation

```bash
pip install modal
modal setup
```

`modal setup` opens a browser for OAuth. On headless/terminal-only systems, it prints a URL — open it on any device, sign up, and copy the token back.

### Python 3.14 Compatibility Issue

On Python 3.14.4, Modal's dependency chain (grpclib, watchfiles, yarl, aiohttp) may have broken or missing `__init__.py` files after installation via `uv`. This manifests as `ImportError: cannot import name 'X' from 'Y'`.

**Fix: use Python 3.13 instead.**

```bash
# Check available Python versions
ls /data/data/com.termux/files/usr/bin/python3.*

# Create venv with Python 3.13
uv venv --python 3.13 .venv-modal
source .venv-modal/bin/activate

# Install modal without uv cache issues
UV_LINK_MODE=copy uv pip install modal

# If that still fails, use pip directly
pip install modal
```

On Termux/PRoot, `uv` may hit hardlink errors (`Operation not permitted`). Setting `UV_LINK_MODE=copy` mitigates this.

### Termux/PRoot: platform tag override

On Termux+PRoot, Python reports `android_24_arm64_v8a` — manylinux wheels are
rejected. Use `--python-platform linux` to override:

```sh
uv pip install --python-platform linux modal==1.4.4.dev17
```

**Critical Termux caveats:**
- `modal` **CLI is broken** on Termux — `watchfiles._rust_notify` is a Rust native .so compiled against glibc, but Android uses Bionic libc. Commands like `modal run`, `modal deploy`, `modal setup` crash with `ModuleNotFoundError: No module named 'watchfiles._rust_notify'`.
- **Python API works fine** — `import modal`, `modal.App()`, `@app.function()`, `.remote()` calls all work.
- **Auth via env vars only** — you cannot run `modal setup`. Use `MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET`.
- **grpclib circular import** — patch `grpclib/__init__.py` to move `__version__` before submodule imports.
- **Use modal>=1.4.4.dev17** — avoids a `config` ↔ `logger` circular import bug in 1.4.3.

See `termux-proot-environment` skill's `references/python-packaging-termux-arm64.md`
for the full ARM64/PRoot installation recipe.

### Token Authentication (no browser)

If `modal setup` fails, set the token manually:

1. Sign up at https://modal.com
2. Go to Settings → Tokens → Create a new token
3. Set environment variables:
```bash
export MODAL_TOKEN_ID="your-token-id"
export MODAL_TOKEN_SECRET="your-token-secret"
```
Or create `~/.modal.toml`:
```toml
[default]
token_id = "your-token-id"
token_secret = "your-token-secret"
```

## Complete Example: Gemma 4 12B Q4_K_M on Modal

### 1. Download the GGUF

```bash
# Install huggingface hub CLI
pip install huggingface-hub

# Download Q4_K_M (7.12 GB)
huggingface-cli download unsloth/gemma-4-12b-it-GGUF \
    gemma-4-12b-it-Q4_K_M.gguf \
    --local-dir ./models
```

### 2. Create the Modal script

```python
# gemma4_modal.py
import modal

# Define container image with llama-cpp-python
image = modal.Image.debian_slim() \
    .apt_install("build-essential") \
    .pip_install("llama-cpp-python")

# Persistent volume for model storage
volume = modal.Volume.from_name("gemma4-models", create_if_missing=True)

app = modal.App("gemma4-12b")

@app.function(
    gpu="t4",
    image=image,
    volumes={"/models": volume},
    timeout=600,          # 10 min max for first load
    container_idle_timeout=120,  # keep warm 2 min between calls
)
def generate(prompt: str) -> str:
    from llama_cpp import Llama

    llm = Llama(
        model_path="/models/gemma-4-12b-it-Q4_K_M.gguf",
        n_ctx=32768,        # 32K context
        n_gpu_layers=-1,    # full GPU offload
        verbose=False,
    )

    result = llm.create_chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=2048,
        temperature=0.7,
    )
    return result["choices"][0]["message"]["content"]

@app.function(gpu="t4", image=image, volumes={"/models": volume})
def chat_stream(prompt: str):
    """Streaming version - yields tokens as they're generated."""
    from llama_cpp import Llama

    llm = Llama(
        model_path="/models/gemma-4-12b-it-Q4_K_M.gguf",
        n_ctx=32768,
        n_gpu_layers=-1,
    )

    stream = llm.create_chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=2048,
        stream=True,
    )

    for chunk in stream:
        delta = chunk["choices"][0]["delta"]
        if "content" in delta:
            yield delta["content"]
```

### 3. Upload the model to Modal

```bash
# Upload GGUF to Modal Volume
modal volume put gemma4-models ./models/gemma-4-12b-it-Q4_K_M.gguf /models/

# Verify
modal volume ls gemma4-models /models/
```

### 4. Run it

```bash
# Interactive run
modal run gemma4_modal.py --prompt "What is the meaning of life?"

# Deploy as persistent API endpoint
modal deploy gemma4_modal.py
# → https://your-workspace--gemma4-12b-generate.modal.run

# Call the endpoint
curl https://your-workspace--gemma4-12b-generate.modal.run \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Write a haiku about GPUs"}'
```

### 5. Manage cost

```bash
# View usage
modal stats

# List all apps
modal app list

# Stop an app to prevent further charges
modal app stop gemma4-12b
```

## Modal Volume Commands

```bash
# List volumes
modal volume list

# Create a volume
modal volume create my-models

# Upload file
modal volume put my-models local/path/model.gguf /remote/path/

# Download file
modal volume get my-models /remote/path/model.gguf local/path/

# List files
modal volume ls my-models /remote/path/

# Delete volume
modal volume delete my-models
```

## Free Tier Limits

From [modal.com/pricing](https://modal.com/pricing):

| Resource | Free tier limit |
|----------|----------------|
| Monthly compute credits | $30 |
| Deployed crons | 5 |
| Web endpoints | 8 |
| Containers | 100 |
| GPU concurrency | 10 |
| Deployed apps | 200 |
| Log retention | 1 day |

**No credit card required** to start. Pricing is pay-per-second after credits exhaust.
