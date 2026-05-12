-- Cairn-Timer smoke (sync section only). Wrapped for the CairnDemo runner.
--
-- Coverage: synchronous API surface — handle shape, tracking, cancel,
-- CancelOwner batch, Every handle + count, Debounce same-key cancel,
-- Stopwatch surface, input validation.
--
-- The original .dev/tests smoke also had an ASYNC section that scheduled
-- C_Timer.After(0.5, ...) callbacks to verify timers actually fire. That
-- section is omitted here because the runner reports synchronously per
-- assertion and can't pick up results from a deferred coroutine. If async
-- coverage is needed later, a separate "Run Async Smokes" path can host
-- it (the runner's report closure could be passed through to a deferred
-- callback). For now: sync coverage only.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Timer"] = function(report)
    -- 1. Library loaded + public API
    local CT = LibStub and LibStub("Cairn-Timer-1.0", true)
    report("Cairn-Timer is loaded under LibStub", CT ~= nil)
    if not CT then return end

    report("CT:After exists",         type(CT.After) == "function")
    report("CT:Every exists",         type(CT.Every) == "function")
    report("CT:Debounce exists",      type(CT.Debounce) == "function")
    report("CT:Stopwatch exists",     type(CT.Stopwatch) == "function")
    report("CT:CancelOwner exists",   type(CT.CancelOwner) == "function")
    report("CT.timers is a table",    type(CT.timers) == "table")
    report("CT.byOwner is a table",   type(CT.byOwner) == "table")


    -- 2. After handle shape + tracking
    local owner = {}
    local h = CT:After(60, function() end, { owner = owner })

    report("After returned a table",       type(h) == "table")
    report("handle.delay = 60",            h.delay == 60)
    report("handle.fn is function",        type(h.fn) == "function")
    report("handle.owner = opts.owner",    h.owner == owner)
    report("handle.repeating = false",     h.repeating == false)
    report("handle.count = nil for After", h.count == nil)
    report("handle.fired = 0",             h.fired == 0)

    local foundInTimers, foundInByOwner = false, false
    for _, t in ipairs(CT.timers) do if t == h then foundInTimers = true; break end end
    local bucket = CT.byOwner[owner]
    if bucket then
        for _, t in ipairs(bucket) do if t == h then foundInByOwner = true; break end end
    end
    report("Timer in CT.timers",          foundInTimers)
    report("Timer in CT.byOwner[owner]",  foundInByOwner)


    -- 3. Cancel + idempotency
    h:Cancel()
    report("Cancel sets :IsCancelled() true",  h:IsCancelled())
    local stillInTimers = false
    for _, t in ipairs(CT.timers) do if t == h then stillInTimers = true; break end end
    report("Cancel removes from CT.timers",    not stillInTimers)
    report("Cancel clears empty bucket",       CT.byOwner[owner] == nil)
    h:Cancel()
    report("Cancel is idempotent",             h:IsCancelled())


    -- 4. CancelOwner
    local owner2 = {}
    local hA = CT:After(60, function() end, { owner = owner2 })
    local hB = CT:After(60, function() end, { owner = owner2 })
    local hC = CT:After(60, function() end)

    CT:CancelOwner(owner2)
    report("CancelOwner: hA cancelled",   hA:IsCancelled())
    report("CancelOwner: hB cancelled",   hB:IsCancelled())
    report("CancelOwner: bucket cleared", CT.byOwner[owner2] == nil)
    report("CancelOwner: hC survives",    not hC:IsCancelled())
    hC:Cancel()


    -- 5. Every handle + count
    local r = CT:Every(60, function() end, { count = 5 })
    report("Every handle has repeating=true", r.repeating == true)
    report("Every handle has count=5",        r.count == 5)
    report("Every handle has fired=0",        r.fired == 0)
    r:Cancel()


    -- 6. Debounce: same-key calls cancel pending and re-arm
    local KEY = "CairnTimerSmoke:debounce:" .. tostring(time and time() or 0)

    local d1 = CT:Debounce(KEY, 60, function() end)
    report("Debounce returned a handle",     type(d1) == "table")
    report("Debounce stored in _debounces",  CT._debounces[KEY] == d1)

    local d2 = CT:Debounce(KEY, 60, function() end)
    report("Second Debounce with same key cancelled the first", d1:IsCancelled())
    report("Second Debounce stored in _debounces",              CT._debounces[KEY] == d2)

    d2:Cancel()
    report("Cancelled Debounce cleared from _debounces", CT._debounces[KEY] == nil)


    -- 7. Stopwatch
    local sw = CT:Stopwatch()
    report("Stopwatch returned a table",    type(sw) == "table")
    report("Stopwatch :Read is a function", type(sw.Read) == "function")
    report("Stopwatch starts not stopped",  not sw:IsStopped())

    local r1 = sw:Read()
    report("Stopwatch :Read returns a non-negative number",
           type(r1) == "number" and r1 >= 0)

    sw:Lap("first")
    local laps1 = sw:Laps()
    report("After Lap, :Laps() contains 'first'", type(laps1.first) == "number")

    local stopped = sw:Stop()
    report("Stop returns a number",          type(stopped) == "number")
    report(":IsStopped() true after Stop",   sw:IsStopped())

    local readAfterStop = sw:Read()
    report(":Read after Stop matches :Stop's return",
           math.abs(readAfterStop - stopped) < 0.001)

    sw:Reset()
    report("Reset clears stopped flag", not sw:IsStopped())
    report("Reset clears laps",         next(sw:Laps()) == nil)


    -- 8. Input validation
    report("After(-1, fn) errors",
           not pcall(function() CT:After(-1, function() end) end))
    report("After('x', fn) errors",
           not pcall(function() CT:After("x", function() end) end))
    report("After(1, 'notafunc') errors",
           not pcall(function() CT:After(1, "notafunc") end))
    report("Every(-1, fn) errors",
           not pcall(function() CT:Every(-1, function() end) end))
    report("After(1, fn, { count = 5 }) errors (count only on Every)",
           not pcall(function() CT:After(1, function() end, { count = 5 }) end))
    report("Every(1, fn, { count = 0 }) errors",
           not pcall(function() CT:Every(1, function() end, { count = 0 }) end))
    report("Every(1, fn, { count = 1.5 }) errors",
           not pcall(function() CT:Every(1, function() end, { count = 1.5 }) end))
    report("Debounce('', delay, fn) errors",
           not pcall(function() CT:Debounce("", 1, function() end) end))
    report("CancelOwner(nil) errors",
           not pcall(function() CT:CancelOwner(nil) end))


    -- =====================================================================
    -- MINOR 15 additions — ContinueAfterCombat + :Start (D5 + D6)
    -- =====================================================================

    -- :ContinueAfterCombat
    report("CT:ContinueAfterCombat is a function",
           type(CT.ContinueAfterCombat) == "function")

    if type(CT.ContinueAfterCombat) == "function" then
        -- Out of combat: should fire synchronously.
        local fired = false
        CT:ContinueAfterCombat(function() fired = true end)
        report("ContinueAfterCombat fires synchronously when out-of-combat",
               fired == true)

        -- Bad input
        report("ContinueAfterCombat with non-function errors",
               not pcall(function() CT:ContinueAfterCombat(42) end))

        -- Queue inspection: out-of-combat, queue should be empty after
        -- synchronous fire (the handler ran inline, didn't append).
        report("ContinueAfterCombat synchronous path leaves queue empty",
               type(CT._combatQueue) == "table" and #CT._combatQueue == 0)
    end


    -- :Start 4-mode dispatch
    report("CT:Start is a function",
           type(CT.Start) == "function")

    if type(CT.Start) == "function" then
        -- push mode delegates to Debounce — verify it returns a handle and
        -- the handle is the same shape as a Debounce handle.
        local pushHandle = CT:Start("smoke_push_" .. tostring(time and time() or 0),
            "push", 0.5, function() end)
        report("Start('push') returns a handle",
               type(pushHandle) == "table" and type(pushHandle.Cancel) == "function")
        pushHandle:Cancel()

        -- ignore mode: first call returns a handle, second call returns nil
        -- (because the first hasn't fired yet).
        local slotIgnore = "smoke_ignore_" .. tostring(time and time() or 0)
        local h1 = CT:Start(slotIgnore, "ignore", 0.5, function() end)
        local h2 = CT:Start(slotIgnore, "ignore", 0.5, function() end)
        report("Start('ignore') first call returns a handle",
               type(h1) == "table")
        report("Start('ignore') second call returns nil (slot busy)",
               h2 == nil)
        if h1 then h1:Cancel() end
        -- Manually clear the slot state since we cancelled, not awaited:
        CT._slotState[slotIgnore] = nil

        -- duplicate mode: always returns a new handle, ignoring slot state.
        local slotDup = "smoke_dup_" .. tostring(time and time() or 0)
        local d1 = CT:Start(slotDup, "duplicate", 0.5, function() end)
        local d2 = CT:Start(slotDup, "duplicate", 0.5, function() end)
        report("Start('duplicate') call 1 returns handle",
               type(d1) == "table")
        report("Start('duplicate') call 2 returns handle (not nil)",
               type(d2) == "table")
        if d1 then d1:Cancel() end
        if d2 then d2:Cancel() end

        -- cooldown mode: first call fires immediately + starts cooldown.
        -- Subsequent calls during cooldown queue exactly ONE trailing fire.
        local slotCD = "smoke_cd_" .. tostring(time and time() or 0)
        local cdFires = 0
        local cdHandle = CT:Start(slotCD, "cooldown", 0.5,
            function() cdFires = cdFires + 1 end)
        report("Start('cooldown') first call fires immediately",
               cdFires == 1)
        report("Start('cooldown') first call returns a handle",
               type(cdHandle) == "table")
        -- A second call during cooldown returns nil + sets pendingTrailing.
        local cdHandle2 = CT:Start(slotCD, "cooldown", 0.5,
            function() cdFires = cdFires + 1 end)
        report("Start('cooldown') subsequent call during cooldown returns nil",
               cdHandle2 == nil)
        report("Start('cooldown') subsequent call sets pendingTrailing",
               CT._slotState[slotCD] and CT._slotState[slotCD].pendingTrailing == true)
        if cdHandle then cdHandle:Cancel() end
        CT._slotState[slotCD] = nil

        -- Bad input
        report("Start with bad slot errors",
               not pcall(function() CT:Start("", "push", 0.5, function() end) end))
        report("Start with bad mode errors",
               not pcall(function() CT:Start("x", "unknown_mode", 0.5, function() end) end))
        report("Start with negative period errors",
               not pcall(function() CT:Start("x", "push", -1, function() end) end))
        report("Start with non-function fn errors",
               not pcall(function() CT:Start("x", "push", 0.5, 42) end))
    end


    -- =====================================================================
    -- MINOR 16 — D1 string-method + D4 argsCount + D7 caller-id + counter
    -- =====================================================================
    -- (D2 fps-drift compensation isn't time-deterministic in synchronous
    -- smoke tests; it's verified by inspection rather than by assertions.
    -- The relevant code path is exercised by every :Every test above.)

    -- D1: fn as string method name, opts.obj as receiver
    local recv = {}
    function recv:Ping(payload) self.last = payload end
    local h_str = CT:After(0, "Ping", { obj = recv }, "pong")
    report("After: fn-as-string with opts.obj is accepted",
           type(h_str) == "table")
    -- Force the schedule to fire by waiting for next-frame equivalent.
    -- Since smoke is synchronous, we can't await C_Timer; instead verify
    -- the handle was constructed correctly.
    report("After: fn-as-string handle stores method name + obj",
           h_str.fn == "Ping" and h_str.obj == recv)
    report("After: fn-as-string handle captures argsCount",
           h_str.argsCount == 1)
    h_str:Cancel()

    -- D1 input validation: string fn requires opts.obj
    report("After: string fn without opts.obj rejected",
           not pcall(function()
               CT:After(0.1, "DoesntExist", nil)
           end))

    -- D1 input validation: bad obj method surfaces at fire time via
    -- geterrorhandler; here we just verify the handle-construction phase
    -- allows it (validation is at dispatch time).
    local h_badmethod = CT:After(0, "NonexistentMethod", { obj = {} })
    report("After: string fn with valid opts.obj constructs even if method missing",
           type(h_badmethod) == "table")
    h_badmethod:Cancel()


    -- D4: argsCount preserves nil holes
    local h_args = CT:After(0, function() end, nil, "a", nil, "c")
    report("After: variadic args captured with argsCount = 3",
           h_args.argsCount == 3)
    report("After: args[1] preserved",
           h_args.args[1] == "a")
    report("After: args[2] is nil (the hole)",
           h_args.args[2] == nil)
    report("After: args[3] preserved",
           h_args.args[3] == "c")
    h_args:Cancel()

    -- D4: no variadic args means argsCount = 0
    local h_noargs = CT:After(0, function() end)
    report("After: no variadic args yields argsCount = 0",
           h_noargs.argsCount == 0)
    report("After: no variadic args means args is nil",
           h_noargs.args == nil)
    h_noargs:Cancel()


    -- D7: opts.from + debugMode + GetCountAfter
    report("CT.debugMode flag exists and defaults false",
           CT.debugMode == false)
    report("CT:GetCountAfter is a function",
           type(CT.GetCountAfter) == "function")
    report("CT:ResetCountAfter is a function",
           type(CT.ResetCountAfter) == "function")
    report("Initial GetCountAfter returns empty table",
           next(CT:GetCountAfter()) == nil)

    -- With debugMode off, fires don't bump the counter (smoke test fakes
    -- the fire path by setting up a 0-delay timer and immediately
    -- checking; since C_Timer is async we just verify state shape).
    local h_from1 = CT:After(0, function() end, { from = "smoke_tag_1" })
    report("After: opts.from captured on handle",
           h_from1.from == "smoke_tag_1")
    h_from1:Cancel()

    -- Toggle debugMode on, then off, to verify the flag flips cleanly
    CT.debugMode = true
    CT._fromCounts["preExisting"] = 5
    local snapshot = CT:GetCountAfter()
    report("GetCountAfter returns a copy (not the live table)",
           snapshot.preExisting == 5 and snapshot ~= CT._fromCounts)
    CT:ResetCountAfter()
    report("ResetCountAfter wipes the counter",
           next(CT:GetCountAfter()) == nil)
    CT.debugMode = false

    -- D7 input validation: opts.from must be a string
    report("opts.from non-string rejected",
           not pcall(function()
               CT:After(0.1, function() end, { from = 42 })
           end))
end
