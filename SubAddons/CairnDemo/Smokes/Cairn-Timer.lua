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
end
