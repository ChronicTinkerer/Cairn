-- Cairn-Util-Path smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; Path.Get walks dot-
-- separated paths and returns nil safely on missing intermediates;
-- Path.Set creates intermediate tables, preserves siblings, errors
-- loud on non-table collision and on empty path, returns the root
-- for chaining.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Path"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Path table exists",     type(CU.Path) == "table")
    report("CU.Path.Get is a function", type(CU.Path and CU.Path.Get) == "function")
    report("CU.Path.Set is a function", type(CU.Path and CU.Path.Set) == "function")

    if not (CU.Path and type(CU.Path.Get) == "function") then return end

    local P = CU.Path


    -- 2. Path.Get
    local t = { window = { position = { x = 100, y = 50 } }, scale = 1.25 }
    report("Get nested value",                P.Get(t, "window.position.x") == 100)
    report("Get nested sibling",              P.Get(t, "window.position.y") == 50)
    report("Get top-level scalar",            P.Get(t, "scale") == 1.25)
    report("Get missing deep returns nil",    P.Get(t, "window.size.width") == nil)
    report("Get missing top returns nil",     P.Get(t, "missing.path.deeper") == nil)
    report("Get through non-table returns nil", P.Get({ a = 5 }, "a.b") == nil)
    report("Get on nil returns nil",          P.Get(nil, "anything") == nil)


    -- 3. Path.Set creates intermediates
    local t2 = {}
    P.Set(t2, "window.position.x", 100)
    report("Set creates first intermediate",  type(t2.window) == "table")
    report("Set creates second intermediate", type(t2.window.position) == "table")
    report("Set leaf value",                  t2.window.position.x == 100)

    P.Set(t2, "window.position.y", 50)
    report("Set preserves existing sibling",  t2.window.position.x == 100)
    report("Set adds new sibling",            t2.window.position.y == 50)

    P.Set(t2, "scale", 1.5)
    report("Set top-level value",             t2.scale == 1.5)


    -- 4. Set non-table collision and empty path raise loudly
    local t3 = { a = 5 }
    local ok, err = pcall(P.Set, t3, "a.b", 10)
    report("Set on non-table collision errors", not ok)
    report("Set preserves non-table value after error", t3.a == 5)

    local ok2 = pcall(P.Set, {}, "", "anything")
    report("Set on empty path errors", not ok2)


    -- 5. Set returns the root for chaining
    local t4 = {}
    local ret = P.Set(t4, "x", 1)
    report("Set returns the input table", ret == t4)
end
