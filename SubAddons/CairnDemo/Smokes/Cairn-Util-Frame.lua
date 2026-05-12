-- Cairn-Util-Frame smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; NormalizeSetPointArgs
-- handles full 5-arg form, abbreviated 1-arg form (expands defaults),
-- abbreviated 4-arg form with relativeTo + offsets, and round-trips an
-- existing frame's anchor via frame:GetPoint(1).

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Frame"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Frame table exists",                        type(CU.Frame) == "table")
    report("CU.Frame.NormalizeSetPointArgs is a function", type(CU.Frame and CU.Frame.NormalizeSetPointArgs) == "function")

    if not (CU.Frame and type(CU.Frame.NormalizeSetPointArgs) == "function") then return end

    local NSPA = CU.Frame.NormalizeSetPointArgs


    -- 2. Full 5-arg form round-trips
    local p, rel, rp, x, y = NSPA("CENTER", UIParent, "CENTER", 10, 20)
    report("Full 5-arg point",         p == "CENTER")
    report("Full 5-arg relativeTo",    rel == UIParent)
    report("Full 5-arg relativePoint", rp == "CENTER")
    report("Full 5-arg offsetX",       x == 10)
    report("Full 5-arg offsetY",       y == 20)


    -- 3. Abbreviated 1-arg form expands defaults
    local p2, rel2, rp2, x2, y2 = NSPA("TOPLEFT")
    report("Abbreviated point",                  p2 == "TOPLEFT")
    report("Abbreviated relativePoint default",  rp2 == "TOPLEFT")
    report("Abbreviated offsetX default",        x2 == 0)
    report("Abbreviated offsetY default",        y2 == 0)


    -- 4. Abbreviated 4-arg form: point + relativeTo + offsets
    local p3, rel3, rp3, x3, y3 = NSPA("LEFT", UIParent, 5, -3)
    report("4-arg point",          p3 == "LEFT")
    report("4-arg relativeTo",     rel3 == UIParent)
    report("4-arg relativePoint",  rp3 == "LEFT")
    report("4-arg offsetX",        x3 == 5)
    report("4-arg offsetY",        y3 == -3)


    -- 5. Round-trip an existing frame's anchor
    local testFrame = CreateFrame("Frame", nil, UIParent)
    testFrame:SetSize(50, 50)
    testFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 50)

    local p4, rel4, rp4, x4, y4 = NSPA(testFrame:GetPoint(1))
    report("Round-trip point",         p4 == "BOTTOMRIGHT")
    report("Round-trip relativeTo",    rel4 == UIParent)
    report("Round-trip relativePoint", rp4 == "BOTTOMRIGHT")
    report("Round-trip offsetX",       x4 == -100)
    report("Round-trip offsetY",       y4 == 50)

    testFrame:Hide()
    testFrame:SetParent(nil)
end
