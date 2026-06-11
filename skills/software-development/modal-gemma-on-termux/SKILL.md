---
name: modal-gemma-on-termux
version: "1.1"
description: Deploy Gemma 4 (or any GGUF model) on Modal from Termux/PRoot ARM64, then connect Hermes to it
---

# Modal + Gemma 4 on Termux/PRoot ARM64

## Prerequisites
- Python 3.13 (not 3.14 — broken dep chain)
- `uv` installed
- Modal account (modal.com) with token_id + token_secret

## Install Modal

```bash
# Create venv with Python 3.13
uv venv --python 3.13 ~/.venv-modal
source ~/.venv-modal/bin/activate

# Force-platform install (bypasses android_24_arm64_v8a detection)
UV_LINK_MODE=copy uv pip install --python-platform linux modal>=1.4.4.dev17

# Patch grpclib circular import
cd ~/.venv-modal/lib/python3.13/site-packages/grpclib
# Move __version__ before submodule imports in __init__.py
```

## Auth (CLI doesn't work on Android — use env vars or config file)
```bash
# Option A: Write ~/.modal.toml
cat > ~/.modal.toml << 'EOF'
[default]
token_id = "ak-..."
token_secret = "as-..."
EOF

# Option B: Env vars (for scripts)
export MODAL_TOKEN_ID="ak-..."
export MODAL_TOKEN_SECRET="as-..."
```

## Deploy
```bash
source ~/.venv-modal/bin/activate
python deploy_gemma.py
```

## OpenAI-Compatible Endpoint (for Hermes integration)

Add this to your Modal app to expose `/v1/chat/completions`:

```python
@app.function(
    gpu="t4",
    image=image,
    volumes={"/models": volume},
    timeout=600,
    scaledown_window=300,       # keep warm 5 min (was container_idle_timeout)
)
@modal.concurrent(max_inputs=10)  # was allow_concurrent_inputs
@modal.fastapi_endpoint(method="POST", label="gemma4-chat")
def chat_completions(data: dict):
    llm = _get_llm()
    messages = [{"role": m["role"], "content": m["content"]} for m in data.get("messages", [])]
    max_tokens = data.get("max_tokens", 1024)
    temperature = data.get("temperature", 0.7)
    result = llm.create_chat_completion(messages=messages, max_tokens=max_tokens, temperature=temperature)
    return {"id": result["id"], "object": "chat.completion", "choices": result["choices"]}
```

For more complex routing (multiple endpoints, CORS, health checks), use `@modal.asgi_app`:

```python
from fastapi import FastAPI
from pydantic import BaseModel

web_app = FastAPI()

class ChatRequest(BaseModel):
    model: str = "gemma-4-12b"
    messages: list
    max_tokens: int = 1024
    temperature: float = 0.7

@web_app.post("/v1/chat/completions")
async def chat(req: ChatRequest):
    llm = _get_llm()
    result = llm.create_chat_completion(
        messages=[{"role": m.role, "content": m.content} for m in req.messages],
        max_tokens=req.max_tokens,
        temperature=req.temperature,
    )
    return {
        "id": result["id"],
        "object": "chat.completion",
        "model": req.model,
        "choices": result["choices"],
    }

@app.function(...)
@modal.asgi_app(label="gemma4-api")
def gemma4_api():
    return web_app
```

Get the web URL:
```python
f = modal.Function.from_name("gemma4-12b", "chat_completions")
print(f.get_web_url())    # https://patrisius-wr--gemma4-chat.modal.run
```

Then configure Hermes to use it (once stable):
```yaml
# hermes config set model.provider custom
# hermes config set model.base_url https://your-endpoint.modal.run
```

## Check Container Status
```python
f = modal.Function.from_name("gemma4-12b", "generate")
stats = f.get_current_stats()
# stats.num_total_runners = 1  → container is running
# stats.backlog = 0            → no pending tasks
```

## Calling a Deployed Function
```python
import modal
f = modal.Function.from_name("gemma4-12b", "generate")
result = f.remote("Your prompt here", max_tokens=1024)
```

Or via the connector script:
```bash
source ~/.venv-modal/bin/activate
python hermes_modal.py -p "Your prompt here"
```

## Key Files
- `/root/gemma4-modal.py` — Modal app definition (generate, gemma4_api w/ OpenAI-compatible endpoint)
- `/root/hermes_modal.py` — Hermes connector script
- `/root/deploy_gemma.py` — Deploy script (bypasses CLI)

## API Endpoint
Once deployed, call via OpenAI-compatible format:
```bash
curl https://patrisius-wr--gemma4-api.modal.run/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-12b","messages":[{"role":"user","content":"hello"}],"max_tokens":1024}'
```

## Hermes Integration (Subagent Delegation)

Configure delegation to route subagents (`delegate_task`) through Gemma:

```bash
hermes config set delegation.provider openai
hermes config set delegation.model gemma-4-12b
hermes config set delegation.base_url https://patrisius-wr--gemma4-api.modal.run/v1
hermes config set delegation.api_key sk-dummy   # required even if unused
hermes config set delegation.api_mode chat_completions
```

### ⚠️ Config Refresh Caveat

**CLI_CONFIG is frozen at Hermes session start.** Running `hermes config set` writes to disk, but the current session's in-memory config snapshot does NOT update. Delegation changes only take effect in a **new** session. To verify after config changes:

```bash
# Start a fresh Hermes session
hermes                           # new interactive session
# Or use a cron job to test
hermes cron create --schedule "in 1m" --prompt "Use delegate_task to test Gemma..."
```

### Resolution Path

When `delegation.base_url` is set, the provider becomes `"custom"` regardless of what `delegation.provider` says. The resolution logic in `tools/delegate_tool.py:_resolve_delegation_credentials`:

1. Checks `CLI_CONFIG.get("delegation")` first (in-memory — stale!)
2. Falls back to `hermes_cli.config.load_config()` reading disk (fresh)
3. If `base_url` is truthy → sets `provider = "custom"`, ignores `configured_provider`

Result in a fresh session:
```
model: gemma-4-12b
provider: custom          ← using custom (OpenAI-compatible) endpoint
base_url: https://patrisius-wr--gemma4-api.modal.run/v1
api_key: sk-dummy
api_mode: chat_completions
```

The `provider: custom` is correct — it means "use the base_url/api_key/api_mode as an OpenAI-compatible endpoint."

### Calling Directly

```bash
source ~/.venv-modal/bin/activate
python hermes_modal.py -p "Your prompt here"
```

## Verification

After configuring delegation, verify in a **new Hermes session**:

```bash
# Start a fresh session
hermes

# Once inside, run a subagent task
delegate_task "What is 15+15? Reply with just the number."
# Expected: subagent uses Gemma 4 (not the parent's model)
```

Or test directly that the delegation config resolves:

```bash
python3 -c "
import urllib.request, json
body = json.dumps({
  'model':'gemma-4-12b',
  'messages':[{'role':'user','content':'2+2?'}],
  'max_tokens':10
}).encode()
req = urllib.request.Request('https://patrisius-wr--gemma4-api.modal.run/v1/chat/completions', data=body, headers={'Content-Type':'application/json'}, method='POST')
resp = urllib.request.urlopen(req, timeout=600)
data = json.loads(resp.read())
print('GEMMA:', data['choices'][0]['message']['content'])
"
# WARM: Hello! → endpoint is alive
```

## Pitfalls
- `modal` CLI doesn't work on Termux (watchfiles native Rust code _rust_notify incompatible with Android Bionic)
- First inference call downloads the full GGUF model (~7.1GB for Q4_K_M) — takes ~10min
- Use `modal>=-1.4.4.dev17` (fixes config/logger circular import in 1.4.3)
- `@modal.web_endpoint` renamed to `@modal.fastapi_endpoint` (since 2025-03-05); for complex path routing prefer `@modal.asgi_app` wrapping a FastAPI `app` object
- `container_idle_timeout` renamed to `scaledown_window` (since 2025-02-24)
- `allow_concurrent_inputs=N` → use `@modal.concurrent(max_inputs=N)` decorator on the function
- `modal.FastAPIEndpoint` (note the `I`) requires fastapi installed in the container image
- **CLI_CONFIG staleness**: `hermes config set` for delegation writes to disk but doesn't update the running session's in-memory config. New Hermes invocation = new config. Use cron jobs or a fresh `hermes` process to verify delegation changes.
- **Provider resolves as "custom"**: When both `delegation.base_url` and `delegation.provider` are set, `_resolve_delegation_credentials()` enters the `base_url` branch and sets `provider = "custom"`, ignoring `delegation.provider`. This is correct behavior — `custom` means "use base_url/api_key/api_mode as an OpenAI-compatible endpoint."
- **Container warmth**: Modal idle containers get scaled down after `scaledown_window` (default 5 min). If you get timeout errors on the API, the container went cold — warm it up with a quick `curl` call first. Set `scaledown_window` higher (e.g. 600 for 10 min) if you make infrequent calls.
