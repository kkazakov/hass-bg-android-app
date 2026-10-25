#!/usr/bin/env bash
# Regenerate the launcher bitmaps from the SVG sources in this directory.
# Requires rsvg-convert (librsvg). The SVGs are self-contained: the BG glyphs
# are outlines, so no font is needed at render time.
set -euo pipefail

cd "$(dirname "$0")/../.."

BRAND=docs/branding
RES=android/app/src/main/res
LEGACY_SIZES=(48 72 96 144 192)
DENSITIES=(mdpi hdpi xhdpi xxhdpi xxxhdpi)
ADAPTIVE_SIZES=(108 162 216 324 432)

for i in "${!DENSITIES[@]}"; do
  d="${DENSITIES[$i]}"
  mkdir -p "$RES/mipmap-$d"

  # Classic launcher icon and round variant (API < 26 fallbacks).
  rsvg-convert -w "${LEGACY_SIZES[$i]}" -h "${LEGACY_SIZES[$i]}" \
    "$BRAND/hass-voice-icon.svg" -o "$RES/mipmap-$d/ic_launcher.png"
  rsvg-convert -w "${LEGACY_SIZES[$i]}" -h "${LEGACY_SIZES[$i]}" \
    "$BRAND/hass-voice-round.svg" -o "$RES/mipmap-$d/ic_launcher_round.png"

  # Adaptive icon layers (108dp canvas).
  rsvg-convert -w "${ADAPTIVE_SIZES[$i]}" -h "${ADAPTIVE_SIZES[$i]}" \
    "$BRAND/hass-voice-background.svg" -o "$RES/mipmap-$d/ic_launcher_background.png"
  rsvg-convert -w "${ADAPTIVE_SIZES[$i]}" -h "${ADAPTIVE_SIZES[$i]}" \
    "$BRAND/hass-voice-foreground.svg" -o "$RES/mipmap-$d/ic_launcher_foreground.png"
  rsvg-convert -w "${ADAPTIVE_SIZES[$i]}" -h "${ADAPTIVE_SIZES[$i]}" \
    "$BRAND/hass-voice-monochrome.svg" -o "$RES/mipmap-$d/ic_launcher_monochrome.png"
done

# Preview used by README.md.
rsvg-convert -w 512 -h 512 "$BRAND/hass-voice-icon.svg" -o "$BRAND/hass-voice-icon-512.png"

echo "Rendered launcher icons."
