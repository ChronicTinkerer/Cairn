--[[
Cairn-Gui-2.0 / Core / Animation

Implements Decision 9 from ARCHITECTURE.md. The full decision lists 11
sub-decisions; this file ships the engine, primitive transition tokens,
composition primitives, ReduceMotion accessibility flag, the standard
easing set, Spring physics, an imperative Tween shortcut, and a per-
widget concurrency cap. OKLCH, off-screen pause beyond Hide cascade, and
AnimationGroup-backend routing for Translation/Scale/Alpha/Rotation
remain deferred (Day 15E candidates).

Public API on the lib:

	Cairn.Gui:RegisterEasing(name, fn)
		Add a named easing function to the global registry. fn receives a
		normalized t in [0, 1] and returns the eased value (typically also
		in [0, 1]; some easings overshoot, e.g. easeOutBack).

	Cairn.Gui.easings -> table
		Public registry keyed by easing name. Read-only externally. Built
		in: linear, easeIn, easeOut, easeInOut, easeOutBack, easeOutBounce.

	Cairn.Gui.ReduceMotion -> boolean (default false)
		Accessibility flag. When true, all subsequent Animate / Sequence /
		Parallel / Stagger / _animatePrimitiveColor calls clamp duration
		AND start-delay to zero, applying their target value synchronously
		and firing complete handlers synchronously. The animation queue is
		bypassed entirely, so the OnUpdate tick never runs for these. Off
		by default; consumers flip it via game settings, OS preference
		mirror, or programmatic test setup.

Public API on widget.Cairn (added to Mixins.Base):

	widget.Cairn:Animate(spec)
		Declarative API. spec maps property names to a per-property def.
		Two def shapes are supported:

		Duration + easing (default):
			{ to = number,    -- target value (required)
			  dur = number,   -- duration in seconds (default 0.2)
			  ease = string,  -- easing name (default "easeOut")
			  complete = fn } -- optional callback fired on completion

		Spring physics (set `spring` to opt in):
			{ to = number,
			  spring = {           -- non-nil swaps to spring path
			    stiffness = N,     -- default 170
			    damping   = N,     -- default 26
			    mass      = N,     -- default 1
			  },
			  complete = fn }

		Supported scalar properties:
			alpha   - frame:SetAlpha
			scale   - frame:SetScale
			width   - frame:SetWidth
			height  - frame:SetHeight

		Calling Animate again for an already-animating property REPLACES
		the in-flight animation, capturing the CURRENT value as the new
		"from". For springs, the in-flight VELOCITY also carries over,
		so a re-Animate during oscillation continues physically rather
		than snapping the velocity to zero.

		Unknown properties are silently ignored for forward-compat.

	widget.Cairn:Tween(prop, to, opts?)
		Imperative shortcut for the common single-property case.
		Equivalent to Animate({ [prop] = mergeInto({ to = to }, opts) }).
		Useful for one-shot calls: `cairn:Tween("alpha", 0.5, { dur = 0.3 })`.

	widget.Cairn:Sequence(steps, opts?)
		Run a list of specs one after another. Each step has the same
		shape as Animate's spec. The next step starts only after every
		property in the current step has completed. opts.complete (if
		set) fires after the last step. With ReduceMotion the entire
		chain unwinds synchronously inside the call.

	widget.Cairn:Parallel(steps, opts?)
		Run a list of specs simultaneously. opts.complete fires once
		every property across every step is done.

	widget.Cairn:Stagger(steps, delay, opts?)
		Like Parallel but each step starts (idx-1) * delay seconds after
		the call. Implemented via per-record `delay` countdown in the
		ticker, so Stagger remains deterministic and unit-testable. With
		ReduceMotion the start-delay is also clamped to zero, so the
		whole stagger collapses into a synchronous Parallel.

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
	- Records may carry a `delay` field. The ticker counts it down before
	  treating dt as elapsed time; overshoot rolls into elapsed on the
	  same tick so a 0.05s delay + 0.10s dt produces a 0.05s elapsed,
	  not zero. Used by Stagger; could be exposed via Animate later.
	- Auto-cancel on Release is wired by extending Base:Release in this
	  file (no edit to Mixins/Base.lua needed) -- the Release method
	  calls self:CancelAnimations() if the method exists.
	- Spring records use semi-implicit Euler integration. The threshold
	  for "settled" is lib.SpringSettleThreshold (default 0.001). When
	  both |position - rest| and |velocity| drop below it, the position
	  snaps to rest and the record completes.
	- A widget caps in-flight animations at lib.MaxConcurrentAnims
	  (default 64). New records past the cap evict the oldest in-flight
	  record silently. Defensive against pathological consumer code; not
	  intended as a routine throttle.

Status: Day 15 slices B + C + D. OKLCH, off-screen pause beyond Hide
cascade, and AnimationGroup-backend routing for Translation/Scale/Alpha/
Rotation are deferred (Day 15E candidates).
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 6
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

-- ReduceMotion accessibility flag. When truthy, animations skip the
-- queue entirely: target values apply synchronously and complete
-- handlers fire synchronously. See module header for full semantics.
if lib.ReduceMotion == nil then
	lib.ReduceMotion = false
end

-- Spring settle threshold. When |position - rest| and |velocity| both
-- drop below this, the spring completes (position snaps to rest, the
-- complete handler fires). Tunable per-deployment; the default is small
-- enough that visual snapping is imperceptible.
if lib.SpringSettleThreshold == nil then
	lib.SpringSettleThreshold = 0.001
end

-- Defensive concurrency cap. A widget with this many in-flight anims
-- evicts the oldest before adding more. Guards against runaway code,
-- not intended as a routine throttle.
if lib.MaxConcurrentAnims == nil then
	lib.MaxConcurrentAnims = 64
end

-- Spring defaults (Framer Motion's "smooth" preset). Override per-call
-- via def.spring = { stiffness, damping, mass }.
local SPRING_STIFFNESS_DEFAULT = 170
local SPRING_DAMPING_DEFAULT   = 26
local SPRING_MASS_DEFAULT      = 1

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Animation requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Easing registry -------------------------------------------------

-- Built-ins. easeInOut is the standard cubic in-out. easeIn/easeOut are
-- quadratic, slightly less aggressive than cubic, which reads more like
-- "subtle UI motion" than "dramatic motion graphics". easeOutBack
-- overshoots slightly past 1.0 then settles back; useful for "pop"
-- entrances. easeOutBounce uses the standard piecewise bounce profile
-- you'd find on caniuse.com / Robert Penner's easing equations.
local EASE_BACK_C1 = 1.70158
local EASE_BACK_C3 = EASE_BACK_C1 + 1
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
	easeOutBack = function(t)
		local u = t - 1
		return 1 + EASE_BACK_C3 * u * u * u + EASE_BACK_C1 * u * u
	end,
	easeOutBounce = function(t)
		local n1, d1 = 7.5625, 2.75
		if t < 1 / d1 then
			return n1 * t * t
		elseif t < 2 / d1 then
			t = t - 1.5 / d1
			return n1 * t * t + 0.75
		elseif t < 2.5 / d1 then
			t = t - 2.25 / d1
			return n1 * t * t + 0.9375
		else
			t = t - 2.625 / d1
			return n1 * t * t + 0.984375
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

-- Apply a record's final value plus run its complete handler. Used by
-- both the normal completion path inside the tick AND the ReduceMotion
-- fast-path in addAnim. Pulled out to keep the two call sites in sync.
local function applyFinal(self, a)
	-- All record types so far store the final value in a.to (scalar
	-- final, rgba final color table, spring rest position). The apply
	-- function is what differentiates them.
	if a.fromType == "scalar" or a.fromType == "rgba" or a.fromType == "spring" then
		a.apply(self, a.to)
	end
	if a.complete then
		local ok, err = pcall(a.complete, self, a)
		if not ok and lib._log and lib._log.Error then
			lib._log:Error("animation %s complete handler errored: %s",
				tostring(a.key), tostring(err))
		end
	end
end

local function tickAnimations(self, dt)
	local anims = self._anims
	if not anims or #anims == 0 then
		detachIfIdle(self)
		return
	end

	-- Records added during this tick (typically by a complete handler
	-- that calls Animate again -- e.g., Sequence's chain or any user
	-- code that re-Animates from inside a complete) wait until the next
	-- OnUpdate to start ticking. Without this guard, a synthetic large
	-- dt (or a slow real frame) could chain through an entire Sequence
	-- in one tick, producing zero per-step pacing. We capture the count
	-- of in-flight records at tick entry and stop processing once we've
	-- visited that many, regardless of late-comers.
	local processedTarget = #anims
	local processed       = 0

	local i = 1
	while processed < processedTarget and i <= #anims do
		local a = anims[i]
		local effectiveDt = dt
		local active      = true

		-- Pre-start delay countdown. Records can carry a `delay` field
		-- (set by Stagger). Subtract dt from delay; if it's still > 0
		-- the record is dormant this tick. If dt drained the delay, the
		-- overshoot becomes elapsed time on this same tick so we don't
		-- visibly stall a frame.
		if a.delay and a.delay > 0 then
			a.delay = a.delay - dt
			if a.delay > 0 then
				active = false
			else
				effectiveDt = -a.delay
				a.delay     = 0
			end
		end

		if active then
			local completed = false

			if a.fromType == "spring" then
				-- Semi-implicit Euler integration:
				--   force = -stiffness * (position - rest) - damping * velocity
				--   accel = force / mass
				--   velocity += accel * dt
				--   position += velocity * dt
				--
				-- Settle test: when both |position - rest| and |velocity|
				-- drop below SpringSettleThreshold, snap to rest exactly
				-- and complete. Avoids forever-decaying tails in the
				-- under-damped tail.
				local restPos   = a.to
				local position  = a.position or a.from
				local velocity  = a.velocity or 0
				local force     = -a.stiffness * (position - restPos)
				                  - a.damping * velocity
				local accel     = force / a.mass
				velocity        = velocity + accel * effectiveDt
				position        = position + velocity * effectiveDt
				a.position      = position
				a.velocity      = velocity

				local thresh = lib.SpringSettleThreshold or 0.001
				if math.abs(position - restPos) < thresh
					and math.abs(velocity) < thresh then
					a.position = restPos
					a.velocity = 0
					a.apply(self, restPos)
					completed  = true
				else
					a.apply(self, position)
				end
			else
				a.elapsed = (a.elapsed or 0) + effectiveDt
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

				if progress >= 1 then completed = true end
			end

			if completed then
				table.remove(anims, i)
				if self._animByKey then self._animByKey[a.key] = nil end
				if a.complete then
					local ok, err = pcall(a.complete, self, a)
					if not ok and lib._log and lib._log.Error then
						lib._log:Error("animation %s complete handler errored: %s",
							tostring(a.key), tostring(err))
					end
				end
				-- Removal shifted indices; don't advance i.
			else
				i = i + 1
			end
		else
			i = i + 1
		end

		processed = processed + 1
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
	rec.key = key

	-- ReduceMotion fast-path. Apply target synchronously, fire complete
	-- synchronously, never enter the queue. Any existing in-flight
	-- record under the same key is canceled first so we don't paint
	-- over the (now-final) value with a leftover lerp on a later tick.
	if lib.ReduceMotion then
		ensureAnimList(self)
		local existing = self._animByKey[key]
		if existing then
			for i, a in ipairs(self._anims) do
				if a == existing then
					table.remove(self._anims, i)
					break
				end
			end
			self._animByKey[key] = nil
		end
		applyFinal(self, rec)
		return
	end

	ensureAnimList(self)
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

	-- Defensive concurrency cap. If a widget has accumulated more than
	-- lib.MaxConcurrentAnims in-flight records (default 64), evict the
	-- OLDEST (lowest index) silently before appending. The cap is a
	-- guard against pathological consumer code, not a routine throttle.
	-- Same-key replacement above already happened, so the count we
	-- check is post-replacement.
	local cap = lib.MaxConcurrentAnims or 64
	if cap > 0 then
		while #self._anims >= cap do
			local oldest = self._anims[1]
			table.remove(self._anims, 1)
			if oldest and self._animByKey[oldest.key] == oldest then
				self._animByKey[oldest.key] = nil
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

			if type(def.spring) == "table" then
				-- Spring path. Carry the in-flight velocity forward
				-- when re-Animating an active spring so a hover-leave-
				-- hover during oscillation continues physically rather
				-- than zeroing out velocity.
				local existing = self._animByKey and self._animByKey[prop]
				local startVelocity = 0
				if existing and existing.fromType == "spring" then
					startVelocity = existing.velocity or 0
				end

				addAnim(self, prop, {
					fromType  = "spring",
					from      = fromValue,
					to        = def.to,
					position  = fromValue,
					velocity  = startVelocity,
					stiffness = def.spring.stiffness or SPRING_STIFFNESS_DEFAULT,
					damping   = def.spring.damping   or SPRING_DAMPING_DEFAULT,
					mass      = def.spring.mass      or SPRING_MASS_DEFAULT,
					apply     = function(_, v) applyFn(frame, v) end,
					complete  = def.complete,
				})
			else
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
		end
		-- Unknown props silently ignored. Allows forward-compat with
		-- future properties (rotation, translateX, etc.) and consumer
		-- typos without runtime errors.
	end
end

-- Imperative sugar over Animate for the common single-property case.
-- Equivalent to Animate({ [prop] = mergeInto({ to = to }, opts) }).
-- Useful for one-shot calls: cairn:Tween("alpha", 0.5, { dur = 0.3 }).
function Base:Tween(prop, to, opts)
	if type(prop) ~= "string" then
		error("Tween: prop must be a string", 2)
	end
	local def = { to = to }
	if type(opts) == "table" then
		for k, v in pairs(opts) do def[k] = v end
	end
	self:Animate({ [prop] = def })
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

-- ----- Composition primitives: Sequence / Parallel / Stagger ----------
--
-- All three accept `steps`: an array of specs in the same shape as
-- Animate's argument (prop -> def). A property def's `complete` is
-- preserved -- composition wraps it rather than replacing it.
--
-- Empty steps (or steps with no properties) are valid no-ops; the
-- top-level opts.complete still fires once, synchronously.

-- Shallow-copy a step so we can install our own complete wrappers
-- without mutating the caller's table.
local function copyStep(step)
	local out = {}
	for prop, def in pairs(step) do
		local d = {}
		for k, v in pairs(def) do d[k] = v end
		out[prop] = d
	end
	return out
end

-- Count the property defs in a step (#step on a hash map is undefined).
local function propCount(step)
	local n = 0
	for _ in pairs(step) do n = n + 1 end
	return n
end

function Base:Sequence(steps, opts)
	if type(steps) ~= "table" then
		error("Sequence: steps must be a table", 2)
	end
	opts = opts or {}

	local idx = 1
	local function fireNext()
		if idx > #steps then
			if opts.complete then opts.complete(self) end
			return
		end
		local step    = steps[idx]
		idx           = idx + 1
		local copy    = copyStep(step)
		local pending = propCount(copy)
		if pending == 0 then
			fireNext()
			return
		end
		for _, def in pairs(copy) do
			local origComplete = def.complete
			def.complete = function(widget, anim)
				if origComplete then origComplete(widget, anim) end
				pending = pending - 1
				if pending <= 0 then fireNext() end
			end
		end
		self:Animate(copy)
	end
	fireNext()
end

function Base:Parallel(steps, opts)
	if type(steps) ~= "table" then
		error("Parallel: steps must be a table", 2)
	end
	opts = opts or {}

	-- Total prop count across all steps.
	local total = 0
	for _, step in ipairs(steps) do total = total + propCount(step) end
	if total == 0 then
		if opts.complete then opts.complete(self) end
		return
	end

	local pending = total
	local function tally()
		pending = pending - 1
		if pending <= 0 and opts.complete then opts.complete(self) end
	end

	for _, step in ipairs(steps) do
		local copy = copyStep(step)
		for _, def in pairs(copy) do
			local origComplete = def.complete
			def.complete = function(widget, anim)
				if origComplete then origComplete(widget, anim) end
				tally()
			end
		end
		self:Animate(copy)
	end
end

function Base:Stagger(steps, delay, opts)
	if type(steps) ~= "table" then
		error("Stagger: steps must be a table", 2)
	end
	delay = delay or 0.05
	if type(delay) ~= "number" or delay < 0 then
		error("Stagger: delay must be a non-negative number", 2)
	end
	opts = opts or {}

	-- ReduceMotion clamps the per-step start delay to zero, collapsing
	-- the call into a synchronous Parallel. addAnim's fast-path handles
	-- the duration clamp for the underlying records.
	if lib.ReduceMotion then
		return Base.Parallel(self, steps, opts)
	end

	local total = 0
	for _, step in ipairs(steps) do total = total + propCount(step) end
	if total == 0 then
		if opts.complete then opts.complete(self) end
		return
	end

	local pending = total
	local function tally()
		pending = pending - 1
		if pending <= 0 and opts.complete then opts.complete(self) end
	end

	for stepIdx, step in ipairs(steps) do
		local copy        = copyStep(step)
		local startDelay  = (stepIdx - 1) * delay
		for _, def in pairs(copy) do
			local origComplete = def.complete
			def.complete = function(widget, anim)
				if origComplete then origComplete(widget, anim) end
				tally()
			end
		end
		-- Animate the step normally, then back-patch the underlying
		-- anim records with the start-delay. Animate uses property
		-- names as keys; we reach for them via _animByKey.
		self:Animate(copy)
		if startDelay > 0 and self._animByKey then
			for prop in pairs(copy) do
				local rec = self._animByKey[prop]
				if rec then rec.delay = startDelay end
			end
		end
	end
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
