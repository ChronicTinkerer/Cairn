-- Cairn-Util-Bitfield smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; :New builds a manager
-- from a flag array; default field name + custom field name both work;
-- :Has/:Add/:Remove operate as expected; multiple flags coexist
-- independently; nil-when-zero clears the storage field on full removal;
-- :IsEmpty reflects state; unknown flag names error loudly; multi-word
-- case (>32 flags) handles cross-word independence; bit-31 boundary.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Bitfield"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Bitfield table exists",      type(CU.Bitfield) == "table")
    report("CU.Bitfield.New is a function", type(CU.Bitfield and CU.Bitfield.New) == "function")

    if not (CU.Bitfield and type(CU.Bitfield.New) == "function") then return end


    -- 2. Single-word case (<= 32 flags)
    local States = CU.Bitfield:New({
        flags = { "KNOWN", "CAN_USE", "LEARNED", "SHARED" },
        field = "states",
    })
    report("New returns a manager",          type(States) == "table")

    local recipe = {}
    report("IsEmpty on fresh entity",        States:IsEmpty(recipe) == true)
    report("Has on fresh entity is false",   States:Has(recipe, "KNOWN") == false)

    States:Add(recipe, "KNOWN")
    report("Has after Add",                  States:Has(recipe, "KNOWN") == true)
    report("IsEmpty false after Add",        States:IsEmpty(recipe) == false)
    report("Storage field is a number",      type(recipe.states) == "number")
    report("Other flag still false",         States:Has(recipe, "CAN_USE") == false)

    States:Add(recipe, "LEARNED")
    report("Add second flag preserves first", States:Has(recipe, "KNOWN") == true)
    report("Second flag is set",             States:Has(recipe, "LEARNED") == true)

    States:Remove(recipe, "KNOWN")
    report("Remove clears one flag",          States:Has(recipe, "KNOWN") == false)
    report("Other flag remains after Remove", States:Has(recipe, "LEARNED") == true)
    report("IsEmpty false with one flag left", States:IsEmpty(recipe) == false)

    States:Remove(recipe, "LEARNED")
    report("Remove last flag empties",       States:IsEmpty(recipe) == true)
    report("Storage field is nil (sparse)",  recipe.states == nil)


    -- 3. Custom field name
    local Roles = CU.Bitfield:New({
        flags = { "TANK", "HEALER", "DAMAGER" },
        field = "role_bits",
    })
    local unit = {}
    Roles:Add(unit, "TANK")
    report("Custom field name used",         type(unit.role_bits) == "number")
    report("Default field not touched",      unit._bitfield == nil)


    -- 4. Default field name
    local Tags = CU.Bitfield:New({ flags = { "A", "B" } })
    local x = {}
    Tags:Add(x, "A")
    report("Default field name '_bitfield' is used", type(x._bitfield) == "number")


    -- 5. Unknown flag errors
    local ok  = pcall(States.Has, States, recipe, "NEVER_DEFINED")
    report("Has with unknown flag errors",    not ok)
    local ok2 = pcall(States.Add, States, recipe, "NEVER_DEFINED")
    report("Add with unknown flag errors",    not ok2)
    local ok3 = pcall(States.Remove, States, recipe, "NEVER_DEFINED")
    report("Remove with unknown flag errors", not ok3)


    -- 6. Multi-word case (>32 flags)
    local manyFlags = {}
    for i = 1, 40 do manyFlags[i] = "F" .. i end
    local Big = CU.Bitfield:New({ flags = manyFlags, field = "flags" })
    local ent = {}

    Big:Add(ent, "F1")    -- word 1, bit 0
    Big:Add(ent, "F33")   -- word 2, bit 0
    report("Multiword storage is a table",  type(ent.flags) == "table")
    report("F1 (word 1) is set",            Big:Has(ent, "F1") == true)
    report("F33 (word 2) is set",           Big:Has(ent, "F33") == true)
    report("F2 (word 1) is NOT set",        Big:Has(ent, "F2") == false)
    report("F34 (word 2) is NOT set",       Big:Has(ent, "F34") == false)

    Big:Remove(ent, "F1")
    report("Removing F1 leaves F33",        Big:Has(ent, "F33") == true)
    report("Entity not empty yet",          Big:IsEmpty(ent) == false)

    Big:Remove(ent, "F33")
    report("All-words-zero clears storage", ent.flags == nil)
    report("IsEmpty true after full clear", Big:IsEmpty(ent) == true)


    -- 7. Bit-31 boundary (signed/unsigned interplay)
    local Many32 = {}
    for i = 1, 32 do Many32[i] = "B" .. (i - 1) end  -- B0..B31
    local Edge = CU.Bitfield:New({ flags = Many32, field = "bits" })
    local e = {}
    Edge:Add(e, "B31")
    report("Bit 31 add works",              Edge:Has(e, "B31") == true)
    report("Bit 0 still unset",             Edge:Has(e, "B0") == false)
    Edge:Add(e, "B0")
    report("Add bit 0 alongside bit 31",    Edge:Has(e, "B0") == true and Edge:Has(e, "B31") == true)
    Edge:Remove(e, "B0")
    report("Removing bit 0 leaves bit 31",  Edge:Has(e, "B31") == true)
    Edge:Remove(e, "B31")
    report("Both removed clears storage",   e.bits == nil)
end
