# YouTube unlisted upload + yt-dlp roundtrip (free, slow fallback)

When Modal is unavailable, YouTube will re-encode any uploaded video to its standard H.264/AAC ladder for free, and `yt-dlp` can pull the result back. The catch: **YT's processing queue adds 5–30 min of latency** depending on file size and current load.

This document assumes the `bgutil-ytdlp-pot-provider` HTTP server is already running on `localhost:4416` (per `playwright-termux-arm64` skill memory).

## Upload via OAuth2 + bgutil POT provider

```python
import os, json, time
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# OAuth2 client installed locally; token cached at ~/.youtube-upload-token.json
creds = Credentials.from_authorized_user_file(os.path.expanduser("~/.youtube-upload-token.json"))
yt = build("youtube", "v3", credentials=creds)

body = {
    "snippet": {
        "title": "transcode-tmp",
        "description": "intermediate file, will be removed after download",
        "categoryId": "22",   # People & Blogs (least moderation scrutiny)
    },
    "status": {
        "privacyStatus": "unlisted",
        "selfDeclaredMadeForKids": False,
    },
}
media = MediaFileUpload("/root/ihsg-youtube/recordings/recording.webm",
                        mimetype="video/webm", resumable=True)
upload = yt.videos().insert(part="snippet,status", body=body, media_body=media)
response = None
while response is None:
    _, response = upload.next_chunk()
print("Uploaded:", response["id"])
VIDEO_ID = response["id"]
```

## Wait for processing, then download with yt-dlp

YT's processing pipeline is asynchronous. Poll every 30 s until the file has a `stream` H.264 format:

```bash
URL="https://www.youtube.com/watch?v=$VIDEO_ID"
until yt-dlp --list-subs "$URL" 2>&1 | grep -q "18\|22\|137\|136"; do
  echo "still processing..."
  sleep 30
done
yt-dlp -f "bv*[ext=mp4][vcodec^=avc]+ba[ext=m4a]/bv*[ext=mp4]+ba/b[ext=mp4]" \
       -o "/root/ihsg-youtube/output/recording_h264.mp4" "$URL"
```

**Cookie / POT caveat:** if YT redirects to a "Sign in to confirm you're not a bot" interstitial, the bgutil POT provider must be running and configured in the yt-dlp config (`~/.config/yt-dlp/config`):

```
--extractor-args youtubepot-bgutilhttp:base_url=http://127.0.0.1:4416
```

## Cleanup (don't leave the file public)

```python
yt.videos().delete(id=VIDEO_ID).execute()
```

## When this is actually the right choice

- Modal cold start fails / quota exhausted
- The file is sensitive and you don't want it on a third-party CDN **for long** (the upload is auto-deleted, but there's a 5–60 min window where it exists)
- You need a **redundant** transcode to verify your own (e.g. a sanity check on a critical render)

## When this is the wrong choice

- Privacy-sensitive content (the file is briefly public-by-link on YT's CDN)
- Tight turnaround (need a 1-hour deliverable)
- File size > YT's free 256 GB cap (this is huge; only matters for 4K raw)
