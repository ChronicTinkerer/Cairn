-- Cairn-DB
-- SavedVariables wrapper with default merging and named profiles.
--
-- The simple case is one line:
--
--   local db = LibStub("Cairn-DB-1.0"):New("MyAddonDB", {
--       global  = { sharedKey = 1 },
--       profile = { perProfileKey = "hello" },
--   })
--
--   print(db.global.sharedKey)          --> 1
--   print(db.profile.perProfileKey)     --> "hello"
--
-- The consumer's .toc must declare `## SavedVariables: MyAddonDB` for the
-- table to actually persist between sessions. We can't enforce that from a
-- library, but the lib will still work in-session if it's missing.
--
-- Public API:
--   local Cairn_DB = LibStub("Cairn-DB-1.0")
--   local db = Cairn_DB:New(savedVarName, defaults)   -- create instance
--   db.global         -- shared across every character (existing)
--   db.profile        -- per-profile (defaults to profile "Default")
--   db.char           -- per-character ("<name> - <realm>")        (MINOR 15)
--   db.realm          -- per-realm                                  (MINOR 15)
--   db.class          -- per-class                                  (MINOR 15)
--   db.race           -- per-race                                   (MINOR 15)
--   db.faction        -- per-faction (Alliance / Horde)             (MINOR 15)
--   db.factionrealm   -- per-faction per-realm                      (MINOR 15)
--   db:SetProfile(name)  -- switch profile (creates if missing, applies defaults)
--   db:GetProfile()      -- returns current profile name
--   db:RegisterMigration(version, fn)  -- MINOR 15
--   db:RegisterNamespace(MAJOR)        -- MINOR 15
--   db:_RemoveDefaults()               -- MINOR 16 (auto on PLAYER_LOGOUT)
--   Cairn_DB:Get(name)   -- returns the registered instance, or nil
--   Cairn_DB.instances   -- { [savedVarName] = db, ... } (for Forge_Registry)
--   Cairn_DB.MIGRATION_DEFER -- sentinel for deferred migrations (MINOR 15)
--
-- removeDefaults on PLAYER_LOGOUT (MINOR 16):
--   At PLAYER_LOGOUT Cairn-DB walks every registered instance and strips
--   keys whose values match the consumer's defaults. SV file shrinks; on
--   next load the stripped keys re-fill from defaults transparently.
--   Blocker rule: a table-typed default does NOT recurse into a user's
--   value when the user's value isn't a table (avoids corrupting
--   structural data when the user typed a scalar). Wildcard defaults
--   (`["*"]` / `["**"]`) participate in the walk — entries that match
--   the wildcard sub-default are stripped too.
--
-- Wildcard defaults (MINOR 15):
--   defaults.profile = {
--       characters = {
--           ["*"] = { level = 1, xp = 0 },         -- direct children only
--       },
--       zones = {
--           ["**"] = { visited = false },           -- recursive at every depth
--       },
--   }
--
-- Migration framework (MINOR 15):
--   db:RegisterMigration(2, function(db)
--       db.profile.foo = db.profile.bar  -- shape change
--       db.profile.bar = nil
--   end)
--
--   db:RegisterMigration(3, function(db)
--       local spec = GetSpecialization()
--       if not spec then return Cairn_DB.MIGRATION_DEFER end  -- retry on PLAYER_LOGIN
--       db.profile.specMap = { [spec] = db.profile.spec }
--   end)
--
--   Migrations receive the DB INSTANCE (not the raw sv root) so they can
--   write `db.profile.foo` / `db.char.foo` / etc. matching normal consumer
--   code. The raw sv is reachable via `rawget(db, "_sv")` if needed.
--   Migrations walk `internalVersion+1 → CURRENT_VERSION` automatically
--   at :RegisterMigration time. Returning Cairn_DB.MIGRATION_DEFER queues
--   for PLAYER_LOGIN re-run. A second defer on the PLAYER_LOGIN retry
--   errors loudly via geterrorhandler.
--
-- Lib-owned namespaces (MINOR 15):
--   local mappingStore = db:RegisterNamespace("Cairn-Settings-SpecProfile")
--   mappingStore.profile.specMap = { ... }   -- sibling sub-store, won't collide
--
-- Design notes:
--   - SavedVariables are loaded BEFORE the consumer's .lua files execute,
--     so there's no "wait for init" timing concern. New() returns a fully
--     usable db.
--   - Defaults merge is non-destructive: keys already present in the saved
--     data are preserved; only missing keys are filled from defaults.
--   - Defaults are NOT retro-applied if the consumer changes the defaults
--     table between sessions — that's an intentional limitation. Use the
--     :RegisterMigration framework if you need shape changes between
--     versions.
--   - Unknown keys in `defaults` raise an error. Catches typos loud rather
--     than silently dropping data.
--   - Bucket fields (.profile / .char / .realm / etc.) are real fields
--     updated at :New (and on :SetProfile for profile); NOT metatable
--     getters. Faster access; "don't cache the bucket across SetProfile
--     calls" gotcha is small and documented.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-DB-1.0"
local LIB_MINOR = 16

local Cairn_DB = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_DB then return end

local CU = LibStub("Cairn-Util-1.0")
local Table_ = CU.Table  -- aliased to avoid shadowing Lua's table


-- Internal state. Preserved across MINOR upgrades (LibStub returns same
-- table on upgrade; `or {}` only initializes once).
Cairn_DB.instances = Cairn_DB.instances or {}

-- Deferred-migration queue. { {db = ..., version = ..., fn = ...}, ... }
-- Drained on first PLAYER_LOGIN. Lib-scope, drained once per session.
Cairn_DB._deferredMigrations = Cairn_DB._deferredMigrations or {}


local DEFAULT_PROFILE = "Default"

-- MIGRATION_DEFER sentinel. Migrations return this
-- value to signal "I can't run yet — needs spec / class / level / etc.
-- state not available at lib-load." The lib queues the migration; on
-- first PLAYER_LOGIN, drains the queue and re-runs each. A second
-- MIGRATION_DEFER return on the PLAYER_LOGIN retry errors loudly.
Cairn_DB.MIGRATION_DEFER = Cairn_DB.MIGRATION_DEFER or {}


-- 8 standard partition buckets. Order matters for the typo-
-- detection sweep in :New; both the public bucket names AND the lib-
-- internal `__namespaces` slot live alongside `internalVersion` and
-- `currentProfile`. Consumers wanting to add custom buckets do it via
-- :RegisterNamespace, not by injecting unknown keys at the top level.
local ALLOWED_DEFAULT_KEYS = {
    global       = true,
    profile      = true,
    char         = true,
    realm        = true,
    class        = true,
    race         = true,
    faction      = true,
    factionrealm = true,
}


-- ---------------------------------------------------------------------------
-- Per-character identity resolution
-- ---------------------------------------------------------------------------
-- Captured at lib load. Defensive against running outside WoW (test VMs,
-- standalone Lua harnesses) where the globals don't exist — fall back to
-- sensible placeholders so the lib still loads.

local function resolveIdentity()
    local name  = (UnitName and UnitName("player"))  or "Unknown"
    local realm = (GetRealmName and GetRealmName())  or "UnknownRealm"
    local _, cls = (UnitClass and UnitClass("player")) or nil, "UNKNOWN"
    local _, rce = (UnitRace  and UnitRace ("player")) or nil, "Unknown"
    local fct   = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"

    return {
        char         = name .. " - " .. realm,
        realm        = realm,
        class        = cls,
        race         = rce,
        faction      = fct,
        factionrealm = fct .. " - " .. realm,
    }
end

local IDENTITY = resolveIdentity()


-- ---------------------------------------------------------------------------
-- Wildcard-aware default merge
-- ---------------------------------------------------------------------------
-- Non-destructive merge of `defaults` into `target` with two special keys:
--   ["*"]  applies the value's sub-table as the default for every
--          DIRECT child of `target` accessed via __index. Set once per
--          parent table.
--   ["**"] applies recursively at every depth below `target`. Installed
--          via a metatable that hands the wildcard down on each level.
--
-- Plain keys merge non-destructively (existing target values win). The
-- wildcard handling installs a metatable; subsequent reads of any missing
-- key on `target` return a sub-table populated from the wildcard. First
-- read MUTATES `target` (creates the entry), so on save the wildcard
-- materializes the keys the user actually used. This matches the AceDB-3.0
-- behavior consumers expect.

local function installWildcards(target, starDefault, doubleStarDefault)
    if starDefault == nil and doubleStarDefault == nil then return end
    local mt = getmetatable(target) or {}
    local prior = mt.__index
    mt.__index = function(t, k)
        if type(k) == "string" and k:sub(1, 1) == "_" then
            -- Skip lib-internal keys (e.g. _defaults, _sv). Defensive
            -- guard so wildcard defaults don't fabricate internal state.
            return nil
        end
        local newEntry = {}
        if starDefault then
            for sk, sv in pairs(starDefault) do
                if newEntry[sk] == nil then newEntry[sk] = sv end
            end
        end
        if doubleStarDefault then
            for sk, sv in pairs(doubleStarDefault) do
                if newEntry[sk] == nil then newEntry[sk] = sv end
            end
            -- Recurse: every depth below also gets the ** wildcard.
            installWildcards(newEntry, nil, doubleStarDefault)
        end
        rawset(t, k, newEntry)
        if type(prior) == "function" then prior(t, k) end
        return newEntry
    end
    setmetatable(target, mt)
end


local function wildcardMerge(target, defaults)
    if type(defaults) ~= "table" or type(target) ~= "table" then return end
    local star = defaults["*"]
    local doubleStar = defaults["**"]
    for k, v in pairs(defaults) do
        if k ~= "*" and k ~= "**" then
            if type(v) == "table" then
                if type(target[k]) ~= "table" then target[k] = {} end
                wildcardMerge(target[k], v)
            else
                if target[k] == nil then target[k] = v end
            end
        end
    end
    installWildcards(target, star, doubleStar)
end


-- Non-destructive default merge lives in Cairn-Util.Table.MergeDefaults —
-- called at New() time and again on SetProfile so newly-created profiles
-- inherit the full defaults shape, including keys added in later versions.


-- ---------------------------------------------------------------------------
-- Instance methods
-- ---------------------------------------------------------------------------

local DBMethods = {}

-- Switching profile is an opt-in via SetProfile rather than a __index getter
-- so `db.profile` stays cheap (direct field, not metatable lookup). The
-- tradeoff: capturing `local p = db.profile` BEFORE a SetProfile call leaves
-- `p` pointing at the OLD profile. Document; don't change.
--
-- We re-run mergeDefaults on every SetProfile (including switching back to
-- a profile that already exists) so a new defaults key added in a future
-- release lands in every profile the consumer touches.
function DBMethods:SetProfile(name)
    if type(name) ~= "string" or name == "" then
        error("Cairn-DB :SetProfile: name must be a non-empty string", 2)
    end

    local sv = rawget(self, "_sv")
    sv.profiles[name] = sv.profiles[name] or {}

    local defs = rawget(self, "_defaults")
    if defs and defs.profile then
        wildcardMerge(sv.profiles[name], defs.profile)
    end

    sv.currentProfile = name
    rawset(self, "profile", sv.profiles[name])
end

function DBMethods:GetProfile()
    return rawget(self, "_sv").currentProfile
end

local DBMeta = { __index = DBMethods }


-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Idempotent on name. Two .lua files in the same addon can both call New()
-- without coordinating; both get the same instance back. If they pass
-- different `defaults`, the second call's defaults are silently ignored —
-- consumer is expected to consolidate defaults at one call site.
--
-- Pitfall: the consumer's .toc MUST declare `## SavedVariables: <name>`.
-- Without it the table still works in-session, but nothing persists across
-- reloads. We can't detect this from the lib side; doc it and move on.
function Cairn_DB:New(name, defaults)
    if type(name) ~= "string" or name == "" then
        error("Cairn-DB:New: savedVarName must be a non-empty string", 2)
    end

    local existing = self.instances[name]
    if existing then return existing end

    if defaults ~= nil then
        if type(defaults) ~= "table" then
            error("Cairn-DB:New: defaults must be a table or nil", 2)
        end
        for k in pairs(defaults) do
            if not ALLOWED_DEFAULT_KEYS[k] then
                error(("Cairn-DB:New: unknown defaults key %q (allowed: %s)")
                    :format(tostring(k),
                            "global, profile, char, realm, class, race, faction, factionrealm"), 2)
            end
        end
    end

    -- Shape the saved-vars container. The `or {}` chain is doing two jobs:
    -- creating fresh shape on first-ever load, AND tolerating older saves
    -- that may pre-date a structural field.
    _G[name] = _G[name] or {}
    local sv = _G[name]

    -- Top-level shape: shared buckets at well-known keys, profiles keyed
    -- under `profiles`, namespaces keyed under `__namespaces`,
    -- migration version under `internalVersion`.
    sv.global         = sv.global         or {}
    sv.profiles       = sv.profiles       or {}
    sv.currentProfile = sv.currentProfile or DEFAULT_PROFILE
    sv.profiles[sv.currentProfile] = sv.profiles[sv.currentProfile] or {}

    -- 8-bucket partition keys. Each per-X bucket is keyed
    -- by the player's current identity. New character / realm / class /
    -- etc. transparently get fresh sub-tables on first access.
    sv.char         = sv.char         or {}
    sv.realm        = sv.realm        or {}
    sv.class        = sv.class        or {}
    sv.race         = sv.race         or {}
    sv.faction      = sv.faction      or {}
    sv.factionrealm = sv.factionrealm or {}
    sv.char[IDENTITY.char]                 = sv.char[IDENTITY.char]                 or {}
    sv.realm[IDENTITY.realm]               = sv.realm[IDENTITY.realm]               or {}
    sv.class[IDENTITY.class]               = sv.class[IDENTITY.class]               or {}
    sv.race[IDENTITY.race]                 = sv.race[IDENTITY.race]                 or {}
    sv.faction[IDENTITY.faction]           = sv.faction[IDENTITY.faction]           or {}
    sv.factionrealm[IDENTITY.factionrealm] = sv.factionrealm[IDENTITY.factionrealm] or {}

    sv.internalVersion = sv.internalVersion or 0
    sv.__namespaces    = sv.__namespaces    or {}

    if defaults then
        if defaults.global       then wildcardMerge(sv.global,                                  defaults.global)       end
        if defaults.profile      then wildcardMerge(sv.profiles[sv.currentProfile],             defaults.profile)      end
        if defaults.char         then wildcardMerge(sv.char[IDENTITY.char],                     defaults.char)         end
        if defaults.realm        then wildcardMerge(sv.realm[IDENTITY.realm],                   defaults.realm)        end
        if defaults.class        then wildcardMerge(sv.class[IDENTITY.class],                   defaults.class)        end
        if defaults.race         then wildcardMerge(sv.race[IDENTITY.race],                     defaults.race)         end
        if defaults.faction      then wildcardMerge(sv.faction[IDENTITY.faction],               defaults.faction)      end
        if defaults.factionrealm then wildcardMerge(sv.factionrealm[IDENTITY.factionrealm],     defaults.factionrealm) end
    end

    -- Build the instance.
    local db = setmetatable({
        _name           = name,
        _defaults       = defaults,
        _sv             = sv,
        _migrations     = {},   -- {[version] = fn}; populated by :RegisterMigration
        _namespaces     = {},   -- {[MAJOR] = subDB}; populated by :RegisterNamespace
        global          = sv.global,
        profile         = sv.profiles[sv.currentProfile],
        char            = sv.char[IDENTITY.char],
        realm           = sv.realm[IDENTITY.realm],
        class           = sv.class[IDENTITY.class],
        race            = sv.race[IDENTITY.race],
        faction         = sv.faction[IDENTITY.faction],
        factionrealm    = sv.factionrealm[IDENTITY.factionrealm],
    }, DBMeta)

    self.instances[name] = db

    -- D3 — register PLAYER_LOGOUT listener for removeDefaults (lazy: only
    -- when at least one DB carries defaults; pure-storage consumers pay
    -- zero cost).
    if defaults then
        Cairn_DB._ensureLogoutListener()
    end

    return db
end


-- ---------------------------------------------------------------------------
-- Migration framework (Decisions 4 + 9)
-- ---------------------------------------------------------------------------
-- :RegisterMigration(version, fn) registers a migration that runs once
-- per addon-version-step. Migrations walk `saved.internalVersion+1 →
-- max(registered version)` in order. A migration that returns the
-- MIGRATION_DEFER sentinel queues for PLAYER_LOGIN re-run (covers cases
-- where the migration needs spec / class / level state not available
-- at lib-load).

function DBMethods:RegisterMigration(version, fn)
    if type(version) ~= "number" or version < 1 or version ~= math.floor(version) then
        error("Cairn-DB :RegisterMigration: version must be a positive integer", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn-DB :RegisterMigration: fn must be a function", 2)
    end
    rawget(self, "_migrations")[version] = fn

    -- Auto-walk pending migrations. Called every time the consumer
    -- registers another migration; the walk is no-op when the current
    -- version is already at the target.
    self:_RunMigrations()
end


-- Internal: walk migrations from sv.internalVersion + 1 upward. Returns
-- normally on completion. Migrations returning MIGRATION_DEFER queue at
-- the lib-scope deferred queue (drained on PLAYER_LOGIN).
--
-- The migration fn receives the DB INSTANCE (not the raw sv root) so
-- consumers can write `db.profile.foo = ...` matching their normal
-- consumer-code mental model. The raw sv is reachable via `rawget(db,
-- "_sv")` if a migration needs to touch lib-internal keys.
function DBMethods:_RunMigrations()
    local sv = rawget(self, "_sv")
    local migrations = rawget(self, "_migrations")
    -- Find max registered version.
    local maxVersion = sv.internalVersion or 0
    for v in pairs(migrations) do
        if v > maxVersion then maxVersion = v end
    end

    local v = (sv.internalVersion or 0) + 1
    while v <= maxVersion do
        local fn = migrations[v]
        if fn then
            local ok, result = pcall(fn, self)
            if not ok then
                geterrorhandler()(result)
                return  -- abort walk on hard error; consumer can retry by re-registering
            end
            if result == Cairn_DB.MIGRATION_DEFER then
                -- Queue for PLAYER_LOGIN drain. Don't bump internalVersion.
                Cairn_DB._deferredMigrations[#Cairn_DB._deferredMigrations + 1] = {
                    db = self, version = v, fn = fn,
                }
                Cairn_DB._ensureLoginListener()
                return  -- pause walk; resume on PLAYER_LOGIN if re-run succeeds
            end
        end
        sv.internalVersion = v
        v = v + 1
    end
end


-- Lazy PLAYER_LOGIN listener for deferred migrations. One frame, lib-scope.
function Cairn_DB._ensureLoginListener()
    if Cairn_DB._loginFrame then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function()
        local queue = Cairn_DB._deferredMigrations
        if not queue or #queue == 0 then return end
        local snapshot = {}
        for i = 1, #queue do snapshot[i] = queue[i] end
        Cairn_DB._deferredMigrations = {}

        for i = 1, #snapshot do
            local entry = snapshot[i]
            local db, version, fn = entry.db, entry.version, entry.fn
            local sv = rawget(db, "_sv")
            local ok, result = pcall(fn, db)
            if not ok then
                geterrorhandler()(result)
            elseif result == Cairn_DB.MIGRATION_DEFER then
                -- Second defer = error loudly. Silent infinite-defer loops
                -- are exactly the failure mode the sentinel exists to prevent.
                geterrorhandler()(("Cairn-DB: migration version %d returned MIGRATION_DEFER twice; "
                    .. "the consumer-supplied migration fn is broken or its required state "
                    .. "still isn't available at PLAYER_LOGIN."):format(version))
            else
                sv.internalVersion = version
                -- Try resuming any later migrations now that this one succeeded.
                db:_RunMigrations()
            end
        end
    end)
    Cairn_DB._loginFrame = frame
end


-- ---------------------------------------------------------------------------
-- Namespace API
-- ---------------------------------------------------------------------------
-- :RegisterNamespace(MAJOR) returns a sub-DB backed by sv.__namespaces[MAJOR].
-- Sub-DB has its own independent buckets (profile / global / etc.) per the
-- 8-bucket partition model. Multiple namespaces per parent DB allowed.
-- Sub-DBs share the parent's migration framework (auto-walk on creation)
-- and identity tables but are otherwise isolated.

function DBMethods:RegisterNamespace(major)
    if type(major) ~= "string" or major == "" then
        error("Cairn-DB :RegisterNamespace: MAJOR must be a non-empty string", 2)
    end
    local existing = rawget(self, "_namespaces")[major]
    if existing then return existing end

    local sv = rawget(self, "_sv")
    sv.__namespaces[major] = sv.__namespaces[major] or {}
    local nssv = sv.__namespaces[major]

    -- Same shape as a top-level sv. No identity-resolution for namespaces —
    -- they share the parent DB's identity captured at IDENTITY load time.
    nssv.global         = nssv.global         or {}
    nssv.profiles       = nssv.profiles       or {}
    nssv.currentProfile = nssv.currentProfile or DEFAULT_PROFILE
    nssv.profiles[nssv.currentProfile] = nssv.profiles[nssv.currentProfile] or {}

    nssv.char         = nssv.char         or {}
    nssv.realm        = nssv.realm        or {}
    nssv.class        = nssv.class        or {}
    nssv.race         = nssv.race         or {}
    nssv.faction      = nssv.faction      or {}
    nssv.factionrealm = nssv.factionrealm or {}
    nssv.char[IDENTITY.char]                 = nssv.char[IDENTITY.char]                 or {}
    nssv.realm[IDENTITY.realm]               = nssv.realm[IDENTITY.realm]               or {}
    nssv.class[IDENTITY.class]               = nssv.class[IDENTITY.class]               or {}
    nssv.race[IDENTITY.race]                 = nssv.race[IDENTITY.race]                 or {}
    nssv.faction[IDENTITY.faction]           = nssv.faction[IDENTITY.faction]           or {}
    nssv.factionrealm[IDENTITY.factionrealm] = nssv.factionrealm[IDENTITY.factionrealm] or {}

    local subDB = setmetatable({
        _name           = major,
        _defaults       = nil,
        _sv             = nssv,
        _migrations     = {},
        _namespaces     = {},
        global          = nssv.global,
        profile         = nssv.profiles[nssv.currentProfile],
        char            = nssv.char[IDENTITY.char],
        realm           = nssv.realm[IDENTITY.realm],
        class           = nssv.class[IDENTITY.class],
        race            = nssv.race[IDENTITY.race],
        faction         = nssv.faction[IDENTITY.faction],
        factionrealm    = nssv.factionrealm[IDENTITY.factionrealm],
        _parent         = self,
    }, DBMeta)

    rawget(self, "_namespaces")[major] = subDB
    return subDB
end


-- Cairn_DB:Get(savedVarName)
function Cairn_DB:Get(name)
    return self.instances[name]
end


-- ---------------------------------------------------------------------------
-- removeDefaults on PLAYER_LOGOUT (MINOR 16)
-- ---------------------------------------------------------------------------
-- Walk the SV data recursively at PLAYER_LOGOUT and strip per-key values
-- that match the consumer's defaults. SV file shrinks; next load re-fills
-- the stripped keys via the wildcard metatable + the normal
-- mergeDefaults pass in :New.
--
-- Blocker semantic: a table-typed default does NOT recurse into the
-- user's value when the user's value is a non-table type. Prevents the
-- "user typed a scalar where the default is a table" foot-gun (e.g.
-- user's `count = 5` won't be stripped because the default is `count =
-- { wrap = "table" }`).
--
-- Wildcard support: walks user keys not covered by explicit defaults,
-- compares against the `["*"]` sub-default (one-level) or `["**"]`
-- (recursive). Same blocker rule applies. Lib-internal keys (those
-- starting with `_`) are skipped — they never came from the consumer's
-- defaults and aren't ours to strip.
--
-- Auto-fire on PLAYER_LOGOUT: lazy listener installed by :New whenever an
-- instance with non-nil defaults is created. One frame, lib-scope, drains
-- once per session.

-- Public-ish hooks for testing. Override in unit tests if you need to
-- intercept the walk without spinning up a real frame.
Cairn_DB._removeDefaultsListenerInstalled = Cairn_DB._removeDefaultsListenerInstalled or false


-- Recursive walk: strip every key in `target` whose value matches the
-- corresponding key in `defaults`. Returns nothing; mutates `target`.
local function removeDefaultsWalk(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end

    -- Pass 1: explicit (non-wildcard) defaults.
    for k, dv in pairs(defaults) do
        if k ~= "*" and k ~= "**" then
            local tv = rawget(target, k)
            if tv ~= nil then
                if type(dv) == "table" then
                    -- Blocker rule: table default + non-table user value =
                    -- don't touch.
                    if type(tv) == "table" then
                        removeDefaultsWalk(tv, dv)
                        if next(tv) == nil then
                            rawset(target, k, nil)
                        end
                    end
                else
                    -- Scalar default: strip if value matches.
                    if tv == dv then
                        rawset(target, k, nil)
                    end
                end
            end
        end
    end

    -- Pass 2: wildcard defaults. Walk user keys NOT covered by an explicit
    -- default and compare against `["*"]` (one-level) or `["**"]`
    -- (recursive). `**` continues recursing with itself at every depth so
    -- a wildcard default applied at depth N also applies at depth N+1.
    local star       = defaults["*"]
    local doubleStar = defaults["**"]
    if star ~= nil or doubleStar ~= nil then
        -- Iterate a snapshot of keys because we'll mutate `target`.
        local keys = {}
        for k in pairs(target) do
            if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
                if defaults[k] == nil then keys[#keys + 1] = k end
            end
        end
        for _, k in ipairs(keys) do
            local tv = rawget(target, k)
            local effective = star
            -- `**` applies even without `*` — wildcard fall-through.
            if effective == nil then effective = doubleStar end
            if type(tv) == "table" and type(effective) == "table" then
                removeDefaultsWalk(tv, effective)
                if doubleStar ~= nil then
                    -- For ** we ALSO recurse with the wildcard at the next
                    -- depth via a synthetic single-wildcard child.
                    removeDefaultsWalk(tv, { ["**"] = doubleStar })
                end
                if next(tv) == nil then
                    rawset(target, k, nil)
                end
            elseif type(effective) ~= "table" then
                -- Scalar wildcard default: strip if user value matches.
                if tv == effective then rawset(target, k, nil) end
            end
            -- (table default + non-table user value: blocker rule; no-op.)
        end
    end
end


-- Per-instance entry point. Walks each bucket against the corresponding
-- defaults sub-table, then every profile in sv.profiles against
-- defaults.profile (defaults are merged into every touched profile by
-- :SetProfile, so removeDefaults must strip across all of them).
function DBMethods:_RemoveDefaults()
    local defaults = rawget(self, "_defaults")
    if type(defaults) ~= "table" then return end
    local sv = rawget(self, "_sv")
    if type(sv) ~= "table" then return end

    if defaults.global and type(sv.global) == "table" then
        removeDefaultsWalk(sv.global, defaults.global)
    end
    if defaults.profile and type(sv.profiles) == "table" then
        for _, profileTbl in pairs(sv.profiles) do
            if type(profileTbl) == "table" then
                removeDefaultsWalk(profileTbl, defaults.profile)
            end
        end
    end
    -- Per-identity buckets only walk the CURRENT identity sub-table — the
    -- defaults were only merged for that identity at :New, so other
    -- identities' subkeys aren't ours to strip.
    if defaults.char and type(sv.char) == "table"
       and type(sv.char[IDENTITY.char]) == "table"
    then
        removeDefaultsWalk(sv.char[IDENTITY.char], defaults.char)
    end
    if defaults.realm and type(sv.realm) == "table"
       and type(sv.realm[IDENTITY.realm]) == "table"
    then
        removeDefaultsWalk(sv.realm[IDENTITY.realm], defaults.realm)
    end
    if defaults.class and type(sv.class) == "table"
       and type(sv.class[IDENTITY.class]) == "table"
    then
        removeDefaultsWalk(sv.class[IDENTITY.class], defaults.class)
    end
    if defaults.race and type(sv.race) == "table"
       and type(sv.race[IDENTITY.race]) == "table"
    then
        removeDefaultsWalk(sv.race[IDENTITY.race], defaults.race)
    end
    if defaults.faction and type(sv.faction) == "table"
       and type(sv.faction[IDENTITY.faction]) == "table"
    then
        removeDefaultsWalk(sv.faction[IDENTITY.faction], defaults.faction)
    end
    if defaults.factionrealm and type(sv.factionrealm) == "table"
       and type(sv.factionrealm[IDENTITY.factionrealm]) == "table"
    then
        removeDefaultsWalk(sv.factionrealm[IDENTITY.factionrealm],
                           defaults.factionrealm)
    end
end


-- Lib-scope walk: iterate every registered DB on PLAYER_LOGOUT and call
-- :_RemoveDefaults on it. pcall'd per-instance so one bad strip doesn't
-- abort the rest of the session-end work.
function Cairn_DB._RunRemoveDefaults()
    for _, db in pairs(Cairn_DB.instances) do
        local ok, err = pcall(db._RemoveDefaults, db)
        if not ok then geterrorhandler()(err) end
    end
end


-- Lazy PLAYER_LOGOUT listener. One frame, lib-scope. Only installed when
-- at least one consumer has a defaults table — addons that don't use
-- defaults pay zero cost.
function Cairn_DB._ensureLogoutListener()
    if Cairn_DB._removeDefaultsListenerInstalled then return end
    Cairn_DB._removeDefaultsListenerInstalled = true
    if type(CreateFrame) ~= "function" then return end  -- non-WoW env

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function()
        Cairn_DB._RunRemoveDefaults()
    end)
    Cairn_DB._logoutFrame = frame
end


-- Expose `_RemoveDefaults` and the walk for testing / introspection.
Cairn_DB._removeDefaultsWalk = removeDefaultsWalk


return Cairn_DB
