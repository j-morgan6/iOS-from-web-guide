#!/usr/bin/env bash
# Pre-archive validator. Exit 0 pass, exit 2 fail (failures on stderr so the
# model sees them when the archive hook blocks).
#
# Checks:
#   1. DEVELOPMENT_TEAM non-empty in project.yml
#   2. CURRENT_PROJECT_VERSION strictly greater than the last uploaded build,
#      read from .build-history — a JSON-lines file in the project root where
#      each upload appends a line like: {"version":"42","date":"2026-07-01"}
#      (maintained by your upload step; the check is skipped if absent)
#   3. No alpha channel on the primary app icon (requires sips; skipped
#      elsewhere). Dark/tinted variants are exempt — Apple expects
#      transparency there.
#   4. Privacy usage strings present for permission-gated imports
#   5. ITSAppUsesNonExemptEncryption declared
#
# Info.plist keys may live in a standalone plist anywhere in the tree or
# inline under info.properties in project.yml (XcodeGen) — both are searched.
#
# Escape hatch: IOS_FROM_WEB_SKIP_VALIDATOR=1 (document why in the commit).

set -u

if [ "${IOS_FROM_WEB_SKIP_VALIDATOR:-0}" = "1" ]; then
  echo "ios-from-web-guide: pre-archive validator skipped (IOS_FROM_WEB_SKIP_VALIDATOR=1)"
  exit 0
fi

FAILURES=()
add_fail() { FAILURES+=("$1"); }

# Locate the Info.plist (the canonical layout nests it under <AppName>/).
PLIST=$(find . \( -path '*/build/*' -o -path '*/DerivedData/*' -o -path '*/.git/*' -o -path '*/.build/*' \) -prune -o -name 'Info.plist' -print 2>/dev/null | head -1)

# True if a plist key is declared in the standalone plist OR project.yml.
has_plist_key() {
  { [ -n "$PLIST" ] && grep -q "$1" "$PLIST" 2>/dev/null; } || grep -q "$1" project.yml 2>/dev/null
}

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
  LAST=$(grep -oE '"version":[[:space:]]*"[0-9]+"' .build-history | grep -oE '[0-9]+' | sort -n | tail -1)
  if [ -n "$LAST" ] && [ -n "$CUR" ] && [ "$CUR" -le "$LAST" ]; then
    add_fail "CURRENT_PROJECT_VERSION ($CUR) must be strictly greater than last uploaded ($LAST)."
  fi
fi

# Check 3: App icon alpha (primary icon only — dark/tinted variants are
# expected to use transparency per Apple's HIG). Requires sips (macOS).
if command -v sips >/dev/null 2>&1; then
  while IFS= read -r icon; do
    case "$(basename "$icon")" in
      *dark*|*tinted*) continue ;;
    esac
    if sips -g hasAlpha "$icon" 2>/dev/null | grep -q "hasAlpha: yes"; then
      add_fail "App icon has alpha channel: $icon. Run: bash \${CLAUDE_PLUGIN_ROOT}/scripts/strip-alpha-from-icon.sh '$icon'"
    fi
  done < <(find . -path '*/AppIcon.appiconset/*.png' 2>/dev/null)
fi

# Check 4: Privacy strings for permission-gated imports.
# Entries are "regex|key" (single-quoted to preserve backslashes).
CHECKS=(
  'import[[:space:]]+PhotosUI|NSPhotoLibraryUsageDescription'
  'AVCaptureDevice|NSCameraUsageDescription'
  'import[[:space:]]+CoreLocation|NSLocationWhenInUseUsageDescription'
  'import[[:space:]]+AppTrackingTransparency|NSUserTrackingUsageDescription'
)
if [ -n "$PLIST" ] || [ -f project.yml ]; then
  for pair in "${CHECKS[@]}"; do
    IMPORT_RE="${pair%%|*}"
    KEY="${pair##*|}"
    if grep -rE "$IMPORT_RE" --include='*.swift' . >/dev/null 2>&1; then
      if ! has_plist_key "$KEY"; then
        add_fail "Missing $KEY (required because ${IMPORT_RE} matches in source). Declare it in Info.plist or project.yml info.properties."
      fi
    fi
  done

  # Check 5: ITSAppUsesNonExemptEncryption present
  if ! has_plist_key 'ITSAppUsesNonExemptEncryption'; then
    add_fail "Missing ITSAppUsesNonExemptEncryption. Add false to pre-answer export compliance."
  fi
fi

if [ ${#FAILURES[@]} -gt 0 ]; then
  {
    echo "🚫 Pre-archive validation FAILED:"
    for f in "${FAILURES[@]}"; do
      echo "   • $f"
    done
    echo
    echo "Escape hatch: IOS_FROM_WEB_SKIP_VALIDATOR=1 (document why in commit message)"
  } >&2
  exit 2
fi

echo "✅ Pre-archive validation passed"
exit 0
