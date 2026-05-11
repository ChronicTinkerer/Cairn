--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / EditBox

Text input. Single-line by default; multi-line via opts.multiline. Ships
with placeholder support, focus ring (border swaps to focus color while
the field has keyboard focus), and the usual semantic events.

Public API:

	eb = Cairn.Gui:Acquire("EditBox", parent, {
		width       = 200,
		height      = 24,                       -- single-line default
		multiline   = false,                    -- default false
		text        = "",                       -- initial text
		placeholder = "Type here...",           -- gray hint shown when empty
		bg          = "color.bg.button",        -- input bg (token spec)
		border      = "color.border.default",
		borderWidth = 1,
		maxLetters  = 0,                        -- 0 = unlimited
		autoFocus   = false,                    -- focus on Acquire
		numeric     = false,                    -- digits only
		password    = false,                    -- mask input
	})

	eb.Cairn:SetText("hello")
	eb.Cairn:GetText()
	eb.Cairn:Focus()                            -- aka SetFocus
	eb.Cairn:Unfocus()                          -- aka ClearFocus
	eb.Cairn:HasFocus()
	eb.Cairn:SetEnabled(false)
	eb.Cairn:HighlightText()                    -- select all
	eb.Cairn:SetPlaceholder("...")

	eb.Cairn:On("TextChanged",  function(w, text) ... end)
	eb.Cairn:On("EnterPressed", function(w, text) ... end)
	eb.Cairn:On("EscapePressed",function(w) ... end)
	eb.Cairn:On("FocusGained",  function(w) ... end)
	eb.Cairn:On("FocusLost",    function(w) ... end)

Multi-line behavior

	When opts.multiline is true the EditBox accepts newlines and wraps
	at its width. Multi-line content that exceeds the height is NOT
	auto-scrolled in v1; wrap the EditBox in a ScrollFrame if you need
	scroll-on-overflow. (We don't auto-wrap because some consumers want
	a fixed-size text area without a scroll affordance.)

Focus ring

	On focus gain, the border re-paints to `color.border.focus` (a
	bright accent). On focus loss, it returns to the default border
	token (or whatever the consumer passed). The bg is unchanged.

Tokens consumed

	color.bg.button              (default input bg if opts.bg omitted)
	color.border.default         (default unfocused border)
	color.border.focus           (focused border)
	color.fg.text                (entered text color)
	color.fg.text.muted          (placeholder text color)
	color.fg.text.disabled       (text color when disabled)
	font.body                    (text font)

Pool: enabled. Forms recycle EditBoxes.

Status

	Day 16. v1: single-line + multi-line, placeholder, focus ring,
	standard events, numeric / password / maxLetters opts pass through
	to the Blizzard EditBox primitives unchanged. No undo stack, no
	auto-completion suggestions, no input mask formatting. All
	deferrable to a follow-up bundle (Cairn-Gui-Widgets-Forms).
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_W      = 200
local DEFAULT_H_S    = 24    -- single-line height
local DEFAULT_H_M    = 80    -- multi-line height
local PAD_X          = 6
local PAD_Y          = 4

-- ----- Helpers ---------------------------------------------------------

local function color(self, token)
	local c = self:ResolveToken(token)
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end
	return 1, 1, 1, 1
end

-- Apply text color from a token to the EditBox + the placeholder. Skips
-- nil values gracefully so a missing token doesn't crash.
local function applyTextColor(self, token)
	local r, g, b, a = color(self, token)
	if self._frame.SetTextColor then
		self._frame:SetTextColor(r, g, b, a)
	end
end

-- Show or hide the placeholder based on current text + focus state.
-- Hidden when text is non-empty OR when focused.
local function refreshPlaceholder(self)
	if not self._placeholderFS then return end
	local text = self._frame:GetText() or ""
	local hasFocus = self._frame:HasFocus() or false
	self._placeholderFS:SetShown(text == "" and not hasFocus and self._placeholderText ~= nil)
end

-- ----- EditBox mixin ---------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	local multiline = opts.multiline and true or false
	frame:SetMultiLine(multiline)
	frame:SetSize(opts.width  or DEFAULT_W,
	              opts.height or (multiline and DEFAULT_H_M or DEFAULT_H_S))
	frame:SetAutoFocus(opts.autoFocus and true or false)
	frame:SetMaxLetters(opts.maxLetters or 0)
	frame:SetNumeric(opts.numeric and true or false)
	frame:SetPassword(opts.password and true or false)
	frame:EnableMouse(true)

	-- Inset the editable text region so it doesn't kiss the border.
	frame:SetTextInsets(PAD_X, PAD_X, PAD_Y, PAD_Y)

	-- Apply the body font. SetFont's third arg is mandatory on 120005.
	local font = self:ResolveToken("font.body")
	if font then
		frame:SetFont(font.face, font.size, font.flags or "")
	end

	-- Background + border via primitives. Border is redrawn on focus
	-- changes so we save the unfocused token for restoration.
	self._bgToken      = opts.bg     or "color.bg.button"
	self._borderToken  = opts.border or "color.border.default"
	self._borderWidth  = opts.borderWidth or 1

	self:DrawRect("bg", self._bgToken)
	self:DrawBorder("frame", self._borderToken, { width = self._borderWidth })

	applyTextColor(self, "color.fg.text")

	-- Placeholder FontString. Created lazily and reused.
	self._placeholderText = opts.placeholder
	if opts.placeholder then
		if not self._placeholderFS then
			self._placeholderFS = frame:CreateFontString(nil, "OVERLAY")
			self._placeholderFS:SetPoint("TOPLEFT",     frame, "TOPLEFT",     PAD_X,  -PAD_Y)
			self._placeholderFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_X,  PAD_Y)
			self._placeholderFS:SetJustifyH("LEFT")
			self._placeholderFS:SetJustifyV(multiline and "TOP" or "MIDDLE")
		end
		if font then
			self._placeholderFS:SetFont(font.face, font.size, font.flags or "")
		end
		local r, g, b, a = color(self, "color.fg.text.muted")
		self._placeholderFS:SetTextColor(r, g, b, a)
		self._placeholderFS:SetText(self:_resolveText(opts.placeholder))
	elseif self._placeholderFS then
		self._placeholderFS:SetText("")
		self._placeholderFS:Hide()
	end

	-- Initial text. Resolve L10n prefix.
	frame:SetText(self:_resolveText(opts.text or ""))

	-- ----- Native -> Cairn event bridges ---------------------------------
	-- Note: in modern WoW retail, OnTextChanged is not reliably fired for
	-- programmatic SetText() calls; this bridge primarily catches user
	-- typing. Programmatic-path TextChanged is fired explicitly from
	-- mixin:SetText to maintain the public contract. The _suppress flag
	-- prevents double-fire when OnTextChanged DOES fire on SetText (older
	-- clients or some corner cases).
	frame:SetScript("OnTextChanged", function(_, userInput)
		refreshPlaceholder(self)
		if self._suppressOnTextChanged then return end
		self:Fire("TextChanged", frame:GetText() or "", userInput and true or false)
	end)
	frame:SetScript("OnEnterPressed", function()
		self:Fire("EnterPressed", frame:GetText() or "")
		if not multiline then frame:ClearFocus() end
	end)
	frame:SetScript("OnEscapePressed", function()
		self:Fire("EscapePressed")
		frame:ClearFocus()
	end)
	frame:SetScript("OnEditFocusGained", function()
		-- Repaint border with focus token. Re-Drawing the same primitive
		-- name reuses the underlying textures.
		self:DrawBorder("frame", "color.border.focus", { width = self._borderWidth })
		refreshPlaceholder(self)
		self:Fire("FocusGained")
	end)
	frame:SetScript("OnEditFocusLost", function()
		self:DrawBorder("frame", self._borderToken, { width = self._borderWidth })
		refreshPlaceholder(self)
		self:Fire("FocusLost")
	end)

	refreshPlaceholder(self)
end

-- ----- Public methods --------------------------------------------------

function mixin:SetText(text)
	text = self:_resolveText(text or "")
	-- Suppress the OnTextChanged bridge for the duration of the native
	-- SetText so we fire TextChanged exactly once even if Blizzard's
	-- OnTextChanged decides to fire. Then explicitly fire TextChanged
	-- ourselves (modern retail's OnTextChanged is unreliable for
	-- programmatic SetText, so we can't depend on the bridge alone).
	self._suppressOnTextChanged = true
	self._frame:SetText(text)
	self._suppressOnTextChanged = false
	refreshPlaceholder(self)
	self:Fire("TextChanged", text, false)
	-- EditBox is usually fixed-size from opts.width, but a parent layout
	-- (e.g. Form) can read intrinsic size for label-column alignment, so
	-- invalidate to be safe.
	self:_invalidateParentLayout()
end

function mixin:GetText()
	return self._frame:GetText() or ""
end

function mixin:Focus()
	self._frame:SetFocus()
end

function mixin:Unfocus()
	self._frame:ClearFocus()
end

function mixin:HasFocus()
	return self._frame:HasFocus() or false
end

function mixin:HighlightText(from, to)
	self._frame:HighlightText(from or 0, to or -1)
end

function mixin:SetPlaceholder(text)
	text = text and self:_resolveText(text) or text
	self._placeholderText = text
	-- Placeholder is shown when the field is empty; its rendered string
	-- can affect what a parent measures if the EditBox uses intrinsic.
	self:_invalidateParentLayout()
	if text and not self._placeholderFS then
		-- Lazy-create on first SetPlaceholder if OnAcquire didn't.
		self._placeholderFS = self._frame:CreateFontString(nil, "OVERLAY")
		self._placeholderFS:SetPoint("TOPLEFT",     self._frame, "TOPLEFT",     PAD_X,  -PAD_Y)
		self._placeholderFS:SetPoint("BOTTOMRIGHT", self._frame, "BOTTOMRIGHT", -PAD_X,  PAD_Y)
		self._placeholderFS:SetJustifyH("LEFT")
		local font = self:ResolveToken("font.body")
		if font then self._placeholderFS:SetFont(font.face, font.size, font.flags or "") end
		local r, g, b, a = color(self, "color.fg.text.muted")
		self._placeholderFS:SetTextColor(r, g, b, a)
	end
	if self._placeholderFS then
		self._placeholderFS:SetText(text or "")
	end
	refreshPlaceholder(self)
end

-- Disabled state: visually dim and ignore input. Uses Blizzard's native
-- EnableKeyboard/EnableMouse switches; primitives don't repaint
-- automatically because the bg/border primitives don't have a
-- "disabled" state variant on EditBox in v1.
function mixin:SetEnabled(enabled)
	enabled = enabled and true or false
	self._disabled = not enabled
	self._frame:EnableKeyboard(enabled)
	self._frame:EnableMouse(enabled)
	if enabled then
		applyTextColor(self, "color.fg.text")
	else
		applyTextColor(self, "color.fg.text.disabled")
		self._frame:ClearFocus()
	end
end

-- ----- Pool reset ------------------------------------------------------

local function reset(self)
	-- Drop any text the previous owner left behind.
	if self._frame and self._frame.SetText then
		self._frame:SetText("")
	end
	if self._placeholderFS then
		self._placeholderFS:Hide()
		self._placeholderFS:SetText("")
	end
	self._placeholderText = nil
	self._bgToken         = nil
	self._borderToken     = nil
	self._disabled        = nil
	-- Clear native scripts. OnAcquire reattaches them; clearing here
	-- prevents a stale subscriber's closure from firing on the recycled
	-- instance before OnAcquire runs.
	if self._frame then
		self._frame:SetScript("OnTextChanged",     nil)
		self._frame:SetScript("OnEnterPressed",    nil)
		self._frame:SetScript("OnEscapePressed",   nil)
		self._frame:SetScript("OnEditFocusGained", nil)
		self._frame:SetScript("OnEditFocusLost",   nil)
	end
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("EditBox", {
	frameType = "EditBox",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
