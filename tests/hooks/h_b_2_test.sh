#!/usr/bin/env bash
# tests/hooks/h_b_2_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for entry in d['hooks'].get('PreToolUse', []):
    if entry.get('matcher') != 'Bash':
        continue
    for h in entry.get('hooks', []):
        desc = h.get('description', '').lower()
        if 'pre-archive' in desc or 'validate_pre_archive' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-B-2 command not found in hooks-settings.json"

# Build fake $HOME with mock validator that creates a marker file
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude/scripts/ios-from-web-guide"
MARKER="$FAKE_HOME/validator_was_called"
cat > "$FAKE_HOME/.claude/scripts/ios-from-web-guide/validate_pre_archive.sh" <<EOF
#!/usr/bin/env bash
touch "$MARKER"
exit 0
EOF
chmod +x "$FAKE_HOME/.claude/scripts/ios-from-web-guide/validate_pre_archive.sh"

run_hook() {
  local input="$1"
  printf '%s' "$input" | HOME="$FAKE_HOME" bash -c "$CMD"
  return $?
}

# Case: xcodebuild archive → validator invoked
rm -f "$MARKER"
run_hook '{"command":"xcodebuild -scheme MyApp archive"}' >/dev/null 2>&1
rc=$?
[ -f "$MARKER" ] || fail "validator should have been called for archive command"
[ $rc -eq 0 ] || fail "archive hook should exit 0 from mock validator (got $rc)"

# Case: non-archive command → validator not invoked
rm -f "$MARKER"
run_hook '{"command":"xcodebuild -scheme MyApp build"}' >/dev/null 2>&1
rc=$?
[ ! -f "$MARKER" ] || fail "validator should NOT have been called for non-archive command"
[ $rc -eq 0 ] || fail "non-archive command should exit 0 (got $rc)"

rm -rf "$FAKE_HOME"
echo "h_b_2_test.sh passed"
