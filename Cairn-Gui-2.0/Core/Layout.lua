--[[
Cairn-Gui-2.0 / Core / Layout

Layout strategy system per Decision 4. Layouts are registered functions
that arrange a container's children. The registry pattern lets the
library, third-party authors, and consumers all add strategies through
the same public API.

Public API on the lib:

	Cairn.Gui:RegisterLayout(name, fn)
		fn signature: function(containerCairn, opts)
		The strategy reads container._children and opts (whatever was
		passed to SetLayout), then assigns positions to each child's
		_frame via SetPoint / SetSize. Children with _layoutManual = true
		are skipped.

	Cairn.Gui:GetLayout(name) -> fn or nil

Public API on widget.Cairn (added to Mixins.Base):

	widget.Cairn:SetLayout(name, opts?)
		Bind a layout strategy to this container with optional opts table.
		Marks the container dirty so the next frame relayouts it.

	widget.Cairn:GetLayout() -> name, opts

	widget.Cairn:RelayoutNow()
		Synchronously run the strategy. Use in tests or tight loops.

	widget.Cairn:_invalidateLayout()  (private)
		Mark this container dirty for next-frame relayout. Called by
		_addChild / _removeChild and SetLayout. Safe to call before any
		strategy is bound (no-op).

	widget.Cairn:SetLayoutManual(bool)
		Opt this widget out of its parent's layout strategy. Useful for
		floating decorations like badges or absolutely-positioned overlays
		inside an otherwise-managed container.

	widget.Cairn:IsLayoutManual() -> bool

Built-in strategies ship in Core/Layouts/:
	Manual   - no-op; children self-anchor.
	Fill     - first child fills the container (with optional padding).
	Stack    - vertical or horizontal stack with gap and padding.

Grid, Form, Flex come in subsequent days. Third parties can register
their own (Hex, Polar, Timeline) without library cooperation.

Lazy recompute: invalidations are coalesced into a dirty set processed
on the next frame via a single shared OnUpdate pump. The pump's OnUpdate
script is attached only when the dirty set is non-empty and detached
when it drains, so an idle UI pays nothing per frame.

Status: Day 9 ships the registry + Manual/Fill/Stack. Grid/Form/Flex
later. No automatic invalidation on parent resize or child intrinsic
size change yet -- those are Day 10+ refinements.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Layout requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- RegisterLayout / GetLayout --------------------------------------

function lib:RegisterLayout(name, fn)
	if type(name) ~= "string" or name == "" then
		error("RegisterLayout: name must be a non-empty string", 2)
	end
	if type(fn) ~= "function" then
		error("RegisterLayout: fn must be a function", 2)
	end
	self.layouts[name] = fn
	return fn
end

function lib:GetLayout(name)
	return self.layouts[name]
end

-- ----- Lazy pump --------------------------------------------------------
-- A single OnUpdate-driven dispatcher processes pending invalidations.
-- The pump's OnUpdate is attached only when dirty has entries; idle UIs
-- pay zero per frame.

local dirty   = {}                                                       -- cairn -> true
local pump                                                                -- created on first need
local pumping = false

local function processDirty()
	-- Snapshot to a list so a relayout that triggers further invalidations
	-- (a child resize within layout) is processed on the NEXT frame, not
	-- recursively in this one.
	local toRun = {}
	for cairn in pairs(dirty) do
		toRun[#toRun + 1] = cairn
	end
	wipe(dirty)
	pumping = false
	if pump then pump:SetScript("OnUpdate", nil) end

	for _, cairn in ipairs(toRun) do
		local frame = cairn._frame
		-- Skip if the widget was Released between invalidation and pump.
		if frame and cairn._layout and cairn._layout ~= "Manual" then
			cairn:RelayoutNow()
			if lib.Stats then lib.Stats:Inc("layout.recomputes") end
		end
	end
end

local function ensurePumpRunning()
	if not pump then
		pump = CreateFrame("Frame")
	end
	if not pumping then
		pumping = true
		pump:SetScript("OnUpdate", processDirty)
	end
end

-- ----- Per-widget API on Mixins.Base -----------------------------------

function Base:SetLayout(name, opts)
	if name ~= nil and name ~= "Manual" and not lib.layouts[name] then
		error(("SetLayout: %q is not a registered layout"):format(tostring(name)), 2)
	end
	self._layout     = name
	self._layoutOpts = opts or {}
	self:_invalidateLayout()
end

function Base:GetLayout()
	return self._layout, self._layoutOpts
end

function Base:RelayoutNow()
	if not self._children then return end
	if not self._layout or self._layout == "Manual" then return end
	local strategy = lib.layouts[self._layout]
	if strategy then
		strategy(self, self._layoutOpts or {})
	end
end

function Base:_invalidateLayout()
	-- Bail if no strategy is bound or the strategy is Manual (no-op).
	if not self._layout or self._layout == "Manual" then return end
	dirty[self] = true
	ensurePumpRunning()
end

function Base:SetLayoutManual(b)
	self._layoutManual = b and true or false
	-- Tell the parent its layout is stale so it can re-skip or re-include us.
	if self._parent and self._parent._invalidateLayout then
		self._parent:_invalidateLayout()
	end
end

function Base:IsLayoutManual()
	return self._layoutManual == true
end
