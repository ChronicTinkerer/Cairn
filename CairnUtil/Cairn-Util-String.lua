-- Cairn-Util-String
-- Small string helpers shared across the Cairn libs. Lives under
-- `Cairn-Util` (`local String = LibStub("Cairn-Util-1.0").String`).
--
-- v15 ships two helpers:
--   - String.TitleCase(s)
--   - String.NormalizeWhitespace(s)
--
-- License: MIT. Author: ChronicTinkerer.

local Cairn_Util = LibStub("Cairn-Util-1.0")
if not Cairn_Util then
    error("Cairn-Util-String.lua: LibStub('Cairn-Util-1.0') is nil; check TOC load order.")
end

Cairn_Util.String = Cairn_Util.String or {}
local String = Cairn_Util.String


-- String.TitleCase(s) -> string
--
-- Title-case each contiguous letter-run independently. Word-boundary
-- characters (apostrophes, hyphens, spaces, digits, punctuation) break
-- runs naturally, so multi-component names round-trip cleanly:
--
--   "o'connor"   -> "O'Connor"
--   "jean-luc"   -> "Jean-Luc"
--   "de la cruz" -> "De La Cruz"
--   "a"          -> "A"
--
-- The idiomatic `(%a)(%a+)` pattern was rejected because it requires at
-- least two consecutive letters; single-letter words at word boundaries
-- would stay lowercase ("o'connor" -> "o'Connor"). Pushing that fix to
-- consumers would violate Cairn's simplicity-applies-to-consumer pillar.
--
-- Idempotent: TitleCase(TitleCase(s)) == TitleCase(s).
--
-- Non-string input raises a Lua type error on the gsub call (loud
-- failure, which is what we want for a typo).
function String.TitleCase(s)
    return (s:gsub("(%a+)", function(word)
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end))
end


-- String.NormalizeWhitespace(s) -> string
--
-- Strip CR/LF, trim leading/trailing whitespace, collapse internal
-- whitespace runs to a single space. Built for TOC-metadata reads where
-- consumer-authoring text editors slip hidden newlines into Notes /
-- Description / Author fields.
--
-- Order of operations matters:
--   1. Strip CR/LF first so embedded newlines become "" (not " "),
--      which means "first\r\nsecond" -> "firstsecond" rather than
--      "first second".
--   2. Trim edges so a leading newline doesn't leave a residual space
--      after step 1 runs.
--   3. Collapse internal runs to a single space.
--
--   "  hello   world  \n" -> "hello world"
--   "first\r\nsecond"     -> "firstsecond"
--   "  spaced    out  "   -> "spaced out"
function String.NormalizeWhitespace(s)
    return (s
        :gsub("[\r\n]", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("%s+", " "))
end


return String
