---
name: infographic-video-generation
title: Animated Infographic Video Generation (ARM64/Proot)
description: Guidance for installing, configuring, and running the open‑source azharlabs/infographic‑video‑generation pipeline on low‑resource ARM64/Android Proot Ubuntu environments.
summary: |
  Step‑by‑step instructions, prerequisite list, common pitfalls and scaling tips for turning text/CSV into animated infographic videos on ARM64.
categories:
  - video
  - AI
  - python
  - infographic
---

## Trigger
When a user asks for an open‑source tool that can turn scripted text or CSV data into an animated infographic video, especially targeting low‑resource ARM64/Android environments.

## Prerequisites
- **Python ≥ 3.8** (the system already provides 3.13).
- **ImageMagick** (`apt-get install -y imagemagick libmagickcore-6.q16-6 libmagick++-6.q16-6`).
- **ffmpeg** (`apt-get install -y ffmpeg`).
- **OpenAI API key** (set in `.env` → `OPENAI_API_KEY`).
- Minimum **8 GB RAM** recommended for video conversion.

## Installation Steps
1. ```bash
   git clone https://github.com/azharlabs/infographic-video-generation.git && cd infographic-video-generation
   ```
2. Create a virtual environment and activate it:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
   *If any wheel fails on ARM, reinstall with `--no-binary :all:`.*
4. Copy the example env file and insert your OpenAI key:
   ```bash
   cp .env.example .env
   # edit .env → OPENAI_API_KEY=***
   ```
5. Verify native tools:
   ```bash
   convert -version   # ImageMagick
   ffmpeg -version    # ffmpeg
   ```

## Quick Demo
Create `demo.txt` with slide markdown, then run:
```bash
python main.py --input demo.txt --output demo.mp4
```
The script will:
1. Chunk text using the RAG pipeline (LlamaIndex + GPT‑4).
2. Build a PPTX with `python-pptx`.
3. Generate per‑slide animations via Matplotlib + ImageMagick.
4. Assemble the final video with MoviePy/ffmpeg.

## Common Pitfalls on ARM64
| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImportError: libmagickwand.so` | ImageMagick not found or wrong lib path | `apt-get install libmagickwand-dev` and ensure `/usr/lib` is in `LD_LIBRARY_PATH` |
| OOM during video conversion | Insufficient RAM / large batch size | Reduce `batch_size` or `chunk_size` in `utils/csv_rag.py`; process fewer slides at a time |
| `ffmpeg` codec error | Missing codec package | `apt-get install libx264-dev` or install `ffmpeg` from a repository that includes `libx264` |
| Slow generation > 10 min | No hardware acceleration, heavy animation | Disable animation (`--no-animation` flag if added) or pre‑generate static GIFs. |

## Scaling Tips for Proot
- Use a swapfile (`dd if=/dev/zero of=/swapfile bs=1M count=2048 && mkswap /swapfile && swapon /swapfile`) if RAM is tight.
- Run the pipeline in a detached `screen`/`tmux` session to avoid killed processes when the terminal disconnects.
- Store generated videos on external storage (`/sdcard/Download`) to avoid filling the limited filesystem.

## References
- Repository README (raw) – see `references/README.md`.
- `requirements.txt` – list of Python packages.
- Official ImageMagick install guide for ARM64 – see `references/ImageMagick_ARM64.md`.

## Automation Hook (optional)
Add a short wrapper script (`scripts/run_infographic.sh`) that accepts a text file path and outputs a video, handling env activation and cleanup automatically.

---

*This skill is kept up‑to‑date for ARM64/Proot Ubuntu on Android. If new native dependencies appear, add them to the **Common Pitfalls** table.*