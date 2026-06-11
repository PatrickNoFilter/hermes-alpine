# Fetchers basics

## Introduction
Fetchers are classes that do requests or fetch pages in a single-line fashion with many features and return a Response object. All fetchers have separate session classes to keep the session running (e.g., a browser fetcher keeps the browser open until you finish all requests).

Fetchers are not wrappers built on top of other libraries. They use these libraries as an engine to request/fetch pages but add features the underlying engines don't have, while still fully leveraging and optimizing them for web scraping.

## Fetchers Overview

Scrapling provides three different fetcher classes with their session classes; each fetcher is designed for a specific use case.

| Feature            | Fetcher                          | DynamicFetcher                       | StealthyFetcher                          |
|--------------------|----------------------------------|--------------------------------------|------------------------------------------|
| Relative speed     | 🐇🐇🐇🐇🐇                        | 🐇🐇🐇                                | 🐇🐇🐇                                    |
| Stealth            | ⭐⭐                               | ⭐⭐⭐                                  | ⭐⭐⭐⭐⭐                                   |
| Anti-Bot options   | ⭐⭐                               | ⭐⭐⭐                                  | ⭐⭐⭐⭐⭐                                   |
| JavaScript loading | ❌                                | ✅                                    | ✅                                       |
| Memory Usage       | ⭐                                | ⭐⭐⭐                                  | ⭐⭐⭐                                     |
| Best used for      | Basic scraping when HTTP alone   | Dynamic sites, small automation, small-mid protections | Dynamic sites, automation, complicated protections |
| Browser(s)         | ❌                                | Chromium and Google Chrome            | Chromium and Google Chrome               |
| Browser API used   | ❌                                | Playwright                            | Playwright                               |

## Parser configuration in all fetchers
```python
from scrapling.fetchers import Fetcher
Fetcher.configure(adaptive=True, keep_comments=False)
# or
Fetcher.adaptive = True
```

## Response Object
```python
page = Fetcher.get('https://example.com')
page.status          # HTTP status code
page.reason          # Status message
page.cookies         # Response cookies
page.headers         # Response headers
page.request_headers # Request headers
page.history         # Redirect history
page.body            # Raw response body (bytes)
page.encoding        # Response encoding
page.meta            # Response metadata
page.captured_xhr    # Captured XHR/fetch responses
```

See `references/fetching/` for detailed docs on each fetcher class.