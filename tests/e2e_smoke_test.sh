#!/usr/bin/env bash
# End-to-end smoke test.
# 1. Installs into a mock HOME via install.sh --non-interactive.
# 2. Verifies the installed layout (skills, agents, scripts, templates, hooks).
# 3. Creates a mock iOS project and runs the installed detect_project.sh.
# 4. Verifies the project-detection cache file.
# 5. Extracts H-W-2's command from the installed settings.json and runs it
#    against a fixture containing a UserDefaults-token smell; asserts exit 2.
# 6. Happy path: runs all PreToolUse Write|Edit hook commands against a
#    clean .swift file; asserts exit 0 or 1 (warnings acceptable, no blocks).
# 7. Cleans up.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "  ok: $1"; }

[ -f "$INSTALL" ] || fail "install.sh missing"

MOCK_HOME=$(mktemp -d)
PROJECT_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_HOME" "$PROJECT_DIR"' EXIT

echo "=== Phase 1: install into mock HOME ==="
HOME="$MOCK_HOME" bash "$INSTALL" --non-interactive >"$MOCK_HOME/install.log" 2>&1 \
  || { cat "$MOCK_HOME/install.log"; fail "installer exited non-zero"; }
pass "installer completed"

echo "=== Phase 2: verify installed layout ==="
SKILL_COUNT=$(find "$MOCK_HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$SKILL_COUNT" = "12" ] || fail "expected 12 skills, got $SKILL_COUNT"
pass "12 skills installed"

AGENT_COUNT=$(find "$MOCK_HOME/.claude/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
[ "$AGENT_COUNT" = "2" ] || fail "expected 2 agents, got $AGENT_COUNT"
pass "2 agents installed"

SCRIPT_DIR="$MOCK_HOME/.claude/scripts/ios-from-web-guide"
SCRIPT_COUNT=$(find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')
[ "$SCRIPT_COUNT" = "3" ] || fail "expected 3 scripts, got $SCRIPT_COUNT"
pass "3 scripts installed"

SETTINGS="$MOCK_HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || fail "settings.json missing"

# Count total hooks
TOTAL_HOOKS=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
t = 0
for ev, groups in s.get('hooks', {}).items():
    for g in groups:
        t += len(g.get('hooks', []))
print(t)
")
[ "$TOTAL_HOOKS" = "13" ] || fail "expected 13 hooks, got $TOTAL_HOOKS"
pass "13 hooks in settings.json"

echo "=== Phase 3: mock iOS project + run detect_project.sh ==="
# Minimal xcodegen project.yml so detect_project.sh flags it as an iOS project
cat > "$PROJECT_DIR/project.yml" <<'YAML'
name: SmokeApp
options:
  deploymentTarget:
    iOS: "17.0"
targets:
  SmokeApp:
    type: application
    platform: iOS
    sources: [SmokeApp]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.smokeapp
YAML

mkdir -p "$PROJECT_DIR/SmokeApp"
cat > "$PROJECT_DIR/SmokeApp/App.swift" <<'SWIFT'
import SwiftUI

@main
struct SmokeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View { Text("Hello") }
}
SWIFT

cd "$PROJECT_DIR"
bash "$SCRIPT_DIR/detect_project.sh" >/dev/null 2>&1 || fail "detect_project.sh errored"
[ -f "$PROJECT_DIR/.ios-from-web-guide-project.json" ] || fail "detect cache not written"
grep -q '"is_ios_project": *true' "$PROJECT_DIR/.ios-from-web-guide-project.json" \
  || fail "expected is_ios_project=true"
grep -q '"uses_xcodegen": *true' "$PROJECT_DIR/.ios-from-web-guide-project.json" \
  || fail "expected uses_xcodegen=true"
grep -q '"has_swiftui": *true' "$PROJECT_DIR/.ios-from-web-guide-project.json" \
  || fail "expected has_swiftui=true"
grep -q '"deployment_target": *"17.0"' "$PROJECT_DIR/.ios-from-web-guide-project.json" \
  || fail "expected deployment_target=17.0"
pass "detect_project.sh wrote correct cache"

echo "=== Phase 4: H-W-2 blocks UserDefaults secrets (exit 2) ==="
# Fixture: a Swift file with the smell
BAD="$PROJECT_DIR/SmokeApp/Auth.swift"
cat > "$BAD" <<'SWIFT'
import Foundation
func storeToken(_ token: String) {
    UserDefaults.standard.set(token, forKey: "auth_token")
}
SWIFT

# Extract H-W-2's command from installed settings.json. H-W-2 is the
# UserDefaults-secrets hook — find it by description substring.
HW2_CMD=$(python3 -c "
import json
s = json.load(open('$SETTINGS'))
for g in s['hooks']['PreToolUse']:
    if g.get('matcher') != 'Write|Edit': continue
    for h in g['hooks']:
        if 'UserDefaults' in h.get('description',''):
            print(h['command']); break
")
[ -n "$HW2_CMD" ] || fail "could not locate H-W-2 command in settings.json"

set +e
CLAUDE_HOOK_FILE_PATH="$BAD" bash -c "$HW2_CMD" >"$PROJECT_DIR/hw2.out" 2>&1
RC=$?
set -e
[ "$RC" = "2" ] || { cat "$PROJECT_DIR/hw2.out"; fail "H-W-2 expected exit 2, got $RC"; }
grep -q "UserDefaults" "$PROJECT_DIR/hw2.out" || fail "H-W-2 did not print the expected message"
pass "H-W-2 blocks UserDefaults secret storage (exit 2)"

echo "=== Phase 5: happy path — clean .swift file through all Write|Edit hooks ==="
CLEAN="$PROJECT_DIR/SmokeApp/Clean.swift"
cat > "$CLEAN" <<'SWIFT'
import SwiftUI

struct CleanView: View {
    var body: some View { Text("clean") }
}
SWIFT

# Run every PreToolUse Write|Edit hook against CLEAN; each must exit 0 or 1
# (0 = silent pass, 1 = non-blocking warning). Exit 2 means the hook blocked,
# which would be a false-positive regression.
python3 -c "
import json
s = json.load(open('$SETTINGS'))
i = 0
for g in s['hooks']['PreToolUse']:
    if g.get('matcher') != 'Write|Edit': continue
    for h in g['hooks']:
        with open('$PROJECT_DIR/hook_%02d.cmd' % i, 'w') as f:
            f.write(h['command'])
        i += 1
print(i)
" >"$PROJECT_DIR/.hook_count"
HOOK_COUNT=$(cat "$PROJECT_DIR/.hook_count")
[ "$HOOK_COUNT" -ge 1 ] || fail "no Write|Edit hooks found"

set +e
for i in $(seq -w 00 $((HOOK_COUNT - 1))); do
  CMD_FILE="$PROJECT_DIR/hook_$i.cmd"
  [ -f "$CMD_FILE" ] || continue
  CLAUDE_HOOK_FILE_PATH="$CLEAN" bash -c "$(cat "$CMD_FILE")" >"$PROJECT_DIR/hook_$i.out" 2>&1
  HRC=$?
  if [ "$HRC" = "2" ]; then
    cat "$PROJECT_DIR/hook_$i.out"
    set -e
    fail "clean file blocked by Write|Edit hook #$i (exit 2)"
  fi
done
set -e
pass "clean .swift passed all Write|Edit hooks (no exit 2)"

echo ""
echo "e2e_smoke_test.sh passed"
