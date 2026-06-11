# Video Production Pipeline — Financial Documentary

Full pipeline from HTML prototype to final MP4, optimized for ARM64/PRoot environment.

## Pipeline Overview

```
Research → Narasi Script → TTS Audio → [html-video (primary)] or [PIL Slides + FFmpeg] → Concat → Final MP4
```

## Phase A: Narasi Script

Write a full script at `narasi-<topic>.md` with one section per slide. Keep each section to 35-45 seconds of spoken text (~70-90 words Indonesian, ~100-120 words English).

Format:
```markdown
# Narasi: [Judul Dokumenter]

## Slide 1 — Judul
[Opening paragraph]

## Slide 2 — Judul
[Content paragraph]

...
```

## Phase B: TTS Audio Generation

Per-slide audio using the text_to_speech tool:

1. Call the tool once per slide's narrative text
2. Save as `slide01.mp3`, `slide02.mp3`, ... (zero-padded)
3. After all audio generated, measure total duration:

```bash
for f in slide*.mp3; do
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  echo "$f: ${dur}s"
done
# Sum with python
python3 -c "
import subprocess, json, sys, glob
total = 0
for f in sorted(glob.glob('slide*.mp3')):
    r = subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','json',f], capture_output=True, text=True)
    d = json.loads(r.stdout)['format']['duration']
    total += float(d)
print(f'Total: {total//60:.0f}m {total%60:.0f}s')
"
```

**Target:** ~10 minutes total for 16 slides (~37s each)

## Phase C: Primary Rendering — html-video

**Environment prerequisites** — all available on this ARM64/PRoot system:
- Node.js >= 20 ✅
- pnpm ✅ (at `/root/.hermes/node/bin/pnpm`)
- ffmpeg 8.x ✅ (libx264 + AAC)
- Playwright Chromium ✅ (standalone, not snap; install with `npx playwright install chromium`)

**Setup html-video:**
```bash
# Clone repo
git clone https://github.com/nexu-io/html-video.git ~/html-video
cd ~/html-video

# Install deps
export PATH="/root/.hermes/node/bin:$PATH"
pnpm install
pnpm -r build

# Verify
node packages/cli/dist/bin.js doctor
```

**Render from existing HTML prototype:**
1. Open HTML prototype (`ihsg-dsi-prototype.html`) in the html-video studio:
   ```bash
   node packages/cli/dist/bin.js studio
   ```
   Navigates to http://127.0.0.1:3071

2. Use the Hermes agent inside the studio — paste the HTML file link, the agent auto-generates a multi-frame storyboard with timing, transitions, audio sync.

3. For CLI automation:
   ```bash
   node packages/cli/dist/bin.js search-templates --intent "data documentary slides"
   ```

**Also available:** The `hyperframes` CLI is pre-installed at `/root/.hermes/node/bin/hyperframes` for direct GSAP-animated compositions.

## Phase D: Fallback — PIL Slide Images

Use Pillow when html-video setup isn't possible:

```python
from PIL import Image, ImageDraw

W, H = 1920, 1080
img = Image.new("RGB", (W, H))
draw = ImageDraw.Draw(img)

# Background
draw.rectangle([(0, 0), (W, H)], fill=(10, 10, 15))

# Text
draw.text((60, 80), "Title", fill=(232, 232, 237))
draw.text((60, 160), "Body text here...", fill=(232, 232, 237))

img.save("slide01.png")
```

Use the `scripts/generate-slides.py` template. Key limitations:
- No emoji rendering
- No right-to-left text shaping
- Manual text wrapping (`textwrap.wrap`)
- Use html-video for complex layouts

## Phase E: FFmpeg Segment Rendering

Per-slide: combine image + audio into a video segment.

```bash
ffmpeg -y -loop 1 -i slide01.png -i slide01.mp3 \
  -c:v libx264 -tune stillimage \
  -c:a aac -b:a 128k \
  -pix_fmt yuv420p -shortest \
  -movflags +faststart \
  segment01.mp4
```

**Parameters explained:**
- `-loop 1`: loop the image indefinitely
- `-shortest`: end when audio finishes
- `-tune stillimage`: optimize H.264 for static content
- `-pix_fmt yuv420p`: ensure broad player compatibility
- `-movflags +faststart`: enable streaming/quick start

## Phase F: Concat

**Method 1 — Concat demuxer (fast, no re-encode):**
```bash
(for i in $(seq -w 1 16); do echo "file 'segment$i.mp4'"; done) > segments.txt

ffmpeg -f concat -safe 0 -i segments.txt -c copy final-video.mp4
```

**Method 2 — Re-encode (for transitions/crossfade):**
```bash
ffmpeg -f concat -safe 0 -i segments.txt \
  -vf "fade=t=in:st=0:d=0.5,fade=t=out:st=9:d=0.5" \
  -c:v libx264 -c:a aac final-video.mp4
```

## Verification

```bash
ffprobe -v error -show_entries format=duration,size,bit_rate \
  -of default=noprint_wrappers=1:nokey=1 final-video.mp4
# Returns: duration(s), size(bytes), bitrate(bps)
```

## ARM64 / PRoot Specifics

| Component | Status | Notes |
|-----------|--------|-------|
| Chromium (Playwright) | ✅ Available | `npx playwright install chromium` — standalone download to ~/.cache/ms-playwright/ |
| Chromium (system snap) | ❌ Doesn't work on PRoot | Use Playwright's bundled version instead |
| html-video pipeline | ✅ Supported | Primary rendering path |
| Hyperframes CLI | ✅ Pre-installed | At `/root/.hermes/node/bin/hyperframes` |
| FFmpeg H.264 | ✅ Available | Full software encode (no GPU needed for still-slide) |
| Pillow | ✅ Available | `pip install Pillow` — fallback only |
| TTS (built-in) | ✅ Available | Via text_to_speech tool |
| edge-tts | ⚠️ Voice disco may fail | Use built-in TTS as fallback |
| GPU encoding | ❌ No GPU | Software x264 fine for documentary slides |

## Improving Visual Quality

For richer visuals than Pillow can produce, use the html-video pipeline (Phase C) which renders the actual HTML prototype with CSS animations, data charts, and transitions via Playwright Chromium.
