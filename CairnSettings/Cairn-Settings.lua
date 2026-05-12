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
--   key            string   required, unique within this addon's schema
--   type           string   required, one of:
--                           toggle | range | dropdown | header   (rendered)
--                           text | color | keybind               (storage-only)
--   label          string   required, user-facing display label
--   default        any      required EXCEPT for type="header"; seeded into db.profile
--   tooltip        string   optional, hover text on the rendered control
--   onChange       function optional, called as fn(newValue, oldValue) after change
--
-- Cluster A additions (locked 2026-05-12):
--   disableif      function optional, fn(get) → bool. Re-evaluated after every
--                           setValue. `get(siblingKey)` reads current sibling
--                           values. Truthy return disables the widget visually
--                           (Blizzard panel best-effort) and fires the
--                           :OnDisableStateChanged callback for renderers that
--                           handle visual disable themselves.
--   disabled       bool     optional static-disable shorthand for the truly-
--                           constant case (a setting that's always disabled).
--   tags           {string} optional array of search tags. Each tag is added
--                           to the widget via initializer:AddSearchTags so the
--                           Blizzard panel search bar finds the widget by tag.
--                           The widget's `label` is also auto-added as a tag.
--   namePhraseId   string   optional Cairn-Locale phrase ID. When set AND
--                           Cairn-Locale is loaded, the resolved phrase WINS
--                           over `label` at panel-build time.
--   descPhraseId   string   optional Cairn-Locale phrase ID. Same as above
--                           for `tooltip`.
--
-- Cluster E additions (locked 2026-05-12):
--   subSettings    array    optional array of child schema entries that
--                           visually nest below the parent and auto-lock
--                           when the parent's value is falsy. Same flat
--                           key namespace as top-level entries (children
--                           are NOT scoped under the parent key).
--                           See `subSettingsModifiable` to override the
--                           parent-lock predicate.
--   subSettingsModifiable
--                  function optional, fn(get) -> bool. When set, replaces
--                           the default parent-truthy predicate for child
--                           enable state. Returns true when children
--                           should be enabled (modifiable).
--
-- :New opts (MINOR 17):
--   opts.layout    string   "vertical" (default) builds a schema-driven
--                           panel. "canvas" registers a canvas-layout
--                           category with the consumer-supplied frame and
--                           skips schema-based rendering (consumer renders
--                           into their own frame). Storage / Get / Set /
--                           OnChange still flow through the schema either
--                           way. Decision 37.
--   opts.frame     Frame    required when opts.layout = "canvas". The
--                           consumer-owned panel frame to register.
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
--   s:OnChange(key, fn, owner) -> unsub fn        -- subscribe to value change
--   s:Open()                                      -- open Blizzard panel
--   s:OpenStandalone()                            -- open Cairn-SettingsPanel-2.0 renderer
--   s:GetCategory()                               -- Blizzard category object (or nil)
--   s:GetCategoryID()                             -- Blizzard category ID (or nil)
--   s:GetWidgetsByType(kind)                      -- array of {entry, setting,
--                                                    initializer} for entries
--                                                    matching kind. Cluster A
--                                                    Decision 4.
--   s:OnDisableStateChanged(fn) -> unsub fn       -- subscribe to disableif
--                                                    state transitions. Cluster
--                                                    A Decision 1 supporting
--                                                    surface.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Settings-1.0"
local LIB_MINOR = 17

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


-- Cairn-Locale is a SOFT dependency for the phrase-ID resolution path
-- (Cluster A Decision 3). When loaded, entry.namePhraseId / descPhraseId
-- resolve through it at panel-build time so locale-bank updates pick up
-- on next panel-open without consumers rebuilding. When absent, the
-- direct label/tooltip fields are used unchanged.
local function getLocale()
    local L = LibStub and LibStub("Cairn-Locale-1.0", true)
    return L
end


-- resolvePhrase(entry, addonName, fieldDirect, fieldId)
--
-- Returns the display string for `entry`:
--   * if `entry[fieldId]` is set AND Cairn-Locale is loaded AND
--     `Cairn-Locale:GetPhrase(addonName, phraseId)` returns a string →
--     use the locale-bank value.
--   * else fall back to `entry[fieldDirect]`.
--   * else return nil (caller decides what to do with nil).
--
-- Per Decision 3: phrase IDs win when both are present. Direct strings
-- stay for English-only consumers and quick prototypes.
--
-- Note: `Cairn-Locale:GetPhrase` (NOT the instance-level `L:Get`) is the
-- right entry point — the lib-level method returns nil on total miss so
-- we can fall through to the direct field, whereas the instance method
-- returns the key itself defensively (good for direct UI use, bad for
-- detect-miss-and-fall-through callers like this one).
local function resolvePhrase(entry, addonName, fieldDirect, fieldId)
    local phraseId = entry[fieldId]
    if type(phraseId) == "string" then
        local L = getLocale()
        if L and type(L.GetPhrase) == "function" then
            local ok, value = pcall(L.GetPhrase, L, addonName, phraseId)
            if ok and type(value) == "string" then return value end
        end
    end
    return entry[fieldDirect]
end


-- Control-type registry (Cluster E Decision 27 — locked 2026-05-12).
--
-- Each entry is a metadata table describing what the schema accepts for
-- that control kind. Lib-internal kinds use this to validate + dispatch
-- registerEntry. Consumer-extended kinds (via :RegisterControl, Decision
-- 34) also land here.
--
-- Spec fields:
--   storageOnly = bool      -- skip Blizzard-panel rendering; just storage
--   skipDefault = bool      -- type doesn't require a `default` field
--                              (e.g. `header` is purely decorative)
--   requireArguments = {}   -- map of fieldName -> requirement.
--                              MINOR 17 (Decision 30): full declarative
--                              shape validation. Each requirement is one
--                              of:
--                                * type string ("number"/"string"/"table"
--                                  /"boolean"/"function")
--                                * { type = "<type>", optional = true }
--                                  table for optional fields
--                                * predicate function(value, entry) -> bool, errMsg
--                              Built-in types ship their existing checks
--                              expressed in this shape so the inline
--                              if-elseif validation in validateSchema can
--                              start consuming the registry uniformly.
--                              Consumer-registered types validate via the
--                              same path with zero special-casing.
Cairn_Settings.controlTypes = Cairn_Settings.controlTypes or {
    toggle   = { storageOnly = false },
    range    = { storageOnly = false,
                 -- min/max/step are technically optional (defaults 0/1/0.1)
                 -- but when supplied must be numbers. Predicate form so
                 -- "absent" is acceptable.
                 requireArguments = {
                     min  = { type = "number", optional = true },
                     max  = { type = "number", optional = true },
                     step = { type = "number", optional = true },
                 } },
    dropdown = { storageOnly = false,
                 requireArguments = { choices = "table" } },
    header   = { storageOnly = false, skipDefault = true },
    text     = { storageOnly = true  },
    color    = { storageOnly = true  },
    keybind  = { storageOnly = true  },
}

local function isSupportedType(kind)
    return Cairn_Settings.controlTypes[kind] ~= nil
end


-- Cluster E Decision 30 — validate per-control-type requirements
-- declaratively. Walks the controlTypes[type].requireArguments map for
-- the entry's type and reports the first failure via error(). Built-in
-- types use this path uniformly with consumer-registered types.
--
-- Returns true on success. Calls error() with a clear message on first
-- violation (consistent with the rest of validateSchema's strict-on-bad-
-- shape posture).
local function validateRequireArguments(entry)
    local spec = Cairn_Settings.controlTypes[entry.type]
    if not spec then return true end
    local req = spec.requireArguments
    if type(req) ~= "table" then return true end

    for fieldName, requirement in pairs(req) do
        local value = entry[fieldName]
        if type(requirement) == "string" then
            -- Simple shape: required field of given Lua type.
            if type(value) ~= requirement then
                error("Cairn-Settings:New: entry '" .. tostring(entry.key) ..
                      "' (" .. entry.type .. ") requires field '" .. fieldName ..
                      "' of type " .. requirement ..
                      " (got " .. type(value) .. ")", 4)
            end
        elseif type(requirement) == "table" then
            -- Compound: { type = "...", optional = true|false }
            local expected = requirement.type
            local optional = requirement.optional
            if value == nil then
                if not optional then
                    error("Cairn-Settings:New: entry '" .. tostring(entry.key) ..
                          "' (" .. entry.type .. ") requires field '" ..
                          fieldName .. "'", 4)
                end
            elseif type(expected) == "string" and type(value) ~= expected then
                error("Cairn-Settings:New: entry '" .. tostring(entry.key) ..
                      "' (" .. entry.type .. ") field '" .. fieldName ..
                      "' must be of type " .. expected ..
                      " (got " .. type(value) .. ")", 4)
            end
        elseif type(requirement) == "function" then
            -- Custom predicate. Receives (value, entry); returns (ok, errMsg).
            local ok, errMsg = requirement(value, entry)
            if not ok then
                error("Cairn-Settings:New: entry '" .. tostring(entry.key) ..
                      "' (" .. entry.type .. ") field '" .. fieldName ..
                      "' failed validation: " .. tostring(errMsg or "(no message)"), 4)
            end
        end
    end
    return true
end


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
        if not isSupportedType(entry.type) then
            error("Cairn-Settings:New: schema entry '" .. entry.key ..
                  "' has unsupported type: " .. tostring(entry.type), 3)
        end
        if seen[entry.key] then
            error("Cairn-Settings:New: duplicate schema key: " .. entry.key, 3)
        end
        seen[entry.key] = true

        local spec = Cairn_Settings.controlTypes[entry.type]
        if not (spec and spec.skipDefault) and entry.default == nil then
            error("Cairn-Settings:New: schema entry '" .. entry.key ..
                  "' requires a 'default' value", 3)
        end

        -- Cluster E Decision 30 — declarative requireArguments validation.
        -- Routes built-in and consumer-registered types through the same
        -- registry-driven path. The inline dropdown 'choices' check below
        -- is superseded by the registry entry for the `dropdown` type.
        validateRequireArguments(entry)

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

        -- Cluster A additions (locked 2026-05-12). All optional; type-checked
        -- here so a typo'd shape surfaces at :New() rather than at panel-build.
        if entry.disableif ~= nil and type(entry.disableif) ~= "function" then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-function 'disableif' (must be function or nil)", 3)
        end
        if entry.disabled ~= nil and type(entry.disabled) ~= "boolean" then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-boolean 'disabled' (must be boolean or nil)", 3)
        end
        if entry.tags ~= nil then
            if type(entry.tags) ~= "table" then
                error("Cairn-Settings:New: entry '" .. entry.key ..
                      "' has non-array 'tags' (must be array of strings)", 3)
            end
            for ti, tag in ipairs(entry.tags) do
                if type(tag) ~= "string" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' tag #" .. ti .. " must be a string", 3)
                end
            end
        end
        if entry.namePhraseId ~= nil and type(entry.namePhraseId) ~= "string" then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-string 'namePhraseId'", 3)
        end
        if entry.descPhraseId ~= nil and type(entry.descPhraseId) ~= "string" then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-string 'descPhraseId'", 3)
        end

        -- Cluster E Decision 35 additions (locked 2026-05-12). Three
        -- optional runtime predicates beyond disableif. Each accepts
        -- either a static bool/function depending on semantics:
        --
        --   isVisible    function -> bool   show/hide the widget entirely
        --                                   (vs disableif which just locks it)
        --   canSearch    bool OR function -> bool   gate search-tag inclusion
        --   newFeature   bool OR function -> bool   show Blizzard's NEW tag
        if entry.isVisible ~= nil and type(entry.isVisible) ~= "function" then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-function 'isVisible'", 3)
        end
        if entry.canSearch ~= nil
           and type(entry.canSearch) ~= "boolean"
           and type(entry.canSearch) ~= "function"
        then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has invalid 'canSearch' (must be bool, function, or nil)", 3)
        end
        if entry.newFeature ~= nil
           and type(entry.newFeature) ~= "boolean"
           and type(entry.newFeature) ~= "function"
        then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has invalid 'newFeature' (must be bool, function, or nil)", 3)
        end

        -- Cluster E Decision 29 — sub-settings. Optional array of child
        -- schema entries that visually nest below the parent control and
        -- auto-lock when the parent value is falsy. The parent-lock
        -- predicate defaults to "parent value is truthy"; consumer can
        -- override via `subSettingsModifiable = function(get) ... end`.
        --
        -- Sub-entries are full schema entries (same validation rules
        -- apply). They register in db.profile with the same flat key
        -- namespace as top-level entries — sub-settings are about VISUAL
        -- nesting and parent-lock, not about scoping the data.
        if entry.subSettings ~= nil then
            if type(entry.subSettings) ~= "table" then
                error("Cairn-Settings:New: entry '" .. entry.key ..
                      "' has non-array 'subSettings' (must be array of child entries)", 3)
            end
            for ci, child in ipairs(entry.subSettings) do
                if type(child) ~= "table" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' subSettings #" .. ci .. " must be a table", 3)
                end
                if type(child.key) ~= "string" or child.key == "" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' subSettings #" .. ci .. " missing 'key' (string)", 3)
                end
                if not isSupportedType(child.type) then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' subSettings '" .. child.key ..
                          "' has unsupported type: " .. tostring(child.type), 3)
                end
                if seen[child.key] then
                    error("Cairn-Settings:New: duplicate schema key (in subSettings): " ..
                          child.key, 3)
                end
                seen[child.key] = true
                local childSpec = Cairn_Settings.controlTypes[child.type]
                if not (childSpec and childSpec.skipDefault) and child.default == nil then
                    error("Cairn-Settings:New: subSettings entry '" .. child.key ..
                          "' requires a 'default' value", 3)
                end
                -- Per-shape declarative validation on the child too.
                validateRequireArguments(child)
            end
        end
        if entry.subSettingsModifiable ~= nil
           and type(entry.subSettingsModifiable) ~= "function"
        then
            error("Cairn-Settings:New: entry '" .. entry.key ..
                  "' has non-function 'subSettingsModifiable'", 3)
        end
    end
end


-- Seed defaults into the consumer's DB. Header entries skipped (no value
-- to store). Only writes when the existing slot is nil so user data
-- survives across version upgrades — a consumer changing a default later
-- doesn't retroactively overwrite the user's saved value. Documented
-- explicitly because consumers WILL hit this and be confused.
--
-- MINOR 17 (Decision 29) — also walks `subSettings` arrays so child
-- entries get their defaults seeded the same way. Same flat key namespace
-- as top-level entries.
local function seedDefaults(db, schema)
    for _, entry in ipairs(schema) do
        if entry.type ~= "header" and db.profile[entry.key] == nil then
            db.profile[entry.key] = entry.default
        end
        if type(entry.subSettings) == "table" then
            for _, child in ipairs(entry.subSettings) do
                if child.type ~= "header" and db.profile[child.key] == nil then
                    db.profile[child.key] = child.default
                end
            end
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


-- Build a `get(siblingKey)` closure for disableif callbacks. Same `self`
-- captured; each call reads the current value via the existing :Get path
-- so callers always see the freshest data including in-flight writes.
local function makeGetter(self)
    return function(siblingKey) return self._db.profile[siblingKey] end
end


-- Cluster A Decision 1 — refresh disableif state for every entry that
-- declared a disableif callback. Called after each setValue (so changes
-- to one key can re-enable / re-disable any sibling). Pushes state into
-- two places:
--   1. Blizzard's initializer via :SetParentInitializer best-effort —
--      modern Settings panels respect the isModifiable callback to gray
--      controls out. Wrapped in pcall because not every Blizzard widget
--      template supports the call on every game version.
--   2. self._disableState[key] + fires _disableListeners — for
--      renderers (Cairn-SettingsPanel-2.0) that handle visual disable
--      themselves. Only fires on TRANSITIONS so listeners aren't spammed.
local function refreshDisableIf(self)
    local getter = makeGetter(self)
    local listeners = self._disableListeners
    for _, entry in ipairs(self._schema) do
        local fn = entry.disableif
        if type(fn) == "function" then
            local ok, disabled = pcall(fn, getter)
            if not ok then geterrorhandler()(disabled) end
            disabled = not not disabled  -- normalize to bool

            local prev = self._disableState[entry.key]
            if prev ~= disabled then
                self._disableState[entry.key] = disabled

                -- Best-effort Blizzard initializer state push. Different
                -- panel templates expose this differently; pcall so a
                -- template without :SetParentInitializer doesn't break the
                -- refresh loop for the rest.
                local init = self._initializers[entry.key]
                if init and type(init.SetParentInitializer) == "function" then
                    pcall(init.SetParentInitializer, init, nil, function() return not disabled end)
                end

                if listeners then
                    for i = 1, #listeners do
                        local sub = listeners[i]
                        if sub and not sub.removed then
                            local cbOk, cbErr = pcall(sub.fn, entry.key, disabled)
                            if not cbOk then geterrorhandler()(cbErr) end
                        end
                    end
                end
            end
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
    -- After every write, re-evaluate disableif callbacks so siblings can
    -- react to the change (Cluster A Decision 1). Cheap — typical N < 50.
    refreshDisableIf(self)
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


-- :GetWidgetsByType(kind) -> array
--
-- Cluster A Decision 4. Returns an array of {entry, setting, initializer}
-- tables for every schema entry whose type matches `kind`. Use cases:
--   * "reset all sliders to default" → walk, call :Set(entry.key, entry.default)
--   * "disable all toggles on combat enter" → walk, flip _disableState
--   * "highlight newly-added widgets" → walk, attach a glow to .initializer
--
-- stubProto returns entry refs only — setting and initializer are nil in
-- stub mode (no Blizzard panel). Consumers introspecting in stub mode
-- still get the schema-level info for non-render-dependent operations.
--
-- Returns an empty array (not nil) when no entries match — callers can
-- iterate unconditionally.
local function getWidgetsByType(self, kind)
    local out = {}
    for _, entry in ipairs(self._schema) do
        if entry.type == kind then
            out[#out + 1] = {
                entry       = entry,
                setting     = self._settings     and self._settings[entry.key]     or nil,
                initializer = self._initializers and self._initializers[entry.key] or nil,
            }
        end
    end
    return out
end
proto.GetWidgetsByType     = getWidgetsByType
stubProto.GetWidgetsByType = getWidgetsByType


-- :OnDisableStateChanged(fn) -> unsub
--
-- Cluster A Decision 1 supporting surface. Subscribes a renderer (typically
-- Cairn-SettingsPanel-2.0 once it implements disableif visual support) to
-- per-widget disable-state changes. Callback shape: fn(key, isDisabled).
-- Fired by refreshDisableIf whenever a tracked disableif transitions.
-- Returns an unsub closure.
local function onDisableStateChanged(self, fn)
    if type(fn) ~= "function" then
        error("Cairn-Settings:OnDisableStateChanged: 'fn' must be a function", 2)
    end
    self._disableListeners = self._disableListeners or {}
    local sub = { fn = fn }
    self._disableListeners[#self._disableListeners + 1] = sub
    return function() sub.removed = true end
end
proto.OnDisableStateChanged     = onDisableStateChanged
stubProto.OnDisableStateChanged = onDisableStateChanged


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

-- Apply Cluster A enhancements (tags, post-create hooks) to a freshly-
-- created initializer. Decision 2 + Decision 36 — explicit `entry.tags`
-- contribute searchTags; if `entry.tags` is absent the label itself is
-- auto-added so the search bar finds the widget by its visible name.
-- Decision 36's auto-add applies regardless of explicit tags (consumers
-- get both).
local function applySearchTags(initializer, entry, displayLabel)
    if type(initializer) ~= "table" then return end
    if type(initializer.AddSearchTags) ~= "function" then return end

    if type(displayLabel) == "string" and displayLabel ~= "" then
        initializer:AddSearchTags(displayLabel)
    end

    if type(entry.tags) == "table" then
        for _, tag in ipairs(entry.tags) do
            if type(tag) == "string" and tag ~= "" then
                initializer:AddSearchTags(tag)
            end
        end
    end
end


local function registerEntry(self, entry)
    local key = entry.key
    local label   = resolvePhrase(entry, self._addonName, "label",   "namePhraseId")
                 or key
    local tooltip = resolvePhrase(entry, self._addonName, "tooltip", "descPhraseId")

    if entry.type == "header" then
        if CreateSettingsListSectionHeaderInitializer and self._layout then
            local init = CreateSettingsListSectionHeaderInitializer(label)
            self._layout:AddInitializer(init)
            self._initializers[key] = init
            applySearchTags(init, entry, label)
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
        self._category, variableName, varType, label, entry.default,
        function() return self._db.profile[key] end,
        function(_, value) setValue(self, key, value) end
    )
    self._settings[key] = setting

    -- Each Settings.Create* call returns the initializer; we capture it so
    -- :GetWidgetsByType + refreshDisableIf can reach it later.
    local init
    if entry.type == "toggle" then
        init = Settings.CreateCheckbox(self._category, setting, tooltip)
    elseif entry.type == "range" then
        local opts = Settings.CreateSliderOptions(entry.min or 0, entry.max or 1, entry.step or 0.1)
        if MinimalSliderWithSteppersMixin and opts.SetLabelFormatter then
            opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        init = Settings.CreateSlider(self._category, setting, opts, tooltip)
    elseif entry.type == "dropdown" then
        init = Settings.CreateDropdown(self._category, setting, function()
            local container = Settings.CreateControlTextContainer()
            -- Sort labels deterministically so the dropdown doesn't shuffle
            -- across runs (pairs() order isn't stable).
            local items = {}
            for value, lbl in pairs(entry.choices) do
                items[#items + 1] = { value = value, label = lbl }
            end
            table.sort(items, function(a, b) return tostring(a.label) < tostring(b.label) end)
            for _, p in ipairs(items) do container:Add(p.value, p.label) end
            return container:GetData()
        end, tooltip)
    end

    self._initializers[key] = init
    applySearchTags(init, entry, label)

    -- Cluster E Decision 29 — render sub-settings nested under this parent.
    -- Each child becomes its own panel row with `SetParentInitializer`
    -- wiring so the child auto-locks when the parent value is falsy
    -- (default predicate). Consumer can override with
    -- `entry.subSettingsModifiable = function(get) -> bool` for multi-
    -- condition locks (parent on AND sibling X in state Y).
    if type(entry.subSettings) == "table" and init then
        local parentInit = init
        local parentSetting = setting
        local customModifiable = entry.subSettingsModifiable
        local getter = makeGetter(self)

        -- Per-child closure capturing parent for SetParentInitializer.
        -- `isModifiable` returns TRUE when child should be enabled; that's
        -- the inverse of disabled. Default predicate: parent value is
        -- truthy. Closure reads through getter so the latest value wins
        -- on each Blizzard refresh.
        local function defaultModifiable()
            return not not getter(entry.key)
        end
        local modifiableFn
        if type(customModifiable) == "function" then
            modifiableFn = function() return not not customModifiable(getter) end
        else
            modifiableFn = defaultModifiable
        end

        for _, child in ipairs(entry.subSettings) do
            -- registerEntry treats child as a top-level entry; the
            -- SetParentInitializer wiring after-the-fact creates the
            -- visual nesting and lock.
            local ok, err = pcall(registerEntry, self, child)
            if not ok then
                local log = getLogger()
                if log then
                    log:Error("Failed to register subSettings child '%s': %s",
                              child.key, tostring(err))
                end
            else
                local childInit = self._initializers[child.key]
                if childInit and type(childInit.SetParentInitializer) == "function" then
                    pcall(childInit.SetParentInitializer, childInit, parentInit, modifiableFn)
                end
            end
        end
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
function Cairn_Settings:New(addonName, db, schema, opts)
    if type(addonName) ~= "string" or addonName == "" then
        error("Cairn-Settings:New: addonName must be a non-empty string", 2)
    end
    if type(db) ~= "table" or type(db.profile) ~= "table" then
        error("Cairn-Settings:New: db must be a Cairn-DB instance with .profile (call after the DB exists)", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("Cairn-Settings:New: opts must be a table or nil", 2)
    end
    -- Cluster E Decision 37 — layout dispatch. "vertical" (default) builds
    -- a schema-driven panel; "canvas" hands the consumer a Blizzard-managed
    -- frame they own entirely. Schema validation + default seeding +
    -- Get/Set/OnChange still happen for canvas mode — the lib just doesn't
    -- render widgets from the schema.
    local layoutKind = opts and opts.layout or "vertical"
    if layoutKind ~= "vertical" and layoutKind ~= "canvas" then
        error("Cairn-Settings:New: opts.layout must be 'vertical' or 'canvas' (got "
              .. tostring(layoutKind) .. ")", 2)
    end
    validateSchema(schema)
    seedDefaults(db, schema)

    -- Flat by-key map across top-level entries AND subSettings children
    -- (Cluster E Decision 29). validateSchema already enforced key
    -- uniqueness across both namespaces so collisions can't reach here.
    local byKey = {}
    for _, entry in ipairs(schema) do
        byKey[entry.key] = entry
        if type(entry.subSettings) == "table" then
            for _, child in ipairs(entry.subSettings) do
                byKey[child.key] = child
            end
        end
    end

    local self = {
        _addonName        = addonName,
        _db               = db,
        _schema           = schema,
        _byKey            = byKey,
        _subs             = {},
        -- Initializer / setting refs captured in registerEntry. Used by
        -- :GetWidgetsByType (Cluster A Decision 4) and refreshDisableIf
        -- (Cluster A Decision 1).
        _initializers     = {},
        _settings         = {},
        -- disableif state map for renderers that handle visual disable
        -- themselves (Cairn-SettingsPanel-2.0). Mirrors what's pushed to
        -- Blizzard's initializers via SetParentInitializer best-effort.
        _disableState     = {},
        _disableListeners = {},
    }

    self._layoutKind = layoutKind

    Cairn_Settings.instances[self] = addonName

    -- Stub mode when Blizzard's Settings global isn't loaded. This is the
    -- Classic-flavor compatibility path — those clients pre-date the
    -- Dragonflight Settings API. Storage and subscribers still work.
    -- (Same path for both layout kinds — canvas/vertical only differ on
    -- modern clients where the factories exist.)
    if not (Settings
            and Settings.RegisterVerticalLayoutCategory
            and Settings.RegisterAddOnCategory) then
        local log = getLogger()
        if log then
            log:Warn("Blizzard Settings API not available; returning Get/Set-only stub for %s.", addonName)
        end
        setmetatable(self, stubProto)
        return self
    end

    -- Cluster E Decision 37 — canvas-vs-vertical category factory dispatch.
    -- Canvas mode requires a consumer-supplied panel frame; if missing we
    -- gracefully fall back to vertical and log a warning so consumers see
    -- the misuse without the panel breaking entirely.
    local category, layout
    if layoutKind == "canvas" then
        local frame = opts and opts.frame
        if frame and Settings.RegisterCanvasLayoutCategory then
            category = Settings.RegisterCanvasLayoutCategory(frame, addonName)
            layout   = nil  -- canvas categories don't expose a layout helper
        else
            local log = getLogger()
            if log then
                log:Warn("layout='canvas' requested but opts.frame missing or RegisterCanvasLayoutCategory unavailable — falling back to vertical for %s.", addonName)
            end
            self._layoutKind = "vertical"
            category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
        end
    else
        category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
    end
    self._category   = category
    self._layout     = layout
    self._categoryID = category and category:GetID() or nil

    setmetatable(self, proto)

    -- Canvas-mode panels don't render from the schema — the consumer owns
    -- the panel frame entirely. Storage / Get / Set / OnChange still work
    -- (validation + defaults seeded above). Skip the per-entry render walk.
    if self._layoutKind == "vertical" then
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
    end

    Settings.RegisterAddOnCategory(category)

    -- Register in the lib-level dual-keyed registry so :OpenToCategory
    -- can deep-link to this addon's panel via its addon name (and, in a
    -- future expansion, subName). Cluster E Decision 38.
    Cairn_Settings:_RegisterCategoryEntry(addonName, self)

    -- Seed initial disableif state so first-paint reflects the right
    -- disabled set. Wrapped via the normal refresh path (same code that
    -- fires on every subsequent setValue) so semantics stay consistent.
    refreshDisableIf(self)

    local log = getLogger()
    if log then
        log:Info("Registered settings category for %s (%d entries)", addonName, #schema)
    end

    return self
end


-- Convenience: `LibStub("Cairn-Settings-1.0")(name, db, schema [, opts])`
-- works without the explicit :New, matching the lib's v1 ergonomics.
-- Doesn't change the behavior — just the call-site shape preference.
-- MINOR 17: forwards optional `opts` arg (Decision 37 layout dispatch).
setmetatable(Cairn_Settings, { __call = function(self, name, db, schema, opts)
    return self:New(name, db, schema, opts)
end })


-- ---------------------------------------------------------------------------
-- :RegisterControl (Cluster E Decision 34)
-- ---------------------------------------------------------------------------
-- Public extension point. Consumers register custom control kinds into
-- Cairn_Settings.controlTypes from outside the lib without forking.
-- After registration, schemas using `type = <name>` validate against the
-- new entry's metadata. The corresponding registerEntry path stays
-- consumer-supplied via the spec's `buildFunction` (rendering remains
-- TODO — Cluster E Decision 27's full registry-driven dispatch isn't
-- yet wired through registerEntry; the controlTypes table provides the
-- VALIDATION half today, with build-function wiring deferred).
function Cairn_Settings:RegisterControl(name, spec)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Settings:RegisterControl: name must be a non-empty string", 2)
    end
    if spec ~= nil and type(spec) ~= "table" then
        error("Cairn-Settings:RegisterControl: spec must be a table or nil", 2)
    end
    self.controlTypes[name] = spec or { storageOnly = false }
    return self.controlTypes[name]
end


-- ---------------------------------------------------------------------------
-- :ModifiedClickOptions (Cluster E Decision 33)
-- ---------------------------------------------------------------------------
-- Returns pre-built ALT/CTRL/SHIFT/NONE dropdown choices for the
-- modifier-key configuration pattern. `mustChooseKey = true` excludes the
-- NONE entry — for cases where SOME modifier is required (e.g. action-bar
-- binding-edit dropdowns).
--
-- Output shape matches Cairn-Settings's `dropdown` widget choices: a
-- `{value = label}` table the consumer drops into their schema.
function Cairn_Settings:ModifiedClickOptions(mustChooseKey)
    local choices = {
        ALT   = "Alt",
        CTRL  = "Ctrl",
        SHIFT = "Shift",
    }
    if not mustChooseKey then choices.NONE = "None" end
    return choices
end


-- ---------------------------------------------------------------------------
-- Dual-keyed registry + :OpenToCategory (Cluster E Decision 38)
-- ---------------------------------------------------------------------------
-- Tracks registered Cairn-Settings instances keyed by their addon name
-- (and optionally a subcategory path), enabling deep-link slash commands:
--
--   /myaddon         -> :OpenToCategory("MyAddon")
--   /myaddon display -> :OpenToCategory("MyAddon", "Display")
--
-- The current `:New` path only registers under the addon name. Sub-
-- category registration is reserved for a future expansion (a `:NewSub`
-- method or a `subName` arg on `:New`); this Decision just nails down
-- the registry shape so consumers can deep-link to the main category
-- today and gain sub-category deep-linking transparently when it lands.

Cairn_Settings.registeredCategories = Cairn_Settings.registeredCategories or {}


-- Internal: called from :New (proto path) after Blizzard category
-- registration so the dual-keyed registry contains everything :New built.
function Cairn_Settings:_RegisterCategoryEntry(addonName, instance)
    self.registeredCategories[addonName] = instance
end


-- :OpenToCategory(addonName [, subName]) -> bool
--
-- Returns true when a category was found + opened, false otherwise.
-- subName joins with addonName via "." so subcategories registered as
-- `MyAddon.Display` (future shape) resolve naturally.
function Cairn_Settings:OpenToCategory(addonName, subName)
    if type(addonName) ~= "string" or addonName == "" then
        error("Cairn-Settings:OpenToCategory: addonName must be a non-empty string", 2)
    end
    local key = addonName
    if type(subName) == "string" and subName ~= "" then
        key = addonName .. "." .. subName
    end
    local instance = self.registeredCategories[key]
    if not instance then return false end

    if type(instance.Open) == "function" then
        instance:Open()
        return true
    end
    return false
end


return Cairn_Settings
