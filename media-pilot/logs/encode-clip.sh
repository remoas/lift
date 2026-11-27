#!/usr/bin/env bash
# Usage: encode-clip.sh <id> <raw.mp4>
# Writes media-pilot/video/<id>.mp4 and posters/<id>-thumb.jpg + <id>-end.jpg
set -euo pipefail
ID="${1:?id}"
RAW="${2:?raw mp4}"
ROOT="/workspace/lift/media-pilot"
OUT="$ROOT/video/${ID}.mp4"
POST="$ROOT/posters"
TMP="/tmp/p2/encode-${ID}"
rm -rf "$TMP" && mkdir -p "$TMP" "$POST" "$ROOT/video"

encode() {
  local crf="$1"
  ffmpeg -y -hide_banner -loglevel error -i "$RAW" -t 8 -map 0:v:0 -an \
    -vf "fps=24,scale=1280:720:flags=lanczos,setsar=1,format=yuv420p" \
    -c:v libx264 -profile:v high -level:v 3.1 -preset slow -crf "$crf" \
    -movflags +faststart -r 24 -pix_fmt yuv420p \
    "$TMP/out.mp4"
  stat -c%s "$TMP/out.mp4"
}

bytes=$(encode 26)
echo "CRF 26 => $bytes bytes"
if [ "$bytes" -gt 600000 ]; then bytes=$(encode 28); echo "CRF 28 => $bytes bytes"; fi
if [ "$bytes" -gt 600000 ]; then bytes=$(encode 30); echo "CRF 30 => $bytes bytes"; fi
if [ "$bytes" -gt 600000 ]; then echo "ERROR still over 600000" >&2; exit 1; fi
cp -f "$TMP/out.mp4" "$OUT"

ffmpeg -y -hide_banner -loglevel error -ss 1 -i "$OUT" -frames:v 1 \
  -vf "scale=240:240:force_original_aspect_ratio=increase,crop=240:240,format=yuvj420p" \
  "$TMP/thumb.png"
ffmpeg -y -hide_banner -loglevel error -sseof -0.05 -i "$OUT" -frames:v 1 \
  -vf "scale=1200:676:force_original_aspect_ratio=increase,crop=1200:676,format=yuvj420p" \
  "$TMP/end.png"

python3 - "$TMP" "$POST" "$ID" << 'PY'
import sys
from pathlib import Path
from PIL import Image
tmp, post, eid = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
for src_name, dest_name in [("thumb.png", f"{eid}-thumb.jpg"), ("end.png", f"{eid}-end.jpg")]:
    im = Image.open(tmp / src_name).convert("RGB")
    dest = post / dest_name
    for q in (80, 70, 60, 50, 40, 35, 30):
        im.save(dest, "JPEG", quality=q, optimize=True, subsampling=2)
        sz = dest.stat().st_size
        print(f"{dest_name} q={q} {sz}")
        if sz <= 60000:
            break
    else:
        raise SystemExit(f"{dest_name} still over 60000")
PY

ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,codec_type,profile,level,width,height,r_frame_rate,nb_frames -of default "$OUT"
ls -la "$OUT" "$POST/${ID}-thumb.jpg" "$POST/${ID}-end.jpg"
