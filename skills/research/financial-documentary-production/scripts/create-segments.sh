#!/usr/bin/env bash
# Template: Render FFmpeg video segments from slide images + TTS audio.
#
# Expects: slide01.png..slideNN.png  and  slide01.mp3..slideNN.mp3
# Output:  segment01.mp4..segmentNN.mp4
#
# Usage:
#   chmod +x create-segments.sh
#   ./create-segments.sh          # renders all 16 segments
#   ./create-segments.sh 12       # renders only segment 12
#   TOTAL=8 ./create-segments.sh  # render 8 slides (default: 16)

set -euo pipefail

TOTAL="${TOTAL:-16}"
START=1
END="$TOTAL"

# Allow single-slide render for debugging
if [ $# -ge 1 ]; then
    START="$1"
    END="$1"
fi

echo "Rendering segments $START-$END of $TOTAL..."

for i in $(seq -f "%02g" "$START" "$END"); do
    PNG="slide${i}.png"
    MP3="slide${i}.mp3"
    OUT="segment${i}.mp4"

    if [ ! -f "$PNG" ]; then
        echo "  ⚠ Skipping $i: $PNG not found"
        continue
    fi
    if [ ! -f "$MP3" ]; then
        echo "  ⚠ Skipping $i: $MP3 not found"
        continue
    fi

    echo "  Rendering $OUT..."
    ffmpeg -y -loop 1 -i "$PNG" -i "$MP3" \
        -c:v libx264 -tune stillimage \
        -c:a aac -b:a 128k \
        -pix_fmt yuv420p -shortest \
        -movflags +faststart \
        "$OUT" 2>/dev/null

    # Verify
    DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" 2>/dev/null)
    echo "    ✓ $OUT  (${DUR}s)"
done

echo ""
echo "Done! Concatenate with:"
echo "  (printf \"file 'segment%%s.mp4'\\\n\" \$(seq -w 1 $TOTAL)) > segments.txt"
echo "  ffmpeg -f concat -safe 0 -i segments.txt -c copy final-video.mp4"
