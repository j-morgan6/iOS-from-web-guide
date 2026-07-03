---
name: ios-app-icon-asset-prep
description: MANDATORY when adding or updating icons in AppIcon.appiconset/. Enforces 1024x1024 sizing and the per-variant alpha rules (primary opaque, dark transparent, tinted opaque grayscale).
---

# iOS App Icon Asset Prep

## RULES — Follow these with no exceptions

1. **The icon must be exactly 1024x1024 px.** Not 1023, not 1025, not 1024x1200 cropped. App Store Connect rejects uploads with dimensions off by a single pixel.
2. **No alpha channel on the primary (light) icon.** RGB only — it doubles as the App Store marketing icon, and an alpha channel (even fully opaque) triggers ITMS-90717 "Invalid App Store Icon" on upload. This rule applies ONLY to the primary icon: the dark variant is *supposed* to have a transparent background, and the tinted variant should be opaque grayscale.
3. **Flatten the primary icon onto a solid background before saving.** A transparent-looking-opaque PNG still carries an alpha channel. Use `scripts/strip-alpha-from-icon.sh` — it flattens via ImageMagick (lossless) with an sips JPEG round-trip fallback. Do NOT flatten the dark variant.
4. **Provide both light and dark variants** in `Contents.json` using `appearances: [{ appearance: luminosity, value: dark }]`. Dark mode is required for a polished iOS 17+ app. Per Apple's docs, give the dark icon a **transparent background** so the system-provided dark background shows through.
5. **No text, no tagline, no version number.** Apple's icon guidelines reject icons with more than a logomark. Save the text for the Marketing Screenshot.
6. **The pre-archive validator blocks archive if an alpha channel is detected** on primary icons under `AppIcon.appiconset/` (files named `*dark*` / `*tinted*` are exempt).

---

## When to invoke

- Dropping a new icon PNG into `Assets.xcassets/AppIcon.appiconset/`.
- Replacing the existing icon.
- Adding a dark-mode or tinted variant.
- Debugging "Invalid Icon" uploads to App Store Connect.

## The 1024×1024 / RGB / no-alpha rule

A classic App Store rejection looks like:

```
ERROR ITMS-90717: "Invalid App Store Icon. The App Store Icon in the asset catalog
in 'YourApp.app' can't be transparent or contain an alpha channel."
```

This happens because iOS asset catalogs were designed for UI images (which often *want* alpha), but the App Store binary-checker singles out the 1024×1024 marketing icon — i.e. the primary/light variant — and demands opaque RGB.

**Detect:**

```bash
sips -g hasAlpha icon-1024.png
#   pixelHeight: 1024
#   pixelWidth: 1024
#   hasAlpha: yes     ← will be rejected
```

**Auto-fix:** invoke `scripts/strip-alpha-from-icon.sh <path>`:

```bash
# Uses ImageMagick when available, else sips JPEG round-trip
bash "${CLAUDE_PLUGIN_ROOT}/scripts/strip-alpha-from-icon.sh" \
  YourApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png

# Background color override (default: FFFFFF)
ICON_BG=000000 bash "${CLAUDE_PLUGIN_ROOT}/scripts/strip-alpha-from-icon.sh" \
  path/to/icon.png
```

The script reads the PNG, flattens it onto a solid-color background, and writes it back in place. Ask the user which background color matches the icon's intended surround (typically the edge color of the icon or pure white/black).

## Light + dark variants via `Contents.json`

iOS 17+ supports a dark-mode icon variant that kicks in when the user has Dark Mode enabled and the icon is rendered over dark wallpaper in the lock-screen / widget contexts. The asset catalog declares it:

```json
{
  "images": [
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "filename": "icon-1024.png"
    },
    {
      "appearances": [
        { "appearance": "luminosity", "value": "dark" }
      ],
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "filename": "icon-1024-dark.png"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

See `<plugin-root>/templates/AppIcon-Contents.json.template` — drop into `Assets.xcassets/AppIcon.appiconset/Contents.json` verbatim and supply the two PNGs (`icon-1024.png` for light, `icon-1024-dark.png` for dark).

Both variants must be 1024×1024 sRGB PNGs. The no-alpha rule applies **only to the light icon** — the dark variant keeps its transparent background (Apple: "Provide your dark app icon with a transparent background so the system-provided background can show through").

## Tinted variant (iOS 18+, optional)

iOS 18 added a *tinted* appearance — the system recolors the icon to match the user's Home Screen tint. If you want to support it:

```json
{
  "appearances": [
    { "appearance": "luminosity", "value": "tinted" }
  ],
  "idiom": "universal",
  "platform": "ios",
  "size": "1024x1024",
  "filename": "icon-1024-tinted.png"
}
```

**Tinted icon rules:**
- Grayscale only; the system supplies the background and applies the tint.
- Fully opaque, and **encoded as RGB with grayscale values** — a Gray Gamma colorspace PNG triggers an App Store Connect icon-display bug. Keep all variants the same format (PNG).
- High-contrast — thin line work gets lost.

This variant is optional. If omitted, iOS auto-generates a tinted version from the light variant, which usually looks worse than a hand-crafted one.

## Pre-archive validator enforcement

`scripts/validate_pre_archive.sh` Check 3 walks the PNGs under `AppIcon.appiconset/` — skipping `*dark*` / `*tinted*` filenames, which are allowed (dark) or not required (tinted) to carry alpha — and runs:

```bash
sips -g hasAlpha "$icon" | grep -q "hasAlpha: yes"
```

If alpha is detected, the validator fails with exit code 2 and prints the remediation command:

```
🚫 Pre-archive validation FAILED:
   • App icon has alpha channel: ./YourApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
     Run: bash ${CLAUDE_PLUGIN_ROOT}/scripts/strip-alpha-from-icon.sh '<path>'
```

The validator runs before `xcodebuild archive`, catching the issue ~90 seconds before the archive step would have discovered it.

**Escape hatch (rare):** `IOS_FROM_WEB_SKIP_VALIDATOR=1` — document why in the commit message.

## Common pitfalls

### "I exported from Figma as PNG — why is there alpha?"

Figma / Sketch / Photoshop default to RGBA. Even a fully opaque canvas carries an alpha channel.

**Fix:** run `strip-alpha-from-icon.sh` after export, or configure Figma to "Export as JPEG then convert to PNG" (avoids alpha entirely).

### "My icon looks fine in Xcode but the upload fails"

Xcode's asset catalog viewer silently ignores alpha. App Store Connect doesn't.

**Fix:** always check `sips -g hasAlpha <path>` before uploading, or let the pre-archive validator do it.

### "1024x1024 but App Store still rejects"

Cause: color profile is CMYK (common from Illustrator exports). App Store requires sRGB.

**Fix:** `sips -s format png -s formatOptions normal --setProperty colorProfile "sRGB IEC61966-2.1" in.png --out out.png`.

### "Dark variant doesn't activate"

Cause: `Contents.json` has the wrong appearance key, or the PNG was swapped but the filename in `Contents.json` doesn't match.

**Fix:** filenames must match `Contents.json` exactly. Use the template from `<plugin-root>/templates/AppIcon-Contents.json.template`.

### "Tinted variant looks muddy"

Cause: exported from color art and the contrast collapses under tint.

**Fix:** re-export as high-contrast, fully opaque grayscale (encoded as RGB). The system supplies the background and does the tinting at runtime.

## Template reference

- `<plugin-root>/templates/AppIcon-Contents.json.template` — drop-in `Contents.json` with light + dark variants.
- `<plugin-root>/scripts/strip-alpha-from-icon.sh` — one-shot alpha stripper.

## Related skills

- `ios-project-structure` — where `Assets.xcassets` lives and how the target references it.
- `ios-info-plist-privacy-strings` — the other common pre-archive blocker.
