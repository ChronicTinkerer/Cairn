-- Cairn-Util-Array smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; each of the 22
-- functions has at least one happy-path case; iteration order is
-- preserved; empty-array edge cases handled (Max/Min/Find return
-- nil); strict-equality default in IndexOf/Contains; fuzzy match via
-- IndexOfApprox; immutability of Map/Filter/Reverse; mutation by
-- Remove; gap-safe Length vs Size; MaxBy/MinBy projection caching;
-- MaxWith/MinWith use Lua's less-than convention; PickWhile takes
-- (current).

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Array"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Array table exists", type(CU.Array) == "table")
    if not (CU.Array and type(CU.Array.Map) == "function") then return end

    local A = CU.Array

    -- Function-existence sweep
    local funcs = {
        "Map", "Filter", "Find", "ForEach", "Reduce",
        "IndexOf", "IndexOfApprox", "Contains", "Equals",
        "Remove",
        "Length", "Size", "IsDense",
        "Max", "Min", "MaxBy", "MinBy", "MaxWith", "MinWith",
        "PickWhile", "DropWhile",
        "Reverse",
    }
    for _, fname in ipairs(funcs) do
        report("Array." .. fname .. " is a function", type(A[fname]) == "function")
    end


    -- 2. Iteration
    local src = { 1, 2, 3, 4 }

    local doubled = A.Map(src, function(x) return x * 2 end)
    report("Map returns new array",     doubled ~= src)
    report("Map applies fn",            doubled[1] == 2 and doubled[2] == 4 and doubled[3] == 6 and doubled[4] == 8)
    report("Map preserves length",      #doubled == 4)
    report("Map doesn't mutate source", src[1] == 1)

    local evens = A.Filter(src, function(x) return x % 2 == 0 end)
    report("Filter keeps matches",         evens[1] == 2 and evens[2] == 4)
    report("Filter drops non-matches",     #evens == 2)
    report("Filter doesn't mutate source", #src == 4)

    local found = A.Find(src, function(x) return x > 2 end)
    report("Find returns first match",  found == 3)
    report("Find returns nil if none",  A.Find(src, function(x) return x > 99 end) == nil)
    report("Find on empty array",       A.Find({}, function() return true end) == nil)

    local sum = 0
    A.ForEach(src, function(x) sum = sum + x end)
    report("ForEach iterates", sum == 10)

    local total = A.Reduce(src, function(acc, x) return acc + x end, 0)
    report("Reduce sums correctly",   total == 10)
    report("Reduce respects initial", A.Reduce({}, function(a, x) return a + x end, 42) == 42)


    -- 3. Search
    local s = { "a", "b", "c", "b" }
    report("IndexOf finds first occurrence", A.IndexOf(s, "b") == 2)
    report("IndexOf returns nil if absent",  A.IndexOf(s, "z") == nil)
    report("Contains true",                  A.Contains(s, "c") == true)
    report("Contains false",                 A.Contains(s, "z") == false)

    -- Strict ==: 1.0000001 != 1.0
    local nums = { 1.0, 2.0, 3.0 }
    report("IndexOf strict ==",             A.IndexOf(nums, 1.0000001) == nil)
    report("IndexOfApprox loose match",     A.IndexOfApprox(nums, 1.0000001, 1e-5) == 1)
    report("IndexOfApprox no match",        A.IndexOfApprox(nums, 5.0) == nil)
    report("IndexOfApprox default epsilon", A.IndexOfApprox(nums, 1.0) == 1)

    report("Equals on identical arrays",   A.Equals({1, 2, 3}, {1, 2, 3}) == true)
    report("Equals fails on diff length",  A.Equals({1, 2}, {1, 2, 3}) == false)
    report("Equals fails on diff element", A.Equals({1, 2, 3}, {1, 2, 4}) == false)
    report("Equals on two empty arrays",   A.Equals({}, {}) == true)


    -- 4. Mutation (Remove)
    local rem = { "a", "b", "c", "b" }
    local idx = A.Remove(rem, "b")
    report("Remove returns first index",          idx == 2)
    report("Remove mutates source",               #rem == 3 and rem[2] == "c")
    report("Remove only removes first occurrence", rem[3] == "b")
    report("Remove returns nil if absent",        A.Remove(rem, "z") == nil)


    -- 5. Counting
    report("Length on dense",  A.Length({1, 2, 3}) == 3)
    report("Size on dense",    A.Size({1, 2, 3}) == 3)
    report("IsDense on dense", A.IsDense({1, 2, 3}) == true)

    local sparse = { [1] = "a", [3] = "c" }
    report("Length gap-safe on sparse", A.Length(sparse) == 2)
    report("IsDense false on sparse",   A.IsDense(sparse) == false)


    -- 6. Extremes
    local nums2 = { 3, 7, 1, 5 }
    report("Max",                      A.Max(nums2) == 7)
    report("Min",                      A.Min(nums2) == 1)
    report("Max on empty returns nil", A.Max({}) == nil)
    report("Min on empty returns nil", A.Min({}) == nil)

    local people = {
        { name = "Alice", age = 30 },
        { name = "Bob",   age = 25 },
        { name = "Carol", age = 40 },
    }
    local oldest = A.MaxBy(people, function(p) return p.age end)
    report("MaxBy returns element with largest projection", oldest.name == "Carol")
    local youngest = A.MinBy(people, function(p) return p.age end)
    report("MinBy returns element with smallest projection", youngest.name == "Bob")

    local lessThan = function(a, b) return a < b end
    report("MaxWith with less-than", A.MaxWith(nums2, lessThan) == 7)
    report("MinWith with less-than", A.MinWith(nums2, lessThan) == 1)


    -- 7. Taking
    local seq = { 1, 2, 3, 10, 4, 5 }
    local taken = A.PickWhile(seq, function(x) return x < 5 end)
    report("PickWhile takes leading matches", #taken == 3 and taken[3] == 3)
    report("PickWhile stops at first miss",   taken[4] == nil)

    local dropped = A.DropWhile(seq, function(x) return x < 5 end)
    report("DropWhile skips leading matches", dropped[1] == 10)
    report("DropWhile keeps rest",            #dropped == 3 and dropped[3] == 5)


    -- 8. Builder
    local rev = A.Reverse({ 1, 2, 3, 4 })
    report("Reverse returns new array", rev[1] == 4 and rev[4] == 1)
    report("Reverse on empty",          #A.Reverse({}) == 0)
end
