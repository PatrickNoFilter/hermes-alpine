---
name: html-video
description: Convert HTML/CSS templates to videos using nexu-io/html-video meta-layer. Works in ARM64 PRoot environments.
category: creative
---
# HTML-to-Video Conversion with nexu-io/html-video

Skill for converting HTML templates to videos using the nexu-io/html-video meta-layer. Works in ARM64 PRoot environments (e.g., Termux) using Playwright's standalone Chromium.

## When to Use
- Creating videos from HTML/CSS/templates (documentaries, presentations, explainers)
- When you need programmatic video generation with agent-friendly workflows
- Working in ARM64 PRoot environments where Chromium snap fails but Playwright Chromium works
- Using pre-built templates or custom HTML designs

## CLI Workflow
1. **Clone repository** (if not already present):
   ```bash
   git clone --depth 1 https://github.com/nexu-io/html-video.git
   cd html-video
   ```

2. **Create project**:
   ```bash
   node packages/cli/dist/bin.js project-create --name "your-project-name"
   ```

3. **Set template** (choose appropriate template for your use case):
   ```bash
   # List available templates
   node packages/cli/dist/bin.js list-templates
   
   # Set template (examples: frame-data-chart-nyt, frame-ihsg-dsi, frame-glitch-title)
   node packages/cli/dist/bin.js project-set-template <project-id> --template <template-id>
   ```

4. **Add HTML asset**:
   ```bash
   node packages/cli/dist/bin.js project-add-asset <project-id> --file /path/to/your/template.html
   ```

5. **Preview** (optional):
   ```bash
   node packages/cli/dist/bin.js project-preview <project-id>
   # Opens preview.html in browser
   ```

6. **Render to MP4**:
   ```bash
   node packages/cli/dist/bin.js project-render <project-id>
   # Output: .html-video/projects/<project-id>/output-<timestamp>.mp4
   ```

## Template Selection Guide
- **Single-frame templates** (e.g., frame-data-chart-nyt): Best for static charts, title cards, simple graphics. Output duration depends on template design (often short).
- **Multi-frame templates** (e.g., frame-ihsg-dsi): Designed for slide-based content, documentaries, sequences. Supports ?slide=N navigation for direct access to specific frames.
- **Check template metadata**: Use `inspect-template` to see duration, resolution, and capabilities.

## ARM64 PRoot Notes
- Works with Playwright's standalone Chromium (no snap required)
- No GPU acceleration needed (CPU rendering is sufficient for most templates)
- Ensure Node.js >=20 and pnpm >=9 are available
- First run may take time to download Chromium binaries (~100MB)

## Verification
Check output properties with:
```bash
ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=width,height,r_frame_rate -of csv=p=0 output.mp4
```

## Common Templates
| Template ID | Best For | Duration Type |
|-------------|----------|---------------|
| frame-data-chart-nyt | NYT-style animated charts | Fixed (short) |
| frame-ihsg-dsi | 16-slide documentaries | Fixed (80-90s) |
| frame-glitch-title | Animated title cards | Fixed |
| frame-liquid-bg-hero | Gradient hero sections | Fixed |
| frame-product-promo | Product showcases | Multi-scene |

## Troubleshooting
- **Blank video**: Check if template supports your HTML structure
- **Short output**: Verify you selected a multi-frame template for slide content
- **Font issues**: Templates include font-loading safeguards to prevent FOUT
- **Missing dependencies**: Run `pnpm install` in repository root if needed

## CRITICAL: Mixed-source concat MUST use concat filter, not demuxer

If you stitch videos from **different sources** (e.g. Hyperframes segment + Remotion segment, or any two videos with different encoders, timebases, or pixel formats), the **concat demuxer** (`-c copy -f concat -i list.txt`) will **silently corrupt the timestamps** — a real 8 s output can become a 35 s file with broken playback. Adding `-vsync cfr` does **not** fix it; bad PTS is already in the stream by then.

**The only correct approach for mixed sources is the concat filter**, which decodes each input independently and rebuilds a single timebase:

```bash
ffmpeg -y \
  -i segment_a.mp4 \
  -i segment_b.mp4 \
  -i segment_c.mp4 \
  -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1[v]" \
  -map "[v]" -map "0:a?" -map "1:a?" -map "2:a?" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -c:a aac -b:a 192k -shortest \
  -movflags +faststart \
  final.mp4
```

**Verification is mandatory** for mixed-source concat — never trust "ffmpeg returned 0 and the file exists":
- `ffprobe` the output and check `duration` matches expected total
- Run `ffmpeg -f null -` over the output to confirm full decode (catches PTS corruption that the player would choke on)
- Spot-check timestamps at segment boundaries

**Single-source concat** (one encoder, one timebase) can still use the concat demuxer with `-c copy` — it's fast and lossless. Use concat filter only when the sources differ.

## Project state (as of 2026-06-07 main)

These notes are from reading `CLAUDE.md` in the cloned repo — they explain what is and isn't actually wired up:

- `adapter-hyperframes` is **still a stub** on main as of mid-2026 — single-frame and multi-frame export paths produce empty files. Don't expect the Hyperframes adapter to deliver MP4 end-to-end yet.
- `adapter-remotion` is the working renderer; native Remotion templates live in `templates/frame-*/` (e.g. `frame-data-rollup` for animated bar charts with `spring()` and `interpolate()` number counters).
- Remotion is a **user-initiated per-frame enhancement plugin**, not an auto-replacement for Hyperframes. The model is: Hyperframes is the base; the user opts a frame into Remotion via `enhanceFrameNative(projectId, nodeId, nativeTemplateId)`.
- A working multi-frame export pipeline exists: `exportMp4` → ffmpeg concat filter (see pitfall above) → 8.000 s MP4 verified end-to-end with `ffprobe` + `-f null -` decode check.
- PR review convention: **squash merge**, don't add new commits to an already-merged PR (the next one gets lost — cherry-pick into a new branch instead).

## References
- Repository: https://github.com/nexu-io/html-video
- Template gallery: https://github.com/nexu-io/html-video#template-gallery
- Engine architecture: Pluggable (Hyperframes default, Remotion/Motion Canvas planned)