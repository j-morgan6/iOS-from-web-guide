#!/usr/bin/env bash
# Pre-archive validator. Runs 6 checks. Exit 0 pass, 2 fail.
set -u

if [ "${IOS_FROM_WEB_SKIP_VALIDATOR:-0}" = "1" ]; then
  echo "ios-from-web-guide: pre-archive validator skipped (IOS_FROM_WEB_SKIP_VALIDATOR=1)"
  exit 0
fi

FAILURES=()
add_fail() { FAILURES+=("$1"); }

# Check 1: DEVELOPMENT_TEAM
if [ -f project.yml ]; then
  TEAM=$(grep -E 'DEVELOPMENT_TEAM:' project.yml | head -1 | sed -E 's/.*DEVELOPMENT_TEAM:[[:space:]]*"?([^"]*)"?/\1/' | tr -d ' ')
  if [ -z "$TEAM" ]; then
    add_fail "DEVELOPMENT_TEAM is empty in project.yml. Set it or XcodeGen will wipe Xcode's manual setting."
  fi
fi

# Check 2: CURRENT_PROJECT_VERSION strictly > last uploaded
if [ -f project.yml ] && [ -f .build-history ]; then
  CUR=$(grep -E 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
  LAST=$(grep -oE '"version":"[0-9]+"' .build-history | grep -oE '[0-9]+' | sort -n | tail -1)
  if [ -n "$LAST" ] && [ -n "$CUR" ] && [ "$CUR" -le "$LAST" ]; then
    add_fail "CURRENT_PROJECT_VERSION ($CUR) must be strictly greater than last uploaded ($LAST)."
  fi
fi

# Check 3: App icon alpha
for icon in $(find . -path '*/AppIcon.appiconset/*.png' 2>/dev/null); do
  if sips -g hasAlpha "$icon" 2>/dev/null | grep -q "hasAlpha: yes"; then
    add_fail "App icon has alpha channel: $icon. Run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/strip-alpha-from-icon.sh '$icon'"
  fi
  DIM=$(sips -g pixelWidth -g pixelHeight "$icon" 2>/dev/null | grep -E 'pixel(Width|Height)' | awk '{print $2}' | sort -u)
  # For v1 we only require the 1024 icon to exist; extensive size-matrix validation deferred
done

# Check 4: Privacy strings for imports
# Use single-quoted array entries to preserve backslashes through to grep -E.
# Each entry is "regex|key" using | as the separator (no backslash in key names).
CHECKS=(
  'import[[:space:]]+PhotosUI|NSPhotoLibraryUsageDescription'
  'AVCaptureDevice|NSCameraUsageDescription'
  'import[[:space:]]+CoreLocation|NSLocationWhenInUseUsageDescription'
  'import[[:space:]]+AppTrackingTransparency|NSUserTrackingUsageDescription'
)
for pair in "${CHECKS[@]}"; do
  IMPORT_RE="${pair%%|*}"
  KEY="${pair##*|}"
  if grep -rE "$IMPORT_RE" --include='*.swift' . >/dev/null 2>&1; then
    if ! grep -q "$KEY" Info.plist 2>/dev/null; then
      add_fail "Missing $KEY in Info.plist (required because ${IMPORT_RE} matches in source)."
    fi
  fi
done

# Check 5: ITSAppUsesNonExemptEncryption present
if [ -f Info.plist ] && ! grep -q 'ITSAppUsesNonExemptEncryption' Info.plist; then
  add_fail "Missing ITSAppUsesNonExemptEncryption in Info.plist. Add <false/> to pre-answer export compliance."
fi

# Check 6: Bundle ID matches (only if config exists — skipped on first run)
if [ -f .ios-from-web-config.json ]; then
  EXPECTED=$(grep -oE '"bundle_id":[[:space:]]*"[^"]*"' .ios-from-web-config.json | sed -E 's/.*"([^"]*)"/\1/')
  ACTUAL=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER' project.yml 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*([A-Za-z0-9.-]+).*/\1/')
  if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
    add_fail "Bundle ID mismatch: expected $EXPECTED, got $ACTUAL"
  fi
fi

if [ ${#FAILURES[@]} -gt 0 ]; then
  echo "🚫 Pre-archive validation FAILED:"
  for f in "${FAILURES[@]}"; do
    echo "   • $f"
  done
  echo
  echo "Escape hatch: IOS_FROM_WEB_SKIP_VALIDATOR=1 (document why in commit message)"
  exit 2
fi

echo "✅ Pre-archive validation passed"
exit 0
