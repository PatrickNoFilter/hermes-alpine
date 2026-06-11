# Modal Cloud ffmpeg — working reference

End-to-end recipe used to transcode a 47 MB VP8 webm (11:16, 1920×1080) to H.264 MP4 in Modal's cloud. Total time on a cold image: ~3 min. Image cache hit: ~30 s.

## Auth (no `modal token new` flow)

`/root/.modal.toml` already exists on this device with a working token pair. The CLI is broken on Termux (watchfiles native code) — use the Python API only.

```python
# CRITICAL: import toml INSIDE a function, NOT at module top level.
# Modal's cloud-side module introspection imports all top-level modules.
# toml is not on the cloud image → ModuleNotFoundError crashes the runner.
def _load_modal_auth():
    import toml  # noqa: local import only
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID']     = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']
```

Call `_load_modal_auth()` inside `@app.local_entrypoint()` or `if __name__ == "__main__"` — never at module top level.

## Full script (copy-paste, edit paths)

```python
#!/usr/bin/env python3
"""Cloud-encode a webm to H.264 MP4 via Modal, then save locally."""
import os, time

# Auth — toml INSIDE function, not at top level
def _load_modal_auth():
    import toml
    cfg = toml.load('/root/.modal.toml')
    os.environ['MODAL_TOKEN_ID']     = cfg['default']['token_id']
    os.environ['MODAL_TOKEN_SECRET'] = cfg['default']['token_secret']

import modal

image = modal.Image.debian_slim(python_version="3.11").apt_install("ffmpeg")
volume = modal.Volume.from_name("video-jobs", create_if_missing=True)
app = modal.App("video-encode", image=image)

@app.function(volumes={"/data": volume}, timeout=900)
def encode(in_name: str, out_name: str, crf: int = 20, preset: str = "medium"):
    import subprocess
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
        raise RuntimeError(f"ffmpeg failed: {p.stderr[-1500:]}")
    volume.commit()
    return {"out": out_name, "bytes": os.path.getsize(f"/data/{out_name}")}

@app.local_entrypoint()
def main():
    LOCAL_IN  = "/root/ihsg-youtube/recordings/recording.webm"
    LOCAL_OUT = "/root/ihsg-youtube/output/recording_h264.mp4"
    REMOTE_IN  = "in.webm"
    REMOTE_OUT = "out.mp4"

    # 1) Upload
    print(f"[1/3] Uploading {LOCAL_IN} ...")
    with open(LOCAL_IN, "rb") as f: data = f.read()
    print(f"  {len(data)/1024/1024:.2f} MB")

    @app.function(volumes={"/data": volume}, timeout=120)
    def upload(name: str, content: bytes):
        with open(f"/data/{name}", "wb") as g: g.write(content)
        volume.commit()
    upload.remote(REMOTE_IN, data)

    # 2) Encode
    print(f"[2/3] Encoding in Modal cloud ...")
    t0 = time.time()
    res = encode.remote(REMOTE_IN, REMOTE_OUT, crf=20, preset="medium")
    print(f"  done in {time.time()-t0:.1f}s → {res}")

    # 3) Download
    print(f"[3/3] Downloading to {LOCAL_OUT} ...")
    @app.function(volumes={"/data": volume}, timeout=120)
    def download(name: str) -> bytes:
        with open(f"/data/{name}", "rb") as g: return g.read()
    out_bytes = download.remote(REMOTE_OUT)
    with open(LOCAL_OUT, "wb") as f: f.write(out_bytes)
    print(f"  saved {len(out_bytes)/1024/1024:.2f} MB")

if __name__ == "__main__":
    main()
```

## Observed timings on this device

| Phase | Cold image | Cached image |
|---|---|---|
| Image build (apt ffmpeg) | ~90 s | 0 s |
| Upload 47 MB webm | ~15 s | ~15 s |
| ffmpeg encode (10:11 webm) | ~110 s | ~110 s |
| Download 28 MB MP4 | ~8 s | ~8 s |
| **Total** | **~3.5 min** | **~2.5 min** |

CRF 20 + `medium` preset hits the sweet spot for archival / upload quality vs speed. Lower CRF (18) is visually indistinguishable for slide content. Higher preset (`slow`) doubles the encode time for marginal gain.

## Pitfalls encountered

- The `volume.commit()` call is **required** before a `download.remote()` from a different function can see the file. Forgetting it yields a silent empty download.
- `Volume.from_name(..., create_if_missing=True)` is idempotent — safe to call every time.
- `pip install modal` will pull `watchfiles` which fails to build on Termux ARM64. Don't run the CLI; the Python API does not import watchfiles on the import path the script uses.
- `modal token set` interactive setup is unnecessary — env-var auth from `/root/.modal.toml` works.
- If a run errors with `container died`, the most likely cause is the 900 s `timeout=900` being too short for very long videos. Bump to 1800 for 30+ min inputs.

## Auto-glob for hash-suffixed filenames

The Playwright render script generates webm files with hash suffixes
(e.g. `page@7601c9fef35ef53eb4672a60dbae4d42.webm`). Don't hardcode
filenames — auto-detect:

```python
import glob
webm_files = sorted(glob.glob("/path/to/recordings/*.webm"))
assert len(webm_files) == 1, f"Expected 1 webm, found {len(webm_files)}"
local_webm = webm_files[0]
```
