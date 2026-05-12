-- Cairn-Timer
-- Timing primitives: one-shot delays, repeating intervals, debounce, and a
-- stopwatch. All built on C_Timer (and GetTime for the stopwatch). Timer
-- handles support ownership tracking so consumers can batch-cancel.
--
--   local CT = LibStub("Cairn-Timer-1.0")
--
--   CT:After(5, Cleanup)                          -- one-shot
--   CT:Every(1, Update, { owner = MyAddon })      -- repeats forever
--   CT:Every(1, Update, { count = 5 })            -- repeats exactly 5x
--   CT:Debounce("refresh", 0.2, Render)           -- collapse rapid calls
--
--   local sw = CT:Stopwatch()                     -- starts immediately
--   sw:Read()                                      -- elapsed seconds (still running)
--   sw:Lap("phase1")                               -- named checkpoint
--   sw:Stop()                                      -- stop + return final
--   sw:Laps()                                      -- { [name] = elapsed }
--   sw:Reset()                                     -- restart from zero
--
--   CT:CancelOwner(MyAddon)                       -- batch-cancel all timers
--                                                  -- tagged with MyAddon
--
-- Public API (lib):
--   CT:After    (delay, fn [, opts [, ...]]) -> handle  -- opts: owner, obj, from
--   CT:Every    (delay, fn [, opts [, ...]]) -> handle  -- opts: owner, count, obj, from
--   CT:Debounce (key, delay, fn [, opts [, ...]]) -> handle -- opts: owner, obj, from
--   CT:Stopwatch()                    -> stopwatch
--   CT:CancelOwner(owner)
--   CT.timers       -- flat array of active After/Every/Debounce handles
--   CT.byOwner      -- { [owner] = { handle, handle, ... } }
--
-- MINOR 15 additions (2026-05-12 walk; Decisions 5 + 6):
--   CT:ContinueAfterCombat(fn)            -- fire now if out-of-combat, else
--                                            queue + drain on PLAYER_REGEN_ENABLED
--   CT:Start(slot, mode, period, fn)      -- unified push / ignore / duplicate /
--                                            cooldown debounce/throttle helper
--
-- MINOR 16 additions (Decisions 1, 2, 4, 7):
--   * `fn` may be a string method name OR function reference. String form
--     dispatches as `opts.obj[fn](opts.obj, args...)`; opts.obj is required.
--     Saves closure allocation on hot paths + honors late-binding.
--   * Variadic args after opts: forwarded to the callback with nil holes
--     preserved via `argsCount = select("#", ...)`. `CT:After(d, fn, opts,
--     "a", nil, "c")` delivers three args including the middle nil.
--   * fps-drift compensation on :Every — the next tick's delay subtracts
--     how late the previous tick fired so average frequency stays accurate
--     across long sessions even when individual ticks overshoot.
--   * `opts.from` caller-id tag + `Cairn.Timer.debugMode` flag + new
--     :GetCountAfter / :ResetCountAfter accessors for attribution
--     profiling. Counter logic short-circuits when debugMode is false
--     (production default).
--
-- Public API (timer handle):
--   handle:Cancel()
--   handle:IsCancelled()                          -> boolean
--   handle.delay, handle.fn, handle.owner, handle.repeating,
--   handle.count, handle.fired                    (read-only fields)
--
-- Public API (stopwatch):
--   sw:Read()                                     -> seconds since start
--   sw:Lap([name])                                -- record checkpoint
--   sw:Laps()                                     -> { [name] = elapsed }
--   sw:Stop()                                     -> final elapsed (stops the watch)
--   sw:Reset()                                    -- start over
--   sw:IsStopped()                                -> boolean
--
-- Semantics:
--   - After: one-shot. After firing OR after Cancel, the handle is untracked.
--   - Every: repeating. With opts.count it auto-cancels after N fires. Without,
--     it runs until cancelled. There's no consumer-side forward-reference
--     dance; the lib handles the bookkeeping.
--   - Debounce: rapid calls with the same key cancel any pending timer and
--     schedule a fresh one. Only the FINAL call (after `delay` of quiet)
--     fires `fn`. The key identifies the debounce slot — choose a stable
--     string per logical "thing to debounce" (e.g. "MyAddon:RefreshBars").
--   - Errors in callbacks are pcall-isolated and routed to geterrorhandler().
--     A throwing Every tick does NOT stop subsequent ticks.
--   - Cancel is idempotent.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Timer-1.0"
local LIB_MINOR = 16

local Cairn_Timer = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Timer then return end

local CU = LibStub("Cairn-Util-1.0")
local Pcall, Table_ = CU.Pcall, CU.Table  -- aliased to avoid shadowing Lua's table


Cairn_Timer.timers     = Cairn_Timer.timers     or {}
Cairn_Timer.byOwner    = Cairn_Timer.byOwner    or {}
Cairn_Timer._debounces = Cairn_Timer._debounces or {}  -- {[key] = handle}

-- MINOR 16 — Decision 7: caller-id attribution. Toggle `Cairn.Timer.debugMode
-- = true` at runtime to enable per-`from`-tag counting; production default
-- is off so the counter logic short-circuits to a single nil-check per
-- fire. Counts persist across `:Cancel` and `:CancelOwner` (the counter
-- tracks "how many fires came from each tag" over the session, not
-- "currently active timers").
Cairn_Timer.debugMode    = Cairn_Timer.debugMode    or false
Cairn_Timer._fromCounts  = Cairn_Timer._fromCounts  or {}


-- ---------------------------------------------------------------------------
-- Internal: tracking
-- ---------------------------------------------------------------------------

local function track(handle)
    local self = Cairn_Timer
    self.timers[#self.timers + 1] = handle

    local owner = handle.owner
    if owner ~= nil then
        local bucket = self.byOwner[owner]
        if not bucket then
            bucket = {}
            self.byOwner[owner] = bucket
        end
        bucket[#bucket + 1] = handle
    end
end


-- Three structures track each timer: the flat .timers list (introspection),
-- the per-owner bucket (batch cancel), and the _debounces key-map (only for
-- Debounce timers). Untrack has to clean all three or we'll either keep
-- references that prevent GC, leak owner buckets, or leave a stale debounce
-- entry that breaks subsequent Debounce calls with the same key.
local function untrack(handle)
    local self = Cairn_Timer

    for i = #self.timers, 1, -1 do
        if self.timers[i] == handle then
            table.remove(self.timers, i)
        end
    end

    local owner = handle.owner
    if owner ~= nil then
        local bucket = self.byOwner[owner]
        if bucket then
            for i = #bucket, 1, -1 do
                if bucket[i] == handle then
                    table.remove(bucket, i)
                end
            end
            if #bucket == 0 then
                self.byOwner[owner] = nil
            end
        end
    end

    -- Only clear _debounces[key] if the active entry there is US — a newer
    -- Debounce call with the same key may have already replaced this entry.
    if handle.debounceKey and self._debounces[handle.debounceKey] == handle then
        self._debounces[handle.debounceKey] = nil
    end
end


-- ---------------------------------------------------------------------------
-- Internal: handle methods (shared metatable)
-- ---------------------------------------------------------------------------

local HandleMethods = {}

function HandleMethods:Cancel()
    if self.cancelled then return end
    self.cancelled = true
    untrack(self)
end

function HandleMethods:IsCancelled()
    return self.cancelled == true
end

local HandleMeta = { __index = HandleMethods }


-- ---------------------------------------------------------------------------
-- Internal: tick scheduling
-- ---------------------------------------------------------------------------

-- Thin wrapper over Cairn-Util.Pcall.Call. The fixed context string keeps
-- the byte-for-byte error text consumers see ("Cairn-Timer: callback threw:
-- ...") identical to the pre-refactor form.
--
-- MINOR 16 — Decisions 1 + 4 + 7:
--   * `handle.fn` accepts a string method name OR a function reference.
--     String form dispatches as `obj[name](obj, args...)` where `obj`
--     is `handle.obj` (set via opts.obj or opts.target). Saves closure
--     allocation on hot paths AND honors late-binding (method body can
--     be swapped between scheduling and firing).
--   * `handle.args` + `handle.argsCount` preserve nil holes via
--     `unpack(args, 1, argsCount)`. Positional locals for the most
--     common arg-counts up to 7 (legacy "hot-path arg forwarding")
--     could land later; for now the table+argsCount path is correct
--     for every case.
--   * `handle.from` caller-id is counted (when debugMode is set) by
--     the caller of safeCall, NOT here, so the counting is exactly
--     once-per-fire regardless of repeating semantics.
local function safeCall(handle)
    local fn   = handle.fn
    local obj  = handle.obj
    local args = handle.args
    local n    = handle.argsCount or 0

    if type(fn) == "string" then
        -- String method dispatch: obj[fn](obj, ...).
        if obj == nil then
            -- Mis-wiring; surface loudly so consumers see it.
            geterrorhandler()(
                ("Cairn-Timer: fn '%s' is a string method name but handle.obj is nil "
                 .. "(pass opts.obj when fn is a string)"):format(tostring(fn)))
            return
        end
        local method = obj[fn]
        if type(method) ~= "function" then
            geterrorhandler()(
                ("Cairn-Timer: obj['%s'] is not a function (got %s)")
                :format(tostring(fn), type(method)))
            return
        end
        if n > 0 then
            Pcall.Call("Cairn-Timer: callback", method, obj, unpack(args, 1, n))
        else
            Pcall.Call("Cairn-Timer: callback", method, obj)
        end
    else
        if n > 0 then
            Pcall.Call("Cairn-Timer: callback", fn, unpack(args, 1, n))
        else
            Pcall.Call("Cairn-Timer: callback", fn)
        end
    end
end


local scheduleTick   -- forward declaration


-- Both fire paths check `cancelled` BEFORE invoking the callback because
-- C_Timer.After can't be cancelled at the Blizzard level — a callback we
-- scheduled before :Cancel was called will still fire. The pre-check is
-- what makes Cancel actually stop pending ticks.
--
-- They also re-check `cancelled` AFTER the callback. Why: the callback
-- itself might have called handle:Cancel() (e.g. a custom self-terminating
-- loop), in which case we must NOT mark cancelled or reschedule.
local function fireOnce(handle)
    if handle.cancelled then return end
    safeCall(handle)
    handle.fired = (handle.fired or 0) + 1
    if not handle.cancelled then
        handle.cancelled = true
        untrack(handle)
    end
end


-- Auto-cancel at count is the "consumer doesn't have to write the counter"
-- payoff. Without it the consumer would need a closure-captured forward
-- reference to call self:Cancel() — that pattern was rejected explicitly
-- in the design review (memory: cairn_simplicity_applies_to_consumer.md).
--
-- MINOR 16 — Decision 2: fps-drift compensation. Each tick records the
-- expected-end time; the next tick's delay subtracts how late we are
-- (capped at zero for "immediate next tick" semantics on extreme drift).
-- Without compensation, a "tick every 5s" timer accumulates seconds of
-- lag across long sessions because individual ticks routinely overshoot
-- by tens-to-hundreds of milliseconds.
local function fireRepeating(handle)
    if handle.cancelled then return end

    -- Capture wall-clock NOW for drift math AFTER firing.
    local nowBefore = GetTime and GetTime() or 0

    if handle.from and Cairn_Timer.debugMode then
        -- D7: bump caller-id counter exactly once per fire.
        local map = Cairn_Timer._fromCounts
        map[handle.from] = (map[handle.from] or 0) + 1
    end

    safeCall(handle)
    handle.fired = (handle.fired or 0) + 1

    if handle.count and handle.fired >= handle.count then
        if not handle.cancelled then
            handle.cancelled = true
            untrack(handle)
        end
        return
    end

    if not handle.cancelled then
        -- Drift compensation: shorten the next delay by however late
        -- this tick fired vs. the expected schedule. Capped at zero
        -- so we never request a negative delay (C_Timer.After would
        -- treat that as "immediate" but consistent zero is clearer).
        if handle._expectedFireAt and GetTime then
            local now  = GetTime()
            local late = now - handle._expectedFireAt
            local next_ = handle.delay - late
            if next_ < 0 then next_ = 0 end
            handle._nextDelay = next_
            handle._expectedFireAt = now + next_
        end
        scheduleTick(handle)
    end
end


scheduleTick = function(handle)
    -- D2 fps-drift: prefer the compensated _nextDelay if present
    -- (set by fireRepeating). On first schedule, seed _expectedFireAt
    -- from the base delay so future drift math has a baseline.
    local delay = handle._nextDelay or handle.delay
    handle._nextDelay = nil  -- one-shot use
    if handle._expectedFireAt == nil and GetTime then
        handle._expectedFireAt = GetTime() + delay
    end
    C_Timer.After(delay, function()
        if handle.repeating then
            fireRepeating(handle)
        else
            -- One-shot path: count for D7 here too.
            if handle.from and Cairn_Timer.debugMode then
                local map = Cairn_Timer._fromCounts
                map[handle.from] = (map[handle.from] or 0) + 1
            end
            fireOnce(handle)
        end
    end)
end


-- ---------------------------------------------------------------------------
-- Internal: validation
-- ---------------------------------------------------------------------------

-- MINOR 16: opts.obj (Decision 1) + opts.from (Decision 7) added.
-- Returns (owner, count, obj, from). Validation rules same as before
-- plus shape checks on the new fields.
local function validateOpts(opts, methodLabel, allowCount)
    if opts == nil then return nil, nil, nil, nil end
    if type(opts) ~= "table" then
        error(("Cairn-Timer:%s: opts must be a table or nil"):format(methodLabel), 3)
    end
    if opts.count ~= nil then
        if not allowCount then
            error(("Cairn-Timer:%s: opts.count is only valid on :Every"):format(methodLabel), 3)
        end
        if type(opts.count) ~= "number" or opts.count < 1 or opts.count ~= math.floor(opts.count) then
            error(("Cairn-Timer:%s: opts.count must be a positive integer"):format(methodLabel), 3)
        end
    end
    if opts.from ~= nil and type(opts.from) ~= "string" then
        error(("Cairn-Timer:%s: opts.from must be a string or nil"):format(methodLabel), 3)
    end
    -- opts.obj has no type constraint — typically a table, but the
    -- caller's mental model is "the receiver"; we just pass it through.
    return opts.owner, opts.count, opts.obj, opts.from
end


-- MINOR 16 (Decisions 1 + 4): fn accepts string method name OR function;
-- variadic args after opts are captured with argsCount so nil holes are
-- preserved on dispatch.
local function newHandle(delay, fn, opts, repeating, methodLabel, debounceKey, args, argsCount)
    if type(delay) ~= "number" or delay < 0 then
        error(("Cairn-Timer:%s: delay must be a non-negative number"):format(methodLabel), 3)
    end
    if type(fn) ~= "function" and type(fn) ~= "string" then
        error(("Cairn-Timer:%s: fn must be a function or method-name string"):format(methodLabel), 3)
    end

    local owner, count, obj, from = validateOpts(opts, methodLabel, repeating)

    -- Cross-check: string method needs a receiver to dispatch on.
    if type(fn) == "string" and obj == nil then
        error(("Cairn-Timer:%s: fn is a string method name '%s' but opts.obj is nil"):format(
              methodLabel, fn), 3)
    end

    local handle = setmetatable({
        delay        = delay,
        fn           = fn,
        owner        = owner,
        obj          = obj,           -- Decision 1: receiver for string-fn dispatch
        from         = from,          -- Decision 7: caller-id (counted when debugMode)
        repeating    = repeating,
        count        = count,
        fired        = 0,
        cancelled    = false,
        debounceKey  = debounceKey,   -- nil for After/Every; set for Debounce
        args         = args,          -- Decision 4: nil if no args supplied
        argsCount    = argsCount or 0,
    }, HandleMeta)

    track(handle)
    scheduleTick(handle)
    return handle
end


-- ---------------------------------------------------------------------------
-- Public API: timing primitives
-- ---------------------------------------------------------------------------

-- MINOR 16 (Decision 4): variadic args after opts. Naive `{...}` would
-- truncate at the first nil; argsCount preserves nil holes for accurate
-- callback dispatch. The (delay, fn, opts) 3-arg form remains unchanged
-- for existing consumers — variadic args are forwarded only when supplied.
function Cairn_Timer:After(delay, fn, opts, ...)
    local n = select("#", ...)
    local args = n > 0 and { ... } or nil
    return newHandle(delay, fn, opts, false, "After", nil, args, n)
end


function Cairn_Timer:Every(delay, fn, opts, ...)
    local n = select("#", ...)
    local args = n > 0 and { ... } or nil
    return newHandle(delay, fn, opts, true, "Every", nil, args, n)
end


-- Each call cancels the pending timer for this key and schedules a fresh
-- one. The "fire X seconds after the LAST call" semantics emerge from this
-- naturally: a burst of N calls leaves only the final timer alive, the
-- prior N-1 having been replaced before they could fire.
--
-- Choose stable keys per logical "thing to debounce" (e.g.
-- "MyAddon:RefreshBars"). Using consumer-supplied keys instead of
-- generated tokens keeps the API one-arg simple at the call site.
function Cairn_Timer:Debounce(key, delay, fn, opts, ...)
    if type(key) ~= "string" or key == "" then
        error("Cairn-Timer:Debounce: key must be a non-empty string", 2)
    end
    local existing = self._debounces[key]
    if existing and not existing.cancelled then
        existing:Cancel()
    end
    local n = select("#", ...)
    local args = n > 0 and { ... } or nil
    local handle = newHandle(delay, fn, opts, false, "Debounce", key, args, n)
    self._debounces[key] = handle
    return handle
end


-- Snapshot first because :Cancel mutates the bucket (via untrack), which
-- we'd be iterating. Same defensive pattern as Cairn-Events / Cairn-Hooks.
function Cairn_Timer:CancelOwner(owner)
    if owner == nil then
        error("Cairn-Timer:CancelOwner: owner must be non-nil", 2)
    end
    local bucket = self.byOwner[owner]
    if not bucket then return end
    local copy = Table_.Snapshot(bucket)
    for _, h in ipairs(copy) do h:Cancel() end
end


-- ---------------------------------------------------------------------------
-- Public API: stopwatch
-- ---------------------------------------------------------------------------

local StopwatchMethods = {}

function StopwatchMethods:Read()
    if self._stopped then
        return self._stopTime - self._startTime
    end
    return GetTime() - self._startTime
end

function StopwatchMethods:Lap(name)
    if name ~= nil and type(name) ~= "string" then
        error("Cairn-Timer Stopwatch :Lap: name must be a string or nil", 2)
    end
    local key = name or (#self._lapsOrdered + 1)
    local elapsed = self:Read()
    self._laps[key] = elapsed
    self._lapsOrdered[#self._lapsOrdered + 1] = { name = key, elapsed = elapsed }
    return elapsed
end

function StopwatchMethods:Laps()
    -- Return a shallow copy so the consumer can't mutate our internal table
    local copy = {}
    for k, v in pairs(self._laps) do copy[k] = v end
    return copy
end

function StopwatchMethods:Stop()
    if not self._stopped then
        self._stopped = true
        self._stopTime = GetTime()
    end
    return self._stopTime - self._startTime
end

function StopwatchMethods:Reset()
    self._startTime   = GetTime()
    self._stopped     = false
    self._stopTime    = nil
    self._laps        = {}
    self._lapsOrdered = {}
end

function StopwatchMethods:IsStopped()
    return self._stopped == true
end

local StopwatchMeta = { __index = StopwatchMethods }


function Cairn_Timer:Stopwatch()
    return setmetatable({
        _startTime   = GetTime(),
        _stopped     = false,
        _stopTime    = nil,
        _laps        = {},
        _lapsOrdered = {},
    }, StopwatchMeta)
end


-- ---------------------------------------------------------------------------
-- :ContinueAfterCombat (Cairn-Timer Decision 5, locked 2026-05-12)
-- ---------------------------------------------------------------------------
-- Universal "I need to do this but combat lockdown is preventing it"
-- deferral. If `not InCombatLockdown()`, fire the handler synchronously.
-- Otherwise append to a module-scope queue; on PLAYER_REGEN_ENABLED,
-- drain the queue in order with each handler wrapped in pcall so a
-- throwing handler routes to geterrorhandler and doesn't stop the drain.
-- Queue wipes after the drain.
--
-- Surfaced by Cairn-Settings Decision 12 (consolidated EditModeExpanded's
-- internal CombatManager). Concrete consumers: any Cairn-Settings
-- combat-aware widget (secureFrameHideable per Cluster B Decision 10),
-- Forge_AddonManager LoadAddon path, Vellum waypoint placement on
-- secure frames.

Cairn_Timer._combatQueue = Cairn_Timer._combatQueue or {}


-- Lazy event-frame init. Sharing one frame across the lib means N
-- consumers using :ContinueAfterCombat get ONE event listener, not N.
local function ensureCombatListener()
    if Cairn_Timer._combatFrame then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        local queue = Cairn_Timer._combatQueue
        if not queue or #queue == 0 then return end
        -- Snapshot then wipe BEFORE iterating so handlers that
        -- re-call :ContinueAfterCombat (e.g. starting another combat-
        -- gated chain) don't double-queue into the current drain.
        local snapshot = {}
        for i = 1, #queue do snapshot[i] = queue[i] end
        Cairn_Timer._combatQueue = {}
        for i = 1, #snapshot do
            Pcall.Call("Cairn-Timer:ContinueAfterCombat handler", snapshot[i])
        end
    end)
    Cairn_Timer._combatFrame = frame
end


function Cairn_Timer:ContinueAfterCombat(fn)
    if type(fn) ~= "function" then
        error("Cairn-Timer:ContinueAfterCombat: fn must be a function", 2)
    end

    local inCombat = (_G.InCombatLockdown and _G.InCombatLockdown()) or false
    if not inCombat then
        -- Out of combat: fire synchronously.
        Pcall.Call("Cairn-Timer:ContinueAfterCombat handler", fn)
        return
    end

    ensureCombatListener()
    local queue = self._combatQueue
    queue[#queue + 1] = fn
end


-- ---------------------------------------------------------------------------
-- :Start (Cairn-Timer Decision 6, locked 2026-05-12)
-- ---------------------------------------------------------------------------
-- Unified API generalizing four canonical debounce/throttle patterns
-- behind a single signature. `slot` is a string key for grouping calls
-- (timers for the same slot interact per the mode semantics). Pattern
-- reference: Gopher (Tammya-MoonGuard, 2018).
--
--   push      Trailing-edge debounce. Cancel + restart on every call;
--             fires once after the LAST call settles for `period`. This
--             is exactly the existing :Debounce semantic, so push mode
--             delegates to it directly.
--
--   ignore    Leading-edge throttle. No-op if a timer for this slot is
--             already running. The first call wins; rest get dropped
--             until the timer fires.
--
--   duplicate Fire-and-forget. Always schedules a new timer with this
--             period regardless of any existing slot state; the handles
--             aren't tracked under the slot key (can't cancel).
--
--   cooldown  Leading-edge with trailing-merge. Fire immediately + merge
--             subsequent calls during the cooldown window into a single
--             trailing fire. After the cooldown elapses, the merged
--             trailing fire (if any calls came in) fires.

Cairn_Timer._slotState = Cairn_Timer._slotState or {}


local function startPush(slot, period, fn)
    -- Delegate to existing Debounce; key = slot.
    return Cairn_Timer:Debounce(slot, period, fn)
end


local function startIgnore(slot, period, fn)
    local state = Cairn_Timer._slotState[slot]
    if state and state.running then return nil end
    -- Mark running; after the timer fires, clear so the next call goes through.
    state = state or {}
    state.running = true
    Cairn_Timer._slotState[slot] = state

    return Cairn_Timer:After(period, function()
        local s = Cairn_Timer._slotState[slot]
        if s then s.running = false end
        fn()
    end)
end


local function startDuplicate(slot, period, fn)
    -- Slot key intentionally ignored — just schedule a new fire-and-forget.
    return Cairn_Timer:After(period, fn)
end


local function startCooldown(slot, period, fn)
    local state = Cairn_Timer._slotState[slot]
    if state and state.coolingDown then
        -- Within cooldown window — mark pending trailing fire.
        state.pendingTrailing = true
        return nil
    end

    -- Not cooling down — fire immediately and start the cooldown window.
    state = state or {}
    state.coolingDown = true
    state.pendingTrailing = false
    state.fn = fn
    Cairn_Timer._slotState[slot] = state

    Pcall.Call("Cairn-Timer:Start[cooldown] immediate fire", fn)

    return Cairn_Timer:After(period, function()
        local s = Cairn_Timer._slotState[slot]
        if not s then return end
        local needsTrailing = s.pendingTrailing
        s.coolingDown = false
        s.pendingTrailing = false
        if needsTrailing and s.fn then
            Pcall.Call("Cairn-Timer:Start[cooldown] trailing fire", s.fn)
        end
    end)
end


local START_MODES = {
    push      = startPush,
    ignore    = startIgnore,
    duplicate = startDuplicate,
    cooldown  = startCooldown,
}


function Cairn_Timer:Start(slot, mode, period, fn)
    if type(slot) ~= "string" or slot == "" then
        error("Cairn-Timer:Start: slot must be a non-empty string", 2)
    end
    local dispatch = START_MODES[mode]
    if not dispatch then
        error("Cairn-Timer:Start: mode must be one of push / ignore / duplicate / cooldown (got "
              .. tostring(mode) .. ")", 2)
    end
    if type(period) ~= "number" or period < 0 then
        error("Cairn-Timer:Start: period must be a non-negative number", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn-Timer:Start: fn must be a function", 2)
    end
    return dispatch(slot, period, fn)
end


-- ---------------------------------------------------------------------------
-- :GetCountAfter (Cairn-Timer Decision 7, locked 2026-05-12)
-- ---------------------------------------------------------------------------
-- Returns the per-`from`-tag counter map populated when `Cairn.Timer.debugMode`
-- is set. Each entry counts how many fires came from a given `from` tag
-- across the session. Empty table when debugMode was never enabled, or
-- when no `from`-tagged timers have fired since enabling.
--
-- The "After" in the name is a nod to the most common scheduling method;
-- the counter tracks fires from `:After`, `:Every`, and `:Debounce`.
--
-- :ResetCountAfter() wipes the counter (use between profiling runs to
-- isolate measurement windows).
function Cairn_Timer:GetCountAfter()
    -- Return a copy so consumers can't accidentally mutate our counter.
    local copy = {}
    for k, v in pairs(self._fromCounts) do copy[k] = v end
    return copy
end


function Cairn_Timer:ResetCountAfter()
    self._fromCounts = {}
end


return Cairn_Timer
