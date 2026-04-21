#!/usr/bin/env bash
# tests/hooks/h_ss_1_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

# Simulate install target
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude/scripts/ios-from-web-guide"
cp "$ROOT/scripts/detect_project.sh" "$FAKE_HOME/.claude/scripts/ios-from-web-guide/"

# Extract the SessionStart command from hooks-settings.json
CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
entries = d['hooks'].get('SessionStart', [])
if not entries:
    sys.exit(1)
print(entries[0]['hooks'][0]['command'])
PY
)
[ -n "$CMD" ] || fail "H-SS-1 command not found"

# Run the command in a test project dir
WORK=$(mktemp -d)
cd "$WORK"
touch project.yml
echo "import SwiftUI" > App.swift
HOME="$FAKE_HOME" bash -c "$CMD" >/dev/null 2>&1 || fail "command failed"
[ -f .ios-from-web-guide-project.json ] || fail "detection file not created"

cd - >/dev/null
rm -rf "$WORK" "$FAKE_HOME"
echo "h_ss_1_test.sh passed"
