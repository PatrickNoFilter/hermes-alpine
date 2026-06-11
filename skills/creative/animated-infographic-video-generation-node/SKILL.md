---
name: animated-infographic-video-generation-node
title: Animated Infographic Video Generation (phone-first, free, cloud-rendered)
description: >-
  End-to-end workflow for producing professional animated infographic
  videos (Vox / Polymatter / Kurzgesagt style) entirely on a phone
  (Termux + PRoot Ubuntu) or any low-resource ARM64 device. Two
  implementation paths — primary is HTML+CSS+Playwright+Modal (the
  "pocket-director" pipeline, fully working and on GitHub); fallback
  is the Reel-Infographics-Gen Node/React/Gemini stack. Pick the
  primary unless you specifically need AI-generated imagery.
tags:
  - infographic
  - video generation
  - node
  - react
  - gemini
  - fal.ai
  - ffmpeg-wasm
  - arm64
  - proot
  - modal
  - playwright
  - edge-tts
  - pocket-director
---

## When to use this skill

- Producing 5–30 minute documentary-style explainer videos (Vox, Polymatter, Kurzgesagt).
- Output formats: **1920×1080 horizontal** (YouTube) or **1080×1920 vertical** (TikTok/Reels).
- Device constraint: phone (Samsung Galaxy A33 / Termux + PRoot Ubuntu) or any ARM64 box with no hardware H.264 encoder.
- Visual style: bar charts growing, number counters ticking, text reveal staggers, timeline dots, quote blocks. NOT live-action, NOT AI-imagery-first.
- Source material: a text script (narration) in any language — the pipeline handles parsing, TTS, layout, animation, recording, encoding, and muxing.

## Primary path: **pocket-director** (HTML+CSS+Playwright+Modal) ★ use this first

**Repo:** https://github.com/PatrickNoFilter/pocket-director
**Local clone:** `~/pocket-director`

The working pipeline as of June 2026. End-to-end on a Galaxy A33 in ~14 min for a 10-min video, **$0 cost** (Modal free tier covers it).

### Architecture

```
   Phone (Termux + PRoot Ubuntu)              Modal Cloud (x86_64)
   ─────────────────────────────              ────────────────────
   1. narration.md (text script)
            ↓
   2. edge-tts  → 16 × slide_NN.mp3           (Indonesian girl, en-US, etc.)
            ↓
   3. build HTML  → slide_deck.html           (single self-contained file, 41KB)
            ↓                                   CSS keyframes:
            ↓                                     - bar height growUp
            ↓                                     - data-counter requestAnimationFrame
            ↓                                     - staggered text reveal
            ↓                                     - quote slideRight
            ↓                                     - timeline scaleIn
            ↓                                     - Ken Burns on bg images
            ↓                                   JS runtime:
            ↓                                     - window.__activate(n) for Playwright
            ↓
   4. Playwright Chromium                     
      recordVideo (VP8)  →  47MB webm          
      auto-advances by TTS duration            
            ↓                                  5. ffmpeg libx264 medium CRF 20
            ↓ ──── upload 47MB webm ────────▶  cpu=8,  ~70s
            ↓                                  6. download 26MB H.264 MP4
            ↓ ◀──────────────────────────────
   7. ffmpeg local                            
      TTS concat + BGM looped                 
      + sidechaincompress (duck BGM under voice) 
      + loudnorm -14 LUFS                      
            ↓
   8. ffmpeg local                            
      mux video + audio → final.mp4 (31MB)    
            ↓
   9. cp → /storage/emulated/0/Movies/       
      (Android Gallery auto-picks up)          
```

### Stage details (pocket-director pipeline)

#### Stage 1: TTS (edge-tts, local)
```python
# pipeline/01_generate_tts.py
# Parses ### SLIDE N sections, generates one MP3 per slide
# Voice: id-ID-GadisNeural (Indonesian girl) or en-US-AriaNeural
# Rate: +5% gives natural pacing for Indonesian
```
- Parse `narration.md` for `### SLIDE N — TITLE\n<body>` blocks
- One MP3 per slide → `audio/slide_NN.mp3`
- Write `audio/manifest.json` with per-slide duration (from ffprobe)

#### Stage 2: HTML slide deck (local, no Playwright yet)
```python
# pipeline/02_build_slides.py
# Injects data into templates/slide_deck.html
```
- The HTML template (`templates/slide_deck.html` in the repo) has:
  - CSS variables at top for colors (red/green/yellow/blue/gray)
  - CSS classes per slide layout: `title`, `chart`, `data`, `timeline`, `quote`, `list`
  - Animation keyframes: `fadeIn`, `growUp`, `scaleIn`, `slideRight`, `countUp`
  - JS function `window.__activate(n)` that adds `.active` class to slide N + staggers children
- Each slide has `<div data-counter="908">$908B</div>` for animated number counters
- Each bar has `<div class="bar" style="height:0" data-target-h="180">` that grows to target on activation
- Watermark: `<div class="watermark">● YOURBRAND</div>` — fixed bottom-right, always renders

#### Stage 3: Playwright record (local, real-time)
```js
// pipeline/03_render.js
const browser = await chromium.launch({
  headless: true,
  executablePath: '/root/.cache/ms-playwright/chromium-XXXX/chrome-linux/chrome',  // see playwright-termux-arm64
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu']
});
const ctx = await browser.newContext({
  viewport: { width: 1920, height: 1080 },
  recordVideo: { dir: 'recordings', size: { width: 1920, height: 1080 } }
});
// ... for each slide: page.evaluate(n => window.__activate(n), slide.num) + wait TTS duration
```
- **CRITICAL: must use full Chromium binary, not the slim headless_shell** (see `playwright-termux-arm64`)
- Auto-advance by TTS duration → natural pacing
- Close **context** (not browser) to flush webm
- Output: `recordings/page@<uuid>.webm` — VP8, ~30fps, ~4MB/min

#### Stage 4: Audio mix (local, ffmpeg)
```python
# pipeline/04_mix_audio.py
```
- Concat TTS mp3s → single voice track
- Loop BGM to match voice duration: `ffmpeg -stream_loop -1 -i bgm.mp3 -t <total_dur>`
- Mix with sidechain compress (BGM ducks under voice):
  ```
  [0:a]volume=1.0[v];
  [1:a]volume=0.25,sidechaincompress=threshold=0.05:ratio=8:attack=5:release=800[bg];
  [v][bg]amix=inputs=2:duration=first[out]
  ```
- Loudnorm: `loudnorm=I=-14:TP=-1.5:LRA=11` (TikTok / YouTube safe)
- BGM needs silence removed first: `silenceremove=stop_periods=-1:stop_duration=0.3`

#### Stage 5: Modal cloud encode (cloud, fast)
- See `devops/modal-cloud-encode-termux` skill for the full script template
- Use a **persistent Modal Volume** (not ephemeral) so 47MB webm + 26MB MP4 round-trip works
- Three functions: `upload_to_volume`, `ffmpeg_encode`, `download_from_volume`
- Encode config: `libx264 medium crf 20 pix_fmt yuv420p +faststart`
- Cloud time: ~70s for 11-min 1080p
- First run adds ~30-40s for apt-install ffmpeg in the container; subsequent runs use cached image

#### Stage 6: Mux + deploy (local, fast)
```bash
ffmpeg -y -i recording_h264.mp4 -i audio_mixed.mp3 \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
  IHSG_Danantara_Final.mp4

# Deploy to Android Movies
cp IHSG_Danantara_Final.mp4 /storage/emulated/0/Movies/
```

### Narration format

Markdown file, one `### SLIDE N` per section. Body is the TTS text. Optional frontmatter for meta:
```markdown
# Title of the video
## Optional subtitle
Watermark: ● PatrickNoFilter
BGM: https://youtu.be/PYne2exHHYU

### SLIDE 1 — IHSG Runtuh, DSI Kontroversi
Indeks Harga Saham Gabungan jatuh tiga puluh delapan persen...
```

Full example: `examples/ihsg-danantara/narration.md` in the repo.

### Performance reference (10-min 16-slide video)

| Stage | Where | Time |
|-------|-------|------|
| TTS generation | local | 2 min |
| HTML build | local | 5 sec |
| Playwright record | local | 11 min (real-time) |
| Audio mix | local | 10 sec |
| Modal encode | cloud | 72 sec |
| Upload/download | cloud | 27 sec |
| Mux + deploy | local | 2 sec |
| **Total wall-clock** | — | **~14 min** |

### Customization

| What | Where | Default |
|------|-------|---------|
| Watermark | `templates/slide_deck.html` | `● PatrickNoFilter` |
| Voice | `pipeline/01_generate_tts.py --voice` | `id-ID-GadisNeural` (Indonesian girl) |
| BGM URL | `pipeline/run_all.sh $BGM` | `https://youtu.be/PYne2exHHYU` |
| Colors | `templates/slide_deck.html` (CSS vars) | red/green/yellow/blue/gray |
| Resolution | `pipeline/03_render.js viewport` | 1920×1080 |
| Encode quality | `pipeline/05_modal_encode.py --crf` | 20 |

### Pocket-director repo structure

```
pocket-director/
├── README.md                    # Full pipeline overview
├── docs/SETUP.md                # Termux + PRoot + Modal install
├── docs/TROUBLESHOOTING.md      # Common issues
├── examples/ihsg-danantara/     # 16-slide documentary example
├── pipeline/
│   ├── 01_generate_tts.py       # edge-tts segments
│   ├── 02_build_slides.py       # HTML generator
│   ├── 03_render.js             # Playwright recording
│   ├── 04_mix_audio.py          # TTS + BGM mix
│   ├── 05_modal_encode.py       # Modal cloud ffmpeg
│   ├── 06_mux.py                # Final mux + deploy
│   └── run_all.sh               # One-command end-to-end
└── templates/slide_deck.html    # Reusable animated HTML template
```

## Fallback path: **Reel-Infographics-Gen** (Node/React/Gemini/Fal.ai)

Use ONLY when:
- You need AI-generated scene imagery (e.g. real photos, abstract visuals, photorealistic backgrounds)
- You're willing to spend money on Gemini + Fal.ai API calls
- The user has a desktop browser and is OK with the AI's creative choices

Skip if:
- The narration is technical/financial/serious (the HTML+CSS path is more accurate)
- Output is documentary-style with data viz (the HTML+CSS path is more precise)
- The user is on a phone (Gemini + Fal.ai web is awkward on mobile)

### Install + run

```bash
git clone https://github.com/iharnoor/Reel-Infographics-Gen.git
cd Reel-Infographics-Gen
npm install
cat > .env <<EOF
GEMINI_API_KEY=***
FAL_API_KEY=***
EOF
npm run dev   # Vite :3000, Express :3001 (proxied)
```

### Known pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| 401 from `/api/gemini/*` or `/api/fal/*` | Bad API key | Verify `.env`, no spaces, restart server |
| CORS error from another origin | Server only allows localhost | Add origin to `cors` middleware in `server/index.js` |
| Long image gen timeouts | Prompts > 2k chars | Keep slides short, split into more scenes |
| Stitching stalls on 10+ scenes | Browser memory | Limit concurrent to 3, export in batches, stitch locally with ffmpeg |
| Missing `ffmpeg.wasm` functions | Old browser | Use modern Chromium-based browser |

## Choosing between the two paths

**Default to pocket-director (primary).** Only switch to Reel-Infographics-Gen when:
- The user explicitly asks for "AI imagery" or "Gemini"
- The visual style is artistic / abstract (not data-viz)
- The user has $$$ to spend on per-scene API calls

## See also

- `devops/modal-cloud-encode-termux` — cloud ffmpeg setup, Modal wheel fix on Termux ARM64
- `devops/playwright-termux-arm64` — full Chromium executable path, launch args
- `references/narration-format.md` (this skill) — narration.md structure with examples
- `references/html-template-architecture.md` (this skill) — how the slide deck template works

---

*Maintained as the canonical skill for animated infographic video production on resource-constrained devices. Update when new animation patterns, providers, or pipeline improvements ship.*
