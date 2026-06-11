# Edge-TTS — batch TTS for any-length videos

Use `pipeline/01_generate_tts.py` (or the project's `scripts/gen_edge_tts.py`) for
unlimited free TTS with no daily quota. Edge-TTS uses Microsoft's Azure Neural voices.

## When to use Edge-TTS over Gemini

- **>10 slides** — Gemini's 10/day free quota can't handle it
- **Consistency** — same voice across all slides (no quota-driven engine switching)
- **Speed** — ~5s per slide, no rate-limit sleep needed
- **Zero cost** — no API key, no billing, no quota anxiety

When to prefer Gemini: quality-sensitive narration where natural prosody matters
(mostly for videos <10 slides).

## Indonesian voices

| Voice | Gender | Tone | Best for |
|-------|--------|------|----------|
| `id-ID-GadisNeural` | Female | Friendly, clear | **Default narration** |
| `id-ID-ArdiNeural` | Male | Friendly, positive | Male narration |

Both handle Indonesian text cleanly. GadisNeural is slightly slower (matches Gemini Kore pacing).
ArdiNeural speaks ~20% faster.

## Batch generation script

```python
#!/usr/bin/env python3
"""Generate all slides with Edge-TTS. No API key needed."""
import json, subprocess, time
from pathlib import Path

VOICE = "id-ID-GadisNeural"
EDGE_TTS = "/root/ihsg-youtube/venv/bin/edge-tts"  # or just "edge-tts" if on PATH
OUTDIR = Path("/root/ihsg-youtube/audio")

slides = json.loads(Path("/root/ihsg-youtube/tts_manifest.json").read_text())
manifest = []

for s in slides:
    out_path = OUTDIR / f"slide_{s['num']:02d}.mp3"
    # Optional: fix branding text before TTS
    text = s['text'].replace('Dokumenter ini', 'Infografis ini')
    
    cmd = [EDGE_TTS, "--voice", VOICE, "--text", text, "--write-media", str(out_path)]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        print(f"  [{s['num']:02d}] FAILED: {p.stderr[:200]}")
        continue
    
    # Get duration via ffprobe
    dur_p = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(out_path)],
        capture_output=True, text=True
    )
    dur = float(dur_p.stdout.strip()) if dur_p.stdout.strip() else 0
    dt = time.time() - t0
    print(f"  [{s['num']:02d}] {dur:.1f}s ({dt:.1f}s wall)")
    
    manifest.append({"num": s['num'], "file": str(out_path), "dur": dur,
                      "model": f"edge-tts/{VOICE}"})
    time.sleep(0.5)

# Write manifest for render_animated.js
(OUTDIR / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
total = sum(m['dur'] for m in manifest)
print(f"\nDONE: {len(manifest)} MP3s | Total: {total:.1f}s ({total/60:.1f} min)")
```

## Content branding changes

When rebranding (e.g. "Dokumenter" → "Infografis"), update in **all three places**:
1. **HTML** (`slide_video.html`) — visual text on slides
2. **Narration text** (`tts_manifest.json`) — what TTS reads aloud
3. **TTS audio** — regenerate affected slides (or all slides for consistency)

The TTS audio is generated FROM the narration text, so if you fix the text and
regenerate, the audio automatically picks up the change. But the HTML is separate
— it must be edited manually.

## Concat into full audio

```bash
cd /root/ihsg-youtube/audio
# Build concat list
for f in slide_*.mp3; do echo "file '$f'"; done | sort > concat_list.txt
# Concat + re-encode to high-quality MP3
ffmpeg -y -f concat -safe 0 -i concat_list.txt -c:a libmp3lame -q:a 2 tts_full.mp3
```

## Edge-TTS quirks

- **No rate limit** — but add 0.5s sleep between calls to be polite to Microsoft's endpoint
- **60-second timeout** — if a single slide text is >5000 chars, it may timeout. Split long slides.
- **SSML support** — Edge-TTS supports SSML for pacing/pitch control. Prefix text with
  `<speak>` and use `<break time="500ms"/>` for pauses.
- **Output format** — MP3 by default. Can also output `audio/raw-24khz-16bit-mono-pcm` via
  `--write-media` with `.raw` extension.

## See also

- `references/gemini-tts.md` — Gemini TTS workflow, quota, hybrid strategy
- `pipeline/01_generate_tts.py` — the production Edge-TTS script in pocket-director
