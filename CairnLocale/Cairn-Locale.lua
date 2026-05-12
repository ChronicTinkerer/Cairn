-- Cairn-Locale
-- i18n table with locale fallback. One instance per addon. ALL registered
-- locales stay in memory simultaneously — switching languages at runtime is
-- a single lookup change, not a reload.
--
--   local L = LibStub("Cairn-Locale-1.0"):New("MyAddon")
--   L:Set("enUS", { greeting = "Hello", farewell = "Goodbye" })
--   L:Set("deDE", { greeting = "Hallo" })
--
--   print(L.greeting)        -- "Hello" on enUS, "Hallo" on deDE
--   print(L:Get("farewell")) -- same lookup, method form
--   print(L.unknownKey)      -- "unknownKey"  (no nil to guard)
--
-- Lookup fallback chain on any key:
--   1. Current locale  (Cairn_Locale:GetLocale())
--   2. enUS            (canonical fallback)
--   3. The key itself  (so missing translations are visible in the UI
--                       instead of breaking consumer code with nils)
--
-- Recommended file structure for shareable translation work:
--
--   MyAddon/
--     MyAddon.toc:
--       Locales\enUS.lua
--       Locales\deDE.lua
--       Locales\frFR.lua
--       ...                  (any order; :New is idempotent)
--
--   MyAddon/Locales/enUS.lua:
--     local L = LibStub("Cairn-Locale-1.0"):New("MyAddon")
--     L:Set("enUS", { greeting = "Hello", ... })
--
--   MyAddon/Locales/deDE.lua:
--     local L = LibStub("Cairn-Locale-1.0"):New("MyAddon")
--     L:Set("deDE", { greeting = "Hallo", ... })
--
-- Each translator owns one file. The first file loaded creates the instance;
-- the rest receive the same instance via the idempotent :New.
--
-- Runtime locale changes:
--   When :SetOverride is called and the EFFECTIVE locale changes, Cairn-Locale
--   fires `Cairn-Locale:Changed` via Cairn-Events with (newLocale, oldLocale).
--   UIs displaying localized text can subscribe and refresh:
--
--     LibStub("Cairn-Events-1.0"):Subscribe("Cairn-Locale:Changed", function(newLocale)
--         MyUI:Refresh()
--     end)
--
--   The event fires ONLY if the effective locale actually changes. Calling
--   SetOverride("enUS") when the client is already enUS does not fire.
--   Cairn-Events is a soft dependency — if it isn't loaded, the event is
--   silently skipped (the locale change still happens).
--
-- Public API:
--   local CL = LibStub("Cairn-Locale-1.0")
--   CL:New(name)         -> instance       -- idempotent on `name`
--   CL:Get(name)                            -- registry lookup
--   CL.registry                             -- { [name] = instance }
--   CL:GetLocale()                          -- effective locale (override
--                                              if set, else GetLocale())
--   CL:SetOverride(locale_or_nil)           -- dev tool; affects ALL
--                                              instances at lookup time
--                                              and fires Cairn-Locale:Changed
--                                              when effective changes
--   CL:GetPhrase(name, key)                 -- lib-level lookup; returns nil
--                                              on total miss (vs instance
--                                              :Get which returns the key)
--   CL:GetEnglishFallback(name, key)        -- reads ONLY from enUS bank
--                                              regardless of current locale.
--                                              Surfaced by Cairn-Slash
--                                              Decision 3.
--
-- Instance API:
--   L:Set(locale, strings)                  -- merge strings into locale
--   L:Get(key)                              -- lookup with fallback
--   L[key]                                  -- same as L:Get(key)
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Locale-1.0"
local LIB_MINOR = 15

local Cairn_Locale = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Locale then return end


Cairn_Locale.registry  = Cairn_Locale.registry  or {}
Cairn_Locale._override = Cairn_Locale._override  -- nil unless SetOverride'd


-- ---------------------------------------------------------------------------
-- Lib-level: locale resolution
-- ---------------------------------------------------------------------------

-- Override changes notify via Cairn-Events ONLY when the EFFECTIVE locale
-- moves. This matters for two no-op cases consumers will hit in practice:
-- setting the override to its current value, and SetOverride("enUS") when
-- the client is already enUS. Firing in those cases would cause spurious
-- UI refreshes.
--
-- Cairn-Events is soft-required: a consumer that just wants Cairn-Locale's
-- lookup behavior without the notification side won't ship Cairn-Events,
-- and we shouldn't crash them.
function Cairn_Locale:SetOverride(locale)
    if locale ~= nil and (type(locale) ~= "string" or locale == "") then
        error("Cairn-Locale:SetOverride: locale must be a non-empty string or nil", 2)
    end

    local before = self:GetLocale()
    self._override = locale
    local after = self:GetLocale()

    if before ~= after then
        local CE = LibStub and LibStub("Cairn-Events-1.0", true)
        if CE then
            CE:Fire("Cairn-Locale:Changed", after, before)
        end
    end
end

function Cairn_Locale:GetLocale()
    if self._override then return self._override end
    return (GetLocale and GetLocale()) or "enUS"
end


-- ---------------------------------------------------------------------------
-- Instance methods
-- ---------------------------------------------------------------------------

local LocaleMethods = {}

-- Merge, not replace: multiple files contributing strings to the same locale
-- (the recommended one-file-per-language pattern) need to compose without
-- the last file winning. Existing key gets overwritten by the new value when
-- both files define it — last loaded wins THAT key, but adjacent keys from
-- earlier files survive.
function LocaleMethods:Set(locale, strings)
    if type(locale) ~= "string" or locale == "" then
        error("Cairn-Locale :Set: locale must be a non-empty string", 2)
    end
    if type(strings) ~= "table" then
        error("Cairn-Locale :Set: strings must be a table", 2)
    end

    local bucket = self._locales[locale]
    if not bucket then
        bucket = {}
        self._locales[locale] = bucket
    end
    for k, v in pairs(strings) do
        bucket[k] = v
    end
end


-- Never returns nil. The "return the key itself on total miss" rule means
-- a missing translation surfaces visibly in the UI (consumer sees the raw
-- key string) instead of crashing whatever code expected a string. Trades
-- a small UI ugliness for a large robustness win.
function LocaleMethods:Get(key)
    if type(key) ~= "string" then
        -- Defensive: a non-string key shouldn't crash. tostring() is
        -- guaranteed to produce something we can return.
        return tostring(key)
    end

    local current = Cairn_Locale:GetLocale()
    local bucket  = self._locales[current]
    if bucket and bucket[key] ~= nil then
        return bucket[key]
    end

    local enUS = self._locales["enUS"]
    if enUS and enUS[key] ~= nil then
        return enUS[key]
    end

    return key
end


-- Instance metatable: route method calls AND `L.key` string lookup through
-- one __index function. Methods take priority so an unfortunate locale key
-- named "Set" can't shadow the method (you'd have to use L:Get("Set") to
-- read the localized value in that case).
local LocaleMeta = {
    __index = function(L, key)
        local m = LocaleMethods[key]
        if m then return m end
        -- Internal fields stored on the instance (e.g. _name, _locales) are
        -- accessed via rawget elsewhere; if a consumer goes after an
        -- underscore-prefixed key, fall through to localization lookup.
        return LocaleMethods.Get(L, key)
    end,
}


-- ---------------------------------------------------------------------------
-- Public API: instance creation
-- ---------------------------------------------------------------------------

-- Idempotent on `name` so the one-file-per-language pattern works without
-- coordination. Each Locales/<lang>.lua file can call :New unconditionally;
-- the first wins, the rest receive the same instance and accumulate their
-- :Set calls on top of it.
function Cairn_Locale:New(name)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Locale:New: name must be a non-empty string", 2)
    end

    local existing = self.registry[name]
    if existing then return existing end

    local L = setmetatable({
        _name    = name,
        _locales = {},
    }, LocaleMeta)

    self.registry[name] = L
    return L
end


-- Cairn_Locale:Get(name)
function Cairn_Locale:Get(name)
    return self.registry[name]
end


-- Cairn_Locale:GetPhrase(name, key) -> string or nil
--
-- Lib-level resolution helper for "looks up a phrase but returns nil on
-- total miss" semantics. The instance-level `L:Get(key)` returns the key
-- itself on miss (defensive against nil-propagation in consumer code),
-- which is good for direct UI use but bad for callers who need to detect
-- "is this translation actually present?" — e.g. Cairn-Settings's
-- `resolvePhrase` helper (Cluster A Decision 3) needs the miss-as-nil
-- shape so it can fall through to the direct `label` / `tooltip` field.
--
-- Resolution order: current locale → enUS → nil. Same fallback chain
-- as `L:Get(key)` minus the "return the key on total miss" final step.
function Cairn_Locale:GetPhrase(name, key)
    if type(name) ~= "string" or type(key) ~= "string" then return nil end
    local inst = self.registry[name]
    if not inst then return nil end

    local current = self:GetLocale()
    local bucket  = inst._locales[current]
    if bucket and bucket[key] ~= nil then return bucket[key] end

    local enUS = inst._locales["enUS"]
    if enUS and enUS[key] ~= nil then return enUS[key] end

    return nil
end


-- Cairn_Locale:GetEnglishFallback(name, key) -> string or nil
--
-- Reads ONLY from the addon's enUS bank, regardless of the current
-- effective locale. Surfaced by Cairn-Slash Decision 3 — sub-command
-- locale-fallback matching needs to compare a typed token against the
-- ENGLISH form of a registered sub-command, even when the user's client
-- is German / French / etc. Returns nil on miss so the slash router can
-- decide what to do.
--
-- Caveat documented in Cairn-Locale Decision 6: addons whose default
-- locale isn't enUS won't have an English bank populated; this returns
-- nil and Cairn-Slash falls through to current-locale-only matching.
function Cairn_Locale:GetEnglishFallback(name, key)
    if type(name) ~= "string" or type(key) ~= "string" then return nil end
    local inst = self.registry[name]
    if not inst then return nil end
    local enUS = inst._locales["enUS"]
    if not enUS then return nil end
    return enUS[key]
end


return Cairn_Locale
