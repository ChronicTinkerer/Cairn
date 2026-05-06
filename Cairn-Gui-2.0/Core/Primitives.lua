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

	widget.Cairn:SetVisualState(state)
		Switch the widget to "default" | "hover" | "pressed" | "disabled".
		Re-applies token values to every primitive.

	widget.Cairn:GetVisualState() -> current state string

	widget.Cairn:Repaint()
		Re-resolve every primitive's spec and re-apply colors. Call
		this after a theme change or per-instance override.

	widget.Cairn:GetPrimitive(slot) -> internal record (for tests)

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
	- Rect, Border ship.
	- State variants drive automatic transitions on actual hover/press.
	- No automatic repaint on SetActiveTheme or SetTokenOverride; call
	  :Repaint() explicitly. Lazy repaint queue is a Decision-5 follow-up.
	- Icon, Divider, Glow, Mask come later. So do atlas resolution and
	  9-slice for radius support.
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

-- ----- Interactive state machine ---------------------------------------
-- Driven by _hovering / _pressing / _disabled flags. The flags are
-- toggled by hook scripts on the underlying frame (OnEnter/OnLeave/
-- OnMouseDown/OnMouseUp) when interactive state is enabled.

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
		-- Repaint inline; skip the public Repaint to avoid the iteration
		-- when we've already computed the new state right here.
		if self._primitives then
			for _, slot in ipairs(self._primitiveList) do
				local rec = self._primitives[slot]
				if rec then
					applyColor(rec.textures, resolveSpec(self, rec.spec, newState))
				end
			end
		end
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

	applyColor(rec.textures, resolveSpec(self, spec, self._visualState or "default"))
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

	applyColor(rec.textures, resolveSpec(self, spec, self._visualState or "default"))
	return rec
end

-- ----- SetVisualState / GetVisualState ---------------------------------

function Base:SetVisualState(state)
	if not VALID_STATES[state] then
		error(("SetVisualState: invalid state %q (must be default/hover/pressed/disabled)"):format(tostring(state)), 2)
	end
	self._visualState = state
	self:Repaint()
end

function Base:GetVisualState()
	return self._visualState or "default"
end

-- ----- Repaint ---------------------------------------------------------

function Base:Repaint()
	if not self._primitives then return end
	local state = self._visualState or "default"
	for _, slot in ipairs(self._primitiveList) do
		local rec = self._primitives[slot]
		if rec then
			applyColor(rec.textures, resolveSpec(self, rec.spec, state))
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
