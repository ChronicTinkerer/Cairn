-- Cairn-Settings
-- Declarative settings schema bridged to Blizzard's native Settings panel
-- (the Dragonflight-era Settings API, refined through Midnight). Backed by
-- a Cairn-DB instance the consumer provides.
--
--   local db = LibStub("Cairn-DB-1.0"):New("MyAddonDB", {
--       profile = { scale = 1.0, enabled = true, theme = "dark" },
--   })
--
--   local settings = LibStub("Cairn-Settings-1.0"):New("MyAddon", db, {
--       { key = "display",  type = "header", label = "Display" },
--       { key = "scale",    type = "range",  label = "Scale",
--         min = 0.5, max = 2.0, step = 0.1, default = 1.0,
--         tooltip = "How big the frame is",
--         onChange = function(v) MyAddon:Rescale(v) end },
--       { key = "enabled",  type = "toggle", label = "Enable",
--         default = true },
--       { key = "theme",    type = "dropdown", label = "Theme",
--         default = "dark",
--         choices = { dark = "Dark", light = "Light", auto = "Auto" } },
--   })
--
--   settings:Open()                              -- open Blizzard panel to this addon
--   settings:Get("scale")                        -- current value
--   settings:Set("scale", 1.5)                   -- write (fires onChange + subscribers)
--   local unsub = settings:OnChange("scale", function(new, old) ... end)
--   unsub()                                       -- cancel the subscription
--
-- Schema entry fields (common):
--   key      string  required, unique within this addon's schema
--   type     string  required, one of:
--                    toggle | range | dropdown | header           (rendered)
--                    text | color | keybind                       (storage-only)
--   label    string  required, user-facing display label
--   default  any     required EXCEPT for type="header"; seeded into db.profile
--   tooltip  string  optional, hover text on the rendered control
--   onChange function optional, called as fn(newValue, oldValue) after change
--
-- Type-specific fields:
--   range:    min, max, step                       (defaults: 0, 1, 0.1)
--   dropdown: choices                              (table {value = label, ...})
--   text:     placeholder, maxLetters, width       (string default required)
--   color:    hasOpacity (bool); default = { r=, g=, b=[, a=] }  named or
--                                              { r, g, b[, a] } positional
--                                              (positional normalized at validate)
--   keybind:  default = binding string ("CTRL-SHIFT-X") or "" for unbound
--
-- Storage-only types (text / color / keybind): these are intentionally NOT
-- rendered in the Blizzard panel. The schema validates them, defaults seed
-- them, Get/Set/OnChange work as expected — but the consumer renders the
-- visual themselves (their own UI / slash / popup). Midnight's Settings API
-- changed enough that the previously-working panel-button paths broke; we
-- chose storage-only over chasing the API rather than ship a broken widget.
--
-- Stub mode: if the Blizzard `Settings` global is unavailable (Classic
-- clients), :New returns a stub that supports Get/Set/OnChange (data still
-- persists via Cairn-DB) but :Open prints a warning instead of opening a
-- panel.
--
-- Public API:
--   local CS = LibStub("Cairn-Settings-1.0")
--   local s  = CS:New(addonName, db, schema)  -> settings instance
--   CS.instances                                  -- {[instance] = addonName} weak
--
-- Instance API:
--   s:Get(key)                                    -- read current value
--   s:Set(key, value)                             -- write (fires callbacks)
--   s:OnChange(key, fn, owner) -> unsub fn        -- subscribe
--   s:Open()                                      -- open Blizzard panel
--   s:GetCategory()                               -- Blizzard category object (or nil)
--   s:GetCategoryID()                             -- Blizzard category ID (or nil)
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Settings-1.0"
local LIB_MINOR = 14

local Cairn_Settings = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Settings then return end


-- Weak-keyed instances table so Forge_Registry / dev tools can enumerate
-- live settings panels. Same pattern Cairn-Callback uses for its registries.
-- Weak keys means a GC'd settings instance disappears from the registry
-- without needing explicit unregister.
Cairn_Settings.instances = Cairn_Settings.instances or setmetatable({}, { __mode = "k" })


-- Cairn-Log is a SOFT dependency — useful for surfacing schema mistakes
-- and stub-mode notices, but not load-bearing. If absent, we just stay
-- quiet (or fall back to print for the stub-mode banner).
local function getLogger()
    if Cairn_Settings._log then return Cairn_Settings._log end
    local Log = LibStub and LibStub("Cairn-Log-1.0", true)
    if Log then
        Cairn_Settings._log = Log:New("Cairn.Settings")
    end
    return Cairn_Settings._log
end


-- Schema types the validator accepts. Splitting into "rendered" vs "storage"
-- inside the registerEntry path; here we just gate the accept set.
local SUPPORTED_TYPES = {
    toggle   = true,
    range    = true,
    dropdown = true,
    header   = true,
    text     = true,   -- storage-only
    color    = true,   -- storage-only
    keybind  = true,   -- storage-only
}


-- ---------------------------------------------------------------------------
-- Schema validation
-- ---------------------------------------------------------------------------
-- Strict by design: catching a typo'd key or missing default at New() time
-- is far cheaper than letting a UI render half-broken. The pcall around
-- registerEntry later still gracefully degrades for non-fatal failures
-- (e.g. one weird entry doesn't break the rest of the panel).

local function validateSchema(schema)
    if type(schema) ~= "table" then
        error("Cairn-Settings:New: schema must be a table (array of entries)", 3)
    end
    local seen = {}
    for i, entry in ipairs(schema) do
        if type(entry) ~= "table" then
            error("Cairn-Settings:New: schema entry #" .. i .. " must be a table", 3)
        end
        if type(entry.key) ~= "string" or entry.key == "" then
            error("Cairn-Settings:New: schema entry #" .. i .. " missing 'key' (string)", 3)
        end
        if not SUPPORTED_TYPES[entry.type] then
            error("Cairn-Settings:New: schema entry '" .. entry.key ..
                  "' has unsupported type: " .. tostring(entry.type), 3)
        end
        if seen[entry.key] then
            error("Cairn-Settings:New: duplicate schema key: " .. entry.key, 3)
        end
        seen[entry.key] = true

        if entry.type ~= "header" and entry.default == nil then
            error("Cairn-Settings:New: schema entry '" .. entry.key ..
                  "' requires a 'default' value", 3)
        end

        if entry.type == "dropdown" and type(entry.choices) ~= "table" then
            error("Cairn-Settings:New: dropdown entry '" .. entry.key ..
                  "' requires a 'choices' table", 3)
        end

        if entry.type == "text" and type(entry.default) ~= "string" then
            error("Cairn-Settings:New: text entry '" .. entry.key ..
                  "' requires a string 'default'", 3)
        end

        if entry.type == "color" then
            -- Canonical default shape is named ({ r=, g=, b=[, a=] } each 0..1).
            -- Positional ({ r, g, b[, a] }) is accepted for backwards-compat
            -- with addons that built their tables that way and normalized in
            -- place to named. Mixed inputs (some named, some positional)
            -- prefer named.
            local d = entry.default
            if type(d) ~= "table" then
                error("Cairn-Settings:New: color entry '" .. entry.key ..
                      "' requires a default table {r=, g=, b=[, a=]} (each 0..1)", 3)
            end
            local hasNamed = (type(d.r) == "number" and type(d.g) == "number" and type(d.b) == "number")
            local hasPos   = (type(d[1]) == "number" and type(d[2]) == "number" and type(d[3]) == "number")
            if not hasNamed and not hasPos then
                error("Cairn-Settings:New: color entry '" .. entry.key ..
                      "' requires default = {r=, g=, b=[, a=]} OR {r, g, b[, a]} (each 0..1)", 3)
            end
            if hasPos and not hasNamed then
                entry.default = { r = d[1], g = d[2], b = d[3], a = d[4] }
            end
        end

        if entry.type == "keybind" and type(entry.default) ~= "string" then
            error("Cairn-Settings:New: keybind entry '" .. entry.key ..
                  "' requires a string 'default' (e.g. \"CTRL-SHIFT-X\" or \"\")", 3)
        end
    end
end


-- Seed defaults into the consumer's DB. Header entries skipped (no value
-- to store). Only writes when the existing slot is nil so user data
-- survives across version upgrades — a consumer changing a default later
-- doesn't retroactively overwrite the user's saved value. Documented
-- explicitly because consumers WILL hit this and be confused.
local function seedDefaults(db, schema)
    for _, entry in ipairs(schema) do
        if entry.type ~= "header" and db.profile[entry.key] == nil then
            db.profile[entry.key] = entry.default
        end
    end
end


-- Dispatch onChange + subscribers after a value write. pcall'd so one bad
-- subscriber doesn't poison the rest. The `removed` flag check skips
-- subscribers cancelled mid-dispatch (the returned unsub fn just sets it).
local function fireSubscribers(self, key, newValue, oldValue)
    local list = self._subs[key]
    if not list then return end
    for i = 1, #list do
        local sub = list[i]
        if sub and not sub.removed then
            local ok, err = pcall(sub.fn, newValue, oldValue)
            if not ok then geterrorhandler()(err) end
        end
    end
end


local function setValue(self, key, value)
    local oldValue = self._db.profile[key]
    if oldValue == value then return end
    self._db.profile[key] = value

    local entry = self._byKey[key]
    if entry and entry.onChange then
        local ok, err = pcall(entry.onChange, value, oldValue)
        if not ok then geterrorhandler()(err) end
    end
    fireSubscribers(self, key, value, oldValue)
end


-- ---------------------------------------------------------------------------
-- Stub instance — used when Blizzard's Settings API isn't available
-- ---------------------------------------------------------------------------
-- Get / Set / OnChange still work because they only need db.profile. :Open
-- prints a warning instead of opening a panel. Storage-only types
-- (text/color/keybind) still seed and round-trip normally.

local stubProto = {}
stubProto.__index = stubProto

function stubProto:Open()
    local log = getLogger()
    if log then
        log:Warn("Settings:Open called but Blizzard's Settings API is not available on this client.")
    else
        print("|cFF7FBFFF[Cairn]|r Settings panel not available on this client.")
    end
end

function stubProto:Get(key)            return self._db.profile[key] end
function stubProto:Set(key, value)     setValue(self, key, value) end
function stubProto:GetCategoryID()     return nil end
function stubProto:GetCategory()       return nil end


-- ---------------------------------------------------------------------------
-- Real instance — bridges to Blizzard Settings
-- ---------------------------------------------------------------------------

local proto = {}
proto.__index = proto

function proto:Get(key)            return self._db.profile[key] end
function proto:Set(key, value)     setValue(self, key, value) end
function proto:GetCategory()       return self._category end
function proto:GetCategoryID()     return self._categoryID end


function proto:Open()
    if not self._categoryID then
        local log = getLogger()
        if log then log:Warn("Settings:Open called but no category was registered.") end
        return
    end
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self._categoryID)
    end
end


-- Standalone panel rendered by Cairn-SettingsPanel-2.0 (built on Cairn-Gui-
-- 2.0). Independent of Blizzard's Settings UI — works for every schema type
-- including the storage-only ones (text/color/keybind) that the Blizzard
-- panel can't render. Returns nil silently if Cairn-SettingsPanel-2.0 isn't
-- loaded; consumers can fall back to :Open() in that case.
function proto:OpenStandalone()
    local Panel = LibStub("Cairn-SettingsPanel-2.0", true)
    if Panel then return Panel.OpenFor(self) end
    local log = getLogger()
    if log then
        log:Warn(":OpenStandalone called but Cairn-SettingsPanel-2.0 is not loaded.")
    end
    return nil
end
stubProto.OpenStandalone = proto.OpenStandalone


-- Shared :OnChange. Returns an unsub closure rather than requiring the
-- consumer to track tokens — easier to use in addon-shutdown paths where
-- you just want to clean up everything at once via a list of closures.
local function onChange(self, key, fn, owner)
    if type(key) ~= "string" then
        error("Cairn-Settings:OnChange: 'key' must be a string", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn-Settings:OnChange: 'fn' must be a function", 2)
    end
    self._subs[key] = self._subs[key] or {}
    local sub = { fn = fn, owner = owner }
    local list = self._subs[key]
    list[#list + 1] = sub
    return function() sub.removed = true end
end
proto.OnChange     = onChange
stubProto.OnChange = onChange


-- ---------------------------------------------------------------------------
-- Schema → Blizzard panel rendering
-- ---------------------------------------------------------------------------

-- Each schema entry maps to one Blizzard panel widget (or none for storage-
-- only types). Wrapped in pcall by the caller so a single bad entry doesn't
-- prevent the rest of the panel from rendering — typical real-world failure
-- mode is "consumer typo'd a dropdown choices value" rather than an
-- across-the-board breakage.

local function registerEntry(self, entry)
    local key = entry.key

    if entry.type == "header" then
        if CreateSettingsListSectionHeaderInitializer and self._layout then
            local init = CreateSettingsListSectionHeaderInitializer(entry.label or key)
            self._layout:AddInitializer(init)
        end
        return
    end

    -- Storage-only types: schema validates them, defaults seed them, Get/Set/
    -- OnChange work — but no panel widget. Consumer renders their own UI.
    if entry.type == "text" or entry.type == "color" or entry.type == "keybind" then
        return
    end

    -- Real settings backed by db.profile and exposed to Blizzard's Settings
    -- panel through a proxy setting. Variable name namespaced per addon to
    -- avoid collision in Blizzard's global setting registry.
    local variableName = "Cairn_" .. self._addonName .. "_" .. key

    local varType
    if entry.type == "toggle" then
        varType = Settings.VarType.Boolean
    elseif entry.type == "range" then
        varType = Settings.VarType.Number
    elseif entry.type == "dropdown" then
        varType = (type(entry.default) == "number")
            and Settings.VarType.Number
            or Settings.VarType.String
    end

    local setting = Settings.RegisterProxySetting(
        self._category, variableName, varType, entry.label or key, entry.default,
        function() return self._db.profile[key] end,
        function(_, value) setValue(self, key, value) end
    )

    if entry.type == "toggle" then
        Settings.CreateCheckbox(self._category, setting, entry.tooltip)
    elseif entry.type == "range" then
        local opts = Settings.CreateSliderOptions(entry.min or 0, entry.max or 1, entry.step or 0.1)
        if MinimalSliderWithSteppersMixin and opts.SetLabelFormatter then
            opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(self._category, setting, opts, entry.tooltip)
    elseif entry.type == "dropdown" then
        Settings.CreateDropdown(self._category, setting, function()
            local container = Settings.CreateControlTextContainer()
            -- Sort labels deterministically so the dropdown doesn't shuffle
            -- across runs (pairs() order isn't stable).
            local items = {}
            for value, label in pairs(entry.choices) do
                items[#items + 1] = { value = value, label = label }
            end
            table.sort(items, function(a, b) return tostring(a.label) < tostring(b.label) end)
            for _, p in ipairs(items) do container:Add(p.value, p.label) end
            return container:GetData()
        end, entry.tooltip)
    end
end


-- ---------------------------------------------------------------------------
-- Public API: constructor
-- ---------------------------------------------------------------------------

-- Per the lib header: db must be a Cairn-DB instance (or any table with a
-- .profile sub-table) that's been created BEFORE this call. Since
-- SavedVariables load before consumer .lua files run, calling :New at file
-- scope is safe IF the consumer's TOC declared the SavedVariables. Document;
-- can't enforce.
function Cairn_Settings:New(addonName, db, schema)
    if type(addonName) ~= "string" or addonName == "" then
        error("Cairn-Settings:New: addonName must be a non-empty string", 2)
    end
    if type(db) ~= "table" or type(db.profile) ~= "table" then
        error("Cairn-Settings:New: db must be a Cairn-DB instance with .profile (call after the DB exists)", 2)
    end
    validateSchema(schema)
    seedDefaults(db, schema)

    local byKey = {}
    for _, entry in ipairs(schema) do
        byKey[entry.key] = entry
    end

    local self = {
        _addonName = addonName,
        _db        = db,
        _schema    = schema,
        _byKey     = byKey,
        _subs      = {},
    }

    Cairn_Settings.instances[self] = addonName

    -- Stub mode when Blizzard's Settings global isn't loaded. This is the
    -- Classic-flavor compatibility path — those clients pre-date the
    -- Dragonflight Settings API. Storage and subscribers still work.
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
        local log = getLogger()
        if log then
            log:Warn("Blizzard Settings API not available; returning Get/Set-only stub for %s.", addonName)
        end
        setmetatable(self, stubProto)
        return self
    end

    local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
    self._category   = category
    self._layout     = layout
    self._categoryID = category and category:GetID() or nil

    setmetatable(self, proto)

    for _, entry in ipairs(schema) do
        local ok, err = pcall(registerEntry, self, entry)
        if not ok then
            local log = getLogger()
            if log then
                log:Error("Failed to register schema entry '%s': %s", entry.key, tostring(err))
            else
                geterrorhandler()(err)
            end
        end
    end

    Settings.RegisterAddOnCategory(category)

    local log = getLogger()
    if log then
        log:Info("Registered settings category for %s (%d entries)", addonName, #schema)
    end

    return self
end


-- Convenience: `LibStub("Cairn-Settings-1.0")(name, db, schema)` works without
-- the explicit :New, matching the lib's v1 ergonomics. Doesn't change the
-- behavior — just the call-site shape preference.
setmetatable(Cairn_Settings, { __call = function(self, name, db, schema)
    return self:New(name, db, schema)
end })


return Cairn_Settings
