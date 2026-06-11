# OpenRouter Free-Tier Hermes Integration Notes

Use when repairing or configuring Hermes to run through OpenRouter, especially free-tier keys.

## Observed durable pattern

Hermes can be configured directly for OpenRouter with:

```yaml
model:
  provider: openrouter
  default: openrouter/free
  base_url: https://openrouter.ai/api/v1
  api_mode: chat_completions
```

`openrouter/free` is a safer default for free-tier OpenRouter keys than pinning a specific free model, because specific `*:free` upstreams may rate-limit or fail while the router can choose an available free backend.

## Verification sequence

1. Confirm key exists without printing it:
   - inspect `.env` for `OPENROUTER_API_KEY` presence, length, prefix/suffix only.
2. Validate the key:
   - `GET https://openrouter.ai/api/v1/auth/key` with `Authorization: Bearer $OPENROUTER_API_KEY`.
   - Expected: HTTP 200 and JSON `data` object.
3. Check free models and context when needed:
   - `GET https://openrouter.ai/api/v1/models`.
   - Filter for model IDs containing `:free` or zero prompt/completion pricing, and context >= 65536.
4. Verify Hermes provider state:
   - `hermes status --all` should show Provider `OpenRouter` and the configured model.
5. Verify a fresh Hermes session:
   - `hermes chat -q 'Reply with exactly: ...' --toolsets safe --quiet`.

## Credential-pool check

Hermes may have multiple OpenRouter credentials in `~/.hermes/auth.json` under `credential_pool.openrouter`, plus an env-backed key. Use:

```bash
hermes auth list openrouter
```

For deeper repair, test each credential against `/auth/key` while redacting token output. Do not print full tokens.

## Pitfall: max_tokens vs free credits

OpenRouter free-tier keys can fail with HTTP 402 if Hermes requests a very large `max_tokens` budget (example seen: requested 65536, affordable 33333). This is not necessarily a bad key. Repair options:

- use `openrouter/free` for default free routing;
- reduce max-output settings if the provider path exposes them;
- use a paid OpenRouter key for high-output sessions.
