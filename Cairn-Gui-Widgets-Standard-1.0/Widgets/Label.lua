--[[
Cairn-Gui-Widgets-Standard-1.0 / Widgets / Label

A static text widget. The simplest widget in the bundle: a Frame with a
single FontString filling its bounds. No primitives, no events, no
interactive state. It is the workhorse for static UI text -- headings,
field labels in forms, status messages, helper text under inputs.

Public API:

	lbl = Cairn.Gui:Acquire("Label", parent, {
		text    = "Hello",
		variant = "body",       -- one of body / heading / small / muted /
		                        -- danger / success / warning / on_accent
		align   = "left",       -- "left" / "center" / "right"
		wrap    = false,        -- enable WoW word-wrap
		width   = 200,          -- explicit width (otherwise from intrinsic)
		height  = 24,           -- explicit height (otherwise from intrinsic)
	})

	lbl.Cairn:SetText("Save changes")
	lbl.Cairn:GetText()
	lbl.Cairn:SetVariant("heading")
	lbl.Cairn:GetVariant()
	lbl.Cairn:SetAlign("center")

Variants (font + color):

	body       font.body    + color.fg.text          -- default body text
	heading    font.heading + color.fg.text          -- larger, for titles
	small      font.small   + color.fg.text.muted    -- helper / caption
	muted      font.body    + color.fg.text.muted    -- secondary text
	danger     font.body    + color.fg.text.danger   -- error messages
	success    font.body    + color.fg.text.success  -- confirmation
	warning    font.body    + color.fg.text.warning  -- caution
	on_accent  font.body    + color.fg.text.on_accent -- text on accent bg

Tokens consumed:
	font.{body, heading, small}
	color.fg.text[.{muted, disabled, on_accent, danger, success, warning}]

Pool: enabled. Labels are very common.

Sizing notes:
	The Label's GetIntrinsicSize returns the rendered text's natural size.
	When inside a layout (Stack / Fill / etc.), the layout assigns frame
	dimensions; the FontString fills the frame, and SetJustifyH (driven by
	the `align` opt) determines horizontal alignment within that space.

	If you want a multi-line label that wraps to a fixed width, set
	opts.wrap = true and opts.width to the desired pixel width. Height
	will then come from the wrapped string's height.

Status: Day 12. Standalone Label only. No automatic dynamic resizing
when text changes (call layout's RelayoutNow if container needs a
recompute after a long-text update).
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-1.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W = 100
local DEFAULT_H = 16

-- ----- Variant -> token mapping ----------------------------------------

local VARIANTS = {
	body      = { font = "font.body",    color = "color.fg.text"             },
	heading   = { font = "font.heading", color = "color.fg.text"             },
	small     = { font = "font.small",   color = "color.fg.text.muted"       },
	muted     = { font = "font.body",    color = "color.fg.text.muted"       },
	danger    = { font = "font.body",    color = "color.fg.text.danger"      },
	success   = { font = "font.body",    color = "color.fg.text.success"     },
	warning   = { font = "font.body",    color = "color.fg.text.warning"     },
	on_accent = { font = "font.body",    color = "color.fg.text.on_accent"   },
}

local DEFAULT_VARIANT = "body"

-- ----- Internal: apply variant to FontString ---------------------------

local function applyVariant(self, variantName)
	local spec = VARIANTS[variantName] or VARIANTS[DEFAULT_VARIANT]
	self._variant = (VARIANTS[variantName] and variantName) or DEFAULT_VARIANT

	if not self._text then return end

	local font = self:ResolveToken(spec.font)
	if type(font) == "table" then
		self._text:SetFont(font.face, font.size, font.flags or "")
	end

	local color = self:ResolveToken(spec.color)
	if type(color) == "table" then
		self._text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
	end
end

-- ----- Label mixin -----------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	-- FontString fills the frame so SetJustifyH alignment works against
	-- the frame's width when a layout assigns one.
	if not self._text then
		self._text = frame:CreateFontString(nil, "OVERLAY")
		self._text:SetAllPoints(frame)
	end

	applyVariant(self, opts.variant or DEFAULT_VARIANT)

	-- Justify (default left for readability of long labels).
	local align = (opts.align or "left"):upper()
	if align ~= "LEFT" and align ~= "CENTER" and align ~= "RIGHT" then
		align = "LEFT"
	end
	self._text:SetJustifyH(align)
	self._text:SetJustifyV("MIDDLE")
	self._text:SetWordWrap(opts.wrap and true or false)

	-- Set text BEFORE measuring intrinsic size (string measurement reads
	-- the current text).
	self._text:SetText(opts.text or "")

	-- Size: explicit dimensions win; otherwise size to fit the rendered
	-- string. Layout strategies will override anyway.
	local iw, ih = self:GetIntrinsicSize()
	frame:SetSize(opts.width or iw or DEFAULT_W, opts.height or ih or DEFAULT_H)
end

-- ----- Public methods --------------------------------------------------

function mixin:SetText(text)
	if self._text then
		self._text:SetText(text or "")
	end
end

function mixin:GetText()
	return self._text and self._text:GetText() or ""
end

function mixin:SetVariant(variantName)
	if not VARIANTS[variantName] then
		error(("SetVariant: %q is not a known Label variant"):format(tostring(variantName)), 2)
	end
	applyVariant(self, variantName)
end

function mixin:GetVariant()
	return self._variant or DEFAULT_VARIANT
end

function mixin:SetAlign(align)
	if not self._text then return end
	align = (align or "left"):upper()
	if align ~= "LEFT" and align ~= "CENTER" and align ~= "RIGHT" then
		error(("SetAlign: %q must be left / center / right"):format(tostring(align)), 2)
	end
	self._text:SetJustifyH(align)
end

function mixin:GetAlign()
	return self._text and self._text:GetJustifyH() or "LEFT"
end

-- Override Base:GetIntrinsicSize. Returns the rendered string's natural
-- dimensions. Used by layouts to size the Label's frame on relayout.
function mixin:GetIntrinsicSize()
	if not self._text then return DEFAULT_W, DEFAULT_H end
	local sw = self._text:GetStringWidth()
	local sh = self._text:GetStringHeight()
	if not sw or sw <= 0 then return DEFAULT_W, DEFAULT_H end
	return math.ceil(sw), math.ceil(sh or DEFAULT_H)
end

-- ----- Pool reset ------------------------------------------------------

local function reset(self)
	if self._text then
		self._text:SetText("")
	end
	self._variant = nil
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("Label", {
	frameType = "Frame",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
