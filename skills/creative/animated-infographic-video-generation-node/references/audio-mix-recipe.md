# Audio mix recipe — pocket-director pipeline

Working ffmpeg recipes for the audio mix stage. All tested with the
IHSG/Danantara video (June 2026) — Indonesian girl TTS, lo-fi BGM
loop, 10-minute video.

## The recipe (single command)

```bash
# 1. Concat TTS MP3s (in order)
ffmpeg -y -f concat -safe 0 -i concat_list.txt -c copy _tts_concat.mp3

# 2. Loop BGM to match TTS duration
ffmpeg -y -stream_loop -1 -i bgm_clean.mp3 -t 605.5 -c copy _bgm_looped.mp3

# 3. Mix with sidechain compression (BGM ducks under voice)
ffmpeg -y \
  -i _tts_concat.mp3 -i _bgm_looped.mp3 \
  -filter_complex "
    [0:a]volume=1.0[v];
    [1:a]volume=0.25,sidechaincompress=threshold=0.05:ratio=8:attack=5:release=800[bg];
    [v][bg]amix=inputs=2:duration=first:dropout_transition=0[m]
  " \
  -map "[m]" -c:a libmp3lame -q:a 4 _mix1.mp3

# 4. Loudnorm to -14 LUFS (TikTok / YouTube safe)
ffmpeg -y -i _mix1.mp3 \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11" \
  -c:a libmp3lame -q:a 4 mixed.mp3
```

## Why these specific values

- **`sidechaincompress threshold=0.05 ratio=8`** — duck ratio of 8:1
  is enough that BGM becomes nearly inaudible when voice is active,
  but doesn't pump audibly between sentences.
- **`attack=5 release=800`** — fast attack (5ms) catches the start
  of each word; slow release (800ms) lets BGM fade back in
  naturally during pauses.
- **`volume=0.25`** — BGM sits at -12dB relative to voice. The
  sidechain then ducks another 8-15dB when voice is active.
- **`loudnorm=I=-14`** — TikTok's loudness target is -14 LUFS,
  YouTube's is around -14 as well. Using -1.5 true peak and 11 LRA
  keeps dynamics natural for documentary content.

## BGM cleaning (must do before mixing)

If you download a YouTube track, it has leading/trailing silence and
volume mismatches. Clean it once before looping:

```bash
# Strip silence at start/end and normalize volume
ffmpeg -y -i raw_bgm.mp3 \
  -af "silenceremove=stop_periods=-1:stop_duration=0.3,volume=0.6" \
  bgm_clean.mp3
```

The `silenceremove=stop_periods=-1:stop_duration=0.3` removes any
silence chunk longer than 300ms from anywhere in the track. The
loop transition is then seamless.

## BGM download with YouTube bot bypass

YouTube blocks datacenter IPs from `yt-dlp` directly. Use the
`bgutil-ytdlp-pot-provider` skill/pattern:

```bash
# 1. Start the POT provider server (Deno + tsc)
cd /root/bgutil-ytdlp-pot-provider
deno task build  # tsc compile
deno task server  # HTTP server on :4416

# 2. Install Python plugin
pip install bgutil-ytdlp-pot-provider

# 3. Download with bot bypass
yt-dlp -v -x --audio-format mp3 \
  -o "music/bgm.%(ext)s" \
  "https://youtu.be/PYne2exHHYU"
```

## AAC encoding for final mux (not for audio mix, but related)

When muxing the final MP4, use AAC for the audio track:
```bash
ffmpeg -i video.mp4 -i mixed.mp3 \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \
  final.mp4
```

If you get "Too many bits ... clamping to max" warnings, lower to
`-b:a 128k` (still fine for 24kHz mono TTS).

## Gotchas

- **`duration=first`** in amix means output length matches first
  input (TTS), not the longest. Use this to avoid runaway BGM
  after voice ends.
- **Sidechain needs the BGM first, voice second** in the filter
  graph (voice triggers the compression on BGM). If you swap
  them, the wrong thing ducks.
- **`dropout_transition=0`** prevents clicks at the end of voice
  when BGM has nothing to mix with.
- **24kHz TTS audio** (edge-tts default) is fine for AAC at 192k.
  Don't upsample to 48kHz — wastes bitrate on content that isn't
  there.
