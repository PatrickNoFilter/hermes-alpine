---
name: scrapling
description: "Scrape web pages using Scrapling with anti-bot bypass (Cloudflare Turnstile), stealth headless browsing, spiders framework, adaptive scraping, and JavaScript rendering. Use when asked to scrape, crawl, or extract data from websites; web_fetch fails; the site has anti-bot protections; write Python code to scrape/crawl; or write spiders."
version: "0.4.8"
---

# Scrapling

Scrapling is an adaptive Web Scraping framework that handles everything from a single request to a full-scale crawl.

- Parser learns from website changes and automatically relocates elements
- Fetchers bypass anti-bot systems like Cloudflare Turnstile out of the box
- Spider framework for concurrent, multi-session crawls with pause/resume and proxy rotation
- Blazing fast — 784x faster than BS4+Lxml in text extraction benchmarks

**Requires: Python 3.10+**

## Setup (once)

```bash
python3 -m venv .venv-scrapling && source .venv-scrapling/bin/activate
pip install "scrapling[all]>=0.4.8" "scrapling[shell]>=0.4.8"
scrapling install --force   # download browser dependencies
```

**Note:** Also install `scrapling[shell]` for CLI `scrapling extract` .md output (needs `markdownify` module).

## CLI Quick Reference

```bash
# Simple HTTP → Markdown
scrapling extract get "https://example.com" page.md

# CSS selector extraction
scrapling extract get "https://blog.example.com" articles.md -s "article"

# Browser-rendered content
scrapling extract fetch "https://example.com" content.md --network-idle

# Anti-bot bypass + Cloudflare
scrapling extract stealthy-fetch "https://site.com" data.txt --solve-cloudflare -s ".result"

# Always use --ai-targeted for AI consumption (sanitizes hidden elements)
scrapling extract get "https://example.com" out.md --ai-targeted
```

## Python API Quick Reference

```python
# HTTP requests
from scrapling.fetchers import Fetcher, FetcherSession
page = Fetcher.get('https://example.com')
quotes = page.css('.quote .text::text').getall()

# Stealth browser (bypasses Cloudflare)
from scrapling.fetchers import StealthyFetcher
page = StealthyFetcher.fetch('https://site.com', headless=True, solve_cloudflare=True)

# Full browser automation
from scrapling.fetchers import DynamicFetcher
page = DynamicFetcher.fetch('https://example.com', network_idle=True)

# Spiders (full crawls)
from scrapling.spiders import Spider, Response
class MySpider(Spider):
    name = "demo"
    start_urls = ["https://example.com/"]
    async def parse(self, response: Response):
        for item in response.css('.product'):
            yield {"title": item.css('h2::text').get()}
MySpider().start()
```

## Selection Methods

```python
page.css('.quote')                              # CSS
page.xpath('//div[@class="quote"]')             # XPath
page.find_all('div', class_='quote')            # BeautifulSoup-style
page.find_by_text('quote', tag='div')           # Text search
first_quote.find_similar()                      # Similar elements
first_quote.below_elements()                    # Elements below
```

## Decision Guide

| Situation | Use |
|-----------|-----|
| Simple static page | `Fetcher.get()` or `scrapling extract get` |
| JS-rendered content | `DynamicFetcher.fetch()` or `scrapling extract fetch` |
| Cloudflare / anti-bot | `StealthyFetcher.fetch()` or `scrapling extract stealthy-fetch` |
| Large crawl with pagination | `Spider` subclass |
| Multiple requests, same session | `FetcherSession` / `StealthySession` / `DynamicSession` |

## Pitfalls
## Pitfalls

- `pip install scrapling` only installs the parser — no fetchers. Use `"scrapling[all]"` for full features.
- After install, always run `scrapling install --force` to download browsers.
- Use `--ai-targeted` flag for CLI commands to protect from prompt injection and save tokens.
- For browser commands, `--solve-cloudflare` is opt-in, not default.
- `StealthyFetcher` opens/closes browser per call. Use `StealthySession` for multiple requests.
- Use `.md` output for readability; `.txt` for clean text; `.html` only if you need raw structure.
- Browser fetchers (Dynamic/Stealthy) require Playwright/Patchright — not supported on arm64 (`ubuntu26.04-arm64`). See `references/arm64-limitation.md` for alternative: **CloakBrowser** provides a working stealth Chromium binary for linux-arm64 with full Playwright API.
- HTTP `Fetcher` works everywhere (no browser needed).

### Python API quirks (v0.4.8 — differs from docs)

- `find_by_text(text)` — takes ONLY the text string, NO `tag=` kwarg. Use CSS/XPath for tag filtering.
- `el.text` — returns element's own text. `el.get_all_text()` — returns all descendant text. **`bare_text` does NOT exist.**
- `el.attrib` — dict of attributes. **`el.attrs` does NOT exist.**
- `el.next_sibling` — **does NOT exist.** Use parent/children navigation instead.
- Response object: `page.status`, `page.headers`, `page.cookies`, `page.body` (bytes), `page.html_content` (str).

- `find_by_text(text)` takes only a text string, NOT `tag=` kwarg. Use CSS/XPath for tag filtering.
- Use `el.text` for element text, `el.get_all_text()` for all descendant text. `bare_text` does NOT exist.
- Use `el.attrib` dict for element attributes. `el.attrs` does NOT exist.
- `next_sibling` / `prev_sibling` do NOT exist on Selector. Use parent + CSS/XPath for sibling traversal.
- If you need similar element detection, use `el.find_similar()` (this one does exist and works).

## Tested Features (v0.4.8)

| Feature | Status | Notes |
|---------|--------|-------|
| CLI `scrapling extract get` | ✅ | Works with .md, .txt, .html output |
| CLI CSS selector (`-s`) | ✅ | Extracts all matches |
| CLI `--ai-targeted` | ✅ | Sanitizes hidden elements |
| Python `Fetcher.get()` | ✅ | HTTP with TLS impersonation |
| CSS selectors | ✅ | `.css('.class::text').getall()` |
| XPath selectors | ✅ | `.xpath('//div/text()').getall()` |
| `find_all()` BS-style | ✅ | `find_all('span', class_='text')` |
| Chained selectors | ✅ | `page.css('.parent').css('.child::text')` |
| Parent navigation | ✅ | `el.parent` |
| `text` / `get_all_text()` | ✅ | Element text extraction |
| `attrib` dict | ✅ | Element attributes |
| `html_content` | ✅ | Full HTML string |
| `FetcherSession` | ✅ | Persistent cookies/headers |
| Spider framework | ✅ | Concurrent crawl, pagination |
| `result.items.to_json()` | ✅ | JSON export |
| `result.items.to_jsonl()` | ✅ | JSONL export |
| StealthyFetcher | ⚠️ | Requires Playwright. For arm64: use CloakBrowser instead |
| DynamicFetcher | ⚠️ | Requires Playwright. For arm64: use CloakBrowser instead |

## References

- `references/fetching/` — All fetcher classes, session management, proxy rotation
- `references/parsing/` — Selection, navigation, adaptive scraping, text processing
- `references/spiders/` — Spider architecture, templates, sessions, advanced features
- `references/mcp-server.md` — MCP server for AI-assisted scraping
- `references/migrating_from_beautifulsoup.md` — BS4 → Scrapling API mapping
- `references/arm64-limitation.md` — arm64 workarounds (CloakBrowser, HTTP fallback)
- `references/curl-amp-fallback.md` — curl + AMP bypass for JS-heavy news sites (alternative when browser fetchers unavailable; arm64-safe)
- Full docs: https://scrapling.readthedocs.io/en/latest/
