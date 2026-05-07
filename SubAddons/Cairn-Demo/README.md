# Cairn-Demo

Live, browseable showcase of every **non-GUI** Cairn library, plus a one-click smoke test that PASS/FAIL-asserts every public API. Companion to `Cairn-Gui-Demo-2.0`, which covers the GUI side.

```
/cdemo               toggle the demo window
/cdemo show          open it
/cdemo hide          close it
/cdemo smoke         open and run the smoke test
```

## What it covers

One tab per library. Each tab renders a working example on the left and the exact Lua snippet on the right.

- **Callback** — `Cairn-Callback-1.0`. Registry-style `:Subscribe / :Fire` with `OnUsed` / `OnUnused` hooks.
- **Events** — `Cairn-Events-1.0`. Game-event subscription with owner-keyed mass unsubscribe.
- **Log** — `Cairn-Log-1.0` + `Cairn-LogWindow-1.0`. Leveled per-source logger backed by a ring buffer.
- **DB** — `Cairn-DB-1.0`. SavedVariables wrapper with profile management.
- **Settings** — `Cairn-Settings-1.0` + `Cairn-SettingsPanel-1.0`. Schema bridged to Blizzard Settings + the standalone Cairn-Gui-1.0 panel.
- **Addon** — `Cairn-Addon-1.0`. ADDON_LOADED / PLAYER_LOGIN lifecycle helpers.
- **Slash** — `Cairn-Slash-1.0`. Slash command router with subcommands and auto-help.
- **EditMode** — `Cairn-EditMode-1.0`. Optional LibEditMode wrapper for movable frames.
- **Locale** — `Cairn-Locale-1.0`. Per-addon localization with active -> default -> key fallback.
- **Hooks** — `Cairn-Hooks-1.0`. Multi-callback hooksecurefunc dispatcher.
- **Sequencer** — `Cairn-Sequencer-1.0`. Composable step-runner.
- **Timer** — `Cairn-Timer-1.0`. Owner-grouped timers + named-timer debounce.
- **FSM** — `Cairn-FSM-1.0`. Flat finite state machine with async transitions.
- **Comm** — `Cairn-Comm-1.0`. Addon-to-addon CHAT_MSG_ADDON wrapper.
- **Smoke Test** — PASS/FAIL assertions across every lib's public API. Run from the tab or `/cdemo smoke`.

## Architecture

The demo window is built on `Cairn-Gui-2.0` widgets because they're a hard dependency of the parent addon -- it would be silly to write a custom window renderer when the GUI lib is already loaded. `Cairn-SettingsPanel-1.0` (which is built on `Cairn-Gui-1.0`) is demonstrated by spawning its own panel via `:OpenStandalone()`; the v1 panel renders independently of this window.

Each tab is a standalone file under `Tabs/`. To add a new tab, create a file there, call `Demo:RegisterTab(id, def)` at file-scope load, and add the file to `Cairn-Demo.toc`.

## Install (development)

Run `Sync-WoWAddons.ps1` from the repo root. The script transparently
treats `SubAddons/` as a pass-through container, so `Cairn-Demo` lands
in `Interface\AddOns\Cairn-Demo\` automatically. No manual junction or
copy needed.

This addon is **not** in Cairn's `.pkgmeta` or `release.ps1` (matching
the existing Cairn-Gui-Demo-2.0 decision). It's an internal-only
showcase, not a published addon.

## Position in the project

Companion to:
- **Cairn-Gui-Demo-2.0** (sibling SubAddon) — the GUI library showcase.
- **CairnTest** (top-level addon) — older, narrower smoke test (PLAYER_LOGIN only). Cairn-Demo's Smoke Test tab supersedes it.

## License

MIT. Cairn-Demo is documentation-as-code for the Cairn library and is not an end-user product.
