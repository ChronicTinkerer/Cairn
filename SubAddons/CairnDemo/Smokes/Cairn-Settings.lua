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
    report("schema with subSettings accepted", type(sS) == "table")
    report("parent default seeded", dbS.profile.parentToggle == true)
    report("subSettings child default seeded", dbS.profile.childA == 0.5)
    report("subSettings second child seeded", dbS.profile.childB == false)
    -- byKey flattening: children accessible via :Get
    report("subSettings child reachable via :Get",
           sS:Get("childA") == 0.5)
    sS:Set("childA", 0.7)
    report("subSettings child round-trip via :Set",
           sS:Get("childA") == 0.7)
    -- subSettings rejection paths
    report("subSettings non-array rejected",
           not pcall(function() CS:New("D29Bad1_" .. stamp, dbS, {
               { key = "p", type = "toggle", label = "P", default = true,
                 subSettings = "notatable" },
           }) end))
    report("subSettings child missing key rejected",
           not pcall(function() CS:New("D29Bad2_" .. stamp, dbS, {
               { key = "p2", type = "toggle", label = "P", default = true,
                 subSettings = { { type = "toggle", label = "X", default = true } } },
           }) end))
    report("subSettings child duplicate key rejected",
           not pcall(function() CS:New("D29Bad3_" .. stamp, dbS, {
               { key = "dupkey", type = "toggle", label = "P", default = true,
                 subSettings = { { key = "dupkey", type = "toggle",
                                   label = "C", default = false } } },
           }) end))
    report("subSettingsModifiable non-function rejected",
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


    -- =====================================================================
    -- MINOR 18 — D31 storage backends (addon / cvar / proxy)
    -- =====================================================================

    -- Proxy backend: consumer-supplied get/set closures bridge to existing state
    local SVPR = "CairnSettingsSmoke_D31p_" .. stamp
    _G[SVPR] = nil; CDB.instances[SVPR] = nil
    local dbPR = CDB:New(SVPR, { profile = {} })

    local externalState = { count = 5 }
    local sP = CS:New("D31proxy_" .. stamp, dbPR, {
        { key = "count", type = "range",
          label = "Count",
          min = 0, max = 100, step = 1, default = 10,
          storage  = "proxy",
          getValue = function() return externalState.count end,
          setValue = function(v) externalState.count = v end },
    })
    report("storage='proxy' :Get reads from getValue closure (D31)",
           sP:Get("count") == 5)
    sP:Set("count", 42)
    report("storage='proxy' :Set writes through setValue closure (D31)",
           externalState.count == 42)
    report("storage='proxy' :Get reflects post-Set state (D31)",
           sP:Get("count") == 42)
    -- Proxy backend SHOULD NOT seed defaults into db.profile (consumer-managed)
    report("storage='proxy' does NOT seed default into db.profile (D31)",
           rawget(dbPR.profile, "count") == nil)
    CDB.instances[SVPR] = nil; _G[SVPR] = nil


    -- Validation: storage='proxy' missing getValue / setValue
    report("storage='proxy' missing getValue rejected (D31)",
           not pcall(function() CS:New("D31bad1_" .. stamp,
               CDB:New("D31bad1_db_" .. stamp, { profile = {} }), {
                   { key = "x", type = "range", label = "X", default = 1,
                     min = 0, max = 10, step = 1, storage = "proxy",
                     setValue = function() end },
               }) end))
    report("storage='proxy' missing setValue rejected (D31)",
           not pcall(function() CS:New("D31bad2_" .. stamp,
               CDB:New("D31bad2_db_" .. stamp, { profile = {} }), {
                   { key = "x", type = "range", label = "X", default = 1,
                     min = 0, max = 10, step = 1, storage = "proxy",
                     getValue = function() return 0 end },
               }) end))
    report("storage='cvar' missing cvar string rejected (D31)",
           not pcall(function() CS:New("D31bad3_" .. stamp,
               CDB:New("D31bad3_db_" .. stamp, { profile = {} }), {
                   { key = "x", type = "toggle", label = "X", default = false,
                     storage = "cvar" },
               }) end))
    report("storage with unknown backend value rejected (D31)",
           not pcall(function() CS:New("D31bad4_" .. stamp,
               CDB:New("D31bad4_db_" .. stamp, { profile = {} }), {
                   { key = "x", type = "toggle", label = "X", default = false,
                     storage = "weirdbackend" },
               }) end))


    -- CVar backend smoke: stub GetCVar/SetCVar in-place so the test
    -- doesn't depend on a real CVar existing. The lib reads/writes
    -- through globals, so swapping them works.
    local SVCV = "CairnSettingsSmoke_D31cv_" .. stamp
    _G[SVCV] = nil; CDB.instances[SVCV] = nil
    local dbCV = CDB:New(SVCV, { profile = {} })

    local fakeCVars = { ["FakeCairnCVar_" .. stamp] = "0" }
    local origGetCVar, origSetCVar = _G.GetCVar, _G.SetCVar
    _G.GetCVar = function(name) return fakeCVars[name] end
    _G.SetCVar = function(name, value)
        fakeCVars[name] = tostring(value); return true
    end

    local sCV = CS:New("D31cvar_" .. stamp, dbCV, {
        { key = "fakeToggle", type = "toggle", label = "Fake CVar",
          default = false,
          storage = "cvar",
          cvar    = "FakeCairnCVar_" .. stamp },
    })
    report("storage='cvar' :Get reads via GetCVar (initial 0 → false) (D31)",
           sCV:Get("fakeToggle") == false)
    sCV:Set("fakeToggle", true)
    report("storage='cvar' :Set writes via SetCVar (writes '1') (D31)",
           fakeCVars["FakeCairnCVar_" .. stamp] == "1")
    report("storage='cvar' :Get reflects post-Set state (D31)",
           sCV:Get("fakeToggle") == true)
    -- CVar backend does NOT seed defaults into db.profile
    report("storage='cvar' does NOT seed default into db.profile (D31)",
           rawget(dbCV.profile, "fakeToggle") == nil)

    _G.GetCVar, _G.SetCVar = origGetCVar, origSetCVar
    CDB.instances[SVCV] = nil; _G[SVCV] = nil


    -- Default storage='addon' still works (existing behavior preserved)
    local SVAD = "CairnSettingsSmoke_D31ad_" .. stamp
    _G[SVAD] = nil; CDB.instances[SVAD] = nil
    local dbAD = CDB:New(SVAD, { profile = {} })
    local sAD = CS:New("D31addon_" .. stamp, dbAD, {
        { key = "myKey", type = "range", label = "K",
          min = 0, max = 1, step = 0.1, default = 0.5 },  -- no storage = addon
    })
    report("default storage='addon' seeds db.profile (D31)",
           dbAD.profile.myKey == 0.5)
    sAD:Set("myKey", 0.8)
    report("default storage='addon' :Set updates db.profile (D31)",
           dbAD.profile.myKey == 0.8)
    report("default storage='addon' :Get reads from db.profile (D31)",
           sAD:Get("myKey") == 0.8)
    CDB.instances[SVAD] = nil; _G[SVAD] = nil


    -- =====================================================================
    -- MINOR 19 — Cluster D spec-aware-profile (D19-D26)
    -- =====================================================================

    report("CS:EnhanceDB is a function",
           type(CS.EnhanceDB) == "function")
    report("CS:IterateDatabases is a function",
           type(CS.IterateDatabases) == "function")
    report("CS:EnhanceOptions is a function",
           type(CS.EnhanceOptions) == "function")
    report("CS._specProfileRegistry is a weak-keyed table",
           type(CS._specProfileRegistry) == "table"
           and getmetatable(CS._specProfileRegistry).__mode == "k")

    -- EnhanceDB mixes methods directly onto the db (D20)
    local SVD = "CairnSettingsSmoke_D19_" .. stamp
    _G[SVD] = nil; CDB.instances[SVD] = nil
    local dbD = CDB:New(SVD, { profile = {} })
    -- Set up two profiles so we can test SetSpecProfile + SetProfile dispatch
    dbD:SetProfile("Default")
    dbD:SetProfile("PvE")
    dbD:SetProfile("PvP")
    dbD:SetProfile("Default")  -- back to Default

    CS:EnhanceDB(dbD, "SmokeDB")
    report("EnhanceDB installs :IsSpecProfileEnabled on db (D20)",
           type(dbD.IsSpecProfileEnabled) == "function")
    report("EnhanceDB installs :GetSpecProfile on db (D20)",
           type(dbD.GetSpecProfile) == "function")
    report("EnhanceDB installs :SetSpecProfile on db (D20)",
           type(dbD.SetSpecProfile) == "function")
    report("EnhanceDB installs :CheckSpecProfileState on db (D20)",
           type(dbD.CheckSpecProfileState) == "function")
    report("EnhanceDB installs :SetSpecProfileEnabled on db (D20)",
           type(dbD.SetSpecProfileEnabled) == "function")
    report("EnhanceDB installs :RewireDeletedProfile on db (D23)",
           type(dbD.RewireDeletedProfile) == "function")

    -- D19: private namespace via :RegisterNamespace
    report("EnhanceDB creates _specProfileStore via RegisterNamespace (D19)",
           type(rawget(dbD, "_specProfileStore")) == "table")

    -- D21: db is in the weak registry
    local foundInRegistry = false
    for db, fname in CS:IterateDatabases() do
        if db == dbD and fname == "SmokeDB" then foundInRegistry = true end
    end
    report("EnhanceDB registers db with friendlyName in weak registry (D21+D26)",
           foundInRegistry == true)

    -- IsSpecProfileEnabled default false
    report("IsSpecProfileEnabled default is false",
           dbD:IsSpecProfileEnabled() == false)
    -- GetSpecProfile default is nil (no bindings)
    report("GetSpecProfile returns nil with no bindings",
           dbD:GetSpecProfile(1) == nil)

    -- SetSpecProfile binds spec→profile-name
    dbD:SetSpecProfile("PvE", 1)
    dbD:SetSpecProfile("PvP", 2)
    report("SetSpecProfile stores binding for spec 1",
           dbD:GetSpecProfile(1) == "PvE")
    report("SetSpecProfile stores binding for spec 2",
           dbD:GetSpecProfile(2) == "PvP")

    -- SetSpecProfile(nil, spec) clears binding
    dbD:SetSpecProfile(nil, 1)
    report("SetSpecProfile(nil, spec) clears binding",
           dbD:GetSpecProfile(1) == nil)

    -- D23: RewireDeletedProfile rewires bindings pointing at deleted profile
    dbD:SetSpecProfile("PvE", 1)
    dbD:SetSpecProfile("PvE", 3)
    dbD:RewireDeletedProfile("PvE")
    local currentProfile = dbD:GetProfile()
    report("RewireDeletedProfile rewires both bindings to current (D23)",
           dbD:GetSpecProfile(1) == currentProfile
           and dbD:GetSpecProfile(3) == currentProfile)

    -- SetSpecProfileEnabled toggles master switch
    dbD:SetSpecProfileEnabled(true)
    report("SetSpecProfileEnabled(true) flips IsSpecProfileEnabled",
           dbD:IsSpecProfileEnabled() == true)
    dbD:SetSpecProfileEnabled(false)
    report("SetSpecProfileEnabled(false) flips back to false",
           dbD:IsSpecProfileEnabled() == false)

    -- Idempotent: second EnhanceDB doesn't double-register
    local sizeBefore = 0
    for _ in pairs(CS._specProfileRegistry) do sizeBefore = sizeBefore + 1 end
    CS:EnhanceDB(dbD, "AlsoSmokeDB")
    local sizeAfter = 0
    for _ in pairs(CS._specProfileRegistry) do sizeAfter = sizeAfter + 1 end
    report("EnhanceDB is idempotent (same db doesn't duplicate registry)",
           sizeBefore == sizeAfter)

    -- D22: EnhanceOptions injects plugins entry without touching args
    local optionsTbl = {
        args = { existingKey = { type = "toggle", default = true } },
    }
    CS:EnhanceOptions(optionsTbl, dbD)
    report("EnhanceOptions adds plugins['Cairn-Settings-SpecProfile'] entry (D22)",
           type(optionsTbl.plugins) == "table"
           and type(optionsTbl.plugins["Cairn-Settings-SpecProfile"]) == "table")
    report("EnhanceOptions does NOT mutate options.args (D22)",
           optionsTbl.args.existingKey ~= nil
           and optionsTbl.args["Cairn-Settings-SpecProfile"] == nil)
    -- Idempotent: second call doesn't re-add
    local pluginsRef = optionsTbl.plugins["Cairn-Settings-SpecProfile"]
    CS:EnhanceOptions(optionsTbl, dbD)
    report("EnhanceOptions is idempotent",
           optionsTbl.plugins["Cairn-Settings-SpecProfile"] == pluginsRef)

    -- Validation
    report("EnhanceDB(non-table) errors",
           not pcall(function() CS:EnhanceDB("notatable") end))
    report("EnhanceOptions on non-enhanced db errors",
           not pcall(function() CS:EnhanceOptions({}, {}) end))
    report("RewireDeletedProfile('') errors",
           not pcall(function() dbD:RewireDeletedProfile("") end))
    report("SetSpecProfile(non-string-non-nil, spec) errors",
           not pcall(function() dbD:SetSpecProfile(42, 1) end))

    CDB.instances[SVD] = nil; _G[SVD] = nil


    -- =====================================================================
    -- MINOR 20 — Cluster F Blizzard-frame override (D39-D44)
    -- =====================================================================

    report("CS:OverrideBlizzardFrame is a function",
           type(CS.OverrideBlizzardFrame) == "function")
    report("CS:SetBlizzardFrameSetting is a function",
           type(CS.SetBlizzardFrameSetting) == "function")
    report("CS:BeginBatch is a function",
           type(CS.BeginBatch) == "function")
    report("CS:ApplyChanges is a function",
           type(CS.ApplyChanges) == "function")
    report("CS:SaveOnly is a function",
           type(CS.SaveOnly) == "function")
    report("CS:RegisterTaintClearance is a function",
           type(CS.RegisterTaintClearance) == "function")
    report("CS:IterateTaintClearances is a function",
           type(CS.IterateTaintClearances) == "function")

    -- Lib-scope state shape
    report("CS._overrideState is a table",
           type(CS._overrideState) == "table")
    report("CS._taintClearances is a table",
           type(CS._taintClearances) == "table")

    -- D42: BeginBatch flips inBatch flag
    report("BeginBatch flips inBatch flag (D42)",
           (function()
               CS._overrideState.inBatch = false
               CS:BeginBatch()
               return CS._overrideState.inBatch == true
           end)())

    -- ApplyChanges clears inBatch flag
    CS._overrideState.activeLayoutPending = false
    CS:ApplyChanges()
    report("ApplyChanges clears inBatch flag (D42)",
           CS._overrideState.inBatch == false)

    -- D43: SaveOnly clears activeLayoutPending
    CS._overrideState.activeLayoutPending = true
    CS:SaveOnly()
    report("SaveOnly clears activeLayoutPending (D43)",
           CS._overrideState.activeLayoutPending == false)

    -- D44: seed clearance recipe is present
    report("Seed taint-clearance for DropDownList1 is registered (D44)",
           type(CS._taintClearances["DropDownList1"]) == "function")

    -- D44: RegisterTaintClearance + IterateTaintClearances
    CS:RegisterTaintClearance("FakeTaintTarget_" .. stamp, function() end)
    report("RegisterTaintClearance adds entry (D44)",
           type(CS._taintClearances["FakeTaintTarget_" .. stamp]) == "function")
    local foundTaintEntry = false
    for tgt, fn in CS:IterateTaintClearances() do
        if tgt == "FakeTaintTarget_" .. stamp and type(fn) == "function" then
            foundTaintEntry = true
        end
    end
    report("IterateTaintClearances yields registered entry (D44)",
           foundTaintEntry == true)
    CS._taintClearances["FakeTaintTarget_" .. stamp] = nil

    -- D44 validation
    report("RegisterTaintClearance('', fn) errors (D44)",
           not pcall(function() CS:RegisterTaintClearance("", function() end) end))
    report("RegisterTaintClearance('x', 'notafn') errors (D44)",
           not pcall(function() CS:RegisterTaintClearance("x", "notafn") end))

    -- D39 / D40 input validation
    report("OverrideBlizzardFrame(nil, ...) errors (D39)",
           not pcall(function()
               CS:OverrideBlizzardFrame(nil, "TOPLEFT", nil, "TOPLEFT", 0, 0)
           end))
    report("OverrideBlizzardFrame with non-string point errors (D39)",
           not pcall(function()
               CS:OverrideBlizzardFrame({}, nil, nil, "TOPLEFT", 0, 0)
           end))
    report("OverrideBlizzardFrame with non-number offset errors (D39)",
           not pcall(function()
               CS:OverrideBlizzardFrame({}, "TOP", nil, "TOP", "x", 0)
           end))
    report("SetBlizzardFrameSetting(nil, ...) errors (D40)",
           not pcall(function() CS:SetBlizzardFrameSetting(nil, 1, 0) end))
    report("SetBlizzardFrameSetting with nil settingEnum errors (D40)",
           not pcall(function() CS:SetBlizzardFrameSetting({}, nil, 0) end))

    -- (Earlier versions of this smoke clobbered _G.EditModeManagerFrame
    -- to test the EditMode-absent path. That taints execution and
    -- propagates into Blizzard's nameplate code on Retail — REMOVED.
    -- The absent-EditMode branch is verified by inspection instead.)


    -- =====================================================================
    -- MINOR 21 — D28 compound controls + D32 LSM dropdown (schema-only)
    -- =====================================================================

    -- Compound + LSM kinds appear in the controlTypes registry
    report("controlTypes.checkbox_and_slider exists (D28)",
           type(CS.controlTypes.checkbox_and_slider) == "table")
    report("controlTypes.checkbox_and_dropdown exists (D28)",
           type(CS.controlTypes.checkbox_and_dropdown) == "table")
    report("controlTypes.checkbox_and_button exists (D28)",
           type(CS.controlTypes.checkbox_and_button) == "table")
    report("controlTypes.lib_shared_media_dropdown exists (D32)",
           type(CS.controlTypes.lib_shared_media_dropdown) == "table")

    -- Schema with checkbox_and_slider accepted when child is supplied
    local SVCK = "CairnSettingsSmoke_D28_" .. stamp
    _G[SVCK] = nil; CDB.instances[SVCK] = nil
    local dbCK = CDB:New(SVCK, { profile = {} })
    local sCK = CS:New("D28cs_" .. stamp, dbCK, {
        { key = "compoundA", type = "checkbox_and_slider",
          label = "Use scaling", default = true,
          child = {
              key = "compoundAChild", type = "range",
              label = "Scale", min = 0.5, max = 2.0, step = 0.1,
              default = 1.0,
          } },
    })
    report("checkbox_and_slider with child accepted (D28)",
           type(sCK) == "table")
    report("checkbox_and_slider top default seeded (D28)",
           dbCK.profile.compoundA == true)

    -- checkbox_and_slider missing child rejected
    report("checkbox_and_slider missing child rejected (D28)",
           not pcall(function() CS:New("D28bad_" .. stamp, dbCK, {
               { key = "missingChild", type = "checkbox_and_slider",
                 label = "X", default = false },
           }) end))

    -- checkbox_and_button similar
    local sCB = CS:New("D28cb_" .. stamp, dbCK, {
        { key = "compoundB", type = "checkbox_and_button",
          label = "Enable feature", default = false,
          child = {
              key = "compoundBChild", type = "header",
              label = "Open Manager",
          } },
    })
    report("checkbox_and_button with child accepted (D28)",
           type(sCB) == "table")

    -- LSM dropdown — accepted when mediaType is set
    local sLSM = CS:New("D32_" .. stamp, dbCK, {
        { key = "fontPick", type = "lib_shared_media_dropdown",
          label = "Font", mediaType = "font",
          default = "CairnDefault" },
    })
    report("lib_shared_media_dropdown with mediaType accepted (D32)",
           type(sLSM) == "table")
    report("lib_shared_media_dropdown default seeded (D32)",
           dbCK.profile.fontPick == "CairnDefault")

    -- LSM dropdown missing mediaType rejected
    report("lib_shared_media_dropdown missing mediaType rejected (D32)",
           not pcall(function() CS:New("D32bad_" .. stamp, dbCK, {
               { key = "fontMissing", type = "lib_shared_media_dropdown",
                 label = "X", default = "Y" },
           }) end))

    CDB.instances[SVCK] = nil; _G[SVCK] = nil


    -- =====================================================================
    -- MINOR 22 — Cluster B+C foundation (D6 + D8 + D11 + D17 + D18)
    -- =====================================================================

    -- D6: custom-setting enum allocator
    report("CS.CUSTOM_SETTING_CONSUMER_FLOOR == 100 (D6)",
           CS.CUSTOM_SETTING_CONSUMER_FLOOR == 100)
    report("CS:RegisterCustomSetting is a function (D6)",
           type(CS.RegisterCustomSetting) == "function")
    report("CS:GetCustomSetting is a function (D6)",
           type(CS.GetCustomSetting) == "function")

    local prevNext = CS._nextCustomSettingId
    -- Reset to 100 for deterministic test
    CS._nextCustomSettingId = 100
    local id1 = CS:RegisterCustomSetting("FakeSetting1_" .. stamp, "Toggle")
    local id2 = CS:RegisterCustomSetting("FakeSetting2_" .. stamp, "Slider")
    report("RegisterCustomSetting allocates from CONSUMER_FLOOR (D6)",
           id1 == 100)
    report("RegisterCustomSetting increments per call (D6)",
           id2 == 101)
    report("GetCustomSetting returns the registered entry (D6)",
           CS:GetCustomSetting("FakeSetting1_" .. stamp).id == 100)
    -- Idempotent on name
    local id1Again = CS:RegisterCustomSetting("FakeSetting1_" .. stamp, "Toggle")
    report("RegisterCustomSetting idempotent on name (D6)",
           id1Again == 100)
    -- Cleanup
    CS._customSettings["FakeSetting1_" .. stamp] = nil
    CS._customSettings["FakeSetting2_" .. stamp] = nil
    CS._nextCustomSettingId = prevNext or 100

    -- D6 validation
    report("RegisterCustomSetting('', type) errors (D6)",
           not pcall(function() CS:RegisterCustomSetting("", "Toggle") end))
    report("RegisterCustomSetting('x', nil) errors (D6)",
           not pcall(function() CS:RegisterCustomSetting("x", nil) end))


    -- D11: custom system ID allocator
    report("CS:AllocateCustomSystemID is a function (D11)",
           type(CS.AllocateCustomSystemID) == "function")
    local sysId1 = CS:AllocateCustomSystemID()
    local sysId2 = CS:AllocateCustomSystemID()
    report("AllocateCustomSystemID returns numbers (D11)",
           type(sysId1) == "number" and type(sysId2) == "number")
    report("AllocateCustomSystemID increments per call (D11)",
           sysId2 == sysId1 + 1)


    -- D8: defensive metatables on framesDB / framesDialogs
    report("CS.framesDB is a table (D8)",
           type(CS.framesDB) == "table")
    report("CS.framesDialogs is a table (D8)",
           type(CS.framesDialogs) == "table")
    -- First access auto-creates entry with `settings` sub-field
    local fakeFrame = { name = "fakeForD8_" .. stamp }
    local dbEntry = CS.framesDB[fakeFrame]
    report("framesDB auto-creates entry on first access (D8)",
           type(dbEntry) == "table" and type(dbEntry.settings) == "table")
    local dlgEntry = CS.framesDialogs[fakeFrame]
    report("framesDialogs auto-creates entry on first access (D8)",
           type(dlgEntry) == "table" and type(dlgEntry.settings) == "table")
    -- Cleanup
    CS.framesDB[fakeFrame] = nil
    CS.framesDialogs[fakeFrame] = nil


    -- D17: FireHideDialog through EventRegistry
    report("CS:FireHideDialog is a function (D17)",
           type(CS.FireHideDialog) == "function")
    report("CS:_EnsureHideDialogListener is a function (D17)",
           type(CS._EnsureHideDialogListener) == "function")
    -- Returns true when EventRegistry is available
    local fireResult = CS:FireHideDialog("smokeTag_" .. stamp)
    report("FireHideDialog returns bool (D17)",
           type(fireResult) == "boolean")


    -- D18: NormalizeAnchorByQuadrant
    report("CS:NormalizeAnchorByQuadrant is a function (D18)",
           type(CS.NormalizeAnchorByQuadrant) == "function")
    -- Build a fake frame that responds to GetCenter / GetWidth / GetHeight
    -- and accepts SetPoint / ClearAllPoints without throwing
    local fakeMovable = {
        GetCenter      = function() return 100, 100 end,  -- bottom-left quadrant
        GetWidth       = function() return 50 end,
        GetHeight      = function() return 50 end,
        ClearAllPoints = function() end,
        SetPoint       = function() end,
    }
    local ok, point, ox, oy = CS:NormalizeAnchorByQuadrant(fakeMovable)
    report("NormalizeAnchorByQuadrant returns true on success (D18)",
           ok == true)
    report("NormalizeAnchorByQuadrant picks BOTTOMLEFT for low-low center (D18)",
           point == "BOTTOMLEFT")
    report("NormalizeAnchorByQuadrant returns ox/oy as numbers (D18)",
           type(ox) == "number" and type(oy) == "number")

    -- Top-right quadrant: center at screen-width*0.9, screen-height*0.9
    local sw = (_G.UIParent and _G.UIParent:GetWidth())  or 1920
    local sh = (_G.UIParent and _G.UIParent:GetHeight()) or 1080
    fakeMovable.GetCenter = function() return sw * 0.9, sh * 0.9 end
    local _, point2 = CS:NormalizeAnchorByQuadrant(fakeMovable)
    report("NormalizeAnchorByQuadrant picks TOPRIGHT for high-high center (D18)",
           point2 == "TOPRIGHT")

    -- D18 validation
    report("NormalizeAnchorByQuadrant(nil) errors (D18)",
           not pcall(function() CS:NormalizeAnchorByQuadrant(nil) end))


    -- =====================================================================
    -- MINOR 23 — Cluster B+C declarative :Add (D13 + D14 + D16 + D10)
    -- =====================================================================

    report("CS:Add is a function (D13)",
           type(CS.Add) == "function")
    report("CS:AddSystemSettings is a function (D16)",
           type(CS.AddSystemSettings) == "function")
    report("CS:GetFrameRegistration is a function",
           type(CS.GetFrameRegistration) == "function")
    report("CS:IterateFrames is a function",
           type(CS.IterateFrames) == "function")
    report("CS:IsRegisteredFrame is a function",
           type(CS.IsRegisteredFrame) == "function")
    report("CS.editModeKinds is a table (D13)",
           type(CS.editModeKinds) == "table")
    report("editModeKinds.anchor exists (D13)",
           type(CS.editModeKinds.anchor) == "table")
    report("editModeKinds.secureFrameHideable exists (D10)",
           type(CS.editModeKinds.secureFrameHideable) == "table")
    report("editModeKinds.scale exists (D13)",
           type(CS.editModeKinds.scale) == "table")

    -- Build a fake frame that responds to :GetName for label fallback
    local fakeAddFrame = { GetName = function() return "FakeAddFrame_" .. stamp end }
    local sysId = CS:Add(fakeAddFrame, {
        { key = "pos",    kind = "anchor", label = "Position" },
        { key = "visible", kind = "hideable", label = "Visible",
          default = true },
        { key = "scale",  kind = "scale", label = "Scale",
          min = 0.5, max = 2.0, step = 0.1, default = 1.0 },
    })
    report(":Add returns a system ID (D13)",
           type(sysId) == "number")
    report(":Add stamps frame.system (D13)",
           fakeAddFrame.system == sysId)
    report("IsRegisteredFrame returns true after :Add (D13)",
           CS:IsRegisteredFrame(fakeAddFrame) == true)
    local reg = CS:GetFrameRegistration(fakeAddFrame)
    report("GetFrameRegistration returns the registration table (D13)",
           type(reg) == "table" and reg.systemId == sysId)
    -- Idempotent
    local sysId2 = CS:Add(fakeAddFrame, { { key = "x", kind = "anchor", label = "X" } })
    report(":Add is idempotent (re-call returns same systemId) (D13)",
           sysId2 == sysId)

    -- IterateFrames walks the registry
    local foundFakeFrame = false
    for f, r in CS:IterateFrames() do
        if f == fakeAddFrame and r.systemId == sysId then foundFakeFrame = true end
    end
    report("IterateFrames yields the registered frame (D13)",
           foundFakeFrame == true)


    -- D10 secureFrameHideable accepts toggleInCombat
    local fakeSecure = { GetName = function() return "FakeSecure_" .. stamp end }
    local sId = CS:Add(fakeSecure, {
        { key = "vis", kind = "secureFrameHideable",
          label = "Visible", default = true,
          toggleInCombat = false,
          hidden = function() return false end },
    })
    report("secureFrameHideable schema accepted with toggleInCombat (D10)",
           type(sId) == "number")

    -- D10 toggleInCombat must be boolean if present
    report("secureFrameHideable rejects non-boolean toggleInCombat (D10)",
           not pcall(function()
               CS:Add({ GetName = function() return "f" .. stamp end }, {
                   { key = "vis", kind = "secureFrameHideable",
                     label = "V", default = true,
                     toggleInCombat = "notabool" },
               })
           end))


    -- D14 consumer-supplied get/set: both must be present OR both absent
    local extState = { scale = 1.0 }
    local fakeProxy = { GetName = function() return "FakeProxy_" .. stamp end }
    local pSysId = CS:Add(fakeProxy, {
        { key = "scale", kind = "scale",
          label = "Scale", min = 0.5, max = 2.0, step = 0.1, default = 1.0,
          get = function() return extState.scale end,
          set = function(v) extState.scale = v end },
    })
    report("get/set both supplied accepted (D14)",
           type(pSysId) == "number")

    report("get without set rejected (D14)",
           not pcall(function()
               CS:Add({ GetName = function() return "f2" .. stamp end }, {
                   { key = "x", kind = "scale", label = "X",
                     default = 1.0, get = function() end },
               })
           end))
    report("set without get rejected (D14)",
           not pcall(function()
               CS:Add({ GetName = function() return "f3" .. stamp end }, {
                   { key = "x", kind = "scale", label = "X",
                     default = 1.0, set = function() end },
               })
           end))


    -- D13 schema validation
    report(":Add rejects non-table schema (D13)",
           not pcall(function() CS:Add({ GetName = function() return "f" end }, "notatable") end))
    report(":Add rejects nil frame (D13)",
           not pcall(function() CS:Add(nil, {}) end))
    report(":Add rejects entry without 'key' (D13)",
           not pcall(function()
               CS:Add({ GetName = function() return "f4" .. stamp end }, {
                   { kind = "anchor", label = "X" },  -- no key
               })
           end))
    report(":Add rejects entry with unknown kind (D13)",
           not pcall(function()
               CS:Add({ GetName = function() return "f5" .. stamp end }, {
                   { key = "x", kind = "unknownKind_" .. stamp, label = "X" },
               })
           end))
    report(":Add rejects duplicate keys (D13)",
           not pcall(function()
               CS:Add({ GetName = function() return "f6" .. stamp end }, {
                   { key = "dup", kind = "anchor", label = "A" },
                   { key = "dup", kind = "anchor", label = "B" },
               })
           end))


    -- D16 :AddSystemSettings
    report(":AddSystemSettings accepts systemID + schema (D16)",
           CS:AddSystemSettings(42, {
               { key = "custom1_" .. stamp, kind = "scale",
                 label = "C", default = 1.0 },
           }) == true)
    report(":AddSystemSettings with subSystemID accepted (D16)",
           CS:AddSystemSettings(42, {
               { key = "custom2_" .. stamp, kind = "scale",
                 label = "C2", default = 1.0 },
           }, 3) == true)
    report(":AddSystemSettings(non-number systemID) errors (D16)",
           not pcall(function() CS:AddSystemSettings("notnum", {}) end))
    report(":AddSystemSettings(num, schema, non-num subSystemID) errors (D16)",
           not pcall(function() CS:AddSystemSettings(1, {}, "notnum") end))


    -- =====================================================================
    -- MINOR 24 — Cluster B+C runtime hooks (D5 + D9 + D15) — completes walk
    -- =====================================================================

    -- D15 — hookVersion stamped at lib-load matches LIB_MINOR
    report("CS.hookVersion is a number (D15)",
           type(CS.hookVersion) == "number")
    report("CS.hookVersion >= 24 (D15)",
           CS.hookVersion >= 24)

    -- D9 — install hooks method exists + installed flag tracked
    report("CS:InstallEditModeHooks is a function (D9)",
           type(CS.InstallEditModeHooks) == "function")
    report("CS._editModeHooksInstalled is a boolean (D9)",
           type(CS._editModeHooksInstalled) == "boolean")

    -- D5 — layout profile name resolution
    report("CS:ResolveLayoutProfileName is a function (D5)",
           type(CS.ResolveLayoutProfileName) == "function")
    report("CS:LoadLayoutProfile is a function (D5)",
           type(CS.LoadLayoutProfile) == "function")

    -- Account-scope layout: profileName = "<layoutType>-<layoutName>"
    -- Use a non-Character layoutType ("Account" or any non-CHAR value)
    -- so the resolver doesn't append character-realm.
    local accName = CS:ResolveLayoutProfileName("Account", "MyLayout_" .. stamp)
    report("ResolveLayoutProfileName: Account scope = 'Account-MyLayout_...' (D5)",
           accName == "Account-MyLayout_" .. stamp)

    -- Character-scope: profileName appends "-<character>-<realm>"
    if _G.Enum and _G.Enum.EditModeLayoutType
       and _G.Enum.EditModeLayoutType.Character
    then
        local CHAR_TYPE = _G.Enum.EditModeLayoutType.Character
        local charName = CS:ResolveLayoutProfileName(CHAR_TYPE, "Solo_" .. stamp)
        report("ResolveLayoutProfileName: Character scope appends -<name>-<realm> (D5)",
               type(charName) == "string"
               and charName:find("Solo_" .. stamp, 1, true) ~= nil
               and charName:find("-", 1, true) ~= nil)
    end

    -- Empty / nil layoutName returns nil
    report("ResolveLayoutProfileName('Account', '') returns nil (D5)",
           CS:ResolveLayoutProfileName("Account", "") == nil)
    report("ResolveLayoutProfileName('Account', nil) returns nil (D5)",
           CS:ResolveLayoutProfileName("Account", nil) == nil)

    -- D5: LoadLayoutProfile switches Cairn-DB profile to the resolved name
    local SVL5 = "CairnSettingsSmoke_D5_" .. stamp
    _G[SVL5] = nil; CDB.instances[SVL5] = nil
    local dbL5 = CDB:New(SVL5, { profile = { scale = 1.0 } })
    local pname = CS:LoadLayoutProfile(dbL5, "Account", "TestLayout_" .. stamp)
    report("LoadLayoutProfile returns the profile name (D5)",
           pname == "Account-TestLayout_" .. stamp)
    report("LoadLayoutProfile switches the db's active profile (D5)",
           dbL5:GetProfile() == "Account-TestLayout_" .. stamp)
    -- New profile inherits defaults via wildcardMerge in SetProfile
    report("LoadLayoutProfile: new profile inherits defaults (D5)",
           dbL5.profile.scale == 1.0)

    -- LoadLayoutProfile validation
    report("LoadLayoutProfile(non-db, ...) errors (D5)",
           not pcall(function() CS:LoadLayoutProfile({}, "Account", "x") end))

    CDB.instances[SVL5] = nil; _G[SVL5] = nil


    -- Cleanup
    CS._frames[fakeAddFrame] = nil
    CS._frames[fakeSecure]   = nil
    CS._frames[fakeProxy]    = nil
    CDB.instances[SV]  = nil; _G[SV]  = nil
    CDB.instances[SV2] = nil; _G[SV2] = nil
    CDB.instances[SV3] = nil; _G[SV3] = nil
end
