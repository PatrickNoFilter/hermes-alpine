# Narration format — pocket-director pipeline

The pocket-director pipeline parses a single Markdown file into slides
+ TTS audio. This file documents the format with worked examples.

## File layout

```markdown
# Video title (H1)
## Optional subtitle (H2)

Watermark: ● PatrickNoFilter
BGM: https://youtu.be/PYne2exHHYU
Voice: id-ID-GadisNeural

---

### SLIDE 1 — Opening title
Body text becomes the TTS narration. Keep it to 2-3 sentences
for title slides, longer for content slides.

### SLIDE 2 — First content
The body becomes TTS. The slide builder will render it under
the title in a `.slide-body` div with `<strong>` emphasis
recognized.

### SLIDE 3 — Chart slide
You can mark values inline with `**` for emphasis. The slide
builder doesn't extract chart data from narration — pass chart
data via the manifest (see templates/narration-with-data.md).
```

## Slide section rules

- Heading: `### SLIDE N — TITLE` (em dash, en dash, or hyphen all work)
- Body: everything until the next `### SLIDE` heading or end of file
- N must be sequential 1, 2, 3, ... (out-of-order is allowed; sort by N)
- Empty body → slide has title only (use for title/closing slides)

## Voice selection

| Language | Female | Male |
|----------|--------|------|
| Indonesian | `id-ID-GadisNeural` | `id-ID-ArdiNeural` |
| English (US) | `en-US-AriaNeural` | `en-US-GuyNeural` |
| English (UK) | `en-GB-SoniaNeural` | `en-GB-RyanNeural` |
| Japanese | `ja-JP-NanamiNeural` | `ja-JP-KeitaNeural` |
| Mandarin | `zh-CN-XiaoxiaoNeural` | `zh-CN-YunxiNeural` |

List all voices: `edge-tts --list-voices | grep <lang-prefix>`

Rate: default `+0%`. `+5%` to `+10%` sounds slightly more energetic
without being rushed. `-5%` for more dramatic / somber.

## Duration targets

- Title slide: 8–15 sec (just the title read aloud)
- Data slide: 30–45 sec
- Chart slide: 25–40 sec
- Quote slide: 15–25 sec
- Timeline slide: 35–50 sec
- List slide: 30–60 sec (depends on item count)
- Closing slide: 10–20 sec

A 16-slide 10-minute documentary averages ~38 sec per slide.

## Emphasis and pacing

The TTS will read `**bold**` with natural emphasis. Use sparingly —
one or two bold phrases per slide is plenty. Avoid ALL CAPS (TTS
may not emphasize), avoid long parenthetical asides (TTS reads them
literally).

## Worked example: opening of IHSG/Danantara documentary

```markdown
# IHSG RUNTUH — DSI KONTROVERSI
## Ketika pasar jatuh, siapa yang menanggung?

Watermark: ● PatrickNoFilter
BGM: https://youtu.be/PYne2exHHYU
Voice: id-ID-GadisNeural

### SLIDE 1 — IHSG Runtuh, DSI Kontroversi
Indeks Harga Saham Gabungan jatuh tiga puluh delapan persen
dalam dua bulan. Triliunan rupiah lenyap. Dan di tengah
kepanikan, sebuah lembaga baru muncul — Danantara — dengan
mandat yang belum pernah ada sebelumnya.

### SLIDE 2 — The First Red Day
Senin, tiga belas Januari. Bursa Efek Indonesia buka dengan
gap turun. Hanya dalam jam pertama, indeks kehilangan dua
puluh tiga ribu poin. volume perdagangan pecah rekor —
ratusan juta lot berpindah tangan dalam satu sesi.
```

## Output structure

The pipeline writes:

```
build/<video-name>/
├── audio/
│   ├── slide_01.mp3          # TTS for slide 1
│   ├── slide_02.mp3
│   ├── ...
│   ├── manifest.json         # [{num, title, text, file, dur}, ...]
│   └── mixed.mp3             # voice + BGM final mix
├── slides/
│   └── slide_deck.html       # the HTML that gets recorded
├── recordings/
│   └── page@<uuid>.webm      # the Playwright output
└── output/
    ├── recording_h264.mp4    # Modal cloud encode result
    └── <video-name>_final.mp4
```
