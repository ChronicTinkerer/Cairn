--[[
Cairn-Gui-2.0

Core entry point for Cairn-Gui-2.0, the parallel-v2 widget library
intended to replace Cairn-Gui-1.0 (Diesal-derived) over time. This
file is the LibStub registration anchor only. All real implementation
lives in sibling files (Core/, Mixins/, LocaleOverlay/) loaded after
this one by Cairn.toc.

Status: SCAFFOLD ONLY. Day 1 of implementation. The library is a
contract surface plus the empty registries the contract will populate.
No widgets, no layouts, no themes, no animations are defined yet.

Architecture: see Cairn-Gui-2.0/ARCHITECTURE.md (LOCAL-ONLY per the
Cairn gitignore policy; not in the public repo). Eleven decisions
locked 2026-05-05. Guiding principle: maximum flexibility for
community widget and theme authors via public registries.

Coexists with: Cairn-Gui-1.0 (different LibStub MAJOR). Both libs
load. Consumers pick which one to depend on.

Verification (Day 1 success criterion):
	/dump LibStub("Cairn-Gui-1.0")  -- returns a table (existing v1)
	/dump LibStub("Cairn-Gui-2.0")  -- returns a table (this file)
]]

-- MINOR bumps:
--   1: Days 1-13 build (registries, Acquire, theme cascade, Rect/Border
--      primitives + state machine, Events, Layout, three layout strategies,
--      Standard widget bundle pilot).
--   2: Day 14: DrawIcon primitive (atlas-first, file-path fallback, sized
--      anchor + tint) and SetPrimitiveShown helper. State variants on
--      icons supported. Texture pool stays per-record-update like Rect.
--   3: Day 15B: Animation engine. Public RegisterEasing + lib.easings
--      registry (linear, easeIn, easeOut, easeInOut), per-widget
--      Animate / CancelAnimations API, internal _animatePrimitiveColor
--      used by the Primitives state machine to animate state-variant
--      color changes when the spec carries a `transition` token. Per-
--      widget OnUpdate parented to the widget frame so Blizzard auto-
--      pauses ticking on Hide. Auto-cancel on Release via Base:Release
--      wrap.
--   4: Bugfix: Acquire's pool path now resets _visualState / _hovering /
--      _pressing / _disabled before OnAcquire so a Released-while-hovered
--      widget doesn't paint at hover color when recycled.
--   5: Day 15C: Animation composition + accessibility. Adds Base:Sequence,
--      Base:Parallel, Base:Stagger composition primitives (specs match
--      Animate's shape; opts.complete fires once when the whole group
--      finishes). Adds the lib.ReduceMotion accessibility flag (clamps
--      duration AND start-delay to zero, applies target value plus
--      complete handler synchronously, bypasses the queue entirely).
--      Adds easeOutBack and easeOutBounce to the built-in easings (the
--      Penner-standard back-overshoot and piecewise bounce curves).
--      Anim records now support a `delay` field (Stagger sets it; the
--      ticker counts it down before treating dt as elapsed time).
--      Tick loop late-comer guard: records added during a tick (e.g.,
--      Sequence's chain) wait until the next OnUpdate before advancing.
--   6: Day 15D: Animation physics + ergonomics. Adds Spring physics --
--      Animate's def now accepts `spring = { stiffness, damping, mass }`
--      to opt into a physics-driven path (semi-implicit Euler, settles
--      via SpringSettleThreshold). In-flight velocity carries over on
--      re-Animate so a hover-leave-hover during oscillation continues
--      physically. Adds Base:Tween(prop, to, opts) imperative shortcut
--      for the single-property case. Adds lib.MaxConcurrentAnims (64)
--      defensive cap -- new records past the cap evict the oldest
--      silently. ReduceMotion fast-path now snaps springs to rest just
--      like scalar/rgba records do.
--   7: Day 15E: OKLCH color interpolation (opt-in per primitive color
--      anim). lib:RgbToOklch / lib:OklchToRgb public conversions.
--      _animatePrimitiveColor gains an opts param; opts.colorSpace =
--      "oklch" triggers OKLCH lerp (L/C linear, hue shortest-arc).
--      Endpoints pre-converted once at addAnim; per-tick cost is one
--      OKLCH->RGB conversion plus the lerps. Avoids the gray-midpoint
--      collapse that RGB lerp produces between complementary hues.
--   8: Day 15F: OKLCH wired into the Primitives state machine. State-
--      variant specs now read a `colorSpace` sibling key alongside
--      `transition` and `ease`; readTransition returns it as a third
--      value, applyAllForState propagates it into applyRecord, and
--      applyRecord forwards it to _animatePrimitiveColor as opts.
--      Theme designers opt into OKLCH per variant without touching the
--      internal animation API.
--   9: Day 15G: Viewport-based off-screen pause. tickAnimations early-
--      returns when the widget's frame is positioned entirely outside
--      UIParent's viewport. Animations freeze in time (dt during off-
--      screen discarded, not banked) and resume from their captured
--      state on the next on-screen tick. The Hide cascade still covers
--      ancestor-hidden cases via Blizzard auto-pause; this adds the
--      "shown but positioned off-screen" coverage. Viewport-only check
--      in v1; scrolled-out-of-clipping-ancestor (e.g., scroll list)
--      cases need parent-chain awareness, deferred.
--  10: Day 15H: Clipping-ancestor walk extends 15G's off-screen pause.
--      isOffScreen now also walks the parent chain; for any ancestor
--      where DoesClipChildren returns true, intersects the widget rect
--      against the ancestor's rect. If entirely outside, returns true.
--      Catches "scrolled outside a ScrollFrame's child" cases. Defensive
--      against ancestors lacking DoesClipChildren or yet-unpositioned
--      ancestors (skipped, walk continues).
local MAJOR, MINOR = "Cairn-Gui-2.0", 10
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- ----- Soft dependencies ------------------------------------------------
-- Cairn-Gui-2.0 is designed to build on these. Pulled lazily via LibStub
-- so loading order in Cairn.toc remains the source of truth.
local Log      = LibStub("Cairn-Log-1.0",      true)
local Locale   = LibStub("Cairn-Locale-1.0",   true)
local Callback = LibStub("Cairn-Callback-1.0", true)

local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.Gui-2") end
	return lib._log
end

-- ----- Public registries (populated by sibling files in later days) ----
-- Keep these as `lib.x = lib.x or {}` so re-loads (LibStub MINOR bump
-- during dev) do not clobber registrations from prior load cycles.
lib.widgets       = lib.widgets       or {}  -- name -> widget definition
lib.layouts       = lib.layouts       or {}  -- name -> layout strategy
lib.themes        = lib.themes        or {}  -- name -> theme object
lib.easings       = lib.easings       or {}  -- name -> easing function
lib.localeOverlay = lib.localeOverlay or {}  -- locale -> override table
lib.contracts     = lib.contracts     or {}  -- registration-shape validators

-- Internal: per-widget-type pool of released cairn objects waiting for
-- recycling. Populated by Base:Release when def.pool == true; drained by
-- lib:Acquire on next call for that type. Day 3.
lib._pool         = lib._pool         or {}  -- name -> array of released cairn objects

-- ----- Dev / debug surface ---------------------------------------------
-- The Cairn.Dev flag toggles overlays, warnings, event log, and the
-- verbose error sink (per ARCHITECTURE.md Decision 10B). Default off in
-- production; consumer addons or Forge flip it on for development.
lib.Dev = lib.Dev or false

-- ----- Bookkeeping for the architecture's "RequireCore" contract -------
-- Bundles (Cairn-Gui-Widgets-Standard-2.0, Cairn-Gui-Theme-Default-2.0,
-- etc.) call lib:RequireCore(MAJOR, MINOR) at load and abort with a
-- chat warning if the running Core is too old. Stubbed for Day 1; full
-- implementation lands when bundles ship.
function lib:RequireCore(requiredMajor, minimumMinor)
	if requiredMajor ~= MAJOR then
		if logger() then
			logger():Error("RequireCore mismatch: caller wants %s, this is %s",
				tostring(requiredMajor), MAJOR)
		end
		return false
	end
	if type(minimumMinor) == "number" and MINOR < minimumMinor then
		if logger() then
			logger():Error("RequireCore: %s revision %d below required %d",
				MAJOR, MINOR, minimumMinor)
		end
		return false
	end
	return true
end

-- ----- Version introspection -------------------------------------------
function lib:GetVersion() return MAJOR, MINOR end

-- ----- Day 1 load confirmation -----------------------------------------
-- Single Info-level log entry on first successful load. Subsequent
-- LibStub loads (MINOR bumps) skip this via the `if not lib then return`
-- guard above, so the line appears at most once per session.
if logger() then
	local hasLocale   = Locale   and "yes" or "no"
	local hasCallback = Callback and "yes" or "no"
	logger():Info("loaded MINOR=%d (Cairn-Locale=%s, Cairn-Callback=%s)",
		MINOR, hasLocale, hasCallback)
end
