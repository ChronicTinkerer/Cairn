--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Window

A top-level container with a title bar, optional close button, and a
content area where consumers add their widgets. Drag-to-move enabled
by default from the title bar.

Public API:

	win = Cairn.Gui:Acquire("Window", UIParent, {
		title    = "Settings",
		width    = 400,
		height   = 300,
		closable = true,        -- show close button (default true)
		movable  = true,        -- title bar drag-to-move (default true)
	})

	local content = win.Cairn:GetContent()  -- Cairn-aware Container frame
	content.Cairn:SetLayout("Stack", { direction = "vertical", gap = 4, padding = 8 })
	Cairn.Gui:Acquire("Label",  content, { text = "Hello", variant = "heading" })
	Cairn.Gui:Acquire("Button", content, { text = "OK",     variant = "primary" })

	win.Cairn:SetTitle("New Title")
	win.Cairn:GetTitle()
	win.Cairn:On("Close", function(widget)
		-- Default handler hides the frame. Add your own to override
		-- (e.g., release the window, save state, prompt confirmation).
	end)

Layout

	The Window itself does NOT use a layout strategy; it positions its
	internal title bar and content area explicitly in OnAcquire. You set
	a layout on the CONTENT frame, not on the Window. The internal
	sub-widgets are flagged SetLayoutManual so even if you SetLayout on
	the Window directly (don't), they wouldn't move.

Pool

	NOT pooled. Top-level windows are low-churn and the simplest
	correct path is to not deal with internal-widget state across
	Acquire cycles. Released Windows have their internal sub-widgets
	cascade-released to their respective pools (Container, Label,
	Button), then the Window frame is hidden.

Tokens consumed:
	color.bg.panel              (window background)
	color.border.default        (window border)
	color.bg.surface            (title bar background)

Internal sub-widgets:
	_titleBar    Container, anchored to top of frame
	_titleLabel  Label, heading variant, left-aligned in title bar
	_closeBtn    Button, ghost variant, right side of title bar (if closable)
	_content     Container, anchored below title bar with 1px inset

Status: Day 13. No resize handle yet; window is a fixed size at acquire
time (consumer can SetSize after if desired). No modal mode. No focus
ring. No keyboard escape-to-close. All deferrable.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W         = 400
local DEFAULT_H         = 300
local TITLE_BAR_HEIGHT  = 28
local CLOSE_BTN_SIZE    = 20
local TITLE_PAD_LEFT    = 12
local CLOSE_PAD_RIGHT   = 4

-- ----- Window mixin ----------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)
	frame:SetFrameStrata(opts.strata or "DIALOG")
	frame:Show()

	-- Movability: default on. Acquired even if movable=false so the
	-- frame can be later toggled (we don't support that yet, but the
	-- enable-mouse cost is negligible).
	local movable = opts.movable ~= false
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)

	-- Window backdrop primitives.
	self:DrawRect("bg", "color.bg.panel")
	self:DrawBorder("frame", "color.border.default", { width = 1 })

	-- ----- Title bar (Container) --------------------------------------
	if not self._titleBar then
		self._titleBar = Core:Acquire("Container", frame, {
			bg = "color.bg.surface",
		})
		self._titleBar.Cairn:SetLayoutManual(true)
	end
	self._titleBar:ClearAllPoints()
	self._titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, -1)
	self._titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	self._titleBar:SetHeight(TITLE_BAR_HEIGHT)

	-- Wire drag on the title bar to move the window.
	self._titleBar:EnableMouse(true)
	self._titleBar:RegisterForDrag("LeftButton")
	if movable then
		self._titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
		self._titleBar:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)
	else
		self._titleBar:SetScript("OnDragStart", nil)
		self._titleBar:SetScript("OnDragStop",  nil)
	end

	-- ----- Title label ------------------------------------------------
	if not self._titleLabel then
		self._titleLabel = Core:Acquire("Label", self._titleBar, {
			text    = opts.title or "",
			variant = "heading",
			align   = "left",
		})
		self._titleLabel.Cairn:SetLayoutManual(true)
	else
		self._titleLabel.Cairn:SetText(opts.title or "")
	end
	self._titleLabel:ClearAllPoints()
	self._titleLabel:SetPoint("LEFT",  self._titleBar, "LEFT",  TITLE_PAD_LEFT, 0)
	self._titleLabel:SetPoint("RIGHT", self._titleBar, "RIGHT", -(CLOSE_BTN_SIZE + CLOSE_PAD_RIGHT * 2), 0)

	-- ----- Close button (optional) ------------------------------------
	local closable = opts.closable ~= false
	if closable then
		if not self._closeBtn then
			self._closeBtn = Core:Acquire("Button", self._titleBar, {
				text    = "x",
				variant = "ghost",
				width   = CLOSE_BTN_SIZE,
				height  = CLOSE_BTN_SIZE,
			})
			self._closeBtn.Cairn:SetLayoutManual(true)

			-- Bridge close-button click to the Window's Close event.
			-- Captured `self` is the Window's cairn; safe under not-pooled.
			self._closeBtn.Cairn:On("Click", function()
				self:Fire("Close")
			end)
		end
		self._closeBtn:ClearAllPoints()
		self._closeBtn:SetPoint("RIGHT", self._titleBar, "RIGHT", -CLOSE_PAD_RIGHT, 0)
		self._closeBtn:Show()
	elseif self._closeBtn then
		self._closeBtn:Hide()
	end

	-- ----- Content area -----------------------------------------------
	if not self._content then
		self._content = Core:Acquire("Container", frame)
		self._content.Cairn:SetLayoutManual(true)
	end
	self._content:ClearAllPoints()
	self._content:SetPoint("TOPLEFT",     frame, "TOPLEFT",     1, -(TITLE_BAR_HEIGHT + 1))
	self._content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
	self._content:Show()

	-- Default Close handler: hide the frame. Consumers can override by
	-- subscribing their own handler; both will fire (multi-subscriber).
	-- Tagged so it can be replaced cleanly via OffByTag if desired.
	self:On("Close", function(widget)
		widget._frame:Hide()
	end, "__defaultClose")
end

-- ----- Public methods --------------------------------------------------

function mixin:GetContent()
	return self._content
end

function mixin:SetTitle(title)
	if self._titleLabel then
		self._titleLabel.Cairn:SetText(title or "")
	end
end

function mixin:GetTitle()
	if self._titleLabel then
		return self._titleLabel.Cairn:GetText()
	end
	return ""
end

-- ----- Register --------------------------------------------------------
-- pool = false: see header for rationale.

Core:RegisterWidget("Window", {
	frameType = "Frame",
	mixin     = mixin,
	template  = "BackdropTemplate",
	pool      = false,
})
