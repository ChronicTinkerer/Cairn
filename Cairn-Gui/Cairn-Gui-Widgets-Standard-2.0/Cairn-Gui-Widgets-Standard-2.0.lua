--[[
Cairn-Gui-Widgets-Standard-2.0

Standard widget bundle for Cairn-Gui-2.0 per Decision 11. This file is
the bundle's LibStub anchor; sibling Widgets/*.lua files register the
actual widget types against Core (Cairn-Gui-2.0).

The bundle's MAJOR matches the Core MAJOR it targets (2.0), to avoid the
trap that earlier MAJOR=1.0 created where the bundle's name didn't
reflect what it actually depended on.

Distinct LibStub MAJOR from Core so consumers can:
	- Depend on just Core (Cairn-Gui-2.0) and ship their own widgets.
	- Depend on Core + Standard for the bundled widget set.
	- Replace Standard with an alternative bundle (e.g.,
	  Cairn-Gui-Widgets-Cyberpunk-2.0) that registers a different
	  visual language under the same widget type names.

Load order in Cairn.toc:
	1. Cairn-Gui-2.0 Core files (LibStub anchor + Mixins + Core APIs)
	2. This file (Cairn-Gui-Widgets-Standard-2.0.lua)  <-- you are here
	3. Each Widgets/*.lua, in any order

Widget files use LibStub("Cairn-Gui-2.0") to get Core, then call
Core:RegisterWidget(name, def) to register themselves.

Status: Day 16. Standard widget set goes from 5 to 10:
ScrollFrame, EditBox, Slider, Dropdown, TabGroup added on top of the
existing Container, Button, Label, Window, Checkbox.

History under previous MAJOR (Cairn-Gui-Widgets-Standard-1.0):
	1: Days 8-13 (Button, Label, Container, Window).
	2: Day 14: Checkbox (uses Core MINOR 2's DrawIcon).
	3: Day 15B: Button variants gain `transition = "duration.fast"` so
	   hover / press / disabled animate via the new Animation engine.

Cairn-Gui-Widgets-Standard-2.0 MINOR bumps:
	1: MAJOR rename only. No API changes from 1.0/MINOR=3. Fresh start
	   to align bundle MAJOR with the Core MAJOR it targets.
	2: Day 16: ScrollFrame, EditBox, Slider, Dropdown, TabGroup. Five
	   new widgets in one batch. ScrollFrame is foundational (Dropdown
	   uses it for the popup; consumers wrap multi-line EditBox in it).
	   EditBox supports single + multi-line, focus ring via border
	   re-paint, placeholder. Slider is horizontal-only, draggable thumb,
	   inline value readout. Dropdown owns a UIParent-strata popup with
	   GLOBAL_MOUSE_DOWN-driven outside-click close. TabGroup is a
	   horizontal tab strip + per-tab Container content panes. All five
	   theme-aware via the existing token cascade; no new tokens
	   introduced.
	3: Companion to Core MINOR 19. Three behavior changes:
	   * Button / Label / Checkbox / EditBox / Dropdown setters call
	     Base:_invalidateParentLayout() so SetText / SetVariant /
	     SetPlaceholder / SetSelected / SetOptions trigger a parent
	     relayout. Stack horizontal in particular silently kept old
	     widths after SetText; this fixes the "longer label bleeds
	     into next sibling" footgun.
	   * ScrollFrame hooks OnSizeChanged on the outer frame and
	     re-sizes the scroll-child Container's width to the new
	     viewport (minus scrollbar reserve), so SetPoint-driven
	     resize after Acquire propagates correctly.
	   * Window default strata DIALOG -> HIGH so DIALOG-strata
	     popups (Dropdown option lists, child windows) layer above
	     host windows reliably. Pass strata = "DIALOG" explicitly
	     when a Window IS itself a popup.
	4: Button.OnAcquire calls frame:RegisterForClicks("AnyUp"). The
	   Primitives layer's OnMouseDown / OnMouseUp HookScripts swallow
	   OnClick on Interface 120005 unless the Button is registered
	   for the click type explicitly. Without this, btn.Cairn:On("Click", fn)
	   silently never fires -- consumers had to add per-button
	   :RegisterForClicks workarounds (Vellum/Panel.lua, Cairn-Media-Browser
	   visibility filter). "AnyUp" covers left/right/middle so consumers
	   can dispatch on the `button` arg passed to the Click handler.
	5: Two Window improvements identified during the Vellum/Panel.lua
	   build (memory: cairn_gui_2_vellum_framework_gaps).
	   * Window.OnAcquire defaults to SetPoint("CENTER", UIParent, "CENTER")
	     when the consumer hasn't anchored the frame. Was: invisible
	     (rendered at (0,0) of UIParent which is the bottom-left corner).
	     Vellum's per-build SetPoint workaround can be removed.
	   * Window fires "Moved" event after OnDragStop with args
	     (x, y, point, relTo, relPoint). Lets consumers persist drag
	     position via widget.Cairn:On("Moved", function(_, x, y) ... end).
	     Was: drag worked visually but no callback, so no way to round-trip
	     position to saved variables without monkey-patching the title bar.
	6: Window OnDragStop now NORMALIZES the post-drag anchor back to
	   CENTER-relative coords before firing "Moved". WoW's StartMoving /
	   StopMovingOrSizing typically rewrites the frame's anchor to a
	   BOTTOMLEFT-relative spec (often "BOTTOMLEFT, UIParent, BOTTOMLEFT,
	   x, y"). MINOR=5 fired Moved with those raw GetPoint(1) coords, so
	   consumers that persisted (x, y) and restored via SetPoint("CENTER",
	   UIParent, "CENTER", x, y) saw the window jump on /reload (anchor
	   types mismatched). MINOR=6 computes the frame's center vs UIParent
	   center (scale-corrected), ClearAllPoints, re-anchors to CENTER, and
	   THEN fires "Moved (dx, dy, 'CENTER', 'UIParent', 'CENTER')". The
	   contract for consumers becomes: "(x, y) is the offset from UIParent
	   center". Vellum's `db.profile.panel.x/y` round-trips without changes.
	12: Checkbox.OnAcquire now calls frame:RegisterForClicks("AnyUp"),
	   matching the Button MINOR=4 fix. Without this, the Primitives
	   layer's OnMouseDown / OnMouseUp HookScripts swallow OnClick on
	   Interface 120005, and clicking a Checkbox never toggles its
	   state. Symptom: hover bg tinting the box made it look like the
	   check appeared on mouseover, but Toggled never fired and the
	   consumer's checked state was never updated. Hit on Forge_AddonManager
	   row checkboxes 2026-05-13.
	13: TabGroup wraps to multiple rows when tabs overflow the strip
	   width. Previously the tabs extended past the right edge of the
	   TabGroup frame (visible on Forge with 18 tabs at default window
	   width). relayoutTabs now tracks current x, wraps to a new row
	   when the next button won't fit, and grows the strip height to
	   fit all rows. Content panes re-anchor to the new strip bottom.
	   A HookScript("OnSizeChanged") re-runs relayout when the
	   container resizes, so widening the window repacks tabs into
	   fewer rows live. Hit on Forge after adding Profiler + Events
	   tabs 2026-05-13.
	14: TreeView widget. Generic expand/collapse hierarchical list.
	   Consumer provides a tree of nodes ({ id, label, aux, children });
	   the widget renders one row per visible node with indicator + depth
	   indent. Collapsed branches contribute one row regardless of how
	   many descendants they have, so the widget naturally handles large
	   data sets (Forge_APIBrowser has ~3000+ entries) that overwhelm a
	   flat list. Single-click toggles expansion on branches; the
	   "Click" event fires on every click with the original node, so
	   consumers can still do click-to-select. Frame height auto-grows
	   to fit visible rows; wrap in a ScrollFrame for tall trees.
	15: TreeView honors a `node.expandable` flag so consumers can mark
	   a branch expandable without pre-building children. The consumer
	   populates children on the "Toggle" event and calls Refresh, so
	   walking large trees becomes pay-as-you-go instead of eager. Hit
	   on Forge_Tables: eagerly walking _G at MAX_BUILD_DEPTH 2 did
	   500k+ ops and froze the client. Lazy expansion via this flag
	   keeps the initial build to just root keys.
]]

local MAJOR, MINOR = "Cairn-Gui-Widgets-Standard-2.0", 15
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Core = LibStub("Cairn-Gui-2.0", true)
if not Core then
	error("Cairn-Gui-Widgets-Standard-2.0 requires Cairn-Gui-2.0; check Cairn.toc load order")
end

-- Verify Core is at a compatible revision. RequireCore returns false on
-- mismatch and routes a chat error through Cairn-Log; we abort the
-- bundle's registration in that case so misaligned versions don't ship
-- partial widget sets. Bump the minimum here when a widget starts using
-- a Core API added in a later MINOR.
--   Day 14 (MINOR 2): DrawIcon
--   Day 15B (MINOR 3): Animate / transition pre-wire
if not Core:RequireCore("Cairn-Gui-2.0", 3) then
	return
end

lib._core = Core

-- Sibling Widgets/*.lua files reach into this lib for shared helpers
-- when they need them. Day 8 has nothing shared yet; placeholder.
lib._helpers = lib._helpers or {}
