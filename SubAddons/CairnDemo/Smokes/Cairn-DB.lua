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

    local ok4 = pcall(function()
        return CD:New("CairnDBSmoke_BadDefaults_" .. tostring(time and time() or 0),
                      { realm = { x = 1 } })
    end)
    report("New with unknown defaults key errors", not ok4)

    local ok5 = pcall(function() db:SetProfile("") end)
    report("SetProfile('') errors", not ok5)


    -- Cleanup
    CD.instances[svName] = nil
    _G[svName] = nil
end
