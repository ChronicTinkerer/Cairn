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


    -- Cleanup
    CL:SetOverride(nil)
    CL.registry[NAME]  = nil
    CL.registry[NAME2] = nil
end
