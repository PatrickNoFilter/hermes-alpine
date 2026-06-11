# Holographic Memory — Architecture Reference

HRR-based structured fact storage with entity resolution, trust scoring, and hybrid retrieval.

## Database Schema (SQLite)

4 tables at `~/.hermes/memory_store.db`:

### `facts`
| Column | Type | Description |
|--------|------|-------------|
| fact_id | INTEGER PK | Auto-increment |
| content | TEXT UNIQUE | The fact text |
| category | TEXT | user_pref / project / tool / general |
| tags | TEXT | Comma-separated |
| trust_score | REAL | 0.0–1.0 (default 0.5) |
| retrieval_count | INTEGER | Times this fact was retrieved |
| helpful_count | INTEGER | Times rated helpful |
| created_at / updated_at | TIMESTAMP | Auto |
| hrr_vector | BLOB | Phase vector (1024-dim, binary) |

### `entities`
Auto-detected capitalized names, quoted strings, and "A aka B" patterns.

### `fact_entities`
Many-to-many link table between facts and entities.

### `facts_fts`
FTS5 virtual table for full-text search. Auto-synced via triggers.

## HRR (Holographic Reduced Representations)

Phase-encoded vectors in [0, 2π). Deterministic from SHA-256, so representations are cross-platform reproducible.

### Operations
- `encode_atom(word, dim=1024)` — hash word to phase vector
- `bind(a, b)` — phase addition — associates two concepts
- `unbind(memory, key)` — phase subtraction — retrieves bound value
- `bundle(*vectors)` — circular mean — merges into superposition

### Properties
- O(sqrt(dim)) items can be bundled before degradation (~32 items at dim=1024)
- bind produces a vector dissimilar to both inputs (quasi-orthogonal)
- unbind(bind(a, b), a) ≈ b (up to superposition noise)

### Capacity & SNR

Memory banks bundle ALL facts in a category into one HRR vector. SNR formula:

```
SNR = √(dim / n_items)
```

| n_items (per category) | SNR at dim=1024 | Effect |
|------------------------|-----------------|--------|
| ≤ 64 | ≥ 4.0 | ✅ Excellent |
| 256 | 2.0 | ⚠️ Threshold — SNR warning logged |
| 512 | 1.4 | ❌ HRR retrieval noise significant |
| 1024 | 1.0 | ❌ HRR component unreliable |

When `snr < 2.0`, a warning is logged: `"HRR storage near capacity: SNR=%.2f (dim=%d, n_items=%d). Retrieval accuracy may degrade."`

The SNR limit only affects the HRR (30%) component of hybrid retrieval. FTS5 (40%) and Jaccard (30%) are unaffected, so overall retrieval still functions — just the HRR-weighted results get noisier.

To increase capacity: raise `hrr_dim` in config (doubling dim quadruples capacity at the same SNR).

## Retrieval Pipeline

```
Query → FTS5 (limit×3 candidates) → Jaccard rerank → Trust-weighted → Top-10
```

Weight distribution (default):
- FTS5: 40%
- Jaccard: 30%
- HRR: 30% (falls back to 0% if numpy unavailable, redistributed to FTS5 60% + Jaccard 40%)

### Trust Scoring
| Event | Delta |
|-------|-------|
| New fact | 0.5 |
| Rated helpful | +0.05 |
| Rated unhelpful | -0.10 |
| Retrieval | count++ (no score change) |

Clamped to [0.0, 1.0]. Facts below `min_trust_threshold` (default 0.3) are excluded.

## Auto-Extraction (on_session_end)

The `on_session_end` hook runs when a session exits, if `auto_extract: true` in config. **Regex-only** — no LLM extraction:

```python
_PREF_PATTERNS = [
    r'\bI\s+(?:prefer|like|love|use|want|need)\s+(.+)',
    r'\bmy\s+(?:favorite|preferred|default)\s+\w+\s+is\s+(.+)',
    r'\bI\s+(?:always|never|usually)\s+(.+)',
]
_DECISION_PATTERNS = [
    r'\bwe\s+(?:decided|agreed|chose)\s+(?:to\s+)?(.+)',
    r'\bthe\s+project\s+(?:uses|needs|requires)\s+(.+)',
]
```

- Only scans user messages
- First match per message wins (single break after first match)
- Extracted as `category: user_pref` or `project`
- Truncated to 400 chars max

`sync_turn()` is intentionally `pass` — no per-turn auto-indexing.

### on_memory_write Mirror

When you call `memory(action='add')` (the built-in tool), holographic mirrors it:
```python
def on_memory_write(self, action, target, content):
    category = "user_pref" if target == "user" else "general"
    self._store.add_fact(content, category=category)
```

This means native memory writes automatically become holographic facts too.

### `fact_store`
Actions: add, search, probe, related, reason, contradict, update, remove, list

### `fact_feedback`
Actions: helpful, unhelpful (trains trust scores)
