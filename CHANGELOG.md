# Changelog

All notable changes to Cairn are recorded here. Version stamps were
YYMMDDHHMM build numbers through `2605041952`; the convention switched
to sequential integer build numbers (one increment per `.dev/release.ps1`
run) on 2026-05-06. Higher integers are newer than any YYMMDDHHMM stamp.

The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Cairn-LogWindow-2.0 MINOR=1** — drop-in successor to `Cairn-LogWindow-1.0`, built entirely on `Cairn-Gui-2.0` Standard widgets (Window + ScrollFrame + Label body + toolbar with Level / Source `Dropdown`s, Search `EditBox`, and Clear `Button`). Public API matches v1 exactly (`Toggle / Show / Hide / IsShown / SetSourceFilter / SetMinLevel / SetSearch / Refresh`), so the `/cairn log ...` slash subcommands and any consumer code calling `Cairn.LogWindow:...` Just Work. New: filters are now discoverable through inline UI controls instead of requiring slash commands. Source dropdown auto-populates from `Cairn.Log`'s registered loggers + live buffer entries; refreshes when an unknown source logs while the window is open. Strata is `DIALOG` so the window layers above any consumer `Window` (which now defaults to `HIGH` since Standard-2.0 MINOR 3). The umbrella facade installs v2 directly via `rawset(Cairn, "LogWindow", lib)` at file-scope load — `Cairn.lua`'s `__index` hardcodes the `-1.0` suffix and would otherwise lock callers onto v1 forever. Final v1 conversion under the v2-only strategy; the `Cairn-Gui-1.0` family is now eligible for extraction to `Diesal-Continued`.
- **Cairn-Standalone-1.0** — `/cairn log ...` slash dispatcher now resolves `Cairn-LogWindow-2.0` first with a `Cairn-LogWindow-1.0` fallback. No call-site changes for users; the v2 surface is API-compatible with v1 so the dispatch table didn't need touching.
- **Cairn-SettingsPanel-2.0 MINOR=1** — drop-in successor to `Cairn-SettingsPanel-1.0`, built entirely on `Cairn-Gui-2.0` Standard widgets. Same public surface (`lib.OpenFor / HideFor / ToggleFor`); consumers calling `settings:OpenStandalone()` get the v2-rendered panel automatically. Full v1 schema parity: header / toggle / range / dropdown / text / anchor / color / keybind. Color renders a live-tinted swatch + opens Blizzard's `ColorPickerFrame` on click; keybind renders as a Button that enters capture mode and binds the next keypress (Esc clears, modifier-aware).
- **Cairn-Settings-1.0 MINOR=4** — `:OpenStandalone()` now prefers `Cairn-SettingsPanel-2.0` when present, with a `Cairn-SettingsPanel-1.0` fallback. No call-site changes for consumers. Spotted while building Cairn-Demo's Settings tab: a v2-styled demo window opening a v1-styled panel was a visible mismatch.
- **Cairn-Settings-1.0 MINOR=5** — color schema validator now accepts BOTH named `{r=, g=, b=[, a=]}` and positional `{r, g, b[, a]}` shapes; positional gets normalized to named at validate time so consumer code only deals with one form. Lib header documented named, validator only accepted positional — caught while wiring Cairn-Demo's Settings tab schema. Same fix exposed text/color/keybind type-specific docs in the header that were absent.

### Fixed

- **Cairn-LogWindow-1.0 MINOR=2** — frame strata bumped from `HIGH` to `DIALOG` so the window layers above hosts using `Cairn-Gui-2.0`'s default `Window` strata (`HIGH` since Standard-2.0 MINOR 3). Caught when Cairn-Demo's "Toggle LogWindow" button opened the window successfully but it rendered behind the demo, looking like a no-op.
- **Cairn-Slash-1.0 MINOR=2** — added public introspection methods so dev/debug UIs don't have to read the private `_subs` / `_slashes` tables.
  - `slash:GetSubcommands()` returns a fresh array of `{ name = "config", help = "open the config panel" }` entries sorted by name.
  - `slash:GetSlashes()` returns a fresh array of every slash this object responds to (primary + aliases).
  - Spotted while building Cairn-Demo's Slash tab — the only way to render the registered-subcommands list was to peek at `s._subs`. Public API now covers it.

### Added (internal)

- **Cairn-Demo** — new internal SubAddon under `Cairn/SubAddons/Cairn-Demo/`. Companion to `Cairn-Gui-Demo-2.0`, covering the non-GUI library surface: 16 tabs (Welcome + Callback + Events + Log + DB + Settings + Addon + Slash + EditMode + Locale + Hooks + Sequencer + Timer + FSM + Comm + Smoke Test). Slash `/cdemo` (alias `/cairn-demo`). MIT. Not in `.pkgmeta` or `release.ps1` (matches the Cairn-Gui-Demo-2.0 internal-only decision).
- **Forge/.dev/tests/cairn_demo_smoke.lua** — headless mirror of the Smoke Test tab. Phase 1 walks every Cairn-Demo tab; phase 2 calls the in-tab runner via `Demo._runSmokeTest(print)` and PASS/FAIL-asserts every public Cairn library API.

## [12] — Cairn-Gui-2.0 Core MINOR=19 + Standard MINOR=3: framework gaps from Demo (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=19, Cairn-Gui-Widgets-Standard-2.0 MINOR=3** — five framework gaps surfaced while building `Cairn-Gui-Demo-2.0` and walking every widget in-game. Each fix removes a class-of-bug consumers hit, not a single instance.

  - **Auto-invalidate parent layout on label/value setters.** New `Base:_invalidateParentLayout()` helper in `Mixins/Base.lua`. `Button.SetText` / `Button.SetVariant`, `Label.SetText` / `Label.SetVariant`, `Checkbox.SetText`, `EditBox.SetText` / `SetPlaceholder`, `Dropdown.SetSelected` / `SetOptions` all call it. Stack horizontal in particular silently kept old widths after `SetText`, letting longer strings (locale switches, post-click confirmations) bleed into adjacent siblings; the auto-invalidate path triggers the parent's next-frame relayout so widths re-measure. Universal: every consumer benefits without changing code.

  - **`ScrollFrame` outer-resize propagation.** New `OnSizeChanged` hook on the outer frame keeps the scroll-child Container's width in sync with the viewport (minus scrollbar reserve). Previously `OnAcquire` sized content from `opts.width`; if a consumer `SetPoint`'d the outer frame to fill a parent later, the content stayed at the original width and children added to it anchored to the wrong-width frame. Idempotent across pool re-Acquire via `_outerSizeHooked`.

  - **`Core/L10n.lua` resolver: rawget against the prototype.** Cairn-Locale's instance metatable treats unknown attribute reads as translation lookups, so `if type(instance.Lookup) == "function"` emitted a missing-key warning every resolution. Resolver now uses `getmetatable(instance).__index` where it's a table, or calls `instance.Get` directly when `__index` is a function (Cairn-Locale's pattern). Silent in the common case.

  - **`Cairn.Dev` warnings on layout fallback.** `Stack`, `Grid`, `Flex`, `Form` now emit a `Cairn-Log` warning under `Cairn.Dev` when a child has no intrinsic size AND no current frame size, so the strategy resorts to `DEFAULT_FALLBACK_SIZE = 20`. Previously this was silent; cells collapsed on top of each other (the "jumbled" symptom) with no signal to the author. Warning text includes the offending widget type and the strategy name.

  - **Window default strata `DIALOG` → `HIGH`.** With Window at `DIALOG`, `DIALOG`-strata popups (`Dropdown` option lists, child `Window`s) raced for frame level inside the same strata and lost half the time, rendering invisibly behind the host. Defaulting Window to `HIGH` lifts host windows out of the collision zone; pass `strata = "DIALOG"` explicitly when a `Window` IS itself a popup. `ARCHITECTURE.md` gains a "Strata Convention" section formalizing `HIGH` / `DIALOG` / `FULLSCREEN_DIALOG` roles.

### Migration notes

- Consumers that explicitly called `container.Cairn:RelayoutNow()` after a `SetText` to work around the old behavior can drop those calls; auto-invalidate handles it. The explicit `RelayoutNow()` is still supported for synchronous override.
- Consumers that `SetFrameStrata("HIGH")` on their host Window can drop the override; `HIGH` is now the Window default.
- Consumers running `Cairn.Dev = true` will see new warnings if they had layouts hitting the 20px fallback. The warnings are advisory, not blocking; pass an explicit `cellHeight` / `rowHeight` / `_flexBasis` to silence.

## [11] — Cairn-Gui-2.0 Core MINOR=18: Round-out pass (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=18** — round-out pass that finishes every remaining ARCHITECTURE.md item. Six surfaces touched: L10n resolver, Contracts validator, animgroup off-screen pause parity, Translation/Rotation animgroup routing, default theme atlas tokens, and a new optional Layouts-Extra bundle.

  - **`Core/L10n.lua` (new)** — `lib:ResolveText(text, widgetCairn?)` resolves the `@namespace:key` prefix against `Cairn-Locale-1.0` (lazy lookup; no hard dep). Mixes `Base:_resolveText(text)` into `Mixins/Base.lua` so widget mixins can call it from text-setting paths. Tries `instance:Lookup(key)` first then `instance:Get(key)`; pass-through for plain strings and for missing namespaces. Wired into `Button.SetText`, `Label.SetText`, `Checkbox.SetLabel`, `EditBox.SetText` + `SetPlaceholder`, `MacroButton.SetText`, and `UnitButton.SetText`.

  - **`Core/Contracts.lua` (new)** — Decision 11 validators. `ValidateWidget`, `ValidateLayout`, `ValidateTheme`, `ValidateEasing` enforce per-registration invariants (secure widgets need a Secure*Template, `pool=true` requires a non-function reset to be flagged as an error, `prewarm` must be non-negative). `lib:RunContracts()` walks every registered piece and returns a `{ ok, warnings, errors }` summary. Warnings flow through `Cairn-Log` when present, falling back to chat. Pure best-effort: warnings don't block registration.

  - **`Core/Animation.lua` extended** — off-screen pause parity now covers AnimationGroup-backed records as well as OnUpdate records. Each animgroup record tracks `_lastOffScreen`; on viewport state change the engine calls `group:Pause()` / `group:Resume()` instead of just skipping the frame. Closes the gap between the OnUpdate path (Day 15G/H) and the animgroup path (Day 15I/J).

  - **Translation / Rotation animgroup routing** — `PROPERTY_ADAPTERS` gains `translateX`, `translateY`, and `rotation` entries with `backend = "animgroup"`. Each adapter installs the appropriate `Translation` or `Rotation` child anim with `setupAnim` closures that set offset/degrees from the target value. Best-effort surface; flagged in code as needing real-consumer validation of the wrapper-level API.

  - **`Cairn-Gui-Layouts-Extra-2.0` (new bundle)** — optional companion to the built-in six strategies. Distinct LibStub MAJOR; consumers depend on it only when they want the extras. RequiresCore(>=17). Two strategies shipped:

    - **`Hex`** — axial-coordinate hexagonal grid. Configurable orientation (`pointy` default, `flat` option), `size` (hex radius), `gap`, and `padding`. Children flow in row-then-column axial order. Use cases: hex-based pickers, grid-style icon arrangements with hex aesthetics.

    - **`Polar`** — radial arrangement around a center point. Configurable `radius`, `startAngle`, `endAngle`, and `direction` (`cw` / `ccw`). Children evenly distributed across the angular sweep; rotated about their own anchor optionally. Use cases: radial menus, dial-style pickers, ring-of-icons HUDs.

  - **Default theme atlas tokens** — `Cairn-Gui-Theme-Default-2.0` adds `texture.icon.x`, `.warning`, `.gear`, `.search`, and `.atlas.glow.soft` token paths. Document headers note the 2x asset path for theme bundles that ship retina-class textures.

### Notes

- **L10n resolution is widget-aware where available.** `Base:_resolveText` is a no-op for plain strings (no `@` prefix), so widgets that pass arbitrary user content through it pay zero cost when locale isn't in use.
- **Contracts surface is gentle.** Designed to be run by Forge/dev tooling, not at addon load. Warnings are advisory; errors don't prevent the widget/layout/theme from registering.
- **In-game test:** `Forge/.dev/tests/cairn_gui_2_round_out.lua` exercises L10n resolve path, Contracts:RunContracts return shape, Layouts-Extra Hex/Polar registration presence, animgroup off-screen pause structure (`_lastOffScreen` field present after first tick), and Translation/Rotation adapter presence in `PROPERTY_ADAPTERS`.

## [10] — Cairn-Gui-2.0 Core MINOR=17: Decision 8 secure widget support (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=17** — full Decision 8 secure-widget surface. Combat queue, taint isolation, pre-warmed pool, layout combat-skip, and a new bundle (`Cairn-Gui-Widgets-Secure-2.0`) with three secure widget types. Action-bar style consumers can now use Cairn-Gui-2.0 for their primary clickable surfaces.

  - **`Core/CombatQueue.lua` (new)** — `lib.Combat:Queue(target, method, ...)` runs immediately when not in combat, queues for FIFO drain on combat exit otherwise. `:QueueClosure(fn)` for multi-call deferred work. `:Stats()` returns queue depth + counters. Listens for `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` to track combat state. `:SetFakeCombat(bool)` lets Forge / tests simulate combat without an actual fight; the queue treats fake combat exactly like real combat. `:OnCombatExit(fn)` subscriber pattern for code that needs to run after the queue drains.

  - **Taint isolation at registration** — `RegisterWidget` recognizes `def.secure = true` and runs a bytecode-pattern check on every method in the mixin, flagging references to forbidden APIs (`EnableAddOn`, `DisableAddOn`, `LoadAddOn`, `RunScript`, `hooksecurefunc`). Errors at registration time, not at runtime, so the failure is loud and attached to the offending mixin name.

  - **Pre-warmed pool** — at `PLAYER_LOGIN` + 0.5s, every secure widget type registers 8 instances into its pool via Acquire-then-Release. Mid-combat `Acquire` calls then come from the pool without a `CreateFrame`, which is what taints during combat for secure frame types. Configurable per-type via `def.prewarm` (default 8 for secure, 0 for non-secure).

  - **`cairn._secure` flag** — set at Acquire time from `def.secure`. Marks instances so Layout strategies and other code can recognize them.

  - **Layout combat-skip** — new `lib:_isLayoutable(child)` helper that returns false for `_secure` children when `lib.Combat:InCombat()` (real or fake). All 6 strategies (Manual, Fill, Stack, Grid, Form, Flex) updated to use it. On combat exit, Layout walks the Inspector tracked set and re-invalidates any container with secure children so they're re-included once it's safe to position them.

  - **`Cairn-Gui-Widgets-Secure-2.0` bundle (new)** — sibling to the Standard bundle. Distinct LibStub MAJOR so consumers depend on whichever (or both) they need. Requires Core MINOR >= 17. Three widgets shipped:

    - **`ActionButton`** — full surface for `SecureActionButtonTemplate`. Typed wrappers `SetSpell` / `SetItem` / `SetMacro` / `SetMacroText` / `SetType` / `SetUnit` route through the combat queue. Cooldown overlay frame and charge-count FontString exposed for consumer wiring. Bridges Blizzard's `PreClick` / `PostClick` to Cairn semantic events.

    - **`MacroButton`** — focused subset for executing macros. Typed wrappers `SetMacro` / `SetMacroText`. Visible label via `SetText` (UI-only, not queued). Smaller surface than ActionButton when consumers don't need the full spell/item/unit space.

    - **`UnitButton`** — `SecureUnitButtonTemplate`-backed. `SetUnit` plus `SetClickAction(button, action, modifier?)` which maps to the standard `type1` / `shift-type1` / etc. attribute scheme. Default click bindings (LeftButton -> target, RightButton -> menu, MiddleButton -> focus) wired on first Acquire.

  - **Forge fake-combat toolbar button** — Forge_CairnInspect's toolbar gains a `Fake Combat: ON/off` toggle that calls `Core.Combat:SetFakeCombat(...)`. Live-syncs with the combat state on every UI refresh.

### Notes

- **Stats counters bumped:** `combat.queued`, `combat.drained`, `combat.lockdownFailures` (the last fires when a lockdown subscription reports a failure; the queue itself never reports failures because Queue always succeeds — either by running immediately or by appending).
- **In-game test:** `Forge/.dev/tests/cairn_gui_2_decision_8_secure.lua` exercises the queue (immediate path, deferred path, drain-on-exit), taint guard (registering with a forbidden-API mixin should error), Acquire path (secure widgets carry `_secure = true`), layout combat-skip (secure child skipped during fake combat), and pre-warm pool presence.
- **Combat Behavior contract**: each new widget mixin documents which methods queue during combat and which are immediate (the file headers list them). Following ARCHITECTURE.md Decision 8's "each secure widget mixin documents a Combat Behavior section" requirement.

## [9] — Cairn-Gui-2.0 Core MINOR=16: Divider / Glow / Mask primitives (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=16** — three new drawing primitives under `Core/Primitives.lua`, completing the v1 set of six (Rect, Border, Icon, Divider, Glow, Mask) called out in ARCHITECTURE.md Decision 7. State-variant color specs work for Divider and Glow exactly as they do for Rect and Border; Mask is metadata-only.

  - **`DrawDivider(slot, spec, opts)`** — single thin line, horizontal or vertical. Configurable `direction`, `thickness`, `inset`, `align` (TOP/BOTTOM/CENTER for horizontal; LEFT/RIGHT/CENTER for vertical), `offset` (perpendicular distance from `align`), `layer` (default `BORDER`). Color resolves through the theme cascade with optional state variants. Use cases: section separators, header underlines, two-column splitter rules.

  - **`DrawGlow(slot, spec, opts)`** — halo around the frame. Implemented as 4 edge textures positioned just OUTSIDE each frame edge with configurable `spread` (default 4px), `layer` (`BACKGROUND` for outer-shadow, `OVERLAY` for outer-outline). Color spec accepts state variants so a glow can fade in on hover. This is a "halo box" — solid edge rectangles, not a soft alpha gradient. Themes that want a soft glow should override the primitive in their widget bundle with a custom rounded-glow texture.

  - **`DrawMask(slot, spec, opts)`** — registers a `MaskTexture` under a slot name. The mask itself doesn't draw anything; it's metadata. Its shape comes from `spec` (atlas key first via `C_Texture.GetAtlasInfo`, file path fallback). Other texture-bearing primitives in the same widget reference the mask via `opts.mask = "<slot>"` to have their texture clipped to the mask's shape. Standard atlas masks: `common-icon-circular` for circular portraits.

- **`DrawRect` and `DrawIcon` accept `opts.mask`** — set to a previously-registered DrawMask slot name to clip the resulting texture to the mask. Calls `Texture:AddMaskTexture(maskTex)`. Tolerant of older clients that don't expose `AddMaskTexture` (no-op in that case). Unknown mask slot names are silently skipped (no error, no mask).

- **Stats counters**: `primitives.divider.draws`, `primitives.glow.draws`, `primitives.mask.draws` track DrawDivider / DrawGlow / DrawMask call counts. Bumped at the entry of each new method, gated on `lib.Stats` like the existing primitive counters.

### Notes

- **In-game test:** `Forge/.dev/tests/cairn_gui_2_primitives_divider_glow_mask.lua` exercises the new primitives sync-only. Spot-checks: kind/texture-count for each, thickness/spread applied correctly, mask integration doesn't error on Icon or Rect, unknown mask ref is silently skipped, stats counters reachable.
- **Mask shape support is whatever atlases / texture files Blizzard exposes.** Common atlas names like `common-icon-circular` work out of the box; consumers can also pass arbitrary file paths.

## [8] — Cairn-Gui-2.0 Core MINOR=15: Grid / Form / Flex layouts (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=15** — three new built-in layout strategies under `Core/Layouts/`, completing the v1 set of six (Manual, Fill, Stack, Grid, Form, Flex) called out in ARCHITECTURE.md Decision 4. All three follow the existing `lib:RegisterLayout(name, fn)` contract; consumers register custom strategies the same way.

  - **`Grid`** — N-column flow. Children fill rows left-to-right and wrap to the next row at `columns`. Cell width is computed from the container width (default) or set explicitly via `opts.cellWidth`. Row height is per-row max-intrinsic (default) or explicit via `opts.cellHeight`. Independent `rowGap` and `colGap`. Use cases: icon grids, uniform card layouts, two-column toggle panels.

  - **`Form`** — Pair-iteration label/field layout. Children consumed in pairs (label, field, label, field, ...); odd-out child becomes a full-width row. Label column auto-fits to widest label intrinsic (override via `opts.labelWidth`); field column fills remaining width minus padding. Per-row height is max of label + field intrinsics. Standard pattern for settings panels and config dialogs.

  - **`Flex`** — CSS-flexbox-inspired. Configurable `direction` (row / column), `justify` (start / end / center / between / around / evenly), `align` (start / end / center / stretch), `gap`, `padding`. Per-child `_flexGrow` distributes leftover free space along the main axis proportionally; `_flexBasis` overrides the initial main-axis size. Single-line only in v1 (no wrap; that's what Grid is for). No flex-shrink and no order property in v1 — both deferred until a real consumer needs them.

### Notes

- **In-game test:** `Forge/.dev/tests/cairn_gui_2_layouts_grid_form_flex.lua` exercises all three with positional spot-checks (Grid 6-cell positions, Form pair offsets, Flex justify-between distribution, Flex grow distribution, Flex column with center align). Sync-only; no timer dependence.
- **Layout strategies are data**: existing widgets / consumers don't need code changes to use the new strategies. Just `container.Cairn:SetLayout("Grid", { columns = 3 })` and the same `RelayoutNow` / dirty-pump path that already drives Manual/Fill/Stack handles them.
- **Cairn-Gui-Layouts-Extra-2.0** (Hex, Polar — per the ARCHITECTURE doc directory layout) is still deferred; those are optional bundles, not part of the v1 core six.

## [7] — Cairn-Gui-2.0 Core MINOR=14: Decision 10B introspection (2026-05-07)

### Added

- **Cairn-Gui-2.0 Core MINOR=14: Decision 10B (Inspector / Stats / EventLog / Dev)** — full read-only introspection surface for the widget library. Forge or any consumer can now enumerate every live widget, inspect per-widget state, count internal events, tail the event log, and toggle a built-in frame-outline overlay. The library exposes the data; the visualization is the consumer's job.

  - **`Cairn.Inspector`** — weak-keyed registry of every widget the library has ever Acquired (released widgets are GC'd naturally). Exposes `Walk(rootCairn, fn)` for depth-first traversal of a subtree, `WalkAll(fn)` for every tree the inspector knows about (no global registry; iterates roots), `Find(x, y)` for hit-testing in screen coordinates with strata + level z-ordering, and `SelectByName(name)` for "first widget of type X." Per-widget `widget.Cairn:Dump()` is mixed into Base; returns a flat table summarizing type, parent, child count, shown state, frame strata/level, rect, intrinsic size, and presence of callbacks/layout.
  - **`Cairn.Stats`** — counters bumped from instrumentation points in Animation (added/completed), Layout (recomputes), Primitives (rect/border/icon draws), and Events (dispatches). `Snapshot()` returns a frozen nested table with sections for animations, layout, primitives, events, pool occupancy per widget type, and event-log buffer state. Custom `Inc(key, delta)` / `Get(key)` for ad-hoc consumer counters.
  - **`Cairn.EventLog`** — fixed-capacity ring buffer (default 200 entries) of every Fire dispatched through Events. Off by default; turns on under `lib.Dev` or via explicit `Enable()`. Stores `{t, widgetType, event, argCount}` per entry — deliberately NOT trailing args, since capturing them risks pinning huge tables for the buffer's lifetime. `Tail(n)` returns the newest n entries oldest-first; `SetCapacity(n)` resizes preserving the latest entries; `Clear()` drops everything.
  - **`Cairn.DevAPI`** — canonical setter for the `lib.Dev` flag. `SetEnabled(bool)`, `Toggle()`, `IsEnabled()`, `OnChange(fn)` (subscribe; returns unsubscribe closure). When enabled, every tracked widget gets a 1px tan outline + a small type-name FontString in its TOPLEFT corner. EventLog is auto-enabled (but not auto-disabled — recordings are intentionally durable for post-mortem inspection). Re-toggling is cheap: overlay frames are hidden, not destroyed.

- **Acquire instrumentation**: every `lib:Acquire` call now registers the new widget in the Inspector via `_track`. Tolerant of Inspector not being loaded.

### Changed

- **Cairn-Gui-2.0 Core: instrumentation hooks installed in 5 files**.
  - `Animation.lua` — `addAnim` bumps `animations.added`; both completion paths (OnUpdate and AnimationGroup OnFinished) bump `animations.completed`.
  - `Layout.lua` — `processDirty`'s post-`RelayoutNow` bumps `layout.recomputes`.
  - `Primitives.lua` — `DrawRect` / `DrawBorder` / `DrawIcon` each bump their respective counter at function entry.
  - `Events.lua` — `Base:Fire` bumps `event_dispatches` and pushes into the EventLog (when enabled) before dispatch.
  - `Acquire.lua` — `lib:Acquire` calls `Inspector:_track(cairn)` after parent registration.
  All call sites are gated on `if lib.Stats then ...` / `if lib.EventLog then ...` / `if lib.Inspector then ...` so the cost is zero when the introspection siblings aren't loaded.

### Notes

- **In-game test:** `Forge/.dev/tests/cairn_gui_2_decision_10b.lua` exercises all four surfaces sync-only. Run after /reload through Forge Console.
- **Forge consumer**: a Forge tab that visualizes the Inspector tree, displays Stats live, and tails the EventLog is the natural follow-up bucket. The APIs are stable as of MINOR 14 and intended to support that consumer.

## [6] — Cairn-Gui Standard bundle MINOR=2: ScrollFrame, EditBox, Slider, Dropdown, TabGroup (2026-05-07)

### Added

- **Cairn-Gui-Widgets-Standard-2.0 MINOR=2** — five new widgets, doubling
  the Standard bundle from 5 to 10. The new set covers the rest of the
  v0.2 form/UX surface: scrolling, text input, numeric input, selection,
  and tabbed navigation.

  - **`ScrollFrame`** — vertical scrollable container. Mouse wheel,
    drag-thumb scrollbar, programmatic `SetVerticalScroll` /
    `ScrollToTop` / `ScrollToBottom` / `SetContentHeight`. Scroll event
    fires per change. Foundational: Dropdown's popup uses it, big lists
    use it, `Forge_Logs`-style scrollers use it. `pool = false`.
  - **`EditBox`** — text input. Single-line and multi-line modes,
    placeholder text, focus-ring border swap (`color.border.focus` while
    focused), numeric / password / maxLetters opts. `TextChanged`,
    `EnterPressed`, `EscapePressed`, `FocusGained`, `FocusLost`. Pooled.
  - **`Slider`** — numeric range input. Horizontal-only in v1.
    Draggable thumb, inline value readout, step / continuous, programmatic
    `SetValue` clamps. `Changed`, `DragStart`, `DragStop`. Pooled.
  - **`Dropdown`** — single-select. Header is a clickable Button;
    popup is parented to UIParent (DIALOG strata) and uses the new
    ScrollFrame internally when option count exceeds `maxVisibleRows`.
    Outside-click close via `GLOBAL_MOUSE_DOWN` through Cairn.Events;
    ESC closes via `OnKeyDown` propagation. `Changed`, `Opened`,
    `Closed`. `pool = false`.
  - **`TabGroup`** — horizontal tab strip + per-tab Container content
    panes. Active tab uses default-variant Button; inactive tabs use
    ghost variant. Per-tab content frame fetched via
    `m:GetTabContent(id)`. `Changed` event on switch. `pool = false`.

- **All five widgets are theme-aware** through the existing token
  cascade. No new theme tokens introduced; `Cairn.Default` covers
  everything. A Cairn.Default follow-up MINOR can add scrollbar-specific
  tokens (track / thumb / thumb.hover / thumb.pressed) if the reuse of
  `color.bg.surface` and `color.border.*` proves visually limiting.

### Changed

- **`Cairn.toc` (and 4 flavor TOCs)** — load the 5 new widget files
  after `Checkbox.lua` in the Standard bundle block. Order chosen so
  ScrollFrame loads before Dropdown (Dropdown's popup uses ScrollFrame
  internally).

- **`Cairn-Gui-2.0.lua` header status line** — was "SCAFFOLD ONLY,
  Day 1," held over from the day-1 commit. Updated to reflect Core
  MINOR 13 (Day 16) with a one-line summary of what's actually shipped.

### Notes

- **In-game test:** `Forge/.dev/tests/cairn_gui_2_widgets_5pack.lua`
  exercises Acquire / Release / public methods / events for all five
  widgets synchronously.

## [5] — Cairn-FSM-1.0 (2026-05-06)

New v0.2 sibling library: `Cairn-FSM-1.0`. Flat finite state machine
with named states, transition graph, per-state entry/exit hooks,
optional guards and actions, and async transitions backed by sibling
Cairn libs.

Designed as a sibling to `Cairn.Sequencer`, not a replacement. Where
Sequencer drives an ordered list of actions ("do these in order, advance
when each one returns truthy"), FSM models a named-state graph with
named transitions ("I'm in some state, named events change which state
I'm in, entering and exiting runs hooks"). They compose — an FSM
transition with `actions = {...}` runs that step list through Sequencer
internally.

### Added

- **`Cairn-FSM-1.0`** — flat finite state machine library at LibStub
  MAJOR `Cairn-FSM-1.0`, MINOR=1. Folder: `CairnFSM/`. Auto-resolves
  at `Cairn.FSM` via the umbrella facade.

  Public API:

  ```lua
  local spec = Cairn.FSM.New({
      initial = "idle",
      context = { retries = 0 },
      states = {
          idle = {
              on = {
                  START = "running",                            -- bare target
                  BOOM  = { target = "error", action = fn },    -- side-effect
                  BAD   = { target = "error", guard  = fn },    -- predicate
                  GO    = { target = "ready", delay  = 1.5 },   -- async: timer
                  DRAIN = { target = "idle",  wait   = pred,
                            timeout = 10, onTimeout = "error" },-- async: poll
                  DEPLOY= { target = "deployed",
                            actions = { fn1, fn2, fn3 } },      -- async: steps
              },
              onEnter = function(m, payload) ... end,
              onExit  = function(m, payload) ... end,
          },
          running = {
              events = {                                        -- WoW events
                  PLAYER_REGEN_DISABLED = "FAIL",
                  PLAYER_DEAD = function(m, ...) m:Send("FAIL") end,
              },
              on = { STOP = "idle", FAIL = "error" },
          },
          error    = { onEnter = function(m, payload) ... end },
          ready    = { on = { GO = "running" } },
          deployed = {},
      },
  })

  local m = spec:Instantiate()
  m:Send("START")           -- transition by name
  m:State()                 -- current state ("running"; FROM during async)
  m:Pending()               -- async descriptor or nil
  m:Cancel()                -- abort pending async
  m:Reset()                 -- back to spec.initial
  m:Destroy()               -- unhook events, cancel timers

  m:On("Transition", function(_, mm, from, to, evt) ... end)
  m:On("Enter:running", function(_, mm) ... end)
  ```

- **Three async transition kinds**:
  - `delay = N` — Cairn.Timer schedules the commit after N seconds.
  - `wait = pred` — Cairn.Timer ticker polls `pred(m)` each
    `pollInterval` (default 0.1s) and commits when truthy. Optional
    `timeout` + `onTimeout` reroute to a different state if the
    predicate never resolves.
  - `actions = {fn1, ...}` — runs the list as a Cairn.Sequencer
    internally and commits when the sequencer finishes.

- **Per-state `events = {...}` map** auto-registers Cairn.Events
  listeners on entry and unregisters on exit. Mappings can be a
  transition name (string) or a custom handler function.

- **Configurable Send-during-pending** via `sendDuringPending` on the
  spec: `"drop"` (default), `"queue"`, or `"override"` (cancel the
  pending transition first). Re-entrant `Send` calls from inside an
  `onEnter` / action / callback are always queued.

- **Owner-tagged cleanup.** The machine acts as the Cairn-Timer /
  Cairn-Events `owner`, so `Destroy` is a single `CancelAll` +
  `UnsubscribeAll` defense-in-depth pass.

- **Soft-required deps.** Cairn-Timer / Sequencer / Callback / Log are
  resolved lazily; missing deps degrade gracefully (e.g., `actions`
  runs each fn once inline if Sequencer is absent).

- **Errors in user functions** (guards, actions, onEnter, onExit, event
  handlers, callbacks) are pcall-trapped and routed to
  `geterrorhandler()`. A bad consumer can't kill the machine.

### Changed

- **`Cairn.toc` v0.2 block** — added `CairnFSM\Cairn-FSM-1.0.lua` line
  after `CairnSequencer` and `CairnTimer` (FSM's soft dependencies for
  the `actions` and `delay`/`wait` async kinds).

- **`README.md`** — new full module section after `Cairn.Sequencer`
  with the FSM example, async-kinds table, method reference, and
  callback signature documentation. Module also added to the Status
  paragraph, the Roadmap v0.2 list, and the File Layout table.

### Notes

- **Flat now, hierarchical later.** `states[name]` is a table of
  properties, never a leaf. A future MINOR can extend a state value
  to contain its own `{ initial, states }` for nested machines without
  breaking the v1 API surface.
- **In-game test:** `Forge/.dev/tests/cairn_fsm_basic.lua` — 30/30
  PASS at release time. Sync-only (Forge Console snippets don't
  observe deferred `C_Timer.After` callbacks; the commit half is
  exercised by calling `m:_completePending()` directly).

## [4] — Cairn-Gui-2.0 Decision 9 implementation (2026-05-06)

Big release. Bundles **nine animation slices** (Day 15C through 15K)
that take the Cairn-Gui-2.0 animation engine from "transition pre-wire
only" to substantially complete on every architectural item Decision 9
named. Plus a TOC ordering fix that surfaced during the 15K test run.

Headline highlights:

- **Composition primitives** (`Sequence` / `Parallel` / `Stagger`) plus
  **ReduceMotion accessibility flag** and the two missing built-in
  easings (`easeOutBack`, `easeOutBounce`).
- **Spring physics** with velocity carry-over on re-Animate, plus an
  imperative `Tween(prop, to, opts)` shortcut and a defensive
  `MaxConcurrentAnims` cap.
- **OKLCH color interpolation** as an opt-in per-tween path (engine +
  state-machine wire-up), so theme designers can transition between
  hues without the gray-midpoint collapse RGB lerp produces.
- **Off-screen pause** in two layers: viewport-based (15G) and via
  parent-chain `DoesClipChildren` walk (15H), covering both "slid out
  of the visible viewport" and "scrolled past a clipping ancestor".
- **AnimationGroup-backend routing** for Alpha and Scale: mappable
  easings push onto Blizzard's native engine; non-mappable easings
  fall back to OnUpdate.
- **Uniform `delay` field on Animate's def shape** with a single path
  to either backend. Closes the Stagger-vs-animgroup bug (Stagger of
  routed properties used to play simultaneously).
- **TOC ordering fix** for `CairnSettingsPanel` so its file-scope
  `LibStub("Cairn-Gui-1.0", true)` resolves on every flavor TOC.
- **249 fresh assertions across nine new test files**, all green at
  release time. Core MINOR 4 → 13.

### Added

- **Cairn-Gui-2.0 Day 15K: Bug fix + uniform delay support.**
  Closes the known Stagger-vs-animgroup bug from 15I/J. The fix promotes
  `delay` to a documented field on `Animate`'s per-property def shape:
  ```lua
  cairn:Animate({
      alpha = { to = 0.0, dur = 0.3, delay = 0.1 },  -- 100ms start delay
  })
  ```
  - **Bug:** Stagger back-patched `rec.delay` AFTER calling `Animate`.
    For animgroup records, `group:Play()` had already been called by
    then, so `anim:SetStartDelay` was never invoked. Stagger of routed
    properties played all steps simultaneously instead of staggered.
  - **Fix:** `def.delay` flows through `Animate` directly. addAnim's
    animgroup branch reads `rec.delay` and calls `anim:SetStartDelay(d)`
    before `Play()`. The OnUpdate ticker (15C) already honored `rec.delay`
    so its behavior is unchanged. Stagger now sets `copy[prop].delay`
    before calling `Animate` and the back-patch loop is removed entirely.
  - **Side benefit:** `delay` is now part of the documented public def
    shape. Useful for one-shot delayed animations without needing
    `Stagger` (e.g., a tooltip that fades in after a 200ms hover hold).
  - Core MINOR 12 → 13.

- **Cairn-Gui-2.0 Day 15J: AnimationGroup routing for Scale.**
  Mirrors 15I's pattern. `PROPERTY_ADAPTERS.scale` gains
  `backend = "animgroup"`, `animType = "Scale"`, and a defensive
  `setupAnim` that handles three Blizzard API variants: modern
  `SetScaleFrom`/`SetScaleTo`, alternate-naming
  `SetFromScale`/`SetToScale`, and legacy delta-style `SetScale(ratio)`.
  Same routing rules as Alpha — mappable easings + no spring → animgroup,
  otherwise OnUpdate. Translation and Rotation still deferred; they
  lack a Frame get/apply property and need a wrapper layer better
  designed against a real consumer. Core MINOR 11 → 12.

- **Cairn-Gui-2.0 Day 15I: AnimationGroup-backend routing for Alpha.**
  Decision 9's last big architectural item. The `alpha` property adapter
  opts into Blizzard's native AnimationGroup engine when the easing maps
  to one of Blizzard's smoothing names (`NONE`, `IN`, `OUT`, `IN_OUT`).
  - **Routing logic.** `Animate` decides backend per spec. Mappable
    easing on a `backend = "animgroup"` adapter → `fromType = "animgroup"`
    record. Non-mappable easings (`easeOutBack`, `easeOutBounce`, any
    custom-registered easing), springs, and other properties fall back
    to OnUpdate so the rendered curve always matches the easing the
    consumer asked for.
  - **Lifecycle.** `addAnim` creates a per-record AnimationGroup and
    Animation, configures duration / smoothing / from-to via the
    adapter's `setupAnim`, hooks `OnFinished` (which applies the final
    value, removes the record, fires the user `complete`), and calls
    `Play()`. The OnUpdate tick loop skips animgroup records — they
    live in the queue only for replacement and cancellation lookup.
  - **Cancellation.** A new `teardownAnimGroupRecord` helper Stops the
    group and nils the `OnFinished` hook. Used by `CancelAnimations`,
    by the same-key replacement path, and by the concurrency-cap
    eviction path so a Stopped record can't fire its handler late.
  - **API compatibility.** `setupAnim` for Alpha tries the modern
    `SetFromAlpha`/`SetToAlpha` API first, falls back to `SetChange`
    (delta) for older builds. `SetSmoothing` is also called defensively.
  - **Caveats (deferred):** off-screen pause (15G/15H) doesn't apply to
    animgroup records because Blizzard runs them past our gate;
    Stagger's per-record `delay` isn't honored by animgroup records;
    Translation / Scale / Rotation routing not implemented (their
    Blizzard APIs vary by build, so the abstraction deserves a real
    consumer's signal before being designed).
  - Core MINOR 10 → 11.

- **Cairn-Gui-2.0 Day 15H: Clipping-ancestor walk for off-screen pause.**
  Extends 15G. `isOffScreen` now also walks the parent chain from the
  widget upward; for any ancestor where `DoesClipChildren()` returns
  true, the widget's rect is intersected against the ancestor's rect.
  If entirely outside, the widget is paused regardless of its own
  visibility flag. Catches "scrolled outside a clipping ancestor's
  visible area" cases (e.g., a list item in a `ScrollFrame` that has
  been scrolled past the viewport). Defensive: ancestors lacking
  `DoesClipChildren`, or those that are themselves not-yet-positioned,
  are skipped without aborting the walk; the check falls through to
  the next ancestor (and ultimately to the UIParent viewport check).
  Core MINOR 9 → 10.

- **Cairn-Gui-2.0 Day 15G: Viewport-based off-screen pause.**
  `tickAnimations` early-returns when the widget's frame is positioned
  entirely outside UIParent's viewport (right ≤ 0, left ≥ width, top ≤ 0,
  or bottom ≥ height). Animations freeze in time -- dt during off-screen
  is discarded (pause semantics, not catch-up) and ticking resumes from
  the captured state on the next on-screen tick. The Hide cascade still
  covers ancestor-hidden cases via Blizzard's auto-pause; this layer
  adds coverage for the "shown but positioned off-screen" cases (e.g.,
  a slid-out toast still ticking through its dormant state). Viewport-
  only in v1; scrolled-out-of-clipping-ancestor cases (e.g., a list
  item scrolled past a ScrollFrame's viewport) need parent-chain
  clipping awareness and remain deferred. Core MINOR 8 → 9.

- **Cairn-Gui-2.0 Day 15F: OKLCH wired into the Primitives state machine.**
  State-variant specs now read a `colorSpace` sibling key alongside
  `transition` and `ease`. Theme designers opt into OKLCH lerp per variant
  without touching the internal animation API:
  ```lua
  -- In a Button bg variant spec:
  spec = {
      default    = "color.bg.button.default",
      hover      = "color.bg.button.hover",
      transition = "duration.fast",
      ease       = "easeOut",
      colorSpace = "oklch",   -- NEW: opts the hover transition into OKLCH
  }
  ```
  `readTransition` returns `(dur, ease, colorSpace)` (third value new);
  `applyAllForState` propagates `colorSpace` into the options passed to
  `applyRecord`; `applyRecord` builds an `opts = { colorSpace = ... }`
  table only when both `colorSpace` is set AND animation is possible
  (defensive against unnecessary allocation on the common no-OKLCH path),
  forwarding to `_animatePrimitiveColor` as the 5th argument. Default
  RGB lerp behavior for variants without `colorSpace` is unchanged.
  Core MINOR 7 → 8.

- **Cairn-Gui-2.0 Day 15E: OKLCH color interpolation.**
  - **`lib:RgbToOklch(r, g, b, a) -> L, C, h, a`** and **`lib:OklchToRgb(L, C, h, a) -> r, g, b, a`** public color-space conversions. r/g/b are sRGB in [0, 1]; L/C are in OKLab's typical UI range; h is in [0, 360) degrees. Pure functions; safe to call any time after Animation.lua loads.
  - **`_animatePrimitiveColor` gains an `opts` parameter.** Pass `opts = { colorSpace = "oklch" }` to opt in to OKLCH interpolation per call. Endpoints are pre-converted once at addAnim; each tick lerps L and C linearly, lerps hue along the shortest arc on [0, 360), and converts back to sRGB for the apply. Default behavior (RGB lerp) is unchanged.
  - **Why it matters.** RGB lerp between complementary hues (yellow ↔ blue, green ↔ magenta) passes through near-gray at the midpoint because all three RGB channels collapse to ~0.5. OKLCH stays in a vivid arc through the whole transition.
  - Gray endpoints (chroma ≈ 0) inherit the other endpoint's hue so we don't lerp toward an arbitrary undefined value.
  - Core MINOR 6 → 7.

- **Cairn-Gui-2.0 Day 15D: Animation physics + ergonomics.**
  - **Spring physics.** Animate's per-property def now accepts a
    `spring = { stiffness, damping, mass }` table; when present, the
    record uses semi-implicit Euler integration instead of
    duration + easing. Settles via `lib.SpringSettleThreshold` (default
    0.001). In-flight velocity carries over on re-Animate so a hover-
    leave-hover during oscillation continues physically rather than
    snapping velocity to zero. Defaults: stiffness 170, damping 26,
    mass 1 (Framer Motion's "smooth" preset).
  - **`Base:Tween(prop, to, opts)` imperative shortcut** for the common
    single-property case. Equivalent to
    `Animate({ [prop] = mergeInto({ to = to }, opts) })`.
  - **`lib.MaxConcurrentAnims` defensive cap** (default 64). When a
    widget would exceed the cap, the oldest in-flight record is evicted
    silently before appending. Cap is configurable; not intended as a
    routine throttle.
  - ReduceMotion fast-path now snaps spring records to their rest
    position (synchronous apply + complete) just like scalar/rgba.
  - Core MINOR 5 → 6.

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

- **TOC ordering: CairnSettingsPanel loaded before Cairn-Gui-1.0.**
  Pre-existing bug across all five TOCs (Retail + Mists + TBC + Vanilla
  + XPTR). `CairnSettingsPanel/Cairn-SettingsPanel-1.0.lua` does
  `LibStub("Cairn-Gui-1.0", true)` at file scope and `error`s if it
  returns nil; SettingsPanel was sandwiched between the v0.2 modules
  and the Cairn-Gui-1.0 family in every TOC, so its file scope ran
  before Gui-1.0 had registered with LibStub. Fix: moved
  `CairnSettingsPanel\Cairn-SettingsPanel-1.0.lua` to AFTER the full
  Cairn-Gui-1.0 family in each TOC, with a comment documenting the
  dependency. Surfaced during the 15K test run; the error fired twice
  on `/reload` but didn't block the test from completing.

- **Animation ticker: records appended during the tick** (e.g., by a
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
