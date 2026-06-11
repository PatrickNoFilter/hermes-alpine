#!/usr/bin/env python3
"""
translate.py — Free translation via DeepLX (primary) + Google Translate (fallback).
Usage: python3 translate.py "Hello world" en id
       python3 translate.py --file article.txt en id
       echo "Hello" | python3 translate.py - en id
"""
import sys, json, urllib.parse, subprocess, time, os

DEEPLX_URL = "http://localhost:1188/translate"
GOOGLE_URL = "https://translate.googleapis.com/translate_a/single?client=gtx"

def translate_deeplx(text, source='EN', target='ID'):
    """Translate via DeepLX (best quality, no API key)."""
    # DeepLX uses UPPERCASE codes
    src = source.upper()
    tgt = target.upper()
    payload = json.dumps({"text": text[:4900], "source_lang": src, "target_lang": tgt})
    tmpfile = f"/tmp/tr_{os.getpid()}.json"
    with open(tmpfile, 'w') as f:
        f.write(payload)
    try:
        result = subprocess.run(['curl', '-s', '--max-time', '30', DEEPLX_URL,
                                '-H', 'Content-Type: application/json', f'-d', f'@{tmpfile}'],
                               capture_output=True, text=True, timeout=35)
        os.unlink(tmpfile)
        data = json.loads(result.stdout)
        if data.get('code') == 200:
            return data.get('data', '')
    except:
        pass
    return None

def translate_google(text, source='en', target='id'):
    """Fallback: Google Translate free API."""
    encoded = urllib.parse.quote(text[:4900])
    url = f"{GOOGLE_URL}&sl={source}&tl={target}&dt=t&q={encoded}"
    result = subprocess.run(['curl', '-s', '--max-time', '10', url],
                           capture_output=True, text=True, timeout=15)
    data = json.loads(result.stdout)
    return ''.join(seg[0] for seg in data[0] if seg[0])

def translate(text, source='en', target='id'):
    """Translate with automatic fallback."""
    # Try DeepLX first
    result = translate_deeplx(text, source, target)
    if result:
        return result, "deeplx"
    # Fallback to Google
    result = translate_google(text, source, target)
    return result, "google"

def translate_long(text, source='en', target='id', chunk_size=3500):
    """Translate long text by chunking into paragraphs."""
    paragraphs = [p.strip() for p in text.split('\n\n') if p.strip()]
    chunks, current = [], ""
    for p in paragraphs:
        if len(current) + len(p) > chunk_size:
            if current: chunks.append(current)
            current = p
        else:
            current = current + "\n\n" + p if current else p
    if current: chunks.append(current)

    translations = []
    for i, chunk in enumerate(chunks):
        try:
            result, engine = translate(chunk, source, target)
            translations.append(result)
            print(f"  [{i+1}/{len(chunks)}] OK ({engine})", file=sys.stderr)
        except Exception as e:
            translations.append(f"[FAILED chunk {i+1}]")
            print(f"  [{i+1}/{len(chunks)}] FAILED: {e}", file=sys.stderr)
        if i < len(chunks) - 1:
            time.sleep(0.5)
    return "\n\n".join(translations)

def main():
    if len(sys.argv) < 4:
        print("Usage: translate.py <text|--file|-|@file> <source_lang> <target_lang>", file=sys.stderr)
        print("  Example: translate.py 'Hello world' en id", file=sys.stderr)
        print("  Example: translate.py --file article.txt en id", file=sys.stderr)
        print("  Example: echo 'Hello' | translate.py - en id", file=sys.stderr)
        sys.exit(1)

    source_text = sys.argv[1]
    source_lang = sys.argv[2]
    target_lang = sys.argv[3]

    if source_text == '-':
        text = sys.stdin.read()
    elif source_text.startswith('--file='):
        with open(source_text[7:]) as f:
            text = f.read()
    elif source_text.startswith('--file'):
        with open(sys.argv[2]) as f:
            text = f.read()
        source_lang = sys.argv[3]
        target_lang = sys.argv[4]
    elif source_text.startswith('@'):
        with open(source_text[1:]) as f:
            text = f.read()
    else:
        text = source_text

    result = translate_long(text, source_lang, target_lang)
    print(result)

if __name__ == '__main__':
    main()
