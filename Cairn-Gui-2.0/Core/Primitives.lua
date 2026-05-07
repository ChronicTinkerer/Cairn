--[[
Cairn-Gui-2.0 / Core / Primitives

Drawing-primitive layer per Decision 7. Widgets call high-level draw
methods (DrawRect, DrawBorder) which create and manage Blizzard
Textures under the hood. Color (and other typed values, later) is
resolved through the theme cascade at draw time, so the same widget
code looks different under different themes without modification.

Public API on widget.Cairn (added to Mixins.Base by this file):

	widget.Cairn:DrawRect(slot, spec, opts?)
		Solid fill covering the entire frame.
		opts.layer overrides the default "BACKGROUND" draw layer.

	widget.Cairn:DrawBorder(slot, spec, opts?)
		Four-edge rectangular border.
		opts.width  = pixel thickness (default 1).
		opts.layer  overrides the default "BORDER" draw layer.

	widget.Cairn:DrawIcon(slot, textureSpec, opts?)
		Sized + anchored texture region inside the frame. textureSpec
		resolves to a string (token-name first via theme cascade, then
		used as-is). The string is tried as an atlas key first, then as
		a file path. State-variant texture maps switch the source on
		state change. Empty/nil string hides the icon.

		opts.size      = number | length-token, square edge (default 16)
		opts.width     = number | length-token, overrides opts.size
		opts.height    = number | length-token, overrides opts.size
		opts.anchor    = "CENTER"|"LEFT"|"RIGHT"|"TOP"|"BOTTOM"|
		                 "TOPLEFT"|"TOPRIGHT"|"BOTTOMLEFT"|"BOTTOMRIGHT"
		                 (default "CENTER")
		opts.offsetX   = number, default 0
		opts.offsetY   = number, default 0
		opts.color     = optional color spec (string token | tuple |
		                 state-variant table). nil = untinted (white).
		opts.layer     = string, default "ARTWORK"

	widget.Cairn:SetVisualState(state)
		Switch the widget to "default" | "hover" | "pressed" | "disabled".
		Re-applies token values to every primitive.

	widget.Cairn:GetVisualState() -> current state string

	widget.Cairn:Repaint()
		Re-resolve every primitive's spec and re-apply colors. Call
		this after a theme change or per-instance override.

	widget.Cairn:GetPrimitive(slot) -> internal record (for tests)

	widget.Cairn:SetPrimitiveShown(slot, shown)
		Show/hide every texture in a primitive. Useful for toggling
		an Icon (e.g. a checkmark when checked) without redrawing.
		No-op for unknown slots.

The `spec` argument to Draw* methods accepts three shapes:

	1. token name string                "color.bg.button"
	2. literal value (color tuple)      {0.5, 0.5, 0.5, 1}
	3. state-variant table              {
	                                      default  = "color.bg.button",
	                                      hover    = "color.bg.button.hover",
	                                      pressed  = "color.bg.button.pressed",
	                                      disabled = "color.bg.button.disabled",
	                                    }

State-variant entries can themselves be token names or literal values;
each is resolved independently when its state is active.

Slots are per-widget identifier strings. Calling DrawRect twice with the
same slot updates the existing primitive rather than duplicating it.

Day 7 additions (state machine):
	- _hovering / _pressing / _disabled flags drive a recomputed state.
	- _enableInteractiveState() hooks OnEnter/OnLeave/OnMouseDown/
	  OnMouseUp on the underlying frame to keep the state current.
	  Idempotent; safe to call multiple times.
	- DrawRect / DrawBorder auto-enable interactive state when given a
	  state-variant spec. Single-token specs do not enable hooks (no
	  point if the visual doesn't change with state).
	- SetEnabled(bool) toggles the disabled state, syncs Blizzard's
	  Frame:SetEnabled when present, and forces a repaint.

Status:
	- Rect, Border, Icon ship.
	- State variants drive automatic transitions on actual hover/press.
	  Icons support state-variant texture maps in addition to color tints.
	- Atlas resolution shipped for Icon (C_Texture.GetAtlasInfo first,
	  file path fallback). Same fallback chain will extend to Rect/Border
	  once 9-slice ships.
	- No automatic repaint on SetActiveTheme or SetTokenOverride; call
	  :Repaint() explicitly. Lazy repaint queue is a Decision-5 follow-up.
	- Divider, Glow, Mask come later. So does 9-slice for radius support.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Primitives requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Constants -------------------------------------------------------

local VALID_STATES = { default = true, hover = true, pressed = true, disabled = true }

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"

-- ----- Spec resolution -------------------------------------------------

-- Detect a state-variant table vs a literal color tuple. State-variant
-- tables have at least one of the named state keys.
local function looksLikeStateMap(t)
	if type(t) ~= "table" then return false end
	if t.default ~= nil or t.hover ~= nil or t.pressed ~= nil or t.disabled ~= nil then
		return true
	end
	return false
end

-- Resolve a spec to a final value for the given visual state.
-- Returns whatever ResolveToken returns (table for color, number for length, etc.).
local function resolveSpec(widgetCairn, spec, state)
	if type(spec) == "string" then
		return lib:ResolveToken(spec, widgetCairn)
	elseif type(spec) == "table" then
		if looksLikeStateMap(spec) then
			local entry = spec[state]
			if entry == nil then entry = spec.default end
			if type(entry) == "string" then
				return lib:ResolveToken(entry, widgetCairn)
			end
			return entry
		else
			-- Literal value (color tuple, font table, etc.).
			return spec
		end
	end
	return nil
end

-- Apply a resolved color to one or more textures.
local function applyColor(textures, color)
	if type(color) ~= "table" then return end
	local r = color[1] or 1
	local g = color[2] or 1
	local b = color[3] or 1
	local a = color[4] or 1
	for _, tex in ipairs(textures) do
		if tex.SetVertexColor then
			tex:SetVertexColor(r, g, b, a)
		end
	end
end

-- ----- Per-widget primitive bookkeeping --------------------------------

local function ensurePrimitives(self)
	if not self._primitives then
		self._primitives    = {}      -- slot -> record
		self._primitiveList = {}       -- list of slots in insertion order
		self._visualState   = "default"
	end
	return self._primitives, self._primitiveList
end

-- ----- Texture spec resolution (Icon) ----------------------------------
-- Resolve a spec to a final texture string for the given visual state.
-- Returns the resolved string, or nil if the spec didn't yield one.
-- Strings: try as token name first; if no token resolution, return as-is.
-- State-variant tables: pick the entry for `state` (fall back to default),
-- then resolve as a string. Anything else returns nil.
local function resolveTextureSpec(widgetCairn, spec, state)
	local raw
	if type(spec) == "string" then
		raw = lib:ResolveToken(spec, widgetCairn)
		if type(raw) ~= "string" then raw = spec end
	elseif type(spec) == "table" and looksLikeStateMap(spec) then
		local entry = spec[state]
		if entry == nil then entry = spec.default end
		if type(entry) == "string" then
			raw = lib:ResolveToken(entry, widgetCairn)
			if type(raw) ~= "string" then raw = entry end
		end
	end
	if type(raw) == "string" then return raw end
	return nil
end

-- Resolve a length-typed value: a literal number passes through; a string
-- resolves through the theme cascade and is accepted only if it resolves
-- to a number. Anything else returns nil.
local function resolveLength(widgetCairn, v)
	if type(v) == "number" then return v end
	if type(v) == "string" then
		local resolved = lib:ResolveToken(v, widgetCairn)
		if type(resolved) == "number" then return resolved end
	end
	return nil
end

-- Atlas-first, file-path fallback application of a texture source string.
-- Empty/nil sources hide the texture rather than blanking it.
local function applyTextureSource(texture, source)
	if not source or source == "" then
		if texture.Hide then texture:Hide() end
		return
	end
	local atlasInfo
	if C_Texture and C_Texture.GetAtlasInfo then
		atlasInfo = C_Texture.GetAtlasInfo(source)
	end
	if atlasInfo then
		texture:SetAtlas(source)
	else
		texture:SetTexture(source)
	end
	if texture.Show then texture:Show() end
end

-- Read a state-variant spec's `transition` token (Day 15 slice B).
-- Returns (durationSeconds, easingName, colorSpace) or (nil, nil, nil) if
-- no transition is configured. The token can be a duration token name
-- (resolved through the cascade) or a literal number; an optional `ease`
-- sibling key supplies the easing name; an optional `colorSpace` sibling
-- (Day 15F) opts the primitive's color transition into OKLCH lerp instead
-- of the default RGB. Any non-positive duration disables the transition
-- (treated as snap).
local function readTransition(self, spec)
	if type(spec) ~= "table" or spec.transition == nil then
		return nil, nil, nil
	end
	local raw = spec.transition
	if type(raw) == "string" then
		raw = lib:ResolveToken(raw, self)
	end
	if type(raw) ~= "number" or raw <= 0 then return nil, nil, nil end
	local ease = spec.ease
	if ease ~= nil and type(ease) ~= "string" then ease = nil end
	local colorSpace = spec.colorSpace
	if colorSpace ~= nil and type(colorSpace) ~= "string" then colorSpace = nil end
	return raw, ease, colorSpace
end

-- Re-resolve a primitive record's spec(s) for the given state and apply.
-- Single point of dispatch by record kind so the state machine, Repaint,
-- and the DrawX entry points all behave consistently.
--
-- options.transition (number, seconds): if set and self has the
--   _animatePrimitiveColor method (Animation.lua loaded), color changes
--   animate over this duration. Otherwise the new color snaps. Source
--   changes on icons (state-variant texture) always snap.
-- options.ease (string): easing name passed through to the animation.
-- options.colorSpace (string, Day 15F): if "oklch", color transitions
--   lerp in OKLCH space instead of RGB. Forwarded to
--   _animatePrimitiveColor as opts.colorSpace.
local function applyRecord(self, slot, rec, state, options)
	options = options or {}
	local transition = options.transition
	local ease       = options.ease
	local colorSpace = options.colorSpace
	local canAnimate = transition and transition > 0 and type(self._animatePrimitiveColor) == "function"

	-- Build the animOpts table only when we'll actually use it. Avoids
	-- a per-call allocation on the common no-OKLCH path.
	local animOpts
	if canAnimate and colorSpace then
		animOpts = { colorSpace = colorSpace }
	end

	if rec.kind == "rect" or rec.kind == "border" then
		local color = resolveSpec(self, rec.spec, state)
		if canAnimate and type(color) == "table" then
			self:_animatePrimitiveColor(slot, color, transition, ease, animOpts)
		else
			applyColor(rec.textures, color)
		end
	elseif rec.kind == "icon" then
		-- Source change (state-variant texture spec) always snaps; v1
		-- doesn't fade between atlases. Color tint, however, animates
		-- when the colorSpec carries a transition.
		local source = resolveTextureSpec(self, rec.spec, state)
		applyTextureSource(rec.textures[1], source)
		if rec.colorSpec then
			local color = resolveSpec(self, rec.colorSpec, state)
			if canAnimate and type(color) == "table" then
				self:_animatePrimitiveColor(slot, color, transition, ease, animOpts)
			else
				applyColor(rec.textures, color)
			end
		else
			-- No tint requested: render the icon at its native color.
			rec.textures[1]:SetVertexColor(1, 1, 1, 1)
		end
	end
end

-- ----- Interactive state machine ---------------------------------------
-- Driven by _hovering / _pressing / _disabled flags. The flags are
-- toggled by hook scripts on the underlying frame (OnEnter/OnLeave/
-- OnMouseDown/OnMouseUp) when interactive state is enabled.

-- Walk every primitive on the widget and apply it for `state`. Per-record
-- transitions are honored so different primitives can transition at
-- different speeds (or not at all). Shared between the state machine
-- and SetVisualState so consumers / tests get the same animated path.
local function applyAllForState(self, state)
	if not self._primitives then return end
	for _, slot in ipairs(self._primitiveList) do
		local rec = self._primitives[slot]
		if rec then
			-- For icons, the transition lives on the colorSpec (the
			-- texture source itself doesn't animate in v1). For
			-- rect/border, the transition lives on the spec.
			local specForTransition
			if rec.kind == "icon" then
				specForTransition = rec.colorSpec
			else
				specForTransition = rec.spec
			end
			local dur, ease, colorSpace = readTransition(self, specForTransition)
			if dur then
				applyRecord(self, slot, rec, state, {
					transition = dur,
					ease       = ease,
					colorSpace = colorSpace,
				})
			else
				applyRecord(self, slot, rec, state)
			end
		end
	end
end

-- Priority: disabled > pressed-while-hovering > hovering > default.
-- Pressed without hovering means the user dragged off the widget while
-- holding the button; we treat that as "default" (cancel-style feedback).
local function recomputeVisualState(self)
	local newState
	if self._disabled then
		newState = "disabled"
	elseif self._pressing and self._hovering then
		newState = "pressed"
	elseif self._hovering then
		newState = "hover"
	else
		newState = "default"
	end
	if newState ~= self._visualState then
		self._visualState = newState
		applyAllForState(self, newState)
	end
end

-- Hook the four state-driving scripts on the underlying frame. Idempotent.
-- HookScript chains so any user-set scripts continue to fire.
local function enableInteractiveState(self)
	if self._interactive then return end
	local frame = self._frame
	if not frame or not frame.HookScript then return end
	self._interactive = true

	-- Plain Frames don't fire OnEnter/OnLeave without EnableMouse. Buttons
	-- do by default. Calling EnableMouse on a frame that already has it is
	-- harmless.
	if frame.EnableMouse then
		frame:EnableMouse(true)
	end

	frame:HookScript("OnEnter", function()
		self._hovering = true
		recomputeVisualState(self)
	end)
	frame:HookScript("OnLeave", function()
		self._hovering = false
		recomputeVisualState(self)
	end)
	frame:HookScript("OnMouseDown", function()
		self._pressing = true
		recomputeVisualState(self)
	end)
	frame:HookScript("OnMouseUp", function()
		self._pressing = false
		recomputeVisualState(self)
	end)
end

-- ----- DrawRect --------------------------------------------------------

function Base:DrawRect(slot, spec, opts)
	if type(slot) ~= "string" or slot == "" then
		error("DrawRect: slot must be a non-empty string", 2)
	end
	local frame = self._frame
	if not frame or not frame.CreateTexture then return end

	opts       = opts or {}
	local layer = opts.layer or "BACKGROUND"

	local prims, list = ensurePrimitives(self)
	local rec = prims[slot]

	if not rec or rec.kind ~= "rect" then
		-- Fresh create. (If a different-kind primitive previously occupied
		-- this slot, drop the old reference; its textures stay attached to
		-- the frame but get hidden by overdraw of the new ones.)
		local tex = frame:CreateTexture(nil, layer)
		tex:SetTexture(WHITE_TEX)
		tex:SetAllPoints(frame)
		rec = { kind = "rect", textures = { tex }, spec = spec, opts = opts }
		prims[slot] = rec
		list[#list + 1] = slot
	else
		-- Update existing in-place.
		rec.spec = spec
		rec.opts = opts
		rec.textures[1]:SetDrawLayer(layer)
		rec.textures[1]:SetAllPoints(frame)
	end

	-- Auto-enable interactive state machine if the spec has variants.
	-- Single-token / literal specs don't need it (visual won't change).
	if looksLikeStateMap(spec) then
		enableInteractiveState(self)
	end

	-- Initial paint snaps (no transition) so the user sees the starting
	-- state immediately. State CHANGES go through recomputeVisualState
	-- which honors the transition token.
	applyRecord(self, slot, rec, self._visualState or "default")
	return rec
end

-- ----- DrawBorder ------------------------------------------------------

function Base:DrawBorder(slot, spec, opts)
	if type(slot) ~= "string" or slot == "" then
		error("DrawBorder: slot must be a non-empty string", 2)
	end
	local frame = self._frame
	if not frame or not frame.CreateTexture then return end

	opts        = opts or {}
	local width = opts.width or 1
	local layer = opts.layer or "BORDER"

	local prims, list = ensurePrimitives(self)
	local rec = prims[slot]

	if not rec or rec.kind ~= "border" then
		-- Fresh create: 4 edge textures (top, right, bottom, left).
		local edges = {}
		for i = 1, 4 do
			local t = frame:CreateTexture(nil, layer)
			t:SetTexture(WHITE_TEX)
			edges[i] = t
		end

		-- Top edge.
		edges[1]:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
		edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		edges[1]:SetHeight(width)

		-- Right edge.
		edges[2]:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, 0)
		edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		edges[2]:SetWidth(width)

		-- Bottom edge.
		edges[3]:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
		edges[3]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		edges[3]:SetHeight(width)

		-- Left edge.
		edges[4]:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
		edges[4]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		edges[4]:SetWidth(width)

		rec = { kind = "border", textures = edges, spec = spec, opts = opts }
		prims[slot] = rec
		list[#list + 1] = slot
	else
		-- Update layer + width on existing edges.
		rec.spec = spec
		rec.opts = opts
		for _, t in ipairs(rec.textures) do
			t:SetDrawLayer(layer)
		end
		rec.textures[1]:SetHeight(width)
		rec.textures[3]:SetHeight(width)
		rec.textures[2]:SetWidth(width)
		rec.textures[4]:SetWidth(width)
	end

	if looksLikeStateMap(spec) then
		enableInteractiveState(self)
	end

	-- Initial paint snaps; state changes via the state machine animate
	-- if the spec carries a transition token.
	applyRecord(self, slot, rec, self._visualState or "default")
	return rec
end

-- ----- SetVisualState / GetVisualState ---------------------------------

-- SetVisualState honors transitions: a state change triggers animation
-- when the spec carries a `transition` token, same as a hover-driven
-- change. Use Repaint() instead when you want a snap (post-theme-swap
-- or post-token-override redraw).
function Base:SetVisualState(state)
	if not VALID_STATES[state] then
		error(("SetVisualState: invalid state %q (must be default/hover/pressed/disabled)"):format(tostring(state)), 2)
	end
	if state ~= self._visualState then
		self._visualState = state
		applyAllForState(self, state)
	end
end

function Base:GetVisualState()
	return self._visualState or "default"
end

-- ----- Repaint ---------------------------------------------------------

-- Repaint snaps to the current state's resolved values for every
-- primitive. Does NOT animate, even if specs carry transitions; Repaint
-- is the explicit "force a redraw" path and is typically called after a
-- theme swap or token override, not on user-driven state changes.
function Base:Repaint()
	if not self._primitives then return end
	local state = self._visualState or "default"
	for _, slot in ipairs(self._primitiveList) do
		local rec = self._primitives[slot]
		if rec then
			applyRecord(self, slot, rec, state)
		end
	end
end

-- ----- GetPrimitive (introspection) ------------------------------------

function Base:GetPrimitive(slot)
	return self._primitives and self._primitives[slot]
end

-- ----- SetEnabled / IsEnabled ------------------------------------------
-- Toggles disabled visual state and, when the underlying frame supports
-- it (Button, EditBox, etc.), Blizzard's own enabled flag. Disabled
-- widgets ignore hover/press transitions until re-enabled.

function Base:SetEnabled(enabled)
	enabled = enabled and true or false
	self._disabled = not enabled
	-- Sync the Blizzard enabled flag if the frame has one. Plain Frames
	-- don't, so guard with a method check.
	local frame = self._frame
	if frame and type(frame.SetEnabled) == "function" then
		frame:SetEnabled(enabled)
	end
	recomputeVisualState(self)
end

function Base:IsEnabled()
	return not self._disabled
end

-- ----- DrawIcon --------------------------------------------------------

local DEFAULT_ICON_SIZE  = 16
local DEFAULT_ICON_LAYER = "ARTWORK"

local VALID_ANCHORS = {
	CENTER = true, LEFT = true, RIGHT = true, TOP = true, BOTTOM = true,
	TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

function Base:DrawIcon(slot, spec, opts)
	if type(slot) ~= "string" or slot == "" then
		error("DrawIcon: slot must be a non-empty string", 2)
	end
	local frame = self._frame
	if not frame or not frame.CreateTexture then return end

	opts         = opts or {}
	local layer  = opts.layer or DEFAULT_ICON_LAYER
	local anchor = opts.anchor or "CENTER"
	if not VALID_ANCHORS[anchor] then
		error(("DrawIcon: invalid anchor %q (CENTER/LEFT/RIGHT/TOP/BOTTOM/TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT)"):format(tostring(anchor)), 2)
	end
	local offsetX = opts.offsetX or 0
	local offsetY = opts.offsetY or 0

	-- Size: width / height override size. Each accepts a number or a
	-- length-token string. Falls back to DEFAULT_ICON_SIZE.
	local size = resolveLength(self, opts.size)   or DEFAULT_ICON_SIZE
	local w    = resolveLength(self, opts.width)  or size
	local h    = resolveLength(self, opts.height) or size

	local prims, list = ensurePrimitives(self)
	local rec = prims[slot]

	if not rec or rec.kind ~= "icon" then
		-- Fresh create. As with other primitives, if a different-kind
		-- record previously occupied this slot we replace it; the old
		-- texture leaks visually until covered, but is unreferenced.
		local tex = frame:CreateTexture(nil, layer)
		rec = {
			kind      = "icon",
			textures  = { tex },
			spec      = spec,
			opts      = opts,
			colorSpec = opts.color,
		}
		prims[slot] = rec
		list[#list + 1] = slot
	else
		-- Update existing in-place.
		rec.spec      = spec
		rec.opts      = opts
		rec.colorSpec = opts.color
		rec.textures[1]:SetDrawLayer(layer)
	end

	-- Position + size on every call (caller may have changed anchor/offsets).
	local tex = rec.textures[1]
	tex:ClearAllPoints()
	tex:SetPoint(anchor, frame, anchor, offsetX, offsetY)
	tex:SetSize(w, h)

	-- Auto-enable interactive state when either spec carries variants;
	-- single-token / literal specs don't need hover/press hooks.
	if looksLikeStateMap(spec) or looksLikeStateMap(opts.color) then
		enableInteractiveState(self)
	end

	-- Apply texture source + tint via the shared dispatcher. Initial
	-- paint snaps; subsequent state changes animate through the state
	-- machine when colorSpec carries a transition token.
	applyRecord(self, slot, rec, self._visualState or "default")

	return rec
end

-- ----- SetPrimitiveShown -----------------------------------------------
-- Show/hide every texture in a named primitive. Used by widgets that need
-- to toggle a glyph (e.g. a check icon when checked) without redrawing.
-- No-op if the slot doesn't exist.

function Base:SetPrimitiveShown(slot, shown)
	local rec = self._primitives and self._primitives[slot]
	if not rec then return end
	local visible = shown and true or false
	for _, t in ipairs(rec.textures) do
		if t.SetShown then t:SetShown(visible) end
	end
end
