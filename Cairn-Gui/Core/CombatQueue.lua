--[[
Cairn-Gui-2.0 / Core / CombatQueue

Combat-lockdown queue per Decision 8. Blizzard's protected-frame system
prevents addon-driven mutations of secure frames during combat (taint
prevention). This module tracks combat state, queues mutations on entry,
and drains the queue FIFO on exit.

Public API on lib (and exposed at lib.Combat for clarity):

	Cairn.Gui.Combat:InCombat()
		True when PLAYER_REGEN_DISABLED has fired and PLAYER_REGEN_ENABLED
		hasn't yet, OR when fake-combat is enabled.

	Cairn.Gui.Combat:Queue(target, methodName, ...)
		If we're in combat, append a (target, method, ...args) call to
		the queue and return true. Otherwise call target[methodName](...)
		immediately and return false. Use this for any mutation that's
		safe-to-defer (SetAttribute, SetText on a secure frame, etc.).

	Cairn.Gui.Combat:QueueClosure(fn)
		Like Queue but takes a single closure. Useful when a single deferred
		operation is several method calls that need to run together.

	Cairn.Gui.Combat:Drain()
		Manually drain the queue. Normally this fires on PLAYER_REGEN_ENABLED
		automatically; expose explicitly for tests / fake-combat exit.

	Cairn.Gui.Combat:SetFakeCombat(bool)
		Toggle fake-combat mode. When true, InCombat() returns true even
		if Blizzard's InCombatLockdown() is false. Forge's fake-combat
		button calls this. Useful for testing the queue path without
		actually getting into a fight.

	Cairn.Gui.Combat:OnLockdown(fn)
		Subscribe to combat-lockdown failures (operations that couldn't
		be queued, e.g., immediate-feedback-required calls). fn is called
		with (operationDescription, target, methodName). Returns an
		unsubscribe closure.

	Cairn.Gui.Combat:Stats()
		Returns { queued = N, drained = N, lockdownFailures = N, depth = N }.
		Useful for the Forge fake-combat tool to display queue health.

Cairn-Gui-2.0/Core/CombatQueue (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Combat = {}

-- Preserve state across LibStub upgrades within a session.
Combat.queue           = lib._combat and lib._combat.queue           or {}
Combat._fakeCombat     = lib._combat and lib._combat._fakeCombat     or false
Combat._lockdownSubs   = lib._combat and lib._combat._lockdownSubs   or {}
Combat._stats          = lib._combat and lib._combat._stats          or {
	queued           = 0,
	drained          = 0,
	lockdownFailures = 0,
}

-- ----- State queries ----------------------------------------------------

function Combat:InCombat()
	if self._fakeCombat then return true end
	return InCombatLockdown and InCombatLockdown() or false
end

-- ----- Queue / Drain ----------------------------------------------------

function Combat:Queue(target, methodName, ...)
	if not self:InCombat() then
		-- Not in combat; run immediately. Common-path no-op overhead is
		-- one InCombat() call plus the method dispatch.
		if type(target) == "table" and type(target[methodName]) == "function" then
			return false, target[methodName](target, ...)
		end
		return false
	end
	-- In combat: append to the queue. Args captured via select-pack.
	local n = select("#", ...)
	local entry = { target = target, method = methodName, n = n, ... }
	self.queue[#self.queue + 1] = entry
	self._stats.queued = self._stats.queued + 1
	return true
end

function Combat:QueueClosure(fn)
	if type(fn) ~= "function" then return end
	if not self:InCombat() then
		fn()
		return false
	end
	self.queue[#self.queue + 1] = { closure = fn }
	self._stats.queued = self._stats.queued + 1
	return true
end

local function safeRun(entry)
	if entry.closure then
		local ok, err = pcall(entry.closure)
		if not ok and geterrorhandler then geterrorhandler()(err) end
		return
	end
	local target, method = entry.target, entry.method
	if type(target) ~= "table" or type(target[method]) ~= "function" then return end
	-- Unpack the captured args back into the call.
	local args = {}
	for i = 1, entry.n do args[i] = entry[i] end
	local ok, err = pcall(target[method], target, unpack(args, 1, entry.n))
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

function Combat:Drain()
	if #self.queue == 0 then return 0 end
	-- Snapshot + clear FIRST so any handler that re-queues during drain
	-- (e.g., a layout that fires more mutations) appends to a fresh queue
	-- and we don't lose them or double-process this batch.
	local snap = self.queue
	self.queue = {}
	for i = 1, #snap do
		safeRun(snap[i])
		self._stats.drained = self._stats.drained + 1
	end
	-- Notify subscribers that the queue drained (useful for layout
	-- recompute on combat exit). Same OnLockdown path; reuse.
	return #snap
end

-- ----- Lockdown sink ----------------------------------------------------

function Combat:OnLockdown(fn)
	if type(fn) ~= "function" then return function() end end
	self._lockdownSubs[#self._lockdownSubs + 1] = fn
	return function()
		for i, sub in ipairs(self._lockdownSubs) do
			if sub == fn then table.remove(self._lockdownSubs, i); return end
		end
	end
end

function Combat:_reportLockdown(desc, target, methodName)
	self._stats.lockdownFailures = self._stats.lockdownFailures + 1
	for _, fn in ipairs(self._lockdownSubs) do
		local ok, err = pcall(fn, desc, target, methodName)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

-- ----- Fake combat (testing) -------------------------------------------

function Combat:SetFakeCombat(on)
	on = on and true or false
	if self._fakeCombat == on then return end
	local wasIn = self:InCombat()
	self._fakeCombat = on
	-- Simulate the corresponding combat transition so the queue behaves
	-- the same way real combat would: entering fake combat doesn't drain;
	-- exiting fake combat (and not actually in combat) drains.
	if wasIn and not self:InCombat() then
		self:Drain()
		self:_notifyCombatExit()
	end
end

function Combat:IsFakeCombat()
	return self._fakeCombat and true or false
end

-- ----- Stats ------------------------------------------------------------

function Combat:Stats()
	return {
		queued           = self._stats.queued,
		drained          = self._stats.drained,
		lockdownFailures = self._stats.lockdownFailures,
		depth            = #self.queue,
		inCombat         = self:InCombat(),
		fakeCombat       = self:IsFakeCombat(),
	}
end

-- ----- Combat-exit notifier --------------------------------------------
-- Layout code subscribes to this to force a relayout including secure
-- children once combat ends. A separate signal from OnLockdown so the
-- meaning stays distinct.

Combat._exitSubs = lib._combat and lib._combat._exitSubs or {}

function Combat:OnCombatExit(fn)
	if type(fn) ~= "function" then return function() end end
	self._exitSubs[#self._exitSubs + 1] = fn
	return function()
		for i, sub in ipairs(self._exitSubs) do
			if sub == fn then table.remove(self._exitSubs, i); return end
		end
	end
end

function Combat:_notifyCombatExit()
	for _, fn in ipairs(self._exitSubs) do
		local ok, err = pcall(fn)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

-- ----- Event listener ---------------------------------------------------
-- One frame, two events. Created once and preserved across reloads via
-- the lib._combat sentinel so we don't stack listeners.

if not lib._combat then
	local f = CreateFrame("Frame", "CairnGui2CombatQueueFrame")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			-- Real combat ended. Drain only if we're not also in fake
			-- combat (otherwise the user wants to keep simulating).
			if not Combat._fakeCombat then
				Combat:Drain()
				Combat:_notifyCombatExit()
			end
		end
	end)
	Combat._frame = f
end

-- ----- Publish ---------------------------------------------------------

lib.Combat  = Combat
lib._combat = Combat
