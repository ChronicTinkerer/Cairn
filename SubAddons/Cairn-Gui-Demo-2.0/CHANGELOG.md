# Cairn-Gui-Demo-2.0 changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Build
numbers are sequential integers per the Cairn version convention; one
bump per `release.ps1` run.

## [Unreleased]

## [1] - 2026-05-07

Initial cut. Author-facing showcase of every Cairn-Gui-2.0 feature in a
single tabbed window. Slash command `/cgdemo` (and long form
`/cairn-gui-demo`). Iterative in-game testing on the same day surfaced
several integration bugs (cell layout fallback, popup strata layering,
ScrollFrame content sizing, locale switching API, Stagger animation
collision, label-overflow when text changes after layout); all fixed
before sign-off.

### Fixed during initial development

- Demo Window strata moved from `DIALOG` to `HIGH` so DIALOG-strata
  popups (Dropdown option lists, child Windows) layer above the demo.
- Window width 920 -> 1240 so all 14 tabs fit without clipping.
- Layouts / Primitives / Layouts Extra Grid layouts now pass explicit
  `cellHeight`; the silent fallback to 20px collapsed cells on top of
  each other.
- `Demo:MakeScrollable` helper added; reads `live:GetWidth()/GetHeight()`
  and passes them to the inserted ScrollFrame so the scroll-child sizes
  to match the visible viewport.
- L10n locale switching uses library-wide `Locale.SetOverride(code)`
  (instance-level `:SetLocale` doesn't exist).
- Animations Stagger uses `Sequence` per actor; back-to-back `Animate`
  calls on the same property cancel each other.
- L10n + Contracts action rows call `RelayoutNow()` after `SetText` so
  re-localized / re-confirmed labels don't overflow into siblings.
- L10n namespace registered with `silent = true` to suppress missing-
  key warning spam from Cairn-Gui's resolver probing for `Lookup`.
- Containers child-window popup uses `FULLSCREEN_DIALOG` strata as
  belt-and-suspenders above the now-HIGH demo Window.

### Added

- Root Window + TabGroup shell with lazy per-tab build.
- Welcome tab: bundle version readout, tab directory.
- Buttons tab: variants, disabled state, click multi-subscriber proof,
  intrinsic sizing demo.
- Inputs tab: EditBox / Slider / Checkbox / Dropdown / Label variants
  feeding a single live readout.
- Containers tab: secondary Window pop-up, ScrollFrame with 30 rows,
  nested TabGroup.
- Layouts tab: Manual, Fill, Stack vertical, Stack horizontal, Grid,
  Form, Flex row, Flex column rendered side-by-side.
- Layouts Extra tab: Hex pointy-top, Hex flat-top, Polar full-circle,
  Polar arc. Graceful "bundle not loaded" fallback.
- Themes tab: registers Demo.Vivid + Demo.Mono themes; live picker
  Dropdown; subtree-theme demo; per-instance token override demo.
- Primitives tab: DrawRect / DrawBorder / DrawIcon / DrawDivider /
  DrawGlow / DrawMask + state-variant transition cell.
- Animations tab: Animate (alpha+scale), Spring, Sequence (blink),
  Stagger pulse, ReduceMotion checkbox.
- Events tab: three regular subscribers + Once + tagged subscriber on a
  shared button; OffByTag and Off() detach controls; Forward to a
  satellite.
- L10n tab: registers @CairnGuiDemoL10n namespace with enUS/deDE/frFR;
  Dropdown switches active locale at runtime; gracefully degrades if
  Cairn-Locale isn't loaded.
- Inspector tab: live Stats snapshot, depth-first tree walk, EventLog
  Enable/Disable/Clear/Tail with auto-refresh ticker.
- Secure tab: ActionButton (spell), MacroButton (macrotext), UnitButton
  (player); fake-combat toggle; live combat-queue stats. Graceful
  fallback when the secure bundle isn't loaded.
- Contracts tab: Run RunContracts() and dump per-kind buckets; broken-
  widget injector to demonstrate the warn path.

### Notes

- License: MIT (parallel to the Cairn library it demonstrates; not the
  All Rights Reserved end-user-addon convention).
- Registers `Demo.Vivid`, `Demo.Mono`, and `CairnGuiDemoL10n` at file
  load. Re-registration is idempotent so `/reload` is safe.
