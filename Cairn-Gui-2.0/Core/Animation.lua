--[[
Cairn-Gui-2.0 / Core / Animation

Implements Decision 9 from ARCHITECTURE.md. The full decision lists 11
sub-decisions; this file ships the engine, primitive transition tokens,
composition primitives, ReduceMotion accessibility flag, the standard
easing set, Spring physics, an imperative Tween shortcut, a per-widget
concurrency cap, OKLCH color interpolation (opt-in per primitive color
anim), off-screen pause (viewport-based plus clipping-ancestor walk),
and AnimationGroup-backend routing for Alpha and Scale (mappable
easings only; non-mappable easings and other properties stay on
OnUpdate). Translation and Rotation routing remain deferred -- they
need a "no underlying frame property" wrapper layer that's better
designed against a real consumer.

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
			  delay = number, -- optional start delay in seconds
			  complete = fn } -- optional callback fired on completion

		`delay` defers the animation's start by N seconds. Honored by
		both backends: OnUpdate records count it down before treating
		dt as elapsed; AnimationGroup records pass it through as
		anim:SetStartDelay before group:Play. Used internally by Stagger;
		consumers can also set it directly for a one-shot delayed call.

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

	widget.Cairn:_animatePrimitiveColor(slot, toColor, duration, easing, opts?)
		Used by the Primitives state machine when a state-variant spec
		carries a `transition` token. Captures the primitive's current
		vertex color as the "from", lerps RGBA over duration via the
		named easing, applies via SetVertexColor on every texture in the
		record. Replacement of an in-flight per-slot animation works the
		same as the public Animate (key is "primColor:<slot>").

		opts.colorSpace = "oklch" opts into OKLCH interpolation (opt-in
		per call). Endpoints are pre-converted once at addAnim time;
		each tick lerps L and C linearly, lerps hue along the shortest
		arc, and converts back to sRGB for the apply. Useful when a
		theme transitions between hues that pass through the desaturated
		region of RGB space (e.g., yellow -> blue, which is gray at the
		RGB midpoint but stays vivid in OKLCH).

	Cairn.Gui:RgbToOklch(r, g, b, a) -> L, C, h, a
	Cairn.Gui:OklchToRgb(L, C, h, a) -> r, g, b, a
		Public color-space conversions. r/g/b in [0, 1] sRGB; L/C in
		[0, ~0.4] typical UI range; h in [0, 360) degrees. Pure functions,
		safe to call any time after Animation.lua loads.

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
	- The tick early-returns when the widget's frame is positioned
	  entirely outside the UIParent viewport OR entirely outside any
	  DoesClipChildren ancestor's clipped rect. Animations freeze in
	  time (dt during off-screen is discarded, not banked) and resume
	  from their captured state when the frame returns on-screen. The
	  Hide cascade still handles "ancestor hidden" via Blizzard's auto-
	  pause; this layer adds "shown but off-screen" coverage for two
	  cases: Day 15G (positioned off the visible viewport) and 15H
	  (scrolled outside a clipping ancestor like a ScrollFrame's child).
	- Day 15I: AnimationGroup-backend routing for properties whose
	  adapter has backend = "animgroup" (currently only `alpha`). When
	  the easing maps to one of Blizzard's smoothing names (NONE / IN /
	  OUT / IN_OUT), addAnim creates a per-record AnimationGroup +
	  Animation, hooks OnFinished, and Plays the group. Blizzard runs
	  the animation on its own clock; the OnUpdate tick skips animgroup
	  records (they sit in the queue purely for replacement and
	  cancellation lookup). Non-mappable easings and the other
	  properties fall back to OnUpdate, so consumers see the same
	  visual curve they asked for. Caveats: Stagger's per-record delay
	  isn't honored by animgroup records yet (delay is for OnUpdate);
	  off-screen pause (15G/15H) doesn't apply to animgroup records
	  because Blizzard runs them past our gate. Both are deferred.

Status: Day 15 slices B + C + D + E + F + G + H + I + J + K.
AnimationGroup-backend routing for Alpha and Scale; Stagger now works
correctly for routed properties via SetStartDelay. Translation and
Rotation routing still deferred (need a wrapper layer designed against
a real consumer).
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 13
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

-- ----- OKLCH color space conversion ------------------------------------
--
-- OKLab is Bjorn Ottosson's perceptually-uniform color space (2020). The
-- polar form OKLCH (Lightness, Chroma, hue) is friendlier for designers
-- and far better than RGB for interpolation: a yellow -> blue lerp in
-- RGB passes through gray (because R, G, B all collapse to 0.5 at the
-- midpoint) but in OKLCH stays vivid through the whole arc.
--
-- Pipeline: sRGB <-> linear sRGB <-> OKLab <-> OKLCH.
--   sRGB <-> linear: standard gamma transfer (CSS Color 4 spec).
--   linear sRGB <-> OKLab: matrix + cube root (Ottosson's coefficients).
--   OKLab <-> OKLCH: polar / cartesian. C = sqrt(a^2 + b^2);
--                    h = atan2(b, a) in degrees.
--
-- These functions return scalars (not tables) to avoid allocation in
-- the conversion path. Hue h is normalized to [0, 360).

local function cbrt(x)
	-- Lua's `^` on negative bases with non-integer exponents returns NaN.
	-- Cube root of a negative is a real negative, so we mirror through 0.
	if x < 0 then return -((-x) ^ (1 / 3)) end
	return x ^ (1 / 3)
end

local function srgbToLinear(c)
	if c <= 0.04045 then return c / 12.92 end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function linearToSrgb(c)
	if c <= 0.0031308 then return c * 12.92 end
	return 1.055 * (c ^ (1 / 2.4)) - 0.055
end

local function rgbToOklab(r, g, b)
	r = srgbToLinear(r)
	g = srgbToLinear(g)
	b = srgbToLinear(b)
	local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	local lr = cbrt(l)
	local mr = cbrt(m)
	local sr = cbrt(s)
	local L = 0.2104542553 * lr + 0.7936177850 * mr - 0.0040720468 * sr
	local A = 1.9779984951 * lr - 2.4285922050 * mr + 0.4505937099 * sr
	local B = 0.0259040371 * lr + 0.7827717662 * mr - 0.8086757660 * sr
	return L, A, B
end

local function oklabToRgb(L, A, B)
	local lr = L + 0.3963377774 * A + 0.2158037573 * B
	local mr = L - 0.1055613458 * A - 0.0638541728 * B
	local sr = L - 0.0894841775 * A - 1.2914855480 * B
	local l = lr * lr * lr
	local m = mr * mr * mr
	local s = sr * sr * sr
	local r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	local b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	return linearToSrgb(r), linearToSrgb(g), linearToSrgb(b)
end

-- Internal versions: skip the self-shim so the tick loop can call them
-- directly without method-call overhead. Public wrappers below.
local function _rgbToOklch(r, g, b, a)
	local L, A, B = rgbToOklab(r, g, b)
	local C = math.sqrt(A * A + B * B)
	local h = math.deg(math.atan2(B, A))
	if h < 0 then h = h + 360 end
	return L, C, h, a or 1
end

local function _oklchToRgb(L, C, h, a)
	local rad = math.rad(h or 0)
	local A = (C or 0) * math.cos(rad)
	local B = (C or 0) * math.sin(rad)
	local r, g, b = oklabToRgb(L or 0, A, B)
	return r, g, b, a or 1
end

-- Public: r,g,b in [0,1] sRGB -> L,C,h (degrees), passes alpha through.
function lib:RgbToOklch(r, g, b, a)
	return _rgbToOklch(r or 0, g or 0, b or 0, a)
end

-- Public: L,C,h(deg) -> r,g,b in [0,1] sRGB, passes alpha through.
function lib:OklchToRgb(L, C, h, a)
	return _oklchToRgb(L or 0, C or 0, h or 0, a)
end

-- Internal: shortest-path hue lerp on [0, 360). Handles wrap so a hue
-- of 350 -> 10 takes the short way (20 degrees) instead of the long
-- way (340 degrees).
local function lerpHue(hFrom, hTo, t)
	local diff = hTo - hFrom
	if diff > 180 then
		hFrom = hFrom + 360
	elseif diff < -180 then
		hTo = hTo + 360
	end
	local h = hFrom + (hTo - hFrom) * t
	return h % 360
end

-- Internal: hue is undefined when chroma is zero; collapse to the
-- defined endpoint's hue so we don't lerp toward an arbitrary value.
-- Returns adjusted (hFrom, hTo).
local function reconcileGrayHues(cFrom, hFrom, cTo, hTo)
	local EPS = 1e-4
	if cFrom < EPS and cTo >= EPS then hFrom = hTo
	elseif cTo < EPS and cFrom >= EPS then hTo = hFrom
	end
	return hFrom, hTo
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

-- Returns true if the frame's UIParent-relative rect is entirely outside
-- (a) UIParent's viewport OR (b) any DoesClipChildren ancestor's clipped
-- rect. Animations whose frame is off-screen pause their tick (they
-- freeze in time; dt during off-screen is discarded, not banked). The
-- Hide cascade already covers the not-visible case via Blizzard auto-
-- pause; this catches:
--
--   Day 15G: "shown but positioned off-screen" cases like a slid-out
--   toast or a popped-in element animating off the visible viewport.
--
--   Day 15H: "shown but scrolled outside a clipping ancestor" cases
--   like a list item that's animated even though it's been scrolled
--   below the visible area of a ScrollFrame.
--
-- An unpositioned frame (GetLeft returns nil) is treated as on-screen so
-- we don't mistake "not yet laid out" for "off-screen" and pause work
-- the consumer is depending on. Same for ancestors that aren't yet
-- laid out -- they're skipped without aborting the walk.
local function isOffScreen(frame)
	if not frame or not frame.GetLeft then return false end
	local left = frame:GetLeft()
	if not left then return false end
	local right  = frame:GetRight()
	local top    = frame:GetTop()
	local bottom = frame:GetBottom()
	if not right or not top or not bottom then return false end

	-- (a) UIParent viewport check (Day 15G).
	local screenW = UIParent:GetWidth()
	local screenH = UIParent:GetHeight()
	if right <= 0 or left >= screenW or top <= 0 or bottom >= screenH then
		return true
	end

	-- (b) Clipping ancestor walk (Day 15H). For each ancestor in the
	-- parent chain that returns true from DoesClipChildren, check
	-- whether the widget is entirely outside that ancestor's rect. If
	-- so, the ancestor's clipping has hidden the widget regardless of
	-- the widget's own visibility flag, so we should pause.
	local parent = frame.GetParent and frame:GetParent()
	while parent do
		if parent.DoesClipChildren and parent:DoesClipChildren() then
			local pLeft = parent.GetLeft and parent:GetLeft()
			if pLeft then
				local pRight  = parent:GetRight()
				local pTop    = parent:GetTop()
				local pBottom = parent:GetBottom()
				if pRight and pTop and pBottom then
					if right  <= pLeft
						or left   >= pRight
						or top    <= pBottom
						or bottom >= pTop then
						return true
					end
				end
			end
		end
		parent = parent.GetParent and parent:GetParent() or nil
	end

	return false
end

-- ----- The tick (per-widget OnUpdate) ----------------------------------

-- Apply a record's final value plus run its complete handler. Used by
-- both the normal completion path inside the tick AND the ReduceMotion
-- fast-path in addAnim. Pulled out to keep the two call sites in sync.
local function applyFinal(self, a)
	-- All record types store the final value in a.to (scalar final,
	-- rgba final color table, spring rest position, animgroup final
	-- value). The apply function is what differentiates them. We
	-- check apply existence rather than the fromType allowlist so a
	-- new record type doesn't silently fall through to a no-op the
	-- way animgroup did pre-15I.
	if a.apply then
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

	-- Off-screen pause. If the widget's frame is positioned entirely
	-- outside the viewport, freeze every record (don't advance, don't
	-- apply). dt is discarded -- this is "pause" semantics, not "catch
	-- up" semantics. Animations resume from their captured state when
	-- the frame returns on-screen on a later tick.
	if isOffScreen(self._frame) then return end

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

		-- Day 15I: Animgroup records are driven by Blizzard's clock via
		-- OnFinished. The OnUpdate tick has nothing to do for them; skip
		-- without touching elapsed or apply. They sit in _anims/_animByKey
		-- for replacement and cancellation purposes only. The `processed`
		-- and `i` increments at the end of the loop body still apply.
		if a.fromType == "animgroup" then
			i = i + 1
		elseif active then
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
					if a.colorSpace == "oklch" then
						-- Lerp L and C linearly; lerp hue along the
						-- shortest arc on [0, 360). Alpha always lerps
						-- linearly in display space (no perceptual
						-- alpha curve in v1).
						local L = a.lFrom + (a.lTo - a.lFrom) * eased
						local C = a.cFrom + (a.cTo - a.cFrom) * eased
						local h = lerpHue(a.hFrom, a.hTo, eased)
						local r, g, b = _oklchToRgb(L, C, h)
						buf[1] = r
						buf[2] = g
						buf[3] = b
						buf[4] = from[4] + (to[4] - from[4]) * eased
					else
						buf[1] = from[1] + (to[1] - from[1]) * eased
						buf[2] = from[2] + (to[2] - from[2]) * eased
						buf[3] = from[3] + (to[3] - from[3]) * eased
						buf[4] = from[4] + (to[4] - from[4]) * eased
					end
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

-- Day 15I: Tear down an animgroup record's Blizzard state. Stops the
-- group (cancels the in-flight animation) and nils the OnFinished hook
-- so it can't fire on a record we've already removed from our queue.
-- Safe to call on records of any fromType (no-op for non-animgroup).
local function teardownAnimGroupRecord(rec)
	if not rec or rec.fromType ~= "animgroup" then return end
	if rec.animObject and rec.animObject.SetScript then
		rec.animObject:SetScript("OnFinished", nil)
	end
	if rec.animGroupForRecord and rec.animGroupForRecord.Stop then
		rec.animGroupForRecord:Stop()
	end
end

-- Add or replace an animation by key. Dispatches by rec.fromType after
-- the same shared bookkeeping (replacement, cap, ReduceMotion fast-path).
local function addAnim(self, key, rec)
	rec.key = key

	-- ReduceMotion fast-path. Apply target synchronously, fire complete
	-- synchronously, never enter the queue. Any existing in-flight
	-- record under the same key is canceled first so we don't paint
	-- over the (now-final) value with a leftover lerp on a later tick.
	-- Animgroup existing records also need their Blizzard group Stop'd
	-- and their OnFinished hook nil'd to avoid fire-on-dead-record.
	if lib.ReduceMotion then
		ensureAnimList(self)
		local existing = self._animByKey[key]
		if existing then
			teardownAnimGroupRecord(existing)
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
		teardownAnimGroupRecord(existing)
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
	-- check is post-replacement. Animgroup-evicted records also get the
	-- Blizzard teardown so their OnFinished can't fire late.
	local cap = lib.MaxConcurrentAnims or 64
	if cap > 0 then
		while #self._anims >= cap do
			local oldest = self._anims[1]
			teardownAnimGroupRecord(oldest)
			table.remove(self._anims, 1)
			if oldest and self._animByKey[oldest.key] == oldest then
				self._animByKey[oldest.key] = nil
			end
		end
	end

	self._anims[#self._anims + 1] = rec
	self._animByKey[key]          = rec

	if rec.fromType == "animgroup" then
		-- Day 15I: AnimationGroup-backend route. Build the Blizzard
		-- objects, hook OnFinished for completion, Play the group.
		-- Blizzard runs the animation on its own clock; our OnUpdate
		-- (if attached for other records) skips animgroup records.
		local group = self._frame:CreateAnimationGroup()
		local anim  = group:CreateAnimation(rec.animType)
		if anim.SetDuration then anim:SetDuration(rec.dur) end
		if rec.smoothing and anim.SetSmoothing then
			anim:SetSmoothing(rec.smoothing)
		end
		if rec.setupAnim then rec.setupAnim(anim, rec.from, rec.to) end
		-- Day 15K: Stagger and direct delay support. SetStartDelay must
		-- happen before Play(); the def.delay -> rec.delay -> SetStartDelay
		-- pipeline replaces the back-patch model that didn't reach the
		-- group in time on the animgroup path.
		if rec.delay and rec.delay > 0 and anim.SetStartDelay then
			anim:SetStartDelay(rec.delay)
		end

		rec.animObject         = anim
		rec.animGroupForRecord = group

		anim:SetScript("OnFinished", function()
			-- Apply final value defensively: Blizzard may leave the
			-- frame at the to value already, but enforcing it here
			-- means a OnFinished consumer can't observe a transient
			-- "almost done" reading. Safe to call.
			if rec.apply then rec.apply(self, rec.to) end
			-- Remove from queue.
			if self._anims then
				for i, a in ipairs(self._anims) do
					if a == rec then
						table.remove(self._anims, i)
						break
					end
				end
			end
			if self._animByKey and self._animByKey[rec.key] == rec then
				self._animByKey[rec.key] = nil
			end
			if rec.complete then
				local ok, err = pcall(rec.complete, self, rec)
				if not ok and lib._log and lib._log.Error then
					lib._log:Error("animation %s complete handler errored: %s",
						tostring(rec.key), tostring(err))
				end
			end
		end)

		if group.Play then group:Play() end
	else
		ensureAnimFrame(self)
	end
end

-- ----- Public Animate API ----------------------------------------------

-- Day 15I: Mappable easings can route to Blizzard's AnimationGroup
-- backend, which runs on Blizzard's clock instead of our OnUpdate. Our
-- four base easings map directly to Blizzard's smoothing parameter; non-
-- mappable easings (easeOutBack, easeOutBounce, custom-registered) fall
-- back to OnUpdate so consumers get the same visual behavior either way.
local EASING_TO_SMOOTHING = {
	linear    = "NONE",
	easeIn    = "IN",
	easeOut   = "OUT",
	easeInOut = "IN_OUT",
}

-- Adapters per property. `backend = "animgroup"` opts the property into
-- AnimationGroup routing (only when the easing is mappable). Properties
-- without `backend` always use OnUpdate. `animType` is the Blizzard
-- animation type name; `setupAnim` configures the from/to on the
-- created Animation object. Defensive about API availability: in
-- Retail (>= ~Shadowlands) Alpha animations support SetFromAlpha /
-- SetToAlpha; older builds may only have SetChange (delta) -- the
-- setupAnim closure tries the modern API first, falls back to delta.
local PROPERTY_ADAPTERS = {
	alpha = {
		get   = function(frame) return frame:GetAlpha() end,
		apply = function(frame, v) frame:SetAlpha(v) end,
		backend  = "animgroup",
		animType = "Alpha",
		setupAnim = function(anim, from, to)
			if anim.SetFromAlpha and anim.SetToAlpha then
				anim:SetFromAlpha(from)
				anim:SetToAlpha(to)
			elseif anim.SetChange then
				anim:SetChange(to - from)
			end
		end,
	},
	scale = {
		get   = function(frame) return frame:GetScale() end,
		apply = function(frame, v) frame:SetScale(v) end,
		backend  = "animgroup",
		animType = "Scale",
		-- Day 15J: Defensive across Blizzard's Scale animation API
		-- variants. Modern Retail (~Shadowlands+): SetScaleFrom /
		-- SetScaleTo for absolute scaling. Alternate naming seen in
		-- some references: SetFromScale / SetToScale. Legacy API: a
		-- single SetScale(x, y) that's the multiplier applied to the
		-- frame's scale at Play time -- so to go from `from` to `to`
		-- the multiplier is `to / from`. We try them in order; only
		-- one will exist, the others are nil-method short-circuits.
		setupAnim = function(anim, from, to)
			if anim.SetScaleFrom and anim.SetScaleTo then
				anim:SetScaleFrom(from, from)
				anim:SetScaleTo(to, to)
			elseif anim.SetFromScale and anim.SetToScale then
				anim:SetFromScale(from, from)
				anim:SetToScale(to, to)
			elseif anim.SetScale and from > 0 then
				local ratio = to / from
				anim:SetScale(ratio, ratio)
			end
		end,
	},
	width = {
		get   = function(frame) return frame:GetWidth() end,
		apply = function(frame, v) frame:SetWidth(v) end,
		-- No native AnimationGroup type for Width; OnUpdate only.
	},
	height = {
		get   = function(frame) return frame:GetHeight() end,
		apply = function(frame, v) frame:SetHeight(v) end,
		-- No native AnimationGroup type for Height; OnUpdate only.
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

			-- Day 15K: def.delay flows through to the record uniformly
			-- across all three branches. The OnUpdate ticker (15C) and
			-- the AnimationGroup branch (15I/J) both honor rec.delay.
			-- Stagger relies on this; consumers can also set it
			-- directly for a one-shot delayed animation.
			local startDelay = (type(def.delay) == "number" and def.delay > 0)
				and def.delay or nil

			if type(def.spring) == "table" then
				-- Spring path. Carry the in-flight velocity forward
				-- when re-Animating an active spring so a hover-leave-
				-- hover during oscillation continues physically rather
				-- than zeroing out velocity. Springs always go OnUpdate
				-- regardless of adapter.backend; physics integration
				-- has no AnimationGroup equivalent.
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
					delay     = startDelay,
					apply     = function(_, v) applyFn(frame, v) end,
					complete  = def.complete,
				})
			else
				-- Day 15I: Decide backend per spec. Adapter must opt in
				-- via backend = "animgroup", AND the chosen easing must
				-- map to one of Blizzard's smoothing names. Non-mappable
				-- easings (easeOutBack, easeOutBounce, custom-registered)
				-- fall back to OnUpdate so the rendered curve matches
				-- the easing the consumer asked for.
				local ease      = def.ease or "easeOut"
				local smoothing = adapter.backend == "animgroup"
					and EASING_TO_SMOOTHING[ease] or nil

				if smoothing then
					addAnim(self, prop, {
						fromType  = "animgroup",
						animType  = adapter.animType,
						from      = fromValue,
						to        = def.to,
						dur       = def.dur or 0.2,
						smoothing = smoothing,
						setupAnim = adapter.setupAnim,
						delay     = startDelay,
						apply     = function(_, v) applyFn(frame, v) end,
						complete  = def.complete,
					})
				else
					addAnim(self, prop, {
						fromType = "scalar",
						from     = fromValue,
						to       = def.to,
						dur      = def.dur or 0.2,
						ease     = ease,
						delay    = startDelay,
						apply    = function(_, v) applyFn(frame, v) end,
						complete = def.complete,
					})
				end
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
		-- Cancel everything. Tear down each animgroup record's Blizzard
		-- objects (Stop the group, nil OnFinished) before clearing.
		-- wipe() preserves the table identity so the existing
		-- _animByKey reference stays valid.
		for _, a in ipairs(anims) do
			teardownAnimGroupRecord(a)
		end
		wipe(anims)
		if self._animByKey then wipe(self._animByKey) end
	else
		local existing = self._animByKey and self._animByKey[prop]
		if existing then
			teardownAnimGroupRecord(existing)
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
			-- Day 15K: Push delay forward via def.delay BEFORE calling
			-- Animate. Replaces the prior back-patch-on-rec model
			-- (which couldn't reach an animgroup record's SetStartDelay
			-- because the group was already Playing by the time the
			-- back-patch loop ran). Single uniform path now works for
			-- both backends.
			if startDelay > 0 then
				def.delay = startDelay
			end
		end
		self:Animate(copy)
	end
end

-- ----- Internal: animate a primitive's color (used by transition wiring)

function Base:_animatePrimitiveColor(slot, toColor, duration, easingName, opts)
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

	local record = {
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
	}

	-- Opt-in OKLCH lerp. Pre-convert endpoints once at addAnim time so
	-- the per-tick cost is only one OKLCH->RGB conversion, not two
	-- conversions plus the lerp. Hue gets the shortest-arc treatment;
	-- gray endpoints inherit the other endpoint's hue so we don't lerp
	-- toward an arbitrary undefined value.
	if opts and opts.colorSpace == "oklch" then
		record.colorSpace = "oklch"
		local lF, cF, hF = _rgbToOklch(from[1], from[2], from[3])
		local lT, cT, hT = _rgbToOklch(to[1],   to[2],   to[3])
		hF, hT = reconcileGrayHues(cF, hF, cT, hT)
		record.lFrom, record.cFrom, record.hFrom = lF, cF, hF
		record.lTo,   record.cTo,   record.hTo   = lT, cT, hT
	end

	addAnim(self, "primColor:" .. slot, record)
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
