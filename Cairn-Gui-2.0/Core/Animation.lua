--[[
Cairn-Gui-2.0 / Core / Animation

Day 15 Slice B implementation of Decision 9. The full decision lists
11 sub-decisions; this file ships the engine plus pre-wires the
primitive transition tokens. Other sub-decisions (Spring physics,
Sequence/Parallel/Stagger, OKLCH, ReduceMotion, off-screen pause,
concurrency cap, AnimationGroup backend routing) are deferred.

Public API on the lib:

	Cairn.Gui:RegisterEasing(name, fn)
		Add a named easing function to the global registry. fn receives a
		normalized t in [0, 1] and returns the eased value (typically also
		in [0, 1]; some easings overshoot, e.g. easeOutBack).

	Cairn.Gui.easings -> table
		Public registry keyed by easing name. Read-only externally. Built
		in: linear, easeIn, easeOut, easeInOut.

Public API on widget.Cairn (added to Mixins.Base):

	widget.Cairn:Animate(spec)
		Declarative API. spec maps property names to a per-property def:
			{ to = number,    -- target value (required)
			  dur = number,   -- duration in seconds (default 0.2)
			  ease = string,  -- easing name (default "easeOut")
			  complete = fn,  -- optional callback fired on completion }

		Supported scalar properties:
			alpha   - frame:SetAlpha
			scale   - frame:SetScale
			width   - frame:SetWidth
			height  - frame:SetHeight

		Calling Animate again for an already-animating property REPLACES
		the in-flight animation, capturing the CURRENT value as the new
		"from". This lets Animate be called repeatedly on hover/press
		state changes without snapping.

		Unknown properties are silently ignored for forward-compat.

	widget.Cairn:CancelAnimations(prop?)
		Cancel a single in-flight animation by property name, or all
		animations on this widget if prop is nil. Targets do NOT snap to
		their final value; they freeze at whatever value the cancel
		caught.

Internal API on widget.Cairn:

	widget.Cairn:_animatePrimitiveColor(slot, toColor, duration, easing)
		Used by the Primitives state machine when a state-variant spec
		carries a `transition` token. Captures the primitive's current
		vertex color as the "from", lerps RGBA over duration via the
		named easing, applies via SetVertexColor on every texture in the
		record. Replacement of an in-flight per-slot animation works the
		same as the public Animate (key is "primColor:<slot>").

Engine notes:
	- One OnUpdate frame per widget, parented to self._frame so Blizzard's
	  visibility cascade auto-pauses ticking when the widget is hidden.
	  This delivers Decision 9's "auto-pause on Hide / resume on Show"
	  with no explicit show/hide hooks of our own.
	- The OnUpdate detaches itself when the per-widget queue drains, so
	  an idle UI pays nothing per frame even if widgets have been
	  animated previously.
	- Animation records carry a stable `key` so a new Animate on the
	  same property cleanly replaces an in-flight one. Same for primitive
	  color tweens, keyed "primColor:<slot>".
	- Auto-cancel on Release is wired by extending Base:Release in this
	  file (no edit to Mixins/Base.lua needed) -- the Release method
	  calls self:CancelAnimations() if the method exists.

Status: Day 15 slice B. Spring / Sequence / Parallel / Stagger /
ReduceMotion / OKLCH / AnimationGroup-backend routing all deferred.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 3
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Animation requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Easing registry -------------------------------------------------

-- Built-ins. easeInOut is the standard cubic in-out. easeIn/easeOut are
-- quadratic, slightly less aggressive than cubic, which reads more like
-- "subtle UI motion" than "dramatic motion graphics".
local DEFAULT_EASINGS = {
	linear    = function(t) return t end,
	easeIn    = function(t) return t * t end,
	easeOut   = function(t) return t * (2 - t) end,
	easeInOut = function(t)
		if t < 0.5 then
			return 2 * t * t
		else
			local u = -2 * t + 2
			return 1 - u * u / 2
		end
	end,
}

lib.easings = lib.easings or {}
for name, fn in pairs(DEFAULT_EASINGS) do
	if lib.easings[name] == nil then
		lib.easings[name] = fn
	end
end

function lib:RegisterEasing(name, fn)
	if type(name) ~= "string" or name == "" then
		error("RegisterEasing: name must be a non-empty string", 2)
	end
	if type(fn) ~= "function" then
		error("RegisterEasing: fn must be a function", 2)
	end
	self.easings[name] = fn
end

-- ----- Per-widget animation list bookkeeping ---------------------------

local function ensureAnimList(self)
	if not self._anims then
		self._anims     = {}    -- list of in-flight records
		self._animByKey = {}    -- key -> rec  for replacement / cancel
	end
end

-- Detach the per-widget OnUpdate when the queue is empty. Idempotent;
-- safe to call multiple times.
local function detachIfIdle(self)
	if self._anims and #self._anims == 0 and self._animFrame and self._animFrameActive then
		self._animFrame:SetScript("OnUpdate", nil)
		self._animFrameActive = false
	end
end

-- ----- The tick (per-widget OnUpdate) ----------------------------------

local function tickAnimations(self, dt)
	local anims = self._anims
	if not anims or #anims == 0 then
		detachIfIdle(self)
		return
	end

	local i = 1
	while i <= #anims do
		local a = anims[i]
		a.elapsed = (a.elapsed or 0) + dt
		local progress = a.dur > 0 and math.min(a.elapsed / a.dur, 1) or 1
		local easeFn = lib.easings[a.ease] or lib.easings.linear
		local eased  = easeFn(progress)

		if a.fromType == "scalar" then
			local v = a.from + (a.to - a.from) * eased
			a.apply(self, v)
		elseif a.fromType == "rgba" then
			local from, to, buf = a.from, a.to, a._lerpBuffer
			buf[1] = from[1] + (to[1] - from[1]) * eased
			buf[2] = from[2] + (to[2] - from[2]) * eased
			buf[3] = from[3] + (to[3] - from[3]) * eased
			buf[4] = from[4] + (to[4] - from[4]) * eased
			a.apply(self, buf)
		end

		if progress >= 1 then
			table.remove(anims, i)
			if self._animByKey then self._animByKey[a.key] = nil end
			if a.complete then
				local ok, err = pcall(a.complete, self, a)
				if not ok and lib._log and lib._log.Error then
					lib._log:Error("animation %s complete handler errored: %s",
						tostring(a.key), tostring(err))
				end
			end
		else
			i = i + 1
		end
	end

	detachIfIdle(self)
end

-- Lazy-create the per-widget tick frame and attach OnUpdate.
local function ensureAnimFrame(self)
	if self._animFrame and self._animFrameActive then return end
	if not self._animFrame then
		-- Parent to self._frame so Blizzard auto-pauses ticking when the
		-- widget is hidden (Decision 9's auto-pause-on-Hide for free).
		self._animFrame = CreateFrame("Frame", nil, self._frame)
	end
	self._animFrameActive = true
	self._animFrame:SetScript("OnUpdate", function(_, dt)
		tickAnimations(self, dt)
	end)
end

-- Add or replace an animation by key.
local function addAnim(self, key, rec)
	ensureAnimList(self)
	rec.key     = key
	rec.elapsed = 0

	-- Replace any existing animation under the same key.
	local existing = self._animByKey[key]
	if existing then
		for i, a in ipairs(self._anims) do
			if a == existing then
				table.remove(self._anims, i)
				break
			end
		end
	end

	self._anims[#self._anims + 1] = rec
	self._animByKey[key]          = rec
	ensureAnimFrame(self)
end

-- ----- Public Animate API ----------------------------------------------

local PROPERTY_ADAPTERS = {
	alpha = {
		get   = function(frame) return frame:GetAlpha() end,
		apply = function(frame, v) frame:SetAlpha(v) end,
	},
	scale = {
		get   = function(frame) return frame:GetScale() end,
		apply = function(frame, v) frame:SetScale(v) end,
	},
	width = {
		get   = function(frame) return frame:GetWidth() end,
		apply = function(frame, v) frame:SetWidth(v) end,
	},
	height = {
		get   = function(frame) return frame:GetHeight() end,
		apply = function(frame, v) frame:SetHeight(v) end,
	},
}

function Base:Animate(spec)
	if type(spec) ~= "table" then
		error("Animate: spec must be a table", 2)
	end
	local frame = self._frame
	if not frame then return end

	for prop, def in pairs(spec) do
		local adapter = PROPERTY_ADAPTERS[prop]
		if adapter and type(def) == "table" and def.to ~= nil then
			local fromValue = adapter.get(frame)
			-- Capture the apply function by reference so closure costs
			-- one indirection per tick rather than a table lookup.
			local applyFn = adapter.apply
			addAnim(self, prop, {
				fromType = "scalar",
				from     = fromValue,
				to       = def.to,
				dur      = def.dur or 0.2,
				ease     = def.ease or "easeOut",
				apply    = function(_, v) applyFn(frame, v) end,
				complete = def.complete,
			})
		end
		-- Unknown props silently ignored. Allows forward-compat with
		-- future properties (rotation, translateX, etc.) and consumer
		-- typos without runtime errors.
	end
end

function Base:CancelAnimations(prop)
	local anims = self._anims
	if not anims or #anims == 0 then return end

	if prop == nil then
		-- Cancel everything. wipe() preserves the table identity so the
		-- existing _animByKey reference stays valid.
		wipe(anims)
		if self._animByKey then wipe(self._animByKey) end
	else
		local existing = self._animByKey and self._animByKey[prop]
		if existing then
			for i, a in ipairs(anims) do
				if a == existing then
					table.remove(anims, i)
					break
				end
			end
			self._animByKey[prop] = nil
		end
	end

	detachIfIdle(self)
end

-- ----- Internal: animate a primitive's color (used by transition wiring)

function Base:_animatePrimitiveColor(slot, toColor, duration, easingName)
	local rec = self._primitives and self._primitives[slot]
	if not rec or not rec.textures or not rec.textures[1] then return end
	if type(toColor) ~= "table" then return end

	-- Capture the current vertex color of the FIRST texture as "from".
	-- Multi-texture records (border with 4 edges) are assumed in sync, so
	-- the first texture is representative.
	local fromR, fromG, fromB, fromA = rec.textures[1]:GetVertexColor()
	fromA = fromA or 1
	local from = { fromR, fromG, fromB, fromA }
	local to   = {
		toColor[1] or 1, toColor[2] or 1, toColor[3] or 1, toColor[4] or 1,
	}

	addAnim(self, "primColor:" .. slot, {
		fromType    = "rgba",
		from        = from,
		to          = to,
		dur         = duration or 0.15,
		ease        = easingName or "easeOut",
		_lerpBuffer = { 0, 0, 0, 0 },
		apply       = function(_, rgba)
			-- Apply across all textures in the record so e.g. all 4
			-- border edges track in lockstep.
			for _, tex in ipairs(rec.textures) do
				if tex.SetVertexColor then
					tex:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4])
				end
			end
		end,
	})
end

-- ----- Auto-cancel on Release (extends Base:Release) -------------------
-- Wrap the existing Release so we don't have to edit Mixins/Base.lua.
-- The wrapper cancels any in-flight animations (so a pooled widget
-- doesn't carry residual ticking into its next Acquire) before delegating
-- to the original Release. Idempotent: a pre-existing wrapper is detected
-- via the marker so re-loads (LibStub MINOR bump during dev) don't stack.

if not Base._releaseWrappedForAnim then
	local originalRelease = Base.Release
	function Base:Release()
		if self.CancelAnimations then
			self:CancelAnimations()
		end
		-- Also detach the OnUpdate frame from the (possibly soon-to-be
		-- re-parented) widget frame. Keep the tick frame around for
		-- pool reuse; just orphan it visually.
		if self._animFrame then
			self._animFrame:SetScript("OnUpdate", nil)
			self._animFrameActive = false
			-- Leave _animFrame attached to self._frame; on pool re-Acquire
			-- the same Cairn table is reused, so the tick frame matches
			-- the widget frame again.
		end
		return originalRelease(self)
	end
	Base._releaseWrappedForAnim = true
end
