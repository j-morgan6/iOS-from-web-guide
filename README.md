# ios-from-web-guide

Enforce iOS/SwiftUI best practices when adding a native iOS client to an existing web app.

**12 skills · 13 hooks · 2 agents · 7 templates · 3 scripts**

A Claude Code plugin. Targets SwiftUI, iOS 17+, XcodeGen, and the App Store release pipeline. Pairs enforced skills with `PreToolUse`/`PostToolUse`/`SessionStart`/`SubagentStart` hooks and opinionated templates so common mistakes are caught before they ship.

## What it solves

Five concrete scars from shipping a real iOS client on top of a web backend:

1. **NavigationLink tap absorption.** `.buttonStyle(.plain)` inside a `NavigationLink` silently eats the tap. Hook H-W-3 blocks this; skill `swiftui-navigation-foundations` teaches it.
2. **Hashable diffing broken by custom `==`.** A custom id-only `==` on a model struct makes SwiftUI think nothing changed. Hook H-W-8 warns; skill `swiftui-equatable-hashable-for-diffing` explains.
3. **VStack + ScrollView clipping.** Intrinsic sizing on a ScrollView child collapses width. Skill `swiftui-layout-pitfalls` covers `containerRelativeFrame` and sibling issues.
4. **`URL(string:)` with a relative path returns nil.** Hook H-W-4 warns; skill `swiftui-async-image-with-backend-paths` + template `String+BackendURL.swift` give the fix.
5. **Alpha in the app icon rejects at App Store upload.** `validate_pre_archive.sh` catches it before Archive; `strip-alpha-from-icon.sh` fixes it.

Plus a handful of "one-hour-to-recover" pitfalls: UserDefaults-for-tokens (blocked), `@Published` when iOS 17 wants `@Observable`, `DispatchQueue.main.async` inside `@MainActor`, `print()` shipping to production, missing privacy strings, non-incrementing build number.

## Quick start

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/j-morgan6/ios-from-web-guide/main/install.sh | bash
```

Restart Claude Code. Verify:

```bash
ls ~/.claude/skills | grep ios-
```

Drop `CLAUDE.md.template` into your iOS project root (it tells Claude which skills to invoke when):

```bash
cp <repo>/CLAUDE.md.template ./CLAUDE.md
```

## Documentation

- **[INSTALL-HOOKS.md](INSTALL-HOOKS.md)** — install, uninstall, per-hook summary, escape hatch, Xcode build-phase snippet, troubleshooting.
- **[CHANGELOG.md](CHANGELOG.md)** — release history.
- **[CLAUDE.md.template](CLAUDE.md.template)** — drop-in project file that tells Claude which skills to invoke on which files.

## Related plugin

`elixir-phoenix-guide` — the sibling plugin for Elixir/Phoenix backends. Same structural pattern (skills + hooks + agents + install.sh), different domain. You can run both installed simultaneously; they don't share skill namespaces or hook matchers.

## Philosophy

- **Every skill traces to a specific pitfall from a real shipped project.** No speculative skills.
- **Block only what costs 30+ minutes to recover from.** Everything else warns or teaches.
- **Negative examples are as valuable as positive ones.** Every skill states what NOT to do and why.
- **Templates are the source of truth for code.** Skills reference templates; no drifting copies.
- **Opinionated and honest.** One stack (SwiftUI + iOS 17+ + XcodeGen). No cross-platform framework support.

## License

MIT. See [LICENSE](LICENSE).
