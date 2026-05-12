-- Cairn-Flow-Decision smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: lib loads, sub-namespace surface, :New validates tree shape
-- at construction (test+value mutual exclusion, missing-required errors,
-- bad-branch-type errors), :Evaluate on binary nodes, :Evaluate on
-- multi-way nodes, default fallthrough, leaf types (nil / bool / string
-- / number / function / nested table), passthrough args reach all
-- test/value/leaf fns, error in test fn yields if_false branch, error
-- in value fn yields default branch, error in leaf fn yields nil.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Flow-Decision"] = function(report)
    -- 1. Surface
    local CF = LibStub and LibStub("Cairn-Flow-1.0", true)
    report("Cairn-Flow is loaded under LibStub", CF ~= nil)
    if not CF then return end

    report("Cairn-Flow.Decision table exists",      type(CF.Decision) == "table")
    report("Cairn-Flow.Decision:New is a function", type(CF.Decision.New) == "function")

    local D = CF.Decision


    -- 2. Validation at :New
    report(":New(nil) errors",
           not pcall(function() D:New(nil) end))
    report(":New({}) errors (no test or value)",
           not pcall(function() D:New({}) end))
    report(":New with both test AND value errors",
           not pcall(function() D:New({ test = function() end, value = function() end }) end))
    report(":New with non-function test errors",
           not pcall(function() D:New({ test = 42, if_true = "x", if_false = "y" }) end))
    report(":New with non-function value errors",
           not pcall(function() D:New({ value = 42, cases = {} }) end))
    report(":New with value but no cases table errors",
           not pcall(function() D:New({ value = function() end }) end))
    report(":New with bad branch type errors",
           not pcall(function() D:New({ test = function() end, if_true = D, if_false = "y" }) end))
    -- (D is a class table from LibStub — unsupported branch type because
    -- it's a table without test/value when treated as a node.)


    -- 3. Binary node, basic
    local d1 = D:New({
        test = function() return true end,
        if_true = "yes",
        if_false = "no",
    })
    report("Binary test true -> if_true branch", d1:Evaluate() == "yes")

    local d2 = D:New({
        test = function() return false end,
        if_true = "yes",
        if_false = "no",
    })
    report("Binary test false -> if_false branch", d2:Evaluate() == "no")


    -- 4. Leaf types: string / number / bool / nil / function
    local d3 = D:New({
        test = function() return true end,
        if_true  = 42,
        if_false = "ignored",
    })
    report("Number leaf returned as-is", d3:Evaluate() == 42)

    local d4 = D:New({
        test = function() return true end,
        if_true  = true,
        if_false = false,
    })
    report("Bool leaf returned as-is", d4:Evaluate() == true)

    -- Nil leaf (omit if_true entirely)
    local d5 = D:New({
        test = function() return true end,
        -- if_true omitted -> nil
        if_false = "no",
    })
    report("Nil leaf returns nil", d5:Evaluate() == nil)

    -- Function leaf
    local d6 = D:New({
        test = function() return true end,
        if_true = function() return "computed" end,
        if_false = "no",
    })
    report("Function leaf called, returns result", d6:Evaluate() == "computed")

    -- Function leaf returning nil
    local d7 = D:New({
        test = function() return true end,
        if_true = function() return nil end,
        if_false = "no",
    })
    report("Function leaf returning nil yields nil", d7:Evaluate() == nil)


    -- 5. Nested composition (table branch recurses)
    local nested = D:New({
        test = function() return true end,
        if_true = {
            test = function() return false end,
            if_true  = "outer-yes-inner-yes",
            if_false = "outer-yes-inner-no",
        },
        if_false = "outer-no",
    })
    report("Nested tree recurses correctly",
           nested:Evaluate() == "outer-yes-inner-no")


    -- 6. Multi-way (value + cases + default)
    local d8 = D:New({
        value = function() return "WARRIOR" end,
        cases = { WARRIOR = "tank", HUNTER = "rdps", PRIEST = "healer" },
        default = "unknown",
    })
    report("Multi-way: matching case returned", d8:Evaluate() == "tank")

    local d9 = D:New({
        value = function() return "MONK" end,
        cases = { WARRIOR = "tank", HUNTER = "rdps" },
        default = "unknown",
    })
    report("Multi-way: no matching case falls to default",
           d9:Evaluate() == "unknown")

    local d10 = D:New({
        value = function() return "MONK" end,
        cases = { WARRIOR = "tank" },
        -- no default
    })
    report("Multi-way: no default yields nil", d10:Evaluate() == nil)


    -- 7. Multi-way with non-string keys (numbers / bools)
    local d11 = D:New({
        value = function() return 2 end,
        cases = { [1] = "first", [2] = "second", [3] = "third" },
        default = "?",
    })
    report("Multi-way: number key matches", d11:Evaluate() == "second")

    local d12 = D:New({
        value = function() return true end,
        cases = { [true] = "yes", [false] = "no" },
    })
    report("Multi-way: bool key matches", d12:Evaluate() == "yes")


    -- 8. Nested multi-way inside multi-way
    local d13 = D:New({
        value = function() return "DRUID" end,
        cases = {
            DRUID = {
                value = function() return 2 end,
                cases = { [1] = "rdps", [2] = "tank", [3] = "healer" },
            },
        },
        default = "?",
    })
    report("Nested multi-way inside multi-way", d13:Evaluate() == "tank")


    -- 9. Passthrough args reach test/value/leaf functions
    local seenA, seenB, seenC
    local d14 = D:New({
        test = function(a, b) seenA = a; return b > 0 end,
        if_true = function(a, b)
            return ("a=%s b=%d"):format(tostring(a), b)
        end,
        if_false = "neg",
    })
    local result = d14:Evaluate("hello", 5)
    report("test fn receives passthrough args",        seenA == "hello")
    report("leaf fn receives passthrough args",        result == "a=hello b=5")

    local d15 = D:New({
        value = function(ctx) return ctx.class end,
        cases = {
            DRUID = function(ctx)
                return ctx.spec and ("druid-" .. ctx.spec) or "druid-none"
            end,
        },
        default = "other",
    })
    report("multi-way value fn receives passthrough arg",
           d15:Evaluate({ class = "DRUID", spec = "feral" }) == "druid-feral")


    -- 10. Error in test fn -> takes if_false branch
    local origGEH = geterrorhandler
    local errCalled = false
    geterrorhandler = function() return function() errCalled = true end end

    local d16 = D:New({
        test = function() error("intentional") end,
        if_true = "should-not-reach",
        if_false = "fallback",
    })
    local r16 = d16:Evaluate()
    report("Throwing test fn took if_false branch",   r16 == "fallback")
    report("Throwing test fn routed error to geterrorhandler", errCalled)


    -- 11. Error in value fn -> falls to default
    errCalled = false
    local d17 = D:New({
        value = function() error("intentional") end,
        cases = { OK = "matched" },
        default = "defaulted",
    })
    local r17 = d17:Evaluate()
    report("Throwing value fn fell to default",       r17 == "defaulted")
    report("Throwing value fn routed to geterrorhandler", errCalled)


    -- 12. Error in leaf fn -> yields nil
    errCalled = false
    local d18 = D:New({
        test = function() return true end,
        if_true = function() error("intentional") end,
        if_false = "no",
    })
    local r18 = d18:Evaluate()
    report("Throwing leaf fn yields nil",             r18 == nil)
    report("Throwing leaf fn routed to geterrorhandler", errCalled)

    geterrorhandler = origGEH
end
