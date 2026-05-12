-- Cairn-Util-String smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; TitleCase handles
-- apostrophes / hyphens / spaces / mixed case / digits / single letters /
-- idempotence; NormalizeWhitespace handles CR/LF stripping, edge
-- trimming, internal collapsing, empty / whitespace-only / already-
-- normal inputs.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-String"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.String table exists",                      type(CU.String) == "table")
    report("CU.String.TitleCase is a function",           type(CU.String and CU.String.TitleCase) == "function")
    report("CU.String.NormalizeWhitespace is a function", type(CU.String and CU.String.NormalizeWhitespace) == "function")

    if not (CU.String and type(CU.String.TitleCase) == "function") then return end

    local TC = CU.String.TitleCase
    local NW = CU.String.NormalizeWhitespace


    -- 2. TitleCase
    report("TitleCase basic word",          TC("hello") == "Hello")
    report("TitleCase all-caps input",      TC("HELLO") == "Hello")
    report("TitleCase mixed-case input",    TC("hELLO") == "Hello")
    report("TitleCase apostrophe",          TC("o'connor") == "O'Connor")
    report("TitleCase hyphen",              TC("jean-luc") == "Jean-Luc")
    report("TitleCase multi-word",          TC("de la cruz") == "De La Cruz")
    report("TitleCase single letter",       TC("a") == "A")
    report("TitleCase empty string",        TC("") == "")
    report("TitleCase digits left alone",   TC("123abc") == "123Abc")
    report("TitleCase idempotent",          TC(TC("o'connor")) == "O'Connor")


    -- 3. NormalizeWhitespace
    report("NormalizeWhitespace trim edges",        NW("  hello  ") == "hello")
    report("NormalizeWhitespace collapse internal", NW("a    b") == "a b")
    report("NormalizeWhitespace strip LF",          NW("first\nsecond") == "firstsecond")
    report("NormalizeWhitespace strip CRLF",        NW("a\r\nb") == "ab")
    report("NormalizeWhitespace combined",          NW("  hello   world  \n") == "hello world")
    report("NormalizeWhitespace empty string",      NW("") == "")
    report("NormalizeWhitespace whitespace-only",   NW(" ") == "")
    report("NormalizeWhitespace already-normal",    NW("hello world") == "hello world")
    report("NormalizeWhitespace tabs collapse",     NW("a\tb") == "a b")


    -- 4. Colorize / ColorizeRGB (Cairn-Media Decision 4 — landed in Util at MINOR 32)
    report("CU.String.Colorize is a function",
           type(CU.String.Colorize) == "function")
    report("CU.String.ColorizeRGB is a function",
           type(CU.String.ColorizeRGB) == "function")

    if type(CU.String.Colorize) == "function" then
        local C = CU.String.Colorize
        report("Colorize wraps with |c...|r",
               C("Hi", "FFFF0000") == "|cFFFF0000Hi|r")
        report("Colorize stringifies non-string text",
               C(42, "FF00FF00") == "|cFF00FF00" .. "42" .. "|r")
    end

    if type(CU.String.ColorizeRGB) == "function" then
        local CR = CU.String.ColorizeRGB
        -- Three-float form
        report("ColorizeRGB three floats produces FF-prefix hex",
               CR("Hi", 1, 0, 0) == "|cFFFF0000Hi|r")
        report("ColorizeRGB rounds via floor(v*255 + 0.5)",
               CR("X", 0.5, 0.5, 0.5) == "|cFF808080X|r")
        -- Table form
        report("ColorizeRGB accepts {r,g,b} table",
               CR("Y", {r=0, g=1, b=0}) == "|cFF00FF00Y|r")
        report("ColorizeRGB table missing fields uses default 1 (white)",
               CR("Z", {}) == "|cFFFFFFFFZ|r")
    end
end
