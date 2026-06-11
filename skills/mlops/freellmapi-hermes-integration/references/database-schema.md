# FreeLLMAPI SQLite Database Schema

**Location:** `~/freellmapi/server/data/freeapi.db`

## Tables

### `api_keys` — Stored provider keys (encrypted)
| Column | Type | Description |
|---|---|---|
| id | INTEGER | PK |
| platform | TEXT | Provider name (google, groq, openrouter, nvidia, etc.) |
| label | TEXT | User label |
| encrypted_key | TEXT | AES-GCM encrypted key |
| iv | TEXT | Initialization vector |
| auth_tag | TEXT | Authentication tag |
| status | TEXT | `healthy`, `disabled`, or `error` |
| enabled | INTEGER | 0 or 1 |
| created_at | TEXT | ISO timestamp |
| last_checked_at | TEXT | Last health check |
| base_url | TEXT | Custom base URL (for custom providers) |

### `models` — Discovered models from each provider
| Column | Description |
|---|---|
| id | PK |
| platform | Provider name |
| model_id | Model string (e.g. `gemini-2.5-flash`) |
| display_name | Human-friendly name |
| intelligence_rank | Lower = smarter (1=best) |
| speed_rank | Lower = faster |
| enabled | 0 or 1 (1 = active in router) |
| supports_vision / supports_tools | 0 or 1 |
| rpm_limit / rpd_limit | Rate limits |
| key_id | FK to api_keys |
| paid_input_per_m / paid_output_per_m | Cost in USD per million tokens |

### `fallback_config` — Provider failover order per model
| Column | Description |
|---|---|
| model_db_id | FK to models.id |
| priority | Fallback order (lower = tried first) |
| enabled | 0 or 1 |

### `requests` — Request history (diagnostic)
| Column | Description |
|---|---|
| platform | Provider used |
| model_id | Model used |
| key_id | FK to api_keys |
| status | `success` or `error` |
| input_tokens / output_tokens | Token counts |
| latency_ms | Total latency |
| error | Error message if failed |
| ttfb_ms | Time to first byte |
| request_type | `chat`, `embed`, etc. |

### `rate_limit_cooldowns` — Provider cooldowns
| Column | Description |
|---|---|
| platform | Provider on cooldown |
| model_id | Specific model |
| key_id | FK to api_keys |
| expires_at_ms | Epoch ms when cooldown lifts |

### `rate_limit_usage` — Per-key token/request counters
| Column | Description |
|---|---|
| kind | `request` or `tokens` |
| tokens | Count for this bucket |
| created_at_ms | Epoch ms |

### `settings` — Global config
| Key | Value |
|---|---|
| `unified_api_key` | The `Bearer ***` token for /v1/ API |
| `embeddings_default_family` | Default embedding model family |

### `users` — Admin accounts
| Column | Description |
|---|---|
| email | Login email |
| password_hash | scrypt hash |

## Useful queries

```sql
-- Check all key health
SELECT platform, status, enabled, last_checked_at FROM api_keys;

-- Recent failures
SELECT platform, model_id, status, error, latency_ms, created_at
FROM requests WHERE status='error'
ORDER BY created_at DESC LIMIT 10;

-- Recent successes
SELECT platform, model_id, input_tokens, output_tokens, latency_ms, created_at
FROM requests WHERE status='success'
ORDER BY created_at DESC LIMIT 10;

-- Current cooldowns
SELECT * FROM rate_limit_cooldowns WHERE expires_at_ms > (strftime('%s','now') * 1000);

-- Count of models per provider
SELECT platform, COUNT(*) FROM models GROUP BY platform;
```
