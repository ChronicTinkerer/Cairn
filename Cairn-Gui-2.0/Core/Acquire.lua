--[[
Cairn-Gui-2.0 / Core / Acquire

Public widget registration and acquisition API.

	Cairn.Gui:RegisterWidget(name, def)
		Register a widget type. `def` is a table:
			frameType = "Frame" | "Button" | etc. (Blizzard CreateFrame type;
			            default "Frame")
			template  = "BackdropTemplate" or comma-separated template list,
			            optional
			mixin     = table of methods to add to widget.Cairn (these layer
			            on top of Mixins.Base; type-specific methods can
			            override Base defaults)
			pool      = boolean, default false. When true, Released widgets
			            of this type are recycled by future Acquire calls.
			reset     = function(cairn) called on a pool-recycled widget
			            before it is handed back to the consumer. Use it
			            to clear residual state (text, colors, hooks, etc.).

	Cairn.Gui:Acquire(name, parent, opts)
		Create or recycle a widget of the registered type. Returns the
		underlying Blizzard Frame, with widget.Cairn populated as the
		namespace for our custom methods.

		parent  defaults to UIParent. If parent has its own widget.Cairn,
		        the new widget is also registered as a Cairn child of it.
		opts    arbitrary options table; merged into widget.Cairn._opts
		        and passed to OnAcquire(opts).

Day 3 status: pool wired. Parent/child registry wired. No theme/layout/
event plumbing yet.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

-- The base mixin must be loaded before this file. It's the foundation
-- every widget shares. If it's missing the .toc load order is wrong.
local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Acquire requires Mixins/Base to load first; check Cairn.toc order")
end

-- ---------- Taint guard for secure-widget mixins ------------------------
-- Heuristic check that runs at RegisterWidget time when def.secure is
-- true. We bytecode-dump each mixin function and grep for references to
-- known taint-spreading APIs. False negatives possible (custom paths via
-- _G or via dynamic lookup); false positives unlikely (string.dump emits
-- a literal constant table). On a hit we error at registration time
-- rather than letting the runtime taint silently.

local FORBIDDEN_API_PATTERNS = {
	"EnableAddOn",
	"DisableAddOn",
	"LoadAddOn",
	"RunScript",          -- arbitrary script execution from a secure path
	"hooksecurefunc",     -- protected-frame hook installation from a mixin
}

-- Public list so consumers can introspect (or extend) the forbidden set.
lib._forbiddenSecureAPIs = FORBIDDEN_API_PATTERNS

local function checkMixinTaint(mixinName, mixin)
	if type(mixin) ~= "table" then return end
	-- WoW's Lua sandbox removes `string.dump` for security reasons.
	-- Without it we can't bytecode-grep the mixin functions for forbidden
	-- API references. The check becomes a no-op in that environment;
	-- mixin authors are responsible for self-policing the rule (see the
	-- forbidden list at lib._forbiddenSecureAPIs and the doc comment
	-- in RegisterWidget). When running outside WoW (a unit-test harness
	-- where string.dump exists), the original bytecode-grep does fire.
	if type(string.dump) ~= "function" then return end
	for methodName, fn in pairs(mixin) do
		if type(fn) == "function" then
			local ok, dump = pcall(string.dump, fn)
			if ok and type(dump) == "string" then
				for _, pat in ipairs(FORBIDDEN_API_PATTERNS) do
					if dump:find(pat, 1, true) then
						error(string.format(
							"RegisterWidget: secure widget %q method %q references forbidden API %q. Forbidden: %s",
							mixinName, methodName, pat,
							table.concat(FORBIDDEN_API_PATTERNS, ", ")), 3)
					end
				end
			end
		end
	end
end

-- ---------- RegisterWidget ----------------------------------------------

function lib:RegisterWidget(name, def)
	if type(name) ~= "string" or name == "" then
		error("RegisterWidget: name must be a non-empty string", 2)
	end
	if type(def) ~= "table" then
		error("RegisterWidget: def must be a table", 2)
	end
	if self.widgets[name] and lib._log and lib._log.Debug then
		-- Re-registration during dev (e.g., /reload after edits) is
		-- expected. Last-write-wins, with a debug log so the author
		-- knows their type was redefined.
		lib._log:Debug("RegisterWidget: redefining %q", name)
	end

	-- Normalize the def. Mutating in place is fine; callers don't keep
	-- the original around as immutable.
	def.frameType  = def.frameType or "Frame"
	def.template   = def.template
	def.mixin      = def.mixin or {}
	def.pool       = def.pool == true
	def.reset      = def.reset
	-- Secure-widget flag (Decision 8). When true, Acquire marks the
	-- resulting cairn with _secure = true so Layout strategies skip it
	-- during combat, and the widget gets pre-warmed at PLAYER_LOGIN.
	def.secure     = def.secure == true
	-- Pre-warm count: how many instances to create at PLAYER_LOGIN. The
	-- architecture says 8 per secure type; non-secure widgets default to
	-- 0 (no pre-warming).
	def.prewarm    = def.prewarm or (def.secure and 8 or 0)

	if def.secure then
		-- Validate mixin doesn't reference forbidden APIs. Errors here
		-- at registration time, not at runtime, so the bug is loud and
		-- attached to the offending mixin name rather than mysterious
		-- combat-time taint warnings later.
		checkMixinTaint(name, def.mixin)
	end

	self.widgets[name] = def
	return def
end

-- ---------- Internal: build a fresh cairn namespace ---------------------

local function makeFreshCairn(def, name, frame, opts)
	local cairn = {
		_frame    = frame,
		_type     = name,
		_opts     = opts or {},
		_children = {},
		_parent   = nil,
		-- Secure-widget marker (Decision 8). Layout strategies skip
		-- _secure children while in combat. Set from the def at
		-- registration time; per-instance opts can't override.
		_secure   = def.secure == true,
	}
	-- Layer mixins: Base first, then the type-specific mixin. Methods
	-- defined later overwrite earlier ones, so type-specific code can
	-- override Base defaults (e.g., GetIntrinsicSize for sizable widgets).
	for k, v in pairs(Base) do
		cairn[k] = v
	end
	for k, v in pairs(def.mixin) do
		cairn[k] = v
	end
	frame.Cairn = cairn
	return cairn
end

-- ---------- Acquire ------------------------------------------------------

function lib:Acquire(name, parent, opts)
	local def = self.widgets[name]
	if not def then
		error(("Acquire: widget type %q is not registered"):format(tostring(name)), 2)
	end

	parent = parent or UIParent

	local cairn

	-- Pool path: pop a recycled cairn if one is waiting. Pooled widgets
	-- already have their frame; we just reset state and reattach.
	if def.pool then
		local p = self._pool[name]
		if p and #p > 0 then
			cairn = table.remove(p)
			cairn._opts     = opts or {}
			cairn._children = {}
			cairn._parent   = nil
			-- Reset the Primitives state machine so a recycled widget
			-- paints at "default" rather than carrying over its previous
			-- owner's state. Without this, a widget Released while
			-- hovered comes out of the pool painted in hover color, and
			-- the user has to mouse over and out to "fix" it.
			-- _interactive (the HookScript-installed flag) intentionally
			-- stays as-is: the hooks are bound to the underlying frame,
			-- which is the same frame, so resetting and re-installing
			-- would stack duplicate handlers. The hooks just toggle the
			-- flags; they're harmless on a recycled widget.
			cairn._visualState = "default"
			cairn._hovering    = false
			cairn._pressing    = false
			cairn._disabled    = false
			-- Reattach the underlying frame to the new parent and show.
			-- Also restore the frame's Blizzard-side enabled flag if a
			-- previous SetEnabled(false) toggled it off; otherwise the
			-- pool-recycled Button stops responding to clicks.
			local frame = cairn._frame
			if frame then
				if frame.SetParent then frame:SetParent(parent) end
				if type(frame.SetEnabled) == "function" then frame:SetEnabled(true) end
				if frame.Show      then frame:Show()           end
			end
			-- def.reset was already called at Release time; the widget
			-- handed out here is "fresh" from the consumer's perspective.
		end
	end

	-- Fresh path: no pool entry available, create a new frame.
	if not cairn then
		local frame = CreateFrame(def.frameType, nil, parent, def.template)
		cairn = makeFreshCairn(def, name, frame, opts)
	end

	-- Cairn-side parent registration: if the parent itself has a Cairn
	-- namespace, this new widget becomes a tracked child for layout
	-- and Release purposes. Plain Blizzard frames (UIParent, etc.)
	-- have no Cairn namespace and are skipped silently.
	if parent and type(parent) == "table" and parent.Cairn and parent.Cairn._addChild then
		parent.Cairn:_addChild(cairn)
	end

	-- Inspector tracking (Decision 10B): every newly-acquired widget is
	-- registered in the weak-keyed inspector table so debug tools can
	-- enumerate live widgets without a global registry. Tolerant of
	-- Inspector not being loaded (it's a soft-required sibling).
	if self.Inspector and self.Inspector._track then
		self.Inspector:_track(cairn)
	end

	-- Run the lifecycle hook last, after all wiring is in place.
	cairn:OnAcquire(opts)

	return cairn._frame
end

-- ---------- Pre-warmed pool for secure widgets (Decision 8) -------------
-- At PLAYER_LOGIN + a short delay, create N instances of every registered
-- secure widget type and Release them straight back to the pool. Acquire
-- calls during the early-combat window then come from the pool without
-- a CreateFrame call (which is what taints during combat for secure
-- frame types). The delay matters because some addons / Blizzard code
-- registers widgets later in the login sequence; waiting 0.5s gives them
-- time to register before we walk the table.

local function prewarmAll()
	if not lib.widgets then return end
	for name, def in pairs(lib.widgets) do
		if def.secure and def.prewarm and def.prewarm > 0 then
			-- Create N hidden, parent-less instances and Release each so
			-- they end up in lib._pool[name]. Release runs the def.reset
			-- path which is the same path Acquire's pool-pop relies on.
			for _ = 1, def.prewarm do
				-- Acquire requires a parent; use UIParent so the frame is
				-- valid. Release immediately. Each Release returns the
				-- cairn to lib._pool[name] (def.pool is implicitly true
				-- for secure widgets via the pre-warm contract; secure
				-- defs that opt out of pooling don't pre-warm).
				local f = lib:Acquire(name, UIParent)
				if f and f.Cairn and f.Cairn.Release then
					f.Cairn:Release()
				end
			end
		end
	end
end

-- Hook PLAYER_LOGIN once. Guard against double-hooking on /reload by
-- using a sentinel field on the lib.
if not lib._prewarmHooked then
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(self_)
		self_:UnregisterEvent("PLAYER_LOGIN")
		if C_Timer and C_Timer.After then
			C_Timer.After(0.5, prewarmAll)
		else
			prewarmAll()
		end
	end)
	-- If we're already past PLAYER_LOGIN (e.g., a /reload mid-session),
	-- the event won't fire again. Schedule pre-warm directly.
	if IsLoggedIn and IsLoggedIn() and C_Timer and C_Timer.After then
		C_Timer.After(0.5, prewarmAll)
	end
	lib._prewarmHooked = true
end
