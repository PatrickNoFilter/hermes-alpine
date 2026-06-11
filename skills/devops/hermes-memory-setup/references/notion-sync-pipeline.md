# Holographic → Notion Sync Pipeline

## Overview

Periodic (every-1h) cold-storage backup of holographic memory facts to Notion Hermes Vault. Zero LLM cost — runs as `no_agent=True` cron job.

## Architecture

```
Holographic memory_store.db  ──read──▶  sync script  ──PATCH──▶  Notion Vault page
                                          │
                                     fact_id tracker
                                    (state JSON file)
```

## State File

`~/.hermes/state/holographic_notion_sync.json`:

```json
{
  "last_synced_fact_id": 9,
  "last_synced_at": "2026-06-03T10:17:24.968564+00:00",
  "total_synced": 9
}
```

- `last_synced_fact_id`: the highest `fact_id` that was synced. Script only fetches facts with `fact_id > this value`.
- `total_synced`: cumulative counter for dashboard/stat purposes.

## Dedup Strategy

Two-layer dedup:

1. **fact_id tracking** — only fetches facts with `fact_id > last_synced`. Handles the steady-state case (most runs sync 0 facts).
2. **Content dedup** — fetches all existing block `plain_text` from the Notion page and compares with each fact's content. Handles edge cases: script reset, state file loss, manual edits.

## Notion API Details

- **Method**: `PATCH /v1/blocks/{page_id}/children` (append children)
- **Version**: `2025-09-03`
- **Batch size**: 10 blocks per call (well under rate limit)
- **Block type**: `bulleted_list_item` with `[category] content` format
- **Heading**: `Holographic Memory` (heading_2) — auto-created if missing

## Env Variable Discovery

The script tries these in order:
1. `env.get("NOTION_API_KEY")` — from `~/.hermes/.env`
2. `os.environ.get("NOTION_API_KEY")` — from process env
3. `env.get("NOTION_TOKEN")` — alternative name
4. `os.environ.get("NOTION_TOKEN")` — alternative name

## Cron Setup

Using `cronjob(action='create')`:

| Field | Value |
|-------|-------|
| name | `holographic-to-notion-sync` |
| schedule | `every 1h` |
| script | `sync-holographic-to-notion.py` |
| no_agent | `true` |
| deliver | `local` |

The `no_agent=true` mode means the scheduler runs the Python script directly and delivers its stdout verbatim. If the script produces no output (no new facts), nothing is delivered.

## Manual Run

```bash
python3 ~/.hermes/scripts/sync-holographic-to-notion.py
```

Use before destructive operations (memory reset, config change). Also useful for initial backfill — just run once and all existing facts are synced.

## Limitations

- **Append-only**: No delete/update propagation. If a fact is removed from holographic, the Notion copy persists.
- **One-directional**: Hot store = holographic (local SQLite, fast), cold archive = Notion (cloud, slow). Queries always hit holographic.
- **Notion 2000-char limit**: `rich_text[].text.content` maxes at 2000 chars. Facts are truncated to this. (Normal holographic facts are <500 chars.)
- **Rate limits**: Notion permits 3 req/s. Batches of 10 blocks/call are fine at 1h intervals.
- **No pagination for vault page**: For large vault pages (1000+ blocks), the full-page fetch could be slow. Not a problem at current scale.
