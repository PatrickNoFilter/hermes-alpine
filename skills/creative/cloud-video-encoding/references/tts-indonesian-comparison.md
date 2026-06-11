# TTS Options for Indonesian Narration (Video Production)

Research from IHSG Danantara project (June 2026).

## Comparison

| Provider | Quality | Cost | Daily Limit | Indonesian Voices | Setup |
|----------|---------|------|-------------|-------------------|-------|
| **OpenAI TTS HD** | ⭐ Best | ~$0.10/10 min ($15/1M chars) | None | 6 voices (nova/shimmer best) | `pip install openai` + API key |
| **Edge-TTS** | Good | Free | None | 2: GadisNeural (F), ArdiNeural (M) | `pip install edge-tts` (already in venv) |
| **Gemini 2.5 Flash TTS** | Good | Free tier | **10/day** | Kore voice | google-genai SDK |
| **Gemini 2.5 Pro TTS** | Good | Separate quota | Likely 10/day | Kore voice | google-genai SDK |
| **Kokoro TTS** | Very good | Free (local) | None | Unclear ARM64 support | Open source, may be slow on phone |

## Recommendation

- **Default: Edge-TTS** — free, unlimited, decent quality, already installed. Use `id-ID-GadisNeural` for female narration.
- **Upgrade: OpenAI TTS HD** — best quality, ~$0.10 for full narration. Needs valid API key.
- **Avoid: Gemini TTS** — 10/day free limit makes it impractical for 16+ slide narrations.

## Edge-TTS usage

```bash
edge-tts --voice id-ID-GadisNeural --text "..." --write-media output.mp3
# or from Python:
subprocess.run(["edge-tts", "--voice", "id-ID-GadisNeural", "--text", text, "--write-media", out])
```

## OpenAI TTS HD usage

```python
from openai import OpenAI
c = OpenAI()  # uses OPENAI_API_KEY env var
resp = c.audio.speech.create(model="tts-1-hd", voice="nova", input=text, response_format="mp3")
resp.stream_to_file("output.mp3")
```

## Batch generation pattern

For multi-slide narrations, iterate over a manifest JSON with slide texts:
- Rate limit: Edge-TTS has none (0.5s sleep is sufficient). Gemini needs 4.5s between requests.
- Use `ffprobe` to measure actual duration of each generated MP3 for the render manifest.
- Concat all MP3s with `ffmpeg -f concat -safe 0 -i list.txt -c:a libmp3lame -q:a 2 full.mp3`.
