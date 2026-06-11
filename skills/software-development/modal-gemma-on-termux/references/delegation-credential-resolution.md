# Delegation Credential Resolution (Internal)

Source: `tools/delegate_tool.py` in Hermes Agent.

## Resolution Chain

```python
def _resolve_delegation_credentials(cfg: dict, parent_agent) -> dict:
```

Called during `delegate_task` to determine which model/provider/endpoint
a subagent should use. `cfg` is the delegation section from config.

### Step 1: `_load_config()` — where config comes from

```python
def _load_config() -> dict:
    try:
        from cli import CLI_CONFIG
        cfg = CLI_CONFIG.get("delegation") or {}
        if cfg:        # non-empty dict → use this, skip file read
            return cfg
    except Exception:
        pass
    # Fallback: read from disk
    from hermes_cli.config import load_config
    full = load_config()
    return full.get("delegation") or {}
```

**Critical**: `CLI_CONFIG` is built at Hermes startup from `config.yaml`.
It is a frozen snapshot — `hermes config set` writes to disk but does NOT
update `CLI_CONFIG`. File fallback path reads disk fresh.

### Step 2: Resolution branches

```python
configured_provider = cfg.get("provider", "")
configured_model = cfg.get("model", "")
configured_base_url = cfg.get("base_url", "")
configured_api_key = cfg.get("api_key", "")
configured_api_mode = cfg.get("api_mode", "")

if configured_model:          # delegation.model is set
    model = configured_model   # → use it

if configured_base_url:        # delegation.base_url is set
    provider = "custom"         # ← overrides configured_provider!
    base_url = configured_base_url
    api_key = configured_api_key or ""
    api_mode = configured_api_mode or ""
    return {
        "model": model,
        "provider": "custom",     # not configured_provider!
        "base_url": base_url,
        "api_key": api_key,
        "api_mode": api_mode,
    }
```

When `delegation.provider` is `"openai"` AND `delegation.base_url` is set,
the code enters the `base_url` branch and **ignores** `configured_provider`,
returning `provider = "custom"`.

### Key Insight for Debugging

If `delegate_task` still uses the parent's model (e.g. deepseek) instead
of Gemma, it's because:

1. **Running session has stale CLI_CONFIG** — the delegation section was
   empty when the session started. Fix: start a new `hermes` session.
2. **`cfg` returned empty from both CLI_CONFIG and load_config** — the
   delegation section doesn't exist in config.yaml at all. Run `hermes config set`
   commands again.
3. **`base_url` not set** — without it, the code falls through to the
   parent agent's provider. Set `delegation.base_url`.
