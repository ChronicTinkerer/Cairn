--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Dropdown

Selection from a list. The header is a clickable Button-like field
showing the current selection (or a placeholder). Clicking opens a
popup parented to UIParent that lists the options; the popup uses
ScrollFrame internally when the option count exceeds maxVisibleRows.

Public API:

	dd = Cairn.Gui:Acquire("Dropdown", parent, {
		width          = 200,
		height         = 24,
		options        = {
			{ value = "small",  label = "Small"  },
			{ value = "medium", label = "Medium" },
			{ value = "large",  label = "Large"  },
		},
		selected       = "medium",       -- initial selection (matches .value)
		placeholder    = "Select size...",
		maxVisibleRows = 8,              -- popup caps at this; rest scroll
		rowHeight      = 22,
	})

	dd.Cairn:SetOptions(opts)
	dd.Cairn:SetSelected(value)         -- programmatic; fires Changed if differs
	dd.Cairn:GetSelected()              -- the current value, or nil
	dd.Cairn:GetSelectedLabel()         -- the displayed label
	dd.Cairn:Open()
	dd.Cairn:Close()
	dd.Cairn:IsOpen()

	dd.Cairn:On("Changed",       function(w, value, label) ... end)
	dd.Cairn:On("Opened",        function(w) ... end)
	dd.Cairn:On("Closed",        function(w) ... end)
	dd.Cairn:On("RowRightClick", function(w, value, label, rowFrame) ... end)

Outside-click behavior

	On Open, the dropdown subscribes to Cairn.Events GLOBAL_MOUSE_DOWN.
	When that fires, the handler checks whether the cursor is over the
	popup or the header; if neither, it calls Close. Subscription is
	dropped on Close.

Pool: NOT pooled. The popup owns sub-widgets (header is its own Button,
popup contains a ScrollFrame and Cairn Button rows); simplest correct
path is no pool. Released Dropdowns cascade-release the row buttons
back to the pool, hide the popup frame, and unhook GLOBAL_MOUSE_DOWN.

Tokens consumed

	color.bg.button[.hover/.pressed]       (header bg, default-variant Button)
	color.bg.panel                          (popup bg)
	color.border.default                    (popup border)
	color.fg.text                           (header / row text)
	color.fg.text.muted                     (placeholder text)
	color.accent.primary                    (selected-row accent strip)
	font.body                               (text font)

Status

	Day 16. v1: single-select, scrollable popup, outside-click close,
	keyboard ESC close. No multi-select, no search/filter, no nested
	options, no icons-per-row. Deferred to a Forms bundle if the demand
	shows up.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

local Events = LibStub("Cairn-Events-1.0", true)

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W           = 200
local DEFAULT_H           = 24
local DEFAULT_ROW_H       = 22
local DEFAULT_MAX_ROWS    = 8
local POPUP_PADDING       = 4
local CARET_W             = 12
local WHITE_TEX           = "Interface\\Buttons\\WHITE8x8"

-- ----- Helpers ---------------------------------------------------------

local function color(self, token)
	local c = self:ResolveToken(token)
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end
	return 1, 1, 1, 1
end

-- Find the option entry whose .value matches `v`. Returns the entry or nil.
local function findOption(options, v)
	if not options then return nil end
	for i = 1, #options do
		if options[i].value == v then return options[i], i end
	end
	return nil
end

-- ----- Popup management -----------------------------------------------
-- The popup is a Frame parented to UIParent so it floats above other UI
-- without being clipped by the dropdown's parent container.

local function ensurePopup(self)
	if self._popup then return end
	local frame = self._frame

	local popup = CreateFrame("Frame", nil, UIParent)
	popup:SetFrameStrata("DIALOG")
	popup:Hide()

	-- Bg + border via raw textures (not Cairn primitives because the popup
	-- isn't a Cairn widget on its own; it's owned internal scaffolding).
	local bg = popup:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE_TEX)
	bg:SetAllPoints(popup)

	local border = {}
	for i = 1, 4 do
		border[i] = popup:CreateTexture(nil, "BORDER")
		border[i]:SetTexture(WHITE_TEX)
	end
	border[1]:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
	border[1]:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
	border[1]:SetHeight(1)
	border[2]:SetPoint("BOTTOMLEFT",  popup, "BOTTOMLEFT",  0, 0)
	border[2]:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 0)
	border[2]:SetHeight(1)
	border[3]:SetPoint("TOPLEFT",    popup, "TOPLEFT",    0, 0)
	border[3]:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 0, 0)
	border[3]:SetWidth(1)
	border[4]:SetPoint("TOPRIGHT",    popup, "TOPRIGHT",    0, 0)
	border[4]:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 0)
	border[4]:SetWidth(1)

	-- Internal ScrollFrame (Cairn widget). Sized later when options are set.
	local scroll = Core:Acquire("ScrollFrame", popup, {
		width  = 100,
		height = 100,
		showScrollbar = true,
	})
	scroll:SetPoint("TOPLEFT",     popup, "TOPLEFT",     POPUP_PADDING, -POPUP_PADDING)
	scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -POPUP_PADDING,  POPUP_PADDING)
	scroll.Cairn:SetLayoutManual(true)

	popup:SetScript("OnKeyDown", function(_, key)
		if key == "ESCAPE" then self:Close() end
	end)
	popup:SetPropagateKeyboardInput(true)

	self._popup       = popup
	self._popupBg     = bg
	self._popupBorder = border
	self._popupScroll = scroll
end

-- Apply token-driven colors to the popup chrome. Called on every Open so
-- a runtime SetActiveTheme picks up.
local function repaintPopupChrome(self)
	if not self._popupBg then return end
	local pr, pg, pb, pa = color(self, "color.bg.panel")
	self._popupBg:SetVertexColor(pr, pg, pb, pa)
	local br, bg, bb, ba = color(self, "color.border.default")
	for _, t in ipairs(self._popupBorder) do
		t:SetVertexColor(br, bg, bb, ba)
	end
end

-- Tear down all currently-acquired row buttons and re-create from the
-- option list. Called on Open and on SetOptions.
local function rebuildRows(self)
	-- Release any previous rows.
	if self._rows then
		for i = 1, #self._rows do
			if self._rows[i] and self._rows[i].Cairn and self._rows[i].Cairn.Release then
				self._rows[i].Cairn:Release()
			end
		end
	end
	self._rows = {}

	local opts    = self._options or {}
	local content = self._popupScroll.Cairn:GetContent()
	local W       = self._popupWidth or DEFAULT_W
	local rowH    = self._rowHeight  or DEFAULT_ROW_H

	for i, opt in ipairs(opts) do
		local row = Core:Acquire("Button", content, {
			text    = opt.label or tostring(opt.value),
			variant = "ghost",
			width   = W - 8,        -- popup padding accounted for
			height  = rowH,
		})
		row.Cairn:SetLayoutManual(true)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, -((i - 1) * rowH))
		row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -((i - 1) * rowH))

		row.Cairn:On("Click", function(_, button)
			-- Right-click on a row fires a dropdown-level event instead of
			-- selecting. Lets consumers attach a per-row context menu
			-- (lock/unlock, delete, etc.) without forking Dropdown. The
			-- popup stays open so the menu can anchor relative to the row.
			if button == "RightButton" then
				self:Fire("RowRightClick", opt.value, opt.label, row)
				return
			end
			self:_selectOption(opt)
		end, "__rowClick")

		self._rows[i] = row
	end

	-- Update content height so ScrollFrame's range is correct.
	self._popupScroll.Cairn:SetContentHeight(#opts * rowH)
end

-- Position the popup directly below the header, sized for the visible
-- row count up to maxVisibleRows. ScrollFrame inside takes care of
-- scrolling the rest.
local function layoutPopup(self)
	local frame    = self._frame
	local popup    = self._popup
	local opts     = self._options or {}
	local maxRows  = self._maxVisibleRows or DEFAULT_MAX_ROWS
	local rowH     = self._rowHeight or DEFAULT_ROW_H
	local visible  = math.min(#opts, maxRows)
	local W        = frame:GetWidth()

	popup:ClearAllPoints()
	popup:SetWidth(W)
	popup:SetHeight(visible * rowH + POPUP_PADDING * 2)
	popup:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)

	self._popupWidth = W
end

-- ----- Outside-click handling ------------------------------------------
-- Close the popup if the user clicks anywhere that isn't the popup or
-- the header. We hook GLOBAL_MOUSE_DOWN via Cairn.Events so we don't
-- fight UIParent for input.

local function bindOutsideClick(self)
	if not Events or self._outsideUnsub then return end
	self._outsideUnsub = Events:Subscribe("GLOBAL_MOUSE_DOWN", function()
		if not self._open then return end
		-- A tick later, IsMouseOver() is reliable. Use C_Timer.After(0).
		C_Timer.After(0, function()
			if not self._open then return end
			local overPopup  = self._popup and self._popup:IsMouseOver()
			local overHeader = self._frame and self._frame:IsMouseOver()
			if not overPopup and not overHeader then
				self:Close()
			end
		end)
	end, self)
end

local function unbindOutsideClick(self)
	if self._outsideUnsub then
		pcall(self._outsideUnsub)
		self._outsideUnsub = nil
	end
end

-- ----- Dropdown mixin --------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)

	self._options        = opts.options or {}
	self._selected       = opts.selected
	self._placeholder    = opts.placeholder or ""
	self._maxVisibleRows = opts.maxVisibleRows or DEFAULT_MAX_ROWS
	self._rowHeight      = opts.rowHeight or DEFAULT_ROW_H
	self._open           = false

	-- Header bg + border (default-variant Button look).
	self:DrawRect("bg", {
		default    = "color.bg.button",
		hover      = "color.bg.button.hover",
		pressed    = "color.bg.button.pressed",
		disabled   = "color.bg.button.disabled",
		transition = "duration.fast",
	})
	self:DrawBorder("frame", "color.border.default", { width = 1 })

	-- Header label.
	if not self._label then
		self._label = frame:CreateFontString(nil, "OVERLAY")
		self._label:SetPoint("LEFT",  frame, "LEFT",  8, 0)
		self._label:SetPoint("RIGHT", frame, "RIGHT", -(CARET_W + 4), 0)
		self._label:SetJustifyH("LEFT")
		self._label:SetWordWrap(false)
	end
	local font = self:ResolveToken("font.body")
	if font then self._label:SetFont(font.face, font.size, font.flags or "") end

	-- Caret on the right side: a tiny down-pointing triangle made of two
	-- triangles via SetTexCoord. Simpler: a static texture from a known
	-- atlas. Use a textured FontString of a unicode arrow as a tiny hack;
	-- we'll switch to atlas in a follow-up.
	if not self._caret then
		self._caret = frame:CreateFontString(nil, "OVERLAY")
		self._caret:SetPoint("RIGHT", frame, "RIGHT", -6, -1)
	end
	if font then self._caret:SetFont(font.face, font.size, font.flags or "") end
	self._caret:SetText("v")  -- minimalist; theme can replace later

	self:_refreshLabel()

	-- Click on header toggles open/close.
	frame:SetScript("OnMouseDown", function() end)  -- swallow so the bg state-machine fires
	frame:SetScript("OnClick", function()
		if self._open then self:Close() else self:Open() end
	end)
	-- Frames need RegisterForClicks to fire OnClick reliably. Slider's
	-- SetScript("OnClick") works because Slider IS a Button frame type;
	-- here our frame might be Button or Frame. We're registered as
	-- frameType "Button" below, so this works.
	if frame.RegisterForClicks then
		frame:RegisterForClicks("LeftButtonUp")
	end
end

function mixin:_refreshLabel()
	local opt = findOption(self._options, self._selected)
	if opt then
		local r, g, b, a = color(self, "color.fg.text")
		self._label:SetTextColor(r, g, b, a)
		self._label:SetText(opt.label or tostring(opt.value))
	else
		local r, g, b, a = color(self, "color.fg.text.muted")
		self._label:SetTextColor(r, g, b, a)
		self._label:SetText(self._placeholder or "")
	end
end

function mixin:_selectOption(opt)
	local prev = self._selected
	self._selected = opt.value
	self:_refreshLabel()
	self:Close()
	if prev ~= opt.value then
		self:Fire("Changed", opt.value, opt.label)
	end
end

-- ----- Public methods --------------------------------------------------

function mixin:SetOptions(opts)
	self._options = opts or {}
	-- If currently selected value isn't in new list, clear selection.
	if self._selected and not findOption(self._options, self._selected) then
		self._selected = nil
	end
	self:_refreshLabel()
	if self._open then
		rebuildRows(self)
		layoutPopup(self)
	end
	-- Header label width tracks the selected option's label; invalidate
	-- the parent layout so siblings re-anchor.
	self:_invalidateParentLayout()
end

function mixin:GetOptions()
	return self._options
end

function mixin:SetSelected(value)
	local prev = self._selected
	self._selected = value
	self:_refreshLabel()
	if prev ~= value then
		local opt = findOption(self._options, value)
		self:Fire("Changed", value, opt and opt.label or nil)
	end
	-- Header text width tracks the selection; tell the parent layout to
	-- re-measure.
	self:_invalidateParentLayout()
end

function mixin:GetSelected()
	return self._selected
end

function mixin:GetSelectedLabel()
	local opt = findOption(self._options, self._selected)
	return opt and opt.label or nil
end

function mixin:Open()
	if self._open then return end
	ensurePopup(self)
	repaintPopupChrome(self)
	rebuildRows(self)
	layoutPopup(self)
	self._popup:Show()
	self._open = true
	bindOutsideClick(self)
	self:Fire("Opened")
end

function mixin:Close()
	if not self._open then return end
	self._open = false
	if self._popup then self._popup:Hide() end
	unbindOutsideClick(self)
	self:Fire("Closed")
end

function mixin:IsOpen()
	return self._open or false
end

-- ----- OnRelease (cleanup; runs before pool/hide) ----------------------

function mixin:OnRelease()
	self:Close()
	if self._rows then
		for i = 1, #self._rows do
			if self._rows[i] and self._rows[i].Cairn then
				self._rows[i].Cairn:Release()
			end
		end
		self._rows = nil
	end
end

-- ----- Register --------------------------------------------------------
-- pool = false: see header for rationale.

Core:RegisterWidget("Dropdown", {
	frameType = "Button",
	mixin     = mixin,
	pool      = false,
})
