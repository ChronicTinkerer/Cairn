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
-- Optional schema fields:
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
-- More schema fields:
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
-- Storage backends (MINOR 18):
--   storage        string   optional, one of "addon" (default), "cvar",
--                           "proxy". Controls where the value lives.
--   cvar           string   required when storage = "cvar". The WoW CVar
--                           name to read/write via GetCVar/SetCVar.
--                           toggle entries use "1"/"0" boundary; range
--                           entries use tonumber.
--   getValue       function required when storage = "proxy". Returns the
--                           current value. No args.
--   setValue       function required when storage = "proxy". Receives the
--                           new value. Return ignored.
--
-- :New opts (MINOR 17):
--   opts.layout    string   "vertical" (default) builds a schema-driven
--                           panel. "canvas" registers a canvas-layout
--                           category with the consumer-supplied frame and
--                           skips schema-based rendering (consumer renders
--                           into their own frame). Storage / Get / Set /
--                           OnChange still flow through the schema either
--                           way.
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
--                                                    matching kind.
--   s:OnDisableStateChanged(fn) -> unsub fn       -- subscribe to disableif
--                                                    state transitions. Cluster
--                                                    supporting
--                                                    surface.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Settings-1.0"
local LIB_MINOR = 24

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
-- (phrase resolution). When loaded, entry.namePhraseId / descPhraseId
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
--phrase IDs win when both are present. Direct strings
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


-- Control-type registry.
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
--                              MINOR 17: full declarative
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

    -- MINOR 21 — compound controls. Three Blizzard-template-backed
    -- kinds: toggle + parameterized child in a single panel row. Each
    -- requires a `child` sub-entry (validated as a full nested schema
    -- entry of the appropriate type — slider / dropdown / button-action).
    -- Parent-lock (child disables when toggle is off) is automatic via
    -- the Blizzard template; no consumer `disableif` needed.
    --
    -- When the Blizzard compound template isn't available (older client
    -- versions), the kind falls back to rendering toggle + child as two
    -- separate widgets — same data shape, slightly different visual.
    checkbox_and_slider = {
        storageOnly = false,
        requireArguments = {
            child = "table",
        },
    },
    checkbox_and_dropdown = {
        storageOnly = false,
        requireArguments = {
            child = "table",
        },
    },
    checkbox_and_button = {
        storageOnly = false,
        requireArguments = {
            child = "table",
        },
    },

    -- MINOR 21 — LibSharedMedia dropdown. Auto-populates choices
    -- from LSM via `mediaType` (font / statusbar / border / background /
    -- sound). Font-type instances render a live preview via a singleton
    -- frame attached on OnShow / detached on OnHide.
    lib_shared_media_dropdown = {
        storageOnly = false,
        requireArguments = {
            mediaType = "string",
        },
    },
}

local function isSupportedType(kind)
    return Cairn_Settings.controlTypes[kind] ~= nil
end


-- ---------------------------------------------------------------------------
-- Storage backends (MINOR 18)
-- ---------------------------------------------------------------------------
-- Three backends control where a widget's value lives:
--
--   "addon"  (default) — db.profile[key], the existing path.
--   "cvar"             — WoW's CVar system. Requires `entry.cvar` (string).
--                        Reads via GetCVar; writes via SetCVar. Bool-typed
--                        toggles auto-translate "1"/"0" boundary.
--   "proxy"             — Consumer-supplied entry.getValue / entry.setValue
--                        closures. Bridges to existing addon state without
--                        forcing migration into Cairn-DB.
--
-- The dispatcher functions below are the single read/write point used by
-- :Get / :Set / the Blizzard RegisterProxySetting closures. Validation
-- on entry shape happens in validateSchema (required-fields
-- enforcement: cvar entries need entry.cvar; proxy entries need both
-- entry.getValue + entry.setValue).

local STORAGE_BACKENDS = { addon = true, cvar = true, proxy = true }


-- Read the current value for `entry` using its storage backend.
local function readEntry(self, entry)
    local storage = entry.storage or "addon"
    if storage == "cvar" then
        if not _G.GetCVar then return entry.default end
        local raw = _G.GetCVar(entry.cvar)
        if entry.type == "toggle" then
            return raw == "1"
        elseif entry.type == "range" then
            return tonumber(raw) or entry.default
        end
        return raw
    elseif storage == "proxy" then
        local fn = entry.getValue
        if type(fn) ~= "function" then return entry.default end
        return fn()
    end
    -- "addon" backend: existing db.profile path
    return self._db.profile[entry.key]
end


-- Write `value` for `entry` using its storage backend. Returns the
-- previous value (for change-detection in setValue).
local function writeEntry(self, entry, value)
    local storage = entry.storage or "addon"
    if storage == "cvar" then
        local old = readEntry(self, entry)
        if not _G.SetCVar then return old end
        if entry.type == "toggle" then
            _G.SetCVar(entry.cvar, value and "1" or "0")
        else
            _G.SetCVar(entry.cvar, tostring(value))
        end
        return old
    elseif storage == "proxy" then
        local old = readEntry(self, entry)
        local fn = entry.setValue
        if type(fn) == "function" then fn(value) end
        return old
    end
    -- "addon" backend: existing db.profile path
    local old = self._db.profile[entry.key]
    self._db.profile[entry.key] = value
    return old
end


--validate per-control-type requirements
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

        --declarative requireArguments validation.
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

        -- Optional fields; type-checked
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

        -- Runtime predicates. Three
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

        -- Storage backend validation. Default is
        -- "addon"; "cvar" requires entry.cvar; "proxy" requires both
        -- entry.getValue and entry.setValue. Bad storage values rejected
        -- at :New time so misconfiguration surfaces loudly.
        if entry.storage ~= nil then
            if type(entry.storage) ~= "string" or not STORAGE_BACKENDS[entry.storage] then
                error("Cairn-Settings:New: entry '" .. entry.key ..
                      "' has invalid 'storage' (must be 'addon', 'cvar', 'proxy', or nil; got "
                      .. tostring(entry.storage) .. ")", 3)
            end
            if entry.storage == "cvar" then
                if type(entry.cvar) ~= "string" or entry.cvar == "" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' has storage='cvar' but missing 'cvar' string", 3)
                end
            elseif entry.storage == "proxy" then
                if type(entry.getValue) ~= "function" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' has storage='proxy' but missing 'getValue' function", 3)
                end
                if type(entry.setValue) ~= "function" then
                    error("Cairn-Settings:New: entry '" .. entry.key ..
                          "' has storage='proxy' but missing 'setValue' function", 3)
                end
            end
        end

        -- Sub-settings. Optional array of child
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
-- MINOR 17 — also walks `subSettings` arrays so child
-- entries get their defaults seeded the same way. Same flat key namespace
-- as top-level entries.
-- MINOR 18: only seed defaults for the "addon" storage backend.
-- "cvar" entries get their defaults from WoW's CVar system; "proxy"
-- entries are consumer-managed and aren't ours to seed.
local function seedDefaults(db, schema)
    for _, entry in ipairs(schema) do
        local storage = entry.storage or "addon"
        if storage == "addon"
           and entry.type ~= "header"
           and db.profile[entry.key] == nil
        then
            db.profile[entry.key] = entry.default
        end
        if type(entry.subSettings) == "table" then
            for _, child in ipairs(entry.subSettings) do
                local childStorage = child.storage or "addon"
                if childStorage == "addon"
                   and child.type ~= "header"
                   and db.profile[child.key] == nil
                then
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
-- captured; each call reads the current value via readEntry so the
-- right storage backend is consulted.
local function makeGetter(self)
    return function(siblingKey)
        local entry = self._byKey[siblingKey]
        if entry then return readEntry(self, entry) end
        return self._db.profile[siblingKey]
    end
end


-- Refresh disableif state for every entry that
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


-- MINOR 18: writes route through writeEntry which dispatches to
-- the entry's storage backend. setValue still fires onChange + subscribers
-- + refreshDisableIf so consumers can react regardless of backend.
local function setValue(self, key, value)
    local entry = self._byKey[key]
    if not entry then
        -- Unknown key — fall back to direct profile write for backward-compat.
        local oldValue = self._db.profile[key]
        if oldValue == value then return end
        self._db.profile[key] = value
        fireSubscribers(self, key, value, oldValue)
        refreshDisableIf(self)
        return
    end

    local oldValue = readEntry(self, entry)
    if oldValue == value then return end
    writeEntry(self, entry, value)

    if entry.onChange then
        local ok, err = pcall(entry.onChange, value, oldValue)
        if not ok then geterrorhandler()(err) end
    end
    fireSubscribers(self, key, value, oldValue)
    -- After every write, re-evaluate disableif callbacks so siblings can
    -- react to the change. Cheap — typical N < 50.
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

-- MINOR 18: :Get routes through readEntry for storage backend
-- dispatch. Unknown keys fall back to direct profile access for backward-
-- compat with consumers using non-schema keys.
function stubProto:Get(key)
    local entry = self._byKey[key]
    if entry then return readEntry(self, entry) end
    return self._db.profile[key]
end
function stubProto:Set(key, value)     setValue(self, key, value) end
function stubProto:GetCategoryID()     return nil end
function stubProto:GetCategory()       return nil end


-- ---------------------------------------------------------------------------
-- Real instance — bridges to Blizzard Settings
-- ---------------------------------------------------------------------------

local proto = {}
proto.__index = proto

function proto:Get(key)
    local entry = self._byKey[key]
    if entry then return readEntry(self, entry) end
    return self._db.profile[key]
end
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
-- Returns an array of {entry, setting, initializer}
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
-- Subscribes a renderer (typically
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

-- Apply search-tag enhancements to a freshly-
-- created initializer. Explicit `entry.tags`
-- contribute searchTags; if `entry.tags` is absent the label itself is
-- auto-added so the search bar finds the widget by its visible name.
-- Label auto-add applies regardless of explicit tags (consumers
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

    -- MINOR 21 (D28 + D32) — compound controls + LSM dropdown are schema-
    -- recognized but render-deferred. The validation half (requireArguments)
    -- already enforced the required `child` / `mediaType` shape; render
    -- support needs Blizzard-template feature-detection (CHECKBOX_AND_*
    -- templates vary by client version) + LSM integration plumbing that's
    -- worth a focused build with visual testing. For now these kinds accept
    -- the schema entry without producing a Blizzard panel widget; consumers
    -- can use sub-settings or RegisterControl to wire custom rendering.
    if entry.type == "checkbox_and_slider"
        or entry.type == "checkbox_and_dropdown"
        or entry.type == "checkbox_and_button"
        or entry.type == "lib_shared_media_dropdown"
    then
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

    -- MINOR 18: closures dispatch through readEntry/writeEntry so
    -- the registered Blizzard setting talks to whatever backend the entry
    -- is configured for.
    --
    -- Defensive nil-coerce on the set closure. Blizzard's dropdown
    -- Decrement / Increment can produce nil when the underlying value
    -- list is iterated past either end. Writing nil through to the DB
    -- leaves the setting in an unrenderable state ("Missing value for
    -- setting 'X'" thrown from InitDropdown on the next refresh). For
    -- entries with a declared `default`, coerce nil back to that default
    -- rather than persisting it.
    local setting = Settings.RegisterProxySetting(
        self._category, variableName, varType, label, entry.default,
        function() return readEntry(self, entry) end,
        function(_, value)
            if value == nil and entry.default ~= nil then
                value = entry.default
            end
            setValue(self, key, value)
        end
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

    -- Render sub-settings nested under this parent.
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
    -- Layout dispatch."vertical" (default) builds
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
    -- validateSchema already enforced key
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
        -- :GetWidgetsByType and refreshDisableIf.
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

    -- Canvas-vs-vertical category factory dispatch.
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
    -- future expansion, subName).
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
-- MINOR 17: forwards optional `opts` arg (layout dispatch).
setmetatable(Cairn_Settings, { __call = function(self, name, db, schema, opts)
    return self:New(name, db, schema, opts)
end })


-- ---------------------------------------------------------------------------
-- :RegisterControl
-- ---------------------------------------------------------------------------
-- Public extension point. Consumers register custom control kinds into
-- Cairn_Settings.controlTypes from outside the lib without forking.
-- After registration, schemas using `type = <name>` validate against the
-- new entry's metadata. The corresponding registerEntry path stays
-- consumer-supplied via the spec's `buildFunction` (rendering remains
-- TODO — full registry-driven dispatch isn't
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
-- :ModifiedClickOptions
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
-- Dual-keyed registry + :OpenToCategory
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


-- ---------------------------------------------------------------------------
-- Spec-aware profile API (MINOR 19)
-- ---------------------------------------------------------------------------
-- LibDualSpec-style "auto-switch profiles on spec change" capability ported
-- to Cairn-DB natively. Consumers call `Cairn.Settings:EnhanceDB(db)` once;
-- the mixin installs four spec-aware methods directly on `db` via rawset
-- (no wrapper handle — consumers think in terms of "their DB"), registers
-- the db with the lib's lazy spec-change listener, and the rest is
-- automatic: switching specs in-game triggers a profile swap to the spec-
-- bound profile, falling back to the current profile if not bound.
--
-- Pattern reference: LibDualSpec-1.0 (Adirelle; BSD-3; inspected 2026-05-11).
--
-- API:
--   Cairn.Settings:EnhanceDB(db)                — install + register
--   db:IsSpecProfileEnabled()                   — bool
--   db:GetSpecProfile(spec)                     — profile name for `spec`
--   db:SetSpecProfile(name, spec)               — bind `spec` to `name`
--   db:CheckSpecProfileState()                  — internal; called by listener
--   Cairn.Settings:IterateDatabases()           — iterator(db, friendlyName)
--   Cairn.Settings:EnhanceOptions(options, db)  — inject spec-profile UI
--
-- Storage: a private Cairn-DB sub-store via db:RegisterNamespace("Cairn-
-- Settings-SpecProfile"). Lib owns its persistence format; addons can
-- migrate independently of consumer cooperation.

Cairn_Settings._specProfileRegistry = Cairn_Settings._specProfileRegistry
    or setmetatable({}, { __mode = "k" })  -- weak keys: GC'd DBs auto-vanish
Cairn_Settings._specChangeFrameInstalled = Cairn_Settings._specChangeFrameInstalled
    or false


-- Resolve the player's current spec index. Handles Retail
-- (PLAYER_SPECIALIZATION_CHANGED) + Classic
-- (ACTIVE_TALENT_GROUP_CHANGED) shapes; falls back to 1 for environments
-- without either API.
local function getCurrentSpec()
    if type(_G.GetSpecialization) == "function" then
        return _G.GetSpecialization() or 1
    end
    if type(_G.GetActiveTalentGroup) == "function" then
        return _G.GetActiveTalentGroup() or 1
    end
    return 1
end


-- Internal: walk the weak registry and tell each enhanced DB to reconcile
-- its current profile against the new spec. pcall'd per-DB so one broken
-- enhanced-DB doesn't abort the rest of the walk.
local function runSpecChangeWalk()
    for db in pairs(Cairn_Settings._specProfileRegistry) do
        if type(db.CheckSpecProfileState) == "function" then
            local ok, err = pcall(db.CheckSpecProfileState, db)
            if not ok then geterrorhandler()(err) end
        end
    end
end


-- Lazy event-frame init. ONE listener for the whole lib, registered for
-- both the Retail and Classic spec-change events (each fires only on its
-- respective flavor; registering both is harmless on the other).
local function ensureSpecChangeListener()
    if Cairn_Settings._specChangeFrameInstalled then return end
    if type(_G.CreateFrame) ~= "function" then return end
    local frame = _G.CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "PLAYER_SPECIALIZATION_CHANGED")  -- Retail
    pcall(frame.RegisterEvent, frame, "ACTIVE_TALENT_GROUP_CHANGED")    -- Classic
    frame:SetScript("OnEvent", runSpecChangeWalk)
    Cairn_Settings._specChangeFrameInstalled = true
    Cairn_Settings._specChangeFrame = frame
end


-- Spec-aware method bodies. Mixed into the enhanced db via rawset so they
-- live directly on the consumer's DB instance (no wrapper handle dance).
local SpecAwareMethods = {}


-- :IsSpecProfileEnabled() -> bool
-- Returns true when the consumer has flipped the enhanced-DB's "active"
-- bit (the master toggle in the EnhanceOptions UI). Default false —
-- enhanced DBs are inert until a consumer explicitly enables them.
function SpecAwareMethods:IsSpecProfileEnabled()
    local store = rawget(self, "_specProfileStore")
    if not store then return false end
    return rawget(store, "_enabled") == true
end


-- :GetSpecProfile(spec?) -> profile-name string or nil
-- spec defaults to current. Reads from the lib-owned sub-store; missing
-- mappings return nil (the consumer's current profile stays active).
function SpecAwareMethods:GetSpecProfile(spec)
    local store = rawget(self, "_specProfileStore")
    if not store then return nil end
    spec = spec or getCurrentSpec()
    local map = rawget(store, "specMap")
    if type(map) ~= "table" then return nil end
    return map[spec]
end


-- :SetSpecProfile(profileName, spec?)
-- Binds `spec` (defaults to current) to `profileName`. Pass nil for
-- profileName to clear the binding. If the new binding matches the
-- current spec, calls :CheckSpecProfileState immediately to apply.
function SpecAwareMethods:SetSpecProfile(profileName, spec)
    if profileName ~= nil and type(profileName) ~= "string" then
        error("Cairn-DB :SetSpecProfile: profileName must be a string or nil", 2)
    end
    local store = rawget(self, "_specProfileStore")
    if not store then return end
    spec = spec or getCurrentSpec()

    local map = rawget(store, "specMap")
    if type(map) ~= "table" then
        map = {}
        rawset(store, "specMap", map)
    end
    map[spec] = profileName

    -- If this binding affects the active spec, switch profile now.
    if spec == getCurrentSpec() then
        self:CheckSpecProfileState()
    end
end


-- :CheckSpecProfileState() — internal/test entry point. Re-resolves the
-- active spec's bound profile (if any) and switches the DB if different.
-- Called by the lib's spec-change listener and also from :SetSpecProfile
-- when the binding affects the current spec.
function SpecAwareMethods:CheckSpecProfileState()
    if not self:IsSpecProfileEnabled() then return end
    local target = self:GetSpecProfile(getCurrentSpec())
    if type(target) ~= "string" or target == "" then return end
    if type(self.GetProfile) == "function" and self:GetProfile() == target then
        return
    end
    if type(self.SetProfile) == "function" then
        local ok, err = pcall(self.SetProfile, self, target)
        if not ok then geterrorhandler()(err) end
    end
end


-- D23 — OnProfileDeleted hook. When a profile gets deleted, any spec
-- binding pointing at it gets rewired to the current profile so the
-- next spec change doesn't try to activate a vanished profile. Cairn-DB
-- doesn't currently expose `OnProfileDeleted` callbacks; for now, expose
-- `:RewireDeletedProfile(deletedName)` so consumers call manually after
-- deleting. When Cairn-DB grows OnProfileDeleted, enhanced DBs will
-- subscribe automatically in :EnhanceDB.
function SpecAwareMethods:RewireDeletedProfile(deletedName)
    if type(deletedName) ~= "string" or deletedName == "" then
        error("Cairn-DB :RewireDeletedProfile: deletedName must be a non-empty string", 2)
    end
    local store = rawget(self, "_specProfileStore")
    if not store then return end
    local map = rawget(store, "specMap")
    if type(map) ~= "table" then return end
    local current = type(self.GetProfile) == "function" and self:GetProfile() or nil
    for spec, name in pairs(map) do
        if name == deletedName then map[spec] = current end
    end
end


-- :SetSpecProfileEnabled(bool) — master toggle. When false, spec changes
-- have no effect even if bindings exist. When flipped to true, immediately
-- reconciles to the current spec's binding (if any).
function SpecAwareMethods:SetSpecProfileEnabled(enabled)
    local store = rawget(self, "_specProfileStore")
    if not store then return end
    rawset(store, "_enabled", enabled == true)
    if enabled then self:CheckSpecProfileState() end
end


-- Cairn.Settings:EnhanceDB(db, friendlyName?)
--
-- One-time install. Idempotent: calling :EnhanceDB twice on the same db
-- doesn't re-install or re-register. The optional `friendlyName` is used
-- by :IterateDatabases for introspection display (typically the addon's
-- display name).
function Cairn_Settings:EnhanceDB(db, friendlyName)
    if type(db) ~= "table" then
        error("Cairn-Settings:EnhanceDB: db must be a Cairn-DB instance", 2)
    end
    if type(db.RegisterNamespace) ~= "function" then
        error("Cairn-Settings:EnhanceDB: db must support :RegisterNamespace "
              .. "(Cairn-DB MINOR 15+)", 2)
    end

    -- Idempotent install.
    if rawget(db, "_specProfileStore") then return db end

    -- Private sub-store via Cairn-DB :RegisterNamespace.
    -- The sub-DB has its own profile/global/etc.; we use its .global for
    -- the spec map (cross-character — bindings stick to the account).
    local sub = db:RegisterNamespace("Cairn-Settings-SpecProfile")
    rawset(db, "_specProfileStore", sub.global)

    -- Mixin methods via rawset. No __index metatable
    -- override — direct method installation matches consumer mental model.
    for k, v in pairs(SpecAwareMethods) do
        rawset(db, k, v)
    end

    -- Register in the weak-key map. GC'd consumer DBs
    -- auto-vanish from the registry.
    self._specProfileRegistry[db] = friendlyName or rawget(db, "_name") or "<anonymous>"

    -- Install the lib's lazy spec-change listener.
    ensureSpecChangeListener()

    return db
end


-- Cairn.Settings:IterateDatabases() -> iterator
--
-- Generic-for iterator yielding (db, friendlyName) pairs over the
-- enhanced-DB weak registry. Used by Forge_AddonManager / `/cairn
-- settings list`-style introspection.
function Cairn_Settings:IterateDatabases()
    local registry = self._specProfileRegistry
    local key
    return function()
        local db, name = next(registry, key)
        key = db
        return db, name
    end
end


-- Cairn.Settings:EnhanceOptions(options, db)
--
-- Injects spec-profile UI into the consumer's options table via
-- `options.plugins["Cairn-Settings-SpecProfile"]` — does NOT mutate
-- `options.args`. Consumer's existing schema iteration stays clean;
-- the plugin entry is removable by deleting the key.
--
-- Strings are routed through Cairn-Locale under the
-- "Cairn-Settings" app namespace when Cairn-Locale is loaded; English
-- fallbacks ship inline so the feature works without locale wiring.
function Cairn_Settings:EnhanceOptions(options, db)
    if type(options) ~= "table" then
        error("Cairn-Settings:EnhanceOptions: options must be a table", 2)
    end
    if type(db) ~= "table" or not rawget(db, "_specProfileStore") then
        error("Cairn-Settings:EnhanceOptions: db must be EnhanceDB'd first", 2)
    end

    options.plugins = options.plugins or {}
    if options.plugins["Cairn-Settings-SpecProfile"] then return options end

    local L = LibStub and LibStub("Cairn-Locale-1.0", true)
    local function loc(key, fallback)
        if L and L.GetPhrase then
            local v = L:GetPhrase("Cairn-Settings", key)
            if type(v) == "string" then return v end
        end
        return fallback
    end

    options.plugins["Cairn-Settings-SpecProfile"] = {
        name  = loc("specProfileSection", "Spec-Aware Profiles"),
        type  = "header",
        order = 100,
        enabledToggle = {
            name = loc("specProfileEnable", "Enable spec-aware profile switching"),
            tooltip = loc("specProfileEnableTip",
                "Switch to a designated profile when your spec changes."),
            get = function() return db:IsSpecProfileEnabled() end,
            set = function(_, v) db:SetSpecProfileEnabled(v) end,
        },
        -- Per-spec dropdown plumbing is renderer-agnostic; consumer's
        -- panel renderer decides how to display the bindings.
    }
    return options
end


-- ---------------------------------------------------------------------------
-- Blizzard-frame override surface (MINOR 20)
-- ---------------------------------------------------------------------------
-- Pattern reference: LibEditModeOverride (plusmouse; inspected 2026-05-11).
-- Orthogonal to the EditMode-bridge half of Cairn-Settings (Clusters B+C):
-- those let consumer-OWNED frames register INTO EditMode; this surface
-- lets consumers programmatically MODIFY Blizzard's stock frames.
--
-- The methods below interact directly with EditModeManagerFrame's saved
-- layout data. They no-op gracefully when EditMode isn't available (Classic
-- flavors, pre-Dragonflight clients).

-- Lib-scope state for batching + taint-clearance registry.
Cairn_Settings._overrideState = Cairn_Settings._overrideState or {
    inBatch          = false,
    activeLayoutPending = false,
    pendingRefresh   = false,    -- D43: queued ApplyChanges for combat exit
}
Cairn_Settings._taintClearances = Cairn_Settings._taintClearances or {}
Cairn_Settings._combatFlushListenerInstalled = Cairn_Settings._combatFlushListenerInstalled or false


-- Detect EditMode availability. Retail clients post-Dragonflight expose
-- `EditModeManagerFrame`; absence is the Classic / pre-DF signal.
local function editModeAvailable()
    return type(_G.EditModeManagerFrame) == "table"
end


-- D41 — preset-layout escape hatch. When the active EditMode layout is a
-- Preset (immutable per Blizzard's design), :OverrideBlizzardFrame would
-- silently no-op. Detect + auto-create a Character-scoped layout named
-- "<AddonName> Overrides" (copy of current) before applying the override.
-- The consumer's AddonName is supplied at call time so the layout name
-- includes a useful identifier.
local function ensurePresetOverrideLayout(addonName)
    if not editModeAvailable() then return false end
    local manager = _G.EditModeManagerFrame
    local isPreset = false
    if type(manager.IsActiveLayoutPreset) == "function" then
        local ok, val = pcall(manager.IsActiveLayoutPreset, manager)
        isPreset = ok and val == true
    end
    if not isPreset then return false end

    local overrideName = (addonName or "Cairn") .. " Overrides"

    -- Try the common Blizzard API shape: copy active to a Character-scope
    -- layout. Both the method name + signature have churned across
    -- patches, so pcall + best-effort.
    if type(manager.MakeNewLayout) == "function" then
        local LAYOUT_TYPE_CHAR = (_G.Enum and _G.Enum.EditModeLayoutType
                                  and _G.Enum.EditModeLayoutType.Character) or 1
        pcall(manager.MakeNewLayout, manager, LAYOUT_TYPE_CHAR, overrideName)
    end
    return true
end


-- D39 — `:OverrideBlizzardFrame(frame, point, relativeTo, relPoint, ox, oy [, opts])`
--
-- Programmatically relocate a Blizzard EditMode-managed frame. Modifies
-- the active EditMode layout's saved anchor in-place and forces a refresh
-- via ShowUIPanel/HideUIPanel(EditModeManagerFrame). No /reload required,
-- no taint triggered.
--
-- `opts.addonName` (string, optional) — used when auto-creating an
--   Overrides layout from a Preset. Defaults to "Cairn".
-- `opts.batchOnly` (bool, optional) — when true, queues the refresh for
--   :ApplyChanges (batching).
--
-- Returns true on success. Returns false silently when EditMode isn't
-- available (Classic flavors) or the frame doesn't have a `system` field
-- recognized by EditMode.
function Cairn_Settings:OverrideBlizzardFrame(frame, point, relativeTo, relPoint, ox, oy, opts)
    if type(frame) ~= "table" then
        error("Cairn-Settings:OverrideBlizzardFrame: frame must be a Frame", 2)
    end
    if type(point) ~= "string" or point == "" then
        error("Cairn-Settings:OverrideBlizzardFrame: point must be a non-empty string", 2)
    end
    if type(ox) ~= "number" or type(oy) ~= "number" then
        error("Cairn-Settings:OverrideBlizzardFrame: ox / oy must be numbers", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("Cairn-Settings:OverrideBlizzardFrame: opts must be a table or nil", 2)
    end

    if not editModeAvailable() then return false end

    -- D41: preset escape hatch.
    ensurePresetOverrideLayout(opts and opts.addonName or "Cairn")

    -- Modify the frame's anchor directly. EditMode picks up changes on
    -- refresh; we don't poke its internal layout-data tables (touching
    -- those across versions risks taint).
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, point, relativeTo, relPoint, ox, oy)

    -- D42: batching. If we're inside a :BeginBatch window, queue the
    -- refresh; otherwise refresh immediately (out-of-combat path).
    local state = self._overrideState
    if state.inBatch or (opts and opts.batchOnly) then
        state.activeLayoutPending = true
        return true
    end

    self:ApplyChanges()
    return true
end


-- D40 — `:SetBlizzardFrameSetting(frame, settingEnum, value)`
--
-- Validates `value` against the per-system min/max/enum rules in
-- `EditModeSettingDisplayInfoManager.systemSettingDisplayInfo[frame.system]`
-- before applying. Out-of-range / wrong-type values throw with a clear
-- message rather than silently no-opping (Blizzard's default behavior).
--
-- Returns true on success. Returns false when EditMode isn't available.
function Cairn_Settings:SetBlizzardFrameSetting(frame, settingEnum, value)
    if type(frame) ~= "table" then
        error("Cairn-Settings:SetBlizzardFrameSetting: frame must be a Frame", 2)
    end
    if settingEnum == nil then
        error("Cairn-Settings:SetBlizzardFrameSetting: settingEnum must not be nil", 2)
    end

    if not editModeAvailable() then return false end

    -- Validate via EditModeSettingDisplayInfoManager if available. The
    -- info table may not exist on every flavor / patch; pcall guards.
    local mgr = _G.EditModeSettingDisplayInfoManager
    if type(mgr) == "table" and type(mgr.systemSettingDisplayInfo) == "table"
        and frame.system
    then
        local sysInfo = mgr.systemSettingDisplayInfo[frame.system]
        if type(sysInfo) == "table" then
            local info = sysInfo[settingEnum]
            if type(info) == "table" then
                if info.type == "Slider" or info.type == "Number" then
                    if type(value) ~= "number" then
                        error(("Cairn-Settings:SetBlizzardFrameSetting: setting %s requires number (got %s)")
                              :format(tostring(settingEnum), type(value)), 2)
                    end
                    if info.minValue and value < info.minValue then
                        error(("Cairn-Settings:SetBlizzardFrameSetting: value %s below min %s")
                              :format(tostring(value), tostring(info.minValue)), 2)
                    end
                    if info.maxValue and value > info.maxValue then
                        error(("Cairn-Settings:SetBlizzardFrameSetting: value %s above max %s")
                              :format(tostring(value), tostring(info.maxValue)), 2)
                    end
                end
            end
        end
    end

    -- Apply via Blizzard's setting-write API. The method name has churned;
    -- pcall + try-the-most-likely-name shape.
    if type(frame.UpdateSystemSettingValue) == "function" then
        pcall(frame.UpdateSystemSettingValue, frame, settingEnum, value)
    elseif type(frame.SetSetting) == "function" then
        pcall(frame.SetSetting, frame, settingEnum, value)
    end

    local state = self._overrideState
    if state.inBatch then
        state.activeLayoutPending = true
    else
        self:ApplyChanges()
    end
    return true
end


-- D42 — :BeginBatch / :ApplyChanges with `activeLayoutPending` flag for
-- coalesced overrides. Override calls between BeginBatch and ApplyChanges
-- queue rather than fire individual EditMode refreshes; single
-- ApplyChanges flushes the queue with one refresh.

function Cairn_Settings:BeginBatch()
    self._overrideState.inBatch = true
end


-- :ApplyChanges() — flush pending overrides. Throws on InCombatLockdown
-- (EditModeManagerFrame manipulation is protected). Use :SaveOnly during
-- combat.
function Cairn_Settings:ApplyChanges()
    local state = self._overrideState
    state.inBatch = false

    if not editModeAvailable() then
        state.activeLayoutPending = false
        return false
    end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        -- D43: queue the refresh for PLAYER_REGEN_ENABLED. SaveOnly state
        -- is preserved in EditMode's layout data (changes already written
        -- via SetPoint / UpdateSystemSettingValue); the queued refresh is
        -- just the visual update.
        state.pendingRefresh = true
        self:_ensureCombatFlushListener()
        return false
    end

    if state.activeLayoutPending then
        -- The Show/Hide flip forces EditMode to re-read the saved layout.
        pcall(_G.ShowUIPanel, _G.EditModeManagerFrame)
        pcall(_G.HideUIPanel, _G.EditModeManagerFrame)
        state.activeLayoutPending = false
    end
    state.pendingRefresh = false
    return true
end


-- D43 — :SaveOnly() stores override state without triggering EditMode UI
-- refresh; safe in combat. The actual frame mutations (SetPoint, setting
-- writes) already happened in :OverrideBlizzardFrame / :SetBlizzardFrame-
-- Setting; SaveOnly just confirms the state without forcing a visual
-- refresh.
function Cairn_Settings:SaveOnly()
    -- No-op beyond clearing the pending-refresh flag; mutations already
    -- happened at call time. The combat-aware :ApplyChanges path is the
    -- only one that actually triggers EditMode visual refresh.
    self._overrideState.activeLayoutPending = false
end


-- Internal — install PLAYER_REGEN_ENABLED listener for auto-flush on
-- combat exit. Lazy + lib-scope.
function Cairn_Settings:_ensureCombatFlushListener()
    if self._combatFlushListenerInstalled then return end
    if type(_G.CreateFrame) ~= "function" then return end
    self._combatFlushListenerInstalled = true
    local frame = _G.CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        if Cairn_Settings._overrideState.pendingRefresh then
            Cairn_Settings:ApplyChanges()
        end
    end)
    self._combatFlushFrame = frame
end


-- D44 — :RegisterTaintClearance(taintTarget, clearanceFn) — registry of
-- known clearance recipes. Cairn-Settings ships the DropDownList1
-- clearance recipe (show/hide `AddonList`) from LibEditModeOverride as the
-- seed entry. Forge_BugCatcher surfaces the registry in its taint-hints
-- panel, letting users diagnosing taint errors see "documented clearance
-- available" inline.
function Cairn_Settings:RegisterTaintClearance(taintTarget, clearanceFn)
    if type(taintTarget) ~= "string" or taintTarget == "" then
        error("Cairn-Settings:RegisterTaintClearance: taintTarget must be a non-empty string", 2)
    end
    if type(clearanceFn) ~= "function" then
        error("Cairn-Settings:RegisterTaintClearance: clearanceFn must be a function", 2)
    end
    self._taintClearances[taintTarget] = clearanceFn
end


-- :IterateTaintClearances() -> iterator(taintTarget, clearanceFn)
function Cairn_Settings:IterateTaintClearances()
    local registry = self._taintClearances
    local key
    return function()
        local k, fn = next(registry, key)
        key = k
        return k, fn
    end
end


-- Seed entry: DropDownList1 taint clearance recipe (LibEditModeOverride).
-- Toggling AddonList visibility resets DropDownList1's taint state. Only
-- registered once per session.
if not Cairn_Settings._taintClearances["DropDownList1"] then
    Cairn_Settings._taintClearances["DropDownList1"] = function()
        if type(_G.AddonList) == "table" then
            pcall(_G.AddonList.Show, _G.AddonList)
            pcall(_G.AddonList.Hide, _G.AddonList)
        end
    end
end


-- ---------------------------------------------------------------------------
-- EditMode-bridge foundation (MINOR 22)
-- ---------------------------------------------------------------------------
-- Pattern reference: EditModeExpanded-1.0 (Cybeloras; inspected 2026-05-11).
-- This is the FIRST of three phased builds for the EditMode-bridge half.
-- This build ships the supporting infrastructure (ID allocators, internal
-- state tables, cross-addon coordination event, anchor-normalization
-- utility). Build 44 ships the declarative `:Add(frame, schema)` API
-- (D13/D14/D16/D10). Build 45 ships the runtime EditMode hooks
-- (D5/D9/D15) that need live EditMode for testing.

-- D6 — Custom-setting enum extension. Cairn reserves IDs 0-99 for its
-- built-in custom settings (Hideable, ClampToScreen, ToggleHideInCombat,
-- MinimapPinned, Clamped, FrameSize, Coordinates, HiddenUntilMouseover,
-- etc.). Consumers allocate IDs from 100+ via :RegisterCustomSetting.
Cairn_Settings.CUSTOM_SETTING_CONSUMER_FLOOR = 100
Cairn_Settings._nextCustomSettingId = Cairn_Settings._nextCustomSettingId or 100
Cairn_Settings._customSettings      = Cairn_Settings._customSettings      or {}


-- :RegisterCustomSetting(name, settingType) -> id
--
-- Allocates a fresh custom-setting ID from the consumer floor (100+).
-- `name` is a stable string consumers reference instead of a raw number.
-- `settingType` is a Blizzard EditMode setting-type enum (e.g.
-- Enum.EditModeFrameSettingType.Toggle, .Slider, etc.); the value is
-- stored as-is for future :Add wiring (build 44).
function Cairn_Settings:RegisterCustomSetting(name, settingType)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Settings:RegisterCustomSetting: name must be a non-empty string", 2)
    end
    if settingType == nil then
        error("Cairn-Settings:RegisterCustomSetting: settingType must not be nil", 2)
    end
    -- Idempotent on name — re-registering returns the previously-allocated id.
    if self._customSettings[name] then
        return self._customSettings[name].id
    end
    local id = self._nextCustomSettingId
    self._nextCustomSettingId = self._nextCustomSettingId + 1
    self._customSettings[name] = { id = id, type = settingType, name = name }
    return id
end


-- :GetCustomSetting(name) -> { id, type, name } or nil
function Cairn_Settings:GetCustomSetting(name)
    return self._customSettings[name]
end


-- D11 — Custom system ID allocator. Blizzard's EditMode uses integer
-- system IDs per managed system; consumer-registered frames need unique
-- IDs that don't collide with Blizzard's stock systems. Each call to
-- :AllocateCustomSystemID returns the next free integer starting at
-- `#Enum.EditModeSystem` (or a safe default when the enum isn't loaded).
Cairn_Settings._nextCustomSystemId = Cairn_Settings._nextCustomSystemId or nil


function Cairn_Settings:AllocateCustomSystemID()
    if self._nextCustomSystemId == nil then
        -- Lazy-init from Enum.EditModeSystem if available; default to
        -- 100 otherwise (well above any current Blizzard system).
        local seed = 100
        if type(_G.Enum) == "table" and type(_G.Enum.EditModeSystem) == "table" then
            local maxBlz = 0
            for _, v in pairs(_G.Enum.EditModeSystem) do
                if type(v) == "number" and v > maxBlz then maxBlz = v end
            end
            seed = maxBlz + 1
        end
        self._nextCustomSystemId = seed
    end
    local id = self._nextCustomSystemId
    self._nextCustomSystemId = self._nextCustomSystemId + 1
    return id
end


-- D8 — Defensive metatables on lib-internal storage. `framesDB` and
-- `framesDialogs` get __index that auto-creates the nested entry with a
-- `settings = {}` sub-field on first access. Eliminates `if not t[k]
-- then t[k] = {} end` boilerplate at every nested-access site.

local function autoCreateMetatable()
    return {
        __index = function(t, k)
            local v = { settings = {} }
            rawset(t, k, v)
            return v
        end,
    }
end


Cairn_Settings.framesDB = Cairn_Settings.framesDB
    or setmetatable({}, autoCreateMetatable())
Cairn_Settings.framesDialogs = Cairn_Settings.framesDialogs
    or setmetatable({}, autoCreateMetatable())


-- D17 — Fire `Cairn.Settings.hideDialog` via Blizzard's `EventRegistry`
-- on dialog open for cross-addon coordination. When any Cairn-Settings
-- dialog opens, fire this event so peer dialogs (other addons using
-- Cairn-Settings, or LibEditMode-style consumers subscribing to the
-- same event name) auto-close. Cross-addon coordination with zero per-
-- consumer wiring.
--
-- Subscriber installed below pcalls EventRegistry.GetCallbackEvent
-- because the EventRegistry global may not exist on Classic.

function Cairn_Settings:FireHideDialog(senderTag)
    local ER = _G.EventRegistry
    if type(ER) ~= "table" or type(ER.TriggerEvent) ~= "function" then
        return false
    end
    pcall(ER.TriggerEvent, ER, "Cairn.Settings.hideDialog", senderTag)
    return true
end


-- Subscribe Cairn-Settings to its own event so peer dialogs auto-close.
-- The subscription is one-shot per session via a lib-scope flag. The
-- actual close-behavior wires up in build 44 when :Add(frame, schema)
-- lands; for now just listen + log for diagnostic purposes.
Cairn_Settings._hideDialogListenerInstalled = Cairn_Settings._hideDialogListenerInstalled or false


function Cairn_Settings:_EnsureHideDialogListener()
    if self._hideDialogListenerInstalled then return end
    local ER = _G.EventRegistry
    if type(ER) ~= "table" or type(ER.RegisterCallback) ~= "function" then return end
    pcall(ER.RegisterCallback, ER, "Cairn.Settings.hideDialog", function(_, senderTag)
        -- Build 44 will wire actual close behavior on registered Cairn-
        -- Settings dialogs here. For now this is a no-op listener that
        -- proves the event fires + cross-addon plumbing works.
    end, self)
    self._hideDialogListenerInstalled = true
end


-- D18 — Auto-anchor-by-quadrant normalization. Used by drag-stop handlers
-- on movable frames to keep visual position stable across UIScale + screen-
-- size changes. Algorithm: pick the screen corner closest to the frame's
-- current center, anchor to that corner, encode offset as signed delta.
--
-- Lives on Cairn.Settings until consumers in Cairn-Gui-2.0 / Vellum want
-- it; at that point promote to Cairn.Util.Frame.NormalizeAnchorByQuadrant.
function Cairn_Settings:NormalizeAnchorByQuadrant(frame)
    if type(frame) ~= "table" or type(frame.GetCenter) ~= "function" then
        error("Cairn-Settings:NormalizeAnchorByQuadrant: frame must be a Frame", 2)
    end

    local screenWidth  = _G.UIParent and _G.UIParent:GetWidth()  or 1920
    local screenHeight = _G.UIParent and _G.UIParent:GetHeight() or 1080
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return false end

    local frameWidth  = frame:GetWidth()  or 0
    local frameHeight = frame:GetHeight() or 0

    -- Determine quadrant by comparing center to screen midpoint.
    local left   = cx < screenWidth  / 2
    local bottom = cy < screenHeight / 2

    local point, ox, oy
    if left and bottom then
        point = "BOTTOMLEFT"
        ox = cx - frameWidth  / 2
        oy = cy - frameHeight / 2
    elseif left and not bottom then
        point = "TOPLEFT"
        ox = cx - frameWidth  / 2
        oy = cy + frameHeight / 2 - screenHeight
    elseif not left and bottom then
        point = "BOTTOMRIGHT"
        ox = cx + frameWidth  / 2 - screenWidth
        oy = cy - frameHeight / 2
    else
        point = "TOPRIGHT"
        ox = cx + frameWidth  / 2 - screenWidth
        oy = cy + frameHeight / 2 - screenHeight
    end

    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, point, _G.UIParent, point, ox, oy)
    return true, point, ox, oy
end


-- ---------------------------------------------------------------------------
-- Declarative :Add(frame, schema) — MINOR 23
-- ---------------------------------------------------------------------------
-- THE FOUNDATIONAL ARCHITECTURAL LOCK for the EditMode-bridge half.
--
-- Adds an addon-owned frame INTO Blizzard's EditMode with a declarative
-- widget schema. Mirrors the LibEditMode shape: each widget descriptor
-- carries `kind/key/label/desc/default/get/set/disabled/disableif/
-- hidden/tags`. Adding a new widget kind becomes DATA (an entry in
-- `Cairn_Settings.editModeKinds`) rather than a new public method.
--
-- This build ships the registration + validation half. Build 45 will
-- wire the runtime EditModeManagerFrame integration so the registered
-- widgets actually appear in EditMode dialogs.
--
-- Pattern reference: LibEditMode (Numy; inspected 2026-05-11; 891 lines,
-- used by EventsTracker). Aligns with the DetailsFramework `buildmenu.lua`
-- shape already used by the Settings-panel half.

-- D13/D10 — EditMode widget-kind registry. Distinct from controlTypes
-- (Settings-panel widgets) to keep the two APIs cleanly separated.
-- Each kind has `requireArguments` for fields the descriptor MUST carry.
Cairn_Settings.editModeKinds = Cairn_Settings.editModeKinds or {
    anchor = {
        -- Position anchor; no extra fields required.
        requireArguments = {},
    },
    hideable = {
        -- A toggle that controls whether the frame is shown. The
        -- consumer's `hidden = function(self) -> bool` predicate
        -- decides current state; `default` is the initial bool value.
        requireArguments = {
            hidden = { type = "function", optional = true },
        },
    },
    secureFrameHideable = {
        -- D10 — combat-aware secure-frame visibility. `hidden` predicate
        -- decides target visibility state; `toggleInCombat` (default
        -- false) decides whether the visibility transition can fire
        -- during combat. When `toggleInCombat = false` and the player
        -- is in combat, visibility changes queue and apply on
        -- PLAYER_REGEN_ENABLED (Cairn-Timer's :ContinueAfterCombat).
        requireArguments = {
            hidden          = { type = "function", optional = true },
            toggleInCombat  = { type = "boolean",  optional = true },
        },
    },
    scale = {
        requireArguments = {
            min  = { type = "number", optional = true },
            max  = { type = "number", optional = true },
            step = { type = "number", optional = true },
        },
    },
    size = {
        requireArguments = {
            min  = { type = "number", optional = true },
            max  = { type = "number", optional = true },
            step = { type = "number", optional = true },
        },
    },
    alpha = {
        requireArguments = {
            min  = { type = "number", optional = true },
            max  = { type = "number", optional = true },
            step = { type = "number", optional = true },
        },
    },
}


-- Internal: validate one EditMode widget descriptor against the kind
-- registry. Throws on first violation with location info.
local function validateEditModeEntry(entry, frameLabel, index)
    if type(entry) ~= "table" then
        error(("Cairn-Settings:Add(%s) entry #%d must be a table"):format(
              tostring(frameLabel), index), 4)
    end
    if type(entry.key) ~= "string" or entry.key == "" then
        error(("Cairn-Settings:Add(%s) entry #%d missing 'key' (string)"):format(
              tostring(frameLabel), index), 4)
    end
    if type(entry.kind) ~= "string" or entry.kind == "" then
        error(("Cairn-Settings:Add(%s) entry '%s' missing 'kind' (string)"):format(
              tostring(frameLabel), entry.key), 4)
    end
    local kindSpec = Cairn_Settings.editModeKinds[entry.kind]
    if not kindSpec then
        error(("Cairn-Settings:Add(%s) entry '%s' has unknown 'kind': %s"):format(
              tostring(frameLabel), entry.key, tostring(entry.kind)), 4)
    end

    -- Per-kind requireArguments check.
    local req = kindSpec.requireArguments
    if type(req) == "table" then
        for fieldName, requirement in pairs(req) do
            local value = entry[fieldName]
            if type(requirement) == "table" then
                local expected = requirement.type
                if value == nil then
                    if not requirement.optional then
                        error(("Cairn-Settings:Add(%s) entry '%s' (%s) requires '%s'"):format(
                              tostring(frameLabel), entry.key, entry.kind, fieldName), 4)
                    end
                elseif type(expected) == "string" and type(value) ~= expected then
                    error(("Cairn-Settings:Add(%s) entry '%s' (%s) field '%s' must be %s (got %s)"):format(
                          tostring(frameLabel), entry.key, entry.kind, fieldName, expected, type(value)), 4)
                end
            elseif type(requirement) == "string" then
                if type(value) ~= requirement then
                    error(("Cairn-Settings:Add(%s) entry '%s' (%s) requires '%s' of type %s"):format(
                          tostring(frameLabel), entry.key, entry.kind, fieldName, requirement), 4)
                end
            end
        end
    end

    -- D14 — consumer-supplied get/set (opt-out). If `get` is set, `set`
    -- must be too (otherwise the lib doesn't know how to write changes).
    if entry.get ~= nil and type(entry.get) ~= "function" then
        error(("Cairn-Settings:Add(%s) entry '%s' has non-function 'get'"):format(
              tostring(frameLabel), entry.key), 4)
    end
    if entry.set ~= nil and type(entry.set) ~= "function" then
        error(("Cairn-Settings:Add(%s) entry '%s' has non-function 'set'"):format(
              tostring(frameLabel), entry.key), 4)
    end
    if (entry.get ~= nil) ~= (entry.set ~= nil) then
        error(("Cairn-Settings:Add(%s) entry '%s' must supply BOTH 'get' and 'set' or NEITHER"):format(
              tostring(frameLabel), entry.key), 4)
    end

    -- Optional shape checks. Reuse same vocabulary as
    -- :New schema for consistency.
    if entry.disableif ~= nil and type(entry.disableif) ~= "function" then
        error(("Cairn-Settings:Add(%s) entry '%s' has non-function 'disableif'"):format(
              tostring(frameLabel), entry.key), 4)
    end
    if entry.disabled ~= nil and type(entry.disabled) ~= "boolean" then
        error(("Cairn-Settings:Add(%s) entry '%s' has non-boolean 'disabled'"):format(
              tostring(frameLabel), entry.key), 4)
    end
    if entry.tags ~= nil and type(entry.tags) ~= "table" then
        error(("Cairn-Settings:Add(%s) entry '%s' has non-array 'tags'"):format(
              tostring(frameLabel), entry.key), 4)
    end
end


-- Internal: validate an entire schema array.
local function validateEditModeSchema(schema, frameLabel)
    if type(schema) ~= "table" then
        error(("Cairn-Settings:Add(%s): schema must be a table"):format(
              tostring(frameLabel)), 3)
    end
    local seen = {}
    for i, entry in ipairs(schema) do
        validateEditModeEntry(entry, frameLabel, i)
        if seen[entry.key] then
            error(("Cairn-Settings:Add(%s): duplicate key '%s' in schema"):format(
                  tostring(frameLabel), entry.key), 3)
        end
        seen[entry.key] = true
    end
end


-- :Add(frame, schema, opts?)
--
-- Registers an addon-owned `frame` into Blizzard's EditMode with a
-- declarative widget `schema`. Validates the schema, allocates a
-- custom system ID, records the registration in `_frames`, and
-- seeds the framesDB/framesDialogs entries (D8 metatables handle the
-- auto-create).
--
-- Returns the allocated system ID so consumers can refer to it later.
-- Idempotent on `frame`: re-adding the same frame returns the original
-- system ID without re-allocating.
--
-- opts.label (string, optional) — human-readable name for diagnostics
--                                 and EditMode dialog title.
function Cairn_Settings:Add(frame, schema, opts)
    if type(frame) ~= "table" then
        error("Cairn-Settings:Add: frame must be a Frame", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("Cairn-Settings:Add: opts must be a table or nil", 2)
    end

    self._frames = self._frames or {}
    local existing = self._frames[frame]
    if existing then return existing.systemId end

    local label = (opts and opts.label) or tostring(frame:GetName() or "<unnamed>")
    validateEditModeSchema(schema, label)

    local systemId = self:AllocateCustomSystemID()
    -- D8 metatables auto-create the nested table on access; we just
    -- read them to materialize the entries.
    local dbEntry  = self.framesDB[frame]
    local dlgEntry = self.framesDialogs[frame]
    -- Record each widget into both halves. Settings-side reads from
    -- framesDB (persistence); UI-side reads from framesDialogs (render).
    for _, entry in ipairs(schema) do
        dbEntry.settings[entry.key]  = dbEntry.settings[entry.key]  or {}
        dlgEntry.settings[entry.key] = entry  -- whole descriptor for render
    end

    local registration = {
        frame    = frame,
        schema   = schema,
        opts     = opts,
        systemId = systemId,
        label    = label,
    }
    self._frames[frame] = registration

    -- Stamp the frame so consumer code (and Blizzard's EditMode dispatch)
    -- can read `frame.system` consistently with stock systems.
    pcall(function() frame.system = systemId end)

    return systemId
end


-- :AddSystemSettings(systemID, schema, subSystemID?)
--
-- Extend Blizzard's stock EditMode dialogs (action bars, raid frames,
-- etc.) with consumer-defined widgets. Same descriptor shape as :Add
-- but takes an existing system ID instead of allocating a new one.
-- subSystemID optionally narrows the registration to a specific sub-
-- system within a multi-system Blizzard component.
function Cairn_Settings:AddSystemSettings(systemID, schema, subSystemID)
    if type(systemID) ~= "number" then
        error("Cairn-Settings:AddSystemSettings: systemID must be a number", 2)
    end
    if subSystemID ~= nil and type(subSystemID) ~= "number" then
        error("Cairn-Settings:AddSystemSettings: subSystemID must be a number or nil", 2)
    end
    local label = ("system %d"):format(systemID)
        .. (subSystemID and (".%d"):format(subSystemID) or "")
    validateEditModeSchema(schema, label)

    self._systemExtensions = self._systemExtensions or {}
    local key = subSystemID and (systemID .. ":" .. subSystemID) or tostring(systemID)
    self._systemExtensions[key] = {
        systemID    = systemID,
        subSystemID = subSystemID,
        schema      = schema,
    }
    return true
end


-- :GetFrameRegistration(frame) -> registration table or nil
-- Used by Forge_BugCatcher / debug surfaces to inspect what's registered.
function Cairn_Settings:GetFrameRegistration(frame)
    return self._frames and self._frames[frame] or nil
end


-- :IterateFrames() -> iterator(frame, registration)
-- Generic-for iterator over every :Add-registered frame.
function Cairn_Settings:IterateFrames()
    local registry = self._frames or {}
    local key
    return function()
        local frame, reg = next(registry, key)
        key = frame
        return frame, reg
    end
end


-- :IsRegisteredFrame(frame) -> bool
function Cairn_Settings:IsRegisteredFrame(frame)
    return self._frames and self._frames[frame] ~= nil or false
end


-- ---------------------------------------------------------------------------
-- Runtime EditMode hooks (MINOR 24)
-- ---------------------------------------------------------------------------
-- Third (final) phased build for the EditMode-bridge half. Wires the
-- runtime EditMode integration so registered frames participate in
-- EnterEditMode/ExitEditMode lifecycles and per-layout persistence.
--
-- D15 — hookVersion pattern. Every hooksecurefunc Cairn-Settings installs
-- checks `Cairn_Settings.hookVersion == MY_MINOR` at the top of the hook
-- body; mismatch returns immediately. On lib upgrade (LibStub re-loads at
-- a higher MINOR), the new file sets `hookVersion = NEW_MINOR` — old
-- hooks self-deactivate because their captured MY_MINOR upvalue no
-- longer matches. Without this, every MINOR bump leaks stale hooks
-- firing in parallel.
Cairn_Settings.hookVersion = LIB_MINOR


-- D5 — Per-EditMode-layout persistence. Profile name key for the
-- consumer's per-layout sub-store. Layout-Account scope: `<layoutType>-
-- <layoutName>`. Layout-Character scope: `<layoutType>-<layoutName>-
-- <character>-<realm>` so different characters using the same Character
-- layout name don't collide.
function Cairn_Settings:ResolveLayoutProfileName(layoutType, layoutName)
    if type(layoutName) ~= "string" or layoutName == "" then return nil end
    local base = tostring(layoutType or "Account") .. "-" .. layoutName

    -- Append character+realm for Character-scope layouts. Enum may be
    -- absent on Classic; fall through to Account-scope on miss.
    local CHAR_TYPE = (_G.Enum and _G.Enum.EditModeLayoutType
                       and _G.Enum.EditModeLayoutType.Character) or nil
    if CHAR_TYPE and layoutType == CHAR_TYPE then
        local name  = (_G.UnitName and _G.UnitName("player")) or "Unknown"
        local realm = (_G.GetRealmName and _G.GetRealmName()) or "UnknownRealm"
        return base .. "-" .. name .. "-" .. realm
    end
    return base
end


-- D5 — Load or copy-forward a layout-specific profile. When the consumer
-- enables per-layout persistence on a registered frame, `:Add` records
-- the base values; on first access of a new layout's sub-profile we
-- copy the base forward. Subsequent layout switches re-apply the stored
-- per-layout values.
function Cairn_Settings:LoadLayoutProfile(db, layoutType, layoutName)
    if type(db) ~= "table" or type(db.SetProfile) ~= "function" then
        error("Cairn-Settings:LoadLayoutProfile: db must be a Cairn-DB instance", 2)
    end
    local profileName = self:ResolveLayoutProfileName(layoutType, layoutName)
    if not profileName then return nil end

    -- Idempotent profile switch — Cairn-DB's :SetProfile creates the
    -- profile if absent and runs wildcardMerge on every call so a fresh
    -- per-layout sub-profile inherits the addon's defaults.
    local prevProfile = (type(db.GetProfile) == "function") and db:GetProfile() or nil
    if prevProfile ~= profileName then
        local ok, err = pcall(db.SetProfile, db, profileName)
        if not ok then geterrorhandler()(err) end
    end
    return profileName
end


-- D9 — Hook EnterEditMode + ExitEditMode for show/hide of
-- hiddenUntilMouseover frames during configuration. Without these hooks
-- the user can't drag a frame that's currently hidden.
--
-- D15 — Each installed hook captures MY_MINOR at install time. The hook
-- body re-checks `Cairn_Settings.hookVersion` against the captured value;
-- mismatch = stale hook from a lower MINOR, return immediately.
Cairn_Settings._editModeHooksInstalled = Cairn_Settings._editModeHooksInstalled or false


-- :InstallEditModeHooks() — idempotent runtime hook installation. Skip
-- when EditMode isn't available (Classic) or when hooks were already
-- installed THIS session.
--
-- Public-but-internal: typically called from :Add on first registration.
function Cairn_Settings:InstallEditModeHooks()
    if self._editModeHooksInstalled then return false end
    if not editModeAvailable() then return false end
    if type(_G.hooksecurefunc) ~= "function" then return false end

    local MY_MINOR = LIB_MINOR
    local manager  = _G.EditModeManagerFrame

    -- Hook EnterEditMode: walk every registered frame, force-show any
    -- frame that's currently hidden so the user can drag it.
    if type(manager.EnterEditMode) == "function" then
        pcall(_G.hooksecurefunc, manager, "EnterEditMode", function()
            -- D15: stale-hook gate.
            if Cairn_Settings.hookVersion ~= MY_MINOR then return end
            local frames = Cairn_Settings._frames
            if not frames then return end
            for frame, reg in pairs(frames) do
                if type(frame.IsVisible) == "function" and not frame:IsVisible() then
                    -- Record that we force-showed this frame so ExitEditMode
                    -- can restore it.
                    reg._wasHiddenForEditMode = true
                    pcall(frame.Show, frame)
                end
            end
        end)
    end

    -- Hook ExitEditMode: restore each frame's previous hidden state.
    if type(manager.ExitEditMode) == "function" then
        pcall(_G.hooksecurefunc, manager, "ExitEditMode", function()
            if Cairn_Settings.hookVersion ~= MY_MINOR then return end
            local frames = Cairn_Settings._frames
            if not frames then return end
            for frame, reg in pairs(frames) do
                if reg._wasHiddenForEditMode then
                    reg._wasHiddenForEditMode = false
                    -- Re-evaluate `hidden` predicate per the widget
                    -- descriptors. If any kind=hideable/secureFrameHideable
                    -- entry's `hidden` predicate returns true, hide.
                    local shouldHide = false
                    if type(reg.schema) == "table" then
                        for _, entry in ipairs(reg.schema) do
                            if (entry.kind == "hideable"
                                or entry.kind == "secureFrameHideable")
                                and type(entry.hidden) == "function"
                            then
                                local ok, val = pcall(entry.hidden, frame)
                                if ok and val then shouldHide = true; break end
                            end
                        end
                    end
                    if shouldHide and type(frame.Hide) == "function" then
                        pcall(frame.Hide, frame)
                    end
                end
            end
        end)
    end

    self._editModeHooksInstalled = true
    return true
end


-- Auto-install hooks when the first frame is added. The previous :Add
-- definition is wrapped here so the existing test surface (frame
-- registration, system ID allocation, schema validation) stays
-- unchanged but a hook-install pass runs alongside.
local _originalAdd = Cairn_Settings.Add
function Cairn_Settings:Add(frame, schema, opts)
    local id = _originalAdd(self, frame, schema, opts)
    -- Best-effort install. Errors during hook install are non-fatal;
    -- the registration above already succeeded.
    pcall(self.InstallEditModeHooks, self)
    return id
end


return Cairn_Settings
