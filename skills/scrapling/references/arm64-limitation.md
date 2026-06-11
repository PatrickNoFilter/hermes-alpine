# Scrapling Browser Fetchers — arm64 Limitation & Solutions

## Problem

Playwright and Patchright (browser automation engines used by Scrapling's `StealthyFetcher` and `DynamicFetcher`) do not support chromium on `ubuntu26.04-arm64`.

## Error

```
ERROR: Playwright does not support chromium on ubuntu26.04-arm64
ERROR: Patchright does not support chromium on ubuntu26.04-arm64
```

## Affected Features

| Feature | Status on arm64 | Status on x86_64 |
|---------|----------------|-----------------|
| `Fetcher.get()` | ✅ Works | ✅ Works |
| CSS/XPath selection | ✅ Works | ✅ Works |
| Spider framework | ✅ Works | ✅ Works |
| `StealthyFetcher` | ❌ No browser | ✅ Works |
| `DynamicFetcher` | ❌ No browser | ✅ Works |
| `scrapling extract fetch` | ❌ No browser | ✅ Works |
| `scrapling extract stealthy-fetch` | ❌ No browser | ✅ Works |

## Workaround A: HTTP Fetcher (no browser needed)

Use `Fetcher.get()` for HTTP scraping (works everywhere). The HTTP `Fetcher` class uses `curl_cffi` for TLS fingerprint impersonation — it can:
- Impersonate Chrome/Firefox TLS fingerprints
- Use stealthy headers
- Handle cookies and sessions
- Bypass basic bot detection

This covers most scraping needs without browser rendering.

## Workaround B: CloakBrowser on arm64 ✅

**CloakBrowser** (`CloakHQ/CloakBrowser`) provides a fully stealth Chromium binary for `linux-arm64` — perfect for PRoot/Termux environments.

### Install

```bash
uv venv ~/.venvs/stealth
source ~/.venvs/stealth/bin/activate
uv pip install "pyee<13" "greenlet==3.4.0" cloakbrowser

# Fix 1: pyee 13 namespace package bug (Python 3.14+)
echo "from .base import EventEmitter" > $(python3 -c "import pyee; print(pyee.__path__[0])")/__init__.py

# Binary auto-downloads on first launch (~389 MB)
python3 -c "
from cloakbrowser import launch
b = launch(headless=True, args=['--no-sandbox', '--disable-gpu'])
p = b.new_page()
p.goto('https://example.com')
print(p.title())
b.close()
"
```

### Verify

```python
# Check debug logs show stealth patches active
from cloakbrowser import launch
b = launch(headless=True, args=['--no-sandbox', '--disable-gpu'], debug=True)
# Expect: "Spoofing navigator.webdriver -> false"
# Expect: "Applying 58 CloakHQ patches..."
```

### Known Version Issues

| Problem | Fix |
|---------|-----|
| `from pyee import EventEmitter` fails (Python 3.14 namespace pkg) | Pin `pyee<13` + create `__init__.py` |
| `AttributeError: module 'greenlet' has no attribute 'greenlet'` | Pin `greenlet==3.4.0` |
| Binary download stuck in PRoot | `cloakbrowser` auto-downloads via `ensure_binary()` — needs internet |

### Hermes Integration

CloakBrowser's Chromium binary can replace Hermes' default browser backend. Hermes browser tool (`browser` toolset) uses `agent-browser` CLI (npm), not Playwright directly.

**Step 1 — Set env var in ~/.hermes/.env:**

```bash
echo 'export AGENT_BROWSER_EXECUTABLE_PATH=/root/.cloakbrowser/chromium-146.0.7680.177.3/chrome' >> ~/.hermes/.env
```
(Hermes loads .env via `dotenv` on startup — no config edit needed.)

**Step 2 — Verify Hermes → CloakBrowser integration:**

```bash
export PATH="/usr/local/lib/hermes-agent/node_modules/.bin:$PATH"
export AGENT_BROWSER_EXECUTABLE_PATH=/root/.cloakbrowser/chromium-146.0.7680.177.3/chrome
agent-browser --engine chrome --json open "https://example.com" --timeout 15000
# Expect: {"success":true,"data":{"title":"Example Domain","url":"https://example.com/"}}
```

**Note:** `browser.engine` in config.yaml only accepts `auto`, `lightpanda`, or `chrome`. Setting `engine: cloak` is rejected with a warning and falls back to `auto`. The `AGENT_BROWSER_EXECUTABLE_PATH` env var is the official (and only) way to point agent-browser at a custom Chromium binary.

### Notes
- Binary cached at `~/.cloakbrowser/chromium-146.*/chrome`
- Passes 30/30 bot detection tests (Cloudflare Turnstile, reCAPTCHA v3, FingerprintJS)
- Patches 58 C++ fingerprint sources (canvas, WebGL, audio, WebRTC, etc.)
- Supports `headless=True` and `humanize=True` (human-like mouse/keyboard)
- Uses Playwright backend internally — full Playwright API available
