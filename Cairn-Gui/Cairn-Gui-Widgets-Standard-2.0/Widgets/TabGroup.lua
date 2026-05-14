--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / TabGroup

Tabbed UI container. The widget has a horizontal tab strip at the top
and a content area below. Each tab has its own Container content frame;
clicking a tab hides the others' content and shows the active one.

Public API:

	tg = Cairn.Gui:Acquire("TabGroup", parent, {
		width  = 400,
		height = 300,
		tabs   = {
			{ id = "general",  label = "General"  },
			{ id = "graphics", label = "Graphics" },
			{ id = "audio",    label = "Audio"    },
		},
		selected  = "general",        -- initial active tab id
		tabHeight = 28,
		gap       = 4,                -- gap between tab buttons
	})

	-- Build the content for each tab via the per-tab content getter:
	local pane = tg.Cairn:GetTabContent("general")
	pane.Cairn:SetLayout("Stack", { direction = "vertical", gap = 4, padding = 8 })
	Cairn.Gui:Acquire("Label",  pane, { text = "General settings", variant = "heading" })
	Cairn.Gui:Acquire("Button", pane, { text = "Save", variant = "primary" })

	tg.Cairn:SetSelected("graphics")
	tg.Cairn:GetSelected()
	tg.Cairn:GetTabIds()              -- {"general", "graphics", "audio"}

	tg.Cairn:On("Changed", function(w, tabId, prevId) ... end)

Tab strip layout

	Tabs are laid out left-to-right at the top of the widget. Tab button
	width adapts to the label string (button intrinsic size). The active
	tab uses the default Button variant; inactive tabs use ghost variant.
	When the next tab would overflow the strip width, it wraps to a new
	row below. The strip auto-grows in height to fit all rows, and the
	content pane re-anchors to the new strip bottom. OnSizeChanged on
	the TabGroup frame triggers re-layout so wider/narrower windows
	repack the rows live.

Pool: NOT pooled. TabGroup owns N+1 sub-widgets (N tab buttons + N
content Containers + the tab strip Container); the simplest correct
path is no pool. Released TabGroups cascade-release everything and
hide.

Tokens consumed

	color.bg.surface              (tab strip bg, subtle)
	color.border.default          (separator below tab strip)

	(tab buttons and content frames inherit token usage from Button and
	Container respectively.)

Status

	Day 16. v1: horizontal tab strip, click-to-switch, runtime
	SetSelected, Changed event. No tab close buttons, no drag-to-reorder,
	no contextual icons. Multi-row wrap on overflow added Standard
	MINOR=13.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W         = 400
local DEFAULT_H         = 300
local DEFAULT_TAB_H     = 28
local DEFAULT_GAP       = 4
local STRIP_PAD         = 4
local ROW_GAP           = 2     -- vertical gap between wrapped tab rows

-- ----- TabGroup mixin --------------------------------------------------

local mixin = {}

-- Re-anchor content panes to the strip's current bottom. Called from
-- relayoutTabs after the strip height is finalized so panes always fill
-- the area below the (possibly multi-row) tab strip.
local function reanchorPanes(self, stripH)
	local frame = self._frame
	for _, t in ipairs(self._tabs or {}) do
		if t._content then
			t._content:ClearAllPoints()
			t._content:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, -stripH)
			t._content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  0)
		end
	end
end

-- Lay out tab buttons left-to-right, wrapping to a new row when the next
-- button won't fit. Grows the strip height to fit all rows so the tab
-- bar never extends past the TabGroup's right edge.
local function relayoutTabs(self)
	local strip = self._tabStrip
	if not strip then return end
	local frame = self._frame
	local frameW = frame:GetWidth()
	if not frameW or frameW <= 0 then
		-- Width not known yet (first frame before layout settles); use the
		-- requested width as a fallback so we don't pack everything into
		-- row 0 and then have to re-wrap on the next OnSizeChanged.
		frameW = self._requestedWidth or DEFAULT_W
	end
	local maxX = frameW - STRIP_PAD
	local rowH = self._tabHeight or DEFAULT_TAB_H
	local gap  = self._gap or DEFAULT_GAP
	local x    = STRIP_PAD
	local yRow = 0     -- top of the current row, measured DOWN from strip TOP

	for _, t in ipairs(self._tabs) do
		if t._button then
			local w, _ = t._button.Cairn:GetIntrinsicSize()
			w = math.max(w or 60, 60)
			-- Wrap when the next button won't fit on this row. The check
			-- skips when x == STRIP_PAD so a single oversized button still
			-- fits (clipped) rather than wrapping infinitely.
			if x > STRIP_PAD and (x + w) > maxX then
				x = STRIP_PAD
				yRow = yRow + rowH + ROW_GAP
			end
			t._button:ClearAllPoints()
			t._button:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -yRow)
			t._button:SetSize(w, rowH)
			x = x + w + gap
		end
	end

	-- Total strip height = (rows * rowH) + ((rows - 1) * ROW_GAP).
	-- yRow is the top of the current (final) row.
	local stripH = yRow + rowH
	if stripH ~= self._currentStripH then
		strip:SetHeight(stripH)
		self._currentStripH = stripH
		reanchorPanes(self, stripH)
	end
end

local function applyVisibility(self)
	for _, t in ipairs(self._tabs) do
		local active = (t.id == self._selected)
		if t._content then t._content:SetShown(active) end
		if t._button then
			t._button.Cairn:SetVariant(active and "default" or "ghost")
		end
	end
end

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)
	frame:Show()

	self._tabHeight      = opts.tabHeight or DEFAULT_TAB_H
	self._gap            = opts.gap or DEFAULT_GAP
	self._requestedWidth = opts.width or DEFAULT_W
	self._currentStripH  = nil  -- forces reanchorPanes on first relayout

	-- Live re-layout on resize. The hook is per-acquire (not per-class)
	-- because the closure binds self; HookScript stacks safely so an
	-- acquire-release-acquire cycle on the same Frame won't accumulate
	-- duplicate calls unless the same frame instance is re-Acquired
	-- (pool=false here, so each Acquire is a fresh Frame).
	if not self._sizeHookInstalled then
		self._sizeHookInstalled = true
		frame:HookScript("OnSizeChanged", function()
			if self._tabs then relayoutTabs(self) end

			-- When a resizable Window grows, each tab pane is anchored
			-- TOPLEFT/BOTTOMRIGHT to our frame and so grows
			-- automatically -- but the Stack/etc layout the consumer
			-- set on the pane positions its children by computed
			-- coordinates, not by anchor inheritance. Force a reflow on
			-- the active pane so its content tracks the new viewport.
			-- Inactive panes are hidden; their layout will recompute
			-- next time they're shown.
			if self._tabs and self._selected then
				for _, t in ipairs(self._tabs) do
					if t.id == self._selected
					   and t._content
					   and t._content.Cairn
					   and t._content.Cairn.RelayoutNow then
						t._content.Cairn:RelayoutNow()
						break
					end
				end
			end
		end)
	end

	-- Tab strip Container along the top.
	if not self._tabStrip then
		self._tabStrip = Core:Acquire("Container", frame, {
			bg = "color.bg.surface",
		})
		self._tabStrip.Cairn:SetLayoutManual(true)
	end
	self._tabStrip:ClearAllPoints()
	self._tabStrip:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
	self._tabStrip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	self._tabStrip:SetHeight(self._tabHeight)

	-- Build tab buttons + content panes from opts.tabs.
	-- Released previous tabs first (in case this is a re-Acquire path,
	-- though pool=false makes that uncommon).
	if self._tabs then
		for _, t in ipairs(self._tabs) do
			if t._button  and t._button.Cairn  then t._button.Cairn:Release()  end
			if t._content and t._content.Cairn then t._content.Cairn:Release() end
		end
	end

	self._tabs = {}
	for i, tdef in ipairs(opts.tabs or {}) do
		local btn = Core:Acquire("Button", self._tabStrip, {
			text    = tdef.label or tdef.id,
			variant = "ghost",
			height  = self._tabHeight,
		})
		btn.Cairn:SetLayoutManual(true)

		local pane = Core:Acquire("Container", frame)
		-- Container's pool recycles the Cairn namespace without clearing
		-- consumer-set fields. Sub-addons' OnTabShow gates first-time
		-- build via `pane.Cairn._builtOnce`; a recycled pane carries that
		-- flag from a PREVIOUS owner, so the consumer skips build, calls
		-- refresh, and the pane renders empty. Explicitly clear here so
		-- every fresh tab pane starts unbuilt for its owner.
		pane.Cairn._builtOnce = nil
		pane.Cairn:SetLayoutManual(true)
		pane:ClearAllPoints()
		pane:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0,  -self._tabHeight)
		pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,   0)
		pane:Hide()

		local entry = {
			id       = tdef.id,
			label    = tdef.label,
			_button  = btn,
			_content = pane,
		}
		self._tabs[i] = entry

		btn.Cairn:On("Click", function()
			self:SetSelected(entry.id)
		end, "__tabClick")
	end

	relayoutTabs(self)

	-- Initial selection: opts.selected, or the first tab.
	local initial = opts.selected
	if not initial and self._tabs[1] then initial = self._tabs[1].id end
	self._selected = nil
	if initial then self:SetSelected(initial, true) end
end

-- ----- Public methods --------------------------------------------------

function mixin:GetTabContent(tabId)
	for _, t in ipairs(self._tabs or {}) do
		if t.id == tabId then return t._content end
	end
	return nil
end

function mixin:GetTabIds()
	local out = {}
	for i, t in ipairs(self._tabs or {}) do out[i] = t.id end
	return out
end

function mixin:SetSelected(tabId, _silentInitial)
	if self._selected == tabId then return end
	-- Verify the tab exists.
	local found
	for _, t in ipairs(self._tabs or {}) do
		if t.id == tabId then found = t; break end
	end
	if not found then return end

	local prev = self._selected
	self._selected = tabId
	applyVisibility(self)

	-- If the window was resized while this pane was hidden, its layout
	-- state is stale relative to the current frame size. Forcing a
	-- RelayoutNow on activation guarantees the content reflows to the
	-- current viewport on the next paint. Cheap when nothing changed
	-- (RelayoutNow short-circuits if the layout isn't dirty).
	if found._content and found._content.Cairn and found._content.Cairn.RelayoutNow then
		found._content.Cairn:RelayoutNow()
	end

	if not _silentInitial then
		self:Fire("Changed", tabId, prev)
	end
end

function mixin:GetSelected()
	return self._selected
end

-- ----- OnRelease (cleanup; runs before pool/hide) ----------------------

function mixin:OnRelease()
	-- Cascade-release tab buttons and content panes. Base:Release walks
	-- _children too, but we explicitly release here so the loop is
	-- correct even if children were SetParent'd elsewhere.
	if self._tabs then
		for _, t in ipairs(self._tabs) do
			if t._button  and t._button.Cairn  then t._button.Cairn:Release()  end
			if t._content and t._content.Cairn then t._content.Cairn:Release() end
		end
		self._tabs = nil
	end
	if self._tabStrip and self._tabStrip.Cairn then
		self._tabStrip.Cairn:Release()
		self._tabStrip = nil
	end
end

-- ----- Register --------------------------------------------------------
-- pool = false: see header for rationale.

Core:RegisterWidget("TabGroup", {
	frameType = "Frame",
	mixin     = mixin,
	pool      = false,
})
