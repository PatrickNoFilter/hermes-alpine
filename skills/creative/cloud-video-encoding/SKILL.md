---
name: cloud-video-encoding
title: Cloud Video Encoding (when local ffmpeg is too slow)
description: >-
  Offload long video transcodes (VP8/VP9 webm → H.264 MP4, concat, mux) to the cloud when local ffmpeg is impractical.
  Full pipeline support: record (Playwright + xvfb) → encode → mux → download, all on Modal.
  Covers Modal Python API on Termux ARM64, YouTube unlisted as a free transcode service, TTS selection for
  Indonesian narration, and a decision matrix. Trigger when: a video task needs encoding longer than ~5 min,
  the device has no hardware accel (no nvenc/qsv/vaapi), the user asks for "cloud encoding" / "not on this machine",
  or the user wants end-to-end video production in the cloud.
tags:
  - ffmpeg
  - video
  - encoding
  - modal
  - termux
  - arm64
  - cloud
---

## When to use

Local ffmpeg on Termux ARM64 (no hardware accel, 12 software cores) hits a wall:
- **>5 min** 1080p VP8/VP9 webm → H.264 MP4 takes 20–50+ min
- Mid-encode kills (e.g. cleanup `kill -9`) leave a **corrupt MP4** that fails NAL parsing
- Drains the device for the duration

If the user says "encode in the cloud", "not on this machine", "hyperframes cloud", or any cloud-encoding intent, **default to this skill** — do not retry the local path.

## Decision matrix

| Option | Speed (10 min 1080p) | Cost | Setup | Reliability |
|---|---|---|---|---|
| **Modal cloud ffmpeg** | ~2–3 min | Free tier covers it | `~/.modal.toml` already exists | High — same ffmpeg, just faster hardware |
| **YouTube unlisted upload → yt-dlp** | ~20–40 min | Free, no quota | Needs Google OAuth + bgutil-ytdlp-pot-provider for upload | Medium — YT processing queue + bot detection |
| **Local `-preset ultrafast -threads 0`** | ~5–10 min (1–2x realtime) | Free | None | High but drains device |
| **Streamable.com / Catbox.moe upload** | Upload only, no transcode | Free | None | Low — neither re-encodes to H.264 on free tier |

**Default: Modal.** Fall back to YouTube if Modal fails. Avoid local ultrafast unless the user explicitly accepts device drain.

## Modal cloud ffmpeg pattern (Termux-safe)

**Why Python API, not CLI:** On Termux, `uv pip install modal` succeeds, but the `modal` CLI crashes with a `watchfiles` native-code error. Use the Python API only.

**Auth (no login flow):**
```python
# CRITICAL: toml INSIDE function, NOT at module top level.
# Modal's cloud-side module introspection imports all top-level modules.
# toml is not on the cloud image → ModuleNotFoundError crashes the runner.
def _load_modal_auth():
    import toml  # noqa: local import only
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID']     = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']

# Call _load_modal_auth() inside @app.local_entrypoint() or if __name__
```

**CRITICAL: @app.function must be at MODULE level.** Modal rejects `@app.function` decorators inside `main()` or other functions — raises `InvalidError`. Define all cloud functions at the top level of the file.

**Minimal encode function (upload + encode + commit):**
```python
import modal, os
image = modal.Image.debian_slim(python_version="3.11").apt_install("ffmpeg")
volume = modal.Volume.from_name("video-jobs", create_if_missing=True)
app = modal.App("encode", image=image)

@app.function(volumes={"/data": volume}, timeout=900)
def encode(in_name: str, out_name: str, crf: int = 20, preset: str = "medium"):
    cmd = [
        "ffmpeg", "-y", "-i", f"/data/{in_name}",
        "-c:v", "libx264", "-preset", preset, "-crf", str(crf),
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        "-threads", "0",
        f"/data/{out_name}",
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-1000:])
    volume.commit()
    return {"out": out_name, "size": os.path.getsize(f"/data/{out_name}")}

@app.local_entrypoint()
def main(local_in: str, local_out: str, remote_in: str = "in.bin", remote_out: str = "out.mp4"):
    with open(local_in, "rb") as f: data = f.read()
    @app.function(volumes={"/data": volume}, timeout=60)
    def upload(name, content):
        with open(f"/data/{name}", "wb") as g: g.write(content)
        volume.commit()
    upload.remote(remote_in, data)
    encode.remote(remote_in, remote_out)
    @app.function(volumes={"/data": volume}, timeout=120)
    def download(name) -> bytes:
        with open(f"/data/{name}", "rb") as g: return g.read()
    with open(local_out, "wb") as g: g.write(download.remote(remote_out))
```

**Cold-start gotcha:** First `apt_install("ffmpeg")` image build takes 1–2 min on Modal's free tier. After that, the image is cached and subsequent calls start in ~3 s. Don't set tight timeouts on the first run.

## YouTube unlisted upload (free, slow) — fallback

When Modal fails or credits are exhausted, YouTube will re-encode the webm to H.264/AAC for free and `yt-dlp` can pull the resulting stream back. ~20–40 min total because of YT's processing queue.

1. Upload via OAuth2 — the `bgutil-ytdlp-pot-provider` HTTP server (running on port 4416) handles the bot-detection bypass.
2. Wait for YT to finish processing (poll with `yt-dlp --list-subs` until formats appear).
3. `yt-dlp -f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]" -o final.mp4 <unlisted-url>`

Trade-offs: privacy (the file lives on Google's CDN), processing latency, and the free tier is rate-limited.

## Mux the audio locally (fast, not the bottleneck)

After cloud encoding returns the H.264 video MP4, mux with the TTS+BGM audio locally. This is cheap (minutes, not 25+) and worth keeping on-device so the audio mix is deterministic:

```bash
ffmpeg -y -i video_h264.mp4 -i audio_mixed.mp3 \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
  final.mp4
```

`-c:v copy` skips re-encoding the video (already H.264 from the cloud). `-shortest` trims to the shorter of the two streams.

## Full Modal pipeline (record → encode → mux → download)

For end-to-end video production entirely in the cloud, use a single Modal app with:
1. **Record** — Playwright + Chromium + xvfb in a Modal container (see image setup below)
2. **Encode** — webm → H.264 MP4 (same pattern as above)
3. **Mux** — video + TTS audio → final MP4
4. **Download** — pull final MP4 to local storage

**Image with Playwright + Chromium + xvfb:**
```python
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install(
        "ffmpeg", "xvfb", "curl", "ca-certificates",
        "fonts-liberation", "libnss3", "libatk-bridge2.0-0",
        "libdrm2", "libxkbcommon0", "libgbm1", "libasound2",
        "libpango-1.0-0", "libcairo2", "libatspi2.0-0",
    )
    .run_commands(
        "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -",
        "apt-get install -y nodejs",
        "npm install -g playwright",
        "npx playwright install --with-deps chromium",
    )
)
```

**Skip-record optimization:** If an existing webm is close to the expected duration (from manifest.json), skip recording and just encode + mux. Saves ~12 min of recording time.

**Observed timings (11 min 1080p video):**

| Step | Cold | Cached |
|------|------|--------|
| Image build (first run) | ~6 min | 0 |
| Upload 81 MB webm | ~30s | ~30s |
| Encode (crf=20, medium) | ~50s | ~50s |
| Mux (video copy + AAC) | ~13s | ~13s |
| Download 67 MB | ~15s | ~15s |
| **Total** | **~2 min** | **~2 min** |

Full working script: `/root/ihsg-youtube/modal_full_pipeline.py`

## Pitfalls

- **`import toml` at module level crashes Modal.** Modal's cloud-side module introspection imports all top-level modules. `toml` is not on the cloud image → `ModuleNotFoundError`. Fix: move `import toml` inside the function that uses it (e.g. `_load_modal_auth()`).
- **`@app.function` inside `main()` raises `InvalidError`.** Modal requires all `@app.function` decorators at module global scope. Define cloud functions at the top level, call them from `main()`.
- **`volume.commit()` required before download.** Forgetting it yields a silent empty download from a different function.
- **Never `rm -rf` a directory that has artifacts** (installed `node_modules`, build caches, prior renders) without explicit user consent. The Hermes safety system blocks destructive commands on non-empty dirs. Clone to a **new** directory instead (e.g. `html-video-fresh/` not `rm -rf html-video`).
- **Don't kill a running ffmpeg mid-encode.** Wait for the `[mp4 @ ...] Starting second pass: moving the moov atom` log line — that is the post-processing step, after which the file is valid. Killing before that yields a corrupt MP4 even though `ls` shows the file size looks right.
- **Modal first call is slow** because of image build; don't interpret a 90-s pause as failure. First Playwright+Chromium image build takes ~6 min.
- **Mixed-source concat** (different encoders / timebases) must use the **concat filter**, not the concat demuxer — see `html-video` skill for the full pattern and the verification commands.
- **Don't trust "ffmpeg exited 0"** as proof of valid output for mixed concat — always `ffprobe` and run `ffmpeg -f null -` over the result to confirm clean decode.
- **xvfb-run needed for Playwright in containers.** Use `xvfb-run --auto-servernum node render.js` — Playwright needs a display server even in headless mode on some container setups.

## References

- `references/modal-encode.md` — full working `modal_encode.py` from a real run, with auth loading and upload/download helpers
- `references/tts-indonesian-comparison.md` — TTS provider comparison for Indonesian narration (Edge-TTS vs OpenAI vs Gemini)
- `references/youtube-unlisted.md` — full YouTube upload + yt-dlp roundtrip recipe with the bgutil POT provider
- `scripts/modal_encode_template.py` — copy-paste starter, fill in input/output paths
- `/root/ihsg-youtube/modal_full_pipeline.py` — full working pipeline (record → encode → mux → download) with skip-record optimization
- `playwright-termux-arm64` skill — upstream step that produces the webm this skill consumes
- `html-video` skill — the "Hyperframes cloud" path; the user's term "hyperframes cloud" typically means "run ffmpeg in a cloud container" rather than a literal Hyperframes SaaS
