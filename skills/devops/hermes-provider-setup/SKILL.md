---
name: hermes-provider-setup
description: "Add or configure an external LLM API provider in Hermes — verify keys, test endpoints, meet the 64K minimum context requirement, and wire into .env + config.yaml."
version: 1.0.0
author: agent
platforms: [linux, macos]
tags: [hermes, providers, configuration, api-keys, groq, openai-compatible]
---

# Hermes Provider Setup

When the user gives you an API key for a new provider, follow this workflow to validate and configure it.

## 1. Identify the Provider

API key prefixes help disambiguate:

| Prefix | Likely provider | Endpoint |
|--------|---------------|----------|
| `sk-or-v1-` | OpenRouter | `https://openrouter.ai/api/v1` |
| `sk-ant-` | Anthropic | `https://api.anthropic.com/v1` |
| `gsk_` | **Groq** (not Grok!) | `https://api.groq.com/openai/v1` |
| `xai-` | xAI / Grok | `https://api.x.ai/v1` |
| `sk-proj-` | OpenAI | `https://api.openai.com/v1` |
| `AIzaSy` | Google Gemini | `https://generativelanguage.googleapis.com/v1` |
| `hf_` | Hugging Face | `https://api-inference.huggingface.co/models` |

**Common confusion:** `gsk_*` keys from tokengratis.id are often labeled "Grok" but are actually **Groq** keys. Test against both endpoints to confirm.

## 2. Test the Key

```bash
# OpenAI-compatible (Groq, OpenRouter, etc.)
curl -s https://api.groq.com/openai/v1/models \
  -H "Authorization: Bearer $KEY" | python3 -c "import json,sys; data=json.load(sys.stdin); [print(m['id'], 'ctx='+str(m.get('context_window','?'))) for m in data.get('data',[])]"

# OpenRouter key/session metadata (does not require a chat call)
curl -s https://openrouter.ai/api/v1/auth/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"

# xAI / Grok
curl -s https://api.x.ai/v1/models \
  -H "Authorization: Bearer $KEY"
```

A 400 "Incorrect API key" means wrong endpoint. A 200 with model list (or OpenRouter `/auth/key` metadata) means you found the right one.

For OpenRouter free-tier/Hermes integration details, see `references/openrouter-free-tier-hermes.md`.

## 3. Check Context Length Against Hermes Minimum

Hermes requires **`MINIMUM_CONTEXT_LENGTH = 64_000`** (defined in `agent/model_metadata.py`).

Models below 64K context are rejected. Common Groq models and their context:

| Model | Context | Hermes OK? |
|-------|---------|-----------|
| `groq/compound` | 131K | ✅ |
| `groq/compound-mini` | 131K | ✅ |
| `llama-3.3-70b-versatile` | 131K | ✅ |
| `llama-3.1-8b-instant` | 131K | ✅ |
| `qwen/qwen3-32b` | 131K | ✅ |
| `allam-2-7b` | 4K | ❌ |
| Whisper / prompt-guard models | <1K | ❌ (not for chat anyway) |

## 4. Add to .env

```bash
# Add the env var (use the standard name from Hermes providers table)
echo 'GROQ_API_KEY=gsk_your_key_here' >> ~/.hermes/.env
```

Common provider env var names (from `hermes-agent` skill provider table):
- Groq → `GROQ_API_KEY`
- xAI/Grok → `XAI_API_KEY`
- OpenRouter → `OPENROUTER_API_KEY`
- etc.

For a custom OpenAI-compatible provider, you can set it via config:
```bash
hermes config set providers.custom_<name>.base_url <url>
hermes config set providers.custom_<name>.api_key env://CUSTOM_KEY_ENV_VAR
```

## 5. Switch Hermes to the New Provider

```bash
# Set provider and model
hermes config set model.provider xai
hermes config set model.default grok-3
```

For OpenRouter free-tier repair, prefer this stable baseline unless the user requested a paid/specific model:

```bash
hermes config set model.provider openrouter
hermes config set model.default openrouter/free
hermes config set model.base_url https://openrouter.ai/api/v1
hermes config set model.api_mode chat_completions
```

Then verify with `hermes status --all` and a fresh `hermes chat -q 'Reply with exactly: ...' --toolsets safe --quiet` run. If multiple credentials exist, use `hermes auth list openrouter` and test each credential against OpenRouter `/auth/key` without printing secrets.

Or set up as delegation model:
```bash
hermes config set delegation.provider groq
hermes config set delegation.model llama-3.3-70b-versatile
```

## Pitfalls

- **Key format ≠ provider identity.** `gsk_` = Groq, not Grok. Always test against the actual endpoint.
- **OpenRouter free-tier 402 can be output-budget, not auth.** If OpenRouter returns a credit error mentioning a huge requested `max_tokens` (for example 65536), the key may still be valid. Verify `/auth/key`, then use `openrouter/free`, reduce output budget if configurable, or switch to a paid key/model.
- **Specific OpenRouter `*:free` models can rate-limit upstream.** For a default Hermes free-tier config, `openrouter/free` is often more robust than pinning a specific free model because OpenRouter can route around temporarily limited upstreams.
- **Credential pools can mask which key is active.** `hermes auth list openrouter` shows env-backed and manual credentials; when repairing, validate each credential against `/auth/key` while redacting full token values.
- **Minimum context guard is hardcoded.** Even if a model works, Hermes won't use it if it reports <64K context_window. Check the models list response.
- **Whisper and embedding models** on Groq have tiny context (448-512). These are NOT for chat — filter them out.
- **`k` vs `K` suffix context.** Some providers report context_window as raw number (e.g., 131072), not abbreviated. 64K = 65536.
- **`hermes config` can time out** on ARM/PRoot. Read `config.yaml` directly with `read_file` instead.
- **After adding key to .env**, run `/reload` in-session or restart Hermes for the change to take effect.
