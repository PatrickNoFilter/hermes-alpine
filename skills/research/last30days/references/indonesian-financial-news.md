# Indonesian Financial & Political News Sources

## Working Sources (ARM64 / no Playwright)

These news sites serve server-rendered HTML that can be scraped directly with Python `urllib.request` + regex, no browser needed.

### Kompas.com
- Article pages: `https://www.kompas.com/tag/{topic}` — topic tag pages list articles
- Search: append `?query={terms}` to tag URL
- Patterns: Articles wrapped in `<div class="article__...">` with linked headlines
- Note: Kompas.com+ paywalled articles show first paragraph only. Tag pages are free.

### Detik Finance
- Main: `https://finance.detik.com/`
- By tag: `https://finance.detik.com/indeks?tag={term}` (e.g. `danantara`)
- Article pattern: `/bursa-dan-valas/d-{number}/{slug}` and `/berita/d-{number}/{slug}`
- Detik uses no significant anti-bot protection on article pages. Navigation-heavy homepage — use direct article URLs or tag-based search.

### CNBC Indonesia
- Search: `https://www.cnbcindonesia.com/search?query={terms}`
- Article pattern: `https://www.cnbcindonesia.com/news/{date}-{id}/...`
- Note: Search results page renders via JS — use direct URL patterns for specific articles when possible.
- Avoid: `/indeks/berita` endpoints (404 from bots half the time).

### Kontan.co.id
- Search: `https://investasi.kontan.co.id/search?q={terms}` (investasi subdomain)
- Also: `https://industri.kontan.co.id/search?q={terms}` for industry/energy
- Article pattern: `https://investasi.kontan.co.id/news/{slug}`
- Note: Search pages load server-rendered HTML. Some technical articles paywalled.

### Bisnis.com
- Search: `https://www.bisnis.com/search?q={terms}&sort=date`
- Article pattern: `https://www.bisnis.com/{category}/read/{date}/{slug}`
- Market subdomain: `https://market.bisnis.com/`

### Antara News
- National news wire — wide coverage, no paywall.
- Search: `https://www.antaranews.com/search?q={terms}`
- Article pages clean, easy to scrape.

### Republika
- `https://ekonomi.republika.co.id/` — economy subdomain
- Tag: `https://ekonomi.republika.co.id/indeks?tag={term}`
- Article pattern: `/berita/{id}/{slug}`

### Katadata.co.id
- Strong economic data focus. Some articles behind soft paywall.
- Search: `https://katadata.co.id/search?q={terms}`

## Scraping Approach

### Recommended: Python Script (no shell escaping issues)

```python
import urllib.request, re

def fetch_article(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
    html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", errors="replace")
    clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
    clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
    clean = re.sub(r'<[^>]+>', ' ', clean)
    clean = re.sub(r'\s+', ' ', clean).strip()
    return clean
```

### Extract URLs from Google Search
```python
# Use this approach when you have google search HTML
import re
urls = re.findall(r'href="/url\?q=(https?://[^&"]+)', html)
for u in urls[:15]:
    decoded = u.replace('%3F','?').replace('%3D','=').replace('%26','&').replace('%2F','/')
    print(decoded)
```

### Extract Article URLs from Search Results Page
```python
# For most Indonesian news sites
links = re.findall(r'href="(https?://[^"]+)"', html)
for l in links:
    if any(kw in l.lower() for kw in ['danantara', 'ihsg', 'rupiah', ...]):
        print(l)
```

## Parallel Fetching

For researching financial/political topics where context changes rapidly (IHSG, forex, policy announcements), always fetch from 3-4 sources in parallel to triangulate. Use `concurrent.futures.ThreadPoolExecutor`.

See also: `scripts/scrape_news.py` in this skill directory for a reusable scraper.

## Sources With Anti-Bot Protection (usually blocked)

- **Google search** — blocks simple curl requests
- **Yahoo Finance Indonesia** — JS-rendered
- **Bloomberg** — paywalled
- **Reuters individual articles** — sometimes blocks

## Topic-Specific Source Maps

| Topic | Best Sources |
|-------|-------------|
| IHSG / Capital market | CNBC Indonesia (market), Kontan (investasi), Detik Finance |
| Rupiah / forex | BI website, Kontan, CNBC |
| DSI / Danantara | Kompas, Detik Finance, CNBC Indonesia |
| Fiscal policy / APBN | Katadata, Kontan, Antara |
| Commodity exports | Bisnis.com, Kontan (industri), Republika |
| Global context | Reuters (if accessible), Antara (AP/NHK relay) |
