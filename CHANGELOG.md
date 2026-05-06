# Changelog

All notable changes to Cairn are recorded here. Version stamps were
YYMMDDHHMM build numbers through `2605041952`; the convention switched
to sequential integer build numbers (one increment per `.dev/release.ps1`
run) on 2026-05-06. Higher integers are newer than any YYMMDDHHMM stamp.

The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
