# Translation API Reference

## DeepLX (Primary)

- **Source:** [OwO-Network/DeepLX](https://github.com/OwO-Network/DeepLX) (8.5k⭐)
- **Binary:** `/usr/local/bin/deeplx`
- **Port:** 1188
- **Start:** `deeplx -p 1188` (auto-starts with OPSEC)
- **Endpoint:** `POST http://localhost:1188/translate`
- **Lang codes:** UPPERCASE (EN, ID, ZH, JA, etc.)
- **Limit:** ~5000 chars/request

### Request Format
```json
{"text": "Hello", "source_lang": "EN", "target_lang": "ID"}
```

### Response Format
```json
{"code": 200, "data": "Halo", "method": "Free", "source_lang": "EN", "target_lang": "ID"}
```

## Google Translate (Fallback)

- **Endpoint:** `GET https://translate.googleapis.com/translate_a/single?client=gtx`
- **Lang codes:** lowercase (en, id, zh, etc.)
- **Limit:** ~5000 chars/request
- **No auth needed**

### Request
```
?sl=en&tl=id&dt=t&q=Hello+world
```

### Response
```json
[[["Halo dunia","Hello world",null,null,10]],null,"en"]
```

## MyMemory (Fallback 2)

- **Endpoint:** `GET https://api.mymemory.translated.net/get`
- **Lang codes:** lowercase with pipe separator (en|id)
- **Limit:** ~500 chars/request (free tier)

### Request
```
?q=Hello+world&langpair=en|id
```

### Response
```json
{"responseData": {"translatedText": "Halo dunia"}}
```

## Discovery Technique

When DeepL's free JSON-RPC was blocked (429), we found DeepLX via:

```bash
curl -sL "https://api.github.com/search/repositories?q=deepl+free+api&sort=stars"
```

This generalizes: search GitHub for open-source implementations when paid APIs block free access.
