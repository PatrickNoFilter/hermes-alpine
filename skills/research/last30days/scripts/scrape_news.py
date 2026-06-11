#!/usr/bin/env python3
"""
Reusable HTML news scraper for Indonesian financial/political news sites.
Usage: python3 scrape_news.py <url> [keyword1 keyword2 ...]

Fetches URL, strips scripts/style/tags, extracts text.
If keywords given, prints only content around those keywords.
"""
import urllib.request, re, sys

def fetch(url):
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}
    )
    try:
        html = urllib.request.urlopen(req, timeout=15).read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None
    
    clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
    clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
    clean = re.sub(r'<[^>]+>', ' ', clean)
    clean = re.sub(r'\s+', ' ', clean).strip()
    return clean

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 scrape_news.py <url> [keyword1 keyword2 ...]", file=sys.stderr)
        sys.exit(1)
    
    url = sys.argv[1]
    keywords = sys.argv[2:]
    
    content = fetch(url)
    if not content:
        sys.exit(1)
    
    if keywords:
        for kw in keywords:
            idx = content.lower().find(kw.lower())
            if idx > -1:
                start = max(0, idx - 200)
                end = min(len(content), idx + 800)
                print(f"\n--- '{kw}' ---")
                print(content[start:end])
        # If no keywords found, show first 2000 chars
        if not any(kw.lower() in content.lower() for kw in keywords):
            print(content[:2000])
    else:
        print(content[:3000])
