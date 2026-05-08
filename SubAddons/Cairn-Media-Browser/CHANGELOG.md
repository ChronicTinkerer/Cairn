# Changelog

All notable changes to Cairn-Media-Browser are recorded here.

## [Unreleased]

### Added

- **Material Symbols full icon set + search.** Icons tab now lists all ~4244 Material Symbols glyphs (previously curated 53). Built lazily in 10-row batches via `C_Timer.After` so the UI stays responsive (~1.4s smooth populate). Search box filters icons by substring match (case-insensitive); row compaction (`SetLayoutManual` on hidden rows) packs visible content to the top with no gaps.
- **LSM aggregation in row tabs.** Fonts / Statusbars / Borders / Backgrounds / Sounds tabs now show every reachable media item — Cairn-private + Cairn-public + third-party LSM (anything any other addon registered with `LibSharedMedia-3.0`). Each row carries a source badge: `[CAIRN PRIVATE]`, `[CAIRN PUBLIC]`, or `[LSM]`. Filter semantics: All = everything; Public = LSM-registered (Cairn-public + third-party); Private = Cairn-private only.
- **Tooltips on every cell / row.** Hover any media item to see the exact code snippet to use it. The snippet adapts to the source: Cairn-Media entries show `Cairn.Media:Get<Type>(name)`; third-party LSM entries show `LibStub("LibSharedMedia-3.0"):Fetch("type", "name")`. Tooltip uses the `GameTooltip` global with `ANCHOR_RIGHT`.
- **Welcome tab** updated to count and label the three categories per media type (Cairn-private, Cairn-public, third-party LSM) plus the `Cairn.Media:ListIcons()` count.

### Changed

- **Row tabs build once + filter by hide/show** instead of release+re-acquire on filter change. Avoids the pool-recycle leftover-FontString gotcha that bit Cairn-Media-Browser earlier and gives instant filter response with no widget churn. Hidden rows opt out of body's vertical Stack via `SetLayoutManual(true)` so visible content packs to the top.
- **Icons tab grid** built once + repurposed on search/picker change (cell text via `SetText` on stashed FontStrings; cell font via `SetFont` on stashed `_glyphFs`). Same "build once + repurpose" pattern as the row tabs. No release+re-acquire on user interaction.

## [1] — Initial scaffold (2026-05-07)

### Added

- Internal SubAddon under `Cairn/SubAddons/Cairn-Media-Browser/`. Mirrors the architecture of `Cairn-Demo` and `Cairn-Gui-Demo-2.0`: `Core.lua` shell + `Tabs/*.lua` per tab.
- Slash command `/cmb` (alias `/cairn-media`) toggles the window. Subcommands `show` / `hide` for explicit control.
- Seven tabs: Welcome (per-type counts + theme tie-in note), Fonts (live preview at 12 / 16 / 24 pt with icon-glyph sample for Material* fonts), Statusbars (3-width tinted swatches), Borders (220×60 sample frame via `BackdropTemplate`), Backgrounds (220×60 panel fill, untinted), Sounds (Play button per row, `PlaySoundFile` on the Master channel), Icons (font picker over Outlined / Rounded / Sharp + 5-column glyph grid with name + Unicode codepoint underneath each).
- Visibility filter row (All / Public / Private) above each media-type list. Re-renders the row list in place when toggled.
- Built entirely on `Cairn-Gui-2.0` widgets (Window, TabGroup, Container, Button, Label, ScrollFrame). Raw WoW frame children (Texture, FontString) used for media previews where a Cairn-Gui widget doesn't apply.
- Internal-only: not in `.pkgmeta`, not part of `release.ps1`, not published to CurseForge / Wago / WoWInterface. Same convention as `Cairn-Demo` and `Cairn-Gui-Demo-2.0`.
