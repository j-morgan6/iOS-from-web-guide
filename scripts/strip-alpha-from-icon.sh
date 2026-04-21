#!/usr/bin/env bash
# Strip alpha channel from a PNG. In-place.
# Primary path: ImageMagick `magick` (lossless flatten onto solid background).
# Fallback: sips JPEG round-trip (lossy but reliable; warns the user).
# Usage: strip-alpha-from-icon.sh <path-to.png>
# Env: ICON_BG (hex, default FFFFFF) — background color the icon is flattened onto.
set -u
INPUT="${1:-}"
BG="${ICON_BG:-FFFFFF}"
if [ -z "$INPUT" ]; then
  echo "Usage: $0 <path-to-png>" >&2
  exit 2
fi
if [ ! -f "$INPUT" ]; then
  echo "File not found: $INPUT" >&2
  exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.png"

# Primary: ImageMagick (produces a clean, lossless RGB PNG)
if command -v magick >/dev/null 2>&1; then
  magick "$INPUT" -background "#$BG" -alpha remove -alpha off "$OUT" >/dev/null 2>&1
elif command -v convert >/dev/null 2>&1; then
  convert "$INPUT" -background "#$BG" -alpha remove -alpha off "$OUT" >/dev/null 2>&1
else
  # Fallback: sips JPEG round-trip. Lossy but produces hasAlpha: no reliably.
  if ! command -v sips >/dev/null 2>&1; then
    echo "Neither ImageMagick nor sips found. Install ImageMagick: brew install imagemagick" >&2
    exit 2
  fi
  echo "⚠️  ImageMagick not found; falling back to lossy sips round-trip. Install ImageMagick for lossless: brew install imagemagick" >&2
  sips -s format jpeg "$INPUT" --out "$TMP/mid.jpg" >/dev/null 2>&1 || { echo "sips jpeg conversion failed" >&2; exit 2; }
  sips -s format png "$TMP/mid.jpg" --out "$OUT" >/dev/null 2>&1 || { echo "sips png conversion failed" >&2; exit 2; }
fi

[ -s "$OUT" ] || { echo "Alpha stripping produced no output" >&2; exit 2; }

# Verify: the resulting file has no alpha
if command -v sips >/dev/null 2>&1; then
  sips -g hasAlpha "$OUT" 2>/dev/null | grep -q "hasAlpha: no" || { echo "Alpha strip did not succeed (file still has alpha)" >&2; exit 2; }
fi

cp "$OUT" "$INPUT"
echo "Alpha stripped from: $INPUT"
