#!/usr/bin/env bash
# Runs install.sh against a mock HOME and asserts the installed layout.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT/install.sh"

fail() { echo "FAIL: $1"; exit 1; }

[ -f "$INSTALL" ] || fail "install.sh not found at $INSTALL"

MOCK_HOME=$(mktemp -d)
trap 'rm -rf "$MOCK_HOME"' EXIT

# Run installer against the mock HOME. Must not touch the real ~/.claude.
HOME="$MOCK_HOME" bash "$INSTALL" --non-interactive >"$MOCK_HOME/install.log" 2>&1 \
  || { cat "$MOCK_HOME/install.log"; fail "installer exited non-zero"; }

# --- Skills: 12 ---
SKILL_COUNT=$(find "$MOCK_HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$SKILL_COUNT" = "12" ] || fail "expected 12 skills, got $SKILL_COUNT"
[ -f "$MOCK_HOME/.claude/skills/ios-project-structure/SKILL.md" ] \
  || fail "sample skill SKILL.md missing"

# --- Agents: 2 ---
AGENT_COUNT=$(find "$MOCK_HOME/.claude/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
[ "$AGENT_COUNT" = "2" ] || fail "expected 2 agents, got $AGENT_COUNT"
[ -f "$MOCK_HOME/.claude/agents/swiftui-checklist.md" ] \
  || fail "swiftui-checklist.md missing"
[ -f "$MOCK_HOME/.claude/agents/ios-project-structure-review.md" ] \
  || fail "ios-project-structure-review.md missing"

# --- Scripts: 3, executable ---
SCRIPTS_DIR="$MOCK_HOME/.claude/scripts/ios-from-web-guide"
SCRIPT_COUNT=$(find "$SCRIPTS_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')
[ "$SCRIPT_COUNT" = "3" ] || fail "expected 3 scripts, got $SCRIPT_COUNT"
for s in detect_project.sh strip-alpha-from-icon.sh validate_pre_archive.sh; do
  [ -f "$SCRIPTS_DIR/$s" ] || fail "$s missing"
  [ -x "$SCRIPTS_DIR/$s" ] || fail "$s not executable"
done

# --- Templates: 7 ---
TEMPLATES_DIR="$MOCK_HOME/.claude/ios-from-web-guide/templates"
TEMPLATE_COUNT=$(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
[ "$TEMPLATE_COUNT" = "7" ] || fail "expected 7 templates, got $TEMPLATE_COUNT"
[ -f "$TEMPLATES_DIR/APIClient.swift" ] || fail "APIClient.swift template missing"

# --- settings.json: contains the hooks tree ---
SETTINGS="$MOCK_HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || fail "settings.json not created"
[ -f "$SETTINGS.backup" ] || fail "settings.json.backup not created"

# Check the major keys landed; use python for robust JSON parsing
python3 - "$SETTINGS" <<'PYEOF' || fail "settings.json does not contain expected hooks structure"
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
h = s.get("hooks", {})
assert "SessionStart" in h, "missing SessionStart"
assert "PreToolUse" in h, "missing PreToolUse"
assert "PostToolUse" in h, "missing PostToolUse"
assert "SubagentStart" in h, "missing SubagentStart"

# Flatten total hook count across all matcher groups
total = 0
for event, groups in h.items():
    for g in groups:
        total += len(g.get("hooks", []))
assert total == 13, f"expected 13 hooks total, got {total}"
PYEOF

echo "install_test.sh passed"
