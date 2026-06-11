---
name: markitdown
description: Convert files (PDF, Word, Excel, PPT, HTML, images) to clean Markdown using Microsoft MarkItDown. Use when the user needs to extract text from documents for LLM consumption.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [documents, conversion, markdown, pdf, ocr]
    related_skills: [ocr-and-documents, google-workspace, scrapling]
---

# MarkItDown — File to Markdown Converter

Convert various file formats to clean Markdown for LLM consumption using `markitdown` CLI.

## Supported Formats

| Format | Notes |
|--------|-------|
| PDF | Preserves headings, lists, tables |
| Word (.docx) | Full document structure |
| PowerPoint (.pptx) | Slides content |
| Excel (.xlsx) | Tables preserved |
| HTML | Clean extraction, strips styling |
| Images (EXIF + OCR) | Extracts text via embedded OCR |
| Audio (EXIF + transcription) | Metadata + speech-to-text |
| CSV/JSON/XML | Tabular rendering |
| EPUB | Book content |
| YouTube URLs | Transcript extraction |
| ZIP | Iterates over contents |

## Usage

### CLI — convert file to markdown

```bash
markitdown file.pdf > output.md
markitdown file.docx > output.md
markitdown file.html > output.md
```

Or pipe:

```bash
cat file.pdf | markitdown > output.md
markitdown < file.pdf > output.md
```

### From Hermes (terminal)

```bash
markitdown /path/to/file 2>/dev/null
```

Redirect stderr to `/dev/null` to suppress the harmless onnxruntime GPU warning on systems without GPU.

### Install all extras (default install is lightweight)

The base install covers text-based formats (HTML, CSV, JSON, XML, markdown). For PDF/Word/Excel/PPT/image OCR support, the `[all]` extras were installed automatically with `uv tool install markitdown`. Verify:

```bash
markitdown --help
```

## Use Cases for This Setup

### Research pipeline (Indonesia topics)
```bash
# Convert downloaded news PDF to markdown for LLM analysis
markitdown laporan_ekonomi_2026.pdf | head -200

# Extract table data from Excel reports
markitdown data_pdb.xlsx

# Convert HTML article to clean text
curl -s https://www.kompas.com/artikel | markitdown
```

### YouTube documentary research
```bash
# Extract text from saved reference documents
markitdown whitepaper.pdf > research_note.md

# Convert table data for data visualization prep
markitdown statistik.xlsx > data.md
```

## Common Pitfalls

1. **onnxruntime GPU warning** — harmless, redirect stderr: `markitdown file.pdf 2>/dev/null`
2. **Large files** — for PDFs > 50 pages, use `--page-range` if available, or pipe through head: `markitdown big.pdf 2>/dev/null | head -500`
3. **OCR on images** — requires the `[all]` extras (already installed)
4. **Non-ARM64 dependencies** — all pure Python, works fine on ARM64 (Termux/PRoot)

## Verification Checklist

- [ ] `markitdown --help` shows usage
- [ ] Can convert a simple file: `echo "test" > /tmp/test.txt && markitdown /tmp/test.txt`
- [ ] HTML to markdown preserves structure (headings, bold, tables)
