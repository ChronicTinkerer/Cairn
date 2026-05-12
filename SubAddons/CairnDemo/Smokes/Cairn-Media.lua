-- Cairn-Media smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, WoW built-ins registered as private,
-- fetch precedence (public > private), list filters, iter ordering,
-- Has / IsPublic inspection, public registration round-trips, icon
-- glyph API, input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Media"] = function(report)
    -- 1. Library + public API surface
    local CM = LibStub and LibStub("Cairn-Media-1.0", true)
    report("Cairn-Media is loaded under LibStub", CM ~= nil)
    if not CM then return end

    report("CM:GetFont exists",         type(CM.GetFont) == "function")
    report("CM:GetStatusbar exists",    type(CM.GetStatusbar) == "function")
    report("CM:GetBorder exists",       type(CM.GetBorder) == "function")
    report("CM:GetBackground exists",   type(CM.GetBackground) == "function")
    report("CM:GetSound exists",        type(CM.GetSound) == "function")
    report("CM:ListFonts exists",       type(CM.ListFonts) == "function")
    report("CM:Iter exists",            type(CM.Iter) == "function")
    report("CM:Has exists",             type(CM.Has) == "function")
    report("CM:IsPublic exists",        type(CM.IsPublic) == "function")
    report("CM._media is a table",      type(CM._media) == "table")


    -- 2. WoW built-ins are registered as private
    report("Font 'Default' resolves to FRIZQT__",
           CM:GetFont("Default") == [[Fonts\FRIZQT__.TTF]])
    report("Font 'Numeric' resolves to ARIALN",
           CM:GetFont("Numeric") == [[Fonts\ARIALN.TTF]])
    report("Statusbar 'Plain' resolves",   CM:GetStatusbar("Plain") ~= nil)
    report("Statusbar 'Solid' resolves",   CM:GetStatusbar("Solid") ~= nil)
    report("Border 'Tooltip' resolves",    CM:GetBorder("Tooltip") ~= nil)
    report("Background 'Solid' resolves",  CM:GetBackground("Solid") ~= nil)
    report("Sound 'Alert' resolves",       CM:GetSound("Alert") ~= nil)
    report("Unknown font name returns nil", CM:GetFont("DefinitelyNotARegisteredFont") == nil)


    -- 3. Has + IsPublic
    report("Has(font, Default) is true",   CM:Has("font", "Default"))
    report("Has(font, Unknown) is false",  not CM:Has("font", "Unknown"))
    report("IsPublic(font, Default) is false (it's private)",
           not CM:IsPublic("font", "Default"))


    -- 4. ListFonts returns all private fonts sorted
    local fonts = CM:ListFonts()
    report("ListFonts returns >= 4 entries",  #fonts >= 4)

    local sorted = true
    for i = 2, #fonts do
        if fonts[i] < fonts[i - 1] then sorted = false; break end
    end
    report("ListFonts is sorted", sorted)

    local present = {}
    for _, n in ipairs(fonts) do present[n] = true end
    report("ListFonts contains Default/Numeric/Heading/Combat",
           present.Default and present.Numeric and present.Heading and present.Combat)


    -- 5. Visibility filters
    local privFonts = CM:ListPrivateFonts()
    local pubFonts  = CM:ListPublicFonts()
    report("ListPrivateFonts returns all WoW built-ins", #privFonts >= 4)
    report("ListPublicFonts contains the 3 Material Symbols variants",
           #pubFonts >= 3)

    report("ListFonts('garbage') errors",
           not pcall(function() CM:ListFonts("garbage") end))


    -- 6. Iter walks in sorted order
    local iterCount, lastName = 0, nil
    local iterSorted = true
    for name, path in CM:Iter("font") do
        iterCount = iterCount + 1
        if lastName and name < lastName then iterSorted = false end
        lastName = name
        if type(path) ~= "string" then iterSorted = false end
    end
    report("Iter('font') yields >= 4 entries",   iterCount >= 4)
    report("Iter('font') yields sorted-by-name", iterSorted)


    -- 7. Public registration round-trips
    local PUBKEY = "CairnMediaSmoke_PubOverride_" .. tostring(time and time() or 0)
    CM._media.public.font[PUBKEY] = "PublicOverridePath"
    CM._media.private.font[PUBKEY] = "PrivatePath"

    report("Public bucket beats private on name collision",
           CM:GetFont(PUBKEY) == "PublicOverridePath")
    report("IsPublic returns true for the public-bucket entry",
           CM:IsPublic("font", PUBKEY))

    CM._media.public.font[PUBKEY] = nil
    report("After removing public entry, private is exposed",
           CM:GetFont(PUBKEY) == "PrivatePath")

    CM._media.private.font[PUBKEY] = nil


    -- 8. Has accepts unknown media type without crashing
    report("Has('weird-type', 'foo') returns false (no crash)",
           CM:Has("weird-type", "foo") == false)
    report("IsPublic('weird-type', 'foo') returns false (no crash)",
           CM:IsPublic("weird-type", "foo") == false)


    -- 9. LSM probe (soft dep)
    report("CM.LSM is nil or a table",
           CM.LSM == nil or type(CM.LSM) == "table")


    -- 10. Material Symbols public-font registrations
    report("MaterialOutlined is registered as a public font", CM:IsPublic("font", "MaterialOutlined"))
    report("MaterialRounded is registered as a public font",  CM:IsPublic("font", "MaterialRounded"))
    report("MaterialSharp is registered as a public font",    CM:IsPublic("font", "MaterialSharp"))

    local outlinedPath = CM:GetFont("MaterialOutlined")
    report("MaterialOutlined path looks correct",
           type(outlinedPath) == "string"
           and outlinedPath:find("Material_Symbols_Outlined", 1, true) ~= nil)


    -- 11. Icon glyph API
    report("CM:GetIconCodepoint exists", type(CM.GetIconCodepoint) == "function")
    report("CM:GetIconGlyph exists",     type(CM.GetIconGlyph) == "function")
    report("CM:HasIcon exists",          type(CM.HasIcon) == "function")
    report("CM:ListIcons exists",        type(CM.ListIcons) == "function")
    report("CM:IterIcons exists",        type(CM.IterIcons) == "function")
    report("CM:RegisterIcon exists",     type(CM.RegisterIcon) == "function")

    report("GetIconCodepoint('close') == 0xE5CD",
           CM:GetIconCodepoint("close") == 0xE5CD)
    report("HasIcon('close') is true",   CM:HasIcon("close"))
    report("HasIcon('not_a_real_icon') is false",
           not CM:HasIcon("not_a_real_icon"))

    local glyph = CM:GetIconGlyph("close")
    report("GetIconGlyph returns a non-empty UTF-8 string",
           type(glyph) == "string" and #glyph > 0)
    report("GetIconGlyph for unknown icon returns nil",
           CM:GetIconGlyph("not_a_real_icon") == nil)

    local icons = CM:ListIcons()
    report("ListIcons returns >= 40 entries", #icons >= 40)

    local iconSorted = true
    for i = 2, #icons do
        if icons[i] < icons[i - 1] then iconSorted = false; break end
    end
    report("ListIcons is sorted", iconSorted)

    local iterIconCount = 0
    for name, cp in CM:IterIcons() do
        iterIconCount = iterIconCount + 1
        if type(name) ~= "string" or type(cp) ~= "number" then iterIconCount = -1; break end
    end
    report("IterIcons yields (string name, number codepoint) pairs",
           iterIconCount >= 40)

    local CUSTOM = "CairnMediaSmoke_custom_" .. tostring(time and time() or 0)
    CM:RegisterIcon(CUSTOM, 0xE9F0)
    report("RegisterIcon adds a custom entry",        CM:GetIconCodepoint(CUSTOM) == 0xE9F0)
    report("Custom icon round-trips through HasIcon", CM:HasIcon(CUSTOM))
    CM._icons[CUSTOM] = nil

    report("RegisterIcon('', cp) errors",
           not pcall(function() CM:RegisterIcon("", 0xE000) end))
    report("RegisterIcon(name, 'not-a-number') errors",
           not pcall(function() CM:RegisterIcon("x", "wat") end))
end
