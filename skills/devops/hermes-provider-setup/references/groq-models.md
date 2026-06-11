# Groq API Model Reference

Captured: 2026-06-03. Groq API at `https://api.groq.com/openai/v1`.

## Chat/LLM Models (≥64K context, Hermes-compatible)

| Model | Context | Type |
|-------|---------|------|
| `groq/compound` | 131K | Flagship compound reasoning |
| `groq/compound-mini` | 131K | Smaller compound |
| `llama-3.3-70b-versatile` | 131K | Meta Llama 3.3 70B |
| `llama-3.1-8b-instant` | 131K | Meta Llama 3.1 8B (fast) |
| `meta-llama/llama-4-scout-17b-16e-instruct` | 131K | Llama 4 Scout 17B |
| `qwen/qwen3-32b` | 131K | Qwen 3 32B |
| `openai/gpt-oss-120b` | 131K | GPT-OSS 120B |
| `openai/gpt-oss-20b` | 131K | GPT-OSS 20B |
| `openai/gpt-oss-safeguard-20b` | 131K | GPT-OSS Safeguard |

## Non-Chat Models (DO NOT use as LLM provider)

| Model | Context | Purpose |
|-------|---------|---------|
| `allam-2-7b` | 4K | Arabic LLM (too small ctx) |
| `canopylabs/orpheus-*` | 4K | TTS |
| `whisper-large-v3*` | 448 | Speech-to-text |
| `meta-llama/llama-prompt-guard-*` | 512 | Prompt injection guard |

## Key Facts

- Groq API keys start with `gsk_` — commonly confused with xAI/Grok keys.
- All usable LLM models report 131072 context (well above Hermes' 64K minimum).
- Groq is OpenAI-compatible — works as a drop-in replacement via `base_url`.
- Rate limits vary by model and account tier. Check Groq console for current limits.
