--[[
Cairn-FSM-1.0

Flat finite state machine with named states, transition graph, per-state
entry/exit hooks, optional guards/actions, and async transitions backed by
Cairn-Timer / Cairn-Sequencer. Per-state WoW event subscriptions auto-
register on enter and unregister on exit via Cairn-Events. Lifecycle
callbacks dispatch through Cairn-Callback.

Why a separate Cairn module:
    Cairn-Sequencer is a linear step-runner (advance when each step returns
    truthy). An FSM is a state graph with named transitions, entry/exit
    hooks, and event-driven changes. They compose, they don't overlap. An
    FSM with `actions = {...}` even uses Sequencer internally for that one
    transition kind.

The flat-now / hierarchical-later split is intentional. The internal
dispatch loop treats `states[name]` as a table of properties, never
assumes leaf-only. A future MINOR can let a state value itself contain
`{ initial, states }` for nested machines without changing the top-level
API surface.

Public API:

    local FSM = LibStub("Cairn-FSM-1.0")          -- or Cairn.FSM

    --- Spec --------------------------------------------------------------

    local spec = FSM.New({
        initial = "idle",
        context = { retries = 0 },                -- default per-instance bag
        states = {
            idle = {
                onEnter = function(m, payload) ... end,
                onExit  = function(m, payload) ... end,
                on = {
                    START = "running",                                 -- bare target
                    BOOM  = { target = "error",  action = fn },        -- side-effect
                    BAD   = { target = "error",  guard  = fn },        -- predicate
                    GO    = { target = "ready",  delay  = 1.5 },       -- async: timer
                    DRAIN = { target = "idle",   wait   = predFn,
                              timeout = 10, onTimeout = "error" },     -- async: poll
                    DEPLOY= { target = "deployed",
                              actions = { fn1, fn2, fn3 } },           -- async: steps
                },
            },
            running = {
                events = {                                             -- WoW events
                    PLAYER_REGEN_DISABLED = "FAIL",
                    PLAYER_DEAD = function(m, ...) m:Send("FAIL") end,
                },
                on = { STOP = "idle", FAIL = "error" },
            },
            error    = { onEnter = function(m, payload) ... end },
            ready    = { on = { GO = "running" } },
            deployed = {},
        },
        owner = "MyAddon",                       -- optional; tags Timer / Events.
        sendDuringPending = "drop",              -- "drop" | "queue" | "override"
    })

    --- Instance -----------------------------------------------------------

    local m = spec:Instantiate({ context = { retries = 1 } })

    m:Send(eventName, [payload])    -- request transition; payload merges into ctx
    m:State()                       -- "running" (FROM during pending async)
    m:Pending()                     -- { from=, to=, evt=, kind= } or nil
    m:Can(eventName)                -- true/false: would Send do anything now?
    m:Context()                     -- mutable context table
    m:Cancel()                      -- abort pending async transition
    m:Reset([payload])              -- back to spec.initial
    m:Destroy()                     -- unhook events, cancel timers, fire "Destroyed"

    --- Subscribe ---------------------------------------------------------

    m:On(eventKey, fn)              -- returns unsubscribe closure
    m:Off(eventKey)                 -- alternative removal

        Subscribers receive (eventKey, machine, ...trailing). Trailing
        args by event:
            "Transition"    (m, from, to, evt, payload)    -- after enter
            "Enter:<name>"  (m, payload)                   -- per-state entry
            "Exit:<name>"   (m, payload)                   -- per-state exit
            "Rejected"      (m, evt, reason)               -- guard / no rule
            "Cancelled"     (m, pendingDescriptor)         -- async aborted
            "Destroyed"     (m)                            -- machine torn down

Behavior contract:

    - Synchronous Send:
          1. Look up state.on[evt]. Missing rule => fire "Rejected" (no-op).
          2. Evaluate `guard(m, payload)` if present. False => fire
             "Rejected".
          3. Fire onExit(from, payload) on the FROM state, then
             "Exit:<from>".
          4. Run transition `action(m, payload)` if present (pcall).
          5. Switch m._state to TO. Fire onEnter(to, payload), then
             "Enter:<to>", then "Transition".
          6. Register TO's `events = {...}` map via Cairn-Events.

    - Async Send (delay / wait / actions):
          - onExit fires immediately (we've committed to leaving FROM).
          - Auto-registered events are unregistered immediately.
          - Pending descriptor populated; m:State() still returns FROM.
          - delay: Cairn-Timer:After(N) -> commit.
          - wait: Cairn-Timer:NewTicker(0.1) polling pred(m); commit on
            true. `timeout` (seconds) routes to `onTimeout` state instead.
          - actions: Cairn-Sequencer.New + ticker; commit on
            sequencer:Status() == "complete".
          - Cancel mid-flight: kills timer/sequencer, fires "Cancelled",
            re-registers FROM's onEnter events and clears pending. State
            stays FROM. (We did fire Exit:from on entry, so we re-fire
            Enter:from to keep symmetry; this matches the
            ENTER == "we're here now" contract.)

    - Send during pending: `sendDuringPending` controls behavior.
          drop     (default): ignore, fire "Rejected".
          queue              : queue and process when pending completes.
          override           : Cancel pending then process this Send.

    - Send during dispatch: re-entrant Send calls (from inside an onEnter,
      action, or callback) are queued and processed after the current
      dispatch unwinds. Prevents stack growth and reentrancy bugs.

    - Errors in user fns (guards, actions, onEnter, onExit, callbacks,
      events handlers) are pcall-trapped and routed to
      `geterrorhandler()`. A bad consumer can't kill the machine.

    - The machine acts as the Cairn-Timer / Cairn-Events `owner` so
      Destroy is a single CancelAll + UnsubscribeAll.

Cairn-FSM-1.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-FSM-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- ----- Sibling lib accessors ---------------------------------------------
-- We resolve sibling libs lazily and tolerantly. Hard-required libs error
-- at first use; soft-required libs (Sequencer for `actions`, Log for
-- diagnostics) gracefully no-op.

local function getEvents()    return LibStub("Cairn-Events-1.0",   true) end
local function getTimer()     return LibStub("Cairn-Timer-1.0",    true) end
local function getCallback()  return LibStub("Cairn-Callback-1.0", true) end
local function getSequencer() return LibStub("Cairn-Sequencer-1.0",true) end

local function getLog()
    if lib._log ~= nil then return lib._log end
    local Log = LibStub("Cairn-Log-1.0", true)
    if Log then lib._log = Log("Cairn.FSM") else lib._log = false end
    return lib._log or nil
end

-- ----- Helpers -----------------------------------------------------------

local function safecall(fn, ...)
    if type(fn) ~= "function" then return true end
    local ok, err = pcall(fn, ...)
    if not ok then
        local handler = geterrorhandler and geterrorhandler() or print
        handler(err)
    end
    return ok
end

local function isCallable(v)
    if type(v) == "function" then return true end
    if type(v) == "table" then
        local mt = getmetatable(v)
        return mt and type(mt.__call) == "function" or false
    end
    return false
end

local function shallowCopy(t)
    if type(t) ~= "table" then return {} end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function mergeInto(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

-- Normalize whatever the user wrote in `on` into a uniform descriptor.
local function normalizeRule(rule)
    if type(rule) == "string" then return { target = rule } end
    if type(rule) == "table"  then return rule end
    return nil
end

local function classifyAsync(rule)
    if rule.delay   ~= nil then return "delay"   end
    if rule.wait    ~= nil then return "wait"    end
    if rule.actions ~= nil then return "actions" end
    return nil
end

-- ----- Spec --------------------------------------------------------------
-- A Spec is a frozen recipe. Many machines can be Instantiated from one
-- spec; the spec itself is never mutated by machine activity.

local Spec = {}
Spec.__index = Spec

local function validateSpec(def)
    if type(def) ~= "table" then
        error("Cairn-FSM: spec must be a table", 3)
    end
    if type(def.initial) ~= "string" or def.initial == "" then
        error("Cairn-FSM: spec.initial must be a non-empty string", 3)
    end
    if type(def.states) ~= "table" then
        error("Cairn-FSM: spec.states must be a table", 3)
    end
    if def.states[def.initial] == nil then
        error(("Cairn-FSM: initial state %q has no entry in states"):format(def.initial), 3)
    end
    -- Validate transition targets resolve.
    for name, state in pairs(def.states) do
        if type(state) ~= "table" then
            error(("Cairn-FSM: state %q must be a table"):format(name), 3)
        end
        if state.on then
            for evt, raw in pairs(state.on) do
                local rule = normalizeRule(raw)
                if not rule or type(rule.target) ~= "string" then
                    error(("Cairn-FSM: state %q event %q has no target"):format(name, evt), 3)
                end
                if def.states[rule.target] == nil then
                    error(("Cairn-FSM: state %q event %q targets unknown state %q")
                        :format(name, evt, rule.target), 3)
                end
                if rule.onTimeout and def.states[rule.onTimeout] == nil then
                    error(("Cairn-FSM: state %q event %q onTimeout points to unknown state %q")
                        :format(name, evt, rule.onTimeout), 3)
                end
            end
        end
    end
end

function lib.New(def)
    validateSpec(def)
    local self = setmetatable({
        initial            = def.initial,
        states             = def.states,           -- read-only-by-convention
        defaultContext     = shallowCopy(def.context),
        owner              = def.owner or ("Cairn-FSM:" .. tostring(def.initial)),
        sendDuringPending  = def.sendDuringPending or "drop",
    }, Spec)
    return self
end

-- Forward declare so Spec:Instantiate can refer to it.
local Machine = {}
Machine.__index = Machine

function Spec:Instantiate(opts)
    opts = opts or {}
    local m = setmetatable({
        _spec        = self,
        _state       = self.initial,
        _context     = mergeInto(shallowCopy(self.defaultContext), opts.context),
        _owner       = opts.owner or self.owner,    -- tags Timer / Events
        _pending     = nil,                         -- { from, to, evt, kind, ... }
        _depth       = 0,                           -- re-entrancy depth
        _queue       = nil,                         -- pending Send during dispatch
        _eventUnsubs = nil,                         -- list of unsub closures
        _destroyed   = false,
        _callbacks   = nil,                         -- Cairn-Callback registry
    }, Machine)

    -- Wire the callback registry. If Cairn-Callback isn't loaded, On/Off
    -- become no-ops so consumers can still drive the machine bare.
    local Cb = getCallback()
    if Cb then m._callbacks = Cb.New("Cairn-FSM:" .. self.initial) end

    -- Enter the initial state. We pcall onEnter and skip "Transition"
    -- (no FROM state for the first entry). Auto-events are registered
    -- via _registerStateEvents.
    local s0 = self.states[self.initial]
    if s0 and s0.onEnter then safecall(s0.onEnter, m, opts.payload) end
    m:_fire("Enter:" .. self.initial, opts.payload)
    m:_registerStateEvents(self.initial)
    return m
end

-- ----- Machine -----------------------------------------------------------

function Machine:State()    return self._state end
function Machine:Context()  return self._context end
function Machine:Pending()  return self._pending and shallowCopy(self._pending) or nil end

function Machine:Can(evt)
    if self._destroyed then return false end
    if self._pending and self._spec.sendDuringPending == "drop" then return false end
    local state = self._spec.states[self._state]
    local rule  = state and state.on and normalizeRule(state.on[evt])
    return rule ~= nil
end

-- Subscribe / unsubscribe wrappers. `key` is the machine itself, so a
-- Destroy can UnsubscribeAll(self) in one call.
function Machine:On(eventKey, fn)
    if self._destroyed or not self._callbacks then return function() end end
    self._callbacks:Subscribe(eventKey, self, fn)
    -- Return an unsubscribe closure for ergonomic local-scope teardown.
    return function() self._callbacks:Unsubscribe(eventKey, self) end
end

function Machine:Off(eventKey)
    if self._destroyed or not self._callbacks then return end
    self._callbacks:Unsubscribe(eventKey, self)
end

-- Internal: fire a callback; tolerant of missing registry.
-- Always prepends `self` so subscribers see a uniform
-- (eventKey, machine, ...) shape regardless of which event fires. This
-- matches Cairn-Callback's "subscribers get (eventname, ...trailing)"
-- contract.
function Machine:_fire(eventKey, ...)
    if self._callbacks then self._callbacks:Fire(eventKey, self, ...) end
end

-- ----- Auto-event wiring -------------------------------------------------

function Machine:_registerStateEvents(name)
    local state = self._spec.states[name]
    if not state or not state.events then return end
    local Events = getEvents()
    if not Events then return end

    self._eventUnsubs = self._eventUnsubs or {}
    for evt, mapping in pairs(state.events) do
        -- mapping can be:
        --   "TRANSITION_NAME" -> Send(TRANSITION_NAME, ...)
        --   function(m, ...)  -> custom handler
        local handler
        if type(mapping) == "string" then
            local target = mapping
            handler = function(...) self:Send(target, { eventArgs = { ... } }) end
        elseif isCallable(mapping) then
            handler = function(...) safecall(mapping, self, ...) end
        else
            -- Bad spec slipped past validate; log and skip.
            local log = getLog()
            if log then log:Warn("state %q event %q has bad mapping", name, evt) end
        end
        if handler then
            local unsub = Events:Subscribe(evt, handler, self._owner)
            table.insert(self._eventUnsubs, unsub)
        end
    end
end

function Machine:_unregisterStateEvents()
    if not self._eventUnsubs then return end
    for i = 1, #self._eventUnsubs do safecall(self._eventUnsubs[i]) end
    self._eventUnsubs = nil
end

-- ----- Send and transition -----------------------------------------------

function Machine:Send(evt, payload)
    if self._destroyed then return false end

    -- Re-entrant Send from inside a callback / onEnter / action: queue it
    -- and bail. The unwinding outer Send will drain the queue.
    if self._depth > 0 then
        self._queue = self._queue or {}
        table.insert(self._queue, { evt = evt, payload = payload })
        return true
    end

    -- Pending async transition: behavior controlled by sendDuringPending.
    if self._pending then
        local mode = self._spec.sendDuringPending
        if mode == "queue" then
            self._queue = self._queue or {}
            table.insert(self._queue, { evt = evt, payload = payload })
            return true
        elseif mode == "override" then
            self:Cancel()
            -- fall through to normal dispatch
        else
            -- "drop" (default)
            self:_fire("Rejected", evt, "pending")
            return false
        end
    end

    return self:_dispatch(evt, payload)
end

function Machine:_dispatch(evt, payload)
    local state = self._spec.states[self._state]
    local rule  = state and state.on and normalizeRule(state.on[evt])
    if not rule then
        self:_fire("Rejected", evt, "no-rule")
        return false
    end

    -- Guard: if false, no transition happens.
    if rule.guard then
        local ok, allow = pcall(rule.guard, self, payload)
        if not ok then
            local handler = geterrorhandler and geterrorhandler() or print
            handler(allow) -- 'allow' is the error msg here
            self:_fire("Rejected", evt, "guard-error")
            return false
        end
        if not allow then
            self:_fire("Rejected", evt, "guard-false")
            return false
        end
    end

    -- Merge payload into context up front so guards/actions/onExit see
    -- the same state. This matches XState semantics and lets event-driven
    -- transitions stash event args on the context for later inspection.
    if type(payload) == "table" then mergeInto(self._context, payload) end

    -- Determine if async.
    local kind = classifyAsync(rule)
    if kind then
        return self:_startAsync(evt, rule, payload, kind)
    end

    -- Synchronous transition: delegate to _commitTransition (defined below).
    local from = self._state
    self:_commitTransition(from, rule.target, evt, payload, rule.action)
    self:_drainQueue()
    return true
end

-- _exitState: fire onExit, then "Exit:<name>", then drop auto-events.
function Machine:_exitState(name, payload)
    local state = self._spec.states[name]
    if state and state.onExit then safecall(state.onExit, self, payload) end
    self:_fire("Exit:" .. name, payload)
    self:_unregisterStateEvents()
end

-- _enterState: switch state, fire onEnter, register auto-events.
function Machine:_enterState(name, payload)
    self._state = name
    local state = self._spec.states[name]
    if state and state.onEnter then safecall(state.onEnter, self, payload) end
    self:_fire("Enter:" .. name, payload)
    self:_registerStateEvents(name)
end

-- Private commit helper used by sync and async paths so both fire the
-- same shape of "Transition" callback.
function Machine:_commitTransition(from, to, evt, payload, action)
    self._depth = self._depth + 1
    self:_exitState(from, payload)
    if action then safecall(action, self, payload) end
    self:_enterState(to, payload)
    self:_fire("Transition", from, to, evt, payload)
    self._depth = self._depth - 1
end

function Machine:_drainQueue()
    if not self._queue then return end
    -- Process queued items only after we're back at depth 0 and not pending.
    if self._depth > 0 or self._pending then return end
    local q = self._queue
    self._queue = nil
    for i = 1, #q do
        local item = q[i]
        if not self._destroyed then self:Send(item.evt, item.payload) end
    end
end

-- ----- Async transitions -------------------------------------------------
-- Async path: we leave FROM (fire onExit, drop auto-events) immediately,
-- store pending, run the timer / poll / sequencer, and on completion
-- enter TO. m:State() returns FROM during this window so consumers see
-- a coherent view.

function Machine:_startAsync(evt, rule, payload, kind)
    local from = self._state

    -- Fire onExit + Exit:<from> + drop FROM events. We've committed.
    self:_exitState(from, payload)

    self._pending = {
        from    = from,
        to      = rule.target,
        evt     = evt,
        kind    = kind,
        payload = payload,
        action  = rule.action,
        rule    = rule,
    }

    if kind == "delay" then
        local Timer = getTimer()
        if not Timer then
            -- No timer available; commit immediately as a degraded path.
            return self:_completePending()
        end
        self._pending.handle = Timer:After(rule.delay, function()
            if self._destroyed or not self._pending then return end
            self:_completePending()
        end, self._owner)

    elseif kind == "wait" then
        local Timer = getTimer()
        if not Timer then return self:_completePending() end
        local pred       = rule.wait
        local interval   = rule.pollInterval or 0.1
        local startedAt  = GetTime and GetTime() or 0
        local timeout    = rule.timeout
        local onTimeout  = rule.onTimeout
        self._pending.handle = Timer:NewTicker(interval, function()
            if self._destroyed or not self._pending then return end
            local ok, done = pcall(pred, self, payload)
            if not ok then
                local handler = geterrorhandler and geterrorhandler() or print
                handler(done)
                return
            end
            if done then
                self:_completePending()
                return
            end
            if timeout and GetTime then
                if (GetTime() - startedAt) >= timeout then
                    -- Reroute to onTimeout state if specified, else just
                    -- proceed to original target.
                    if onTimeout then self._pending.to = onTimeout end
                    self:_completePending()
                end
            end
        end, self._owner)

    elseif kind == "actions" then
        local Sequencer = getSequencer()
        local Timer     = getTimer()
        if not Sequencer or not Timer then
            -- Degrade: run the actions inline once, ignoring their return
            -- values, then commit. Better than silently doing nothing.
            for i = 1, #rule.actions do safecall(rule.actions[i], self) end
            return self:_completePending()
        end
        local seq = Sequencer.New(rule.actions, {})
        self._pending.sequencer = seq
        local interval = rule.tickInterval or 0.1
        self._pending.handle = Timer:NewTicker(interval, function()
            if self._destroyed or not self._pending then return end
            seq:Execute()
            if seq:Finished() then self:_completePending() end
        end, self._owner)
    end

    return true
end

function Machine:_completePending()
    local p = self._pending
    if not p then return false end
    self._pending = nil

    -- Cancel the driver. We may still hold a stale handle if e.g. a
    -- delay finished naturally (C_Timer doesn't need cancellation in
    -- that case), but defensive cleanup is cheap and prevents the
    -- wait-ticker case from re-entering.
    if p.handle then
        local Timer = getTimer()
        if Timer and Timer.Cancel then pcall(Timer.Cancel, Timer, p.handle) end
    end

    -- Run transition action (between exit and enter, like sync path).
    -- Note: onExit was already fired when async began, so we only need
    -- the action + enter half here.
    self._depth = self._depth + 1
    if p.action then safecall(p.action, self, p.payload) end
    self:_enterState(p.to, p.payload)
    self:_fire("Transition", p.from, p.to, p.evt, p.payload)
    self._depth = self._depth - 1

    self:_drainQueue()
    return true
end

function Machine:Cancel()
    local p = self._pending
    if not p then return false end
    self._pending = nil
    if p.handle then
        local Timer = getTimer()
        if Timer and Timer.Cancel then pcall(Timer.Cancel, Timer, p.handle) end
    end
    if p.sequencer and p.sequencer.Abort then pcall(p.sequencer.Abort, p.sequencer) end
    -- Re-enter FROM so the machine is in a coherent state again. We did
    -- fire Exit:from earlier, so symmetry says fire Enter:from now.
    self:_enterState(p.from, p.payload)
    self:_fire("Cancelled", p)
    self:_drainQueue()
    return true
end

-- ----- Reset / Destroy ---------------------------------------------------

function Machine:Reset(payload)
    if self._destroyed then return false end
    if self._pending then self:Cancel() end
    local from = self._state
    self:_exitState(from, payload)
    -- Don't run any transition action; Reset is unconditional.
    self:_enterState(self._spec.initial, payload)
    self:_fire("Transition", from, self._spec.initial, "@reset", payload)
    self:_drainQueue()
    return true
end

function Machine:Destroy()
    if self._destroyed then return end
    if self._pending then
        local p = self._pending
        self._pending = nil
        if p.handle then
            local Timer = getTimer()
            if Timer and Timer.Cancel then pcall(Timer.Cancel, Timer, p.handle) end
        end
        if p.sequencer and p.sequencer.Abort then pcall(p.sequencer.Abort, p.sequencer) end
    end
    self:_unregisterStateEvents()

    -- Owner-based mass cleanup (defense in depth: catches any timers /
    -- subscriptions whose individual closures might have been dropped).
    local Timer = getTimer()
    if Timer and Timer.CancelAll then pcall(Timer.CancelAll, Timer, self._owner) end
    local Events = getEvents()
    if Events and Events.UnsubscribeAll then pcall(Events.UnsubscribeAll, Events, self._owner) end

    self:_fire("Destroyed")
    if self._callbacks and self._callbacks.UnsubscribeAll then
        pcall(self._callbacks.UnsubscribeAll, self._callbacks, self)
    end
    self._destroyed = true
end
