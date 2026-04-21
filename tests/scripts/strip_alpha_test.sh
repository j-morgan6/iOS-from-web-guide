#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/strip-alpha-from-icon.sh"
FIX="$ROOT/tests/fixtures/icons"
fail() { echo "FAIL: $1"; exit 1; }

# Prepare a mutable copy of the alpha-bearing PNG
WORK=$(mktemp -d)
cp "$FIX/with_alpha.png" "$WORK/icon.png"

# Verify fixture really has alpha
sips -g hasAlpha "$WORK/icon.png" | grep -q "hasAlpha: yes" || fail "fixture with_alpha.png doesn't have alpha"

# Run script
bash "$SCRIPT" "$WORK/icon.png" || fail "script exited non-zero"

# After run, no alpha
sips -g hasAlpha "$WORK/icon.png" | grep -q "hasAlpha: no" || fail "alpha not stripped"

# Idempotent: running again should succeed without error
bash "$SCRIPT" "$WORK/icon.png" || fail "second run failed"

# Clean up
rm -rf "$WORK"
echo "strip_alpha_test.sh passed"
