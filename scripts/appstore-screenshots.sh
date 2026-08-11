#!/bin/bash
# Turns raw macOS screen captures into Mac App Store screenshots.
#
# Apple wants 16:10 at 1280x800, 1440x900, 2560x1600, or 2880x1800, PNG or JPEG,
# and no alpha channel. A full-screen grab on this Mac is 2560x1664, so trimming
# 64 rows lands on 2560x1600 at 1:1 — no upscaling, no softness.
#
#   ./scripts/appstore-screenshots.sh raw/ out/          # keep the top (menu bar)
#   ./scripts/appstore-screenshots.sh raw/ out/ center   # centre-weighted crop
#
# Anchor matters: "top" keeps the menu bar, which is the subject of most Punctual
# shots. Use "center" for the full-screen alert, where the content is centred.

set -euo pipefail

SRC="${1:?usage: $0 <input-dir> <output-dir> [top|center|bottom]}"
DST="${2:?usage: $0 <input-dir> <output-dir> [top|center|bottom]}"
ANCHOR="${3:-top}"

TARGET_W=2560
TARGET_H=1600

command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)"; exit 1; }
mkdir -p "$DST"

shopt -s nullglob
files=("$SRC"/*.png "$SRC"/*.PNG "$SRC"/*.jpg "$SRC"/*.jpeg)
[ ${#files[@]} -gt 0 ] || { echo "no images found in $SRC"; exit 1; }

for f in "${files[@]}"; do
    name=$(basename "${f%.*}")
    IFS=, read -r w h < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0 "$f")

    # Largest 16:10 rectangle that fits inside the source.
    if [ "$((w * 10))" -gt "$((h * 16))" ]; then
        cw=$(( h * 16 / 10 )); ch=$h
    else
        cw=$w; ch=$(( w * 10 / 16 ))
    fi
    cw=$(( cw - cw % 2 )); ch=$(( ch - ch % 2 ))

    x=$(( (w - cw) / 2 ))
    case "$ANCHOR" in
        top)    y=0 ;;
        bottom) y=$(( h - ch )) ;;
        *)      y=$(( (h - ch) / 2 )) ;;
    esac

    out="$DST/$name.png"
    # rgb24 drops any alpha channel, which the App Store rejects.
    ffmpeg -v error -i "$f" \
        -vf "crop=${cw}:${ch}:${x}:${y},scale=${TARGET_W}:${TARGET_H}:flags=lanczos" \
        -pix_fmt rgb24 "$out" -y

    note=""
    [ "$cw" -lt "$TARGET_W" ] && note="  (upscaled from ${cw}x${ch} - will look soft)"
    echo "${name}: ${w}x${h} -> crop ${cw}x${ch}+${x}+${y} -> ${TARGET_W}x${TARGET_H}${note}"
done

echo
echo "Wrote $(ls -1 "$DST" | wc -l | tr -d ' ') screenshot(s) to $DST"
echo "Verify none say 'upscaled' above; Apple accepts them but they look soft."
