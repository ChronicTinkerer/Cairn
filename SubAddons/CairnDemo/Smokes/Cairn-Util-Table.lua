-- Cairn-Util-Table smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; Snapshot returns a
-- shallow copy that survives source mutation; MergeDefaults preserves
-- user values, recurses, refuses to overwrite a scalar with a defaults-
-- side table; DeepCopy handles nested tables, cycles, metatables
-- (shared, not duplicated), non-table inputs, and refs.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Table"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Table table exists",                type(CU.Table) == "table")
    report("CU.Table.Snapshot is a function",      type(CU.Table and CU.Table.Snapshot) == "function")
    report("CU.Table.MergeDefaults is a function", type(CU.Table and CU.Table.MergeDefaults) == "function")
    report("CU.Table.DeepCopy is a function",      type(CU.Table and CU.Table.DeepCopy) == "function")

    if not (CU.Table and type(CU.Table.DeepCopy) == "function") then return end

    local Snap = CU.Table.Snapshot
    local MD   = CU.Table.MergeDefaults
    local DC   = CU.Table.DeepCopy


    -- 2. Snapshot
    local arr  = { 10, 20, 30 }
    local snap = Snap(arr)
    report("Snapshot returns same length",          #snap == 3)
    report("Snapshot returns same values",          snap[1] == 10 and snap[2] == 20 and snap[3] == 30)
    report("Snapshot survives source mutation",
           (function() arr[1] = 999; return snap[1] == 10 end)())
    report("Snapshot on nil returns empty table",       type(Snap(nil)) == "table" and #Snap(nil) == 0)
    report("Snapshot on non-table returns empty table", type(Snap("nope")) == "table" and #Snap("nope") == 0)


    -- 3. MergeDefaults
    local t = { a = "user", nested = { x = "user-x" } }
    MD(t, { a = "DEFAULT", b = "fill", nested = { x = "DEFAULT-X", y = "fill-y" } })
    report("MergeDefaults preserves user scalar",       t.a == "user")
    report("MergeDefaults fills missing scalar",        t.b == "fill")
    report("MergeDefaults preserves user nested scalar", t.nested.x == "user-x")
    report("MergeDefaults fills missing nested scalar", t.nested.y == "fill-y")

    local t2 = { count = 5 }
    MD(t2, { count = { wrap = "table" } })
    report("MergeDefaults preserves user scalar when default is a table", t2.count == 5)


    -- 4. DeepCopy
    local src = { a = 1, b = { c = 2, d = { e = 3 } } }
    local cp = DC(src)
    report("DeepCopy returns a table",                  type(cp) == "table")
    report("DeepCopy is not the same instance",         cp ~= src)
    report("DeepCopy preserves scalar values",          cp.a == 1)
    report("DeepCopy recurses into nested tables",      cp.b ~= src.b and cp.b.c == 2)
    report("DeepCopy recurses deeper",                  cp.b.d ~= src.b.d and cp.b.d.e == 3)

    cp.b.c   = 999
    cp.b.d.e = 888
    report("DeepCopy mutation doesn't bleed to source", src.b.c == 2 and src.b.d.e == 3)

    -- Cycle handling.
    local cyc = { name = "self-ref" }
    cyc.self  = cyc
    local cycCopy = DC(cyc)
    report("DeepCopy of cyclic table returns",          type(cycCopy) == "table")
    report("DeepCopy preserves self-reference shape",   cycCopy.self == cycCopy)
    report("DeepCopy of cyclic table is not source",    cycCopy ~= cyc)

    -- Metatable handling: shared reference.
    local mt   = { __index = function() return "class-method" end }
    local obj  = setmetatable({ data = "instance" }, mt)
    local objCopy = DC(obj)
    report("DeepCopy preserves metatable identity",     getmetatable(objCopy) == mt)
    report("DeepCopy copy still routes through metatable", objCopy.something == "class-method")
    report("DeepCopy mutation of copy doesn't touch source",
           (function() objCopy.data = "changed"; return obj.data == "instance" end)())

    -- Non-table inputs pass through.
    report("DeepCopy of nil returns nil",               DC(nil) == nil)
    report("DeepCopy of number returns number",         DC(42) == 42)
    report("DeepCopy of string returns string",         DC("hello") == "hello")
    report("DeepCopy of bool returns bool",             DC(true) == true)

    -- Functions, userdata, and tables-as-keys pass by reference.
    local fn      = function() end
    local refCopy = DC({ fn = fn })
    report("DeepCopy passes function by reference",     refCopy.fn == fn)
end
