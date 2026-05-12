-- Cairn-Events smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, API surface (Subscribe / Unsubscribe / UnsubscribeOwner
-- / Fire), dispatch with args, multiple subscribers, Unsubscribe single,
-- UnsubscribeOwner batch, internal-event clearing, real-WoW-event
-- RegisterEvent + UnregisterEvent lifecycle, handler error isolation,
-- snapshot-during-dispatch, Fire for internal events, input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Events"] = function(report)
    -- Namespaced fake event names so we can't collide with a real WoW event.
    local FAKE_EVENT   = "CairnEventsSmoke:" .. tostring(time and time() or 0)
    local FAKE_EVENT_2 = FAKE_EVENT .. "_2"

    -- 1. Library loaded + API
    local CE = LibStub and LibStub("Cairn-Events-1.0", true)
    report("Cairn-Events is loaded under LibStub", CE ~= nil)
    if not CE then return end

    report("Cairn-Events:Subscribe exists",        type(CE.Subscribe) == "function")
    report("Cairn-Events:Unsubscribe exists",      type(CE.Unsubscribe) == "function")
    report("Cairn-Events:UnsubscribeOwner exists", type(CE.UnsubscribeOwner) == "function")
    report("Cairn-Events:Fire exists",             type(CE.Fire) == "function")
    report("Cairn-Events.handlers is a table",     type(CE.handlers) == "table")
    report("Cairn-Events._listener is a Frame",
           type(CE._listener) == "table" and CE._listener.RegisterEvent ~= nil)

    local function fire(event, ...) CE:Fire(event, ...) end


    -- 2. Subscribe returns a token with the right shape
    local fired1 = 0
    local function h1() fired1 = fired1 + 1 end

    local sub = CE:Subscribe(FAKE_EVENT, h1)
    report("Subscribe returns a table",         type(sub) == "table")
    report("sub.event matches",                 sub.event == FAKE_EVENT)
    report("sub.handler matches",               sub.handler == h1)
    report("handlers[event] exists",            CE.handlers[FAKE_EVENT] ~= nil)
    report("handlers[event] contains the sub",  CE.handlers[FAKE_EVENT][1] == sub)


    -- 3. Dispatch fires the handler with the right args
    local capturedA, capturedB
    local function h2(a, b) capturedA, capturedB = a, b end
    CE:Subscribe(FAKE_EVENT, h2)

    fire(FAKE_EVENT, "alpha", "beta")
    report("first handler fired (count=1)",  fired1 == 1)
    report("second handler received args",   capturedA == "alpha" and capturedB == "beta")


    -- 4. Multiple subscribers all fire on one event
    local fired3 = 0
    local sub3 = CE:Subscribe(FAKE_EVENT, function() fired3 = fired3 + 1 end)
    fire(FAKE_EVENT)
    report("after one fire with 3 subs, h1 count == 2", fired1 == 2)
    report("after one fire with 3 subs, h3 count == 1", fired3 == 1)


    -- 5. Unsubscribe removes one sub
    CE:Unsubscribe(sub3)
    fire(FAKE_EVENT)
    report("h3 didn't fire after Unsubscribe(sub3)", fired3 == 1)
    report("h1 still fires after sub3 removed",      fired1 == 3)


    -- 6. Owner-based batch unsubscribe
    local owner = {}
    local ownerFired = 0
    CE:Subscribe(FAKE_EVENT,   function() ownerFired = ownerFired + 1 end, owner)
    CE:Subscribe(FAKE_EVENT_2, function() ownerFired = ownerFired + 1 end, owner)

    fire(FAKE_EVENT)
    fire(FAKE_EVENT_2)
    report("Owner's subs fire on both events (count=2)", ownerFired == 2)

    CE:UnsubscribeOwner(owner)
    fire(FAKE_EVENT)
    fire(FAKE_EVENT_2)
    report("UnsubscribeOwner: no further fires for owner", ownerFired == 2)
    report("UnsubscribeOwner: handlers[FAKE_EVENT_2] gone (was only owner's sub)",
           CE.handlers[FAKE_EVENT_2] == nil)


    -- 7. Last Unsubscribe clears handlers entry for an internal event
    CE:Unsubscribe(sub)
    local subs = CE.handlers[FAKE_EVENT]
    report("handlers[FAKE_EVENT] still present after one removal (h2 remains)",
           subs ~= nil and #subs == 1)
    CE:Unsubscribe(subs[1])
    report("After removing last sub, handlers[FAKE_EVENT] is nil",
           CE.handlers[FAKE_EVENT] == nil)


    -- 7b. Real WoW event integration
    local REAL = "GROUP_ROSTER_UPDATE"
    local realSub = CE:Subscribe(REAL, function() end)
    report("Subscribe to real WoW event registers it on the frame",
           CE._listener:IsEventRegistered(REAL) == true)
    CE:Unsubscribe(realSub)
    report("Last Unsubscribe unregisters the real WoW event from the frame",
           CE._listener:IsEventRegistered(REAL) == false)


    -- 8. Handler error isolation
    local originalGetErrorHandler = geterrorhandler
    local errorCalled = false
    geterrorhandler = function() return function(err) errorCalled = true end end

    local survivorFired = 0
    local function survivor() survivorFired = survivorFired + 1 end
    local subErr = CE:Subscribe(FAKE_EVENT, function() error("boom") end)
    local subOk  = CE:Subscribe(FAKE_EVENT, survivor)
    fire(FAKE_EVENT)
    geterrorhandler = originalGetErrorHandler

    report("error-handler invoked on thrown handler", errorCalled)
    report("Survivor handler still fired after error", survivorFired == 1)

    CE:Unsubscribe(subErr)
    CE:Unsubscribe(subOk)


    -- 9. Safe unsubscribe-during-dispatch (snapshot semantics)
    local seq = {}
    local sa, sb, sc
    sa = CE:Subscribe(FAKE_EVENT, function()
        seq[#seq + 1] = "a"
        CE:Unsubscribe(sc)
    end)
    sb = CE:Subscribe(FAKE_EVENT, function() seq[#seq + 1] = "b" end)
    sc = CE:Subscribe(FAKE_EVENT, function() seq[#seq + 1] = "c" end)

    fire(FAKE_EVENT)
    report("snapshot dispatch fired all three on the unsubscribe pass",
           table.concat(seq, ",") == "a,b,c",
           ("got " .. table.concat(seq, ",")))

    seq = {}
    fire(FAKE_EVENT)
    report("second fire skips the unsubscribed c",
           table.concat(seq, ",") == "a,b",
           ("got " .. table.concat(seq, ",")))

    CE:Unsubscribe(sa)
    CE:Unsubscribe(sb)


    -- 10. Fire — internal addon-to-addon event channel
    local INTERNAL = "CairnEventsSmoke:internal:" .. tostring(time and time() or 0)
    local internalArgs = nil
    CE:Subscribe(INTERNAL, function(...) internalArgs = { ... } end)

    CE:Fire(INTERNAL, "payload", 42, true)
    report("Fire dispatches to subs with the given args",
           internalArgs
           and internalArgs[1] == "payload"
           and internalArgs[2] == 42
           and internalArgs[3] == true)

    report("Fire on event with no subs is a no-op (no error)",
           pcall(function() CE:Fire("CairnEventsSmoke:NobodyHome") end))


    -- 11. Input validation
    report("Subscribe('', fn) errors",
           not pcall(function() CE:Subscribe("", function() end) end))
    report("Subscribe('X', non-fn) errors",
           not pcall(function() CE:Subscribe("X", "notafunc") end))
    report("Unsubscribe(non-table) errors",
           not pcall(function() CE:Unsubscribe("notatable") end))
    report("UnsubscribeOwner(nil) errors",
           not pcall(function() CE:UnsubscribeOwner(nil) end))
    report("Fire('') errors",
           not pcall(function() CE:Fire("") end))
    report("Fire(nil) errors",
           not pcall(function() CE:Fire(nil) end))


    -- =====================================================================
    -- MINOR 15 additions: D4 :Once + D5 EventTrace + D8 ValidateEvent +
    -- D9 :SubscribeUnit + D10 :IsUnitEvent
    -- =====================================================================

    report("CE:Once is a function",          type(CE.Once)          == "function")
    report("CE:OnceMessage is a function",   type(CE.OnceMessage)   == "function")
    report("CE:ValidateEvent is a function", type(CE.ValidateEvent) == "function")
    report("CE:SubscribeUnit is a function", type(CE.SubscribeUnit) == "function")
    report("CE:IsUnitEvent is a function",   type(CE.IsUnitEvent)   == "function")


    -- D4 :Once fires exactly once then auto-unsubscribes
    if type(CE.Once) == "function" then
        local onceEvent = "CairnEvents_OnceTest_" .. tostring(time and time() or 0)
        local onceFires = 0
        CE:Once(onceEvent, function() onceFires = onceFires + 1 end)
        CE:Fire(onceEvent)
        CE:Fire(onceEvent)
        CE:Fire(onceEvent)
        report(":Once fires exactly once across multiple Fire calls",
               onceFires == 1,
               ("got " .. onceFires))

        report(":Once with non-function errors",
               not pcall(function() CE:Once("X", "notafunc") end))
    end


    -- D8 :ValidateEvent
    if type(CE.ValidateEvent) == "function" then
        report(":ValidateEvent('PLAYER_LOGIN') is true",
               CE:ValidateEvent("PLAYER_LOGIN") == true)
        local ok, errMsg = CE:ValidateEvent("DEFINITELY_NOT_A_REAL_EVENT_XYZ")
        report(":ValidateEvent('bogus event') returns false",
               ok == false)
        report(":ValidateEvent('bogus') provides errMsg",
               type(errMsg) == "string")
        local ok2 = CE:ValidateEvent("")
        report(":ValidateEvent('') returns false",
               ok2 == false)
    end


    -- D10 :IsUnitEvent
    if type(CE.IsUnitEvent) == "function" then
        report(":IsUnitEvent('UNIT_HEALTH') is true",
               CE:IsUnitEvent("UNIT_HEALTH") == true)
        report(":IsUnitEvent('PLAYER_LOGIN') is false (not a UNIT event)",
               CE:IsUnitEvent("PLAYER_LOGIN") == false)
        report(":IsUnitEvent('') is false",
               CE:IsUnitEvent("") == false)
    end


    -- D9 :SubscribeUnit — validates the unit token + sets up filtered handler
    if type(CE.SubscribeUnit) == "function" then
        report(":SubscribeUnit with valid unit + handler returns subscription",
               type(CE:SubscribeUnit("UNIT_HEALTH", "player", function() end)) == "table")
        report(":SubscribeUnit with bad unit errors",
               not pcall(function() CE:SubscribeUnit("UNIT_HEALTH", "definitely_not_a_unit", function() end) end))
        report(":SubscribeUnit with non-function errors",
               not pcall(function() CE:SubscribeUnit("UNIT_HEALTH", "player", "notafunc") end))

        local sub = CE:SubscribeUnit("UNIT_HEALTH", "target", function() end)
        report(":SubscribeUnit sub carries .unit annotation",
               sub.unit == "target")

        -- Filtered dispatch: only fires for the matching unit
        local targetFires, playerFires = 0, 0
        local testEvent = "UNIT_TEST_EVENT_" .. tostring(time and time() or 0)
        local subT = CE:SubscribeUnit(testEvent, "target", function() targetFires = targetFires + 1 end)
        local subP = CE:SubscribeUnit(testEvent, "player", function() playerFires = playerFires + 1 end)
        CE:Fire(testEvent, "target")
        CE:Fire(testEvent, "player")
        CE:Fire(testEvent, "focus")
        report(":SubscribeUnit filters: target fires for target only",
               targetFires == 1)
        report(":SubscribeUnit filters: player fires for player only",
               playerFires == 1)

        -- Cleanup
        CE:Unsubscribe(subT)
        CE:Unsubscribe(subP)
    end


    -- =====================================================================
    -- MINOR 16 — D2 messages registry + D3 auto-namespace
    -- =====================================================================

    local stamp = tostring(time and time() or 0)

    report("CE:SubscribeMessage is a function",
           type(CE.SubscribeMessage) == "function")
    report("CE:UnsubscribeMessage is a function",
           type(CE.UnsubscribeMessage) == "function")
    report("CE:SendMessage is a function",
           type(CE.SendMessage) == "function")
    report("CE._messages is a table",
           type(CE._messages) == "table")

    -- Basic round-trip on the messages registry (no target — bare names stay bare)
    -- MINOR 16 SendMessage signature: (name, target, ...) — pass nil target
    -- to fire without namespacing.
    local msgFired = nil
    local subMsg = CE:SubscribeMessage("MyCustomMessage_" .. stamp, function(...)
        msgFired = { ... }
    end)
    CE:SendMessage("MyCustomMessage_" .. stamp, nil, "a", "b")
    report("SubscribeMessage handler fires on SendMessage",
           type(msgFired) == "table")
    report("SendMessage forwards args (arg1)",
           msgFired and msgFired[1] == "a")
    report("SendMessage forwards args (arg2)",
           msgFired and msgFired[2] == "b")
    CE:UnsubscribeMessage(subMsg)

    -- After UnsubscribeMessage, fires don't reach
    msgFired = nil
    CE:SendMessage("MyCustomMessage_" .. stamp, nil, "z")
    report("UnsubscribeMessage stops further fires",
           msgFired == nil)

    -- D3 auto-namespace: target with tocName causes bare names to prefix
    local addonNs = { tocName = "FakeAddon_" .. stamp }
    local nsFired = nil
    local subNs = CE:SubscribeMessage("Refresh", function(payload)
        nsFired = payload
    end, addonNs)
    -- The internal key is now "FakeAddon_<stamp>.Refresh"
    report("Subscribe auto-prefixes bare name with target.tocName",
           subNs.message == "FakeAddon_" .. stamp .. ".Refresh")
    report("rawMessage preserves the consumer-typed string",
           subNs.rawMessage == "Refresh")
    -- SendMessage with the same target hits the prefixed name
    CE:SendMessage("Refresh", addonNs, "data1")
    report("SendMessage with target hits the auto-prefixed entry",
           nsFired == "data1")
    -- SendMessage with bare name + nil target does NOT hit the prefixed entry
    nsFired = nil
    CE:SendMessage("Refresh", nil, "data2")
    report("SendMessage without target doesn't hit auto-prefixed entry",
           nsFired == nil)
    -- Cross-addon: explicit fully-qualified name reaches the prefixed entry
    CE:SendMessage("FakeAddon_" .. stamp .. ".Refresh", nil, "data3")
    report("SendMessage with fully-qualified name reaches auto-prefixed sub",
           nsFired == "data3")
    CE:UnsubscribeMessage(subNs)

    -- Names containing `.` or `:` are considered already-namespaced and pass through
    local subQ = CE:SubscribeMessage("Already.Qualified.Name_" .. stamp, function() end,
                                     { tocName = "WouldNotPrefix" })
    report("Already-namespaced name (with '.') NOT re-prefixed",
           subQ.message == "Already.Qualified.Name_" .. stamp)
    CE:UnsubscribeMessage(subQ)

    -- Target as string (also a valid tocName form)
    local strFired = nil
    local subStr = CE:SubscribeMessage("Event", function(x)
        strFired = x
    end, "StringTarget_" .. stamp)
    report("Subscribe accepts string target as tocName",
           subStr.message == "StringTarget_" .. stamp .. ".Event")
    CE:SendMessage("Event", "StringTarget_" .. stamp, "ok")
    report("SendMessage with string target hits prefixed entry",
           strFired == "ok")
    CE:UnsubscribeMessage(subStr)

    -- :OnceMessage one-shot on messages registry
    local onceCount = 0
    CE:OnceMessage("OneShot_" .. stamp, function()
        onceCount = onceCount + 1
    end)
    CE:SendMessage("OneShot_" .. stamp, nil)
    CE:SendMessage("OneShot_" .. stamp, nil)
    report("OnceMessage fires exactly once",
           onceCount == 1)

    -- UnsubscribeOwner walks both events and messages registries
    local ownerToken = { name = "ownerSmoke_" .. stamp }
    local ev1 = CE:Subscribe("InternalEvent_" .. stamp, function() end, ownerToken)
    local msg1 = CE:SubscribeMessage("OwnedMsg_" .. stamp, function() end, nil, ownerToken)
    report("Owner has entries in both registries before unsubscribe",
           CE.handlers["InternalEvent_" .. stamp] ~= nil
           and CE._messages["OwnedMsg_" .. stamp] ~= nil)
    CE:UnsubscribeOwner(ownerToken)
    report("UnsubscribeOwner cleans events registry",
           CE.handlers["InternalEvent_" .. stamp] == nil)
    report("UnsubscribeOwner cleans messages registry",
           CE._messages["OwnedMsg_" .. stamp] == nil)

    -- Input validation
    report("SubscribeMessage('', fn) errors",
           not pcall(function() CE:SubscribeMessage("", function() end) end))
    report("SubscribeMessage('x', 'notafn') errors",
           not pcall(function() CE:SubscribeMessage("x", "notafn") end))
    report("SendMessage('') errors",
           not pcall(function() CE:SendMessage("") end))
    report("UnsubscribeMessage with non-message sub errors",
           not pcall(function() CE:UnsubscribeMessage({}) end))
end
