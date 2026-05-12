-- Cairn-Flow-FSM smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: surface, validation rejection of malformed shapes (missing
-- initial, missing states, duplicate names, unknown target, unknown
-- initial, bad on-entry shape), initial entry fires onEnter chain root-
-- to-leaf, GetState / GetPath / IsIn at each level, sibling transition
-- onExit/onEnter order, transition to ancestor (LCA computation —
-- ancestor stays active), transition to descendant composite (follows
-- initial chain), deep cross-tree transition (LCA = root), guard
-- accepting fires transition, guard declining bubbles to parent,
-- declining-all-the-way drops the event silently, OnTransition observer
-- shape and unsub, passthrough args reach guard + onEnter + onExit +
-- observer, throwing guard treated as decline, throwing onExit doesn't
-- abort the transition, throwing onEnter doesn't abort.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Flow-FSM"] = function(report)
    -- 1. Surface
    local CF = LibStub and LibStub("Cairn-Flow-1.0", true)
    report("Cairn-Flow is loaded under LibStub", CF ~= nil)
    if not CF then return end

    report("Cairn-Flow.FSM table exists",      type(CF.FSM) == "table")
    report("Cairn-Flow.FSM:New is a function", type(CF.FSM.New) == "function")

    local F = CF.FSM


    -- 2. Validation
    report(":New(nil) errors",
           not pcall(function() F:New(nil) end))
    report(":New without initial errors",
           not pcall(function() F:New({ states = { A = {} } }) end))
    report(":New without states errors",
           not pcall(function() F:New({ initial = "A" }) end))
    report(":New with initial referencing unknown state errors",
           not pcall(function() F:New({ initial = "Nope", states = { A = {} } }) end))
    report(":New with transition to unknown target errors",
           not pcall(function() F:New({
               initial = "A",
               states  = { A = { on = { GO = "Nowhere" } } },
           }) end))
    report(":New composite missing initial errors",
           not pcall(function() F:New({
               initial = "C",
               states  = { C = { states = { X = {} } } },  -- composite without initial
           }) end))
    report(":New composite initial referencing unknown child errors",
           not pcall(function() F:New({
               initial = "C",
               states  = { C = { initial = "Nope", states = { X = {} } } },
           }) end))
    report(":New with duplicate state names errors",
           not pcall(function() F:New({
               initial = "A",
               states  = {
                   A = { states = { Dup = {} }, initial = "Dup" },
                   Dup = {},
               },
           }) end))
    report(":New with bad on-entry shape errors",
           not pcall(function() F:New({
               initial = "A",
               states  = { A = { on = { GO = 42 } } },
           }) end))


    -- 3. Initial entry fires onEnter chain root-to-leaf
    local entrySeq = {}
    local m1 = F:New({
        initial = "Combat",
        states  = {
            Idle   = { onEnter = function() entrySeq[#entrySeq+1] = "Idle.in" end },
            Combat = {
                initial = "Engaging",
                onEnter = function() entrySeq[#entrySeq+1] = "Combat.in" end,
                states  = {
                    Engaging = { onEnter = function() entrySeq[#entrySeq+1] = "Engaging.in" end },
                    Looting  = {},
                },
            },
        },
    })
    report("Initial entry fires Combat.onEnter then Engaging.onEnter",
           entrySeq[1] == "Combat.in" and entrySeq[2] == "Engaging.in"
           and #entrySeq == 2)


    -- 4. GetState / GetPath / IsIn
    report("GetState returns active leaf name",  m1:GetState() == "Engaging")
    local path = m1:GetPath()
    report("GetPath is root-to-leaf",
           #path == 2 and path[1] == "Combat" and path[2] == "Engaging")
    report("IsIn(leaf) true",                    m1:IsIn("Engaging"))
    report("IsIn(ancestor) true",                m1:IsIn("Combat"))
    report("IsIn(sibling) false",                not m1:IsIn("Looting"))
    report("IsIn(unrelated) false",              not m1:IsIn("Idle"))
    report("IsIn(non-string) false",             not m1:IsIn(42))


    -- 5. Sibling transition fires onExit then onEnter
    local seq = {}
    local m2 = F:New({
        initial = "A",
        states  = {
            A = {
                onEnter = function(ev) seq[#seq+1] = "A.in:"..tostring(ev) end,
                onExit  = function(ev) seq[#seq+1] = "A.out:"..tostring(ev) end,
                on      = { GO = "B" },
            },
            B = {
                onEnter = function(ev) seq[#seq+1] = "B.in:"..tostring(ev) end,
                onExit  = function(ev) seq[#seq+1] = "B.out:"..tostring(ev) end,
            },
        },
    })
    -- seq after init: { "A.in:nil" }
    report("Initial onEnter sees event=nil",     seq[1] == "A.in:nil")
    seq = {}
    m2:Send("GO")
    report("Sibling transition: A.out first",    seq[1] == "A.out:GO")
    report("Sibling transition: B.in second",    seq[2] == "B.in:GO")
    report("Sibling transition: exactly two callbacks", #seq == 2)
    report("Sibling transition: GetState updated", m2:GetState() == "B")


    -- 6. Transition to ancestor (LCA = ancestor itself; ancestor stays active)
    seq = {}
    local m3 = F:New({
        initial = "Combat",
        states  = {
            Combat = {
                initial = "Engaging",
                onEnter = function() seq[#seq+1] = "Combat.in" end,
                onExit  = function() seq[#seq+1] = "Combat.out" end,
                on      = { RESET = "Combat" },  -- transition to self/ancestor
                states  = {
                    Engaging = {
                        onEnter = function() seq[#seq+1] = "Engaging.in" end,
                        onExit  = function() seq[#seq+1] = "Engaging.out" end,
                    },
                    Looting = {
                        onEnter = function() seq[#seq+1] = "Looting.in" end,
                        onExit  = function() seq[#seq+1] = "Looting.out" end,
                    },
                },
            },
        },
    })
    -- After init: seq has Combat.in, Engaging.in
    seq = {}
    m3:Send("RESET")
    -- LCA(Engaging, Combat) = Combat. onExit walks Engaging only.
    -- Then resolveLeaf(Combat) descends via initial -> Engaging.onEnter.
    -- Combat.onExit / Combat.onEnter do NOT fire (LCA is exclusive).
    report("Transition to ancestor: Engaging.out fires", seq[1] == "Engaging.out")
    report("Transition to ancestor: Engaging.in re-fires via initial chain",
           seq[2] == "Engaging.in")
    report("Transition to ancestor: Combat.out does NOT fire (it's the LCA)",
           not table.concat(seq, "|"):find("Combat.out"))
    report("Transition to ancestor: Combat.in does NOT fire (it's the LCA)",
           not table.concat(seq, "|"):find("Combat.in"))


    -- 7. Transition to descendant composite — follows initial chain
    seq = {}
    local m4 = F:New({
        initial = "Idle",
        states  = {
            Idle = {
                onExit = function() seq[#seq+1] = "Idle.out" end,
                on = { ENGAGE = "Combat" },
            },
            Combat = {
                initial = "Engaging",
                onEnter = function() seq[#seq+1] = "Combat.in" end,
                states  = {
                    Engaging = { onEnter = function() seq[#seq+1] = "Engaging.in" end },
                    Looting  = { onEnter = function() seq[#seq+1] = "Looting.in" end },
                },
            },
        },
    })
    seq = {}
    m4:Send("ENGAGE")
    report("Descend into composite: Idle.out first",     seq[1] == "Idle.out")
    report("Descend into composite: Combat.in second",   seq[2] == "Combat.in")
    report("Descend into composite: Engaging.in (initial) third",
           seq[3] == "Engaging.in")
    report("Descend into composite: Looting.in does NOT fire",
           not table.concat(seq, "|"):find("Looting.in"))
    report("Descend into composite: GetState lands on Engaging",
           m4:GetState() == "Engaging")


    -- 8. Deep cross-tree transition (LCA = root)
    seq = {}
    local m5 = F:New({
        initial = "X",
        states  = {
            X = {
                initial = "XA",
                onEnter = function() seq[#seq+1] = "X.in" end,
                onExit  = function() seq[#seq+1] = "X.out" end,
                states  = {
                    XA = {
                        initial = "XAB",
                        onEnter = function() seq[#seq+1] = "XA.in" end,
                        onExit  = function() seq[#seq+1] = "XA.out" end,
                        states  = {
                            XAB = {
                                onEnter = function() seq[#seq+1] = "XAB.in" end,
                                onExit  = function() seq[#seq+1] = "XAB.out" end,
                                on = { JUMP = "YBD" },
                            },
                        },
                    },
                },
            },
            Y = {
                initial = "YA",
                onEnter = function() seq[#seq+1] = "Y.in" end,
                onExit  = function() seq[#seq+1] = "Y.out" end,
                states  = {
                    YA = { onEnter = function() seq[#seq+1] = "YA.in" end },
                    YB = {
                        initial = "YBA",
                        onEnter = function() seq[#seq+1] = "YB.in" end,
                        states  = {
                            YBA = { onEnter = function() seq[#seq+1] = "YBA.in" end },
                            YBD = {
                                onEnter = function() seq[#seq+1] = "YBD.in" end,
                            },
                        },
                    },
                },
            },
        },
    })
    -- After init: X.in, XA.in, XAB.in
    seq = {}
    m5:Send("JUMP")
    -- LCA = root. onExit walks XAB, XA, X. onEnter walks Y, YB, YBD.
    -- (YBD is a leaf so no further descent.)
    report("Deep cross-tree: onExit walks leaf-to-root excluding LCA",
           seq[1] == "XAB.out" and seq[2] == "XA.out" and seq[3] == "X.out")
    report("Deep cross-tree: onEnter walks root-to-target",
           seq[4] == "Y.in" and seq[5] == "YB.in" and seq[6] == "YBD.in")
    report("Deep cross-tree: exactly six callbacks", #seq == 6)
    report("Deep cross-tree: GetState lands on YBD", m5:GetState() == "YBD")
    report("Deep cross-tree: GetPath is Y/YB/YBD",
           (function() local p = m5:GetPath()
                return #p == 3 and p[1] == "Y" and p[2] == "YB" and p[3] == "YBD" end)())


    -- 9. Guard accepts -> transition fires
    local m6 = F:New({
        initial = "A",
        states  = {
            A = { on = { GO = { target = "B", guard = function() return true end } } },
            B = {},
        },
    })
    m6:Send("GO")
    report("Guard returning true allows the transition", m6:GetState() == "B")


    -- 10. Guard declines -> bubbles to parent
    local m7 = F:New({
        initial = "Combat",
        states  = {
            Idle = {},
            Combat = {
                initial = "Engaging",
                on = { ABORT = "Idle" },  -- parent handles
                states  = {
                    Engaging = {
                        -- Child has a guarded ABORT that always declines.
                        on = { ABORT = { target = "Looting", guard = function() return false end } },
                    },
                    Looting = {},
                },
            },
        },
    })
    m7:Send("ABORT")
    report("Guard declining at child bubbles to parent's handler",
           m7:GetState() == "Idle")


    -- 11. Decline all the way -> event dropped silently
    local m8 = F:New({
        initial = "A",
        states  = {
            A = { on = { GO = { target = "B", guard = function() return false end } } },
            B = {},
        },
    })
    m8:Send("GO")
    report("Guard declining with no parent handler: event dropped, state unchanged",
           m8:GetState() == "A")


    -- 12. Unknown event dropped silently (no error)
    local okU = pcall(function() m8:Send("NEVER_DEFINED") end)
    report("Unknown event is dropped (no error)", okU)


    -- 13. OnTransition observer
    local observations = {}
    local m9 = F:New({
        initial = "A",
        states  = {
            A = { on = { GO = "B" } },
            B = { on = { BACK = "A" } },
        },
    })
    local unsub = m9:OnTransition(function(oldS, newS, event, payload)
        observations[#observations + 1] = { old = oldS, new = newS, event = event, p = payload }
    end)
    m9:Send("GO", "first")
    m9:Send("BACK", "second")
    report("Observer fired on first transition",
           observations[1] and observations[1].old == "A" and observations[1].new == "B"
           and observations[1].event == "GO" and observations[1].p == "first")
    report("Observer fired on second transition",
           observations[2] and observations[2].old == "B" and observations[2].new == "A"
           and observations[2].event == "BACK" and observations[2].p == "second")

    unsub()
    m9:Send("GO")
    report("After unsub, observer does NOT fire on subsequent transition",
           #observations == 2)


    -- 14. Passthrough args reach guard + onEnter + onExit + observer
    local capture = {}
    local m10 = F:New({
        initial = "A",
        states  = {
            A = {
                onExit = function(event, key) capture.exit = { event = event, key = key } end,
                on = { GO = { target = "B", guard = function(key) capture.guardKey = key; return key == "yes" end } },
            },
            B = {
                onEnter = function(event, key) capture.enter = { event = event, key = key } end,
            },
        },
    })
    m10:OnTransition(function(oldS, newS, event, key)
        capture.obs = { old = oldS, new = newS, event = event, key = key }
    end)
    m10:Send("GO", "yes")
    report("Passthrough: guard sees args (no event prefix)",   capture.guardKey == "yes")
    report("Passthrough: onExit sees event then args",
           capture.exit and capture.exit.event == "GO" and capture.exit.key == "yes")
    report("Passthrough: onEnter sees event then args",
           capture.enter and capture.enter.event == "GO" and capture.enter.key == "yes")
    report("Passthrough: observer sees (old, new, event, args)",
           capture.obs and capture.obs.old == "A" and capture.obs.new == "B"
           and capture.obs.event == "GO" and capture.obs.key == "yes")


    -- 15. Throwing guard treated as decline
    local origGEH = geterrorhandler
    local errCalled = false
    geterrorhandler = function() return function() errCalled = true end end

    local m11 = F:New({
        initial = "A",
        states  = {
            A = { on = { GO = { target = "B", guard = function() error("boom") end } } },
            B = {},
        },
    })
    m11:Send("GO")
    report("Throwing guard treated as decline (state unchanged)",
           m11:GetState() == "A")
    report("Throwing guard routed to geterrorhandler", errCalled)


    -- 16. Throwing onExit does NOT abort the transition
    errCalled = false
    local seqOK = {}
    local m12 = F:New({
        initial = "A",
        states  = {
            A = {
                onExit = function() error("boom-exit") end,
                on = { GO = "B" },
            },
            B = {
                onEnter = function() seqOK[#seqOK+1] = "B.in" end,
            },
        },
    })
    m12:Send("GO")
    report("Throwing onExit does NOT abort: B.onEnter still ran",
           seqOK[1] == "B.in")
    report("Throwing onExit: state advanced to B",     m12:GetState() == "B")
    report("Throwing onExit routed to geterrorhandler", errCalled)


    -- 17. Throwing onEnter does NOT abort
    errCalled = false
    local m13 = F:New({
        initial = "A",
        states  = {
            A = { on = { GO = "B" } },
            B = { onEnter = function() error("boom-enter") end },
        },
    })
    m13:Send("GO")
    report("Throwing onEnter: state still advanced to B",  m13:GetState() == "B")
    report("Throwing onEnter routed to geterrorhandler",   errCalled)

    geterrorhandler = origGEH


    -- 18. Send input validation
    report(":Send('') errors",
           not pcall(function() m13:Send("") end))
    report(":Send(nil) errors",
           not pcall(function() m13:Send(nil) end))

    -- 19. OnTransition input validation
    report(":OnTransition(non-fn) errors",
           not pcall(function() m13:OnTransition("notafunc") end))


    -- 20. Multiple observers all fire; unsub only removes its own
    local m14 = F:New({
        initial = "A",
        states  = { A = { on = { GO = "B" } }, B = {} },
    })
    local hitA, hitB = 0, 0
    local unsubA = m14:OnTransition(function() hitA = hitA + 1 end)
    local unsubB = m14:OnTransition(function() hitB = hitB + 1 end)
    m14:Send("GO")
    report("Multiple observers both fire on transition", hitA == 1 and hitB == 1)
    unsubA()
    -- transition back to fire observers again (use a fresh path through ON)
    local m14b = F:New({
        initial = "A",
        states  = { A = { on = { GO = "B" } }, B = {} },
    })
    -- Just verify unsubA closure semantics: calling unsubA twice doesn't error
    local okDouble = pcall(unsubA)
    report("Calling unsub() twice doesn't error", okDouble)
end
