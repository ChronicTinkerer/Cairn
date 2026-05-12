-- Cairn-Util-Numbers smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; FormatWithCommas
-- handles positive / negative / fractional / single-digit / no-comma
-- inputs; FormatWithCommasToThousands branches correctly across raw /
-- K / M ranges, handles negatives, inserts commas for >= 1B values.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Numbers"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Numbers table exists",                             type(CU.Numbers) == "table")
    report("CU.Numbers.FormatWithCommas is a function",           type(CU.Numbers and CU.Numbers.FormatWithCommas) == "function")
    report("CU.Numbers.FormatWithCommasToThousands is a function", type(CU.Numbers and CU.Numbers.FormatWithCommasToThousands) == "function")

    if not (CU.Numbers and type(CU.Numbers.FormatWithCommas) == "function") then return end

    local FC = CU.Numbers.FormatWithCommas
    local FK = CU.Numbers.FormatWithCommasToThousands


    -- 2. FormatWithCommas
    report("FormatWithCommas(0)",            FC(0) == "0")
    report("FormatWithCommas(999)",          FC(999) == "999")
    report("FormatWithCommas(1000)",         FC(1000) == "1,000")
    report("FormatWithCommas(1234567)",      FC(1234567) == "1,234,567")
    report("FormatWithCommas(1234567.89)",   FC(1234567.89) == "1,234,567.89")
    report("FormatWithCommas(-1234567)",     FC(-1234567) == "-1,234,567")
    report("FormatWithCommas(-999)",         FC(-999) == "-999")
    report("FormatWithCommas(1000000000)",   FC(1000000000) == "1,000,000,000")


    -- 3. FormatWithCommasToThousands
    report("FormatWithCommasToThousands(0)",           FK(0) == "0")
    report("FormatWithCommasToThousands(999)",         FK(999) == "999")
    report("FormatWithCommasToThousands(1000)",        FK(1000) == "1.00K")
    report("FormatWithCommasToThousands(12500)",       FK(12500) == "12.50K")
    report("FormatWithCommasToThousands(999000)",      FK(999000) == "999.00K")
    report("FormatWithCommasToThousands(1000000)",     FK(1000000) == "1.00M")
    report("FormatWithCommasToThousands(1234567)",     FK(1234567) == "1.23M")
    report("FormatWithCommasToThousands(1500000000)",  FK(1500000000) == "1,500.00M")
    report("FormatWithCommasToThousands(-1500000)",    FK(-1500000) == "-1.50M")
    report("FormatWithCommasToThousands(-1500000000)", FK(-1500000000) == "-1,500.00M")
    report("FormatWithCommasToThousands(-999)",        FK(-999) == "-999")
end
