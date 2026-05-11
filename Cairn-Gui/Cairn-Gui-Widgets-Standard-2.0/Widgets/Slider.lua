--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Slider

Numeric range input. Horizontal-only in v1. The slider has a track, a
draggable thumb, and an optional value readout. The track drawing
fits within the slider's height and is theme-token-driven.

Public API:

	sl = Cairn.Gui:Acquire("Slider", parent, {
		width       = 200,
		height      = 20,
		min         = 0,
		max         = 100,
		step        = 1,            -- 0 = continuous (any float)
		value       = 50,           -- initial value (clamped to min/max)
		showValue   = true,         -- inline value readout to the right
		valueFormat = "%d",         -- format string for the readout
	})

	sl.Cairn:SetValue(75)           -- programmatic; fires Changed if value differs
	sl.Cairn:GetValue()
	sl.Cairn:SetMinMax(min, max)
	sl.Cairn:GetMinMax()
	sl.Cairn:SetStep(step)
	sl.Cairn:SetEnabled(false)

	sl.Cairn:On("Changed",   function(w, value) end)   -- on every value change
	sl.Cairn:On("DragStart", function(w) end)
	sl.Cairn:On("DragStop",  function(w, value) end)

Tokens consumed

	color.bg.surface              (track bg, subtle)
	color.border.default          (track border, very thin)
	color.accent.primary          (thumb default)
	color.accent.primary.hover    (thumb hover)
	color.fg.text                 (value readout)
	font.body                     (value readout font)

Pool: enabled. Settings panels recycle Sliders heavily.

Status

	Day 16. v1: horizontal only, draggable thumb, inline value display,
	step + continuous modes, standard events. No keyboard arrow nudging,
	no tick marks, no logarithmic scale, no vertical orientation. All
	deferrable.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W           = 200
local DEFAULT_H           = 20
local TRACK_HEIGHT        = 4
local THUMB_W             = 12
local THUMB_H             = 16
local VALUE_RESERVE       = 36   -- px on the right reserved for value readout
local WHITE_TEX           = "Interface\\Buttons\\WHITE8x8"

-- ----- Helpers ---------------------------------------------------------

local function color(self, token)
	local c = self:ResolveToken(token)
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end
	return 1, 1, 1, 1
end

-- Build the thumb texture and apply default tint. Idempotent for pool reuse.
local function ensureThumbTexture(self)
	if self._thumbTex then return end
	local thumbTex = self._frame:CreateTexture(nil, "OVERLAY")
	thumbTex:SetTexture(WHITE_TEX)
	thumbTex:SetSize(THUMB_W, THUMB_H)
	-- Blizzard Slider requires SetThumbTexture before render; pass our
	-- texture object and it will be positioned automatically on value
	-- changes by the underlying Slider machinery.
	self._frame:SetThumbTexture(thumbTex)
	self._thumbTex = thumbTex
end

local function applyThumbColor(self, state)
	if not self._thumbTex then return end
	local r, g, b, a
	if state == "hover" or state == "pressed" then
		r, g, b, a = color(self, "color.accent.primary.hover")
	else
		r, g, b, a = color(self, "color.accent.primary")
	end
	self._thumbTex:SetVertexColor(r, g, b, a)
end

-- Update the value readout FontString from the current slider value.
local function refreshValueText(self)
	if not self._valueFS then return end
	local v   = self._frame:GetValue() or 0
	local fmt = self._valueFormat or "%d"
	-- For integer step, format as int even if Lua treats as float.
	if self._step and self._step >= 1 then v = math.floor(v + 0.5) end
	self._valueFS:SetText(string.format(fmt, v))
end

-- ----- Slider mixin ----------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	local W = opts.width  or DEFAULT_W
	local H = opts.height or DEFAULT_H
	frame:SetSize(W, H)
	frame:SetOrientation("HORIZONTAL")
	frame:Show()

	-- Range + step.
	local mn, mx = opts.min or 0, opts.max or 100
	if mx <= mn then mx = mn + 1 end
	frame:SetMinMaxValues(mn, mx)
	self._step = opts.step or 1
	frame:SetValueStep(self._step)
	frame:SetObeyStepOnDrag(self._step > 0)

	-- Initial value (clamped).
	local v = opts.value or mn
	if v < mn then v = mn end
	if v > mx then v = mx end
	frame:SetValue(v)

	self._valueFormat = opts.valueFormat or "%d"

	-- Track (a thin centered rect drawn via the primitive system).
	self:DrawRect("track", "color.bg.surface")

	-- Pin the track to the center of the slider's height. Primitives let
	-- us reach the underlying texture for repositioning. SetPrimitiveRect
	-- isn't a thing in v1, so we do raw size+anchor on the track texture
	-- via the primitive's _tex hook, falling back to creating our own
	-- texture if the primitive system doesn't expose it.
	if not self._trackBgTex then
		local trackBg = frame:CreateTexture(nil, "BACKGROUND")
		trackBg:SetTexture(WHITE_TEX)
		trackBg:SetHeight(TRACK_HEIGHT)
		local rightInset = (opts.showValue ~= false) and VALUE_RESERVE or 0
		trackBg:SetPoint("LEFT",  frame, "LEFT",  0, 0)
		trackBg:SetPoint("RIGHT", frame, "RIGHT", -rightInset, 0)
		self._trackBgTex = trackBg
	end
	-- Tint the track from the surface token. Slightly dimmer for subtlety.
	local tr, tg, tb, ta = color(self, "color.bg.surface")
	self._trackBgTex:SetVertexColor(tr, tg, tb, ta * 0.8)

	-- Thumb (Blizzard-managed positioning, our texture).
	ensureThumbTexture(self)
	applyThumbColor(self, "default")

	-- Value readout FontString (optional).
	local showValue = opts.showValue ~= false
	if showValue then
		if not self._valueFS then
			self._valueFS = frame:CreateFontString(nil, "OVERLAY")
			self._valueFS:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
			self._valueFS:SetJustifyH("RIGHT")
			self._valueFS:SetWidth(VALUE_RESERVE)
		end
		local font = self:ResolveToken("font.body")
		if font then self._valueFS:SetFont(font.face, font.size, font.flags or "") end
		local r, g, b, a = color(self, "color.fg.text")
		self._valueFS:SetTextColor(r, g, b, a)
		self._valueFS:Show()
	elseif self._valueFS then
		self._valueFS:Hide()
	end
	refreshValueText(self)

	-- ----- Native -> Cairn event bridges -------------------------------
	frame:SetScript("OnValueChanged", function(_, value, userInput)
		refreshValueText(self)
		self:Fire("Changed", value, userInput and true or false)
	end)
	frame:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			applyThumbColor(self, "pressed")
			self:Fire("DragStart")
		end
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			applyThumbColor(self, frame:IsMouseOver() and "hover" or "default")
			self:Fire("DragStop", frame:GetValue() or 0)
		end
	end)
	frame:SetScript("OnEnter", function() applyThumbColor(self, "hover") end)
	frame:SetScript("OnLeave", function() applyThumbColor(self, "default") end)
end

-- ----- Public methods --------------------------------------------------

function mixin:GetValue()
	return self._frame:GetValue() or 0
end

function mixin:SetValue(v)
	-- Blizzard's SetValue clamps to min/max automatically. Going through
	-- it fires OnValueChanged which our handler bridges to "Changed".
	self._frame:SetValue(v)
end

function mixin:GetMinMax()
	return self._frame:GetMinMaxValues()
end

function mixin:SetMinMax(mn, mx)
	if mx <= mn then mx = mn + 1 end
	self._frame:SetMinMaxValues(mn, mx)
	-- Re-clamp current value if it now falls outside the range.
	local v = self._frame:GetValue() or mn
	if v < mn then self._frame:SetValue(mn) end
	if v > mx then self._frame:SetValue(mx) end
end

function mixin:SetStep(step)
	self._step = step or 1
	self._frame:SetValueStep(self._step)
	self._frame:SetObeyStepOnDrag(self._step > 0)
end

function mixin:SetEnabled(enabled)
	enabled = enabled and true or false
	self._frame:EnableMouse(enabled)
	if enabled then
		applyThumbColor(self, "default")
	else
		-- Dim the thumb; Blizzard's :Disable() stops input but doesn't
		-- gray the texture for us.
		if self._thumbTex then
			self._thumbTex:SetVertexColor(0.4, 0.4, 0.5, 0.6)
		end
	end
end

function mixin:GetIntrinsicSize()
	return DEFAULT_W, DEFAULT_H
end

-- ----- Pool reset ------------------------------------------------------

local function reset(self)
	if self._frame then
		self._frame:SetScript("OnValueChanged", nil)
		self._frame:SetScript("OnMouseDown",    nil)
		self._frame:SetScript("OnMouseUp",      nil)
		self._frame:SetScript("OnEnter",        nil)
		self._frame:SetScript("OnLeave",        nil)
	end
	if self._valueFS then self._valueFS:Hide() end
	self._step = nil
	self._valueFormat = nil
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("Slider", {
	frameType = "Slider",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
