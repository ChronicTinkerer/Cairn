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
end
