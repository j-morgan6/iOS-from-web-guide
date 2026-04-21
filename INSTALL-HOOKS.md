# Installing hooks

This doc walks you through installing `ios-from-web-guide` into a working Claude Code setup, what each hook does, how to bypass a hook when you need to, and how to uninstall.

## Prerequisites

- **macOS.** The plugin targets the Apple-only iOS/SwiftUI/Xcode toolchain.
- **Claude Code CLI.** See https://claude.ai/download. The installer warns but does not hard-error if `claude` is not on `PATH`, so you can install manually.
- **Optional — `jq`.** Used by the installer to merge `hooks-settings.json` into `~/.claude/settings.json`. If absent, the installer falls back to a Python deep-merge (Python ships with macOS).
- **Optional — ImageMagick (`magick` or `convert`).** Used by `strip-alpha-from-icon.sh` when available; it falls back to macOS `sips` otherwise.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/j-morgan6/ios-from-web-guide/main/install.sh | bash
```

Or from a local clone:

```bash
git clone https://github.com/j-morgan6/ios-from-web-guide
cd ios-from-web-guide
bash install.sh
```

Restart Claude Code after install.

## What gets installed

| Location | Contents |
|---|---|
| `~/.claude/skills/<name>/SKILL.md` | 12 skills |
| `~/.claude/agents/<name>.md` | 2 agents |
| `~/.claude/scripts/ios-from-web-guide/*.sh` | 3 scripts (executable) |
| `~/.claude/ios-from-web-guide/templates/*` | 7 Swift / config templates |
| `~/.claude/settings.json` | 13 hooks merged into existing settings |
| `~/.claude/settings.json.backup` | Pre-merge backup (overwritten on every install) |

The `CLAUDE.md.template` in the repo is intentionally NOT auto-installed — it is a reference file. Copy it into any iOS project root where you want the plugin's rules surfaced directly to Claude:

```bash
cp <repo>/CLAUDE.md.template /path/to/ios-project/CLAUDE.md
```

## Hook summary

**SessionStart (1):**
- **Project detection** — writes `.ios-from-web-guide-project.json` in the project root with detection flags (`is_ios_project`, `uses_xcodegen`, `has_swiftui`, `deployment_target`, `bundle_id`). Consulted by the context-aware Write|Edit hooks.

**PreToolUse — Bash (2):**
- **H-B-1 — dangerous-Bash blocker.** `git push --force main/master` → exit 2 (blocked). `xcrun simctl erase all` → exit 1 (warning).
- **H-B-2 — pre-archive validator.** Matches `xcodebuild ... archive` and delegates to `validate_pre_archive.sh`.

**PreToolUse — Write|Edit (8):**
- **H-W-1 — skill reminder.** On any `.swift`, `.plist`, or `project.yml` write in a detected iOS project, remind the model to invoke the matching skill.
- **H-W-2 — UserDefaults secrets (blocker).** Detects `UserDefaults.*\b(token|password|secret|api_key|bearer)\b` → exit 2. Recommends `KeychainService`.
- **H-W-3 — `.plain` in NavigationLink (blocker).** Button inside a NavigationLink with `.buttonStyle(.plain)` → exit 2. Use `.borderless`.
- **H-W-4 — relative `URL(string:)` (warning).** `URL(string: "/path")` returns nil. Use `.asBackendURL`.
- **H-W-5 — `DispatchQueue.main.async` inside `@MainActor` (warning).** Redundant; remove.
- **H-W-6 — `@Published`/`@ObservedObject`/`@StateObject` on iOS 17+ (warning).** Prefer `@Observable`.
- **H-W-7 — `print()` outside tests (warning).** Use `os.Logger`.
- **H-W-8 — custom id-only `==` on Hashable struct (warning).** Let Swift synthesize structural equality.

**PostToolUse — Write|Edit (1):**
- **H-P-1 — Views/ checklist suggestion.** On writes matching `/Views/`, suggests dispatching the `swiftui-checklist` agent.

**SubagentStart (1):**
- **H-SA-1 — rules injection.** Injects a condensed rules block (navigation, state, API/auth, shipping, layout) into every subagent prompt so sub-tasks inherit the same constraints.

## Escape hatch: `IOS_FROM_WEB_SKIP_VALIDATOR=1`

The pre-archive validator (`validate_pre_archive.sh`) honours `IOS_FROM_WEB_SKIP_VALIDATOR=1`. Set it before running `xcodebuild archive` to bypass the 6-check gate when you need to (CI edge cases, debugging the validator itself, emergency hot-fix archives):

```bash
IOS_FROM_WEB_SKIP_VALIDATOR=1 xcodebuild -scheme MyApp archive
```

The Write|Edit hooks do not read this variable — they are cheap and narrowly targeted, and blocking hooks (H-W-2, H-W-3) are blocking for a reason. If you genuinely need to bypass one, commit the exact file with `git commit --no-verify` outside Claude Code, or temporarily disable the hook entry in `~/.claude/settings.json`.

## Xcode build-phase snippet (opt-in)

`xcodebuild archive` is caught by H-B-2 automatically. If you also archive from the Xcode GUI, paste this into a Run Script build phase on your app target so the same validation runs there:

```bash
VALIDATOR="$HOME/.claude/scripts/ios-from-web-guide/validate_pre_archive.sh"
if [ "$ACTION" = "install" ] && [ -x "$VALIDATOR" ]; then
  "$VALIDATOR" || exit $?
fi
```

`install` is the action Xcode runs during Archive. Put the script phase AFTER "Compile Sources" and BEFORE "Copy Bundle Resources" so failures abort early.

## Uninstall

```bash
# Restore pre-install settings.json
mv ~/.claude/settings.json.backup ~/.claude/settings.json

# Remove plugin assets
rm -rf ~/.claude/skills/ios-project-structure \
       ~/.claude/skills/ios-api-client-foundation \
       ~/.claude/skills/ios-auth-keychain-storage \
       ~/.claude/skills/ios-feature-scaffold \
       ~/.claude/skills/ios-app-icon-asset-prep \
       ~/.claude/skills/ios-info-plist-privacy-strings \
       ~/.claude/skills/swiftui-observable-viewmodel-boilerplate \
       ~/.claude/skills/swiftui-navigation-foundations \
       ~/.claude/skills/swiftui-layout-pitfalls \
       ~/.claude/skills/swiftui-equatable-hashable-for-diffing \
       ~/.claude/skills/swiftui-async-image-with-backend-paths \
       ~/.claude/skills/swiftui-optimistic-ui-pattern
rm -f  ~/.claude/agents/swiftui-checklist.md \
       ~/.claude/agents/ios-project-structure-review.md
rm -rf ~/.claude/scripts/ios-from-web-guide \
       ~/.claude/ios-from-web-guide
```

Restart Claude Code.

## Troubleshooting

**Hooks are not firing.** Restart Claude Code. `~/.claude/settings.json` is read once at startup.

**`settings.json` got clobbered.** Restore `~/.claude/settings.json.backup`. The installer writes one every run.

**A PreToolUse hook is blocking a legitimate write.** The blocking hooks (H-W-2, H-W-3) exist because the cost of the bug they catch is >30 minutes of recovery. If you're hitting a false positive, open an issue with the exact file snippet. Temporary workaround: delete the hook's entry from `~/.claude/settings.json` and restart.

**`detect_project.sh` flagged my project as non-iOS.** It looks for `*.xcodeproj`, `project.yml`, or `Package.swift` in CWD. Run Claude Code from the project root, not a subdirectory.

**ImageMagick missing.** `strip-alpha-from-icon.sh` falls back to macOS `sips`. Both produce alpha-free PNGs; ImageMagick is simply preferred when available.

**Python not found during install.** macOS ships with `python3`. If both `jq` and `python3` are missing, install one: `brew install jq` is the one-liner.
