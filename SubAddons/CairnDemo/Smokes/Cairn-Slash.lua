-- Cairn-Slash smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, Register wires WoW globals, aliases, :Sub
-- variants (leaf, group, group-with-description), chainability, nested
-- dispatch, walk-as-deep-as-possible matching, handler receives
-- unmatched remainder, default fallback via :Default at any depth,
-- recursive auto-help shows ALL descendants, handler error isolation,
-- input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Slash"] = function(report)
    -- 1. Library loaded + API
    local CS = LibStub and LibStub("Cairn-Slash-1.0", true)
    report("Cairn-Slash is loaded under LibStub", CS ~= nil)
    if not CS then return end

    report("CS:Register exists",     type(CS.Register) == "function")
    report("CS:Get exists",          type(CS.Get) == "function")
    report("CS.registry is a table", type(CS.registry) == "table")


    -- 2. Register wires WoW slash globals
    local stamp   = tostring(time and time() or 0)
    local NAME    = "CairnSlashSmoke_" .. stamp
    local PRIMARY = "/css" .. stamp
    local ALIAS   = "/c_smoke" .. stamp
    local KEY     = "CAIRN_SLASH_" .. NAME:upper()

    local slash = CS:Register(NAME, PRIMARY, { aliases = { ALIAS } })
    report("Register returned a node table",   type(slash) == "table")
    report("registry[name] == instance",       CS.registry[NAME] == slash)
    report("SLASH_<KEY>1 == primary",          _G["SLASH_" .. KEY .. "1"] == PRIMARY)
    report("SLASH_<KEY>2 == alias",            _G["SLASH_" .. KEY .. "2"] == ALIAS)
    report("SlashCmdList[KEY] is a function",  type(_G.SlashCmdList[KEY]) == "function")


    -- 3. Sub variants
    local leafFired = nil

    local leaf = slash:Sub("logs", function(rest) leafFired = rest end, "open logs")
    report("Sub returns a node",                            type(leaf) == "table")
    report("leaf node has _fullSlash composed from parent", leaf._fullSlash == PRIMARY .. " logs")
    report("leaf has _handler set",                         type(leaf._handler) == "function")
    report("leaf has _description set",                     leaf._description == "open logs")

    local dev = slash:Sub("dev", "developer tools")
    report("group node returned",                       type(dev) == "table")
    report("group has nil _handler",                    dev._handler == nil)
    report("group has _description set via string arg", dev._description == "developer tools")

    local plain = slash:Sub("plain")
    report("bare group has nil _handler and nil _description",
           plain._handler == nil and plain._description == nil)


    -- 4. Nested subs
    local localeRest, devLogsRest = nil, nil
    dev:Sub("locale", function(rest) localeRest = rest end, "set locale override")
    dev:Sub("logs",   function(rest) devLogsRest = rest end, "open dev logs viewer")

    report("dev:Sub returns a sub of dev",
           dev:GetSubs().locale ~= nil and dev:GetSubs().locale._parent == dev)
    report("nested _fullSlash composes correctly",
           dev:GetSubs().locale._fullSlash == PRIMARY .. " dev locale")


    -- 5. Dispatch
    local dispatcher = _G.SlashCmdList[KEY]

    dispatcher("logs hello")
    report("Top-level leaf fires with rest", leafFired == "hello")

    dispatcher("dev locale enUS")
    report("Nested leaf fires with rest = 'enUS'", localeRest == "enUS")

    dispatcher("dev logs")
    report("Nested leaf with no rest fires with ''", devLogsRest == "")

    localeRest = nil
    dispatcher("dev locale  some  multi  spaced   trailing")
    report("Nested rest preserves multi-token strings",
           localeRest == "some  multi  spaced   trailing")


    -- 6. Walk-as-deep semantics
    local devSelfRest = nil
    dev:Default(function(rest) devSelfRest = rest end)

    dispatcher("dev zzz extra")
    report("Unrecognized continuation falls to dev's handler with remainder",
           devSelfRest == "zzz extra")


    -- 7. Recursive auto-help
    local NAME2 = NAME .. "_nohelp"
    local PRIMARY2 = "/csh" .. stamp
    local KEY2 = "CAIRN_SLASH_" .. NAME2:upper()
    local slash2 = CS:Register(NAME2, PRIMARY2)
    slash2:Sub("alpha", "alpha description")
    local beta = slash2:Sub("beta", "beta description")
    beta:Sub("nested", function() end, "deeply nested")

    local originalPrint, captured = print, {}
    print = function(...) captured[#captured + 1] = table.concat({...}, "\t") end
    _G.SlashCmdList[KEY2]("")
    print = originalPrint

    local helpJoined = table.concat(captured, "\n")
    report("Auto-help printed at least one line",   #captured > 0)
    report("Auto-help shows root path",             helpJoined:find(PRIMARY2, 1, true) ~= nil)
    report("Auto-help shows top-level sub /alpha",  helpJoined:find(PRIMARY2 .. " alpha", 1, true) ~= nil)
    report("Auto-help shows top-level sub /beta",   helpJoined:find(PRIMARY2 .. " beta", 1, true) ~= nil)
    report("Auto-help shows NESTED sub /beta nested",
           helpJoined:find(PRIMARY2 .. " beta nested", 1, true) ~= nil)
    report("Auto-help shows descriptions",
           helpJoined:find("alpha description", 1, true) ~= nil
           and helpJoined:find("deeply nested", 1, true) ~= nil)


    -- 8. Subtree auto-help
    captured = {}
    print = function(...) captured[#captured + 1] = table.concat({...}, "\t") end
    _G.SlashCmdList[KEY2]("beta")
    print = originalPrint

    helpJoined = table.concat(captured, "\n")
    report("Subtree auto-help shows beta's nested child",
           helpJoined:find(PRIMARY2 .. " beta nested", 1, true) ~= nil)
    report("Subtree auto-help does NOT show sibling alpha",
           helpJoined:find(PRIMARY2 .. " alpha", 1, true) == nil)


    -- 9. Idempotent Register / idempotent Sub (updates handler/description)
    local same = CS:Register(NAME, PRIMARY)
    report("Register(same name) returns the existing instance", same == slash)

    local prevLeaf = leaf
    leaf = slash:Sub("logs", function(rest) leafFired = "updated:" .. rest end, "open logs (v2)")
    report("Sub(same name) returns the existing sub node", leaf == prevLeaf)

    dispatcher("logs hello")
    report("Sub re-registration updated the handler",     leafFired == "updated:hello")
    report("Sub re-registration updated the description", leaf._description == "open logs (v2)")


    -- 10. Handler error isolation
    local originalGetErrorHandler = geterrorhandler
    local errorCalled = false
    geterrorhandler = function() return function() errorCalled = true end end

    slash:Sub("boom", function() error("intentional smoke-test error") end)
    _G.SlashCmdList[KEY]("boom args here")

    geterrorhandler = originalGetErrorHandler
    report("Handler error routed to geterrorhandler", errorCalled)


    -- 11. Input validation
    report("Register('', '/x') errors",
           not pcall(function() CS:Register("", "/x") end))
    report("Register('X', 'noslash') errors",
           not pcall(function() CS:Register("X_" .. stamp, "noprefix") end))
    report("Register with non-table aliases errors",
           not pcall(function() CS:Register("X2_" .. stamp, "/x2" .. stamp, { aliases = "string" }) end))
    report(":Sub('') errors",
           not pcall(function() slash:Sub("") end))
    report(":Sub('x', 42) errors (second arg neither function nor string)",
           not pcall(function() slash:Sub("x", 42) end))
    report(":Sub('x', 'a desc', 'extra') errors (description passed twice)",
           not pcall(function() slash:Sub("x", "a desc", "extra") end))
    report(":Default(non-fn) errors",
           not pcall(function() slash:Default("notafunc") end))


    -- =====================================================================
    -- :GetArgs(str, numargs) parser (Cairn-Slash Decision 2, MINOR 15)
    -- =====================================================================

    report("CS:GetArgs is a function",
           type(CS.GetArgs) == "function")

    if type(CS.GetArgs) == "function" then
        local GA = function(...) return CS:GetArgs(...) end

        -- Plain split
        local a, b, rest = GA("foo bar baz", 2)
        report("GetArgs plain split: arg1=foo",  a == "foo")
        report("GetArgs plain split: arg2=bar",  b == "bar")
        report("GetArgs plain split: rest=baz",  rest == "baz")

        -- Quoted strings preserved
        local q1, q2, qrest = GA('hi "Cathedral Square" rest', 2)
        report("GetArgs quoted: arg1=hi",                       q1 == "hi")
        report("GetArgs quoted: arg2 preserved with space",     q2 == "Cathedral Square")
        report("GetArgs quoted: rest=rest",                     qrest == "rest")

        -- Hyperlink preserved as one unit
        local h1, h2, hrest = GA('show |Hitem:9351|h[Twill Belt]|h details', 2)
        report("GetArgs hyperlink: arg1=show",  h1 == "show")
        report("GetArgs hyperlink: arg2 preserved as full link",
               h2 == "|Hitem:9351|h[Twill Belt]|h",
               ("got " .. tostring(h2)))
        report("GetArgs hyperlink: rest=details", hrest == "details")

        -- Texture escape preserved as one unit
        local t1, t2, trest = GA("see |TInterface/Icons/Foo:0|t after", 2)
        report("GetArgs texture: arg1=see",                t1 == "see")
        report("GetArgs texture: arg2 preserved as |T...|t",
               t2 == "|TInterface/Icons/Foo:0|t",
               ("got " .. tostring(t2)))
        report("GetArgs texture: rest=after",              trest == "after")

        -- Leading + trailing whitespace tolerated
        local w1, wrest = GA("   leading  ", 1)
        report("GetArgs leading whitespace stripped",  w1 == "leading")
        report("GetArgs trailing whitespace stripped", wrest == "")

        -- Args beyond available are nil
        local x1, x2, x3, xrest = GA("only", 3)
        report("GetArgs more numargs than tokens: arg1=only", x1 == "only")
        report("GetArgs more numargs than tokens: arg2=nil",  x2 == nil)
        report("GetArgs more numargs than tokens: arg3=nil",  x3 == nil)
        report("GetArgs more numargs than tokens: rest=''",   xrest == "")

        -- Unmatched quote: consumes rest as the token
        local u1, urest = GA('"unmatched here', 1)
        report("GetArgs unmatched quote consumes tail",
               u1 == "unmatched here" and urest == "")

        -- Bad input rejected
        report("GetArgs non-string str errors",
               not pcall(function() CS:GetArgs(42, 1) end))
        report("GetArgs zero numargs errors",
               not pcall(function() CS:GetArgs("x", 0) end))
    end


    -- Cleanup
    CS.registry[NAME]  = nil
    CS.registry[NAME2] = nil
end
