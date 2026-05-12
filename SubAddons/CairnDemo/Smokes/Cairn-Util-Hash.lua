-- Cairn-Util-Hash smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; MD5 + MD5Raw match
-- RFC 1321 reference vectors; FNV1a32 matches standard reference
-- vectors (empty / "a" / "foobar"), is deterministic, distinct inputs
-- produce distinct outputs, seed differentiates hash spaces, output
-- stays in uint32 range; Combine is order-independent, dup-removing,
-- handles zero / one / multi arg cases.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Hash"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Hash table exists",          type(CU.Hash) == "table")
    report("CU.Hash.MD5 is a function",     type(CU.Hash and CU.Hash.MD5) == "function")
    report("CU.Hash.MD5Raw is a function",  type(CU.Hash and CU.Hash.MD5Raw) == "function")
    report("CU.Hash.FNV1a32 is a function", type(CU.Hash and CU.Hash.FNV1a32) == "function")
    report("CU.Hash.Combine is a function", type(CU.Hash and CU.Hash.Combine) == "function")

    if not (CU.Hash and type(CU.Hash.FNV1a32) == "function") then return end

    local H = CU.Hash


    -- 2. MD5 reference vectors (RFC 1321)
    report("MD5('')",    H.MD5("")    == "d41d8cd98f00b204e9800998ecf8427e")
    report("MD5('a')",   H.MD5("a")   == "0cc175b9c0f1b6a831c399e269772661")
    report("MD5('abc')", H.MD5("abc") == "900150983cd24fb0d6963f7d28e17f72")
    report("MD5Raw length is 16 bytes", #H.MD5Raw("anything") == 16)


    -- 3. FNV-1a 32-bit reference vectors
    report("FNV1a32('') == offset basis", H.FNV1a32("") == 2166136261)
    report("FNV1a32('a')",                H.FNV1a32("a") == 3826002220)
    report("FNV1a32('foobar')",           H.FNV1a32("foobar") == 3214735720)

    report("FNV1a32 deterministic",                H.FNV1a32("test") == H.FNV1a32("test"))
    report("FNV1a32 distinct inputs distinct out", H.FNV1a32("a") ~= H.FNV1a32("b"))

    -- Seed differentiation.
    report("FNV1a32 seed 1 != seed 2 on short input", H.FNV1a32("x", 1) ~= H.FNV1a32("x", 2))
    report("FNV1a32 seed 2 != seed 3 on short input", H.FNV1a32("x", 2) ~= H.FNV1a32("x", 3))
    report("FNV1a32 unseeded != seeded",               H.FNV1a32("x") ~= H.FNV1a32("x", 1))

    -- Output range
    local h = H.FNV1a32("range-check")
    report("FNV1a32 result in uint32 range", h >= 0 and h < 4294967296)


    -- 4. Combine
    report("Combine() == 0",              H.Combine() == 0)
    report("Combine(a) == a",             H.Combine(42) == 42)
    report("Combine order-independent",   H.Combine(100, 200) == H.Combine(200, 100))
    report("Combine dup-removing",        H.Combine(42, 42) == 0)
    report("Combine three-arg",           H.Combine(1, 2, 3) == bit.bxor(bit.bxor(1, 2), 3) % 4294967296)
    report("Combine empty != small hash", H.Combine() ~= H.FNV1a32("anything"))
end
