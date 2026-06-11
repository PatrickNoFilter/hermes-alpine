---
name: modal-cloud-encode-termux
description: Cloud-encode video/audio via Modal ffmpeg from Termux/PRoot ARM64. Bypasses local CPU bottleneck (libx264 software encode is ~0.4x speed on ARM64, unusable for 10+ min videos). Use when user wants fast ffmpeg work without draining local machine, or has 1GB+ media to transcode.
---

# Modal Cloud ffmpeg Encode from Termux

Cloud-encodes video (or any ffmpeg job) in a Modal container. Modal provides fast x86_64 CPU + libx264 software encoding. For 11-min 1080p webm → MP4, expect ~70s encode + 18s upload + 9s download (vs 8+ hours locally on ARM64).

## When to use

- Local ffmpeg is too slow (ARM64 / no hardware accel / low CPU budget)
- File too big to leave on local disk
- User explicitly asks for cloud encoding ("hyperframes cloud", "modal cloud", "encode in cloud", "not on this machine")

## Setup (one-time)

Modal wheel is BROKEN on Termux ARM64 (modal 1.4.3 has no `__init__.py` — imports as namespace package → `from modal import App` fails with "unknown location"). **Pin to modal 1.3.5** which ships a proper `__init__.py`:

```bash
uv pip install --python-platform linux 'modal>=1.0,<1.4'
```

**Also fix grpclib** (installed as namespace package, modal does `from grpclib import Status, GRPCError`):

```python
# /root/.../venv/lib/python*/site-packages/grpclib/__init__.py
__version__ = "0.4.9"
from .const import Status
from .exceptions import GRPCError
```

If `from modal import App, Image, Volume` STILL fails with "unknown location", create `/.../modal/__init__.py` with lazy `__getattr__`:

```python
def __getattr__(name):
    if name == 'App': from .app import App; return App
    if name == 'Image': from .image import Image; return Image
    if name == 'Volume': from .volume import Volume; return Volume
    if name == 'Function': from .functions import Function; return Function
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

## Auth

Load `~/.modal.toml` and inject token IDs into env — must happen **locally only**, before any `.remote()` call:

```python
def _load_modal_auth():
    import toml  # INSIDE the function — see Pre-flight verification below
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID'] = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']
```

**CRITICAL**: Keep the `import toml` INSIDE this function. Module-level toml imports will be executed by Modal's cloud-side module walker and crash with `ModuleNotFoundError("toml")` because the cloud image (debian-slim + ffmpeg only) doesn't have `toml` installed. The `local_entrypoint` runs locally first, so this function is reached before any cloud code; the cloud walker never sees the import.

## Script template (modal_encode.py)

```python
import os, time
import modal  # NO toml/requests/etc import at module level — cloud has no toml

app = modal.App("my-encode")
image = modal.Image.debian_slim(python_version="3.11").apt_install("ffmpeg")
volume = modal.Volume.from_name("my-videos", create_if_missing=True)  # PERSISTENT

@app.function(image=image, volumes={"/data": volume}, timeout=1800, cpu=8)
def ffmpeg_encode(input_name: str, output_name: str, crf: int = 20, preset: str = "medium"):
    import subprocess
    cmd = ["ffmpeg", "-y", "-i", f"/data/{input_name}",
           "-c:v", "libx264", "-preset", preset, "-crf", str(crf),
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
           "-movflags", "+faststart", "-threads", "0",
           f"/data/{output_name}"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0: raise RuntimeError(f"ffmpeg failed: {p.stderr[-500:]}")
    volume.commit()
    return {"output": output_name, "size": os.path.getsize(f"/data/{output_name}")}

@app.function(volumes={"/data": volume}, timeout=300)
def upload_to_volume(filename: str, data: bytes):
    with open(f"/data/{filename}", "wb") as f: f.write(data)
    volume.commit()
    return {"uploaded": filename, "size": len(data)}

@app.function(volumes={"/data": volume}, timeout=600)
def download_from_volume(filename: str) -> bytes:
    with open(f"/data/{filename}", "rb") as f: return f.read()

def _load_modal_auth():  # LOCAL-ONLY — never called from cloud
    import toml
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID'] = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']

@app.local_entrypoint()
def main():
    _load_modal_auth()
    # 1. read local
    with open("local.webm", "rb") as f: data = f.read()
    # 2. upload (note: .remote, not direct call)
    upload_to_volume.remote("in.webm", data)
    # 3. encode
    ffmpeg_encode.remote("in.webm", "out.mp4", crf=20, preset="medium")
    # 4. download
    mp4 = download_from_volume.remote("out.mp4")
    with open("local.mp4", "wb") as f: f.write(mp4)

if __name__ == "__main__":
    with modal.enable_output():    # shows cloud container logs in terminal
        with app.run():             # enters Modal context — function .remote() calls work here
            main()
```

Run with `python modal_encode.py` in the venv. Cold start (apt-install ffmpeg) is ~30-40s. Subsequent runs use cached image and skip apt.

## Pattern notes (learned in production)

### The three-function pattern for large files
For files >10MB, **do not** try to pass data as a function argument and write to ephemeral storage — Modal's default ephemeral volume is wiped on container exit. Use a **persistent `modal.Volume`** with three separate functions:
1. `upload_to_volume(filename, data)` — writes the local file to the volume
2. `ffmpeg_encode(input, output)` — reads from the volume, writes back
3. `download_from_volume(filename)` — reads the encoded file back as bytes

Each function is a separate `app.function()` decorator. The volume persists between runs and across functions in the same `app.run()` context.

### `.remote()` vs direct call
Inside `app.run()` block, use `func.remote(...)` for cloud execution. Direct `func(...)` calls may not work the way you expect — Modal's wrapping means the function object isn't directly callable in the local process.

### `with modal.enable_output()`
Wraps `app.run()` to stream container stdout to the local terminal. Without it, you see only "running function..." messages, not the actual ffmpeg output or print statements. **Always include it for debugging.**

### Modal's own `Image.apt_install("ffmpeg")` is enough
Don't add `ffmpeg-python` or build ffmpeg from source. The debian-slim image with `apt_install("ffmpeg")` gives you everything: libx264, libvpx, aac, the works. ~30-40s build time on first run, cached forever after.

### Encoding for web playback
The command shown (`+faststart` + AAC + yuv420p) is the YouTube/web safe profile. For social media (TikTok, Instagram), this is also fine. If uploading directly to YouTube via their API, you can skip `+faststart` (they re-transcode anyway).

## Performance reference

- 47MB 1080p VP8 webm (11:16) → 27MB H.264 MP4: **72s encode cloud time**
- Upload: ~18s for 47MB
- Download: ~9s for 26MB
- Total: ~3 min vs 8+ hours locally

## Common pitfalls

- **Module-level toml/HTTP imports** → cloud container fails with ModuleNotFoundError. Move to function.
- **Modal CLI broken on Termux** (watchfiles native code crashes). Use Python API only.
- **Don't `rm -rf` anything** — destructive commands auto-block. Clone to fresh dir instead.
- **Run with `background=true` + `notify_on_complete=true`** if encoding might take >600s.

## Pre-flight verification (run before first launch)

Even when copying from the template, the project's actual `modal_encode.py` can drift and re-introduce the toml-at-top-level bug. Always grep before running:

```bash
# Find module-level imports that aren't modal itself (these will crash the cloud)
grep -nE '^(import |from )(toml|requests|yaml|pandas|dotenv)' modal_encode.py
# Output should be EMPTY. If not, move those imports inside the function that uses them.
```

A `ModuleNotFoundError("toml")` from `pkg/modal/_runtime/user_code_imports.py` during cold start is the diagnostic — Modal walks the module and tries to import every top-level import before any function is called.

## Puppeteer/Playwright webm filenames: never hardcode

Recordings from headless browser automation use hash-suffixed names that change per run, e.g. `recordings/page@7601c9fef35ef53eb4672a60dbae4d42.webm`. Hardcoding the path in `modal_encode.py` breaks after every re-render. Auto-discover instead:

```python
import glob
webm_candidates = sorted(glob.glob("/path/to/recordings/*.webm"))
assert len(webm_candidates) == 1, f"Expected 1 webm, found {len(webm_candidates)}: {webm_candidates}"
local_webm = webm_candidates[0]
```

The `assert` catches the case where zero or multiple recordings exist (e.g., a leftover from a prior failed render wasn't cleaned up). Always `rm` the old one before re-recording, or use a glob+assert pair.

## Orphaned ffmpeg processes from killed renderers

When the upstream render script (e.g., `render_animated.js`) is killed mid-flight, the inner ffmpeg `execSync` child process often survives as a detached orphan and keeps re-encoding the same webm. Symptom: `pgrep -af ffmpeg` shows processes with timestamps from a previous session, `output/video_only.mp4` keeps growing in the background. Always check before launching a new render:

```bash
pgrep -af ffmpeg
# If anything is running that you didn't start, kill it before the new render
pkill -9 -f 'ffmpeg.*output/'   # adjust pattern to match your output path
```

For a 7-min 1080p video, a stale ffmpeg encodes at ~0.4x on ARM64 — wastes 8+ minutes of CPU and disk I/O for no output gain.

## Standard pattern: video-only cloud encode + local mux with TTS audio

For projects that generate TTS audio separately from the visual recording (e.g., `audio_mixed.mp3` produced by `gemini-tts` from a manifest, then a Puppeteer render of the slide deck visuals), the cloud encoder should produce a **video-only MP4** and the audio gets muxed locally. This is much faster to re-iterate (no need to re-upload audio) and the TTS doesn't have to be regenerated for every visual tweak.

```python
# modal_encode.py — encode video only, no audio args
cmd = ["ffmpeg", "-y", "-i", f"/data/{input_name}",
       "-c:v", "libx264", "-preset", preset, "-crf", str(crf),
       "-pix_fmt", "yuv420p",
       "-an",  # strip any audio from the source webm
       "-movflags", "+faststart", "-threads", "0",
       f"/data/{output_name}"]
```

Then locally:

```bash
ffmpeg -y -i output/recording_h264.mp4 -i output/audio_mixed.mp3 \
       -c:v copy -c:a aac -b:a 192k -shortest \
       -movflags +faststart output/IHSG_Final.mp4
```

`-shortest` is critical: it makes the output duration match the shorter of the two streams, so a 1-frame mismatch at the tail doesn't bloat the file with silent video. Verify sync with `ffprobe` — both streams should report duration within ~1 frame of each other (e.g., 291.04s vs 291.03s for 25fps).

If `-c:a aac` re-encodes to a much lower bitrate than `-b:a 192k` (e.g., ffprobe reports 105kbps), don't panic — that's VBR for a near-silent track. Run `ffmpeg -i final.mp4 -af volumedetect -vn -f null -` to confirm `max_volume` is reasonable (> -20 dB). If it shows ~-90 dB, you have silent audio, not a re-encode issue.

## Verifying the final output

After mux, always run this 3-check before declaring done:

```bash
# 1. Both streams present and within 1 frame of each other
ffprobe -v error -show_streams output/Final.mp4 | grep -E 'index|codec_type|duration'

# 2. Audio not silent (max_volume > -20 dB)
ffmpeg -hide_banner -i output/Final.mp4 -af volumedetect -vn -f null - 2>&1 | grep max_volume

# 3. faststart applied (mov container)
ffprobe -v error -show_format output/Final.mp4 | grep format_name   # mov,mp4,m4a
```
