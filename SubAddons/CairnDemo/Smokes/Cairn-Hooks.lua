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
end
