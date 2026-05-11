--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Checkbox

Boolean toggle. A row containing a 16x16 box on the left and a label
on the right; the whole row is clickable, with subtle hover/press
feedback. When checked, an accent-tinted check glyph is drawn inside
the box.

Public API on a Checkbox widget:

	cb = Cairn.Gui:Acquire("Checkbox", parent, {
		text    = "Show grid",   -- label text
		checked = false,         -- initial value
		width   = 200,           -- row width  (default 200)
		height  = 24,            -- row height (default 24)
	})

	cb.Cairn:SetChecked(true)         -- update value (fires Toggled if it changes)
	cb.Cairn:IsChecked() -> bool       -- read value
	cb.Cairn:Toggle()                   -- flip value (fires Toggled)
	cb.Cairn:SetText("Show grid")
	cb.Cairn:GetText()
	cb.Cairn:SetEnabled(false)         -- gray out and ignore clicks
	cb.Cairn:On("Click", function(widget, mouseButton, newValue) end)
	cb.Cairn:On("Toggled", function(widget, newValue) end)

Events:
	Click    fires on every mouse click while enabled. Args: mouseButton,
	         newCheckedValue (after the toggle).
	Toggled  fires when the checked value actually changes (programmatic
	         changes via SetChecked also fire it). Arg: newCheckedValue.

Tokens consumed (resolved through theme cascade):
	color.bg.button.ghost.hover     -- whole-row hover bg
	color.bg.button.ghost.pressed   -- whole-row pressed bg
	color.bg.button                  -- 16x16 box surface
	color.border.default             -- 16x16 box border
	color.fg.text                    -- label text
	color.accent.primary             -- check glyph tint
	texture.icon.check               -- check glyph atlas/path
	font.body                        -- label font

The 16x16 box uses raw CreateTexture for bg + border, matching Button's
precedent of using raw CreateFontString for its label. The whole-row
hover bg goes through the primitive system (DrawRect with state-variant)
so the state machine auto-engages on hover/press. The check glyph goes
through the new DrawIcon primitive (Day 14) and is shown/hidden via
SetPrimitiveShown on toggle.

Pool: enabled. Settings panels recycle Checkboxes heavily. Reset clears
text, checked state, and re-hides the glyph for the next Acquire.

Status: Day 14 v1. Future enhancements: variant set (e.g. switch-style),
indeterminate state, keyboard-focus ring.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_WIDTH    = 200
local DEFAULT_HEIGHT   = 24
local BOX_SIZE         = 16
local BOX_OFFSET_X     = 4   -- box left edge inset from row LEFT
local BORDER_WIDTH     = 1
local CHECK_SIZE       = 12  -- glyph edge; box has 2px inset on each side
local LABEL_OFFSET_X   = BOX_OFFSET_X + BOX_SIZE + 4  -- box + 4px gap

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"

-- ----- Internal: build the 16x16 box (run once per frame instance) ----
-- Stored on the Cairn table so a pool re-Acquire reuses the textures
-- rather than creating fresh ones.

local function ensureBox(self)
	if self._box_bg then return end
	local frame = self._frame

	-- Box BG: a single white square positioned LEFT of the row.
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE_TEX)
	bg:SetSize(BOX_SIZE, BOX_SIZE)
	bg:SetPoint("LEFT", frame, "LEFT", BOX_OFFSET_X, 0)
	self._box_bg = bg

	-- Box BORDER: 4 thin edge textures anchored to the box bg.
	local edges = {}
	for i = 1, 4 do
		edges[i] = frame:CreateTexture(nil, "BORDER")
		edges[i]:SetTexture(WHITE_TEX)
	end
	-- Top.
	edges[1]:SetPoint("TOPLEFT",  bg, "TOPLEFT",  0, 0)
	edges[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 0, 0)
	edges[1]:SetHeight(BORDER_WIDTH)
	-- Right.
	edges[2]:SetPoint("TOPRIGHT",    bg, "TOPRIGHT",    0, 0)
	edges[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
	edges[2]:SetWidth(BORDER_WIDTH)
	-- Bottom.
	edges[3]:SetPoint("BOTTOMLEFT",  bg, "BOTTOMLEFT",  0, 0)
	edges[3]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
	edges[3]:SetHeight(BORDER_WIDTH)
	-- Left.
	edges[4]:SetPoint("TOPLEFT",    bg, "TOPLEFT",    0, 0)
	edges[4]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
	edges[4]:SetWidth(BORDER_WIDTH)
	self._box_border = edges
end

-- Re-resolve the box's color tokens against the current theme cascade.
-- Called from OnAcquire after ensureBox; safe to call repeatedly.
local function applyBoxColors(self)
	local boxBg = self:ResolveToken("color.bg.button")
	if type(boxBg) == "table" and self._box_bg then
		self._box_bg:SetVertexColor(boxBg[1] or 1, boxBg[2] or 1, boxBg[3] or 1, boxBg[4] or 1)
	end
	local boxBorder = self:ResolveToken("color.border.default")
	if type(boxBorder) == "table" and self._box_border then
		for _, e in ipairs(self._box_border) do
			e:SetVertexColor(boxBorder[1] or 1, boxBorder[2] or 1, boxBorder[3] or 1, boxBorder[4] or 1)
		end
	end
end

-- ----- Checkbox mixin --------------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	-- Default size.
	frame:SetSize(opts.width or DEFAULT_WIDTH, opts.height or DEFAULT_HEIGHT)

	-- Whole-row hover/press feedback. Transparent default keeps the row
	-- bg-free so it composes with whatever container the user nests it in.
	-- Using ghost-variant tokens (translucent white-on-anything) so the
	-- hover effect reads on light AND dark surfaces.
	self:DrawRect("rowbg", {
		default  = { 0, 0, 0, 0 },
		hover    = "color.bg.button.ghost.hover",
		pressed  = "color.bg.button.ghost.pressed",
		disabled = { 0, 0, 0, 0 },
	})

	-- 16x16 box (raw textures; small visual element, not a full-frame
	-- primitive). Idempotent: re-Acquire keeps the same textures.
	ensureBox(self)
	applyBoxColors(self)

	-- Check glyph: 12x12 atlas inside the box, accent-tinted. Hidden until
	-- checked. Anchored LEFT with offsetX = box_offset + (box-glyph)/2 so it
	-- centers visually inside the box.
	self:DrawIcon("check", "texture.icon.check", {
		size    = CHECK_SIZE,
		anchor  = "LEFT",
		offsetX = BOX_OFFSET_X + (BOX_SIZE - CHECK_SIZE) / 2,
		offsetY = 0,
		color   = "color.accent.primary",
	})

	-- Label FontString. Reuse if pooled; create fresh otherwise.
	if not self._label then
		self._label = frame:CreateFontString(nil, "OVERLAY")
		self._label:SetPoint("LEFT", frame, "LEFT", LABEL_OFFSET_X, 0)
		self._label:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
		self._label:SetJustifyH("LEFT")
		self._label:SetWordWrap(false)
	end

	-- Apply current theme's body font + text color.
	local font = self:ResolveToken("font.body")
	if font then
		self._label:SetFont(font.face, font.size, font.flags or "")
	end
	local fg = self:ResolveToken("color.fg.text")
	if type(fg) == "table" then
		self._label:SetTextColor(fg[1] or 1, fg[2] or 1, fg[3] or 1, fg[4] or 1)
	end

	-- Initial text + checked state.
	self._label:SetText(self:_resolveText(opts.text or ""))
	self._checked = opts.checked and true or false
	self:SetPrimitiveShown("check", self._checked)

	-- Bridge Blizzard OnClick to a Cairn semantic event AND toggle.
	-- HookScript would chain, but we want to control toggle order here:
	-- toggle first so handlers see the new value via IsChecked.
	frame:SetScript("OnClick", function(_, mouseButton)
		if self._disabled then return end
		self._checked = not self._checked
		self:SetPrimitiveShown("check", self._checked)
		self:Fire("Click", mouseButton, self._checked)
		self:Fire("Toggled", self._checked)
	end)
end

-- ----- Public methods --------------------------------------------------

function mixin:SetText(text)
	if self._label then
		self._label:SetText(self:_resolveText(text or ""))
		-- Row width depends on label width; tell the parent layout to
		-- re-measure.
		self:_invalidateParentLayout()
	end
end

function mixin:GetText()
	return self._label and self._label:GetText() or ""
end

function mixin:IsChecked()
	return self._checked and true or false
end

-- Programmatic value change. Fires Toggled IFF the value actually flipped.
-- Click is NOT fired (no user click occurred).
function mixin:SetChecked(value)
	value = value and true or false
	if self._checked == value then return end
	self._checked = value
	self:SetPrimitiveShown("check", value)
	self:Fire("Toggled", value)
end

function mixin:Toggle()
	self:SetChecked(not self._checked)
end

-- Override Base:GetIntrinsicSize. Width = box + gap + label string;
-- height = max(box, label). Falls back to defaults if the label hasn't
-- laid out yet.
function mixin:GetIntrinsicSize()
	if not self._label then
		return DEFAULT_WIDTH, DEFAULT_HEIGHT
	end
	local sw = self._label:GetStringWidth() or 0
	local sh = self._label:GetStringHeight() or 0
	if sw <= 0 then
		return DEFAULT_WIDTH, DEFAULT_HEIGHT
	end
	local w = LABEL_OFFSET_X + math.ceil(sw) + 4
	local h = math.max(BOX_SIZE + 4, math.ceil(sh) + 4)
	return w, h
end

-- ----- Pool reset ------------------------------------------------------
-- Called by Base:Release at pool-return time.

local function reset(self)
	if self._label then
		self._label:SetText("")
	end
	self._checked = false
	-- The check glyph primitive was shown/hidden during life; hide it now
	-- so the next OnAcquire starts from a known state regardless of what
	-- the previous owner left.
	self:SetPrimitiveShown("check", false)
end

-- ----- Register --------------------------------------------------------

Core:RegisterWidget("Checkbox", {
	frameType = "Button",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
