#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Flags
NON_INTERACTIVE=false
for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=true ;;
  esac
done

echo -e "${GREEN}Installing ios-from-web-guide${NC}"
echo "============================="
echo ""

# Check for Claude Code CLI (warn but don't hard-error)
if ! command -v claude >/dev/null 2>&1; then
  echo -e "${YELLOW}Warning: claude CLI not found on PATH.${NC}"
  echo "  ios-from-web-guide is designed for Claude Code. Continuing anyway."
  echo "  Install Claude Code: https://claude.ai/download"
  echo ""
fi

# Resolve ~/.claude (respect overridden HOME for tests)
CLAUDE_DIR="$HOME/.claude"
if [ ! -d "$CLAUDE_DIR" ]; then
  echo -e "${YELLOW}Creating $CLAUDE_DIR...${NC}"
  mkdir -p "$CLAUDE_DIR"
fi

# Detect run context: local clone vs curl | bash
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
TEMP_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/skills" ] && [ -d "$SCRIPT_DIR/agents" ]; then
  SOURCE_DIR="$SCRIPT_DIR"
  echo -e "${GREEN}Installing from local repository: $SOURCE_DIR${NC}"
else
  echo -e "${GREEN}Downloading from GitHub...${NC}"
  if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}Error: git not found and running from curl.${NC}"
    echo "Please install git or clone the repository manually."
    exit 1
  fi
  TEMP_DIR=$(mktemp -d)
  git clone --depth 1 https://github.com/j-morgan6/ios-from-web-guide "$TEMP_DIR" >/dev/null 2>&1
  SOURCE_DIR="$TEMP_DIR"
fi

# Sanity
if [ ! -f "$SOURCE_DIR/hooks-settings.json" ]; then
  echo -e "${RED}Error: hooks-settings.json not found in $SOURCE_DIR${NC}"
  exit 1
fi

# ---- Skills ----
echo -e "${YELLOW}Installing skills...${NC}"
mkdir -p "$CLAUDE_DIR/skills"
SKILL_COUNT=0
for skill_dir in "$SOURCE_DIR/skills"/*; do
  if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    cp "$skill_dir/SKILL.md" "$CLAUDE_DIR/skills/$skill_name/SKILL.md"
    SKILL_COUNT=$((SKILL_COUNT + 1))
  fi
done
echo -e "${GREEN}  Installed $SKILL_COUNT skills${NC}"

# ---- Agents ----
echo -e "${YELLOW}Installing agents...${NC}"
mkdir -p "$CLAUDE_DIR/agents"
AGENT_COUNT=0
for agent_file in "$SOURCE_DIR/agents"/*.md; do
  if [ -f "$agent_file" ]; then
    cp "$agent_file" "$CLAUDE_DIR/agents/$(basename "$agent_file")"
    AGENT_COUNT=$((AGENT_COUNT + 1))
  fi
done
echo -e "${GREEN}  Installed $AGENT_COUNT agents${NC}"

# ---- Scripts ----
echo -e "${YELLOW}Installing scripts...${NC}"
SCRIPTS_TARGET="$CLAUDE_DIR/scripts/ios-from-web-guide"
mkdir -p "$SCRIPTS_TARGET"
SCRIPT_COUNT=0
for s in "$SOURCE_DIR/scripts"/*.sh; do
  if [ -f "$s" ]; then
    cp "$s" "$SCRIPTS_TARGET/$(basename "$s")"
    chmod +x "$SCRIPTS_TARGET/$(basename "$s")"
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
  fi
done
echo -e "${GREEN}  Installed $SCRIPT_COUNT scripts${NC}"

# ---- Templates ----
echo -e "${YELLOW}Installing templates...${NC}"
TEMPLATES_TARGET="$CLAUDE_DIR/ios-from-web-guide/templates"
mkdir -p "$TEMPLATES_TARGET"
TEMPLATE_COUNT=0
for t in "$SOURCE_DIR/templates"/*; do
  if [ -f "$t" ]; then
    cp "$t" "$TEMPLATES_TARGET/$(basename "$t")"
    TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
  fi
done
echo -e "${GREEN}  Installed $TEMPLATE_COUNT templates${NC}"

# ---- Hooks: merge into settings.json ----
echo -e "${YELLOW}Merging hooks into settings.json...${NC}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi
cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"

if command -v jq >/dev/null 2>&1; then
  # Deep-merge using jq's `*` operator. Hooks arrays from the plugin REPLACE the
  # existing arrays at the same matcher keys (simpler and deterministic; reinstalls
  # stay idempotent).
  jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$SOURCE_DIR/hooks-settings.json" > "$SETTINGS_FILE.tmp"
  mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  echo -e "${GREEN}  Merged hooks with jq${NC}"
else
  # Fallback: Python (ships with macOS). Same deep-merge semantics.
  PY=python3
  command -v "$PY" >/dev/null 2>&1 || PY=python
  if ! command -v "$PY" >/dev/null 2>&1; then
    echo -e "${RED}Error: neither jq nor python available for settings merge.${NC}"
    exit 1
  fi
  "$PY" - "$SETTINGS_FILE" "$SOURCE_DIR/hooks-settings.json" <<'PYEOF'
import json, sys
a_path, b_path = sys.argv[1], sys.argv[2]
with open(a_path) as f: a = json.load(f)
with open(b_path) as f: b = json.load(f)
def merge(x, y):
    if isinstance(x, dict) and isinstance(y, dict):
        out = dict(x)
        for k, v in y.items():
            out[k] = merge(x[k], v) if k in x else v
        return out
    # for non-dicts (incl. lists), right-hand value wins
    return y
merged = merge(a, b)
with open(a_path, 'w') as f: json.dump(merged, f, indent=2)
PYEOF
  echo -e "${GREEN}  Merged hooks with python fallback${NC}"
fi

# ---- Cleanup temp clone ----
if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
  rm -rf "$TEMP_DIR"
fi

# ---- Summary ----
echo ""
echo -e "${GREEN}Installation complete.${NC}"
echo ""
echo "  Skills:    $SKILL_COUNT  in  $CLAUDE_DIR/skills/"
echo "  Agents:    $AGENT_COUNT  in  $CLAUDE_DIR/agents/"
echo "  Scripts:   $SCRIPT_COUNT  in  $SCRIPTS_TARGET/"
echo "  Templates: $TEMPLATE_COUNT  in  $TEMPLATES_TARGET/"
echo "  Hooks:     merged into $SETTINGS_FILE"
echo "  Backup:    $SETTINGS_FILE.backup"
echo ""
echo "The CLAUDE.md.template lives in the repo — copy it manually to any iOS"
echo "project where you want the plugin's rules surfaced to Claude:"
echo "  cp <repo>/CLAUDE.md.template /path/to/ios-project/CLAUDE.md"
echo ""
if [ "$NON_INTERACTIVE" = "false" ]; then
  echo -e "${YELLOW}Restart Claude Code to load the new configuration.${NC}"
fi
