---
name: firecrawl
description: Master Firecrawl skill — web scraping, search, crawling, browser interaction, and structured data extraction via Firecrawl API and CLI. Orchestrates all sub-skills and MCP tools.
allowed_tools:
  - terminal
  - execute_code
  - web_search
  - web_extract
inputs:
  - target_urls
  - search_query
  - extraction_schema
---

# Firecrawl Web Intelligence Suite

Firecrawl is your web intelligence layer — search, scrape, crawl, interact with, and extract structured data from any website at scale. This skill orchestrates the full stack:

## Two Paths

### 1. CLI Path (ad-hoc web work during agent sessions)
Install: Already installed globally as `firecrawl` v1.19.6.
API key: Set in `~/.hermes/.env` as `FIRECRAWL_API_KEY`.

Workflow: **search → scrape/map/crawl → interact**

| Step | Command | Sub-skill |
|------|---------|-----------|
| Search | `firecrawl search "query" --scrape` | `firecrawl-search` |
| Scrape URL | `firecrawl scrape <url> --format markdown` | `firecrawl-scrape` |
| Map site | `firecrawl map <url>` | `firecrawl-map` |
| Crawl | `firecrawl crawl <url>` | `firecrawl-crawl` |
| Interact | `firecrawl interact <url>` | `firecrawl-interact` |
| AI Extract | `firecrawl agent <url> --schema <json>` | `firecrawl-agent` |
| Monitor | `firecrawl monitor create <url>` | `firecrawl-monitor` |
| Parse | `firecrawl parse <url>` | `firecrawl-parse` |
| Download | `firecrawl download <url>` | `firecrawl-download` |

Output directory convention: `-o .firecrawl/<file>`

### 2. Build / Integration Path (adding Firecrawl to application code)
Sub-skills: `firecrawl-build`, `firecrawl-build-scrape`, `firecrawl-build-search`, `firecrawl-build-interact`, `firecrawl-build-onboarding`

### 3. MCP Path (native tool access)
Server `firecrawl-mcp` runs via `npx -y firecrawl-mcp`. Tools exposed:
- `firecrawl_scrape`
- `firecrawl_search`
- `firecrawl_crawl`
- `firecrawl_map`
- `firecrawl_interact`
- `firecrawl_extract`

## Quick Start Examples

**Scrape a page:**
```bash
firecrawl scrape https://example.com --format markdown
```

**Search the web:**
```bash
firecrawl search "latest AI news 2026" --scrape --limit 10
```

**Ask MCP agent to extract structured data:**
Use the `firecrawl_extract` MCP tool with a JSON schema.

## Pricing (Credit System)
- Search: 2 credits (+ 1 credit per result with `--scrape`)
- Search-feedback: refunds 1 credit
- Scrape: 1 credit per URL
- Crawl: 1 credit per page crawled
- Map: 1 credit per 500 URLs discovered
- Agent (AI extract): 2–5 min, 5+ credits
- Interact: 5 credits per session
- Parse: 1 credit
- Monitor: 10 credits + 1 per check
- Download: 1 credit per file

## Guardrails
- Always respect `robots.txt` — Firecrawl enforces this by default
- Avoid scraping PII or login-gated content
- For JS-heavy SPAs, use `--format screenshot screenshot@fullPage` or interact mode
- When in doubt about available options: `firecrawl <action> --help`
- Check credits and status: `firecrawl --status`

## Load These Sub-skills for Context
- `firecrawl-cli`: Master CLI workflow
- `firecrawl-scrape`: Single-URL scraping
- `firecrawl-search`: Web search
- `firecrawl-map`: Site mapping
- `firecrawl-crawl`: Deep crawling
- `firecrawl-interact`: Browser interaction
- `firecrawl-agent`: AI-powered structured extraction

## Reference
- [Integration architecture](references/architecture.md) — how CLI, MCP, skills, and config fit together
