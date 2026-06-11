# Firecrawl Integration Architecture

## How the pieces fit together

```
┌──────────────────────────────────────────────────────────────┐
│                    .env                                      │
│  FIRECRAWL_API_KEY=fc-...  ← single source of truth         │
└────┬─────────────────────────────────────────────────────┬───┘
     │                                                     │
     ▼                                                     ▼
┌─────────────┐                              ┌─────────────────────┐
│ CLI (npm)   │                              │ MCP Server (npx)    │
│ firecrawl   │                              │ firecrawl-mcp       │
│ v1.19.6     │                              │                     │
│             │                              │ Exposes tools:      │
│ Commands:   │                              │ scrape, search,     │
│ scrape      │                              │ crawl, map,         │
│ search      │                              │ interact, extract   │
│ crawl       │                              └─────────┬───────────┘
│ map         │                                        │
│ interact    │                              ┌─────────┴───────────┐
│ agent       │                              │ Hermes config.yaml  │
│ monitor     │                              │ mcp_servers:        │
│ parse       │                              │   firecrawl: {...}  │
│ download    │                              └─────────────────────┘
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ ~/.hermes/skills/firecrawl*/SKILL.md  (16 skills)                │
│                                                                  │
│ firecrawl/         ← master orchestrator (load first)            │
│ firecrawl-cli/     ← CLI workflow reference                     │
│ firecrawl-scrape/  ← scrape specific URLs                       │
│ firecrawl-search/  ← web search + feedback pattern              │
│ firecrawl-crawl/   ← bulk site extraction                       │
│ firecrawl-map/     ← URL discovery                              │
│ firecrawl-interact/ ← browser interaction                       │
│ firecrawl-agent/   ← AI structured extraction                   │
│ firecrawl-monitor/ ← scheduled change detection                 │
│ firecrawl-parse/   ← local file parsing (PDF, DOCX, etc.)       │
│ firecrawl-download/ ← full site download                        │
│ firecrawl-build*/  ← app-integration skills                     │
└──────────────────────────────────────────────────────────────────┘
```

## Key URLs

- **API endpoint**: `https://api.firecrawl.dev/v1/`
- **Docs**: `https://docs.firecrawl.dev/`
- **Dashboard**: `https://www.firecrawl.dev/dashboard`
- **GitHub (skills)**: `https://github.com/firecrawl/skills`
- **GitHub (CLI skills)**: `https://github.com/firecrawl/cli/tree/main/skills`

## Verified CLI Behavior (v1.19.6)

| You might think | Actual command |
|---|---|
| `firecrawl --credits` | `firecrawl --status` |
| `firecrawl scrape --formats` | `firecrawl scrape --format` |
| `firecrawl credit-usage` | `firecrawl credit-usage` (separate command) |

## How to verify integration

```bash
# Check auth + credits
firecrawl --status

# Test scrape
firecrawl scrape https://httpbin.org/get --format markdown

# Test search
firecrawl search "test query" --limit 2 --json -o .firecrawl/test.json

# Check MCP server is registered
grep -A4 'firecrawl:' ~/.hermes/config.yaml
```

## Quick facts

- **API key location**: `~/.hermes/.env` → `FIRECRAWL_API_KEY=...`
- **CLI install**: `npm install -g firecrawl-cli`
- **MCP server**: Added to `config.yaml` under `mcp_servers.firecrawl`
- **Skills source**: Upstream from `firecrawl/cli` and `firecrawl/skills` repos
- **Credits**: 1,024 / 1,000 (as of setup), refundable via search-feedback
