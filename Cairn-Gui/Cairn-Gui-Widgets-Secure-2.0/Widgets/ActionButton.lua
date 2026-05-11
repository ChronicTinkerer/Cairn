--[[
Cairn-Gui-Widgets-Secure-2.0 / Widgets / ActionButton

A secure clickable button that casts a spell, uses an item, runs a
macro, or invokes any other Blizzard SecureActionButtonTemplate-driven
action. All mutations go through the combat queue (lib.Combat) so the
public API is safe to call during combat -- the call queues, drains on
combat exit, and the button starts behaving with the new attributes.

Public API on an ActionButton widget:

	btn = Cairn.Gui:Acquire("ActionButton", parent, {
		type     = "spell" | "item" | "macro" | "macrotext" | ...
		spell    = "Fireball",     -- for type="spell"
		item     = "Heartstone",   -- for type="item"
		macro    = "Heroic Strike",-- for type="macro" (named)
		macrotext= "/cast Mount",  -- for type="macrotext" (inline)
		unit     = "player",       -- target context
		width    = 36,
		height   = 36,
	})

	btn.Cairn:SetSpell("Frostbolt")             -- queued during combat
	btn.Cairn:SetItem("Hearthstone")            -- queued during combat
	btn.Cairn:SetMacroText("/cast [@target] Heal")  -- queued during combat
	btn.Cairn:SetType("spell")                  -- queued during combat
	btn.Cairn:SetUnit("player")                 -- queued during combat
	btn.Cairn:Clear()                            -- removes spell/item/macro

	btn.Cairn:On("PreClick",  function(w, mouseButton, down) ... end)
	btn.Cairn:On("PostClick", function(w, mouseButton, down) ... end)

Combat behavior

	The full Blizzard rule: SetAttribute on a secure frame taints during
	combat. Every typed wrapper above goes through lib.Combat:Queue,
	which runs the call immediately when not in combat and queues it for
	drain-on-combat-exit when in combat. Read-only methods (GetSpell,
	GetType, IsCurrentlyHeld, etc.) are unaffected.

	Visual state (icon, cooldown swipe, charge count) is NOT queued.
	Those are FontString / Texture mutations on UI-only sub-elements,
	which don't taint. They update immediately regardless of combat.

Tokens consumed (resolved through theme cascade):

	color.bg.button[.{hover, pressed, disabled}]       -- bg state machine
	color.border.default                                -- 1px border
	color.fg.text                                       -- charge / count text

Pool: enabled (def.pool = true via def.secure default). Pre-warmed: 8
instances created at PLAYER_LOGIN + 0.5s so early Acquire calls don't
trigger CreateFrame during combat.

Status

	Day 17. v1: spell / item / macro / macrotext types via the standard
	Blizzard secure attribute set. Cooldown texture stub (Cooldown frame
	parented to the button; consumer updates SetCooldown directly).
	Charge / stack count not displayed in v1; consumer can hook the
	UNIT_AURA / SPELL_UPDATE_CHARGES events themselves and SetText on
	btn._countFs (exposed for that purpose).
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Secure-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

local Combat = Core.Combat  -- might be nil during file load on broken setups;
                            -- typed wrappers below tolerate it gracefully.

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W = 36
local DEFAULT_H = 36

-- ----- ActionButton mixin ---------------------------------------------

local mixin = {}

-- Internal helper: SetAttribute via combat queue when available, direct
-- otherwise. We tolerate Combat being absent so a paranoid consumer
-- could disable lib.Combat for testing without breaking the widget.
local function setAttr(self, name, value)
	local frame = self._frame
	if not frame then return end
	if Combat and Combat.Queue then
		Combat:Queue(frame, "SetAttribute", name, value)
	else
		if frame.SetAttribute then frame:SetAttribute(name, value) end
	end
end

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame
	frame:SetSize(opts.width or DEFAULT_W, opts.height or DEFAULT_H)

	-- Background + border. Standard hover/press state machine drives
	-- the visual on user input. NOT queued (these are UI-only textures).
	self:DrawRect("bg", {
		default    = "color.bg.button",
		hover      = "color.bg.button.hover",
		pressed    = "color.bg.button.pressed",
		disabled   = "color.bg.button.disabled",
		transition = "duration.fast",
	})
	self:DrawBorder("frame", "color.border.default", { width = 1 })

	-- Icon: the spell/item icon. Consumer can override via opts.icon
	-- (atlas key or file path) or it'll be filled from the spell info
	-- automatically by the consumer's UNIT-event handlers.
	if opts.icon then
		self:DrawIcon("icon", opts.icon, {
			size   = math.min(opts.width or DEFAULT_W, opts.height or DEFAULT_H) - 4,
			anchor = "CENTER",
		})
	end

	-- Cooldown overlay frame. Standard CooldownFrameTemplate; the
	-- consumer wires SetCooldown / OnCooldownDone via the existing
	-- Blizzard API. We just build it and expose it.
	if not self._cooldown then
		self._cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
		self._cooldown:SetAllPoints(frame)
	end

	-- Charge / stack count FontString in the bottom-right corner.
	if not self._countFs then
		self._countFs = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		self._countFs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
		self._countFs:SetText("")
	end

	-- Apply initial attributes from opts. Each goes through the queue
	-- so a fresh-from-pre-warm widget picked up during combat doesn't
	-- taint just because it's being initialized.
	if opts.type      then setAttr(self, "type",      opts.type)      end
	if opts.spell     then setAttr(self, "spell",     opts.spell)     end
	if opts.item      then setAttr(self, "item",      opts.item)      end
	if opts.macro     then setAttr(self, "macro",     opts.macro)     end
	if opts.macrotext then setAttr(self, "macrotext", opts.macrotext) end
	if opts.unit      then setAttr(self, "unit",      opts.unit)      end

	-- Bridge Blizzard's PreClick / PostClick to Cairn semantic events.
	-- These are UI events fired BEFORE/AFTER the secure click handler;
	-- subscribing to them is safe even during combat.
	frame:SetScript("PreClick", function(_, button, down)
		self:Fire("PreClick", button, down)
	end)
	frame:SetScript("PostClick", function(_, button, down)
		self:Fire("PostClick", button, down)
	end)

	-- Register both up and down clicks so consumers can wire either.
	-- AnyDown is required for some action types (e.g., cast-on-keydown
	-- mode in Blizzard's options).
	if frame.RegisterForClicks then
		frame:RegisterForClicks("AnyUp", "AnyDown")
	end
end

-- ----- Typed attribute wrappers ---------------------------------------
-- Each wrapper is a thin call to setAttr; the queue path handles
-- combat-time deferral. Public API kept ergonomic (SetSpell vs raw
-- SetAttribute("spell", ...)) per Decision 8's guidance.

function mixin:SetSpell(name)     setAttr(self, "spell",     name) end
function mixin:SetItem(name)      setAttr(self, "item",      name) end
function mixin:SetMacro(name)     setAttr(self, "macro",     name) end
function mixin:SetMacroText(text) setAttr(self, "macrotext", text) end
function mixin:SetType(t)         setAttr(self, "type",      t)    end
function mixin:SetUnit(u)         setAttr(self, "unit",      u)    end

function mixin:Clear()
	-- Reset all action-defining attributes to nil. Each goes through
	-- the queue so even a clear-during-combat is safe.
	setAttr(self, "type",      nil)
	setAttr(self, "spell",     nil)
	setAttr(self, "item",      nil)
	setAttr(self, "macro",     nil)
	setAttr(self, "macrotext", nil)
end

-- ----- Read-only inspectors -------------------------------------------

function mixin:GetType()      return self._frame:GetAttribute("type")      end
function mixin:GetSpell()     return self._frame:GetAttribute("spell")     end
function mixin:GetItem()      return self._frame:GetAttribute("item")      end
function mixin:GetMacro()     return self._frame:GetAttribute("macro")     end
function mixin:GetMacroText() return self._frame:GetAttribute("macrotext") end
function mixin:GetUnit()      return self._frame:GetAttribute("unit")      end

-- Convenience accessors.
function mixin:GetCooldown() return self._cooldown end
function mixin:SetCount(text)
	if self._countFs then self._countFs:SetText(text or "") end
end

-- ----- Pool reset ------------------------------------------------------

local function reset(self)
	-- Clear all attributes so the next consumer doesn't inherit a spell
	-- from the previous Acquire. The setAttr path is queue-aware, so
	-- this is safe even if Release is called during combat (rare; usually
	-- Release happens at addon teardown which is post-combat).
	if self.Clear then self:Clear() end
	-- Clear the count text + cooldown.
	if self._countFs then self._countFs:SetText("") end
	if self._cooldown and self._cooldown.Clear then self._cooldown:Clear() end
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("ActionButton", {
	frameType = "Button",
	template  = "SecureActionButtonTemplate, BackdropTemplate",
	mixin     = mixin,
	pool      = true,    -- secure widgets default to pooled per Decision 8
	secure    = true,
	prewarm   = 8,
	reset     = reset,
})
