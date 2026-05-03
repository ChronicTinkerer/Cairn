--[[
Cairn-Sequencer-1.0

Composable step-runner. Each step is a function that returns truthy to
advance and falsy to retry on the next tick. A sequencer carries an
optional reset condition and abort condition, fires lifecycle callbacks
(OnStep / OnComplete / OnAbort / OnReset), and exposes a small inspector
API so guide UIs can render current/total state.

Public API:

	local seq = Cairn.Sequencer.New({
		function(s) return goToZone("Westfall") end,   -- truthy => advance
		function(s) return acceptQuest(123)   end,
		function(s) return killMobs(8)        end,
		function(s) return turnIn(123)        end,
	}, {
		resetWhen   = function() return playerLeftZone() end,
		abortWhen   = function() return questAbandoned() end,
		onStep      = function(seq, index, action) ... end,
		onComplete  = function(seq) ... end,
		onAbort     = function(seq) ... end,
		onReset     = function(seq) ... end,
	})

	seq:Execute()       -- run :Next once, after auto-checking reset/abort.
	                    -- Returns true if a step advanced this call.

	seq:Next()           -- raw advance (no reset/abort check).
	seq:Reset()          -- back to step 1, fires onReset.
	seq:Abort()          -- jumps past last step, fires onAbort.
	seq:Finished()       -- true once index > #actions.
	seq:Index()          -- 1-based current step index.
	seq:Total()          -- number of steps.
	seq:Current()        -- the current step function (nil when finished).
	seq:Progress()       -- (index - 1) / total, 0..1.
	seq:Status()         -- "pending" | "running" | "complete" | "aborted".

	seq:OnStep(fn)       -- subscribe; returns unsubscribe closure.
	seq:OnComplete(fn)
	seq:OnAbort(fn)
	seq:OnReset(fn)

	seq:SetActions(t)    -- replace step list; resets index.
	seq:Append(fn)       -- push a new step on the end.

Behavior contract:

	- On :Execute, if resetWhen() returns truthy the sequencer is reset
	  before the step runs. If abortWhen() returns truthy the sequencer
	  is aborted instead.
	- Step functions are called as `action(seq)`. Errors are pcall-trapped
	  so a single bad step doesn't kill the rest of the sequencer; the
	  error is logged via Cairn.Log("Cairn.Sequencer") if available.
	- A step returning truthy advances the index by 1 and fires onStep
	  with (seq, index_just_completed, action_just_completed). When the
	  index passes #actions, status becomes "complete" and onComplete
	  fires once.
	- :Reset() resets index to 1, clears the "complete" / "aborted" flag,
	  and fires onReset.
	- Subscribers (OnStep etc.) compose with the inline option callbacks;
	  both fire.

Why a separate Cairn module: any addon that runs an ordered list of
asynchronous-ish actions (guide steps, multi-stage tutorials, animation
chains, deploy-style preflight checks) needs the same shape. Pulled out
of Bastion's combat-rotation framework and generalized.
]]

local MAJOR, MINOR = "Cairn-Sequencer-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.Sequencer") end
	return lib._log
end

-- ----- helpers ----------------------------------------------------------

local function isCallable(v)
	if type(v) == "function" then return true end
	if type(v) == "table" then
		local mt = getmetatable(v)
		if mt and type(mt.__call) == "function" then return true end
	end
	return false
end

local function fireSubs(list, ...)
	if not list then return end
	-- Copy first so a callback unsubscribing itself mid-fire doesn't skip neighbors.
	local snap = {}
	for i = 1, #list do snap[i] = list[i] end
	for i = 1, #snap do
		local fn = snap[i]
		local ok, err = pcall(fn, ...)
		if not ok and logger() then
			logger():Warn("subscriber error: %s", tostring(err))
		end
	end
end

local function makeSub(list, fn)
	if not isCallable(fn) then
		error("Sequencer subscribe: fn must be callable", 3)
	end
	list[#list + 1] = fn
	return function()
		for i = 1, #list do
			if list[i] == fn then table.remove(list, i); return true end
		end
		return false
	end
end

-- ----- prototype --------------------------------------------------------

local proto = {}
local mt = { __index = proto }

function proto:_init(actions, opts)
	opts = opts or {}
	self._actions    = {}
	self._index      = 1
	self._status     = "pending"
	self._opts       = opts
	self._stepSubs   = {}
	self._doneSubs   = {}
	self._abortSubs  = {}
	self._resetSubs  = {}
	self:SetActions(actions or {})
end

function proto:SetActions(actions)
	if type(actions) ~= "table" then
		error("Sequencer:SetActions expects an array of functions", 2)
	end
	local copy = {}
	for i = 1, #actions do
		if not isCallable(actions[i]) then
			error(("Sequencer action %d is not callable"):format(i), 2)
		end
		copy[i] = actions[i]
	end
	self._actions = copy
	self._index = 1
	self._status = (#copy == 0) and "complete" or "pending"
end

function proto:Append(fn)
	if not isCallable(fn) then
		error("Sequencer:Append expects a callable", 2)
	end
	self._actions[#self._actions + 1] = fn
	if self._status == "complete" then
		-- A fresh action after we'd run dry; resume.
		self._status = "running"
	end
	return self
end

function proto:Index()    return self._index end
function proto:Total()    return #self._actions end
function proto:Status()   return self._status end
function proto:Finished() return self._index > #self._actions end

function proto:Current()
	if self:Finished() then return nil end
	return self._actions[self._index]
end

function proto:Progress()
	local n = #self._actions
	if n == 0 then return 1 end
	local done = self._index - 1
	if done < 0 then done = 0 end
	if done > n then done = n end
	return done / n
end

function proto:Reset()
	self._index  = 1
	self._status = (#self._actions == 0) and "complete" or "pending"
	if self._opts.onReset then pcall(self._opts.onReset, self) end
	fireSubs(self._resetSubs, self)
end

function proto:Abort()
	if self._status == "aborted" then return end
	self._status = "aborted"
	self._index = #self._actions + 1
	if self._opts.onAbort then pcall(self._opts.onAbort, self) end
	fireSubs(self._abortSubs, self)
end

local function complete(self)
	if self._status == "complete" then return end
	self._status = "complete"
	if self._opts.onComplete then pcall(self._opts.onComplete, self) end
	fireSubs(self._doneSubs, self)
end

function proto:Next()
	if self:Finished() then
		complete(self)
		return false
	end
	self._status = "running"
	local i = self._index
	local action = self._actions[i]
	local ok, result = pcall(action, self)
	if not ok then
		if logger() then logger():Warn("step %d errored: %s", i, tostring(result)) end
		return false
	end
	if result then
		self._index = i + 1
		if self._opts.onStep then pcall(self._opts.onStep, self, i, action) end
		fireSubs(self._stepSubs, self, i, action)
		if self:Finished() then complete(self) end
		return true
	end
	return false
end

function proto:Execute()
	-- Aborted sequencers stay aborted until reset.
	if self._status == "aborted" then return false end

	if self._opts.abortWhen then
		local ok, hit = pcall(self._opts.abortWhen, self)
		if ok and hit then self:Abort(); return false end
	end
	if self._opts.resetWhen then
		local ok, hit = pcall(self._opts.resetWhen, self)
		if ok and hit then self:Reset() end
	end
	return self:Next()
end

function proto:OnStep(fn)     return makeSub(self._stepSubs,  fn) end
function proto:OnComplete(fn) return makeSub(self._doneSubs,  fn) end
function proto:OnAbort(fn)    return makeSub(self._abortSubs, fn) end
function proto:OnReset(fn)    return makeSub(self._resetSubs, fn) end

function proto:__tostring()
	return ("Cairn.Sequencer(%d/%d, %s)"):format(self._index, #self._actions, self._status)
end

-- ----- factory ----------------------------------------------------------

function lib.New(actions, opts)
	local self = setmetatable({}, mt)
	proto._init(self, actions, opts)
	return self
end

setmetatable(lib, { __call = function(_, actions, opts) return lib.New(actions, opts) end })

return lib
