---
name: ocr-and-documents
description: "Extract text from PDFs/scans (pymupdf, marker-pdf)."
version: 2.5.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [PDF, Documents, Research, Arxiv, Text-Extraction, OCR]
    related_skills: [powerpoint]
---

# PDF & Document Extraction

For DOCX: use `python-docx` (parses actual document structure, far better than OCR).
For PPTX: see the `powerpoint` skill (uses `python-pptx` with full slide/notes support).
This skill covers **PDFs and scanned documents**.

## Step 1: Remote URL Available?

If the document has a URL, **always try `web_extract` first**:

```
web_extract(urls=["https://arxiv.org/pdf/2402.03300"])
web_extract(urls=["https://example.com/report.pdf"])
```

This handles PDF-to-markdown conversion via Firecrawl with no local dependencies.

Only use local extraction when: the file is local, web_extract fails, or you need batch processing.

## Step 2: Choose Local Extractor

| Feature | pymupdf (~25MB) | marker-pdf (~3-5GB) | PaddleOCR (~88MB) |
|---------|-----------------|---------------------|--------------------|
| **Text-based PDF** | ✅ | ✅ | ✅ |
| **Scanned PDF (OCR)** | ❌ | ✅ (90+ languages) | ✅ (100+ languages) |
| **Images → text (OCR)** | ❌ | ✅ | ✅ (native strength) |
| **Tables** | ✅ (basic) | ✅ (high accuracy) | ✅ (PP-StructureV3) |
| **Equations / LaTeX** | ❌ | ✅ | ✅ (PP-StructureV3) |
| **Layout → Markdown** | ❌ | ✅ | ✅ (PP-StructureV3 / PaddleOCR-VL) |
| **JSON structured output** | ❌ | ✅ | ✅ |
| **MCP server ready** | ❌ | ❌ | ✅ (native mcp_server/) |
| **Cloud/API mode** | ❌ | ❌ | ✅ (free online service) |
| **ARM64 Linux wheels** | ✅ | ❌ (no PyTorch ARM) | ✅ (native Linux ARM) / ⚠️ Termux-Android (cloud only) |
| **Form fields** | ❌ | ✅ | ❌ |
| **Code blocks** | ❌ | ✅ | ❌ |
| **Headers/footers removal** | ❌ | ✅ | ❌ |
| **Reading order detection** | ❌ | ✅ | ✅ |
| **Images extraction** | ✅ (embedded) | ✅ (with context) | ❌ |
| **EPUB** | ✅ | ✅ | ❌ |
| **Install size** | ~25MB | ~3-5GB (PyTorch + models) | ~88MB (PaddlePaddle) + ~50-100MB models |
| **Speed** | Instant | ~1-14s/page (CPU) | Fast (lightweight models) |

**Decision rules**:
- **pymupdf** → text PDFs, simple extractions, instant no-dependency setup.
- **marker-pdf** → scanned PDFs, equations, complex layout, forms, highest quality. But big install.
- **PaddleOCR** → best all-rounder for ARM64, has cloud mode (no local install needed), MCP integration, good for images (not just PDFs). Not great for forms or code blocks, but strong on tables/equations/layout. On Termux/Android, use aistudio cloud mode or direct HTTP client since the MCP server package can't install natively.

If the user needs marker capabilities but lacks disk space:
> "This document needs OCR/advanced extraction (marker-pdf), which requires ~5GB for PyTorch and models. Your system has [X]GB free. Options: PaddleOCR (smaller, has cloud mode, ARM64-compatible, MCP server available), free up space, provide a URL for web_extract, or try pymupdf for text-based PDFs."

---

## pymupdf (lightweight)

```bash
pip install pymupdf pymupdf4llm
```

**Via helper script**:
```bash
python scripts/extract_pymupdf.py document.pdf              # Plain text
python scripts/extract_pymupdf.py document.pdf --markdown    # Markdown
python scripts/extract_pymupdf.py document.pdf --tables      # Tables
python scripts/extract_pymupdf.py document.pdf --images out/ # Extract images
python scripts/extract_pymupdf.py document.pdf --metadata    # Title, author, pages
python scripts/extract_pymupdf.py document.pdf --pages 0-4   # Specific pages
```

**Inline**:
```bash
python3 -c "
import pymupdf
doc = pymupdf.open('document.pdf')
for page in doc:
    print(page.get_text())
"
```

---

## marker-pdf (high-quality OCR)

```bash
# Check disk space first
python scripts/extract_marker.py --check

pip install marker-pdf
```

**Via helper script**:
```bash
python scripts/extract_marker.py document.pdf                # Markdown
python scripts/extract_marker.py document.pdf --json         # JSON with metadata
python scripts/extract_marker.py document.pdf --output_dir out/  # Save images
python scripts/extract_marker.py scanned.pdf                 # Scanned PDF (OCR)
python scripts/extract_marker.py document.pdf --use_llm      # LLM-boosted accuracy
```

**CLI** (installed with marker-pdf):
```bash
marker_single document.pdf --output_dir ./output
marker /path/to/folder --workers 4    # Batch
```

---

## Arxiv Papers

```
# Abstract only (fast)
web_extract(urls=["https://arxiv.org/abs/2402.03300"])

# Full paper
web_extract(urls=["https://arxiv.org/pdf/2402.03300"])

# Search
web_search(query="arxiv GRPO reinforcement learning 2026")
```

## Split, Merge & Search

pymupdf handles these natively — use `execute_code` or inline Python:

```python
# Split: extract pages 1-5 to a new PDF
import pymupdf
doc = pymupdf.open("report.pdf")
new = pymupdf.open()
for i in range(5):
    new.insert_pdf(doc, from_page=i, to_page=i)
new.save("pages_1-5.pdf")
```

```python
# Merge multiple PDFs
import pymupdf
result = pymupdf.open()
for path in ["a.pdf", "b.pdf", "c.pdf"]:
    result.insert_pdf(pymupdf.open(path))
result.save("merged.pdf")
```

```python
# Search for text across all pages
import pymupdf
doc = pymupdf.open("report.pdf")
for i, page in enumerate(doc):
    results = page.search_for("revenue")
    if results:
        print(f"Page {i+1}: {len(results)} match(es)")
        print(page.get_text("text"))
```

No extra dependencies needed — pymupdf covers split, merge, search, and text extraction in one package.

---

## PaddleOCR (lightweight, MCP-ready, ARM64-friendly)

Best for: images, scanned docs, multi-language OCR, layout-aware Markdown. Native MCP server for Hermes integration.

### Setup

```bash
# Core install (in venv)
pip install paddleocr

# Or with full doc parsing (tables, formulas, layout)
pip install "paddleocr[doc-parser]"

# Or everything
pip install "paddleocr[all]"
```

PaddlePaddle 3.2+ publishes ARM64 Linux wheels — works on aarch64 out of the box.

### Usage: Local Python

```python
from paddleocr import PaddleOCR

# Basic OCR on image
ocr = PaddleOCR(lang='en')  # or 'id', 'ch', 'ja', etc.
result = ocr.ocr('invoice.jpg')

# PP-StructureV3: layout → Markdown
from paddleocr import PPStructure
engine = PPStructure()
result = engine('document.pdf')
markdown = result['markdown']
```

### Usage: MCP Server (Hermes native)

PaddleOCR ships a **separate MCP server package** (`paddleocr-mcp`) that wraps its pipelines as MCP tools. The package name (`paddleocr-mcp`) differs from the binary name (`paddleocr_mcp` — underscore, not hyphen).

**Installing via uvx (recommended — no manual install needed):**

```yaml
mcpServers:
  paddleocr:
    command: "uvx"
    args: ["--from", "paddleocr-mcp", "paddleocr_mcp"]
    env:
      PADDLEOCR_MCP_PIPELINE: "PP-StructureV3"
      PADDLEOCR_MCP_PPOCR_SOURCE: "local"
```

Choose pipeline: `OCR` (text only), `PP-StructureV3` (layout/Markdown), or `PaddleOCR-VL` (VLM-based).

Once configured, you get tool access to:
- `ocr(path="invoice.jpg")` — extract text from image/PDF
- `pp_structurev3(path="doc.pdf")` — layout → Markdown with tables, formulas

**Available env vars (MCP server):**

| Env Variable | CLI arg | Purpose | Values | Default |
|---|---|---|---|---|
| `PADDLEOCR_MCP_PIPELINE` | `--pipeline` | Pipeline to run | `OCR`, `PP-StructureV3`, `PaddleOCR-VL`, `PaddleOCR-VL-1.5`, `PaddleOCR-VL-1.6` | `OCR` |
| `PADDLEOCR_MCP_PPOCR_SOURCE` | `--ppocr_source` | Backend mode | `local`, `aistudio`, `qianfan`, `self_hosted` | `local` |
| `PADDLEOCR_MCP_SERVER_URL` | `--server_url` | Base URL (required for cloud modes) | URL string | `None` |
| `PADDLEOCR_MCP_AISTUDIO_ACCESS_TOKEN` | `--aistudio_access_token` | AI Studio token (aistudio mode) | Token string | `None` |
| `PADDLEOCR_MCP_QIANFAN_API_KEY` | `--qianfan_api_key` | API key (qianfan mode) | Key string | `None` |
| `PADDLEOCR_MCP_TIMEOUT` | `--timeout` | HTTP timeout | seconds | `60` |

**The MCP server exposes exactly ONE tool per instance** — the pipeline you set. To expose multiple pipelines, add multiple MCP server entries in config.yaml with different names.

### Usage: Cloud Modes (no local models)

Four modes are available, controlled by `PADDLEOCR_MCP_PPOCR_SOURCE`:

| Mode | Value | API Key? | Cost | Best for |
|------|-------|----------|------|----------|
| Local | `local` | None | Free, offline | Full privacy, no internet |
| AI Studio | `aistudio` | Free token from aistudio.baidu.com | Free (rate-limited) | Quick testing, no GPU |
| Qianfan (Baidu Cloud) | `qianfan` | Paid API key | Pay-per-call | Production cloud |
| Self-hosted | `self_hosted` | Your own server | Free (you host) | Data privacy at scale |

**Mode: aistudio (free cloud, recommended for Termux/ARM)**

Register at [aistudio.baidu.com/paddleocr](https://aistudio.baidu.com/paddleocr?lang=en), click "API" in the upper-left corner, copy `API_URL` (base URL without `/ocr` suffix) and `TOKEN`.

```yaml
env:
  PADDLEOCR_MCP_PIPELINE: "OCR"
  PADDLEOCR_MCP_PPOCR_SOURCE: "aistudio"
  PADDLEOCR_MCP_SERVER_URL: "https://xxxxxx.aistudio-app.com"
  PADDLEOCR_MCP_AISTUDIO_ACCESS_TOKEN: "your-token-here"
```

No local models needed — works on any device with internet.

**Direct HTTP client (fallback when MCP server can't install):**

On some platforms (e.g., Termux/PRoot on Android where the platform tag `android_24_arm64_v8a` prevents pip/uv from resolving manylinux wheels), the `paddleocr-mcp` package dependencies (Pillow, etc.) may not install. Use direct HTTP instead:

```python
import httpx, json

BASE_URL = "https://xxxxxx.aistudio-app.com"
TOKEN = "your-token-here"

# OCR on an image
with open("document.jpg", "rb") as f:
    r = httpx.post(
        f"{BASE_URL}/ocr",
        files={"file": f},
        headers={"Authorization": f"Token {TOKEN}"}
    )
print(json.dumps(r.json(), indent=2))
```

### Model caching

Models download to `~/.paddleocr/` on first use (~50-100MB for English). Subsequent runs use cache. Cloud modes download nothing locally.

### Language support

100+ languages. Set `lang` param: `'en'`, `'id'` (Indonesian), `'ch'`, `'ja'`, `'ko'`, `'fr'`, `'ar'`, etc.

### Notes

- PaddleOCR excels at **images** — not just PDFs. Use for photos of documents, whiteboards, screenshots.
- PP-StructureV3 outputs **Markdown with table/formula structure**, not just raw text.
- MCP server means you can call it as a tool in Hermes without writing glue code.
- Cloud mode = zero local models, works on anything with internet.
- ARM64 note: PaddlePaddle 3.2+ publishes Linux ARM64 wheels (`manylinux2014_aarch64`). However, on **Termux/PRoot (Android)** the platform tag is `android_24_arm64_v8a` — pip/uv will reject the manylinux wheel and try to build from source, which will fail. On Termux, only cloud modes work (aistudio or direct HTTP). Native Linux ARM64 (Raspberry Pi, etc.) works fine.

- `web_extract` is always first choice for URLs
- pymupdf is the safe default — instant, no models, works everywhere
- marker-pdf is for OCR, scanned docs, equations, complex layouts — install only when needed
- Both helper scripts accept `--help` for full usage
- marker-pdf downloads ~2.5GB of models to `~/.cache/huggingface/` on first use
- For Word docs: `pip install python-docx` (better than OCR — parses actual structure)
- For PowerPoint: see the `powerpoint` skill (uses python-pptx)
