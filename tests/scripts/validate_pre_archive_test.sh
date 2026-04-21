#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate_pre_archive.sh"
fail() { echo "FAIL: $1"; exit 1; }

make_fixture_common() {
  local dir="$1"
  mkdir -p "$dir/Sources" "$dir/AppIcon.appiconset"
  cat > "$dir/project.yml" <<EOF
name: MyApp
settings:
  PRODUCT_BUNDLE_IDENTIFIER: com.example.myapp
  DEVELOPMENT_TEAM: ABC123DEF4
  CURRENT_PROJECT_VERSION: 2
EOF
  cat > "$dir/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
</dict>
</plist>
EOF
  echo '{"version":"1","status":"uploaded"}' > "$dir/.build-history"
  echo "import Foundation" > "$dir/Sources/App.swift"
  # Minimal 1024 RGB icon (generate with Pillow)
  python3 -c "from PIL import Image; Image.new('RGB',(1024,1024),(255,0,0)).save('$dir/AppIcon.appiconset/icon.png')"
}

# GOOD fixture
GOOD=$(mktemp -d)
make_fixture_common "$GOOD"
cd "$GOOD"
bash "$SCRIPT" || fail "good fixture should pass"
cd - >/dev/null

# BAD TEAM
BT=$(mktemp -d); make_fixture_common "$BT"
sed -i.bak 's/DEVELOPMENT_TEAM: ABC123DEF4/DEVELOPMENT_TEAM: ""/' "$BT/project.yml"
cd "$BT"
bash "$SCRIPT" && fail "bad_team should fail"
cd - >/dev/null

# BAD BUILD NUMBER (equal to last uploaded)
BB=$(mktemp -d); make_fixture_common "$BB"
sed -i.bak 's/CURRENT_PROJECT_VERSION: 2/CURRENT_PROJECT_VERSION: 1/' "$BB/project.yml"
cd "$BB"
bash "$SCRIPT" && fail "bad_build_number should fail"
cd - >/dev/null

# BAD ALPHA
BA=$(mktemp -d); make_fixture_common "$BA"
python3 -c "from PIL import Image; Image.new('RGBA',(1024,1024),(255,0,0,128)).save('$BA/AppIcon.appiconset/icon.png')"
cd "$BA"
bash "$SCRIPT" && fail "bad_alpha should fail"
cd - >/dev/null

# MISSING PRIVACY (import PhotosUI but no NSPhotoLibraryUsageDescription)
MP=$(mktemp -d); make_fixture_common "$MP"
echo "import PhotosUI" > "$MP/Sources/Picker.swift"
cd "$MP"
bash "$SCRIPT" && fail "missing_privacy should fail"
cd - >/dev/null

# ESCAPE HATCH
cd "$BT"
IOS_FROM_WEB_SKIP_VALIDATOR=1 bash "$SCRIPT" || fail "escape hatch should let bad_team pass"
cd - >/dev/null

rm -rf "$GOOD" "$BT" "$BB" "$BA" "$MP"
echo "validate_pre_archive_test.sh passed"
