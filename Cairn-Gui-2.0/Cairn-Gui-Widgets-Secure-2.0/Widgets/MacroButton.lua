--[[
Cairn-Gui-Widgets-Secure-2.0 / Widgets / MacroButton

A focused subset of ActionButton specialized for executing macro text.
The button's `type` is fixed at "macro" or "macrotext" depending on
which is provided. Useful when the consumer doesn't need the full
spell/item/unit-target surface.

Public API on a MacroButton widget:

	btn = Cairn.Gui:Acquire("MacroButton", parent, {
		macro     = "Heroic Strike",     -- named saved macro, OR
		macrotext = "/cast Frostbolt",   -- inline text
		text      = "Macro 1",            -- visible label
		width     = 120,
		height    = 28,
	})

	btn.Cairn:SetMacroText("/cast Holy Light")  -- queued during combat
	btn.Cairn:SetMacro("Heroic Strike")          -- queued during combat
	btn.Cairn:SetText("Different Label")         -- not queued (label is UI-only)

	btn.Cairn:On("PostClick", function(w, mouseButton, down) ... end)

Combat behavior

	SetMacroText / SetMacro queue during combat just like ActionButton's
	typed wrappers. SetText is a label change on a FontString and runs
	immediately regardless of combat state.

Pool: enabled. Pre-warmed: 8 instances at PLAYER_LOGIN+0.5s.

Cairn-Gui-Widgets-Secure-2.0/Widgets/MacroButton (c) 2026 ChronicTinkerer.
MIT license.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Secure-2.0", true)
if not Bundle then return end

local Core   = Bundle._core
local Combat = Core and Core.Combat

local DEFAULT_W = 120
local DEFAULT_H = 28

local function setAttr(self, name, value)
	local frame = self._frame
	if not frame then return end
	if Combat and Combat.Queue then
		Combat:Queue(frame, "SetAttribute", name, value)
	else
		if frame.SetAttribute then frame:SetAttribute(name, value) end
	end
end

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame
	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)

	-- Standard button visuals (state-machine bg + 1px border + label).
	self:DrawRect("bg", {
		default    = "color.bg.button",
		hover      = "color.bg.button.hover",
		pressed    = "color.bg.button.pressed",
		disabled   = "color.bg.button.disabled",
		transition = "duration.fast",
	})
	self:DrawBorder("frame", "color.border.default", { width = 1 })

	if not self._label then
		self._label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		self._label:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end
	self._label:SetText(self:_resolveText(opts.text or ""))

	-- Default action type: macro if a macro is given, macrotext if text
	-- is given, else nothing until the consumer wires one explicitly.
	if opts.macrotext then
		setAttr(self, "type", "macrotext")
		setAttr(self, "macrotext", opts.macrotext)
	elseif opts.macro then
		setAttr(self, "type", "macro")
		setAttr(self, "macro", opts.macro)
	end

	frame:SetScript("PostClick", function(_, button, down)
		self:Fire("PostClick", button, down)
	end)
	if frame.RegisterForClicks then
		frame:RegisterForClicks("AnyUp")
	end
end

function mixin:SetMacro(name)
	setAttr(self, "type",  "macro")
	setAttr(self, "macro", name)
end

function mixin:SetMacroText(text)
	setAttr(self, "type",      "macrotext")
	setAttr(self, "macrotext", text)
end

function mixin:SetText(text)
	-- Label is a UI-only FontString; not subject to combat lockdown.
	if self._label then self._label:SetText(self:_resolveText(text or "")) end
end

function mixin:GetText()
	return self._label and self._label:GetText() or ""
end

local function reset(self)
	setAttr(self, "type",      nil)
	setAttr(self, "macro",     nil)
	setAttr(self, "macrotext", nil)
	if self._label then self._label:SetText("") end
end

Core:RegisterWidget("MacroButton", {
	frameType = "Button",
	template  = "SecureActionButtonTemplate, BackdropTemplate",
	mixin     = mixin,
	pool      = true,
	secure    = true,
	prewarm   = 8,
	reset     = reset,
})
