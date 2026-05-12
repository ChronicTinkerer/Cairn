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
end
