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
	When the strip would overflow horizontally, tabs are clipped (no
	scroll affordance in v1; consumers can wrap a TabGroup inside a
	ScrollFrame or use shorter labels for now).

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
	no contextual icons, no "tabs that scroll horizontally." Deferred.
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

-- ----- TabGroup mixin --------------------------------------------------

local mixin = {}

local function relayoutTabs(self)
	local strip = self._tabStrip
	if not strip then return end
	local x   = STRIP_PAD
	local gap = self._gap or DEFAULT_GAP
	for _, t in ipairs(self._tabs) do
		if t._button then
			local w, _ = t._button.Cairn:GetIntrinsicSize()
			w = math.max(w or 60, 60)
			t._button:ClearAllPoints()
			t._button:SetPoint("LEFT", strip, "LEFT", x, 0)
			t._button:SetSize(w, self._tabHeight)
			x = x + w + gap
		end
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

	self._tabHeight = opts.tabHeight or DEFAULT_TAB_H
	self._gap       = opts.gap or DEFAULT_GAP

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
