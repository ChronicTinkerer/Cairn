--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Button

The pilot widget. Pulls together everything Core (Cairn-Gui-2.0) ships:
mixin namespace, Acquire/Release lifecycle, parent/child registry,
theme cascade, drawing primitives with state variants, automatic
hover/press transitions, and the event system.

Public API on a Button widget:

	btn = Cairn.Gui:Acquire("Button", parent, {
		text    = "OK",         -- initial label text
		variant = "primary",    -- one of "default" / "primary" / "danger" / "ghost"
		width   = 100,          -- default 100
		height  = 28,           -- default 28
	})

	btn.Cairn:SetText("Save")        -- update label
	btn.Cairn:GetText()               -- read label
	btn.Cairn:SetVariant("danger")   -- swap variant at runtime
	btn.Cairn:GetVariant()            -- current variant name
	btn.Cairn:On("Click", function(widget, mouseButton)
		-- mouseButton is "LeftButton" / "RightButton" / etc. from Blizzard.
	end)
	btn.Cairn:SetEnabled(false)      -- gray out, ignore clicks visually

Variants

	"default"   - neutral surface, body text. The general-purpose button.
	"primary"   - accent surface (blue in Cairn.Default), white-on-accent
	              text. Use for the recommended action in a group.
	"danger"    - red surface, white-on-accent text. Destructive actions
	              (delete, cancel reservation, sign out, etc.).
	"ghost"     - transparent until hovered. Subtle / icon-only buttons,
	              context menus, low-emphasis actions.

Each variant maps to a set of tokens for bg/border/text. The mapping
is internal to this file; themes adjust visuals by overriding the
underlying tokens (color.bg.button.primary, etc.), not by re-defining
the variant set. Adding a NEW variant currently requires editing this
file; a future RegisterVariant API can lift that out.

Tokens consumed (resolved through theme cascade):
	color.bg.button[.{primary,danger,ghost}].{default,hover,pressed,disabled}
	color.border.{default,accent,danger,subtle}
	color.fg.text[.on_accent]
	font.body

Pool: enabled. Buttons are common, the recycle saves a CreateFrame call.

Status: Day 11 ships variants. Future days bring icon support, tooltip,
loading state, and badge support.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_WIDTH  = 100
local DEFAULT_HEIGHT = 28
local DEFAULT_PAD_X  = 8   -- horizontal padding between text and edges
local DEFAULT_PAD_Y  = 4   -- vertical padding

-- ----- Variant -> token spec mapping ----------------------------------
-- Each variant supplies the token names that the bg, border, and text
-- primitives resolve through. State variants on bg are in the inner
-- table; border and text use single tokens (their colors don't change
-- with state, only with the variant).

local VARIANTS = {
	default = {
		bg = {
			default    = "color.bg.button",
			hover      = "color.bg.button.hover",
			pressed    = "color.bg.button.pressed",
			disabled   = "color.bg.button.disabled",
			transition = "duration.fast",
		},
		border = "color.border.default",
		text   = "color.fg.text",
	},
	primary = {
		bg = {
			default    = "color.bg.button.primary",
			hover      = "color.bg.button.primary.hover",
			pressed    = "color.bg.button.primary.pressed",
			disabled   = "color.bg.button.primary.disabled",
			transition = "duration.fast",
		},
		border = "color.border.accent",
		text   = "color.fg.text.on_accent",
	},
	danger = {
		bg = {
			default    = "color.bg.button.danger",
			hover      = "color.bg.button.danger.hover",
			pressed    = "color.bg.button.danger.pressed",
			disabled   = "color.bg.button.danger.disabled",
			transition = "duration.fast",
		},
		border = "color.border.danger",
		text   = "color.fg.text.on_accent",
	},
	ghost = {
		bg = {
			default    = "color.bg.button.ghost",
			hover      = "color.bg.button.ghost.hover",
			pressed    = "color.bg.button.ghost.pressed",
			disabled   = "color.bg.button.ghost.disabled",
			transition = "duration.fast",
		},
		border = "color.border.subtle",
		text   = "color.fg.text",
	},
}

local DEFAULT_VARIANT = "default"

-- ----- Internal: apply a variant's token spec to the primitives -------

local function applyVariant(self, variantName)
	local spec = VARIANTS[variantName] or VARIANTS[DEFAULT_VARIANT]
	self._variant = (VARIANTS[variantName] and variantName) or DEFAULT_VARIANT

	self:DrawRect("bg", spec.bg)
	self:DrawBorder("frame", spec.border, { width = 1 })

	if self._label then
		local fg = self:ResolveToken(spec.text)
		if type(fg) == "table" then
			self._label:SetTextColor(fg[1] or 1, fg[2] or 1, fg[3] or 1, fg[4] or 1)
		end
	end
end

-- ----- Button mixin ----------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	-- Default size if not provided.
	frame:SetSize(opts.width or DEFAULT_WIDTH, opts.height or DEFAULT_HEIGHT)

	-- Label FontString. Reuse if pooled; create fresh otherwise.
	if not self._label then
		self._label = frame:CreateFontString(nil, "OVERLAY")
		self._label:SetPoint("CENTER", frame, "CENTER", 0, 0)
	end

	-- Apply current theme's body font.
	local font = self:ResolveToken("font.body")
	if font then
		self._label:SetFont(font.face, font.size, font.flags or "")
	end

	-- Apply variant (does the bg + border + text-color work).
	applyVariant(self, opts.variant or DEFAULT_VARIANT)

	-- Initial text from opts. Resolve L10n prefix.
	self._label:SetText(self:_resolveText(opts.text or ""))

	-- Bridge Blizzard's native OnClick to a Cairn semantic event.
	frame:SetScript("OnClick", function(_, button)
		self:Fire("Click", button)
	end)

	-- RegisterForClicks defensively: the Primitives layer's
	-- OnMouseDown / OnMouseUp HookScripts swallow OnClick on Interface
	-- 120005 unless the Button is explicitly registered for the click
	-- type. Default behavior on a bare CreateFrame("Button") is for
	-- LeftButtonUp to fire OnClick, but the hook chain breaks that
	-- default. Registering "AnyUp" here covers left + right + middle
	-- so mixin consumers can dispatch on the `button` arg. Caught by
	-- Vellum/Panel.lua build (per memory: cairn_gui_2_vellum_framework_gaps)
	-- and by Cairn-Media-Browser visibility filter buttons (2026-05-08).
	if frame.RegisterForClicks then
		frame:RegisterForClicks("AnyUp")
	end
end

-- ----- Public methods --------------------------------------------------

function mixin:SetText(text)
	if self._label then
		-- Resolve "@namespace:key" L10n prefix; pass-through for plain strings.
		self._label:SetText(self:_resolveText(text or ""))
		-- Intrinsic width depends on label width; tell the parent layout
		-- to re-measure so siblings re-anchor around the new size.
		self:_invalidateParentLayout()
	end
end

function mixin:GetText()
	return self._label and self._label:GetText() or ""
end

function mixin:SetVariant(variantName)
	if not VARIANTS[variantName] then
		error(("SetVariant: %q is not a known variant (default/primary/danger/ghost)"):format(tostring(variantName)), 2)
	end
	applyVariant(self, variantName)
	-- Variant changes don't usually shift intrinsic width, but text-color
	-- repaints and border swaps can affect padding-aware sizing in custom
	-- variants. Cheap to invalidate.
	self:_invalidateParentLayout()
end

function mixin:GetVariant()
	return self._variant or DEFAULT_VARIANT
end

-- Override Base:GetIntrinsicSize. Width = label string width + padding;
-- height = label string height + padding. Falls back to default size if
-- the label hasn't laid out yet.
function mixin:GetIntrinsicSize()
	if not self._label then
		return DEFAULT_WIDTH, DEFAULT_HEIGHT
	end
	local sw = self._label:GetStringWidth()
	local sh = self._label:GetStringHeight()
	if not sw or sw <= 0 then
		return DEFAULT_WIDTH, DEFAULT_HEIGHT
	end
	return math.ceil(sw) + DEFAULT_PAD_X * 2, math.ceil(sh or 12) + DEFAULT_PAD_Y * 2
end

-- ----- Pool reset ------------------------------------------------------
-- Called by Base:Release at pool-return time. Clear state specific to the
-- previous Acquire so the next Acquire starts clean.

local function reset(self)
	if self._label then
		self._label:SetText("")
	end
	-- _variant gets re-set by OnAcquire on next Acquire; clear here so a
	-- bug in OnAcquire (forgot to set variant) doesn't silently inherit
	-- the previous owner's variant.
	self._variant = nil
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("Button", {
	frameType = "Button",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
