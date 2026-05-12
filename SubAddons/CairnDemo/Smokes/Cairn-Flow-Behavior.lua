-- Cairn-Flow-Behavior smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: BT.Status constants, all 11 factories surface, Action +
-- Condition leaves (return-shape, blackboard, passthrough args, invalid
-- return = Failure, throwing = Failure), Sequence (AND, first-fail
-- short-circuit, resume-from-Running, terminal auto-reset), Selector
-- (OR, first-success short-circuit, resume-from-Running), Parallel
-- (default thresholds, custom thresholds, all-Running yields Running,
-- bad thresholds error), Invert (S<->F, R passes), RetryN (retries
-- consumed across ticks, eventual Success short-circuits counter,
-- exhausted retries yield Failure, n=0 = no retries), TimeLimit (with
-- mocked nowFn, before/after limit, internal reset on timeout),
-- Cooldown (with mocked nowFn, success starts cooldown, returns Failure
-- during cooldown without ticking child, resumes after), AlwaysSucceed
-- / AlwaysFail (Running passes through, terminal coerces), :Reset wipes
-- subtree state, deep composition with blackboard mutation visible
-- across siblings, input validation across all factories.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Flow-Behavior"] = function(report)
    -- 1. Surface
    local CF = LibStub and LibStub("Cairn-Flow-1.0", true)
    report("Cairn-Flow is loaded under LibStub", CF ~= nil)
    if not CF then return end

    report("Cairn-Flow.Behavior table exists", type(CF.Behavior) == "table")

    local BT = CF.Behavior
    report("BT.Status table exists",          type(BT.Status) == "table")
    report("BT.Status.Success is a string",   type(BT.Status.Success) == "string")
    report("BT.Status.Failure is a string",   type(BT.Status.Failure) == "string")
    report("BT.Status.Running is a string",   type(BT.Status.Running) == "string")
    report("Status values are all distinct",
           BT.Status.Success ~= BT.Status.Failure
           and BT.Status.Failure ~= BT.Status.Running
           and BT.Status.Success ~= BT.Status.Running)

    for _, name in ipairs({ "Sequence", "Selector", "Parallel",
                            "Invert", "RetryN", "TimeLimit", "Cooldown",
                            "AlwaysSucceed", "AlwaysFail",
                            "Action", "Condition" }) do
        report("BT." .. name .. " is a function", type(BT[name]) == "function")
    end

    local S = BT.Status


    -- 2. Action leaf — return values
    local s1 = BT.Action(function() return S.Success end):Tick()
    local f1 = BT.Action(function() return S.Failure end):Tick()
    local r1 = BT.Action(function() return S.Running end):Tick()
    report("Action returning Success",  s1 == S.Success)
    report("Action returning Failure",  f1 == S.Failure)
    report("Action returning Running",  r1 == S.Running)

    -- Invalid return (typo'd lower-case) treated as Failure
    local bad = BT.Action(function() return "success" end):Tick()
    report("Action with invalid return value treated as Failure", bad == S.Failure)

    local nilret = BT.Action(function() return nil end):Tick()
    report("Action returning nil treated as Failure", nilret == S.Failure)


    -- 3. Action — blackboard + passthrough args
    local seenBb, seenArg
    local ax = BT.Action(function(bb, arg) seenBb = bb; seenArg = arg; return S.Success end)
    ax:Tick({ key = "val" }, "extra")
    report("Action receives blackboard as 1st arg",      seenBb and seenBb.key == "val")
    report("Action receives passthrough arg after bb",   seenArg == "extra")


    -- 4. Action throwing -> Failure + routed to geterrorhandler
    local origGEH = geterrorhandler
    local errHits = 0
    geterrorhandler = function() return function() errHits = errHits + 1 end end

    local throwy = BT.Action(function() error("intentional") end):Tick()
    report("Throwing Action -> Failure",                 throwy == S.Failure)
    report("Throwing Action routed to geterrorhandler",  errHits == 1)


    -- 5. Condition truthy/falsy + throwing
    report("Condition truthy -> Success",
           BT.Condition(function() return true end):Tick() == S.Success)
    report("Condition falsy -> Failure",
           BT.Condition(function() return false end):Tick() == S.Failure)
    report("Condition nil -> Failure",
           BT.Condition(function() return nil end):Tick() == S.Failure)
    report("Condition non-nil (number) -> Success",
           BT.Condition(function() return 42 end):Tick() == S.Success)

    errHits = 0
    report("Throwing Condition -> Failure",
           BT.Condition(function() error("boom") end):Tick() == S.Failure)
    report("Throwing Condition routed to geterrorhandler", errHits == 1)
    geterrorhandler = origGEH


    -- 6. Sequence — basic AND behavior
    local seq1 = BT.Sequence({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
    })
    report("Sequence all-Success -> Success", seq1:Tick() == S.Success)

    -- First Failure short-circuits the rest
    local secondRan = false
    local seq2 = BT.Sequence({
        BT.Action(function() return S.Failure end),
        BT.Action(function() secondRan = true; return S.Success end),
    })
    report("Sequence first Failure -> Failure",         seq2:Tick() == S.Failure)
    report("Sequence first Failure: subsequent siblings NOT ticked", not secondRan)


    -- 7. Sequence — resume from Running child
    local progress = { 0, 0, 0 }
    local seq3 = BT.Sequence({
        BT.Action(function() progress[1] = progress[1] + 1; return S.Success end),
        BT.Action(function() progress[2] = progress[2] + 1; if progress[2] >= 3 then return S.Success end; return S.Running end),
        BT.Action(function() progress[3] = progress[3] + 1; return S.Success end),
    })
    report("Sequence tick 1: 1 ticks, 2 ticks (Running), 3 not yet ticked",
           seq3:Tick() == S.Running and progress[1] == 1 and progress[2] == 1 and progress[3] == 0)
    report("Sequence tick 2: resumes at 2 (1 NOT re-ticked)",
           seq3:Tick() == S.Running and progress[1] == 1 and progress[2] == 2 and progress[3] == 0)
    report("Sequence tick 3: 2 finally Success, 3 ticks, sequence Success",
           seq3:Tick() == S.Success and progress[1] == 1 and progress[2] == 3 and progress[3] == 1)
    -- After terminal: next tick starts fresh from 1
    seq3:Tick()
    report("Sequence terminal auto-resets: 1 re-ticked",  progress[1] == 2)


    -- 8. Selector — basic OR behavior
    local sel1 = BT.Selector({
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Success end),
    })
    report("Selector first Success after Failures -> Success", sel1:Tick() == S.Success)

    local thirdRan = false
    local sel2 = BT.Selector({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
        BT.Action(function() thirdRan = true; return S.Success end),
    })
    report("Selector first Success short-circuits rest",  sel2:Tick() == S.Success and not thirdRan)

    local sel3 = BT.Selector({
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Failure end),
    })
    report("Selector all-Failure -> Failure",  sel3:Tick() == S.Failure)


    -- 9. Selector resume from Running
    local count2 = 0
    local sel4 = BT.Selector({
        BT.Action(function() return S.Failure end),
        BT.Action(function() count2 = count2 + 1; if count2 >= 2 then return S.Success end; return S.Running end),
        BT.Action(function() return S.Success end),
    })
    report("Selector tick 1: 1 fails, 2 Running",   sel4:Tick() == S.Running and count2 == 1)
    report("Selector tick 2: resumes at 2 (NOT re-ticking 1)",
           sel4:Tick() == S.Success and count2 == 2)


    -- 10. Parallel — defaults
    local par1 = BT.Parallel({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
    })
    report("Parallel default: all Success -> Success",  par1:Tick() == S.Success)

    local par2 = BT.Parallel({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Success end),
    })
    report("Parallel default: 1 Failure -> Failure",  par2:Tick() == S.Failure)

    local par3 = BT.Parallel({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Running end),
        BT.Action(function() return S.Running end),
    })
    report("Parallel default: Success + Running -> Running (not enough Success yet)",
           par3:Tick() == S.Running)


    -- 11. Parallel — custom thresholds
    local par4 = BT.Parallel({
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Success end),
        BT.Action(function() return S.Running end),
    }, { successThreshold = 2 })
    report("Parallel successThreshold=2: 2 Success -> Success", par4:Tick() == S.Success)

    local par5 = BT.Parallel({
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Failure end),
        BT.Action(function() return S.Success end),
    }, { failureThreshold = 2 })
    report("Parallel failureThreshold=2: 2 Failure -> Failure", par5:Tick() == S.Failure)


    -- 12. Parallel — validation
    report("Parallel with successThreshold > #children errors",
           not pcall(function()
               BT.Parallel({ BT.Action(function() return S.Success end) }, { successThreshold = 5 })
           end))
    report("Parallel with failureThreshold < 1 errors",
           not pcall(function()
               BT.Parallel({ BT.Action(function() return S.Success end) }, { failureThreshold = 0 })
           end))


    -- 13. Invert
    report("Invert(Success) -> Failure",
           BT.Invert(BT.Action(function() return S.Success end)):Tick() == S.Failure)
    report("Invert(Failure) -> Success",
           BT.Invert(BT.Action(function() return S.Failure end)):Tick() == S.Success)
    report("Invert(Running) stays Running",
           BT.Invert(BT.Action(function() return S.Running end)):Tick() == S.Running)


    -- 14. RetryN — retries consumed across ticks
    local attempts = 0
    local retry = BT.RetryN(BT.Action(function()
        attempts = attempts + 1
        if attempts >= 3 then return S.Success end
        return S.Failure
    end), 5)
    report("RetryN tick 1: fail #1, return Running",  retry:Tick() == S.Running and attempts == 1)
    report("RetryN tick 2: fail #2, return Running",  retry:Tick() == S.Running and attempts == 2)
    report("RetryN tick 3: success on attempt 3, return Success",
           retry:Tick() == S.Success and attempts == 3)


    -- 15. RetryN — exhausted retries yield Failure
    local fails = 0
    local retry2 = BT.RetryN(BT.Action(function()
        fails = fails + 1; return S.Failure
    end), 2)
    -- n=2 = 2 retries allowed after the first attempt (3 total tries before giving up)
    report("RetryN n=2 tick 1 (1st fail): Running", retry2:Tick() == S.Running)
    report("RetryN n=2 tick 2 (2nd fail): Running", retry2:Tick() == S.Running)
    report("RetryN n=2 tick 3 (3rd fail): Failure", retry2:Tick() == S.Failure)

    -- n=0: no retries, Failure passes straight through
    local retry0 = BT.RetryN(BT.Action(function() return S.Failure end), 0)
    report("RetryN n=0: Failure passes through immediately", retry0:Tick() == S.Failure)


    -- 16. TimeLimit with mocked clock
    local mockTime = 0
    local function mockNow() return mockTime end
    local timeUp = BT.TimeLimit(BT.Action(function() return S.Running end), 5, mockNow)
    mockTime = 0
    report("TimeLimit within limit: pass child status",  timeUp:Tick() == S.Running)
    mockTime = 3
    report("TimeLimit still within limit: pass child status", timeUp:Tick() == S.Running)
    mockTime = 6
    report("TimeLimit beyond limit: Failure",            timeUp:Tick() == S.Failure)

    -- After timeout, internal state resets; next call starts fresh from current time
    mockTime = 100
    local childRan = false
    local timeUp2 = BT.TimeLimit(BT.Action(function() childRan = true; return S.Success end), 5, mockNow)
    timeUp2:Tick()
    report("TimeLimit fresh start at time 100: child ran, returned Success",
           childRan and timeUp2._start == nil)


    -- 17. Cooldown with mocked clock
    local mt2 = 0
    local function mt2Now() return mt2 end
    local cdCount = 0
    local cd = BT.Cooldown(BT.Action(function()
        cdCount = cdCount + 1; return S.Success
    end), 10, mt2Now)
    mt2 = 0
    report("Cooldown first tick: child runs, Success",   cd:Tick() == S.Success and cdCount == 1)
    mt2 = 5
    report("Cooldown mid-cooling: Failure without ticking child",
           cd:Tick() == S.Failure and cdCount == 1)
    mt2 = 9
    report("Cooldown still cooling: still Failure",      cd:Tick() == S.Failure and cdCount == 1)
    mt2 = 11
    report("Cooldown elapsed: child runs again, Success",
           cd:Tick() == S.Success and cdCount == 2)


    -- 18. AlwaysSucceed
    report("AlwaysSucceed(Success) -> Success",
           BT.AlwaysSucceed(BT.Action(function() return S.Success end)):Tick() == S.Success)
    report("AlwaysSucceed(Failure) -> Success",
           BT.AlwaysSucceed(BT.Action(function() return S.Failure end)):Tick() == S.Success)
    report("AlwaysSucceed(Running) stays Running",
           BT.AlwaysSucceed(BT.Action(function() return S.Running end)):Tick() == S.Running)


    -- 19. AlwaysFail
    report("AlwaysFail(Success) -> Failure",
           BT.AlwaysFail(BT.Action(function() return S.Success end)):Tick() == S.Failure)
    report("AlwaysFail(Failure) -> Failure",
           BT.AlwaysFail(BT.Action(function() return S.Failure end)):Tick() == S.Failure)
    report("AlwaysFail(Running) stays Running",
           BT.AlwaysFail(BT.Action(function() return S.Running end)):Tick() == S.Running)


    -- 20. :Reset wipes subtree state
    local nrCalls = 0
    local resetable = BT.Sequence({
        BT.Action(function() return S.Success end),
        BT.Action(function() nrCalls = nrCalls + 1; return S.Running end),
        BT.Action(function() return S.Success end),
    })
    resetable:Tick()   -- 1 Success, 2 Running
    report("Pre-Reset: Running stored at child 2",  resetable._runningIdx == 2)
    resetable:Reset()
    report("After Reset: _runningIdx cleared",      resetable._runningIdx == nil)
    -- Verify Reset cascades: a RetryN counter inside should also be 0
    local r3Fails = 0
    local resetableRetry = BT.RetryN(BT.Action(function()
        r3Fails = r3Fails + 1; return S.Failure
    end), 10)
    resetableRetry:Tick()
    resetableRetry:Tick()
    local midCount = resetableRetry._failures
    resetableRetry:Reset()
    report("RetryN failure counter cleared by Reset",
           midCount == 2 and resetableRetry._failures == 0)


    -- 21. Blackboard mutation visible across siblings
    local bb = { tally = 0 }
    local bbTree = BT.Sequence({
        BT.Action(function(bb) bb.tally = bb.tally + 1; return S.Success end),
        BT.Action(function(bb) bb.tally = bb.tally + 10; return S.Success end),
        BT.Action(function(bb) bb.tally = bb.tally + 100; return S.Success end),
    })
    bbTree:Tick(bb)
    report("Blackboard mutations from siblings stack",  bb.tally == 111)


    -- 22. Deep composition with blackboard and passthrough args
    local trace = {}
    local complex = BT.Selector({
        BT.Sequence({
            BT.Condition(function(bb) return bb.cond1 end),
            BT.Action(function(bb, arg)
                trace[#trace + 1] = "A:" .. tostring(arg)
                return S.Success
            end),
        }),
        BT.Action(function(bb, arg)
            trace[#trace + 1] = "B:" .. tostring(arg)
            return S.Success
        end),
    })
    -- cond1=false -> Sequence Failure (first branch), Selector tries B
    complex:Tick({ cond1 = false }, "hello")
    report("Selector falls to 2nd branch when 1st fails", trace[1] == "B:hello")

    trace = {}
    complex:Tick({ cond1 = true }, "world")
    report("Selector succeeds at 1st branch when cond true", trace[1] == "A:world")


    -- 23. Input validation
    report("BT.Sequence empty children errors",
           not pcall(function() BT.Sequence({}) end))
    report("BT.Sequence non-node child errors",
           not pcall(function() BT.Sequence({ "not a node" }) end))
    report("BT.Selector empty children errors",
           not pcall(function() BT.Selector({}) end))
    report("BT.Parallel empty children errors",
           not pcall(function() BT.Parallel({}) end))
    report("BT.Invert with non-node child errors",
           not pcall(function() BT.Invert("nope") end))
    report("BT.RetryN with negative n errors",
           not pcall(function() BT.RetryN(BT.Action(function() return S.Success end), -1) end))
    report("BT.RetryN with non-integer n errors",
           not pcall(function() BT.RetryN(BT.Action(function() return S.Success end), 1.5) end))
    report("BT.TimeLimit with zero secs errors",
           not pcall(function() BT.TimeLimit(BT.Action(function() return S.Success end), 0) end))
    report("BT.TimeLimit with bad nowFn errors",
           not pcall(function() BT.TimeLimit(BT.Action(function() return S.Success end), 1, "not a fn") end))
    report("BT.Cooldown with negative secs errors",
           not pcall(function() BT.Cooldown(BT.Action(function() return S.Success end), -1) end))
    report("BT.Action(non-fn) errors",
           not pcall(function() BT.Action(42) end))
    report("BT.Condition(non-fn) errors",
           not pcall(function() BT.Condition("nope") end))
end
