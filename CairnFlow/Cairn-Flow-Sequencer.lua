--[[
Cairn-Flow-1.0 / Sequencer

A linear list of actions, each driven by a `fn` that returns truthy when
the step is done. The Sequencer advances on truthy, retries on falsy,
and exposes optional reset/abort gates that the consumer's drive loop
checks every Tick.

Typical use shape:

    local s = Cairn.Flow.Sequencer:New({
        actions = {
            { id = "wait-for-zone",   fn = function() return GetZoneText() == "Stormwind" end },
            { id = "fly-to-mailbox",  fn = function() return AtMailbox() end },
            { id = "open-mail",       fn = function() OpenMail(); return true end },
        },
        resetCondition = function() return PlayerInCombat() end,
        abortCondition = function() return PlayerDead() end,
        onComplete     = function() print("done") end,
        onAbort        = function(reason) print("aborted:", reason) end,
    })

    -- Driver: call :Tick from an OnUpdate, timer, or event handler.
    -- :Tick checks abort then reset gates, then runs the current step.
    s:Tick()

Public API:

    s:Tick()              -- drive one step: check gates, run current fn, advance if truthy
    s:Next()              -- skip current step manually; returns true if there was a step to advance
    s:Reset()             -- back to step 1, clear finished/aborted state
    s:Abort(reason?)      -- mark aborted, fire onAbort, stop responding to Tick
    s:IsFinished()        -- true once the last step returned truthy (or :Abort was called)
    s:IsAborted()         -- distinguish abort from clean completion
    s:CurrentStep()       -- returns { id = ..., index = N } for the active step, or nil if finished/aborted

Open question (a) resolution: Tick is the canonical public driver. Next
is exposed too but represents a manual skip — bypasses gate checks and
the current step's fn. CurrentStep returns BOTH id and index so consumers
can branch on either (id for human-readable logging, index for progress
bars).

Error isolation: every consumer callback (action fn, resetCondition,
abortCondition, onComplete, onAbort) is wrapped with Cairn.Util.Pcall.Call.
A throwing callback reports through geterrorhandler and the Sequencer
treats it as falsy (action) / no-trigger (gate) / no-op (lifecycle),
keeping the driver loop alive.
]]

local LIB_MAJOR = "Cairn-Flow-1.0"
local Cairn_Flow = LibStub(LIB_MAJOR, true)
if not Cairn_Flow then return end

local CU = LibStub("Cairn-Util-1.0", true)
local function safeCall(context, fn, ...)
    if CU and CU.Pcall and CU.Pcall.Call then
        return CU.Pcall.Call(context, fn, ...)
    end
    -- Fallback when Cairn-Util isn't loaded (standalone embed without it).
    -- Lose error reporting but keep the dispatch loop alive.
    if type(fn) ~= "function" then return true end
    return pcall(fn, ...)
end


local Sequencer = Cairn_Flow.Sequencer
Sequencer.__index = Sequencer


-- ============================================================================
-- Internal helpers
-- ============================================================================

local function validateActions(actions)
    if type(actions) ~= "table" or #actions == 0 then
        error("Cairn-Flow.Sequencer:New: opts.actions must be a non-empty array", 3)
    end
    local seenIds = {}
    for i, step in ipairs(actions) do
        if type(step) ~= "table" then
            error(("Cairn-Flow.Sequencer:New: actions[%d] must be a table"):format(i), 3)
        end
        if type(step.fn) ~= "function" then
            error(("Cairn-Flow.Sequencer:New: actions[%d].fn must be a function"):format(i), 3)
        end
        if step.id ~= nil and type(step.id) ~= "string" then
            error(("Cairn-Flow.Sequencer:New: actions[%d].id must be a string when provided"):format(i), 3)
        end
        if step.id and seenIds[step.id] then
            error(("Cairn-Flow.Sequencer:New: duplicate action id %q at index %d"):format(step.id, i), 3)
        end
        if step.id then seenIds[step.id] = true end
    end
end

local function callOptional(self, hookName, ...)
    -- WHY a single helper for optional lifecycle/gate calls: every callsite
    -- has the same shape (check the opts slot, route through safeCall with
    -- a context string that says which addon's seq + which hook fired).
    local fn = self._opts[hookName]
    if type(fn) ~= "function" then return end
    safeCall(
        ("Cairn-Flow.Sequencer(%s).%s"):format(self._name or "?", hookName),
        fn, ...)
end


-- ============================================================================
-- :New
-- ============================================================================
-- opts = {
--   actions = { { id = "..", fn = function() ... return done end }, ... },
--   resetCondition = function() return true end,   -- optional
--   abortCondition = function() return true end,   -- optional
--   onComplete     = function() end,                -- optional
--   onAbort        = function(reason) end,          -- optional, reason is string or nil
--   name           = "MySequencer",                 -- optional, used in error reports
-- }
function Sequencer:New(opts)
    if type(opts) ~= "table" then
        error("Cairn-Flow.Sequencer:New: opts must be a table", 2)
    end

    validateActions(opts.actions)

    for _, field in ipairs({ "resetCondition", "abortCondition", "onComplete", "onAbort" }) do
        if opts[field] ~= nil and type(opts[field]) ~= "function" then
            error(("Cairn-Flow.Sequencer:New: opts.%s must be a function when provided"):format(field), 2)
        end
    end

    if opts.name ~= nil and type(opts.name) ~= "string" then
        error("Cairn-Flow.Sequencer:New: opts.name must be a string when provided", 2)
    end

    local self = setmetatable({}, Sequencer)
    self._opts     = opts
    self._actions  = opts.actions
    self._name     = opts.name
    self._index    = 1
    self._finished = false
    self._aborted  = false
    self._abortReason = nil
    return self
end


-- ============================================================================
-- :Tick — the driver
-- ============================================================================
-- Single canonical drive method. The consumer loop (OnUpdate, timer,
-- event handler, etc.) calls :Tick whenever it wants to make progress;
-- :Tick is self-throttling in the sense that finished/aborted seqs are
-- a no-op. Gate-check order is fixed: abort first (cancels even if
-- reset would have re-armed), then reset (re-armed seqs run their
-- first step on the same Tick), then action dispatch.
function Sequencer:Tick()
    if self._finished or self._aborted then return end

    -- Abort gate (checked first; an abort beats a reset).
    if self._opts.abortCondition then
        local ok, triggered = safeCall(
            ("Cairn-Flow.Sequencer(%s).abortCondition"):format(self._name or "?"),
            self._opts.abortCondition)
        -- Pcall.Call returns (true, fn-returns...) or (false, err). The
        -- "triggered" we want is the FIRST fn-return, which Pcall.Call
        -- gives us as the second positional. ok=false means the gate
        -- threw and we treat it as "not triggered".
        if ok and triggered then
            self:Abort("abortCondition")
            return
        end
    end

    -- Reset gate.
    if self._opts.resetCondition then
        local ok, triggered = safeCall(
            ("Cairn-Flow.Sequencer(%s).resetCondition"):format(self._name or "?"),
            self._opts.resetCondition)
        if ok and triggered then
            self:Reset()
            -- Continue to action dispatch on this same Tick so the
            -- consumer doesn't have to wait one frame after reset.
        end
    end

    -- Action dispatch. Out-of-range index means we already finished;
    -- guard so :Reset followed by reaching past the end fires onComplete
    -- exactly once per completion (not on every Tick after finishing).
    local step = self._actions[self._index]
    if not step then
        -- Finished off the end; bookkeep + lifecycle.
        self._finished = true
        callOptional(self, "onComplete")
        return
    end

    local ok, done = safeCall(
        ("Cairn-Flow.Sequencer(%s).actions[%d]%s")
            :format(self._name or "?", self._index,
                    step.id and (" id=" .. step.id) or ""),
        step.fn)

    if ok and done then
        self._index = self._index + 1
        -- If we just advanced past the last step, finalize on this same
        -- Tick so consumers see :IsFinished() == true immediately rather
        -- than after one extra Tick. onComplete fires here.
        if self._index > #self._actions then
            self._finished = true
            callOptional(self, "onComplete")
        end
    end
end


-- ============================================================================
-- :Next — manual advance (bypasses gates AND current step's fn)
-- ============================================================================
-- Returns true if there was a step to advance past, false if the
-- sequencer was already finished or aborted. Useful for "skip the
-- current waiting step" buttons in a debug UI.
function Sequencer:Next()
    if self._finished or self._aborted then return false end
    self._index = self._index + 1
    if self._index > #self._actions then
        self._finished = true
        callOptional(self, "onComplete")
    end
    return true
end


-- ============================================================================
-- :Reset — back to step 1, clear finished/aborted state
-- ============================================================================
function Sequencer:Reset()
    self._index    = 1
    self._finished = false
    self._aborted  = false
    self._abortReason = nil
end


-- ============================================================================
-- :Abort — mark aborted and stop responding to Tick
-- ============================================================================
-- onAbort receives the reason string (or nil if Abort was called with
-- no argument). Idempotent: a second Abort on an already-aborted
-- sequencer is a silent no-op; onAbort does NOT re-fire.
function Sequencer:Abort(reason)
    if self._aborted or self._finished then return end
    self._aborted     = true
    self._abortReason = reason
    callOptional(self, "onAbort", reason)
end


-- ============================================================================
-- Introspection
-- ============================================================================
function Sequencer:IsFinished() return self._finished == true end
function Sequencer:IsAborted()  return self._aborted == true end
function Sequencer:CurrentStep()
    if self._finished or self._aborted then return nil end
    local step = self._actions[self._index]
    if not step then return nil end
    return { id = step.id, index = self._index }
end
