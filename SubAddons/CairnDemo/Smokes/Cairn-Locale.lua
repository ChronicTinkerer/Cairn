-- Cairn-Locale smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, GetLocale + SetOverride, New + idempotency,
-- :Set merge behavior, :Get fallback chain, __index lookup equivalent
-- to :Get, methods take priority over locale keys, multiple instances
-- independent, Cairn-Locale:Changed event fires via Cairn-Events, input
-- validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Locale"] = function(report)
    -- 1. Library loaded + public API
    local CL = LibStub and LibStub("Cairn-Locale-1.0", true)
    report("Cairn-Locale is loaded under LibStub", CL ~= nil)
    if not CL then return end

    report("CL:New exists",          type(CL.New) == "function")
    report("CL:Get exists",          type(CL.Get) == "function")
    report("CL:GetLocale exists",    type(CL.GetLocale) == "function")
    report("CL:SetOverride exists",  type(CL.SetOverride) == "function")
    report("CL.registry is a table", type(CL.registry) == "table")


    -- 2. GetLocale + SetOverride
    local realLocale = GetLocale and GetLocale() or "enUS"

    report("GetLocale() returns a string by default", type(CL:GetLocale()) == "string")

    CL:SetOverride("deDE")
    report("After SetOverride('deDE'), GetLocale() returns 'deDE'", CL:GetLocale() == "deDE")

    CL:SetOverride(nil)
    report("After SetOverride(nil), GetLocale() returns real client locale",
           CL:GetLocale() == realLocale,
           ("got " .. tostring(CL:GetLocale())))


    -- 3. New() + idempotent registration
    local stamp = tostring(time and time() or 0)
    local NAME  = "CairnLocaleSmoke_" .. stamp

    CL.registry[NAME] = nil
    local L = CL:New(NAME)
    report("New returned a table",                 type(L) == "table")
    report("registry tracks the new instance",     CL.registry[NAME] == L)
    report("CL:Get(name) returns the instance",    CL:Get(NAME) == L)
    report("CL:Get(unknown) returns nil",          CL:Get("CairnLocaleSmoke_Nope") == nil)

    local L2 = CL:New(NAME)
    report("New(same name) returns same instance", L == L2)


    -- 4. Set + Get round-trip via the method
    L:Set("enUS", { greeting = "Hello", farewell = "Goodbye" })
    L:Set("deDE", { greeting = "Hallo" })

    CL:SetOverride("enUS")
    report("Get on existing key returns enUS value",  L:Get("greeting") == "Hello")
    report("Get on enUS-only key returns enUS value", L:Get("farewell") == "Goodbye")

    CL:SetOverride("deDE")
    report("Get on key present in deDE returns deDE", L:Get("greeting") == "Hallo")
    report("Get on key only in enUS falls back to enUS",
           L:Get("farewell") == "Goodbye")


    -- 5. __index lookup is equivalent to :Get
    CL:SetOverride("enUS")
    report("L.greeting via __index matches :Get", L.greeting == L:Get("greeting"))
    report("L.farewell via __index matches :Get", L.farewell == L:Get("farewell"))

    CL:SetOverride("deDE")
    report("__index respects locale override",    L.greeting == "Hallo")


    -- 6. Missing key falls back to the key itself
    CL:SetOverride("enUS")
    report("L:Get('nonexistent') returns 'nonexistent'", L:Get("nonexistent") == "nonexistent")
    report("L.nonexistent via __index also returns the key", L.nonexistent == "nonexistent")


    -- 7. Set merges into existing locale
    L:Set("enUS", { extra = "added later" })
    report("Original enUS keys preserved after merge",  L:Get("greeting") == "Hello")
    report("New key added by merge is reachable",       L:Get("extra") == "added later")


    -- 8. Methods take priority over locale keys named the same
    L:Set("enUS", { Set = "this is a locale string named Set" })
    report("L.Set still resolves to the method (not the localized string)",
           type(L.Set) == "function")
    report("L:Get('Set') can still reach the localized string",
           L:Get("Set") == "this is a locale string named Set")


    -- 9. Independent instances
    local NAME2 = NAME .. "_other"
    CL.registry[NAME2] = nil
    local L2nd = CL:New(NAME2)
    L2nd:Set("enUS", { greeting = "Hi from L2nd" })
    report("L2nd:Get returns its own value, not L's",
           L2nd:Get("greeting") == "Hi from L2nd")
    report("L:Get still returns L's value, unaffected",
           L:Get("greeting") == "Hello")


    -- 9b. SetOverride fires "Cairn-Locale:Changed" via Cairn-Events
    local CE = LibStub and LibStub("Cairn-Events-1.0", true)
    if CE then
        CL:SetOverride(nil)

        local fires = {}
        local sub = CE:Subscribe("Cairn-Locale:Changed", function(newLocale, oldLocale)
            fires[#fires + 1] = { new = newLocale, old = oldLocale }
        end)

        local A = realLocale == "deDE" and "frFR" or "deDE"
        local B = realLocale == "frFR" and "esES" or "frFR"

        CL:SetOverride(A)
        report("SetOverride to new locale fires Cairn-Locale:Changed",
               #fires == 1 and fires[1].new == A)
        report("Event payload includes oldLocale = previous effective",
               fires[1].old == realLocale)

        CL:SetOverride(A)
        report("SetOverride to SAME effective locale does NOT fire (no-op)",
               #fires == 1)

        CL:SetOverride(B)
        report("SetOverride to different locale fires again",
               #fires == 2 and fires[2].new == B and fires[2].old == A)

        CL:SetOverride(nil)
        report("SetOverride(nil) fires with effective = real client locale",
               #fires == 3 and fires[3].new == realLocale)

        CE:Unsubscribe(sub)
    else
        report("(skipped) Cairn-Events not loaded; event-fire section skipped", true)
    end


    -- 10. Input validation
    report("New('') errors",
           not pcall(function() CL:New("") end))
    report("New(nil) errors",
           not pcall(function() CL:New(nil) end))
    report("SetOverride('') errors",
           not pcall(function() CL:SetOverride("") end))
    report("SetOverride(42) errors",
           not pcall(function() CL:SetOverride(42) end))
    report("L:Set('', {}) errors",
           not pcall(function() L:Set("", {}) end))
    report("L:Set('enUS', 'notatable') errors",
           not pcall(function() L:Set("enUS", "notatable") end))


    -- =====================================================================
    -- GetPhrase + GetEnglishFallback (added at Cairn-Locale MINOR 15)
    -- =====================================================================

    report("CL:GetPhrase is a function",
           type(CL.GetPhrase) == "function")
    report("CL:GetEnglishFallback is a function",
           type(CL.GetEnglishFallback) == "function")

    if type(CL.GetPhrase) == "function" then
        -- Reuse the existing instance L (NAME) which already has enUS + deDE.
        -- L was set up earlier in this smoke; assume its strings persist.
        CL:SetOverride("deDE")
        report("GetPhrase returns deDE value when current locale is deDE",
               CL:GetPhrase(NAME, "greeting") == "Hallo")
        report("GetPhrase falls back to enUS for keys missing in current",
               CL:GetPhrase(NAME, "farewell") == "Goodbye")
        report("GetPhrase returns nil on total miss (NOT the key)",
               CL:GetPhrase(NAME, "nonexistent_phrase") == nil)
        report("GetPhrase on unknown addon name returns nil",
               CL:GetPhrase("UnknownAddon_XYZ", "any") == nil)
        report("GetPhrase with non-string args returns nil",
               CL:GetPhrase(NAME, 42) == nil)
        CL:SetOverride(nil)
    end

    if type(CL.GetEnglishFallback) == "function" then
        -- Should ALWAYS read enUS regardless of current locale.
        CL:SetOverride("deDE")
        report("GetEnglishFallback reads enUS even when current is deDE",
               CL:GetEnglishFallback(NAME, "greeting") == "Hello")
        report("GetEnglishFallback returns nil for keys missing in enUS",
               CL:GetEnglishFallback(NAME, "german_only_key") == nil)
        report("GetEnglishFallback on unknown addon returns nil",
               CL:GetEnglishFallback("UnknownAddon_XYZ", "any") == nil)
        CL:SetOverride(nil)
    end


    -- =====================================================================
    -- MINOR 16 — :NewLocale write-proxy API + GAME_LOCALE + SetActiveLocale
    -- (Decisions 1, 2, 3, 4, 5)
    -- =====================================================================

    -- D5 — GAME_LOCALE override takes precedence over GetLocale()
    CL:SetOverride(nil)
    local prevGameLocale = _G.GAME_LOCALE
    _G.GAME_LOCALE = "frFR"
    report("GAME_LOCALE override propagates through GetLocale (D5)",
           CL:GetLocale() == "frFR")
    _G.GAME_LOCALE = prevGameLocale  -- restore real env


    -- :SetActiveLocale alias for :SetOverride
    report("CL:SetActiveLocale is a function",
           type(CL.SetActiveLocale) == "function")
    if type(CL.SetActiveLocale) == "function" then
        CL:SetActiveLocale("deDE")
        report("SetActiveLocale routes through SetOverride",
               CL:GetLocale() == "deDE")
        CL:SetActiveLocale(nil)
    end


    -- D1 — :NewLocale returns a write-proxy with auto-key-as-value
    report("CL:NewLocale is a function",
           type(CL.NewLocale) == "function")

    -- Force devMode + reset for these tests so behavior is deterministic
    local NAML = "CairnLocaleSmoke_NewLocale_" .. stamp
    CL.registry[NAML] = nil
    local prevDev = CL.devMode
    CL.devMode = true

    -- Default-locale path: auto-key-as-value
    local Len = CL:NewLocale(NAML, "enUS", true, "silent")
    report("NewLocale(default) returns a proxy",
           type(Len) == "table")
    if Len then
        Len["Hello"]   = true
        Len["Goodbye"] = true
        Len["Custom"]  = "Custom-but-string"
        local inst = CL.registry[NAML]
        report("auto-key-as-value: L['Hello'] = true → bucket['Hello'] = 'Hello' (D1)",
               inst._locales.enUS.Hello == "Hello")
        report("auto-key-as-value: L['Goodbye'] = true → bucket['Goodbye'] = 'Goodbye' (D1)",
               inst._locales.enUS.Goodbye == "Goodbye")
        report("explicit string still works on default proxy (D1)",
               inst._locales.enUS.Custom == "Custom-but-string")

        -- D2 — first-definition-wins on default
        Len["Hello"] = "Different"
        report("default-proxy: subsequent write to existing key is no-op (D2)",
               inst._locales.enUS.Hello == "Hello")
        Len["Hello"] = nil  -- nil-write allowed (deletes)
        report("default-proxy: explicit nil clears key (D2 carve-out)",
               inst._locales.enUS.Hello == nil)

        -- Bad-value rejection on default
        report("default-proxy rejects non-string non-true non-nil value (D1)",
               not pcall(function() Len["NumKey"] = 42 end))
    end

    -- Non-default-locale path: explicit values only
    local Lde = CL:NewLocale(NAML, "deDE", false)
    report("NewLocale(non-default) returns a proxy in devMode (D4 bypass)",
           type(Lde) == "table")
    if Lde then
        Lde["Goodbye"] = "Auf Wiedersehen"
        local inst = CL.registry[NAML]
        report("non-default proxy writes explicit string (D1)",
               inst._locales.deDE.Goodbye == "Auf Wiedersehen")

        -- D1 — non-default rejects `true` shorthand (would silently turn key
        -- into key value in the wrong language)
        report("non-default proxy rejects true value (D1)",
               not pcall(function() Lde["Key"] = true end))
        report("non-default proxy rejects number value (D1)",
               not pcall(function() Lde["Key"] = 99 end))
    end


    -- D4 — nil-return for non-current non-default locales when devMode OFF
    CL.devMode = false
    local NAML2 = "CairnLocaleSmoke_NewLocale2_" .. stamp
    CL.registry[NAML2] = nil

    -- Default locale always returns a proxy regardless of current
    local Lalways = CL:NewLocale(NAML2, "enUS", true)
    report("NewLocale(default) always returns proxy outside devMode (D4)",
           type(Lalways) == "table")

    -- Current client locale returns a proxy
    local currentLoc = CL:GetLocale()
    local Lcurr = CL:NewLocale(NAML2, currentLoc, false)
    report("NewLocale(current locale) returns proxy outside devMode (D4)",
           type(Lcurr) == "table")

    -- A locale guaranteed to NOT match: produce a string highly unlikely
    -- to equal currentLoc. We pick "zzZZ" as a sentinel non-locale.
    local Lnone = CL:NewLocale(NAML2, "zzZZ", false)
    report("NewLocale(non-current non-default) returns nil outside devMode (D4)",
           Lnone == nil)


    -- D3 — Missing-key modes ("warn"/"silent"/"raw")
    local NAML3 = "CairnLocaleSmoke_NewLocale3_" .. stamp
    CL.registry[NAML3] = nil
    CL.devMode = true

    local Lraw = CL:NewLocale(NAML3, "enUS", true, "raw")
    if Lraw then
        Lraw["Known"] = true
        local inst = CL.registry[NAML3]
        CL:SetOverride("enUS")
        report("raw mode returns nil on missing key (D3)",
               inst:Get("MissingKey") == nil)
        report("raw mode returns the value when present (D3)",
               inst:Get("Known") == "Known")
        CL:SetOverride(nil)
    end

    local NAML4 = "CairnLocaleSmoke_NewLocale4_" .. stamp
    CL.registry[NAML4] = nil
    local Lsil = CL:NewLocale(NAML4, "enUS", true, "silent")
    if Lsil then
        Lsil["Known"] = true
        local inst = CL.registry[NAML4]
        CL:SetOverride("enUS")
        report("silent mode returns the key on miss, no warn (D3)",
               inst:Get("MissingKey2") == "MissingKey2")
        CL:SetOverride(nil)
    end


    -- :NewLocale input validation
    report("NewLocale('', 'enUS') errors",
           not pcall(function() CL:NewLocale("", "enUS") end))
    report("NewLocale('x', '') errors",
           not pcall(function() CL:NewLocale("x", "") end))
    report("NewLocale('x', 'enUS', 'notabool') errors",
           not pcall(function() CL:NewLocale("x", "enUS", "notabool") end))
    report("NewLocale('x', 'enUS', true, 'bogusmode') errors",
           not pcall(function() CL:NewLocale("x", "enUS", true, "bogusmode") end))


    -- Cleanup
    CL.devMode = prevDev
    CL:SetOverride(nil)
    CL.registry[NAML]  = nil
    CL.registry[NAML2] = nil
    CL.registry[NAML3] = nil
    CL.registry[NAML4] = nil
    CL.registry[NAME]  = nil
    CL.registry[NAME2] = nil
end
