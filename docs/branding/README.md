# HASS Voice icon

The launcher icon merges Home Assistant's blue house with a speech bubble and a
**BG** monogram for Bulgarian voice control.

| File | Purpose |
|---|---|
| `hass-voice-icon.svg` | 512 px rounded-square launcher plate and README preview |
| `hass-voice-round.svg` | Round launcher fallback (API < 26) |
| `hass-voice-background.svg` | Adaptive-icon background layer (full bleed) |
| `hass-voice-foreground.svg` | Adaptive-icon foreground layer (bubble + BG) |
| `hass-voice-monochrome.svg` | Themed-icon silhouette; the BG counters are punched out |
| `hass-voice-icon-512.png` | Preview used by the root README |

All SVGs are self-contained: the BG lettering is converted to outlines, so no
font is needed to render them. The adaptive foreground and monochrome layers use
a 0.84× scale so the bubble occupies roughly 73% of the 72 dp adaptive viewport;
the legacy and round bitmaps use 1.21× because the full bitmap is visible.

## Palette

- Home Assistant blue `#18BCF2` fading into the app's Bulgarian-teal accent
  `#0E8B78`
- Paper `#FFFFFF` → `#F0FBFF`
- Ink `#074C46`
- Shadow `#043C36` at 30%

The BG lettering is based on **Nunito Black** (SIL Open Font License 1.1),
converted to outlines with fontTools. The house is inspired by Home Assistant's
mark; this is an unofficial companion app, not an official Home Assistant asset.

## Regenerating the Android bitmaps

`rsvg-convert` (librsvg) is the only external tool needed:

```bash
./docs/branding/render-icons.sh
```

It writes the legacy, round, adaptive foreground/background and monochrome PNGs
to `android/app/src/main/res/mipmap-*`. The adaptive-icon XML manifests live in
`mipmap-anydpi-v26/` (background + foreground) and `mipmap-anydpi-v33/` (adds
the monochrome layer). Do not edit the generated PNGs by hand.
