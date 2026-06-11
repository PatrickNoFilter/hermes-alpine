# DuckDuckGo Lite Fallback (for when last30days has no API keys)

When `last30days` returns no results because API keys are missing
(Reddit 403, no Brave/Serper/OpenAI keys), use this fallback.

## Step 1 — Search with DuckDuckGo Lite (POST)

```bash
curl -s -L -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  --data "q=your+search+terms" \
  "https://lite.duckduckgo.com/lite/" \
  | sed -n '/<a rel="nofollow" href="/p'
```

Key: must use POST, not GET — Lite mode won't serve results via GET.

For Indonesian-focused searches, add `&kl=id-id` to the POST data.

## Step 2 — Fetch article content

```bash
curl -s -L -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  "ARTICLE_URL" | python3 -c "
import sys, re
html = sys.stdin.read()
clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
clean = re.sub(r'<[^>]+>', ' ', clean)
clean = re.sub(r'\\s+', ' ', clean).strip()
print(clean[:5000])
"
```

## Step 3 — Python script (cleaner alternative)

Save as `/tmp/ddg_search.py` and reuse across queries:

```python
import urllib.request, re, sys, html
from urllib.parse import quote

query = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else "default query"
params = {'q': query}
data = urllib.parse.urlencode(params).encode()

req = urllib.request.Request('https://lite.duckduckgo.com/lite/',
    data=data,
    headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) ...',
             'Content-Type': 'application/x-www-form-urlencoded'})

html_page = urllib.request.urlopen(req, timeout=15).read().decode('utf-8', errors='replace')

seen = set()
for m in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*class="[^"]*result-link[^"]*"[^>]*>', html_page):
    url = m.group(1)
    if url not in seen:
        seen.add(url)
        print(url)
# Also grab title+url for matched domains
for m in re.finditer(r'<a[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>', html_page):
    url = m.group(1)
    title = re.sub(r'<[^>]+>', '', m.group(2)).strip()
    if any(k in url for k in ['.detik.', '.kompas.', '.cnbc', '.kontan.', '.bisnis.']):
        if url not in seen and len(title) > 10:
            seen.add(url)
            print(f"{title[:100]}\n  {url}")
```

Usage: `python3 /tmp/ddg_search.py "politik ekonomi indonesia 2026"`

## Step 4 — Parallel batch fetch (speed)

For 3+ articles, use Python ThreadPoolExecutor:

```python
from concurrent.futures import ThreadPoolExecutor

articles = [
    ("label1", "https://finance.detik.com/..."),
    ("label2", "https://finance.detik.com/..."),
]

def fetch(label, url):
    # same curl|python3 parsing from Step 2
    ...

with ThreadPoolExecutor(max_workers=3) as ex:
    futures = {ex.submit(fetch, l, u): l for l, u in articles}
    for f in futures:
        l, out = f.result()
        print(f"\n=== {l} ===")
        print(out[:3000])
```

## Step 5 — Gap analysis

After collecting sources, explicitly track what's verified vs missing:

```markdown
| Source | Status | Notes |
|--------|--------|-------|
| ✅ [Article Title] | Terverifikasi | Detik, 6 Juni 2026 |
| ❌ Specific data point | Belum ditemukan | What to search for next |
```

## Sources that work (with proper UA)
- Lite DuckDuckGo (search) — POST method, GET doesn't work
- **detikFinance** — works well, easy to parse
- **detikBursa** — works well
- Kompas.com (non-paywall articles only — paywall returns "Halaman tidak ditemukan")
- Katadata.co.id, IDXChannel.com, MediaKampung.com
- Kontan.co.id (sometimes Cloudflare-blocked)
- Kompas.id (English section visible, Indonesian behind paywall)
- KompasTV.com (works)

## Indonesian news parsing tip

Indonesian news articles typically start body text with "Jakarta" or "Jakarta, CNBC Indonesia" or city name. Use this as anchor:

```python
idx = clean.find('Jakarta')
if idx < 0 or idx > 1000: idx = 0
print(clean[idx:idx+3000])
```

## Sources that block
- CNBC Indonesia (403 — requires proper session)
- Reuters (401)
- Investing.com (403)
- Bisnis.com/BisnisPro (paywall/CloudFront)
- Kompas.com paywall articles ("Halaman tidak ditemukan")
- Google Search (blocks direct curl — use DDG Lite instead)
