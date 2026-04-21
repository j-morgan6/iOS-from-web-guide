# Changelog

## 1.0.1 — 2026-04-21

### Fixed

All 9 Write|Edit hooks were silent no-ops: they referenced `$CLAUDE_HOOK_FILE_PATH`, an env var Claude Code does not set. The hooks ran but saw empty input and exited 0. Hooks now parse tool input from stdin JSON via a new `scripts/hook-lint.sh` dispatcher, and check the pending `content` / `new_string` rather than a nonexistent file path.

The Bash hooks (force-push and simctl blocks) were also reworked to parse `tool_input.command` properly instead of grepping the raw JSON payload — previously they worked incidentally because the command text appeared in the JSON, but could false-positive on unrelated JSON keys.

## 1.0.0 — 2026-04-20

Initial release.

### Skills (12)

**Track A — iOS client + SwiftUI pitfalls (10):**
- `ios-project-structure` — opinionated folder layout, XcodeGen baseline.
- `ios-api-client-foundation` — `APIClient` with snake_case coding, auth injection.
- `ios-auth-keychain-storage` — tokens live in Keychain, never UserDefaults.
- `ios-feature-scaffold` — model → viewmodel → view → API method loop.
- `swiftui-observable-viewmodel-boilerplate` — `@Observable` only, no `@Published`.
- `swiftui-navigation-foundations` — `NavigationStack` + `NavigationLink(value:)` + `navigationDestination(for:)`.
- `swiftui-layout-pitfalls` — `containerRelativeFrame`, ScrollView clipping, safe-area handling.
- `swiftui-equatable-hashable-for-diffing` — let Swift synthesize; no custom id-only `==`.
- `swiftui-async-image-with-backend-paths` — always resolve relative paths via `.asBackendURL`.
- `swiftui-optimistic-ui-pattern` — optimistic mutation + rollback on error.

**Track B — App Store shipping (2):**
- `ios-info-plist-privacy-strings` — every permission has its usage description.
- `ios-app-icon-asset-prep` — RGB, no alpha, correct sizes.

### Hooks (13)

**SessionStart (1):**
- Project detection — caches `is_ios_project`, `deployment_target`, `uses_xcodegen`, `has_swiftui`, `bundle_id` in `.ios-from-web-guide-project.json` for other hooks to consult.

**PreToolUse — Bash (2):**
- Block dangerous Bash (force push to main/master → exit 2; `xcrun simctl erase all` → warn exit 1).
- Pre-archive validator — on any `xcodebuild ... archive`, delegates to `validate_pre_archive.sh` (build-number increment, alpha-free icon, privacy strings, release config).

**PreToolUse — Write|Edit (8):**
- Skill invocation reminder on `.swift`/`.plist`/`project.yml` (context-aware via project-cache).
- Block `UserDefaults` storage of tokens/passwords/secrets (exit 2).
- Block `.buttonStyle(.plain)` inside `NavigationLink` — use `.borderless` (exit 2).
- Warn on `URL(string:)` with relative path — use `.asBackendURL` (exit 1).
- Warn on `DispatchQueue.main.async` inside a `@MainActor` class/struct (exit 1).
- Warn on `@Published`/`@ObservedObject`/`@StateObject` in iOS 17+ projects — prefer `@Observable` (exit 1).
- Warn on `print()` outside test files — use `os.Logger` (exit 1).
- Warn on custom id-only `==` on a `Hashable` struct — breaks SwiftUI diffing (exit 1).

**PostToolUse — Write|Edit (1):**
- On writes into `/Views/`, suggest running the `swiftui-checklist` agent.

**SubagentStart (1):**
- Inject a condensed rules block (navigation, state, API/auth, shipping, layout) into every subagent.

### Agents (2)

- `swiftui-checklist` — reviews a Swift file for navigation, state, equality, and layout pitfalls.
- `ios-project-structure-review` — reviews overall project layout against the opinionated baseline.

### Templates (7)

`APIClient.swift`, `KeychainService.swift`, `String+BackendURL.swift`, `Configuration.swift`, `AppState.swift`, `project.yml.template`, `AppIcon-Contents.json.template`.

### Scripts (3)

- `detect_project.sh` — writes the session cache file.
- `strip-alpha-from-icon.sh` — removes alpha channel from a PNG (ImageMagick primary, `sips` fallback).
- `validate_pre_archive.sh` — 6-check pre-archive validator (build number, icon alpha, privacy strings, release config, development team, bundle id).

### Distribution

Distributed as a Claude Code plugin via the `ios-from-web-guide` marketplace. Install with `/plugin marketplace add j-morgan6/ios-from-web-guide` + `/plugin install ios-from-web-guide@ios-from-web-guide`. Skills, agents, and hooks activate automatically.
