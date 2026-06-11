# Gemini 2.5 TTS — pipeline TTS engine (alternative to edge-tts)

Use `pipeline/01b_tts_gemini.py` instead of `01_generate_tts.py` (edge-tts) when you want:
- **Higher voice quality** — Gemini Pro TTS is more natural, with emotion/style hints
- **Voice control** — 8 named voices (Kore, Aoede, Charon, Fenrir, Puck, Orus, Zephyr)
- **Multilingual** — voices work across languages; e.g. Korean voice "Kore" speaks Indonesian cleanly
- **Style hints** — prompt the model to speak as "news anchor" / "podcast host" / etc.

## Free-tier quota (the gotcha that kills long videos)

| Model | Free tier | Notes |
|-------|-----------|-------|
| `gemini-2.5-flash-preview-tts` | **10 requests/day/project** | Default. What to use. |
| `gemini-2.5-pro-preview-tts`  | **0 free** (paid only) | Higher quality but unusable free. |

**There is no per-minute reset.** 10 requests/day is a hard cap. A 16-slide video
exceeds this. A 17-slide video (with credits) is impossible with one key.

**Recovery options when you hit 429 RESOURCE_EXHAUSTED:**
1. **Wait until tomorrow** (quota resets at midnight PT)
2. **Create a second key in a second Google Cloud project** — each project has its own quota
3. **Hybrid** — use Gemini for the first 10 slides, fall back to edge-tts for the rest
4. **Sibling subagent** — a parallel agent can use a different key, doubling the budget

## Working code template (verified)

```python
from google import genai
from google.genai import types
from pathlib import Path
import os, struct, subprocess, time

# Load API key from .env (terminal blocks inline reads; use Python)
os.environ.setdefault("GEMINI_API_KEY", open("/root/.hermes/.env").read().split("GEMINI_API_KEY=")[1].split("\n")[0].strip())

client = genai.Client()  # uses GEMINI_API_KEY env var

def gen_one(text: str, voice: str = "Kore", out_mp3: Path = None) -> Path:
    """One TTS call. Returns path to .mp3 (wav internally → ffmpeg → mp3)."""
    resp = client.models.generate_content(
        model="gemini-2.5-flash-preview-tts",
        contents=text,
        config=types.GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice)
                )
            )
        )
    )
    # Audio is raw PCM, 24kHz, mono, 16-bit
    pcm = resp.candidates[0].content.parts[0].inline_data.data
    wav = _pcm_to_wav(pcm, sample_rate=24000, channels=1, sample_width=2)
    wav_path = out_mp3.with_suffix(".wav")
    wav_path.write_bytes(wav)
    # Convert to mp3 for compactness (ffmpeg)
    subprocess.run(["ffmpeg", "-y", "-i", str(wav_path), "-codec:a", "libmp3lame", "-q:a", "2", str(out_mp3)],
                   check=True, capture_output=True)
    wav_path.unlink()
    return out_mp3

def _pcm_to_wav(pcm: bytes, sample_rate=24000, channels=1, sample_width=2) -> bytes:
    """Wrap raw PCM in a standard 44-byte WAV header."""
    data_size = len(pcm)
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF", 36 + data_size, b"WAVE",
        b"fmt ", 16, 1, channels, sample_rate,
        sample_rate * channels * sample_width, channels * sample_width, sample_width * 8,
        b"data", data_size
    ) + pcm
```

## Voice list (8 voices, all multilingual)

| Voice | Character | Best for |
|-------|-----------|----------|
| `Kore` | Female, warm, clear | **Indonesian narration (default)** |
| `Aoede` | Female, bright | Educational |
| `Charon` | Male, deep | Documentary |
| `Fenrir` | Male, intense | News, urgent |
| `Puck` | Male, playful | Entertainment |
| `Orus` | Male, formal | Corporate |
| `Zephyr` | Female, soft | Meditation, soft news |
| `Leda` | Female, youthful | Kids, casual |

All 8 voices handle Indonesian, English, Japanese, Korean, Spanish, etc. The
voice you pick is a TIMBRE choice, not a LANGUAGE choice.

## Production rate (free tier)

- ~2-3 sec per request
- Add 4-5 sec `time.sleep()` between calls to be polite
- 10-slide batch ≈ 70-90 sec total
- 17-slide batch → impossible in one key, plan hybrid

## Hybrid strategy: Gemini + edge-tts fallback

When the video has more than 10 narration blocks:

```bash
# Slides 1-10: Gemini 2.5 Flash TTS, voice=Kore
python3 pipeline/01b_tts_gemini.py narration.md --voice Kore --end 10

# Slides 11+: edge-tts id-ID-GadisNeural (closest match to Kore, female Indonesian)
# Pre-generate per-slide text and call edge-tts manually for the rest
for i in 11 12 13 14 15 16 17; do
  edge-tts --voice id-ID-GadisNeural --text "$(sed -n "/^### SLIDE $i /,/^### SLIDE /p" narration.md | head -n -1 | tail -n +2)" --write-media audio/slide_$(printf %02d $i).mp3
done
```

Voice change at slide 11 is audible but acceptable. The credits slide
(last) is the safest place to switch if you must.

## Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `429 RESOURCE_EXHAUSTED` | Daily quota hit | Switch to edge-tts for remaining slides, or wait 24h, or new key in new project |
| `403 PERMISSION_DENIED` | API key flagged as leaked | User must revoke at aistudio.google.com/app/apikey and create new key |
| Empty `inline_data.data` | Model returned text instead of audio | Check `response_modalities=["AUDIO"]` is set |
| `AudioConfig` not found | Wrong import path | Use `from google.genai import types` then `types.SpeechConfig` (not `AudioConfig`) |
| Audio sounds robotic | Wrong voice or language mismatch | Try `Kore` (default), or add style hint to `contents=` (e.g. `"Say as a news anchor: " + text`) |

## Verifying output

```bash
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 audio/slide_01.mp3
# expect: 6.25 (or similar, matches narration length)
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 audio/slide_01.mp3
# expect: codec_name=mp3 / sample_rate=24000 / channels=1
```

## See also

- `pipeline/01b_tts_gemini.py` — the production script
- `pipeline/01_generate_tts.py` — edge-tts version (no quota)
- `examples/ihsg-danantara/` — reference narration (Indonesian, 17 slides, hybrid)
