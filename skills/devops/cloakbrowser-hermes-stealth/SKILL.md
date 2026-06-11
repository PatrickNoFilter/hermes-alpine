---
name: cloakbrowser-hermes-stealth
description: "Use when setting up CloakBrowser as Hermes' stealth browser for ARM64 Linux. Covers AGENT_BROWSER_EXECUTABLE_PATH, Python fixes, and verification."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [cloakbrowser, stealth, browser, arm64, playwright, anti-detection]
    related_skills: [hermes-agent]
---

# CloakBrowser + Hermes Stealth Browser Setup (ARM64 Linux)

## Overview

[CloakBrowser](https://github.com/CloakHQ/CloakBrowser) is a drop-in Playwright replacement with stealth anti-detection Chromium patches. On ARM64 Linux (Termux PRoot), where official Playwright browsers aren't supported, CloakBrowser automatically downloads an ARM64 Chromium binary with built-in fingerprint masking.

After setup, Hermes' `browser_*` tools use CloakBrowser's Chromium via `AGENT_BROWSER_EXECUTABLE_PATH`, passing all major bot detection tests.

## When to Use

- Setting up Hermes with a stealth browser on ARM64 Linux
- Replacing default Playwright browser with CloakBrowser for anti-detection
- Configuring `AGENT_BROWSER_EXECUTABLE_PATH` in Hermes `.env`
- Debugging CloakBrowser installation issues (pyee/greenlet)

## Installation

### 1. Install CloakBrowser

```bash
uv pip install cloakbrowser
```

### 2. Fix pyee (namespace package bug)

pyee 13+ is a namespace package without `__init__.py`. Pin to <13:

```bash
uv pip install "pyee<13"
```

If already installed, manually create `__init__.py` in pyee site-packages:
```python
# Content: from .base import EventEmitter
```

### 3. Fix greenlet (ARM64 compatibility)

greenlet 3.5 has `AttributeError: module 'greenlet' has no attribute 'greenlet'` on ARM64:

```bash
uv pip install "greenlet==3.4.0"
```

### 4. Verify binary was downloaded

```python
python3 -c "
from cloakbrowser.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=['--no-sandbox', '--disable-gpu'])
    print('CloakBrowser launched OK')
    browser.close()
"
```

Binary auto-downloads to `~/.cloakbrowser/chromium-*/chrome` on first launch.

## Configure Hermes to Use CloakBrowser

### Set AGENT_BROWSER_EXECUTABLE_PATH

Find the binary path:

```bash
ls ~/.cloakbrowser/chromium-*/chrome
```

Add to `~/.hermes/.env`:

```bash
echo 'export AGENT_BROWSER_EXECUTABLE_PATH=/root/.cloakbrowser/chromium-<VERSION>/chrome' >> ~/.hermes/.env
```

### Verify env var is loaded

```bash
echo "AGENT_BROWSER_EXECUTABLE_PATH=${AGENT_BROWSER_EXECUTABLE_PATH:-<not set>}"
```

**Note:** Hermes loads `.env` via `dotenv` on next restart. In the current session, `source ~/.hermes/.env` to activate immediately.

## Verification

### Bot detection test

Navigate to https://bot.sannysoft.com/ via `browser_navigate`. All tests should pass:

- WebDriver (New): **missing (passed)**
- WebDriver Advanced: **passed**
- Chrome: **present (passed)**
- SELENIUM_DRIVER: ok (all false)
- HEADCHR/PHANTOM tests: all **ok**

### Optional: full anti-detection suite

Visit https://fingerprint.com/demo/ for commercial-grade fingerprint testing.

## Common Pitfalls

1. **pyee 13+ namespace bug**: CloakBrowser depends on pyee which became a namespace package in v13. Install `pyee<13` to restore `EventEmitter`.

2. **greenlet 3.5 ARM64 crash**: `AttributeError: module 'greenlet' has no attribute 'greenlet'`. Pin to 3.4.0 — this is a known ARM64 issue.

3. **AGENT_BROWSER_EXECUTABLE_PATH not taking effect**: Hermes reads `.env` at startup. Source it manually in the current session: `source ~/.hermes/.env`. Or restart Hermes.

4. **Binary not found**: `ensure_binary()` downloads automatically on first `launch()`. If it fails, check network connectivity — the binary is ~389MB.

5. **--no-sandbox required**: In PRoot/container environments, Chromium needs `--no-sandbox` and `--disable-gpu` args to launch correctly.

## Verification Checklist

- [ ] `cloakbrowser` installed (`uv pip list | grep cloakbrowser`)
- [ ] `pyee<13` installed (not pyee 13+)
- [ ] `greenlet==3.4.0` pinned (not 3.5+)
- [ ] `AGENT_BROWSER_EXECUTABLE_PATH` set in `~/.hermes/.env`
- [ ] Binary exists at path (`ls` the path)
- [ ] `browser_navigate` to `https://bot.sannysoft.com/` — all tests passed
- [ ] Env var visible: `echo $AGENT_BROWSER_EXECUTABLE_PATH`
