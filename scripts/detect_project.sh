#!/usr/bin/env bash
# Writes .ios-from-web-guide-project.json with detection flags.
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

# Use nullglob so an unmatched glob produces no iteration rather than a literal "*.xcodeproj" string
shopt -s nullglob 2>/dev/null || true
for f in *.xcodeproj; do [ -d "$f" ] && has_xcodeproj=true; done
[ -f project.yml ] && has_xcodegen=true
[ -f Package.swift ] && has_swift_package=true

# Any .swift file containing `import SwiftUI`
if find . -maxdepth 3 -name "*.swift" -print0 2>/dev/null | xargs -0 grep -lE '^[[:space:]]*import[[:space:]]+SwiftUI' 2>/dev/null | grep -q .; then
  has_swiftui=true
fi

# Extract deployment target and bundle id from project.yml if present
if [ -f project.yml ]; then
  deployment_target=$(grep -E '^\s*iOS:' project.yml | head -1 | sed -E 's/.*"([0-9.]+)".*/\1/')
  bundle_id=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER' project.yml | head -1 | sed -E 's/.*:[[:space:]]*([A-Za-z0-9.-]+).*/\1/')
fi

is_ios=false
if [ "$has_xcodeproj" = "true" ] || [ "$has_xcodegen" = "true" ] || [ "$has_swiftui" = "true" ]; then
  is_ios=true
fi

cat > "$OUT" <<EOF
{
  "is_ios_project": $is_ios,
  "has_swiftui": $has_swiftui,
  "deployment_target": "$deployment_target",
  "uses_xcodegen": $has_xcodegen,
  "has_swift_package": $has_swift_package,
  "bundle_id": "$bundle_id"
}
EOF
