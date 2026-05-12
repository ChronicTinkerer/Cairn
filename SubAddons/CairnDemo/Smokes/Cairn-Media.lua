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


    -- =====================================================================
    -- Color helpers (Decisions 1-3, 5 from the 2026-05-12 walk; MINOR 15)
    -- =====================================================================

    report("CM:GetExpansionColor is a function", type(CM.GetExpansionColor) == "function")
    report("CM:GetQualityColor   is a function", type(CM.GetQualityColor)   == "function")
    report("CM:GetFactionColor   is a function", type(CM.GetFactionColor)   == "function")
    report("CM:GetThresholdColor is a function", type(CM.GetThresholdColor) == "function")
    report("CM:GetThresholdColorHex is a function", type(CM.GetThresholdColorHex) == "function")


    -- GetExpansionColor
    if type(CM.GetExpansionColor) == "function" then
        report("GetExpansionColor('legion') = FFA335EE",
               CM:GetExpansionColor("legion") == "FFA335EE")
        report("GetExpansionColor('LEGION') case-insensitive",
               CM:GetExpansionColor("LEGION") == "FFA335EE")
        report("GetExpansionColor('dragonflight') = FF33937F",
               CM:GetExpansionColor("dragonflight") == "FF33937F")
        report("GetExpansionColor('unknown') = nil",
               CM:GetExpansionColor("unknown_xpac") == nil)
        report("GetExpansionColor(nil) = nil",
               CM:GetExpansionColor(nil) == nil)
    end


    -- GetQualityColor (depends on ITEM_QUALITY_COLORS global)
    if type(CM.GetQualityColor) == "function" and _G.ITEM_QUALITY_COLORS then
        local epic = CM:GetQualityColor("Epic")
        report("GetQualityColor('Epic') returns a hex string",
               type(epic) == "string" and #epic == 8)
        report("GetQualityColor('epic') case-insensitive",
               CM:GetQualityColor("epic") == epic)
        report("GetQualityColor('NonExistent') = nil",
               CM:GetQualityColor("NonExistent") == nil)
    end


    -- GetFactionColor (depends on FACTION_BAR_COLORS or uses fallback)
    if type(CM.GetFactionColor) == "function" then
        local alliance = CM:GetFactionColor("Alliance")
        report("GetFactionColor('Alliance') returns a hex string",
               type(alliance) == "string" and #alliance == 8)
        report("GetFactionColor('alliance') case-insensitive",
               CM:GetFactionColor("alliance") == alliance)
        local horde = CM:GetFactionColor("Horde")
        report("GetFactionColor('Horde') returns a hex string",
               type(horde) == "string" and #horde == 8)
        report("GetFactionColor('Neutral') = nil",
               CM:GetFactionColor("Neutral") == nil)
    end


    -- GetThresholdColor — descending stops (latency-style)
    if type(CM.GetThresholdColor) == "function" then
        local function approx(a, b) return math.abs(a - b) < 0.01 end

        local r1, g1, b1 = CM:GetThresholdColor(0, 1000, 500, 250, 100, 0)
        report("GetThresholdColor: 0ms with descending stops -> green",
               approx(r1, 0) and approx(g1, 1) and approx(b1, 0),
               ("got " .. string.format("(%.2f, %.2f, %.2f)", r1 or 0, g1 or 0, b1 or 0)))

        local r2, g2, b2 = CM:GetThresholdColor(1000, 1000, 500, 250, 100, 0)
        report("GetThresholdColor: 1000ms with descending stops -> red",
               approx(r2, 1) and approx(g2, 0) and approx(b2, 0))

        local r3, g3, b3 = CM:GetThresholdColor(500, 1000, 500, 250, 100, 0)
        report("GetThresholdColor: 500ms with descending stops -> yellow midpoint",
               approx(r3, 1) and approx(g3, 1) and approx(b3, 0))

        -- Ascending stops (quality-style: 0 = worst, 1 = best)
        local r4, g4, b4 = CM:GetThresholdColor(1.0, 0, 0.25, 0.5, 0.75, 1.0)
        report("GetThresholdColor: 1.0 quality with ascending stops -> green",
               approx(r4, 0) and approx(g4, 1) and approx(b4, 0))

        local r5, g5, b5 = CM:GetThresholdColor(0, 0, 0.25, 0.5, 0.75, 1.0)
        report("GetThresholdColor: 0.0 quality with ascending stops -> red",
               approx(r5, 1) and approx(g5, 0) and approx(b5, 0))

        -- NaN guard
        local nan = 0/0
        local rN, gN, bN = CM:GetThresholdColor(nan, 0, 1)
        report("GetThresholdColor: NaN -> neutral yellow (no crash)",
               approx(rN, 1) and approx(gN, 1) and approx(bN, 0))

        -- Inf guard
        local rI, gI, bI = CM:GetThresholdColor(math.huge, 0, 1)
        report("GetThresholdColor: Inf -> neutral yellow",
               approx(rI, 1) and approx(gI, 1) and approx(bI, 0))

        -- Boundary clamp — descending stops (1, 0) where low value = best.
        -- Below-range (-100) clamps to lo (0) which is BEST → green.
        local r6, g6, b6 = CM:GetThresholdColor(-100, 1, 0)
        report("GetThresholdColor: below-range with descending stops clamps to best end (green)",
               approx(r6, 0) and approx(g6, 1) and approx(b6, 0),
               ("got " .. string.format("(%.2f, %.2f, %.2f)", r6 or 0, g6 or 0, b6 or 0)))

        -- Above-range — descending stops (1, 0) where high value = worst.
        -- Above-range (100) clamps to hi (1) which is WORST → red.
        local r7, g7, b7 = CM:GetThresholdColor(100, 1, 0)
        report("GetThresholdColor: above-range with descending stops clamps to worst end (red)",
               approx(r7, 1) and approx(g7, 0) and approx(b7, 0))
    end


    -- GetThresholdColorHex
    if type(CM.GetThresholdColorHex) == "function" then
        local hex = CM:GetThresholdColorHex(0, 1000, 500, 250, 100, 0)
        report("GetThresholdColorHex returns 8-char hex string",
               type(hex) == "string" and #hex == 8)
        report("GetThresholdColorHex starts with 'FF'",
               hex:sub(1, 2) == "FF")
    end
end
