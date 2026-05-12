-- Cairn-Callback smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, New installs Register/Unregister/All on
-- target with default + custom names, function-form dispatch (event,
-- ...), method-string-form (consumer:m(event, ...)), with-arg dispatch,
-- multiple subscribers, Unregister single, UnregisterAll, OnUsed/
-- OnUnused, handler error isolation, safe self-unregister during
-- dispatch, input validation, CallbackHandler-1.0 shim round-trip.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Callback"] = function(report)
    -- 1. Library loaded + public API
    local CC = LibStub and LibStub("Cairn-Callback-1.0", true)
    report("Cairn-Callback is loaded under LibStub", CC ~= nil)
    if not CC then return end

    report("CC:New exists",           type(CC.New) == "function")
    report("CC.instances is a table", type(CC.instances) == "table")


    -- 2. New(target) installs default-named methods
    local target = {}
    local cb = CC:New(target)
    report("New returned a registry table",            type(cb) == "table")
    report("registry has :Fire",                       type(cb.Fire) == "function")
    report("target.RegisterCallback installed",        type(target.RegisterCallback) == "function")
    report("target.UnregisterCallback installed",      type(target.UnregisterCallback) == "function")
    report("target.UnregisterAllCallbacks installed",  type(target.UnregisterAllCallbacks) == "function")
    report("CC.instances tracks the registry",         CC.instances[target] == cb)


    -- 3. Function-form dispatch: fn(eventName, ...)
    local consumer = {}
    local fnArgs = nil
    target.RegisterCallback(consumer, "TEST_EVENT", function(event, a, b)
        fnArgs = { event = event, a = a, b = b }
    end)

    cb:Fire("TEST_EVENT", "alpha", "beta")
    report("Function-form handler fired",                fnArgs ~= nil)
    report("Function-form handler received eventName",   fnArgs and fnArgs.event == "TEST_EVENT")
    report("Function-form handler received fire args",   fnArgs and fnArgs.a == "alpha" and fnArgs.b == "beta")

    target.UnregisterCallback(consumer, "TEST_EVENT")


    -- 4. Method-string-form dispatch
    local self_seen, methodArgs = nil, nil
    local consumerWithMethod = {
        OnTestEvent = function(self, event, a, b)
            self_seen  = self
            methodArgs = { event = event, a = a, b = b }
        end,
    }
    target.RegisterCallback(consumerWithMethod, "TEST_EVENT", "OnTestEvent")

    cb:Fire("TEST_EVENT", "x", "y")
    report("Method-form handler fired",                  methodArgs ~= nil)
    report("Method-form receives self as 1st arg",       self_seen == consumerWithMethod)
    report("Method-form receives eventName as 2nd arg",  methodArgs and methodArgs.event == "TEST_EVENT")
    report("Method-form receives fire args after event", methodArgs and methodArgs.a == "x" and methodArgs.b == "y")

    target.UnregisterCallback(consumerWithMethod, "TEST_EVENT")


    -- 5. With-arg form: function — fn(arg, eventName, ...)
    local argArgs = nil
    target.RegisterCallback(consumer, "TEST_EVENT", function(arg, event, a)
        argArgs = { arg = arg, event = event, a = a }
    end, "INJECTED_ARG")

    cb:Fire("TEST_EVENT", "payload")
    report("With-arg function-form: arg comes before eventName",
           argArgs and argArgs.arg == "INJECTED_ARG"
           and argArgs.event == "TEST_EVENT"
           and argArgs.a == "payload")

    target.UnregisterCallback(consumer, "TEST_EVENT")


    -- 6. With-arg form: method-string
    local argMethodArgs = nil
    consumerWithMethod.OnWithArg = function(self, arg, event, a)
        argMethodArgs = { self = self, arg = arg, event = event, a = a }
    end
    target.RegisterCallback(consumerWithMethod, "TEST_EVENT", "OnWithArg", "INJECTED")

    cb:Fire("TEST_EVENT", "payload")
    report("With-arg method-form: self, arg, event, fireargs in order",
           argMethodArgs
           and argMethodArgs.self == consumerWithMethod
           and argMethodArgs.arg == "INJECTED"
           and argMethodArgs.event == "TEST_EVENT"
           and argMethodArgs.a == "payload")

    target.UnregisterCallback(consumerWithMethod, "TEST_EVENT")


    -- 7. Multiple subscribers
    local consumerA = {}
    local consumerB = {}
    local fired = {}
    target.RegisterCallback(consumerA, "MULTI", function() fired.A = true end)
    target.RegisterCallback(consumerB, "MULTI", function() fired.B = true end)
    cb:Fire("MULTI")
    report("Multiple subscribers all fire",  fired.A and fired.B)


    -- 8. UnregisterCallback removes one
    fired = {}
    target.UnregisterCallback(consumerA, "MULTI")
    cb:Fire("MULTI")
    report("Unregister removed A but B still fires",  fired.B and not fired.A)
    target.UnregisterCallback(consumerB, "MULTI")


    -- 9. UnregisterAllCallbacks
    target.RegisterCallback(consumerA, "E1", function() end)
    target.RegisterCallback(consumerA, "E2", function() end)
    target.RegisterCallback(consumerB, "E1", function() end)
    target.UnregisterAllCallbacks(consumerA)

    target.RegisterCallback(consumerA, "MARK1", function() end)
    target.RegisterCallback(consumerB, "MARK1", function() end)
    report("UnregisterAllCallbacks cleared consumerA's E1 sub",
           not cb._events["E1"] or cb._events["E1"][consumerA] == nil)
    report("UnregisterAllCallbacks cleared consumerA's E2 sub",
           not cb._events["E2"] or cb._events["E2"][consumerA] == nil)
    report("UnregisterAllCallbacks did NOT clear consumerB's E1 sub",
           cb._events["E1"] ~= nil and cb._events["E1"][consumerB] ~= nil)

    target.UnregisterAllCallbacks(consumerA)
    target.UnregisterAllCallbacks(consumerB)


    -- 10. OnUsed / OnUnused
    local target2 = {}
    local onUsedCalls, onUnusedCalls = {}, {}
    local cb2 = CC:New(target2,
        nil, nil, nil,
        function(t, ev) onUsedCalls[#onUsedCalls + 1] = { target = t, event = ev } end,
        function(t, ev) onUnusedCalls[#onUnusedCalls + 1] = { target = t, event = ev } end)

    target2.RegisterCallback(consumerA, "FIRST_EVENT", function() end)
    report("OnUsed fires when first sub registered",
           #onUsedCalls == 1 and onUsedCalls[1].event == "FIRST_EVENT"
           and onUsedCalls[1].target == target2)

    target2.RegisterCallback(consumerB, "FIRST_EVENT", function() end)
    report("OnUsed does NOT fire on second sub for same event", #onUsedCalls == 1)

    target2.UnregisterCallback(consumerA, "FIRST_EVENT")
    report("OnUnused does NOT fire while one sub remains", #onUnusedCalls == 0)

    target2.UnregisterCallback(consumerB, "FIRST_EVENT")
    report("OnUnused fires when last sub leaves",
           #onUnusedCalls == 1 and onUnusedCalls[1].event == "FIRST_EVENT")


    -- 11. Handler error isolation
    local originalGetErrorHandler = geterrorhandler
    local errCalled = false
    geterrorhandler = function() return function() errCalled = true end end

    local survivorFired = false
    target.RegisterCallback(consumerA, "BOOM_TEST", function() error("intentional smoke-test error") end)
    target.RegisterCallback(consumerB, "BOOM_TEST", function() survivorFired = true end)
    cb:Fire("BOOM_TEST")
    geterrorhandler = originalGetErrorHandler

    report("Handler error routed to geterrorhandler",   errCalled)
    report("Survivor handler still fired after error",  survivorFired)

    target.UnregisterAllCallbacks(consumerA)
    target.UnregisterAllCallbacks(consumerB)


    -- 12. Safe self-unregister during Fire
    local selfUnregFired = 0
    local survivorFired2 = false
    target.RegisterCallback(consumerA, "SELFUN", function()
        selfUnregFired = selfUnregFired + 1
        target.UnregisterCallback(consumerA, "SELFUN")
    end)
    target.RegisterCallback(consumerB, "SELFUN", function() survivorFired2 = true end)

    cb:Fire("SELFUN")
    report("Self-unregister during fire: handler fired once this round", selfUnregFired == 1)
    report("Self-unregister during fire: peer still fired", survivorFired2)

    selfUnregFired = 0
    survivorFired2 = false
    cb:Fire("SELFUN")
    report("After self-unregister, handler does NOT fire next round", selfUnregFired == 0)
    report("Peer still fires next round", survivorFired2)

    target.UnregisterAllCallbacks(consumerA)
    target.UnregisterAllCallbacks(consumerB)


    -- 13. Custom register/unregister names
    local target3 = {}
    CC:New(target3, "On", "Off", "OffAll")
    report("Custom regName 'On' installed",         type(target3.On)     == "function")
    report("Custom unregName 'Off' installed",      type(target3.Off)    == "function")
    report("Custom unregAllName 'OffAll' installed", type(target3.OffAll) == "function")
    report("Default 'RegisterCallback' NOT installed when custom name provided",
           target3.RegisterCallback == nil)


    -- 14. Input validation
    report("New(non-table) errors",
           not pcall(function() CC:New("not a table") end))
    report("RegisterCallback(non-table consumer) errors",
           not pcall(function() target.RegisterCallback("nope", "X", function() end) end))
    report("RegisterCallback(consumer, '', fn) errors",
           not pcall(function() target.RegisterCallback({}, "", function() end) end))
    report("RegisterCallback(consumer, 'X', nil) errors",
           not pcall(function() target.RegisterCallback({}, "X", nil) end))
    report("RegisterCallback with handler type 'number' errors",
           not pcall(function() target.RegisterCallback({}, "X", 42) end))


    -- 15. CallbackHandler-1.0 shim
    local CHshim = LibStub("CallbackHandler-1.0", true)
    report("CallbackHandler-1.0 is registered under LibStub", CHshim ~= nil)
    report("CallbackHandler-1.0 has :New method",             CHshim and type(CHshim.New) == "function")

    local shimTarget = {}
    local shimReg = CHshim:New(shimTarget)
    report("CallbackHandler-1.0 :New returns a registry",     type(shimReg) == "table")
    report("CallbackHandler-1.0 registry has :Fire",          type(shimReg.Fire) == "function")
    report("CallbackHandler-1.0 installed RegisterCallback",  type(shimTarget.RegisterCallback) == "function")

    local shimFired = false
    shimTarget.RegisterCallback({}, "SHIM_E", function() shimFired = true end)
    shimReg:Fire("SHIM_E")
    report("CallbackHandler-1.0 shim dispatches correctly", shimFired)
end
