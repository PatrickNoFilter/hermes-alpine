# PaddleOCR on Termux / ARM64 Android (Gotchas)

## Platform Tag Mismatch

Termux/PRoot environments report platform tag `android_24_arm64_v8a` (not `manylinux2014_aarch64`). This causes pip/uv to reject pre-built manylinux wheels and attempt source builds, which will fail.

### Affected packages

| Package | Issue |
|---------|-------|
| `paddlepaddle` | Has `manylinux2014_aarch64` wheels but tagged for CPU-only on linux → rejected on android platform. |
| `paddleocr` | Depends on `paddlepaddle` → same issue. |
| `paddleocr-mcp` (MCP server) | Depends on `pillow` → pillow build from source fails (missing jpeg/zlib headers in Termux). |
| `pillow` | No pre-built android wheel; build from source fails without jpeg/zlib dev headers. |

### Attempted but failed

```bash
# uv tool install with UV_LINK_MODE=copy — fails on pillow build
UV_LINK_MODE=copy uv tool install paddleocr-mcp
# → Failed to build pillow (jpeg dependency missing)

# uv pip install in venv — same pillow build failure
uv pip install paddleocr-mcp

# pip download to check wheel availability
pip3.13 download pillow --only-binary=:all: --platform manylinux2014_aarch64
# → Wheel downloads fine but cannot install (platform tag rejected)
# → pip install <wheel>.whl → "is not a supported wheel on this platform"

# apt install python3-pil → installs for system Python (3.14), not accessible from 3.13 venv
```

### Viable alternatives on Termux

1. **Direct HTTP to aistudio** — works, no heavy dependencies. Need httpx or requests.
2. **pymupdf** — `apt install python3-pymupdf` or `pip install pymupdf` — works for text-based PDFs.
3. **Tesseract** — `apt install tesseract-ocr` — lighter than PaddleOCR for basic OCR on Termux.
4. **marker-pdf** — won't work (needs PyTorch, no ARM wheel for Android platform tag).

## Verification commands (useful for future diagnostics)

```bash
# Check platform tag
python3 -c "from pip._internal.utils.compatibility_tags import get_supported; tags = list(get_supported()); print(tags[0])"

# Check if a wheel is compatible
python3 -c "
from pip._internal.utils.compatibility_tags import get_supported
tags = {t[0] for t in get_supported()}
# Example: check if manylinux2014_aarch64 is in tags
print('manylinux2014_aarch64 supported:', 'manylinux2014_aarch64' in tags)
print('First tags:', list(sorted(tags))[:5])
"

# Try to download a specific platform wheel
pip3.13 download pillow --only-binary=:all: \
  --platform manylinux2014_aarch64 \
  --python-version 3.13

# Check Termux Python paths vs system Python paths
python3 -c "import sys; print(sys.path)"
which python3.13
which python3.14
dpkg -L python3-pil 2>/dev/null | head -5
```

## aistudio.baidu.com registration tip

- Register at https://aistudio.baidu.com/paddleocr?lang=en (English UI available)
- Click "API" in upper-left corner → copy `API_URL` (remove trailing `/ocr`) and `TOKEN`
- Free tier has rate limits but enough for testing/prototyping
- Token is a long random string, store in `.env` or Hermes config
