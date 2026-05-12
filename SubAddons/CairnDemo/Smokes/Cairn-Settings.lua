-- Cairn-Settings smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, schema validation, default seeding into
-- db.profile, Get/Set round-trip, onChange handler with (new, old),
-- subscribers via OnChange + unsub closure, storage-only types (text/
-- color/keybind), color positional default normalization, Blizzard
-- category registered, instance tracking, schema-validation rejections,
-- OnChange input validation.
--
-- Uses Cairn-DB to back the schema, mirroring real consumer usage.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Settings"] = function(report)
    -- 1. Library + public API
    local CS = LibStub and LibStub("Cairn-Settings-1.0", true)
    report("Cairn-Settings is loaded under LibStub", CS ~= nil)
    if not CS then return end

    report("CS:New exists",          type(CS.New) == "function")
    report("CS.instances is a table", type(CS.instances) == "table")

    local CDB = LibStub("Cairn-DB-1.0", true)
    report("Cairn-DB is loaded (required for Settings)", CDB ~= nil)
    if not CDB then return end


    -- 2. Schema validation: good schemas accepted
    local stamp = tostring(time and time() or 0)
    local SV = "CairnSettingsSmokeDB_" .. stamp
    _G[SV] = nil
    CDB.instances[SV] = nil

    local db = CDB:New(SV, { profile = {} })

    local goodSchema = {
        { key = "header1", type = "header",   label = "Display" },
        { key = "scale",   type = "range",    label = "Scale",
          min = 0.5, max = 2.0, step = 0.1, default = 1.0,
          tooltip = "Frame size" },
        { key = "enabled", type = "toggle",   label = "Enable",
          default = true },
        { key = "theme",   type = "dropdown", label = "Theme",
          default = "dark",
          choices = { dark = "Dark", light = "Light" } },
        { key = "label",   type = "text",     label = "Custom Label",
          default = "Hello" },
        { key = "color1",  type = "color",    label = "Bar color",
          default = { r = 0.5, g = 0.5, b = 1.0 } },
        { key = "color2",  type = "color",    label = "Other color",
          default = { 0.8, 0.2, 0.2 } },
        { key = "bind",    type = "keybind",  label = "Hotkey",
          default = "CTRL-SHIFT-X" },
    }

    local AN = "CairnSettingsSmoke_" .. stamp
    local s = CS:New(AN, db, goodSchema)
    report("New returned an instance",            type(s) == "table")
    report("instance is tracked in CS.instances", CS.instances[s] == AN)


    -- 3. Defaults seeded into db.profile
    report("scale default seeded into db.profile", db.profile.scale == 1.0)
    report("enabled default seeded",               db.profile.enabled == true)
    report("theme default seeded",                 db.profile.theme == "dark")
    report("label (text) default seeded",          db.profile.label == "Hello")
    report("color1 default seeded",
           type(db.profile.color1) == "table" and db.profile.color1.r == 0.5)
    report("bind (keybind) default seeded",        db.profile.bind == "CTRL-SHIFT-X")
    report("header has no value seeded",           db.profile.header1 == nil)


    -- 4. Color positional default normalized to named
    local c2 = db.profile.color2
    report("Positional color default normalized to named",
           type(c2) == "table" and c2.r == 0.8 and c2.g == 0.2 and c2.b == 0.2)


    -- 5. Get / Set round-trip
    report("Get returns current value",   s:Get("scale") == 1.0)
    s:Set("scale", 1.5)
    report("Set persisted to db.profile", db.profile.scale == 1.5)
    report("Get reflects the new value",  s:Get("scale") == 1.5)


    -- 6. onChange handler fires with (newValue, oldValue)
    local seenNew, seenOld = nil, nil
    local s2 = CS:New(AN .. "_hooked", db, {
        { key = "scale2", type = "range", label = "Scale 2",
          min = 0, max = 10, step = 1, default = 5,
          onChange = function(new, old) seenNew, seenOld = new, old end },
    })
    s2:Set("scale2", 7)
    report("onChange fires with (newValue, oldValue)",
           seenNew == 7 and seenOld == 5)


    -- 7. Subscribers fire; unsub closure stops them
    local subFireCount = 0
    local unsub = s:OnChange("scale", function() subFireCount = subFireCount + 1 end)

    s:Set("scale", 2.0)
    report("Subscriber fired on Set",         subFireCount == 1)

    s:Set("scale", 1.0)
    report("Subscriber fired on second Set",  subFireCount == 2)

    unsub()
    s:Set("scale", 1.5)
    report("Subscriber NOT fired after unsub", subFireCount == 2)

    local noOpCount = 0
    local unsub2 = s:OnChange("scale", function() noOpCount = noOpCount + 1 end)
    s:Set("scale", 1.5)
    report("Set to same value is a no-op (subscriber not called)", noOpCount == 0)
    unsub2()


    -- 8. Storage-only types work
    s:Set("label", "Updated")
    report("text type Set persists",  s:Get("label") == "Updated")

    s:Set("color1", { r = 1.0, g = 0.0, b = 0.0 })
    report("color type Set persists", s:Get("color1").r == 1.0)

    s:Set("bind", "ALT-Q")
    report("keybind type Set persists", s:Get("bind") == "ALT-Q")


    -- 9. Blizzard category registered (real-mode only)
    if Settings and Settings.RegisterAddOnCategory then
        report("Real mode: GetCategoryID returns non-nil", s:GetCategoryID() ~= nil)
        report("Real mode: GetCategory returns a category object",
               type(s:GetCategory()) == "table")
    else
        report("Stub mode: GetCategoryID is nil", s:GetCategoryID() == nil)
    end


    -- 10. Schema validation: bad shapes error
    report("New with non-string addonName errors",
           not pcall(function() CS:New(42, db, {}) end))
    report("New with db missing .profile errors",
           not pcall(function() CS:New("X" .. stamp, {}, {}) end))
    report("Schema entry without 'key' errors",
           not pcall(function() CS:New("X1_" .. stamp, db, {
               { type = "toggle", label = "X", default = true }
           }) end))
    report("Schema entry with unsupported type errors",
           not pcall(function() CS:New("X2_" .. stamp, db, {
               { key = "x", type = "weird", label = "X", default = true }
           }) end))
    report("Schema entry missing 'default' (non-header) errors",
           not pcall(function() CS:New("X3_" .. stamp, db, {
               { key = "x", type = "toggle", label = "X" }
           }) end))
    report("Duplicate key errors",
           not pcall(function() CS:New("X4_" .. stamp, db, {
               { key = "x", type = "toggle", label = "X", default = true },
               { key = "x", type = "range",  label = "Y", default = 0 },
           }) end))
    report("Dropdown without choices table errors",
           not pcall(function() CS:New("X5_" .. stamp, db, {
               { key = "x", type = "dropdown", label = "X", default = "a" }
           }) end))
    report("text entry with non-string default errors",
           not pcall(function() CS:New("X6_" .. stamp, db, {
               { key = "x", type = "text", label = "X", default = 42 }
           }) end))
    report("color entry with non-table default errors",
           not pcall(function() CS:New("X7_" .. stamp, db, {
               { key = "x", type = "color", label = "X", default = "red" }
           }) end))


    -- 11. OnChange input validation
    report("OnChange with non-string key errors",
           not pcall(function() s:OnChange(42, function() end) end))
    report("OnChange with non-function fn errors",
           not pcall(function() s:OnChange("scale", "not-a-func") end))


    -- Cleanup
    CDB.instances[SV] = nil
    _G[SV] = nil
end
