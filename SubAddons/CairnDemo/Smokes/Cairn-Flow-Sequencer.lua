-- Cairn-Flow-Sequencer smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: lib loads, sub-namespace surface, :New rejects bad opts,
-- CurrentStep reports active step (id + index), Tick advances on
-- truthy fn / stays on falsy fn, onComplete fires exactly once on
-- finish, Tick is no-op after finished, manual :Next advances
-- bypassing gates AND fn, :Reset returns to step 1, resetCondition
-- triggers Reset mid-flow, abortCondition triggers Abort with reason,
-- Abort beats Reset on same Tick, onAbort idempotent on double-abort,
-- handler error in action fn doesn't crash the sequencer.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Flow-Sequencer"] = function(report)
    -- 1. Library + sub-namespace surface
    local CF = LibStub and LibStub("Cairn-Flow-1.0", true)
    report("Cairn-Flow is loaded under LibStub", CF ~= nil)
    if not CF then return end

    report("Cairn-Flow.Sequencer table exists", type(CF.Sequencer) == "table")
    report("Cairn-Flow.Sequencer:New is a function", type(CF.Sequencer.New) == "function")

    local Seq = CF.Sequencer


    -- 2. Bad opts rejected
    report(":New(nil) errors",
           not pcall(function() Seq:New(nil) end))
    report(":New({}) errors (missing actions)",
           not pcall(function() Seq:New({}) end))
    report(":New({ actions = {} }) errors (empty actions)",
           not pcall(function() Seq:New({ actions = {} }) end))
    report(":New action without fn errors",
           not pcall(function() Seq:New({ actions = { { id = "x" } } }) end))
    report(":New duplicate ids errors",
           not pcall(function() Seq:New({ actions = {
               { id = "a", fn = function() return true end },
               { id = "a", fn = function() return true end },
           }}) end))
    report(":New resetCondition non-fn errors",
           not pcall(function() Seq:New({ actions = {
               { fn = function() return true end }
           }, resetCondition = 42 }) end))


    -- 3. Happy path: 3 steps, each returns truthy on its second Tick
    local progress = { 0, 0, 0 }  -- one counter per step
    local completed = 0
    local s = Seq:New({
        name = "happy",
        actions = {
            { id = "a", fn = function() progress[1] = progress[1] + 1; return progress[1] >= 2 end },
            { id = "b", fn = function() progress[2] = progress[2] + 1; return progress[2] >= 2 end },
            { id = "c", fn = function() progress[3] = progress[3] + 1; return progress[3] >= 2 end },
        },
        onComplete = function() completed = completed + 1 end,
    })

    -- Before any Tick
    local cs = s:CurrentStep()
    report("CurrentStep before first Tick has index 1",  cs and cs.index == 1)
    report("CurrentStep before first Tick has id 'a'",   cs and cs.id == "a")
    report("IsFinished false before any Tick",           not s:IsFinished())

    -- Tick 1: each step fires its fn once, returns 1 (< 2 -> falsy), stays
    s:Tick()
    report("After Tick 1, still on step 1",              s:CurrentStep().index == 1)
    report("Step 1 fn ran once",                          progress[1] == 1)
    report("Step 2 fn has not yet run",                   progress[2] == 0)

    -- Tick 2: step 1 returns truthy, advance. Step 2 fn NOT auto-fired on same tick.
    s:Tick()
    report("After Tick 2, advanced to step 2",            s:CurrentStep().index == 2)
    report("CurrentStep id reflects step 2",              s:CurrentStep().id == "b")
    report("Step 2 fn has STILL not run (advance doesn't auto-fire next)",
           progress[2] == 0)

    -- Tick 3, 4: step 2 fires twice, advances
    s:Tick(); s:Tick()
    report("After Tick 4, advanced to step 3",            s:CurrentStep().index == 3)

    -- Tick 5, 6: step 3 fires twice, advances past end, IsFinished + onComplete
    s:Tick(); s:Tick()
    report("After 6 ticks, sequencer is finished",        s:IsFinished())
    report("CurrentStep returns nil after finish",         s:CurrentStep() == nil)
    report("onComplete fired exactly once",                completed == 1)

    -- Tick after finished: no-op
    local progressBeforeExtra = progress[3]
    s:Tick(); s:Tick()
    report("Tick after finished is no-op (step 3 fn doesn't re-fire)",
           progress[3] == progressBeforeExtra)
    report("onComplete still fired exactly once after extra ticks",
           completed == 1)


    -- 4. Manual :Next bypasses gates AND fn
    local nextFn = 0
    local s2 = Seq:New({
        name = "manualNext",
        actions = {
            { id = "x", fn = function() nextFn = nextFn + 1; return false end },
            { id = "y", fn = function() nextFn = nextFn + 1; return false end },
        },
    })
    local advanced = s2:Next()
    report(":Next returns true when advance happened",   advanced == true)
    report(":Next did NOT call the current step's fn",   nextFn == 0)
    report(":Next moved to step 2",                       s2:CurrentStep().index == 2)

    s2:Next()
    report(":Next past last step marks finished",         s2:IsFinished())
    report(":Next on finished sequencer returns false",   s2:Next() == false)


    -- 5. :Reset
    local s3 = Seq:New({
        actions = {
            { fn = function() return true end },
            { fn = function() return true end },
        },
    })
    s3:Tick(); s3:Tick()
    report("After 2 ticks, s3 finished",   s3:IsFinished())
    s3:Reset()
    report("After Reset, IsFinished false", not s3:IsFinished())
    report("After Reset, back on step 1",   s3:CurrentStep().index == 1)


    -- 6. resetCondition mid-flow
    local resetWanted = false
    local s4 = Seq:New({
        actions = {
            { id = "first",  fn = function() return false end },
            { id = "second", fn = function() return false end },
        },
        resetCondition = function() return resetWanted end,
    })
    s4:Tick()
    s4:Tick()
    s4:Next()  -- jump to step 2
    report("Pre-reset: on step 2",         s4:CurrentStep().index == 2)
    resetWanted = true
    s4:Tick()
    report("resetCondition fired -> back on step 1", s4:CurrentStep().index == 1)
    resetWanted = false  -- so subsequent ticks don't keep resetting


    -- 7. abortCondition
    local abortReason = nil
    local doAbort = false
    local s5 = Seq:New({
        name = "aborty",
        actions = {
            { fn = function() return false end },
        },
        abortCondition = function() return doAbort end,
        onAbort = function(reason) abortReason = reason end,
    })
    s5:Tick()
    report("Pre-abort: not aborted",            not s5:IsAborted())
    doAbort = true
    s5:Tick()
    report("abortCondition triggered abort",    s5:IsAborted())
    report("onAbort fired with reason 'abortCondition'", abortReason == "abortCondition")
    report("Aborted sequencer CurrentStep returns nil", s5:CurrentStep() == nil)


    -- 8. Abort beats Reset on the same Tick (abort checked first)
    local s6BothFired = { onAbort = false }
    local s6 = Seq:New({
        actions = { { fn = function() return false end } },
        resetCondition = function() return true end,
        abortCondition = function() return true end,
        onAbort = function() s6BothFired.onAbort = true end,
    })
    s6:Tick()
    report("With both gates true, Abort wins (onAbort fired)", s6BothFired.onAbort)
    report("With both gates true, sequencer is aborted, not just reset",
           s6:IsAborted())


    -- 9. Idempotent Abort + manual :Abort
    local abortCount = 0
    local s7 = Seq:New({
        actions = { { fn = function() return false end } },
        onAbort = function() abortCount = abortCount + 1 end,
    })
    s7:Abort("manual")
    s7:Abort("again")
    report("Second :Abort on aborted seq does NOT re-fire onAbort", abortCount == 1)
    report("Manual :Abort sets IsAborted", s7:IsAborted())


    -- 10. Action fn error is caught and treated as falsy (sequencer survives)
    local origGEH = geterrorhandler
    local errorCalled = false
    geterrorhandler = function() return function() errorCalled = true end end

    local survivedTicks = 0
    local s8 = Seq:New({
        actions = {
            { fn = function() error("intentional smoke-test error") end },
            { fn = function() survivedTicks = survivedTicks + 1; return true end },
        },
    })
    s8:Tick()
    geterrorhandler = origGEH

    report("Action error routed to geterrorhandler", errorCalled)
    report("Sequencer stayed on the throwing step (error treated as falsy)",
           s8:CurrentStep().index == 1)
    report("Sequencer is NOT marked aborted or finished by handler error",
           not s8:IsAborted() and not s8:IsFinished())

    -- Recover: Use :Next to skip past the throwing step, confirm step 2 runs
    s8:Next()
    s8:Tick()
    report("After :Next past throwing step, step 2 fn ran and advanced",
           survivedTicks == 1 and s8:IsFinished())


    -- 11. Actions without ids work (id is optional)
    local s9 = Seq:New({
        actions = {
            { fn = function() return true end },
            { fn = function() return true end },
        },
    })
    local cs9 = s9:CurrentStep()
    report("Action without id: CurrentStep.id is nil",   cs9.id == nil)
    report("Action without id: CurrentStep.index is set", cs9.index == 1)
end
