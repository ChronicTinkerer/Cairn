-- Cairn-DB smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, New() shape, defaults merge, non-destructive
-- defaults, idempotent New, profile switch, profile defaults on new
-- profiles, Get(), introspection, input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-DB"] = function(report)
    -- 1. Library loaded + public API surface
    local CD = LibStub and LibStub("Cairn-DB-1.0", true)
    report("Cairn-DB is loaded under LibStub", CD ~= nil)
    if not CD then return end

    report("Cairn-DB:New exists",          type(CD.New) == "function")
    report("Cairn-DB:Get exists",          type(CD.Get) == "function")
    report("Cairn-DB.instances is a table", type(CD.instances) == "table")


    -- 2. New() returns an instance with the expected shape
    local svName = "CairnDBSmoke_" .. tostring(time and time() or 0)
    _G[svName] = nil
    CD.instances[svName] = nil

    local db = CD:New(svName, {
        global  = { sharedKey = 1, sharedTable = { a = "alpha" } },
        profile = { perProfileKey = "hello", nested = { foo = 42 } },
    })
    report("New returned a table",                  type(db) == "table")
    report("db._name matches savedVarName",         db._name == svName)
    report("db.global is a table",                  type(db.global) == "table")
    report("db.profile is a table",                 type(db.profile) == "table")
    report("CD.instances[name] == db",              CD.instances[svName] == db)


    -- 3. Defaults merged into both global and profile
    report("defaults.global.sharedKey landed",       db.global.sharedKey == 1,
           ("got " .. tostring(db.global.sharedKey)))
    report("defaults.global.sharedTable nested value landed",
           type(db.global.sharedTable) == "table" and db.global.sharedTable.a == "alpha")
    report("defaults.profile.perProfileKey landed", db.profile.perProfileKey == "hello")
    report("defaults.profile.nested deep value landed",
           type(db.profile.nested) == "table" and db.profile.nested.foo == 42)


    -- 4. Idempotent New(): same name returns same instance
    report("New(same name) returns same instance",  CD:New(svName) == db)
    report("Get(name) returns the instance",        CD:Get(svName) == db)
    report("Get(unknown) returns nil",              CD:Get("CairnDBSmoke_DefinitelyNotRegistered") == nil)


    -- 5. Non-destructive defaults
    db.global.sharedKey = 99
    CD.instances[svName] = nil
    local db2 = CD:New(svName, {
        global  = { sharedKey = 1 },
        profile = { perProfileKey = "hello", nested = { foo = 42 } },
    })
    report("Existing global value preserved across re-New",
           db2.global.sharedKey == 99,
           ("got " .. tostring(db2.global.sharedKey)))
    db = db2


    -- 6. Profile switching
    report("Initial profile is 'Default'",   db:GetProfile() == "Default")

    local oldProfileTable = db.profile
    db:SetProfile("Combat")
    report("SetProfile updates GetProfile",  db:GetProfile() == "Combat")
    report("db.profile points at new profile table", db.profile ~= oldProfileTable)
    report("New profile got the profile defaults",
           db.profile.perProfileKey == "hello",
           ("got " .. tostring(db.profile.perProfileKey)))
    report("New profile's nested defaults landed",
           type(db.profile.nested) == "table" and db.profile.nested.foo == 42)

    db.profile.combatOverride = "true"
    db:SetProfile("Default")
    report("Switching back to Default exposes original profile data",
           db.profile.perProfileKey == "hello" and db.profile.combatOverride == nil)


    -- 7. Persistence: changes to db.global and db.profile reflect in _G[name]
    db.global.persisted = "yes"
    db.profile.alsoPersisted = "yep"
    report("Writes to db.global land in _G[name].global",
           _G[svName].global.persisted == "yes")
    report("Writes to db.profile land in _G[name].profiles[currentProfile]",
           _G[svName].profiles[_G[svName].currentProfile].alsoPersisted == "yep")


    -- 8. Input validation
    local ok1 = pcall(function() return CD:New("")  end)
    local ok2 = pcall(function() return CD:New(nil) end)
    local ok3 = pcall(function() return CD:New(42)  end)
    report("New('')  errors",   not ok1)
    report("New(nil) errors",   not ok2)
    report("New(42)  errors",   not ok3)

    -- MINOR 15 added 6 new partition buckets (char/realm/class/race/faction/
    -- factionrealm), so previously-rejected `realm` now passes. Use a clearly
    -- bogus key for the unknown-defaults assertion.
    local ok4 = pcall(function()
        return CD:New("CairnDBSmoke_BadDefaults_" .. tostring(time and time() or 0),
                      { definitelyBogusKey = { x = 1 } })
    end)
    report("New with unknown defaults key errors", not ok4)

    local ok5 = pcall(function() db:SetProfile("") end)
    report("SetProfile('') errors", not ok5)


    -- =====================================================================
    -- MINOR 15 additions: D1 (8 buckets), D2 (wildcards), D4 (migrations),
    -- D8 (RegisterNamespace), D9 (MIGRATION_DEFER sentinel)
    -- =====================================================================

    -- D1: 8 standard partition buckets
    local svN = "CairnDBSmoke_Buckets_" .. tostring(time and time() or 0)
    _G[svN] = nil
    CD.instances[svN] = nil
    local dbB = CD:New(svN, {
        global       = { gKey = 1 },
        profile      = { pKey = 2 },
        char         = { cKey = 3 },
        realm        = { rKey = 4 },
        class        = { clsKey = 5 },
        race         = { rceKey = 6 },
        faction      = { fKey = 7 },
        factionrealm = { frKey = 8 },
    })
    report("db.global is a table",       type(dbB.global)       == "table")
    report("db.profile is a table",      type(dbB.profile)      == "table")
    report("db.char is a table",         type(dbB.char)         == "table")
    report("db.realm is a table",        type(dbB.realm)        == "table")
    report("db.class is a table",        type(dbB.class)        == "table")
    report("db.race is a table",         type(dbB.race)         == "table")
    report("db.faction is a table",      type(dbB.faction)      == "table")
    report("db.factionrealm is a table", type(dbB.factionrealm) == "table")
    -- Defaults seeded into each bucket
    report("db.char default seeded",   dbB.char.cKey   == 3)
    report("db.realm default seeded",  dbB.realm.rKey  == 4)
    report("db.faction default seeded", dbB.faction.fKey == 7)


    -- D2: wildcard defaults `["*"]` (one-level)
    local svW = "CairnDBSmoke_Wildcards_" .. tostring(time and time() or 0)
    _G[svW] = nil
    CD.instances[svW] = nil
    local dbW = CD:New(svW, {
        profile = {
            characters = {
                ["*"] = { level = 1, xp = 0 },
            },
        },
    })
    -- Reading a missing key auto-creates an entry with the wildcard defaults.
    local alice = dbW.profile.characters["Alice"]
    report("wildcard ['*'] creates new entry on first access",
           type(alice) == "table")
    report("wildcard ['*'] defaults level applied",
           alice.level == 1)
    report("wildcard ['*'] defaults xp applied",
           alice.xp == 0)


    -- D2: recursive wildcard `["**"]`
    local svWR = "CairnDBSmoke_WildcardRecursive_" .. tostring(time and time() or 0)
    _G[svWR] = nil
    CD.instances[svWR] = nil
    local dbWR = CD:New(svWR, {
        profile = {
            zones = {
                ["**"] = { visited = false },
            },
        },
    })
    -- Deep-nested access — every level below `zones` gets the wildcard
    -- defaults recursively.
    local stormwind = dbWR.profile.zones.Stormwind
    report("wildcard ['**'] one level deep",
           stormwind.visited == false)
    local cathedral = stormwind.Cathedral
    report("wildcard ['**'] two levels deep",
           cathedral.visited == false)


    -- D4: migration framework
    local svM = "CairnDBSmoke_Migration_" .. tostring(time and time() or 0)
    _G[svM] = nil
    CD.instances[svM] = nil
    local dbM = CD:New(svM, { profile = {} })

    report("db:RegisterMigration is a function",
           type(dbM.RegisterMigration) == "function")

    local migration1Ran, migration2Ran = false, false
    dbM:RegisterMigration(1, function(db)
        migration1Ran = true
        db.profile.migratedAt1 = true
    end)
    report("Migration 1 ran",                  migration1Ran == true)
    report("Migration 1 mutation visible",     dbM.profile.migratedAt1 == true)
    report("internalVersion bumped to 1",      dbM._sv.internalVersion == 1)

    dbM:RegisterMigration(2, function(db)
        migration2Ran = true
        db.profile.migratedAt2 = true
    end)
    report("Migration 2 ran",                  migration2Ran == true)
    report("internalVersion bumped to 2",      dbM._sv.internalVersion == 2)

    -- Re-running a migration that already ran: don't re-execute.
    migration1Ran = false
    dbM:_RunMigrations()
    report("Already-applied migrations don't re-run",
           migration1Ran == false)


    -- D9: MIGRATION_DEFER sentinel queues without bumping version
    report("CD.MIGRATION_DEFER exists",
           CD.MIGRATION_DEFER ~= nil)

    local svD = "CairnDBSmoke_Defer_" .. tostring(time and time() or 0)
    _G[svD] = nil
    CD.instances[svD] = nil
    local dbD = CD:New(svD, { profile = {} })
    local deferCount = 0
    dbD:RegisterMigration(1, function(db)
        deferCount = deferCount + 1
        return CD.MIGRATION_DEFER
    end)
    report("MIGRATION_DEFER fn ran once at register-time",
           deferCount == 1)
    report("MIGRATION_DEFER doesn't bump internalVersion",
           dbD._sv.internalVersion == 0)
    report("MIGRATION_DEFER appended to deferred queue",
           type(CD._deferredMigrations) == "table"
           and #CD._deferredMigrations >= 1)
    -- Clean up deferred queue for the smoke runner so the PLAYER_LOGIN
    -- listener doesn't error on retry.
    CD._deferredMigrations = {}


    -- D8: :RegisterNamespace
    local svNS = "CairnDBSmoke_Namespace_" .. tostring(time and time() or 0)
    _G[svNS] = nil
    CD.instances[svNS] = nil
    local dbNS = CD:New(svNS, { profile = {} })

    report("db:RegisterNamespace is a function",
           type(dbNS.RegisterNamespace) == "function")

    local sub = dbNS:RegisterNamespace("TestNamespace-1.0")
    report("RegisterNamespace returns a sub-DB",
           type(sub) == "table")
    report("Sub-DB has its own .profile (distinct from parent)",
           type(sub.profile) == "table" and sub.profile ~= dbNS.profile)
    report("Sub-DB has its own .global",
           type(sub.global) == "table" and sub.global ~= dbNS.global)
    report("Sub-DB has 8 buckets like parent",
           type(sub.char) == "table" and type(sub.faction) == "table")
    report("Sub-DB stored in __namespaces[MAJOR]",
           dbNS._sv.__namespaces["TestNamespace-1.0"] ~= nil)
    -- Re-register returns same instance
    local sub2 = dbNS:RegisterNamespace("TestNamespace-1.0")
    report("RegisterNamespace is idempotent",
           sub2 == sub)
    -- Different MAJOR returns different sub-DB
    local sub3 = dbNS:RegisterNamespace("OtherNamespace-1.0")
    report("Different MAJOR returns different sub-DB",
           sub3 ~= sub)

    -- Bad input
    report("RegisterNamespace with empty MAJOR errors",
           not pcall(function() dbNS:RegisterNamespace("") end))


    -- =====================================================================
    -- MINOR 16 — D3 removeDefaults on PLAYER_LOGOUT
    -- =====================================================================

    report("CD._removeDefaultsWalk is a function",
           type(CD._removeDefaultsWalk) == "function")
    report("CD._RunRemoveDefaults is a function",
           type(CD._RunRemoveDefaults) == "function")

    -- Scenario 1: scalar key matching default → stripped
    local svR1 = "CairnDBSmoke_RemDef1_" .. tostring(time and time() or 0)
    _G[svR1] = nil; CD.instances[svR1] = nil
    local dbR1 = CD:New(svR1, { profile = { scale = 1.0, color = "blue" } })
    -- Both keys match defaults at this point
    dbR1:_RemoveDefaults()
    report("D3 scalar matching default is stripped",
           rawget(dbR1.profile, "scale") == nil)
    report("D3 second scalar matching default is stripped",
           rawget(dbR1.profile, "color") == nil)
    -- After strip, reads return nil since defaults metatable is wildcard-only
    -- (no metatable __index for non-wildcard defaults). So consumer would
    -- need to re-merge on next load. The seed in :New does that via
    -- wildcardMerge, so test by directly poking the values back to non-
    -- default and re-running.
    rawset(dbR1.profile, "scale", 1.5)  -- non-default value
    rawset(dbR1.profile, "color", "red")
    dbR1:_RemoveDefaults()
    report("D3 scalar NOT matching default is kept",
           rawget(dbR1.profile, "scale") == 1.5)
    report("D3 second scalar NOT matching default is kept",
           rawget(dbR1.profile, "color") == "red")


    -- Scenario 2: table default + non-table user value (blocker rule)
    local svR2 = "CairnDBSmoke_RemDef2_" .. tostring(time and time() or 0)
    _G[svR2] = nil; CD.instances[svR2] = nil
    local dbR2 = CD:New(svR2, { profile = { meta = { wrap = "table" } } })
    -- Force a non-table user value where the default is a table
    rawset(dbR2.profile, "meta", 5)  -- scalar where default is table
    dbR2:_RemoveDefaults()
    report("D3 blocker: table-default + scalar-user value is preserved",
           rawget(dbR2.profile, "meta") == 5)


    -- Scenario 3: nested table — partial match strips matching keys,
    --             non-matching keys preserved
    local svR3 = "CairnDBSmoke_RemDef3_" .. tostring(time and time() or 0)
    _G[svR3] = nil; CD.instances[svR3] = nil
    local dbR3 = CD:New(svR3, { profile = {
        ui = { scale = 1.0, alpha = 1.0, position = "top" } } })
    -- ui.scale matches default, ui.alpha is user-mutated, ui.position
    -- doesn't exist anymore
    rawset(dbR3.profile.ui, "alpha", 0.5)  -- non-default
    rawset(dbR3.profile.ui, "position", nil)
    dbR3:_RemoveDefaults()
    report("D3 nested: matching scalar stripped",
           rawget(dbR3.profile.ui, "scale") == nil)
    report("D3 nested: non-matching scalar kept",
           rawget(dbR3.profile.ui, "alpha") == 0.5)


    -- Scenario 4: profiles walk — every profile gets stripped against
    --             defaults.profile, not just current
    local svR4 = "CairnDBSmoke_RemDef4_" .. tostring(time and time() or 0)
    _G[svR4] = nil; CD.instances[svR4] = nil
    local dbR4 = CD:New(svR4, { profile = { value = 42 } })
    dbR4:SetProfile("Alt")
    rawset(dbR4.profile, "value", 42)  -- matches default in Alt profile too
    dbR4:SetProfile("Default")
    rawset(dbR4.profile, "value", 42)  -- matches default in Default
    dbR4:_RemoveDefaults()
    -- Both profiles should have `value` stripped
    local sv = rawget(dbR4, "_sv")
    report("D3 walks all profiles: Default profile stripped",
           rawget(sv.profiles.Default, "value") == nil)
    report("D3 walks all profiles: Alt profile stripped",
           rawget(sv.profiles.Alt, "value") == nil)


    -- Scenario 5: per-identity bucket (char) is walked
    local svR5 = "CairnDBSmoke_RemDef5_" .. tostring(time and time() or 0)
    _G[svR5] = nil; CD.instances[svR5] = nil
    local dbR5 = CD:New(svR5, { char = { hello = "world" } })
    rawset(dbR5.char, "hello", "world")  -- matches default
    rawset(dbR5.char, "extra", "value")  -- not in defaults; left alone
    dbR5:_RemoveDefaults()
    report("D3 per-identity char bucket: matching scalar stripped",
           rawget(dbR5.char, "hello") == nil)
    report("D3 per-identity char bucket: non-default key untouched",
           rawget(dbR5.char, "extra") == "value")


    -- Scenario 6: wildcard defaults — * sub-default
    local svR6 = "CairnDBSmoke_RemDef6_" .. tostring(time and time() or 0)
    _G[svR6] = nil; CD.instances[svR6] = nil
    local dbR6 = CD:New(svR6, { profile = {
        characters = { ["*"] = { level = 1, xp = 0 } } } })
    -- Materialize two entries via wildcard reads
    local _ = dbR6.profile.characters["Hero1"].level  -- matches default
    rawset(dbR6.profile.characters.Hero1, "xp", 0)    -- matches default
    rawset(dbR6.profile.characters, "Hero2", { level = 10, xp = 0 })  -- partial mismatch
    dbR6:_RemoveDefaults()
    -- Hero1 had both fields at default → entirely stripped
    report("D3 wildcard *: fully-default entry stripped",
           rawget(dbR6.profile.characters, "Hero1") == nil)
    -- Hero2 had level != default; level kept, xp (matching) stripped
    local h2 = rawget(dbR6.profile.characters, "Hero2")
    report("D3 wildcard *: partial-default entry retains diverged key",
           type(h2) == "table" and rawget(h2, "level") == 10)
    report("D3 wildcard *: partial-default entry strips matching key",
           type(h2) == "table" and rawget(h2, "xp") == nil)


    -- Scenario 7: PLAYER_LOGOUT listener install gated by defaults presence
    report("D3 logout listener install flag is bool",
           type(CD._removeDefaultsListenerInstalled) == "boolean")


    -- Cleanup
    CD.instances[svName] = nil
    _G[svName] = nil
    CD.instances[svN]  = nil; _G[svN]  = nil
    CD.instances[svW]  = nil; _G[svW]  = nil
    CD.instances[svWR] = nil; _G[svWR] = nil
    CD.instances[svM]  = nil; _G[svM]  = nil
    CD.instances[svD]  = nil; _G[svD]  = nil
    CD.instances[svNS] = nil; _G[svNS] = nil
    CD.instances[svR1] = nil; _G[svR1] = nil
    CD.instances[svR2] = nil; _G[svR2] = nil
    CD.instances[svR3] = nil; _G[svR3] = nil
    CD.instances[svR4] = nil; _G[svR4] = nil
    CD.instances[svR5] = nil; _G[svR5] = nil
    CD.instances[svR6] = nil; _G[svR6] = nil
end
