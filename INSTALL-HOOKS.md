# Installing hooks

This doc will cover installing the plugin's hooks into a target project, including:

- How the installer wires `hooks-settings.json` into `.claude/settings.json`.
- The per-hook validators and what they check.
- The `IOS_FROM_WEB_SKIP_VALIDATOR=1` escape hatch for temporarily bypassing validators when you need to (emergencies, experimentation, CI edge cases).

Full details land with the 1.0.0 release.
