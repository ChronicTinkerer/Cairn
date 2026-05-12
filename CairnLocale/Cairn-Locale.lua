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
--   CL:NewLocale(app, locale, isDefault, mode) -- AceLocale-style write-
--                                              proxy entry point. Returns
--                                              nil for non-current non-
--                                              default locales unless
--                                              Cairn.Locale.devMode = true.
--                                              See MINOR 16 section below.
--   CL:Get(name)                            -- registry lookup
--   CL.registry                             -- { [name] = instance }
--   CL.devMode                              -- set true BEFORE locale files
--                                              load to force :NewLocale to
--                                              return a proxy for every
--                                              locale (translator support).
--   CL:GetLocale()                          -- effective locale (override
--                                              if set, else GAME_LOCALE,
--                                              else GetLocale())
--   CL:SetOverride(locale_or_nil)           -- dev tool; affects ALL
--                                              instances at lookup time
--                                              and fires Cairn-Locale:Changed
--                                              when effective changes
--   CL:SetActiveLocale(locale_or_nil)       -- alias for :SetOverride
--   CL:GetPhrase(name, key)                 -- lib-level lookup; returns nil
--                                              on total miss (vs instance
--                                              :Get which returns the key)
--   CL:GetEnglishFallback(name, key)        -- reads ONLY from enUS bank
--                                              regardless of current locale.
--                                              Surfaced by Cairn-Slash
--                                              (used by Cairn-Slash).
--
-- MINOR 16 — `:NewLocale` write-proxy API (Cairn-Locale Decisions 1-5):
--
--   -- enUS.lua  (default locale, auto-key-as-value)
--   local L = LibStub("Cairn-Locale-1.0"):NewLocale("MyAddon", "enUS", true)
--   if L then
--       L["Hello"]   = true   -- becomes "Hello" via the proxy
--       L["Goodbye"] = true   -- becomes "Goodbye"
--   end
--
--   -- deDE.lua  (translation, explicit values)
--   local L = LibStub("Cairn-Locale-1.0"):NewLocale("MyAddon", "deDE")
--   if L then
--       L["Hello"] = "Hallo"
--   end
--
--   -- Missing-key modes: pass as 4th arg on the default-
--   -- locale call. Three modes: "warn" (default, prints once per key),
--   -- "silent" (returns key, no print), "raw" (returns nil).
--
-- Instance API:
--   L:Set(locale, strings)                  -- merge strings into locale
--   L:Get(key)                              -- lookup with fallback
--   L[key]                                  -- same as L:Get(key)
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Locale-1.0"
local LIB_MINOR = 16

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
    -- Resolution order:
    --   1. SetOverride/SetActiveLocale value (dev tool, runtime swap)
    --   2. GAME_LOCALE global (translator-set in dev environment so live
    --      re-renders work without changing the client install)
    --   3. GetLocale() (the client's actual locale)
    --   4. "enUS" fallback (for test VMs without GetLocale())
    if self._override then return self._override end
    if type(GAME_LOCALE) == "string" and GAME_LOCALE ~= "" then
        return GAME_LOCALE
    end
    return (GetLocale and GetLocale()) or "enUS"
end


-- :SetActiveLocale(locale) — alias for :SetOverride, matching the
-- AceLocale-style vocabulary. Both names map to the
-- same underlying mechanism + same `Cairn-Locale:Changed` event fire.
-- The dual-naming is permanent — consumers familiar with AceLocale-style
-- vocabulary find :SetActiveLocale and consumers reading older Cairn
-- code find :SetOverride. No behavioral difference.
function Cairn_Locale:SetActiveLocale(locale)
    return self:SetOverride(locale)
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
-- `resolvePhrase` helper needs the miss-as-nil
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
-- effective locale. Used by Cairn-Slash for sub-command
-- locale-fallback matching needs to compare a typed token against the
-- ENGLISH form of a registered sub-command, even when the user's client
-- is German / French / etc. Returns nil on miss so the slash router can
-- decide what to do.
--
-- Caveat: addons whose default
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


-- ---------------------------------------------------------------------------
-- :NewLocale write-proxy API (MINOR 16, Decisions 1-4)
-- ---------------------------------------------------------------------------
--
-- AceLocale-style sister API that returns a WRITE-PROXY into a locale's
-- bucket. The proxy's `__newindex` accepts the auto-key-as-value shorthand
-- (`L["Hello"] = true` rewrites to `L["Hello"] = "Hello"`) for default-
-- locale files, cutting source-locale-file LOC roughly in half.
--
-- Coexists with the existing `:New(name)` + `L:Set(locale, strings)` shape.
-- Both surfaces share the same underlying instance via the lib's registry
-- — a consumer that does `:New("MyAddon"):Set(...)` AND a translator who
-- does `:NewLocale("MyAddon", "deDE")` cooperate on one instance.
--
-- Consumer pattern (default locale):
--   local L = LibStub("Cairn-Locale-1.0"):NewLocale("MyAddon", "enUS", true)
--   if L then
--       L["Hello"]   = true      -- becomes "Hello"
--       L["Goodbye"] = true      -- becomes "Goodbye"
--   end
--
-- Consumer pattern (translation):
--   local L = LibStub("Cairn-Locale-1.0"):NewLocale("MyAddon", "deDE")
--   if L then
--       L["Hello"]   = "Hallo"
--       L["Goodbye"] = "Auf Wiedersehen"
--   end
--
-- ## Default-locale first-definition-wins
-- The default-locale proxy refuses to overwrite an existing key (no-ops
-- silently). Locale files load in any order without later-loading files
-- trampling earlier definitions. Non-default-locale proxies overwrite as
-- normal — translators legitimately need to fix typos.
--
-- ## Three missing-key modes (last-call wins)
--   "warn"   (default) — missing key returns the key string + prints a
--                        one-time warning per key. Helps translators spot
--                        gaps. The "seen warnings" set is per-app +
--                        instance-wide.
--   "silent"           — missing key returns the key string, no warning.
--                        Production-quiet.
--   "raw"              — missing key returns nil. Consumer handles
--                        fallback themselves.
--
-- ## nil-return for non-current non-default locales
-- Production: `:NewLocale("X", "frFR")` returns nil when the client locale
-- isn't frFR AND frFR isn't the default. Consumer's `if not L then return
-- end` bails the rest of the locale file. Skips 200+ entries of memory
-- bloat per non-current locale per addon.
--
-- Dev Mode bypass: set `Cairn.Locale.devMode = true` BEFORE any locale
-- file loads. All `:NewLocale` calls return a proxy regardless of current.
-- Banks populate. Translators using the `GAME_LOCALE` override
-- get live re-renders.
--
-- Default-locale path: always returns the proxy regardless of current. The
-- default IS canonical and needed for the `:GetEnglishFallback` path.

-- Tracks per-app missing-key warnings so each key warns once per session.
-- Lib-level (not per-instance) so re-loads via /reload reset the cache.
Cairn_Locale._missingKeyWarnings = Cairn_Locale._missingKeyWarnings or {}

-- Public flag for the dev-mode bypass. Default false; set true BEFORE
-- locale file load to force all `:NewLocale` calls to return proxies.
Cairn_Locale.devMode = Cairn_Locale.devMode or false


-- Internal: warn-mode missing-key handler. Caches per (app, key) so each
-- key fires at most one chat print per session.
local function warnMissingKey(appName, key)
    local cache = Cairn_Locale._missingKeyWarnings
    local bucket = cache[appName]
    if not bucket then
        bucket = {}
        cache[appName] = bucket
    end
    if bucket[key] then return end
    bucket[key] = true
    -- Use the Cairn-Log soft-dep if available; fall back to print so
    -- warnings always reach the translator's chat window.
    local Log = LibStub and LibStub("Cairn-Log-1.0", true)
    -- Existence-check must use `.` (Log.Get); calling uses `:` (Log:Get(...)).
    -- The colon operator requires immediate function arguments and isn't
    -- valid in a boolean-chain existence test.
    local logger = Log and type(Log.Get) == "function" and Log:Get("Cairn.Locale")
    if logger and logger.Warn then
        logger:Warn("[%s] missing localization for key '%s'", appName, tostring(key))
    elseif print then
        print(("|cFFFFAA00[Cairn.Locale]|r [%s] missing key '%s'"):format(
              tostring(appName), tostring(key)))
    end
end


-- :NewLocale(app, locale, isDefault, mode) -> write-proxy or nil
--
-- Returns nil when the locale isn't relevant to this client (production
-- gate). Returns a write-proxy otherwise. The proxy writes
-- through to the same instance the existing `:New(name)` returns, so the
-- two surfaces interop transparently.
function Cairn_Locale:NewLocale(app, locale, isDefault, mode)
    if type(app) ~= "string" or app == "" then
        error("Cairn-Locale:NewLocale: app must be a non-empty string", 2)
    end
    if type(locale) ~= "string" or locale == "" then
        error("Cairn-Locale:NewLocale: locale must be a non-empty string", 2)
    end
    if isDefault ~= nil and type(isDefault) ~= "boolean" then
        error("Cairn-Locale:NewLocale: isDefault must be a boolean or nil", 2)
    end
    if mode ~= nil and mode ~= "warn" and mode ~= "silent" and mode ~= "raw" then
        error("Cairn-Locale:NewLocale: mode must be 'warn', 'silent', 'raw', or nil", 2)
    end

    -- Production gate: return nil for non-current non-default
    -- locales unless devMode is active.
    local current = self:GetLocale()
    local shouldPopulate = self.devMode or isDefault or (locale == current)
    if not shouldPopulate then return nil end

    -- Ensure the backing instance exists (idempotent on app name) and
    -- pre-allocate the bucket so writes don't pay the lazy-create cost
    -- on every key.
    local inst = self.registry[app] or self:New(app)
    local bucket = inst._locales[locale]
    if not bucket then
        bucket = {}
        inst._locales[locale] = bucket
    end

    -- Stash mode on the instance so reads through L:Get respect it.
    -- Last-call wins — typically the default-locale file is the only one
    -- that supplies a mode, but if two callers conflict the last write
    -- wins to keep behavior deterministic + traceable.
    if mode ~= nil then
        inst._missingKeyMode = mode
    elseif inst._missingKeyMode == nil then
        inst._missingKeyMode = "warn"
    end

    -- Build the write-proxy. The metatable differs for default vs non-
    -- default locales (first-definition-wins on default only).
    local proxyMeta
    if isDefault then
        proxyMeta = {
            __newindex = function(_, key, value)
                -- Explicit nil writes ALWAYS clear (D2 carve-out for typo
                -- correction). The first-definition-wins rule applies to
                -- non-nil writes only.
                if value == nil then
                    bucket[key] = nil
                    return
                end
                if bucket[key] ~= nil then return end  -- first-def wins
                if value == true then
                    bucket[key] = key  -- auto-key-as-value shorthand
                elseif type(value) == "string" then
                    bucket[key] = value
                else
                    error("Cairn-Locale: default-locale value must be a string, true, or nil (key='"
                          .. tostring(key) .. "', got " .. type(value) .. ")", 2)
                end
            end,
            __index = function(_, key) return bucket[key] end,
        }
        -- Mark this app's default locale so missing-key warns are tied to
        -- a known default. Used by the read-side via inst._defaultLocale.
        inst._defaultLocale = locale
    else
        proxyMeta = {
            __newindex = function(_, key, value)
                if value == nil then
                    bucket[key] = nil
                elseif type(value) == "string" then
                    bucket[key] = value
                elseif value == true then
                    -- Translation files writing `L["foo"] = true` is a
                    -- mistake (would mean "use the key string as the
                    -- French translation"); loudly reject.
                    error("Cairn-Locale: non-default-locale value cannot be true (key='"
                          .. tostring(key) .. "')", 2)
                else
                    error("Cairn-Locale: non-default-locale value must be a string or nil (key='"
                          .. tostring(key) .. "', got " .. type(value) .. ")", 2)
                end
            end,
            __index = function(_, key) return bucket[key] end,
        }
    end

    return setmetatable({}, proxyMeta)
end


-- Re-wire LocaleMethods:Get to honor the per-instance missing-key mode.
-- Backward-compat: instances created via the legacy `:New(name)` path
-- never set `_missingKeyMode`, so they fall through to the existing
-- "return the key" behavior (acting as `silent` mode without the chat
-- print — keeps existing consumers' behavior identical).
do
    local rawGetMethod = LocaleMethods.Get
    LocaleMethods.Get = function(self, key)
        if type(key) ~= "string" then return tostring(key) end

        local current = Cairn_Locale:GetLocale()
        local bucket  = self._locales[current]
        if bucket and bucket[key] ~= nil then
            return bucket[key]
        end

        local enUS = self._locales["enUS"]
        if enUS and enUS[key] ~= nil then
            return enUS[key]
        end

        -- Missing-key path. Mode-driven behavior:
        --   raw    -> nil
        --   silent -> key
        --   warn   -> key + one-time chat warning
        --   nil    -> key (legacy / silent-equivalent without warn)
        --
        -- IMPORTANT: use rawget for _missingKeyMode + _name lookup. The
        -- instance metatable's __index routes missing-field reads back
        -- through LocaleMethods.Get; without rawget, instances created
        -- via the legacy `:New(name)` path (which never set
        -- _missingKeyMode) infinite-recurse here.
        local mode = rawget(self, "_missingKeyMode")
        if mode == "raw" then
            return nil
        end
        if mode == "warn" then
            warnMissingKey(rawget(self, "_name"), key)
        end
        return key
    end
end


return Cairn_Locale
