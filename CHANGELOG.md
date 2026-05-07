# Changelog

All notable changes to Cairn are recorded here. Version stamps were
YYMMDDHHMM build numbers through `2605041952`; the convention switched
to sequential integer build numbers (one increment per `.dev/release.ps1`
run) on 2026-05-06. Higher integers are newer than any YYMMDDHHMM stamp.

The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Cairn-Gui-2.0 Day 15C: Animation composition + accessibility.**
  Closes out the bulk of Decision 9. New on `widget.Cairn`:
  - `Sequence(steps, opts)` runs a list of specs one after another. The
    next step starts only after every property in the current step has
    completed. `opts.complete` fires after the final step.
  - `Parallel(steps, opts)` runs all specs simultaneously and fires
    `opts.complete` once every property across every step is done.
  - `Stagger(steps, delay, opts)` like `Parallel`, but each step starts
    `(idx-1) * delay` seconds after the call. Implemented via a per-
    record `delay` field that the ticker counts down before treating dt
    as elapsed time, so Stagger remains deterministic and unit-testable.
  - New `lib.ReduceMotion` boolean accessibility flag (default false).
    When truthy, all subsequent Animate / Sequence / Parallel / Stagger /
    `_animatePrimitiveColor` calls clamp duration AND start-delay to
    zero, applying the target value synchronously and firing complete
    handlers synchronously. The animation queue is bypassed entirely.
  - New built-in easings: `easeOutBack` (Penner-standard back-overshoot
    with c1 = 1.70158) and `easeOutBounce` (piecewise bounce).
  - Core MINOR 4 → 5.

### Changed

- The animation ticker now respects a `delay` field on records (counts
  it down before applying values; overshoot rolls into elapsed on the
  same tick so a 0.05s delay + 0.10s dt produces a 0.05s elapsed, not
  zero). Existing records without `delay` behave identically.

### Fixed

- Animation ticker: records appended during the tick (e.g., by a
  complete handler that calls `Animate` again -- including Sequence's
  chain) no longer advance in the same frame they were enqueued. The
  ticker captures the in-flight count at entry and stops once it has
  processed that many records, regardless of late-comers. Without this
  guard, a long synthetic dt (or a slow real frame) could chain through
  an entire Sequence in one tick, producing zero per-step pacing.

## [3] — Cairn-Gui-2.0 Days 14 + 15B + source layout migration (2026-05-06)

Big release. Bundles three feature days, two bug fixes, and a full source-tree reorganization. Driven by the Cairn-Gui-2.0 ARCHITECTURE.md plan plus a known-bug cleanup.

Headline highlights:

- **Cairn-Gui-2.0 Day 14 (Icon + Checkbox):** new `DrawIcon` primitive with atlas-first / file-path fallback, state-variant texture and color specs, `SetPrimitiveShown` helper. New `Checkbox` widget on top of it.
- **Cairn-Gui-2.0 Day 15B (Animation engine + transition pre-wire):** new `Core/Animation.lua` with `Animate` / `CancelAnimations` API, four built-in easings, custom-easing registration. Per-widget OnUpdate parented to the widget frame so Blizzard auto-pauses ticking on Hide. The Primitives state machine animates state-variant color changes when a spec carries a `transition` token; every Button variant now fades on hover/press.
- **Bugfix: pool-recycle state leak.** Acquire's pool path resets `_visualState` / `_hovering` / `_pressing` / `_disabled` and restores `frame:SetEnabled(true)` so a recycled widget paints at default and responds to clicks.
- **Source layout: per-module folders.** All 18 previously-flat libraries moved into per-module folders. The v1 GUI family collapsed under `Cairn-Gui-1.0/`; the v2 GUI family collapsed under `Cairn-Gui-2.0/`. The two v2 bundles renamed from `*-1.0` to `*-2.0` to align bundle MAJORs with the Core they target.
- **142 in-game / Python assertions** across 5 test suites all passing at release time.

### Changed

- **Source layout: per-module folders.** Every Cairn library now lives in
  its own folder, replacing the previous mixed layout where some libs
  were flat `.lua` files at the repo root and some were already foldered.
  Folder naming uses the `CairnX/` short form (drops the LibStub-MAJOR
  version suffix); existing already-foldered libraries keep their longer
  `Cairn-X-1.0/` names. The umbrella facade `Cairn.lua` stays at the root.
  - 16 flat libraries moved into `CairnCallback/`, `CairnEvents/`,
    `CairnLog/`, `CairnLogWindow/`, `CairnDB/`, `CairnSettings/`,
    `CairnAddon/`, `CairnSlash/`, `CairnEditMode/`, `CairnLocale/`,
    `CairnHooks/`, `CairnSequencer/`, `CairnTimer/`, `CairnComm/`,
    `CairnSettingsPanel/`, `CairnStandalone/`. The file inside each
    folder keeps its LibStub-MAJOR-style name (e.g.,
    `CairnEvents/Cairn-Events-1.0.lua`).
  - **Cairn-Gui-1.0 family collapsed under a single container.** The v1
    base file plus its components (Tools, Style, Core, Menu) all live
    under `Cairn-Gui-1.0/` now, with each component in its own folder.
    Source-tree cohesion for the Diesal-derived family.
  - **Cairn-Gui-2.0 family collapsed under a single container.** The v2
    bundles (`Cairn-Gui-Widgets-Standard-*`, `Cairn-Gui-Theme-Default-*`)
    moved under `Cairn-Gui-2.0/` to mirror the v1 structure visually.

- **Bundle MAJOR rename: 1.0 → 2.0** for the two v2 bundles, fixing the
  longstanding naming mismatch where bundles built on Cairn-Gui-2.0 Core
  were nonetheless named `*-1.0`. Both bundles always called
  `LibStub("Cairn-Gui-2.0", true)` and hard-failed without the v2 Core,
  so the on-disk and code-referenced MAJORs now line up.
  - `Cairn-Gui-Widgets-Standard-1.0` → `Cairn-Gui-Widgets-Standard-2.0`.
    MINOR resets to 1; previous MINOR history (Days 8-15B) preserved in
    the file header as "history under previous MAJOR".
  - `Cairn-Gui-Theme-Default-1.0` → `Cairn-Gui-Theme-Default-2.0`. Same
    pattern: MINOR resets to 1 with previous-MAJOR history preserved.
  - All 5 widget consumers (`Button.lua`, `Label.lua`, `Container.lua`,
    `Window.lua`, `Checkbox.lua`) updated to call
    `LibStub("Cairn-Gui-Widgets-Standard-2.0", true)`.

- **All 5 TOCs rewritten** to reflect the new layout: `Cairn.toc`
  (Retail), `Cairn_Mists.toc`, `Cairn_TBC.toc`, `Cairn_Vanilla.toc`,
  `Cairn_XPTR.toc`. The 4 flavor TOCs were lagging behind Retail (missing
  `Animation.lua` and `Checkbox.lua` from the [Unreleased] features
  above); they're now fully in sync.

- **No public API changes from this migration.** Consumers using
  `LibStub("Cairn-X-1.0")` keep working — only the on-disk paths
  changed. The bundle rename DOES change `LibStub` lookup names for
  `Cairn-Gui-Widgets-Standard-*` and `Cairn-Gui-Theme-Default-*`;
  consumers (rare; the bundles are usually consumed via Core) need to
  switch from `-1.0` to `-2.0`.

### Fixed

- **Cairn-Gui-2.0 pool-recycle state-machine leak.** A widget Released
  while in a non-default visual state (hover, pressed, disabled) was
  carrying that state into its next pool-Acquire, so a recycled Button
  could paint at hover color or refuse clicks even though the consumer
  saw a "fresh" widget. `Core/Acquire.lua` pool path now resets
  `_visualState`, `_hovering`, `_pressing`, `_disabled` on the cairn
  AND calls `frame:SetEnabled(true)` on the underlying Blizzard frame
  before `OnAcquire` runs. Verified with a new test:
  `Forge\.dev\tests\cairn_gui_2_pool_reset.lua` — 14/14 PASS.
- **Cairn-Gui-2.0 MINOR 3 → 4.** Bugfix only; no public API changes.
  Consumers don't need to bump their `RequireCore` minimum.

### Added

- **Cairn-Gui-2.0 Day 15B: Animation engine + transition pre-wire on
  primitives.** Slice B of the 11-sub-decision Decision-9 plan. Spring
  physics, Sequence/Parallel/Stagger, OKLCH, ReduceMotion, off-screen
  pause, AnimationGroup-backend routing, and concurrency cap are
  deferred to later slices.
  - New `Core/Animation.lua` ships the engine. Public API on the lib:
    `RegisterEasing(name, fn)` and a `Cairn.Gui.easings` registry with
    four built-ins (`linear`, `easeIn`, `easeOut`, `easeInOut`). Public
    API on `widget.Cairn`: `Animate(spec)` for declarative property
    tweens (alpha / scale / width / height as scalar, with `to`, `dur`,
    `ease`, `complete` per property) and `CancelAnimations(prop?)` to
    cancel a single property or every in-flight animation on the widget.
    Re-calling `Animate` for an already-animating property captures the
    current value as the new `from` and replaces the in-flight record;
    no snapping during state ping-pong.
  - One OnUpdate per widget regardless of property count (per Decision 9).
    The tick frame is parented to the widget frame so Blizzard's
    visibility cascade auto-pauses ticking on Hide and resumes on Show
    -- one of Decision 9's lifecycle sub-decisions delivered for free
    by the parenting choice. The OnUpdate detaches itself when the
    per-widget queue drains, so an idle UI pays nothing per frame.
  - Internal `widget.Cairn:_animatePrimitiveColor(slot, toColor, dur,
    ease)` lerps RGBA over the duration via the named easing, applied
    via `SetVertexColor` across every texture in the primitive record
    (so a multi-edge border tracks in lockstep).
  - **Transition token pre-wire on primitives** (mandatory per Decision
    9). Any state-variant spec passed to `DrawRect` / `DrawBorder` /
    `DrawIcon` (color tint) can include a `transition = "duration.X"`
    key. When the state machine moves between visual states, the new
    color animates over that duration instead of snapping. Decision 5's
    duration tokens drive the timing through the theme cascade. Initial
    paint and `Repaint` always snap; only state-change paths animate.
  - Auto-cancel on Release: `Base:Release` is wrapped in `Animation.lua`
    to call `CancelAnimations()` and detach the OnUpdate before
    delegating to the original Release. Pooled widgets get a clean
    animation slate on every recycle.
  - Pilot consumer: every Button variant (`default`, `primary`,
    `danger`, `ghost`) now carries `transition = "duration.fast"` on its
    bg state map. Hovering and pressing a Button visibly fades between
    states over ~120ms -- the existing widget gained the animation for
    free without an Animate call in its OnAcquire.

- **Cairn-Gui-2.0 Day 14: Icon primitive + Checkbox widget.**
  - `Core/Primitives.lua` — new `widget.Cairn:DrawIcon(slot, spec, opts)`
    primitive. Atlas-first resolution via `C_Texture.GetAtlasInfo`,
    file-path fallback, per Decision 7. Supports state-variant texture
    specs (default / hover / pressed / disabled), token-name resolution
    through the theme cascade, optional color tint (string token, literal
    tuple, or state-variant table), anchored sub-region positioning
    (anchor + offsetX + offsetY + width + height with length-token
    support), default layer ARTWORK. Empty/nil source hides; non-empty
    re-shows. Re-Draw on the same slot updates in place. The state
    machine and Repaint dispatch primitives by record kind via a shared
    helper so Rect / Border / Icon all stay in lockstep on hover, press,
    disabled, and theme change.
  - `Core/Primitives.lua` — new `widget.Cairn:SetPrimitiveShown(slot,
    bool)` helper. Toggles every texture in a primitive record without
    redrawing. Used by Checkbox to flip the check glyph on toggle.
  - `Core/Theme.lua` and `Cairn-Gui-Theme-Default-1.0` — new
    `texture.icon.check` token, default `common-icon-checkmark` atlas.
  - `Cairn-Gui-Widgets-Standard-1.0/Widgets/Checkbox.lua` — pooled
    Checkbox widget. 16x16 box with raw textures (matches Button's
    raw FontString precedent for label content), DrawIcon for the check
    glyph, whole-row DrawRect with state-variant ghost-hover for
    subtle row-level hover/press feedback. Public API: `SetChecked`,
    `IsChecked`, `Toggle`, `SetText`, `GetText`, `SetEnabled`. Events:
    `Click(mouseButton, newValue)` on every enabled click; `Toggled
    (newValue)` whenever the checked value actually flips (programmatic
    SetChecked-to-same-value does NOT re-fire).

### Changed

- **Cairn-Gui-2.0 MINOR 2 → 3.** Animation engine + transition pre-wire
  on the Primitives state machine. Existing primitives keep working;
  specs without a `transition` key continue to snap. `SetVisualState`
  now honors transitions when the spec carries them (matching the
  hover/press path); use `Repaint` if you specifically want a snap.
- **Cairn-Gui-2.0 MINOR 1 → 2.** New public methods (`DrawIcon`,
  `SetPrimitiveShown`) extend the surface; existing primitives unchanged.
- **Cairn-Gui-Widgets-Standard-1.0 MINOR 2 → 3.** Bundle now requires
  Core MINOR ≥ 3 (Animate + transition pre-wire) because Button uses
  the transition token. Existing widgets unchanged for consumers who
  only use the public API.
- **Cairn-Gui-Widgets-Standard-1.0 MINOR 1 → 2.** Bundle now requires
  Core MINOR ≥ 2 via `RequireCore("Cairn-Gui-2.0", 2)` because Checkbox
  uses `DrawIcon`.
- **Cairn-Gui-Theme-Default-1.0 MINOR 1 → 2.** Adds the
  `texture.icon.check` token registration.
- **`Cairn.toc`** — loads `Cairn-Gui-2.0\Core\Animation.lua` after
  Primitives and before Layout; loads
  `Cairn-Gui-Widgets-Standard-1.0\Widgets\Checkbox.lua` after Window.

### Verified in-game

- `Forge\.dev\tests\cairn_gui_2_animation.lua` — 50/50 PASS. Covers
  built-in easings + custom easing registration, `Animate` mid-tick
  interpolation and complete-handler firing exactly once, in-flight
  replacement (new `from` is the current value), unknown-property
  silent ignore, `CancelAnimations(prop)` and `CancelAnimations()`,
  OnUpdate detachment when queue drains, tick frame parented to widget
  frame, `_animatePrimitiveColor` RGBA lerp, transition pre-wire on
  Button hover (state change enqueues primColor anim, mid-tick color
  is between default and hover), auto-cancel on Release with pool
  reuse not retaining residual animations.
- `Forge\.dev\tests\cairn_gui_2_icon.lua` — 30/30 PASS. Covers atlas
  vs. file-path resolution, token cascade, state-variant switching,
  literal + token color tints, hide/show via empty source and via
  `SetPrimitiveShown`, in-place re-draw idempotency, Repaint, anchor
  validation, pool reuse.
- `Forge\.dev\tests\cairn_gui_2_checkbox.lua` — 32/32 PASS. Covers
  registration, opts honoring, `SetChecked` / `Toggle` / `IsChecked`
  semantics, Toggled event dedup on same-value writes, click bridging
  via Blizzard `OnClick` script firing both `Click` and `Toggled` with
  the new value, `SetEnabled(false)` suppression of click handling,
  pool reuse with subscription cleanup (the Day 13 Base:Release Off()
  contract held).

## [2] — Multi-flavor TOCs (2026-05-06)

### Added

- **Multi-flavor support.** Cairn now ships per-flavor TOCs covering
  every WoW client Steven's project supports:
  - `Cairn.toc` — Mainline / Retail (Interface 120005)
  - `Cairn_Mists.toc` — MoP Classic (Interface 50503)
  - `Cairn_TBC.toc` — TBC Anniversary (Interface 20505)
  - `Cairn_Vanilla.toc` — Classic Era / Hardcore (Interface 11508)
  - `Cairn_XPTR.toc` — Experimental PTR (Interface 120007)

  All five TOCs share the same file load order. The BigWigs packager
  picks each TOC up by suffix and produces a separate per-flavor zip.
  Existing single-TOC consumers (Pattern B / vendored) keep working
  against `Cairn.toc` as before.

### Changed

- **Mainline `Cairn.toc` `## Interface:` line** trimmed from the
  comma-separated multi-interface form
  (`120005, 50503, 20505, 11508, 120007`) to just `120005`. Per-flavor
  TOCs now declare each Interface number on their own.
- **`.dev/release.ps1`** `$FilesToBump` lists all 5 TOCs so every release
  bumps them in lockstep. Adding a new flavor in the future is a single
  array entry; retiring one is a single deletion.

### Notes

- **First-ship distribution policy** — the four new flavor TOCs omit
  `X-Wago-ID` and `X-WoWI-ID` so the BigWigs packager only uploads them
  to CurseForge. Once each flavor is validated in-game, add the two
  X-* lines to enable Wago + WoWI publishing on subsequent releases.
- **Compatibility caveats per flavor** are documented at the top of
  each per-flavor TOC. Headline: `Cairn-EditMode-1.0` is Retail-only
  and no-ops on Classic flavors via LibEditMode's optional dep.
  `Cairn-Settings-1.0` / `Cairn-SettingsPanel-1.0` lean on the modern
  Settings API which is partially supported on Vanilla / TBC; consumer
  addons should treat Settings registration as best-effort there.

## [1] — Cairn-Gui-2.0 + sequential versioning (2026-05-06)

First release under the sequential build-number convention. Bundles the
Cairn-Gui-2.0 widget library work from Days 1-13, the dev-tooling
consolidation under `.dev/`, and the versioning convention switch.

### Added

- **Cairn-Gui-2.0** — parallel v2 widget library, separate LibStub MAJOR
  so it coexists with Cairn-Gui-1.0. Consumers pick which to depend on.
  - `Cairn-Gui-2.0.lua` lib anchor: six registries (widgets, layouts,
    themes, primitives, mixins, pools), `RequireCore` / `GetVersion`
    surface, `lib.Dev` flag.
  - `Mixins/Base.lua` — base mixin with widget identity, intrinsic-size,
    Acquire / Release lifecycle, Reparent, cascade release.
  - `Core/Acquire.lua` — `RegisterWidget(name, def)` + `Acquire(name,
    parent, opts)` with optional pool reuse.
  - `Core/Theme.lua` — five-step cascading theme resolution: instance
    override → ancestor theme → active theme → extends chain → library
    default. Token-type validation by name prefix.
  - `Core/Events.lua` — `On` / `Once` / `Off` / `OffByTag` / `Fire` /
    `Forward` over Cairn-Callback. Per-widget registry, multi-subscriber,
    error-isolated.
  - `Core/Primitives.lua` + auto state transitions — `DrawRect` /
    `DrawBorder` with state-variant specs (default / hover / pressed /
    disabled), `SetVisualState` / `Repaint` / `SetEnabled`.
  - `Core/Layout.lua` + `Manual`, `Fill`, `Stack` strategies — lazy
    OnUpdate pump that detaches when the dirty set drains, so idle UIs
    pay zero per-frame cost.
- **Cairn-Gui-Widgets-Standard-1.0** — bundled widget set built on the
  Cairn-Gui-2.0 core. Separate LibStub MAJOR per the architecture's
  Decision 11 so consumers can swap in alternative bundles.
  - `Widgets/Container.lua` — building-block frame with optional bg /
    border opts, exposed by Window as content area.
  - `Widgets/Button.lua` — pooled, four variants (`default`, `primary`,
    `danger`, `ghost`), state-variant primitives, bridges Blizzard
    OnClick to a Cairn `"Click"` event.
  - `Widgets/Label.lua` — pooled, eight text variants (body / heading /
    small / muted / danger / success / warning / on_accent), intrinsic
    sizing from rendered string.
  - `Widgets/Window.lua` — top-level frame with title bar (Container +
    heading Label), optional close Button (ghost variant) firing
    `"Close"`, content area exposed via `GetContent`. Drag-to-move from
    the title bar. Not pooled (top-level, low churn).
- **Cairn-Gui-Theme-Default-1.0** — default visual theme, ~80 tokens:
  dark surfaces, blue accent, full state variants for primary / danger
  / ghost button types, semantic accent palette (success / warning /
  info), padding+gap scale, three font sizes, snappier durations
  (12 / 20 / 35 ms). Auto-activates on load via
  `SetActiveTheme("Cairn.Default")`.
- **`.dev/` folder convention** — all dev-local artifacts live under
  `/.dev/` at the repo root: `release.ps1` and any future tooling,
  caches, intermediate dumps, configs. One folder, one `.gitignore`
  line, one `.pkgmeta` exclusion. Established 2026-05-05 on LibCodex;
  applied to Cairn here for consistency.

### Changed

- **Versioning convention**: switched from YYMMDDHHMM build stamps to
  sequential integer build numbers, +1 per `.dev/release.ps1` run.
  Reads the current `## Version:` from `Cairn.toc`, increments by 1,
  writes the result back. Caveat: the new sequential value (1) is
  numerically lower than the last published stamp (2605041952), so
  users on 2605041952 won't auto-update from CurseForge / WoWInterface
  / Wago. They have to update once manually; auto-updates resume from
  the next bump.
- **`release.ps1` moved to `.dev/release.ps1`** with anchored repo-root
  resolution (`Split-Path -Parent $PSScriptRoot`) so the script works
  regardless of the user's current directory. Header docs rewritten to
  describe the sequential convention; the load-bearing reminders
  (Cairn lib MINORs are NOT auto-bumped, CallbackHandler MINOR=7 pin)
  are preserved.
- **`.pkgmeta`** — `ignore:` block now excludes `.dev` (covers
  `release.ps1` and any future dev-only artifacts in one line). Version
  comment updated to reference the sequential convention.
- **`.github/workflows/release.yml`** — header comment updated to
  describe sequential build-number tags instead of YYMMDDHHMM stamps.
- **`.gitignore`** — added `.dev/` to the dev-tooling block. The
  pre-existing `*.ps1` rule still applies as defense in depth.

### Notes

- **Cairn-Gui-2.0** ships alongside Cairn-Gui-1.0; nothing removed. The
  Diesal-derived 1.0 widget set continues to work for consumers that
  depend on it. New consumers should target 2.0.
- **No public API changes** to the existing v0.1 / v0.2 modules
  (`Cairn-Events-1.0`, `Cairn-Log-1.0`, `Cairn-DB-1.0`,
  `Cairn-Settings-1.0`, `Cairn-Addon-1.0`, `Cairn-Slash-1.0`,
  `Cairn-EditMode-1.0`, `Cairn-Locale-1.0`, `Cairn-Hooks-1.0`,
  `Cairn-Sequencer-1.0`, `Cairn-Timer-1.0`, `Cairn-Comm-1.0`,
  `Cairn-Gui-1.0`, `Cairn-SettingsPanel-1.0`).
- **`ARCHITECTURE.md`** at `Cairn-Gui-2.0/ARCHITECTURE.md` documents the
  11 locked design decisions for the v2 library. It is local-only per
  the Cairn `.gitignore` allowlist policy and does not ship in the
  source repo or the published zip.

## 2605041952 — Initial public release (2026-05-04)

First public release. Wired CurseForge (1532175), WoWInterface (27134),
and Wago (`b6XemBKp`) distribution via the BigWigsMods/packager v2
GitHub Actions workflow. Tag push triggers a build that uploads to all
three sites and creates a matching GitHub Release.

### Added — Core libraries (v0.1)

- **`Cairn-Events-1.0`** — declarative event-handler library. Per-addon
  registry with auto-cleanup at `PLAYER_LOGOUT`.
- **`Cairn-Log-1.0`** — structured logger with per-source filtering,
  ring-buffer SavedVariables persistence, chat-frame echo opt-out.
- **`Cairn-LogWindow-1.0`** — minimal in-game log viewer used by
  `Cairn-Standalone`'s `/cairn log` subcommands.
- **`Cairn-DB-1.0`** — SavedVariables wrapper with profile / global /
  realm scopes, defaults merging, and reset-to-defaults.
- **`Cairn-Settings-1.0`** — declarative settings schema that bridges to
  Blizzard's native Settings panel and registers EditMode anchors.
- **`Cairn-Addon-1.0`** — addon lifecycle (`OnInit`, `OnEnable`,
  `OnDisable`) with `Cairn.DB` integration.
- **`Cairn-Slash-1.0`** — slash-command router with subcommand
  composition.

### Added — Core libraries (v0.2)

- **`Cairn-EditMode-1.0`** — EditMode anchor registration helpers built
  on top of LibEditMode (soft-optional dep).
- **`Cairn-Locale-1.0`** — per-addon localization with fallback chain
  and `SetOverride` / `GetOverride` for testing translations.
- **`Cairn-Hooks-1.0`** — multi-callback hook management with priority
  ordering and `pcall`-isolated dispatch.
- **`Cairn-Sequencer-1.0`** — composable step execution and lifecycle
  management for multi-stage operations.
- **`Cairn-Timer-1.0`** — single-shot and repeating timer wrappers with
  named-cancel support.
- **`Cairn-Comm-1.0`** — addon-channel messaging with throttling and
  multi-part reassembly.
- **`Cairn-Gui-1.0`** — widget framework derived from Diesal libraries
  (BSD 3-clause): Tools + Style + Core + Menu bundles with 12 widgets
  (Window, Button, CheckBox, Input, ScrollFrame, Spinner, DropDown,
  ComboBox, etc.). See `Diesal/ATTRIBUTION.md` for provenance.
- **`Cairn-SettingsPanel-1.0`** — opinionated settings panel built on
  `Cairn-Gui-1.0` for addons that need a custom UI rather than the
  Blizzard panel.

### Added — Library shims and vendored deps

- **`Cairn-Callback-1.0`** — standalone callback-registry library
  exposed at `LibStub("Cairn-Callback-1.0")`. Backs the
  `CallbackHandler-1.0` shim and exposes the `instances` table for
  `Forge_Registry` to enumerate live registries.
- **`CallbackHandler-1.0` shim** — port of ElvUI's MINOR=8 variant,
  registered at MINOR=7 so it loses to ElvUI's bundled copy when ElvUI
  is present and wins against upstream WoWAce (MINOR=6) otherwise. See
  the file header for the full ElvUI-race rationale.
- **`LibSharedMedia-3.0`** — vendored as-is (LGPL v2.1) for the
  cross-addon shared media registry. LibStub auto-wins the highest
  revision if another addon embeds a newer copy.
- **`LibStub`** — universal addon-library loader.

### Added — Umbrella facade and standalone

- **`Cairn.lua`** — umbrella facade plus `/cairn` slash router. Same
  API whether Cairn is loaded as a shared addon or LibStub-embedded.
- **`Cairn-Standalone-1.0.lua`** — SavedVariables persistence + `/cairn
  log` subcommands. Loaded only when Cairn ships as a standalone
  addon; do not include when embedding Cairn in another addon.

### Distribution

- CurseForge project ID **1532175**.
- WoWInterface project ID **27134**.
- Wago project ID **b6XemBKp** (note: the published URL slug is
  separate from the Wago ID).
- BigWigsMods/packager v2 workflow at `.github/workflows/release.yml`,
  triggered on tag push.
- License: MIT (`LICENSE` shipped inside the package zip).

### Hybrid distribution model

Cairn works as a standalone shared addon OR LibStub-embedded inside
another addon. The umbrella facade pattern keeps the API identical in
both modes; `Cairn-Standalone-1.0.lua` is the only file consumers omit
when embedding.
