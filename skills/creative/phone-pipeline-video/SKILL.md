---
name: phone-pipeline-video
description: Class-level workflow for producing animated documentary-style infographic videos end-to-end from a phone, using a scripted pipeline of TTS, HTML+CSS animations, Playwright record, audio mix, cloud encode, and mux. Reference implementation is github.com/PatrickNoFilter/pocket-director. Use this skill when the user wants to make a long-form animated explainer video and has access to a phone, PRoot Ubuntu, and a free cloud ffmpeg service such as Modal, Replicate, RunPod, or Colab.
---

# Phone → Animated Infographic Video Pipeline

The **class of work** is: turn a topic into a 5-20 minute
documentary-style animated explainer video, entirely scripted,
re-runnable, free, and producible from a phone (Termux + PRoot Ubuntu
on Android, no GPU, no local heavy ffmpeg).

This is a CLASS skill, not a project skill. The reference
implementation is `pocket-director`, but the technique (HTML+CSS
animations + Playwright record + cloud encode) applies to any
phone-based video production. Use it for explainer videos, financial
documentaries, news analysis, education content, and TikTok long-form.

## When this skill is the right fit

✓ User wants a documentary-style video (5-20 min, narrated, animated)
✓ User has research (notes.md) and a narration script
✓ User is on a constrained device (phone, ARM64, no GPU, slow CPU)
✓ User wants a reusable pipeline, not a one-off render
✓ User accepts "free + cloud-rendered" as the constraint

✗ Don't use for short social clips (TikTok 60s) — too much overhead
✗ Don't use if user wants real footage / live action — wrong tool
✗ Don't use if user has a beefy desktop — pocket-director is
  optimized for phone constraints; desktop users should consider
  DaVinci Resolve, After Effects, or local ffmpeg scripts

## TTS engine comparison

| Engine | Quality | Quota | Indonesian voices | Best for |
|--------|---------|-------|-------------------|----------|
| **Edge-TTS** | Good (Azure Neural) | **Unlimited, free** | GadisNeural (F), ArdiNeural (M) | All videos, any length |
| **Gemini 2.5 Flash** | Better (more natural) | **10/day free** | Kore (F), + 7 others | Short videos (≤10 slides) |
| **OpenAI TTS HD** | Best (most natural) | ~$0.10/10min | alloy, nova, shimmer | When quality matters most |

**Edge-TTS is the default.** Use Gemini or OpenAI only when the user explicitly wants higher quality AND the slide count fits the quota. See `references/gemini-tts.md` for Gemini-specific gotchas and `references/edge-tts.md` for Edge-TTS batch workflow.

## Pipeline shape (the class)

```
  [Stage 0] research          → notes.md (optional, see references/research-stage.md)
       ↓
  [Stage 1] TTS               → 16+ .mp3 files + manifest.json
       ↓
  [Stage 2] HTML slide deck   → single .html with all slides
       ↓
  [Stage 3] Playwright record → .webm (real-time, ~video length)
       ↓
  [Stage 4] audio mix         → mixed.mp3 (TTS + BGM, sidechain)
       ↓
  [Stage 5] cloud encode      → .mp4 H.264 (libx264 medium, 8 vCPU)
       ↓
  [Stage 6] mux + deploy      → final.mp4 in /storage/emulated/0/Movies/
```

Total wall-clock for a 10-min video: ~14 minutes (dominated by
Playwright record at real-time + Modal cloud round-trip).

## Pipeline reference: pocket-director

**Repo:** https://github.com/PatrickNoFilter/pocket-director (17 files,
MIT, public). Local clone at `~/pocket-director/`.

| File | Purpose |
|------|---------|
| `pipeline/00_research.sh` | Optional pre-stage: last30days or manual notes.md |
| `pipeline/01_generate_tts.py` | edge-tts per slide → manifest.json |
| `pipeline/01b_tts_gemini.py` | Gemini 2.5 Flash TTS, voice=Kore and others |
| `pipeline/02_build_slides.py` | Python f-string HTML builder with CSS animations |
| `pipeline/03_render.js` | Playwright Chromium, auto-advances per manifest |
| `pipeline/04_mix_audio.py` | ffmpeg concat + sidechain compress + loudnorm |
| `pipeline/05_modal_encode.py` | Modal Volume + libx264 medium + faststart |
| `pipeline/06_mux.py` | ffmpeg copy + AAC + deploy to /Movies |
| `pipeline/run_all.sh` | One-command orchestration |
| `templates/slide_deck_template.html` | Inline-CSS animation patterns (bars, counters, timeline, quote) |
| `docs/SETUP.md` | Termux + PRoot + Modal install |
| `docs/RESEARCH.md` | Research stage with 3 ways to satisfy |
| `docs/TROUBLESHOOTING.md` | Common gotchas (Modal wheel, Playwright headless_shell, ffmpeg AAC) |

## Key design choices (the WHY)

### Why HTML+CSS animations over PIL/Manim/After Effects?
- CSS keyframes are declarative and version-controllable in git
- All 16 slides share one stylesheet → consistent visual language
- Playwright records 1920x1080 @ 25fps with frame-perfect timing
- No raster intermediate = no quality loss until final encode

### Why Playwright Chromium over ffmpeg drawtext or ComfyUI?
- Playwright can record webm via MediaRecorder natively
- Real CSS animations (transitions, keyframes) work out of the box
- No need to compose static PNG frames and stitch them
- Trade-off: recording is real-time (10 min video = 10 min render)

### Why cloud ffmpeg (Modal) over local?
- Local libx264 software encode is 0.2-0.5x speed on ARM64 (phone)
- A 10-min video would take 4-8 HOURS to encode locally
- Modal: 8 vCPU cloud, CRF 20, medium preset → 72 seconds
- Free tier: $30/month credit (enough for 100+ encodes)
- Reference: `devops/modal-cloud-encode-termux` skill for setup

### Why sidechain compression on BGM?
- BGM at full volume competes with voice → listener fatigue
- Sidechaincompress detects voice peaks, ducks BGM by 8:1
- Result: clear narration, music never overwhelms
- Final loudnorm at -14 LUFS (TikTok/YouTube standard)

## Gotchas to watch for (full list in repo's docs/TROUBLESHOOTING.md)

1. **Modal wheel broken on Termux**: `modal>=1.4.3` wheel is missing
   `__init__.py` (manylinux mismatch). Pin to `modal>=1.0,<1.4`.
   If still broken, patch `__init__.py` with placeholder. Full fix in
   `devops/modal-cloud-encode-termux` skill.

2. **Playwright `headless_shell` missing**: `playwright install chromium`
   defaults to the slim `headless_shell` which can't record. Install
   the full Chromium (NOT `...-headless-shell`) and set `CHROME_PATH`
   env var to the full binary.

3. **`toml` import at module top in modal_encode.py**: Modal's cloud
   container doesn't have `toml`. Move `import toml` inside a function
   that runs locally before `app.run()`. Full fix and copy-paste
   template in `devops/cloud-video-encoding` skill (references/modal-encode.md).

3b. **Hardcoded webm filename in modal_encode.py**: The render script
    generates hash-suffixed filenames (e.g. `page@7601c9fef3...webm`).
    Don't hardcode — auto-glob: `glob.glob("recordings/*.webm")` and
    assert exactly 1 match. Or use `sorted(glob)[0]` to pick the latest.

4. **edge-tts rate limits**: 60-second timeout on Microsoft's
   endpoint. If you get 403/timeout, wait or switch voices.

5. **Gemini API key leak detection**: If user pastes a key in chat,
   Google's auto-flagging may 403 it within minutes. Always load
   keys from .env via Python (terminal blocks inline reads). If a
   key is flagged, ask user to revoke + create new one.

6. **Gemini TTS free-tier daily quota is 10 requests/day** on
   `gemini-2.5-flash-tts`. Pro model has 0 free quota. There is
   no in-session recovery — when you hit 429 RESOURCE_EXHAUSTED,
   the run is over. **Plan the fallback (edge-tts, secondary key)
   BEFORE starting a >10-slide run.** Full code template, voice
   list, and hybrid strategy in `references/gemini-tts.md`.

7. **Watermark visibility**: white text on dark background with
   0.5 opacity, 0.15 alpha border, blur(4px) backdrop — visible on
   every color but never overpowering. Hard-coded in CSS.

8. **fmp4 faststart**: `-movflags +faststart` is REQUIRED for web
   playback (moves moov atom to start of file). Forgetting this
   means videos won't play in-browser without full download.

9. **Storage path inside PRoot**: `/storage/emulated/0/Movies/` may
   not be mounted. Test with `ls /mnt/sdcard/Movies/` or run
   `termux-setup-storage` outside PRoot.

10. **LSP warnings on `modal.Function.remote`**: Pyright can't infer
    `.remote` on Modal's wrapped function. The runtime works. Add
    `# type: ignore[attr-defined]` to silence.

## Customization entry points

| User wants to... | Edit |
|-------------------|------|
| Change voice | `01_generate_tts.py --voice` (or `01b_tts_gemini.py --voice`) |
| Change watermark | `--watermark` flag in `02_build_slides.py` |
| Change BGM | `--bgm` flag in `04_mix_audio.py` |
| Add a new slide type | New layout in `02_build_slides.py` `render_slide_html()` |
| Change theme (colors) | `CSS` block in `02_build_slides.py` |
| Change TTS engine | New script in `pipeline/01b_*` then call in `run_all.sh` |
| Deploy to YouTube | Add `07_youtube_upload.py` using `yt-dlp` or google-api-python-client |
| Change aspect ratio | Edit `1920x1080` in `03_render.js` viewport + modal ffmpeg pix_fmt |

## What to ask the user before starting

- Topic + research source (have they done research, or want Stage 0?)
- Voice preference (Indonesian girl, English woman, etc.)
- Watermark text (default "● PatrickNoFilter")
- BGM source (YouTube URL or local file)
- Length target (10 min is sweet spot; <5 min wastes pipeline, >20 min
  may exceed Modal free tier credits)

## Reference implementations / variations

- **pocket-director** (canonical): phone + Modal + edge-tts or Gemini
  TTS, Playwright HTML+CSS recording, ffmpeg audio mix. MIT.
  https://github.com/PatrickNoFilter/pocket-director
- **html-video skill** (in Hermes `creative/`): different approach
  using nexu-io/html-video server, NOT Playwright. May be slower
  but easier setup. Use if user doesn't want cloud GPU/server.
- **manim-video skill** (in Hermes `creative/`): Manim CE
  animations, Python-only. Use for math and data viz content, not
  documentary narration.
- **animated-infographic-video-generation-node** (in Hermes
  `creative/`): node-based tool chain. Use if user has Node
  installed and prefers JS-driven pipelines.

## See also

- `devops/modal-cloud-encode-termux` — full Modal setup including
  grpclib patch and `toml` module-top gotcha
- `devops/termux-proot-environment` — Termux + PRoot Ubuntu setup,
  including venv + RTK notes
- `creative/humanizer` — strip AI-isms from narration script
  before recording (storytelling quality matters)
- `playwright-termux-arm64` — Playwright Chromium on PRoot
