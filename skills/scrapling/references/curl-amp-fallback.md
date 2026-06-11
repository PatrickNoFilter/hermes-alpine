# Curl + AMP Fallback for JS-Heavy News Sites

When Scrapling's browser-based fetchers (StealthyFetcher, DynamicFetcher) aren't available — e.g. on **linux-arm64** where Playwright has no native binary — use this curl-based approach to extract text from JS-heavy news sites.

## Technique

Many Indonesian news sites (Katadata, Detik, Kompas, IDXChannel, Bisnis, Kontan) render article content via JavaScript. The main page served by `curl` is mostly navigation/ads. Two bypasses:

### 1. AMP URL (best for Katadata)

AMP versions serve the article body as plain HTML without JS rendering.

```bash
# Normal URL:
#   https://katadata.co.id/finansial/keuangan/6a203f119c503/...
# AMP URL suffix (same path, prefixed with /amp/):
#   https://katadata.co.id/amp/finansial/keuangan/6a203f119c503/...
```

Google AMP cache also works:
```bash
curl -sL "https://katadata.co.id/amp/finansial/..." -H "User-Agent: Mozilla/5.0"
# or via Google:
curl -sL "https://www.google.com/amp/s/katadata.co.id/amp/finansial/..."
```

After fetching, extract article body with:
```python
import re
html = result_of_curl  # as string
# Strip scripts + styles first
clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
# Then strip remaining tags
clean = re.sub(r'<[^>]+>', ' ', clean)
# Collapse whitespace
clean = re.sub(r'\s+', ' ', clean).strip()
# Find article start (often "Jakarta" or "Jakarta, CNN Indonesia")
idx = clean.find('Jakarta')
if idx is None or idx > 1500:
    idx = 0
print(clean[idx:idx+3000])
```

### 2. browser_navigate (best for IDXChannel, Kompas, Detik)

For sites that work but need JS, use browser_navigate (if Chromium/Playwright is available on the architecture) or CloakBrowser (on arm64):

```bash
# For Kompas, Detik, Bisnis.com — fetch via terminal with curl + good UA
curl -sL "https://www.detik.com/..." -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
# Then apply same HTML stripping
```

When curl alone doesn't get the article body (site blocks non-JS clients), fall back to `browser_navigate()`.

## Parallel Multi-URL Fetching

Fetch N articles in parallel using ThreadPoolExecutor + terminal():

```python
from concurrent.futures import ThreadPoolExecutor
from hermes_tools import terminal

urls = {
    "label1": "https://site1.com/article",
    "label2": "https://site2.com/article",
}

def fetch(label, url):
    cmd = f'''curl -sL "{url}" -A "Mozilla/5.0" | python3 -c "
import sys, re
html = sys.stdin.read()
clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
clean = re.sub(r'<[^>]+>', ' ', clean)
clean = re.sub(r'\\\\s+', ' ', clean).strip()
print(clean[:4000])
"'''
    r = terminal(cmd, timeout=20)
    return label, r['output']

with ThreadPoolExecutor(max_workers=len(urls)) as ex:
    futures = {ex.submit(fetch, l, u): l for l, u in urls.items()}
    for f in futures:
        label, out = f.result()
        print(f"=== {label} ===")
        print(out)
```

**Note:** The shell escaping `\\\\s+` becomes `\\s+` inside the shell, which Python receives as `\s+`. This is the correct whitespace regex.

## Indonesian News Site Notes

| Site | Amp? | Curl+strip? | browser_navigate? | Notes |
|------|------|-------------|-------------------|-------|
| Katadata | ✅ yes | ✅ (AMP) | ✅ | Use AMP path: `/amp/...` |
| Detik | ❌ no | ✅ partial | ✅ | Article body sometimes in JSON-LD `<script type="application/ld+json">` |
| Kompas | ❌ no | ⚠️ partial | ✅ | Navigation-heavy; comment body has article |
| IDXChannel | ❌ no | ❌ | ✅ | Full JS render needed |
| Bisnis.com | ❌ no | ✅ partial | ✅ | article body in `<div class="detail">` |
| Kontan | ❌ no | ✅ partial | ✅ | Strip JS, look for `.read__content` |
| Suara.com | ❌ no | ✅ yes | ✅ | Clean HTML structure, works with curl+strip |
| CNBC Indonesia | ❌ no | ❌ no JS | ✅ | Full JS render |
| Republika | ❌ no | ✅ yes | ✅ | Clean HTML |
