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


    -- =====================================================================
    -- Cluster A additions (locked 2026-05-12) — disableif, tags, phraseId,
    -- :GetWidgetsByType, :OnDisableStateChanged
    -- =====================================================================

    -- :GetWidgetsByType returns matching schema entries
    report("GetWidgetsByType is a function",
           type(s.GetWidgetsByType) == "function")

    local toggles = s:GetWidgetsByType("toggle")
    report("GetWidgetsByType('toggle') returns a table",
           type(toggles) == "table")
    report("GetWidgetsByType('toggle') has one entry (enabled)",
           #toggles == 1 and toggles[1].entry.key == "enabled")

    local headers = s:GetWidgetsByType("header")
    report("GetWidgetsByType('header') has one entry (header1)",
           #headers == 1 and headers[1].entry.key == "header1")

    local sliders = s:GetWidgetsByType("range")
    report("GetWidgetsByType('range') has one entry (scale)",
           #sliders == 1 and sliders[1].entry.key == "scale")

    local missing = s:GetWidgetsByType("nonexistent_kind")
    report("GetWidgetsByType('nonexistent_kind') returns empty array",
           type(missing) == "table" and #missing == 0)


    -- Schema validation rejects bad Cluster-A field types
    local SV2 = SV .. "_ClusterA"
    _G[SV2] = nil
    CDB.instances[SV2] = nil
    local db2 = CDB:New(SV2, { profile = {} })

    report("disableif must be function (string rejected)",
           not pcall(function()
               CS:New("ClusterA_BadDisableif_" .. stamp, db2, {
                   { key = "t", type = "toggle", default = true,
                     label = "t", disableif = "not a function" },
               })
           end))

    report("disabled must be bool (string rejected)",
           not pcall(function()
               CS:New("ClusterA_BadDisabled_" .. stamp, db2, {
                   { key = "t", type = "toggle", default = true,
                     label = "t", disabled = "not a bool" },
               })
           end))

    report("tags must be a table (string rejected)",
           not pcall(function()
               CS:New("ClusterA_BadTags1_" .. stamp, db2, {
                   { key = "t", type = "toggle", default = true,
                     label = "t", tags = "not a table" },
               })
           end))

    report("tags must contain only strings (numeric tag rejected)",
           not pcall(function()
               CS:New("ClusterA_BadTags2_" .. stamp, db2, {
                   { key = "t", type = "toggle", default = true,
                     label = "t", tags = { "a", 42, "b" } },
               })
           end))

    report("namePhraseId must be string (number rejected)",
           not pcall(function()
               CS:New("ClusterA_BadPhrase_" .. stamp, db2, {
                   { key = "t", type = "toggle", default = true,
                     label = "t", namePhraseId = 42 },
               })
           end))


    -- disableif: build a schema where one toggle depends on another, and
    -- verify the disable state transitions correctly + the change-listener
    -- fires.
    local SV3 = SV .. "_DisableIf"
    _G[SV3] = nil
    CDB.instances[SV3] = nil
    local db3 = CDB:New(SV3, { profile = {} })

    local seenTransitions = {}
    local sd = CS:New("ClusterA_DisableIf_" .. stamp, db3, {
        { key = "master",  type = "toggle", default = true,  label = "Master" },
        { key = "slave",   type = "toggle", default = false, label = "Slave",
          disableif = function(get) return not get("master") end },
        { key = "always",  type = "toggle", default = false, label = "Always Off",
          disableif = function() return true end },
    })

    local unsub = sd:OnDisableStateChanged(function(key, disabled)
        seenTransitions[#seenTransitions + 1] = { key = key, disabled = disabled }
    end)

    -- Initial state: master=true so slave's disableif returns false (NOT disabled).
    -- "always" is unconditionally true (disabled).
    -- The initial refreshDisableIf in :New fired transitions; those land in
    -- seenTransitions only for entries that transitioned from the "not-yet-
    -- seen" prior state — which is nil for both. So both registered listeners
    -- saw the initial transition.

    -- Flip master off → slave should transition to disabled=true.
    sd:Set("master", false)

    local slaveTrans
    for _, t in ipairs(seenTransitions) do
        if t.key == "slave" then slaveTrans = t end
    end
    report("disableif change-listener fired for slave on master flip",
           slaveTrans ~= nil and slaveTrans.disabled == true,
           ("got " .. tostring(slaveTrans and slaveTrans.disabled)))

    -- Flip master back on → slave should transition to disabled=false.
    seenTransitions = {}
    sd:Set("master", true)
    local slaveReenable
    for _, t in ipairs(seenTransitions) do
        if t.key == "slave" then slaveReenable = t end
    end
    report("disableif change-listener fired re-enable for slave",
           slaveReenable ~= nil and slaveReenable.disabled == false,
           ("got " .. tostring(slaveReenable and slaveReenable.disabled)))

    -- Unsub stops further notifications.
    unsub()
    seenTransitions = {}
    sd:Set("master", false)
    report("OnDisableStateChanged unsub stops further fires",
           #seenTransitions == 0)


    -- =====================================================================
    -- MINOR 16: Cluster E partial (D27 + D33 + D34 + D35 + D38)
    -- =====================================================================

    -- D27: control-type registry exposed publicly
    report("CS.controlTypes is a table",
           type(CS.controlTypes) == "table")
    report("controlTypes.toggle exists",
           type(CS.controlTypes.toggle) == "table")
    report("controlTypes.header has skipDefault = true",
           CS.controlTypes.header.skipDefault == true)
    report("controlTypes.text has storageOnly = true",
           CS.controlTypes.text.storageOnly == true)


    -- D34: RegisterControl extension point
    report("CS:RegisterControl is a function",
           type(CS.RegisterControl) == "function")
    if type(CS.RegisterControl) == "function" then
        CS:RegisterControl("custom_kind_" .. stamp, { storageOnly = true })
        report("RegisterControl adds entry to controlTypes",
               CS.controlTypes["custom_kind_" .. stamp] ~= nil)
        -- After registration, the schema validator accepts the new kind.
        local SVR = "CairnSettingsSmoke_RegCtl_" .. stamp
        _G[SVR] = nil; CDB.instances[SVR] = nil
        local dbR = CDB:New(SVR, { profile = {} })
        local sR = CS:New("RegCtl_" .. stamp, dbR, {
            { key = "x", type = "custom_kind_" .. stamp, label = "X",
              default = "hello" },
        })
        report("RegisterControl-defined kind accepted by validator",
               type(sR) == "table")
        -- Cleanup
        CDB.instances[SVR] = nil; _G[SVR] = nil
        CS.controlTypes["custom_kind_" .. stamp] = nil

        report("RegisterControl('', spec) errors",
               not pcall(function() CS:RegisterControl("", {}) end))
        report("RegisterControl('x', 'not-a-table') errors",
               not pcall(function() CS:RegisterControl("x", "notatable") end))
    end


    -- D33: ModifiedClickOptions helper
    report("CS:ModifiedClickOptions is a function",
           type(CS.ModifiedClickOptions) == "function")
    if type(CS.ModifiedClickOptions) == "function" then
        local opts1 = CS:ModifiedClickOptions(false)
        report("ModifiedClickOptions(false) includes NONE",
               opts1.NONE ~= nil and opts1.ALT ~= nil
               and opts1.CTRL ~= nil and opts1.SHIFT ~= nil)
        local opts2 = CS:ModifiedClickOptions(true)
        report("ModifiedClickOptions(true) excludes NONE",
               opts2.NONE == nil and opts2.ALT ~= nil)
    end


    -- D35: runtime predicates validation (isVisible / canSearch / newFeature)
    local SVP = "CairnSettingsSmoke_Predicates_" .. stamp
    _G[SVP] = nil; CDB.instances[SVP] = nil
    local dbP = CDB:New(SVP, { profile = {} })

    report("isVisible function accepted",
           type(CS:New("Pred1_" .. stamp, dbP, {
               { key = "x", type = "toggle", label = "X", default = true,
                 isVisible = function() return true end },
           })) == "table")
    report("canSearch bool accepted",
           type(CS:New("Pred2_" .. stamp, dbP, {
               { key = "x", type = "toggle", label = "X", default = true,
                 canSearch = false },
           })) == "table")
    report("newFeature function accepted",
           type(CS:New("Pred3_" .. stamp, dbP, {
               { key = "x", type = "toggle", label = "X", default = true,
                 newFeature = function() return true end },
           })) == "table")
    report("isVisible non-function rejected",
           not pcall(function() CS:New("Pred4_" .. stamp, dbP, {
               { key = "x", type = "toggle", label = "X", default = true,
                 isVisible = "notafunc" },
           }) end))
    report("canSearch non-bool-or-fn rejected",
           not pcall(function() CS:New("Pred5_" .. stamp, dbP, {
               { key = "x", type = "toggle", label = "X", default = true,
                 canSearch = "notabool" },
           }) end))
    CDB.instances[SVP] = nil; _G[SVP] = nil


    -- D38: dual-keyed registry + :OpenToCategory
    report("CS.registeredCategories is a table",
           type(CS.registeredCategories) == "table")
    report("CS:OpenToCategory is a function",
           type(CS.OpenToCategory) == "function")
    -- The existing settings instance `s` was registered at the top of this
    -- smoke against `addonName` — verify it's in the registry.
    -- Note: `s` was created with addonName == the smoke's `addonName` var
    -- (the literal string used earlier in the smoke). Look it up via the
    -- internal _addonName field.
    if type(CS.OpenToCategory) == "function" and s and s._addonName then
        report("registeredCategories has entry for the smoke addon",
               CS.registeredCategories[s._addonName] == s)

        -- :OpenToCategory with unknown name returns false
        local ok = CS:OpenToCategory("DefinitelyNotRegistered_" .. stamp)
        report(":OpenToCategory unknown name returns false",
               ok == false)

        report(":OpenToCategory('') errors",
               not pcall(function() CS:OpenToCategory("") end))
    end


    -- =====================================================================
    -- MINOR 17: Cluster E partial 2 (D29 sub-settings + D30 requireArguments
    --                                + D37 layout dispatch)
    -- =====================================================================

    -- D30: requireArguments declarative shape validation. controlTypes
    -- ships with requireArguments for `dropdown` (choices = "table") and
    -- `range` (optional numeric min/max/step). Consumer-registered types
    -- gain the same validation path with zero special-casing.
    report("controlTypes.dropdown has requireArguments",
           type(CS.controlTypes.dropdown.requireArguments) == "table")
    report("controlTypes.dropdown requires choices: 'table'",
           CS.controlTypes.dropdown.requireArguments.choices == "table")
    report("controlTypes.range has requireArguments (optional)",
           type(CS.controlTypes.range.requireArguments) == "table"
           and type(CS.controlTypes.range.requireArguments.min) == "table"
           and CS.controlTypes.range.requireArguments.min.optional == true)

    -- dropdown without choices fails the declarative validator
    local SVD = "CairnSettingsSmoke_D30_" .. stamp
    _G[SVD] = nil; CDB.instances[SVD] = nil
    local dbD = CDB:New(SVD, { profile = {} })
    report("dropdown missing choices rejected (D30)",
           not pcall(function() CS:New("D30Drop_" .. stamp, dbD, {
               { key = "x", type = "dropdown", label = "X", default = "a" },
           }) end))
    -- range with wrong-type min rejected
    report("range with string min rejected (D30)",
           not pcall(function() CS:New("D30Range_" .. stamp, dbD, {
               { key = "x", type = "range", label = "X", default = 0.5,
                 min = "zero", max = 1.0, step = 0.1 },
           }) end))
    -- range without min/max/step is accepted (all optional)
    report("range with no min/max/step accepted",
           type(CS:New("D30RangeOK_" .. stamp, dbD, {
               { key = "x", type = "range", label = "X", default = 0.5 },
           })) == "table")
    -- Consumer-registered type with requireArguments validates by the same path
    CS:RegisterControl("my_custom_" .. stamp, {
        storageOnly = true,
        requireArguments = {
            mandatoryField = "string",
            optionalField  = { type = "number", optional = true },
            predicateField = function(value, entry)
                if value ~= nil and value < 0 then
                    return false, "must be non-negative"
                end
                return true
            end,
        },
    })
    report("consumer-registered type accepts valid schema (D30)",
           type(CS:New("D30Cust1_" .. stamp, dbD, {
               { key = "x", type = "my_custom_" .. stamp, label = "X",
                 default = "v", mandatoryField = "hello" },
           })) == "table")
    report("consumer-registered type rejects missing required field (D30)",
           not pcall(function() CS:New("D30Cust2_" .. stamp, dbD, {
               { key = "x", type = "my_custom_" .. stamp, label = "X",
                 default = "v" },
           }) end))
    report("consumer-registered type rejects predicate failure (D30)",
           not pcall(function() CS:New("D30Cust3_" .. stamp, dbD, {
               { key = "x", type = "my_custom_" .. stamp, label = "X",
                 default = "v", mandatoryField = "hi", predicateField = -1 },
           }) end))
    CS.controlTypes["my_custom_" .. stamp] = nil
    CDB.instances[SVD] = nil; _G[SVD] = nil


    -- D29: sub-settings (visually nested children with parent-lock).
    local SVS = "CairnSettingsSmoke_D29_" .. stamp
    _G[SVS] = nil; CDB.instances[SVS] = nil
    local dbS = CDB:New(SVS, { profile = {} })
    local sS = CS:New("D29_" .. stamp, dbS, {
        { key = "parentToggle", type = "toggle", label = "Parent",
          default = true,
          subSettings = {
              { key = "childA", type = "range", label = "Child A",
                min = 0, max = 1, step = 0.1, default = 0.5 },
              { key = "childB", type = "toggle", label = "Child B",
                default = false },
          } },
    })
    report("schema with subSettings accepted (D29)", type(sS) == "table")
    report("parent default seeded (D29)", dbS.profile.parentToggle == true)
    report("subSettings child default seeded (D29)", dbS.profile.childA == 0.5)
    report("subSettings second child seeded (D29)", dbS.profile.childB == false)
    -- byKey flattening: children accessible via :Get
    report("subSettings child reachable via :Get (D29)",
           sS:Get("childA") == 0.5)
    sS:Set("childA", 0.7)
    report("subSettings child round-trip via :Set (D29)",
           sS:Get("childA") == 0.7)
    -- subSettings rejection paths
    report("subSettings non-array rejected (D29)",
           not pcall(function() CS:New("D29Bad1_" .. stamp, dbS, {
               { key = "p", type = "toggle", label = "P", default = true,
                 subSettings = "notatable" },
           }) end))
    report("subSettings child missing key rejected (D29)",
           not pcall(function() CS:New("D29Bad2_" .. stamp, dbS, {
               { key = "p2", type = "toggle", label = "P", default = true,
                 subSettings = { { type = "toggle", label = "X", default = true } } },
           }) end))
    report("subSettings child duplicate key rejected (D29)",
           not pcall(function() CS:New("D29Bad3_" .. stamp, dbS, {
               { key = "dupkey", type = "toggle", label = "P", default = true,
                 subSettings = { { key = "dupkey", type = "toggle",
                                   label = "C", default = false } } },
           }) end))
    report("subSettingsModifiable non-function rejected (D29)",
           not pcall(function() CS:New("D29Bad4_" .. stamp, dbS, {
               { key = "p3", type = "toggle", label = "P", default = true,
                 subSettingsModifiable = "notafn",
                 subSettings = { { key = "c3", type = "toggle",
                                   label = "C", default = false } } },
           }) end))
    CDB.instances[SVS] = nil; _G[SVS] = nil


    -- D37: layout dispatch (canvas vs vertical)
    local SVL = "CairnSettingsSmoke_D37_" .. stamp
    _G[SVL] = nil; CDB.instances[SVL] = nil
    local dbL = CDB:New(SVL, { profile = {} })
    -- Default layout = vertical
    local sV = CS:New("D37Vert_" .. stamp, dbL, {
        { key = "x", type = "toggle", label = "X", default = true },
    })
    report("default layout is vertical (D37)",
           sV._layoutKind == "vertical")
    -- Explicit vertical
    local sV2 = CS:New("D37VertEx_" .. stamp, dbL, {
        { key = "y", type = "toggle", label = "Y", default = true },
    }, { layout = "vertical" })
    report("explicit layout='vertical' accepted (D37)",
           sV2._layoutKind == "vertical")
    -- Canvas without frame falls back to vertical with a warning
    local sC = CS:New("D37Canvas_" .. stamp, dbL, {
        { key = "z", type = "toggle", label = "Z", default = true },
    }, { layout = "canvas" })
    report("layout='canvas' missing frame falls back to vertical (D37)",
           sC._layoutKind == "vertical")
    -- opts non-table rejected
    report("opts non-table rejected (D37)",
           not pcall(function() CS:New("D37Bad1_" .. stamp, dbL, {
               { key = "x", type = "toggle", label = "X", default = true },
           }, "notatable") end))
    -- Bad layout kind rejected
    report("opts.layout invalid value rejected (D37)",
           not pcall(function() CS:New("D37Bad2_" .. stamp, dbL, {
               { key = "x", type = "toggle", label = "X", default = true },
           }, { layout = "weird" }) end))
    CDB.instances[SVL] = nil; _G[SVL] = nil


    -- Cleanup
    CDB.instances[SV]  = nil; _G[SV]  = nil
    CDB.instances[SV2] = nil; _G[SV2] = nil
    CDB.instances[SV3] = nil; _G[SV3] = nil
end
