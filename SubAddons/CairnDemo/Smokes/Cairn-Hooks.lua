-- Cairn-Hooks smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, Post/Pre/Wrap call ordering, args pass
-- through, original return values preserved (incl. multi-return and
-- embedded nils), chain composition, Unhook removes one, UnhookOwner
-- batch removes, last-unhook restores original, handler error
-- isolation, input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Hooks"] = function(report)
    -- 1. Library loaded + API
    local CH = LibStub and LibStub("Cairn-Hooks-1.0", true)
    report("Cairn-Hooks is loaded under LibStub", CH ~= nil)
    if not CH then return end

    report("CH:Pre exists",            type(CH.Pre)  == "function")
    report("CH:Post exists",           type(CH.Post) == "function")
    report("CH:Wrap exists",           type(CH.Wrap) == "function")
    report("CH:Unhook exists",         type(CH.Unhook) == "function")
    report("CH:UnhookOwner exists",    type(CH.UnhookOwner) == "function")
    report("CH._registry is a table", type(CH._registry) == "table")


    -- 2. Post hook: runs after original, original args + returns preserved
    local target = { value = 0 }
    function target:add(n)
        self.value = self.value + n
        return self.value, "tag"
    end

    local postSeenN, postSeenSelf = nil, nil
    CH:Post(target, "add", function(self, n)
        postSeenSelf = self
        postSeenN    = n
    end)

    local r1, r2 = target:add(5)
    report("Post: original still runs (value updated)", target.value == 5)
    report("Post: original 1st return value preserved", r1 == 5)
    report("Post: original 2nd return value preserved", r2 == "tag")
    report("Post: hook saw the original args (n=5)",    postSeenN == 5)
    report("Post: hook saw self",                       postSeenSelf == target)


    -- 3. Embedded nils in return values survive the Post wrapper
    target.value = 0
    function target:weirdReturn() return "a", nil, "c" end
    CH:Post(target, "weirdReturn", function() end)
    local a, b, c = target:weirdReturn()
    report("Post: embedded nil preserved (3rd value)",  a == "a" and b == nil and c == "c")


    -- 4. Pre hook: runs before original
    target.value = 0
    local sequence = {}
    target.preTest = function(self, n) sequence[#sequence + 1] = "orig:" .. n; return n end
    CH:Pre(target, "preTest", function(self, n) sequence[#sequence + 1] = "pre:" .. n end)
    target:preTest(7)
    report("Pre fires before original",  sequence[1] == "pre:7")
    report("Original still fires after", sequence[2] == "orig:7")


    -- 5. Wrap hook: replaces original
    target.wrapTest = function(self, n) return n * 2 end
    CH:Wrap(target, "wrapTest", function(orig, self, n)
        return orig(self, n + 10)
    end)
    report("Wrap can modify args before calling orig", target:wrapTest(3) == 26)


    -- 6. Multiple hooks chain
    target.chainTest = function(self, n) sequence[#sequence + 1] = "orig:" .. n; return n end
    sequence = {}
    CH:Pre (target, "chainTest", function(self, n) sequence[#sequence + 1] = "pre1:"  .. n end)
    CH:Pre (target, "chainTest", function(self, n) sequence[#sequence + 1] = "pre2:"  .. n end)
    CH:Post(target, "chainTest", function(self, n) sequence[#sequence + 1] = "post1:" .. n end)
    CH:Post(target, "chainTest", function(self, n) sequence[#sequence + 1] = "post2:" .. n end)

    target:chainTest(9)
    report("Chain produces all hook fires + original (5 entries)",
           #sequence == 5,
           ("got " .. #sequence .. ": " .. table.concat(sequence, "|")))
    report("Original runs in the middle of the chain", sequence[3] == "orig:9")


    -- 7. Unhook removes one hook
    target.unhookTest = function(self, n) sequence[#sequence + 1] = "orig:" .. n; return n end
    sequence = {}
    local hA = CH:Post(target, "unhookTest", function() sequence[#sequence + 1] = "A" end)
    local hB = CH:Post(target, "unhookTest", function() sequence[#sequence + 1] = "B" end)
    CH:Unhook(hA)
    target:unhookTest(0)
    report("Unhook(hA): A no longer fires", not table.concat(sequence, "|"):find("A"))
    report("Unhook(hA): B still fires",     table.concat(sequence, "|"):find("B") ~= nil)


    -- 8. Last unhook restores the original
    target.restoreTest = function(self, n) return n + 1 end
    local pristineOrig = target.restoreTest
    local hX = CH:Post(target, "restoreTest", function() end)
    report("After hooking, target.restoreTest is replaced", target.restoreTest ~= pristineOrig)
    CH:Unhook(hX)
    report("After last Unhook, target.restoreTest is restored",
           target.restoreTest == pristineOrig)


    -- 9. UnhookOwner
    target.ownerTest = function(self) sequence[#sequence + 1] = "orig" end
    sequence = {}
    local OWN = {}
    CH:Post(target, "ownerTest", function() sequence[#sequence + 1] = "P1" end, OWN)
    CH:Pre (target, "ownerTest", function() sequence[#sequence + 1] = "Pre1" end, OWN)
    CH:Post(target, "ownerTest", function() sequence[#sequence + 1] = "P2" end)

    CH:UnhookOwner(OWN)

    target:ownerTest()
    local joined = table.concat(sequence, "|")
    report("UnhookOwner: owner-tagged hooks removed (no P1, no Pre1)",
           not joined:find("P1") and not joined:find("Pre1"))
    report("UnhookOwner: untagged hook P2 still fires", joined:find("P2") ~= nil)


    -- 10. Handler error isolation (Pre/Post)
    local originalGetErrorHandler = geterrorhandler
    local errorCalled = false
    geterrorhandler = function() return function() errorCalled = true end end

    target.errTest = function(self) return "result" end
    CH:Pre(target, "errTest", function() error("intentional smoke-test error") end)
    local survivorRan = false
    CH:Post(target, "errTest", function() survivorRan = true end)
    local rv = target:errTest()
    geterrorhandler = originalGetErrorHandler

    report("Pre hook error did not crash dispatch", rv == "result")
    report("Error routed to geterrorhandler",       errorCalled)
    report("Post hook still ran after Pre threw",   survivorRan)


    -- 11. _registry tracks installed hooks
    report("Registry has at least one entry after this test set",
           #CH._registry > 0,
           ("size = " .. #CH._registry))


    -- 12. Input validation
    report("Post(non-table, ...) errors",
           not pcall(function() CH:Post("not a table", "m", function() end) end))
    report("Post(target, '', fn) errors",
           not pcall(function() CH:Post(target, "", function() end) end))
    report("Post(target, 'method', non-fn) errors",
           not pcall(function() CH:Post(target, "add", "not a func") end))
    report("Post(target, 'nonexistent', fn) errors",
           not pcall(function() CH:Post(target, "this_does_not_exist_on_target", function() end) end))
    report("Unhook(non-handle) errors",
           not pcall(function() CH:Unhook("not a handle") end))
    report("UnhookOwner(nil) errors",
           not pcall(function() CH:UnhookOwner(nil) end))


    -- Cleanup
    local ours = {}
    for _, hookH in ipairs(CH._registry) do
        if hookH.target == target then ours[#ours + 1] = hookH end
    end
    for _, hookH in ipairs(ours) do CH:Unhook(hookH) end


    -- =====================================================================
    -- HookOnce family (Cairn-Hooks Decision 5; MINOR 15)
    -- =====================================================================

    report("CH:HookOnce is a function",     type(CH.HookOnce)     == "function")
    report("CH:HookAlways is a function",   type(CH.HookAlways)   == "function")
    report("CH:HookFuncOnce is a function", type(CH.HookFuncOnce) == "function")


    -- HookOnce: 3 subscribers attached. One real handler installed. After
    -- the first fire all 3 callbacks run, then the list is wiped.
    --
    -- CreateFrame("Frame") returns an ALREADY-SHOWN frame by default, so
    -- the first frame:Show() is a no-op and OnShow doesn't fire. Pre-Hide
    -- to guarantee the Show triggers an actual OnShow.
    if type(CH.HookOnce) == "function" then
        local frame = CreateFrame("Frame")
        frame:Hide()   -- start hidden so the next Show fires OnShow
        local fires = { 0, 0, 0 }
        CH:HookOnce(frame, "OnShow", function() fires[1] = fires[1] + 1 end)
        CH:HookOnce(frame, "OnShow", function() fires[2] = fires[2] + 1 end)
        CH:HookOnce(frame, "OnShow", function() fires[3] = fires[3] + 1 end)

        -- Trigger OnShow by toggling visibility (Show fires OnShow).
        frame:Show()

        report("HookOnce: all 3 subscribers fired on first show",
               fires[1] == 1 and fires[2] == 1 and fires[3] == 1,
               ("got fires=(" .. fires[1] .. "," .. fires[2] .. "," .. fires[3] .. ")"))

        -- Second show — list was wiped, none should fire again.
        frame:Hide()
        frame:Show()
        report("HookOnce: subscribers do NOT re-fire on second show",
               fires[1] == 1 and fires[2] == 1 and fires[3] == 1)

        frame:Hide()
    end


    -- HookAlways: 2 subscribers attached. Both fire on each show, persisting.
    -- Same pre-Hide guard as HookOnce above.
    if type(CH.HookAlways) == "function" then
        local frame = CreateFrame("Frame")
        frame:Hide()
        local fires = { 0, 0 }
        CH:HookAlways(frame, "OnShow", function() fires[1] = fires[1] + 1 end)
        CH:HookAlways(frame, "OnShow", function() fires[2] = fires[2] + 1 end)

        frame:Show(); frame:Hide()
        frame:Show(); frame:Hide()
        frame:Show()

        report("HookAlways: both subscribers fired 3 times (persistent)",
               fires[1] == 3 and fires[2] == 3,
               ("got fires=(" .. fires[1] .. "," .. fires[2] .. ")"))

        frame:Hide()
    end


    -- HookFuncOnce: 2 subscribers on a fake table method. Both fire once.
    if type(CH.HookFuncOnce) == "function" then
        local stub = {}
        function stub:Ping() end

        local fires = { 0, 0 }
        CH:HookFuncOnce(stub, "Ping", function() fires[1] = fires[1] + 1 end)
        CH:HookFuncOnce(stub, "Ping", function() fires[2] = fires[2] + 1 end)

        stub:Ping()
        report("HookFuncOnce: both subscribers fired on first call",
               fires[1] == 1 and fires[2] == 1)

        stub:Ping()
        report("HookFuncOnce: subscribers do NOT re-fire on second call",
               fires[1] == 1 and fires[2] == 1)
    end


    -- Bad input
    if type(CH.HookOnce) == "function" then
        report("HookOnce on non-frame errors",
               not pcall(function() CH:HookOnce(42, "OnShow", function() end) end))
        report("HookOnce with empty script errors",
               not pcall(function() CH:HookOnce(CreateFrame("Frame"), "", function() end) end))
        report("HookOnce with non-function callback errors",
               not pcall(function() CH:HookOnce(CreateFrame("Frame"), "OnShow", 42) end))
    end


    -- =====================================================================
    -- MINOR 16 — D1+D2+D3+D4: AceHook-style API
    -- =====================================================================

    report("CH:Hook is a function",          type(CH.Hook) == "function")
    report("CH:SecureHook is a function",    type(CH.SecureHook) == "function")
    report("CH:RawHook is a function",       type(CH.RawHook) == "function")
    report("CH:FailsafeHook is a function",  type(CH.FailsafeHook) == "function")
    report("CH:UnhookAll is a function",     type(CH.UnhookAll) == "function")
    report("CH.actives is a table",          type(CH.actives) == "table")

    -- D1: :Hook installs a Pre-style wrapper + auto-chain
    local hookTarget = { Greet = function(self, name) self.last = "Hello " .. name end }
    local hookFired = false
    local h_hook = CH:Hook(hookTarget, "Greet", function(self, name)
        hookFired = true
    end, "hookOwner_1")
    hookTarget:Greet("World")
    report("Hook: handler fired",          hookFired == true)
    report("Hook: original ran (auto-chain)", hookTarget.last == "Hello World")
    report("Hook handle has _aceHookUid",  type(h_hook._aceHookUid) == "number")
    report("Hook handle has _aceHookKind", h_hook._aceHookKind == "Hook")
    report("CH.actives[uid] is true",      CH.actives[h_hook._aceHookUid] == true)

    -- :Unhook soft-unhook + physical removal for Hook handle
    CH:Unhook(h_hook)
    report("Unhook flips actives[uid] to false",
           CH.actives[h_hook._aceHookUid] == false)
    -- After unhook, the handler should no-op; the original still runs
    hookFired = false
    hookTarget.last = nil
    hookTarget:Greet("After")
    report("Unhook: handler no-ops",       hookFired == false)
    report("Unhook: original still runs after hook torn down",
           hookTarget.last == "Hello After")


    -- D2: :RawHook does NOT auto-chain
    local rawTarget = { Save = function(self, data) self.saved = data end }
    local rawCalled = false
    local h_raw = CH:RawHook(rawTarget, "Save", function(orig, self, data)
        rawCalled = true
        -- intentionally NOT calling orig — RawHook is replacement
    end, "rawOwner")
    rawTarget:Save("data1")
    report("RawHook: handler fired",       rawCalled == true)
    report("RawHook: original DID NOT run (no auto-chain)",
           rawTarget.saved == nil)
    report("RawHook handle kind tagged",   h_raw._aceHookKind == "RawHook")
    CH:Unhook(h_raw)


    -- D3: :FailsafeHook — original ALWAYS fires even if handler throws
    local fsTarget = { Tick = function(self) self.ticks = (self.ticks or 0) + 1 end }
    local fsHandlerFired = false
    local h_fs = CH:FailsafeHook(fsTarget, "Tick", function(self)
        fsHandlerFired = true
        error("intentional smoke-test throw — should be caught by xpcall")
    end, "fsOwner")

    -- Temporarily swallow errors so the handler's intentional throw
    -- doesn't pollute the smoke output. Save the real geterrorhandler
    -- (the function itself, not its return value) and restore after.
    local prevGetHandler = _G.geterrorhandler
    _G.geterrorhandler = function() return function(e) end end
    fsTarget:Tick()
    _G.geterrorhandler = prevGetHandler

    report("FailsafeHook: handler fired",  fsHandlerFired == true)
    report("FailsafeHook: original ran even though handler threw",
           fsTarget.ticks == 1)
    CH:Unhook(h_fs)


    -- D1: :Hook on a secure function should error
    -- Synthesize a fake secure global via a stub issecurevariable
    local origIsSecure = _G.issecurevariable
    _G.issecurevariable = function(t, k) return k == "FakeSecureMethod" end
    local secStubTarget = { FakeSecureMethod = function() end }
    report("Hook on secure method errors with hint",
           not pcall(function()
               CH:Hook(secStubTarget, "FakeSecureMethod", function() end)
           end))
    _G.issecurevariable = origIsSecure


    -- D1: :SecureHook installs via hooksecurefunc; handle is soft-unhook only
    local secTarget = { Action = function() end }
    local secCalls = 0
    local h_sec = CH:SecureHook(secTarget, "Action", function() secCalls = secCalls + 1 end,
                                "secOwner")
    secTarget:Action()
    report("SecureHook: handler fired after original (1 call)",
           secCalls == 1)
    secTarget:Action()
    report("SecureHook: handler fires on subsequent calls (2)",
           secCalls == 2)
    CH:Unhook(h_sec)
    secTarget:Action()
    report("SecureHook: actives flag stops dispatch after Unhook",
           secCalls == 2)
    report("SecureHook handle has _aceHookKind = 'SecureHook'",
           h_sec._aceHookKind == "SecureHook")


    -- D4: :UnhookAll batch by owner
    local target1 = { Method1 = function() end }
    local target2 = { Method2 = function() end }
    local target3 = { Method3 = function() end }
    local h1 = CH:Hook(target1,  "Method1", function() end, "batchOwner")
    local h2 = CH:RawHook(target2, "Method2", function(orig) orig() end, "batchOwner")
    local h3 = CH:Hook(target3,  "Method3", function() end, "otherOwner")
    CH:UnhookAll("batchOwner")
    report("UnhookAll: batchOwner's h1 actives flag cleared",
           CH.actives[h1._aceHookUid] == false)
    report("UnhookAll: batchOwner's h2 actives flag cleared",
           CH.actives[h2._aceHookUid] == false)
    report("UnhookAll: otherOwner's h3 actives flag untouched",
           CH.actives[h3._aceHookUid] == true)
    CH:Unhook(h3)


    -- Input validation for the new methods
    report("Hook(nil, ...) errors",
           not pcall(function() CH:Hook(nil, "x", function() end) end))
    report("Hook(t, '', fn) errors",
           not pcall(function() CH:Hook({x = function() end}, "", function() end) end))
    report("Hook(t, 'x', 'notafn') errors",
           not pcall(function() CH:Hook({x = function() end}, "x", "notafn") end))
    report("SecureHook on non-function method errors",
           not pcall(function() CH:SecureHook({}, "nosuch", function() end) end))
    report("UnhookAll(nil) errors",
           not pcall(function() CH:UnhookAll(nil) end))
end
