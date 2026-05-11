--[[
Cairn-Gui-Widgets-Secure-2.0 / Widgets / UnitButton

A secure unit-frame-style button. Clicking it acts on the bound unit:
target / focus / assist / menu, etc., depending on the click bindings.
This is the foundation for raid frames, party frames, target frames,
arena/boss unit displays, and any custom unit interaction surface.

Public API on a UnitButton widget:

	btn = Cairn.Gui:Acquire("UnitButton", parent, {
		unit  = "player",        -- unit token bound to the button
		width = 100,
		height= 28,
	})

	btn.Cairn:SetUnit("party1")           -- queued during combat
	btn.Cairn:SetClickAction(button, action, modifier?)
	                                      -- e.g. ("LeftButton", "target")
	                                      -- queued during combat
	btn.Cairn:Clear()

	btn.Cairn:On("PreClick",  function(w, mouseButton, down) ... end)
	btn.Cairn:On("PostClick", function(w, mouseButton, down) ... end)

Default click bindings (set on first Acquire if not overridden):

	LeftButton           = "target"     (target the unit)
	RightButton          = "menu"       (open the unit context menu)
	MiddleButton         = "focus"      (set focus to the unit)
	-- Modifiers can be layered via the standard Blizzard
	-- "type1" / "*type2" / "shift-type1" / "ctrl-type1" attribute names;
	-- pass `modifier = "shift"` etc. to SetClickAction.

Combat behavior

	SetUnit and SetClickAction queue during combat. Visual decorations
	(health/power bars, name plate text, debuff icons) are not bound by
	the secure system and update immediately as long as the consumer
	wires them on top of the widget.

Pool: enabled. Pre-warmed: 8 instances at PLAYER_LOGIN+0.5s.

Cairn-Gui-Widgets-Secure-2.0/Widgets/UnitButton (c) 2026 ChronicTinkerer.
MIT license.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Secure-2.0", true)
if not Bundle then return end

local Core   = Bundle._core
local Combat = Core and Core.Combat

local DEFAULT_W = 100
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

-- Map mouseButton string (as passed to RegisterForClicks) to the
-- attribute-key prefix Blizzard's SecureUnitButtonTemplate expects.
local CLICK_KEY = {
	LeftButton   = "type1",
	RightButton  = "type2",
	MiddleButton = "type3",
	Button4      = "type4",
	Button5      = "type5",
}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame
	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)

	self:DrawRect("bg", {
		default    = "color.bg.button",
		hover      = "color.bg.button.hover",
		pressed    = "color.bg.button.pressed",
		disabled   = "color.bg.button.disabled",
		transition = "duration.fast",
	})
	self:DrawBorder("frame", "color.border.default", { width = 1 })

	-- Optional name label centered horizontally; consumers can hide via
	-- SetText("") if they're laying out a custom unit-frame.
	if not self._nameFs then
		self._nameFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		self._nameFs:SetPoint("LEFT", frame, "LEFT", 6, 0)
		self._nameFs:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
		self._nameFs:SetJustifyH("LEFT")
	end
	self._nameFs:SetText(self:_resolveText(opts.text or ""))

	-- Bind unit + default click actions.
	if opts.unit then setAttr(self, "unit", opts.unit) end

	-- Default click bindings (applied on first Acquire only).
	if not self._clicksWired then
		self:SetClickAction("LeftButton",   "target")
		self:SetClickAction("RightButton",  "menu")
		self:SetClickAction("MiddleButton", "focus")
		self._clicksWired = true
	end

	frame:SetScript("PreClick", function(_, button, down)
		self:Fire("PreClick", button, down)
	end)
	frame:SetScript("PostClick", function(_, button, down)
		self:Fire("PostClick", button, down)
	end)

	if frame.RegisterForClicks then
		frame:RegisterForClicks("AnyUp", "AnyDown")
	end
end

-- ----- Typed attribute wrappers ---------------------------------------

function mixin:SetUnit(unit)
	setAttr(self, "unit", unit)
end

function mixin:GetUnit()
	return self._frame:GetAttribute("unit")
end

-- Map (mouseButton, action[, modifier]) to a SetAttribute call. The
-- attribute name format follows Blizzard's secure-template convention:
--   type1 / type2 / type3 / type4 / type5 for plain button bindings
--   shift-type1 / ctrl-type1 / alt-type1 etc. for modifier-prefixed
--   *type1 etc. for "any unmodified" wildcard (rarely used)
function mixin:SetClickAction(mouseButton, action, modifier)
	local key = CLICK_KEY[mouseButton]
	if not key then return end
	if modifier and modifier ~= "" then
		key = modifier .. "-" .. key
	end
	setAttr(self, key, action)
end

function mixin:Clear()
	-- Clear the unit + standard click bindings. Consumers who installed
	-- custom modifier bindings have to clear those themselves.
	setAttr(self, "unit",  nil)
	setAttr(self, "type1", nil)
	setAttr(self, "type2", nil)
	setAttr(self, "type3", nil)
end

function mixin:SetText(text)
	if self._nameFs then self._nameFs:SetText(self:_resolveText(text or "")) end
end

function mixin:GetText()
	return self._nameFs and self._nameFs:GetText() or ""
end

local function reset(self)
	if self.Clear then self:Clear() end
	if self._nameFs then self._nameFs:SetText("") end
	-- Don't reset _clicksWired; the wiring stays for the next Acquire
	-- because the frame's attribute table isn't cleared by SetAttribute(_,nil).
	-- Subsequent Acquire's SetClickAction calls will re-set them anyway.
end

Core:RegisterWidget("UnitButton", {
	frameType = "Button",
	template  = "SecureUnitButtonTemplate, BackdropTemplate",
	mixin     = mixin,
	pool      = true,
	secure    = true,
	prewarm   = 8,
	reset     = reset,
})
