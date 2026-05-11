--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / ScrollFrame

Vertical scrollable container. The ScrollFrame is a viewport with a
content area that can grow taller than the visible region; mouse wheel
and an optional themed scrollbar drive vertical scroll.

Public API:

	sf = Cairn.Gui:Acquire("ScrollFrame", parent, {
		width         = 300,                    -- viewport width (default 300)
		height        = 200,                    -- viewport height (default 200)
		bg            = "color.bg.surface",     -- optional viewport bg
		border        = "color.border.default", -- optional border
		borderWidth   = 1,
		contentHeight = 800,                    -- initial content area height
		showScrollbar = true,                   -- draw a themed scrollbar (default true)
		scrollStep    = 30,                     -- pixels per wheel tick (default 30)
	})

	local content = sf.Cairn:GetContent()       -- Cairn-aware Container
	content.Cairn:SetLayout("Stack", { direction = "vertical", gap = 4, padding = 8 })
	Cairn.Gui:Acquire("Label",  content, { text = "row 1" })
	Cairn.Gui:Acquire("Button", content, { text = "row 2" })

	sf.Cairn:SetContentHeight(1000)             -- update if content grew
	sf.Cairn:GetContentHeight()
	sf.Cairn:GetVerticalScroll()                -- current offset (0 = top)
	sf.Cairn:SetVerticalScroll(y)               -- programmatic scroll (clamps)
	sf.Cairn:ScrollToTop()
	sf.Cairn:ScrollToBottom()

	sf.Cairn:On("Scroll", function(widget, y) ... end)  -- fires per change

Layout

	The ScrollFrame itself does NOT use a layout strategy. Set the layout
	on the CONTENT frame, not on the ScrollFrame. The internal scroll
	plumbing (Blizzard ScrollFrame + scrollbar Frame) is not part of the
	Cairn child registry.

Pool

	NOT pooled. Top-level scrollable containers own internal sub-widgets
	(scroll child Container plus a raw scrollbar Frame); the simplest
	correct path is no pool. Released ScrollFrames cascade-release the
	content Container and hide the outer frame.

Tokens consumed

	color.bg.surface              (optional viewport bg)
	color.border.default          (optional viewport border)
	color.bg.surface              (scrollbar track)
	color.border.default          (scrollbar thumb default)
	color.border.focus            (scrollbar thumb hover)
	color.accent.primary.hover    (scrollbar thumb pressed/dragging)

	No new tokens introduced; reuses existing ones. If a Cairn.Default
	follow-up adds scrollbar-specific tokens, the resolution swaps in
	transparently.

Internal sub-widgets / frames

	_scrollFrame   raw Blizzard ScrollFrame (frameType "ScrollFrame")
	               occupying viewport width minus scrollbar reserve
	_content       Cairn Container; the scroll child; consumer-managed size
	_scrollbar     raw Frame on the right edge, scrollbar reserve wide
	_thumb         raw Button inside _scrollbar; draggable

Status

	Day 16. v1: vertical scroll only, mouse wheel, drag-thumb scrollbar,
	scroll position events. No horizontal scroll, no fade-in scrollbar
	on hover, no virtualization. All deferrable.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

-- ----- Defaults --------------------------------------------------------

local DEFAULT_WIDTH         = 300
local DEFAULT_HEIGHT        = 200
local DEFAULT_SCROLL_STEP   = 30
local SCROLLBAR_RESERVE     = 8       -- width reserved on the right for scrollbar
local THUMB_MIN_HEIGHT      = 16      -- never let the thumb get smaller than this

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"

-- ----- Internal helpers ------------------------------------------------

-- Read a color token through the cascade and return r,g,b,a.
local function color(self, token, fallback)
	local c = self:ResolveToken(token)
	if type(c) == "table" then
		return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
	end
	if fallback then return fallback[1], fallback[2], fallback[3], fallback[4] end
	return 1, 1, 1, 1
end

-- Compute thumb height given viewport height, content height, and track height.
-- Thumb height is the visible-fraction times the track height, clamped to a
-- usable minimum and to the track height itself.
local function computeThumbHeight(viewportH, contentH, trackH)
	if contentH <= viewportH or contentH <= 0 then return trackH end
	local h = trackH * (viewportH / contentH)
	if h < THUMB_MIN_HEIGHT then h = THUMB_MIN_HEIGHT end
	if h > trackH then h = trackH end
	return h
end

-- Position the thumb based on current scroll value.
local function repositionThumb(self)
	local sb        = self._scrollbar
	local thumb     = self._thumb
	if not sb or not thumb then return end

	local viewportH = self._scrollFrame:GetHeight()
	local contentH  = self._contentHeight or viewportH
	local trackH    = sb:GetHeight()
	local thumbH    = computeThumbHeight(viewportH, contentH, trackH)
	thumb:SetHeight(thumbH)

	local maxScroll = math.max(0, contentH - viewportH)
	local maxThumbY = math.max(0, trackH - thumbH)
	local scroll    = self._scrollFrame:GetVerticalScroll() or 0
	local fraction  = (maxScroll > 0) and (scroll / maxScroll) or 0
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", sb, "TOP", 0, -fraction * maxThumbY)

	-- Hide thumb when content fits entirely; show otherwise.
	thumb:SetShown(contentH > viewportH)
end

-- Apply the current visual state's color to the thumb. Called on
-- enter/leave/down/up + once at OnAcquire.
local function applyThumbColor(self, state)
	if not self._thumb_tex then return end
	local r, g, b, a
	if state == "pressed" then
		r, g, b, a = color(self, "color.accent.primary.hover")
	elseif state == "hover" then
		r, g, b, a = color(self, "color.border.focus")
	else
		r, g, b, a = color(self, "color.border.default")
	end
	self._thumb_tex:SetVertexColor(r, g, b, a)
end

-- Build the scrollbar UI on first Acquire. Idempotent: pool re-Acquire
-- reuses the same frames.
local function ensureScrollbar(self)
	if self._scrollbar then return end
	local frame = self._frame

	-- Track Frame
	local sb = CreateFrame("Frame", nil, frame)
	sb:SetWidth(SCROLLBAR_RESERVE)
	sb:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, 0)
	sb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	local trackTex = sb:CreateTexture(nil, "BACKGROUND")
	trackTex:SetTexture(WHITE_TEX)
	trackTex:SetAllPoints(sb)
	local tr, tg, tb, ta = color(self, "color.bg.surface")
	trackTex:SetVertexColor(tr, tg, tb, ta * 0.6)  -- a touch dimmer than panel surfaces
	self._scrollbar     = sb
	self._scrollbar_tex = trackTex

	-- Thumb Button (inside the track)
	local thumb = CreateFrame("Button", nil, sb)
	thumb:SetWidth(SCROLLBAR_RESERVE)
	thumb:RegisterForDrag("LeftButton")
	thumb:EnableMouse(true)
	local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetTexture(WHITE_TEX)
	thumbTex:SetAllPoints(thumb)
	self._thumb     = thumb
	self._thumb_tex = thumbTex

	-- Drag handlers. We capture the cursor's Y at drag start and the
	-- scroll's Y at drag start; OnUpdate translates cursor delta into
	-- scroll delta. Track's UI scale is used so we don't drift on
	-- non-1.0 UI scales.
	thumb:SetScript("OnEnter", function()
		if not thumb._dragging then applyThumbColor(self, "hover") end
	end)
	thumb:SetScript("OnLeave", function()
		if not thumb._dragging then applyThumbColor(self, "default") end
	end)
	thumb:SetScript("OnDragStart", function()
		thumb._dragging   = true
		local _, cursorY  = GetCursorPosition()
		local scale       = sb:GetEffectiveScale()
		thumb._dragStartCursor = cursorY / scale
		thumb._dragStartScroll = self._scrollFrame:GetVerticalScroll() or 0
		applyThumbColor(self, "pressed")
		thumb:SetScript("OnUpdate", function()
			local _, ny    = GetCursorPosition()
			local cy       = ny / sb:GetEffectiveScale()
			local dyScreen = thumb._dragStartCursor - cy   -- + when dragging down
			local viewportH = self._scrollFrame:GetHeight()
			local contentH  = self._contentHeight or viewportH
			local trackH    = sb:GetHeight()
			local thumbH    = computeThumbHeight(viewportH, contentH, trackH)
			local maxThumbY = math.max(1, trackH - thumbH)
			local maxScroll = math.max(0, contentH - viewportH)
			local newScroll = thumb._dragStartScroll + (dyScreen / maxThumbY) * maxScroll
			if newScroll < 0 then newScroll = 0 end
			if newScroll > maxScroll then newScroll = maxScroll end
			self._scrollFrame:SetVerticalScroll(newScroll)
		end)
	end)
	thumb:SetScript("OnDragStop", function()
		thumb._dragging = false
		thumb:SetScript("OnUpdate", nil)
		-- Restore hover state if cursor is still over the thumb, else default.
		if thumb:IsMouseOver() then
			applyThumbColor(self, "hover")
		else
			applyThumbColor(self, "default")
		end
	end)

	applyThumbColor(self, "default")
end

-- ----- ScrollFrame mixin ----------------------------------------------

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	local W = opts.width  or DEFAULT_WIDTH
	local H = opts.height or DEFAULT_HEIGHT
	frame:SetSize(W, H)
	frame:Show()

	self._scrollStep    = opts.scrollStep or DEFAULT_SCROLL_STEP
	self._contentHeight = opts.contentHeight or H

	-- Optional bg / border on the outer frame.
	if opts.bg then
		self:DrawRect("bg", opts.bg)
	end
	if opts.border then
		self:DrawBorder("frame", opts.border, { width = opts.borderWidth or 1 })
	end

	-- ----- Inner Blizzard ScrollFrame (the actual viewport) -------------
	-- Reserve scrollbarReserve px on the right ALWAYS, whether the bar is
	-- shown or not. Reserving avoids layout jitter when content grows past
	-- the viewport and the scrollbar appears.
	local showSB = opts.showScrollbar ~= false
	local sbReserve = showSB and SCROLLBAR_RESERVE or 0

	if not self._scrollFrame then
		self._scrollFrame = CreateFrame("ScrollFrame", nil, frame)
	end
	local sf = self._scrollFrame
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0, 0)
	sf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -sbReserve, 0)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, delta)
		local current = sf:GetVerticalScroll() or 0
		local maxS    = math.max(0, (self._contentHeight or 0) - sf:GetHeight())
		local target  = current - delta * self._scrollStep   -- delta>0 = wheel up
		if target < 0 then target = 0 end
		if target > maxS then target = maxS end
		sf:SetVerticalScroll(target)
	end)
	sf:SetScript("OnVerticalScroll", function(_, offset)
		repositionThumb(self)
		self:Fire("Scroll", offset or 0)
	end)
	sf:SetScript("OnSizeChanged", function()
		repositionThumb(self)
	end)

	-- ----- Content Container (the scroll child) -------------------------
	if not self._content then
		self._content = Core:Acquire("Container", sf, {
			width  = W - sbReserve,
			height = self._contentHeight,
		})
		self._content.Cairn:SetLayoutManual(true)
	else
		self._content:SetSize(W - sbReserve, self._contentHeight)
	end
	sf:SetScrollChild(self._content)

	-- ----- Outer-frame resize propagation -------------------------------
	-- If a consumer SetPoint's the outer frame to fill a parent (rather
	-- than relying on opts.width/height), the outer frame's size changes
	-- AFTER OnAcquire ran and our content Container was sized from the
	-- now-stale defaults. Hook the outer's OnSizeChanged once and keep
	-- the content's width in sync with the viewport's width minus the
	-- scrollbar reserve. Idempotent across pool re-Acquire via the
	-- _outerSizeHooked sentinel.
	self._sbReserve = sbReserve
	if not self._outerSizeHooked then
		frame:HookScript("OnSizeChanged", function(_, ow, _oh)
			if not self._content then return end
			local reserve = self._sbReserve or 0
			local newW = math.max(1, ow - reserve)
			local _, ch = self._content:GetSize()
			if not ch or ch <= 0 then ch = self._contentHeight or ow end
			self._content:SetSize(newW, ch)
			-- Inner Blizzard ScrollFrame is anchored via SetPoint to the
			-- outer, so it tracks automatically. Thumb repositions next
			-- frame via the inner SF's own OnSizeChanged hook.
		end)
		self._outerSizeHooked = true
	end

	-- ----- Scrollbar (optional) -----------------------------------------
	if showSB then
		ensureScrollbar(self)
		self._scrollbar:Show()
	elseif self._scrollbar then
		self._scrollbar:Hide()
	end

	-- Initial scroll = 0; reposition thumb to reflect it.
	sf:SetVerticalScroll(0)
	repositionThumb(self)
end

-- ----- Public methods --------------------------------------------------

function mixin:GetContent()
	return self._content
end

function mixin:SetContentHeight(h)
	h = h or 0
	if h < 0 then h = 0 end
	self._contentHeight = h
	if self._content then
		local w = self._content:GetWidth()
		self._content:SetSize(w, h)
	end
	-- Re-clamp current scroll if it now exceeds the new max. Use the
	-- OUTER frame's explicit SetSize-derived height for viewport; the
	-- inner Blizzard ScrollFrame is anchor-derived and returns 0 until
	-- layout has been computed (which doesn't happen on hidden parents).
	local sf       = self._scrollFrame
	local viewport = self._frame:GetHeight()
	local maxS     = math.max(0, h - viewport)
	if (sf:GetVerticalScroll() or 0) > maxS then
		sf:SetVerticalScroll(maxS)
	end
	repositionThumb(self)
end

function mixin:GetContentHeight()
	return self._contentHeight or 0
end

function mixin:GetVerticalScroll()
	return self._scrollFrame and self._scrollFrame:GetVerticalScroll() or 0
end

function mixin:SetVerticalScroll(y)
	local sf = self._scrollFrame
	if not sf then return end
	-- Use outer frame height (explicit SetSize) rather than inner sf:GetHeight()
	-- (anchor-derived; returns 0 before layout). Same value at runtime, but
	-- the outer one is reliable in tests where parents are hidden.
	local viewport = self._frame:GetHeight()
	local maxS = math.max(0, (self._contentHeight or 0) - viewport)
	if y < 0 then y = 0 end
	if y > maxS then y = maxS end
	sf:SetVerticalScroll(y)
end

function mixin:ScrollToTop()
	self:SetVerticalScroll(0)
end

function mixin:ScrollToBottom()
	local sf = self._scrollFrame
	if not sf then return end
	local viewport = self._frame:GetHeight()
	local maxS = math.max(0, (self._contentHeight or 0) - viewport)
	sf:SetVerticalScroll(maxS)
end

-- ----- Register --------------------------------------------------------
-- pool = false: see header for rationale.

Core:RegisterWidget("ScrollFrame", {
	frameType = "Frame",
	mixin     = mixin,
	pool      = false,
})
