#!/usr/bin/env bash
# SessionStart hook: detect an iOS project and cache metadata for the other
# hooks. Writes .ios-from-web-guide-project.json (add it to your .gitignore)
# ONLY when the directory looks like an iOS project — non-iOS repos are left
# untouched. Prints a one-line summary to stdout, which SessionStart adds to
# the model's context.
#
# Fields: is_ios_project, has_swiftui, deployment_target, uses_xcodegen,
#         has_swift_package, bundle_id.
set -u
OUT=".ios-from-web-guide-project.json"

has_xcodeproj=false
has_xcodegen=false
has_swift_package=false
has_swiftui=false
deployment_target=""
bundle_id=""

# nullglob so an unmatched glob produces no iteration
shopt -s nullglob 2>/dev/null || true
for f in *.xcodeproj; do [ -d "$f" ] && has_xcodeproj=true; done
[ -f project.yml ] && has_xcodegen=true
[ -f Package.swift ] && has_swift_package=true

# Any .swift file containing `import SwiftUI`
if find . -maxdepth 3 -name "*.swift" -print0 2>/dev/null | xargs -0 grep -lE '^[[:space:]]*import[[:space:]]+SwiftUI' 2>/dev/null | grep -q .; then
  has_swiftui=true
fi

# Deployment target and bundle id from project.yml (quoted or unquoted values)
if [ -f project.yml ]; then
  deployment_target=$(grep -E '^[[:space:]]*iOS:' project.yml | head -1 | sed -nE 's/^[[:space:]]*iOS:[[:space:]]*"?([0-9]+(\.[0-9]+)?)"?.*$/\1/p')
  bundle_id=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER' project.yml | head -1 | sed -nE 's/.*:[[:space:]]*"?([A-Za-z0-9.-]+)"?.*$/\1/p')
fi

if [ "$has_xcodeproj" != "true" ] && [ "$has_xcodegen" != "true" ] && [ "$has_swiftui" != "true" ]; then
  # Not an iOS project — write nothing, say nothing.
  exit 0
fi

cat > "$OUT" <<EOF
{
  "is_ios_project": true,
  "has_swiftui": $has_swiftui,
  "deployment_target": "$deployment_target",
  "uses_xcodegen": $has_xcodegen,
  "has_swift_package": $has_swift_package,
  "bundle_id": "$bundle_id"
}
EOF

SUMMARY="ios-from-web-guide: iOS project detected"
[ -n "$deployment_target" ] && SUMMARY="$SUMMARY (deployment target $deployment_target)"
[ "$has_xcodegen" = "true" ] && SUMMARY="$SUMMARY, XcodeGen"
[ "$has_swiftui" = "true" ] && SUMMARY="$SUMMARY, SwiftUI"
echo "$SUMMARY. Plugin hooks are active; consult the ios-from-web-guide skills before writing Swift/plist/project.yml files."
exit 0
