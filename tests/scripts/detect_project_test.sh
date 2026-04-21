#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/detect_project.sh"
fail() { echo "FAIL: $1"; exit 1; }

# Case 1: xcodegen project
cd "$ROOT/tests/fixtures/detect_project/xcodegen"
rm -f .ios-from-web-guide-project.json
bash "$SCRIPT" >/dev/null 2>&1 || fail "script errored on xcodegen fixture"
[ -f .ios-from-web-guide-project.json ] || fail "cache file not created"
grep -q '"is_ios_project": *true' .ios-from-web-guide-project.json || fail "expected is_ios_project=true"
grep -q '"uses_xcodegen": *true' .ios-from-web-guide-project.json || fail "expected uses_xcodegen=true"
grep -q '"has_swiftui": *true' .ios-from-web-guide-project.json || fail "expected has_swiftui=true"
grep -q '"deployment_target": *"17.0"' .ios-from-web-guide-project.json || fail "expected deployment_target=17.0"
grep -q '"bundle_id": *"com.example.myapp"' .ios-from-web-guide-project.json || fail "expected bundle_id=com.example.myapp"
rm -f .ios-from-web-guide-project.json

# Case 2: xcodeproj only
cd "$ROOT/tests/fixtures/detect_project/xcodeproj_only"
rm -f .ios-from-web-guide-project.json
bash "$SCRIPT" >/dev/null 2>&1
grep -q '"is_ios_project": *true' .ios-from-web-guide-project.json || fail "expected is_ios_project=true for xcodeproj"
grep -q '"uses_xcodegen": *false' .ios-from-web-guide-project.json || fail "expected uses_xcodegen=false"
rm -f .ios-from-web-guide-project.json

# Case 3: Package.swift only (library, not an iOS app target)
cd "$ROOT/tests/fixtures/detect_project/package_swift"
rm -f .ios-from-web-guide-project.json
bash "$SCRIPT" >/dev/null 2>&1
grep -q '"has_swift_package": *true' .ios-from-web-guide-project.json || fail "expected has_swift_package=true"
rm -f .ios-from-web-guide-project.json

# Case 4: not iOS
cd "$ROOT/tests/fixtures/detect_project/not_ios"
rm -f .ios-from-web-guide-project.json
bash "$SCRIPT" >/dev/null 2>&1
grep -q '"is_ios_project": *false' .ios-from-web-guide-project.json || fail "expected is_ios_project=false for non-ios"
rm -f .ios-from-web-guide-project.json

echo "detect_project_test.sh passed"
