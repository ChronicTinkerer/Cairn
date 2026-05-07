# Changelog

All notable changes to **Cairn-Demo** are documented here.
The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are sequential build numbers (per the Cairn version convention).

## [Unreleased]

## [1] - 2026-05-07

### Added

- New SubAddon `Cairn-Demo` under `Cairn/SubAddons/Cairn-Demo/`.
- 16 tabs: Welcome + 14 library tabs + Smoke Test.
- Smoke Test runs PASS/FAIL assertions against every public API in
  `Cairn-Callback`, `Cairn-Events`, `Cairn-Log`, `Cairn-LogWindow`,
  `Cairn-DB`, `Cairn-Settings`, `Cairn-SettingsPanel`, `Cairn-Addon`,
  `Cairn-Slash`, `Cairn-EditMode`, `Cairn-Locale`, `Cairn-Hooks`,
  `Cairn-Sequencer`, `Cairn-Timer`, `Cairn-FSM`, `Cairn-Comm`, plus the
  `Cairn` umbrella facade.
- Slash command `/cdemo` (alias `/cairn-demo`) routed via `Cairn.Slash`.
  Subcommands: `show`, `hide`, `smoke`.
- Headless test mirror at `Forge/.dev/tests/cairn_demo_smoke.lua` for
  Forge_Console.
