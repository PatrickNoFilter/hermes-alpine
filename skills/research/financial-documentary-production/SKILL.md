---
name: financial-documentary-production
version: "2.0.0"
description: "End-to-end financial documentary production: research, source verification, HTML slide prototyping, TTS narration, and MP4 video rendering. Primary: html-video via Playwright Chromium. Fallback: Pillow + FFmpeg."
author: hermes-agent
license: MIT
allowed-tools: terminal, browser, write_file, execute_code, web_search
---

# Financial Documentary Production

Produce structured slide-based financial documentaries with verified sources, data visualization, TTS narration, and final MP4 video output. Renders via html-video (primary, Playwright Chromium) or Pillow + FFmpeg (fallback).

## Trigger
- User asks to research Indonesia financial/economic topics (IHSG, DSI, capital flows, kebijakan ekonomi)
- User wants slide-based documentary or YouTube video format
- User requests deep-dive analysis on market/economic issues
- User wants a narrated video built from research slides

## Workflow

### Phase 1: Multi-Source Research

1. **Identify target sources** for Indonesia financial news:
   - Detik Finance (detik.com/finance)
   - Kompas.com (bisnis & ekonomi sections)
   - IDXChannel.com (market analysis)
   - Bisnis.com (market & corporate news)
   - Kontan.co.id (market & economy)
   - Suara.com (policy angles)
   - Katadata.co.id (data-driven reporting)
   - TradingEconomics.com (macro data)
   - CNBC Indonesia (cnbcindonesia.com)

2. **Fetch articles** — use curl with Python extraction (AMP versions often yield better text):
   ```python
   import re, sys
   html = sys.stdin.read()
   clean = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
   clean = re.sub(r'<style[^>]*>.*?</style>', '', clean, flags=re.DOTALL)
   clean = re.sub(r'<[^>]+>', ' ', clean)
   clean = re.sub(r'\s+', ' ', clean).strip()
   ```

3. **Parallel fetch** — use ThreadPoolExecutor with curl in terminal() for multiple articles concurrently (user prefers batch ops over sequential).

4. **Triangulate 3-4 sources** per claim — cross-reference Detik, Kompas, Kontan, CNBC Indonesia.

### Phase 2: Gap Analysis

1. List all data points needed per slide/scene
2. Mark each as: ✅ verified / ❌ missing / ⚠️ partial
3. Track missing sources explicitly and re-search until filled
4. As new sources are found, update the gap table — don't cling to old angles
5. Typical gaps to watch for: rating agency actions (Moody's, Fitch, S&P), MSCI announcements, historical comparison data, analyst quotes

### Phase 3: Slide Structure

Organize in 4 parts:
- **Bagian 1 — Fakta:** The raw data (what happened)
- **Bagian 2 — Trigger:** The policy/event that caused it
- **Bagian 3 — Konteks:** Global context & turning points
- **Bagian 4 — Jalan Keluar:** Constructive recommendations

### Phase 4: HTML Slide Prototype

Build an interactive HTML prototype for user review:
- Dark theme (#0a0a0f background, #e8e8ed text) matching documentary tone
- Single HTML file with all CSS + JS embedded — no dependencies
- **No direct photos of public officials** — use silhouettes, data graphics, icons, illustrations
- Data cards for key metrics
- Chart bars for comparisons
- Timelines for chronology
- Quote blocks for analyst/expert citations
- Step lists for recommendations
- Progress bar + keyboard navigation (arrow keys)
- **Query parameter slide navigation:** support `?slide=N` in URL so individual slides can be targeted for screenshot/render
- Mobile-responsive

### Phase 5: Framing & Tone

- **Nada:** Santun, santai, dokumenter analitis
- **Posisi:** Bukan "siapa yang salah" — tapi "apa yang tidak beres, apa yang bisa diperbaiki"
- **Bahasa:** Indonesian for Indonesia topics; concise
- **Visual style:** Data-driven, no mugshots, use infographics & silhouettes

### Phase 6: Narasi Script & TTS Audio

1. **Write full narration script** — one paragraph or a few sentences per slide, matching the slide content framing
2. **Generate per-slide audio** using the text_to_speech tool:
   - Call once per slide narrative block
   - Save as `slideNN.mp3` (zero-padded numbers, e.g. slide01.mp3)
   - Track total audio duration — sum all MP3 durations via ffprobe
   - Target: ~10-12 minutes for a 16-slide documentary (~35-45s per slide)
3. **TTS voice note:** The text_to_speech tool provides basic TTS. For specific voices (e.g. Indonesian female "edge"), attempt edge-tts setup first; if voice discovery fails on ARM64/PRoot, fall back to the tool's built-in TTS.

### Phase 7: HTML-to-Video Rendering Pipeline

This environment supports **two** rendering pipelines. The html-video pipeline (primary) produces richer visuals (animations, data graphics, transitions). The Pillow pipeline (fallback) works when html-video isn't set up.

**Setup prerequisite — Playwright Chromium on ARM64:**
```bash
npx playwright install chromium
# Installs standalone Chromium to ~/.cache/ms-playwright/ — no snap needed, works on ARM64 PRoot
```

#### Primary path: html-video (nexu-io/html-video)

A Node.js meta-layer over multiple render engines (Hyperframes shipped, Remotion/Motion Canvas planned). Converts HTML slides → multi-frame storyboard → MP4 via Playwright Chromium + ffmpeg.

1. **Clone and build:**
   ```bash
   git clone https://github.com/nexu-io/html-video.git ~/html-video
   cd ~/html-video
   export PATH="/root/.hermes/node/bin:$PATH"
   pnpm install
   pnpm -r build
   ```

2. **Launch studio (browser UI at http://127.0.0.1:3071):**
   ```bash
   node packages/cli/dist/bin.js studio
   ```
   Pick a template, paste the existing HTML prototype URL/link, and let the agent build a multi-frame storyboard.

3. **CLI scripting alternative:**
   ```bash
   node packages/cli/dist/bin.js doctor
   node packages/cli/dist/bin.js search-templates --intent "data visualization documentary"
   ```

4. **Export MP4** — headless Chromium records each animated HTML frame, ffmpeg encodes to libx264.

Also check the `hyperframes` skill if working directly with GSAP-animated HTML compositions (same engine pipeline).

#### Fallback path: Pillow + FFmpeg

Render slides programmatically with Pillow (PIL):

1. **Generate slide images** — use `scripts/generate-slides.py` template:
   - 1920×1080 pixels, dark background (#0a0a0f), white/light text
   - Output: `slide01.png` through `slideNN.png`

2. **Render video segments** — use `scripts/create-segments.sh` template:
   - Per segment: `ffmpeg -loop 1 -i slideN.png -i slideN.mp3 -c:v libx264 -c:a aac -pix_fmt yuv420p -shortest segmentN.mp4`
   - H.264, 1920×1080, 30fps, AAC 128kbps

3. **Concatenate segments** using FFmpeg concat demuxer (fast, lossless join):
   - Create `segments.txt`
   - Run: `ffmpeg -f concat -safe 0 -i segments.txt -c copy final-output.mp4`

4. **Verify the output:**
   ```bash
   ffprobe -v error -show_entries format=duration,size,bit_rate \
     -of default=noprint_wrappers=1:nokey=1 output.mp4
   ```

### Phase 8: Final Review & Polish

1. Confirm final duration (target ~10 min for 16 slides)
2. For richer visuals than Pillow, use the **html-video pipeline** (Phase 7 primary path) which renders the HTML prototype directly with Playwright Chromium — transitions, data charts, animations all included. As a last resort, export the HTML prototype on a laptop (OBS record or DevTools screenshot)
3. For background music, overlay with FFmpeg amix after concat
4. For transitions (fade/crossfade), render segments with -vf fade and re-encode during concat

## Pitfalls

### Research
- Google Search blocks Indonesian IPs after 1-2 requests via browser_navigate → use DuckDuckGo Lite as fallback
- Katadata uses heavy JS for article body → use AMP version (`/amp/` in URL path) for curl extraction
- Kompas sometimes requires subscription → the AMP/text-only versions accessible via curl often work
- MSCI letter details are hard to find directly → search Kontan and Bisnis for "MSCI rebalancing" coverage
- TradingEconomics data is JS-rendered → curl extracts partial data, enough for key numbers
- Always note source URL + date for every data point used

### HTML Prototype
- When building the prototype, the list of slides must be enumerable (id="slide1", "slide2") for query-param targeting
- Add `getSlideFromUrl()` on page load that parses `?slide=N` and jumps there

### Video Production on ARM64 / PRoot / Low-Resource
- **Chromium on PRoot:** The system `chromium-browser` snap wrapper does NOT work on PRoot. However, **Playwright's standalone Chromium** does work — install with `npx playwright install chromium` (downloads to ~/.cache/ms-playwright/). This enables headless HTML screenshot/render for video production.
- **html-video primary path:** The `html-video` (nexu-io) pipeline via Playwright Chromium is the preferred rendering method. Only fall back to Pillow if html-video setup fails.
- **PIL limitations:** No rich text formatting, no emoji, no complex layouts. Use plain text with manual positioning.
- **TTS basic voice only:** The text_to_speech tool provides default TTS. For specific voices (edge-tts), the voice ID discovery may fail on ARM64 — the Python client has aiohttp compatibility issues in some envs.
- **No GPU:** H.264 software encoding is fine for documentary-style static slides (fast per-segment, just image + audio loop).
- **Memory:** PRoot underreports cores. Don't parallelize FFmpeg segment rendering — serialize to avoid OOM.

### Multi-slide Concat
- Use `-c copy` for concat to avoid re-encoding
- If different segments have different codec parameters (e.g. resolution mismatch), `-c copy` will fail → re-encode with `-vf scale=1920:1080 -c:v libx264`
- Ensure zero-padded numbers are consistent across slide images, audio, and video filenames

## Files

### `references/`
- `ihsg-dsi-source-compilation.md` — Complete source compilation from the IHSG/DSI session (June 2026). Pattern for documenting verified data points per slide.
- `gap-analysis-template.md` — Template for tracking which data points still need sources.
- `video-production-pipeline.md` — Full pipeline details, FFmpeg commands, TTS workflow, and ARM64/PRoot workarounds.

### `templates/`
- `html-slide-prototype.md` — HTML/CSS/JS patterns for building interactive slide prototypes (dark theme, data cards, chart bars, timelines, keyboard nav, query-param targeting).

### `scripts/`
- `generate-slides.py` — Python Pillow script template for rendering 1920×1080 dark-theme slides. Modify the slide content dict for new documentaries.
- `create-segments.sh` — Bash template for FFmpeg segment rendering (image + audio loop per slide). Modify the slide count and paths as needed.
