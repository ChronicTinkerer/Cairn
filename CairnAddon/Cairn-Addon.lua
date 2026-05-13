-- Cairn-Addon
-- Addon lifecycle wrapper + single-call orchestrator.
--
-- TWO API surfaces, in increasing convenience:
--
-- 1. Lifecycle wrapper (the original surface). Gives every consumer the
--    same three hooks: OnInit (ADDON_LOADED for the consumer's own addon),
--    OnLogin (PLAYER_LOGIN), and OnDisable (PLAYER_LOGOUT, best-effort).
--
--    The defining feature is **retro-fire**: if a consumer assigns OnInit
--    or OnLogin after the matching event has already passed, the handler
--    fires immediately. This is the main pain point in the old Cairn-Addon:
--    load-on-demand addons that registered late had their OnLogin never
--    fire, which silently broke every consumer that did setup work there.
--
-- 2. Single-call orchestrator. One call wires up everything a typical
--    Cairn consumer wants: metadata extraction, DB init, settings panel,
--    auto-attached companion libs.
--
--        local Addon = {}
--        Addon.Settings = Cairn.Register("MyAddon", Addon, {
--          minimap = true,
--          Gui = true, Slash = true, DB = true,
--        })
--
--    The returned Settings is a 12-field metadata table (AddonName,
--    Version, NominalVersion, etc.). Optional phases (DB, Settings panel,
--    minimap, tooltip, auto-wiring) skip cleanly when their opts keys are
--    absent.
--
--    Cairn-Addon RE-IMPLEMENTS the KLib / AceAddon pattern natively
--    against Cairn-DB and Cairn-Settings; it does NOT depend on Ace3.
--    Cairn is the Ace3 alternative (memory:
--    cairn_is_ace3_alternative_not_wrapper).
--
-- Public API (lifecycle):
--   local CA = LibStub("Cairn-Addon-1.0")
--   local addon = CA:New("MyAddon")
--   function addon:OnInit()    end   -- runs on or after ADDON_LOADED for "MyAddon"
--   function addon:OnLogin()   end   -- runs on or after PLAYER_LOGIN
--   function addon:OnDisable() end   -- runs on PLAYER_LOGOUT (best-effort)
--
-- Public API (orchestrator, on the `_G.Cairn` namespace):
--   Cairn.Register(tocName, Addon, opts) -> Metadata
--   Cairn.GetRegistry()                  -> shallow copy of the rich registry
--   Cairn.NewLibrary(name, ver, opts)    -> LibStub:NewLibrary wrapper
--   Cairn.CurrentLibrary                 -> last lib registered with SetCurrent
--
-- Library-author shape (returned by Cairn.NewLibrary):
--   lib:NewSubmodule(subName, ver, parent?) -> submodule table
--
-- Introspection (used by Forge_Registry and friends):
--   CA.registry            -- {[name] = lifecycle instance}
--   CA.tocRegistry         -- {[tocName] = {Addon, Metadata, ...} rich entry}
--   CA:Get(name)           -- lifecycle instance for name, or nil
--   Cairn.GetRegistry()    -- shallow copy of tocRegistry (consumer-safe)
--
-- Guarantees:
--   - OnInit always fires before OnLogin for a given addon.
--   - Each handler fires at most once per session.
--   - New() / Cairn.Register() are idempotent: same name returns the same
--     instance / entry.
--   - Handler errors are caught (geterrorhandler()) so one bad handler
--     doesn't break dispatch for the rest.
--   - Cairn.GetRegistry() returns a shallow COPY; consumers can't mutate
--     the live registry.
--
-- TOC-load-order gotcha for CurrentLibrary / NewSubmodule:
--   A submodule file's TOC line MUST follow its parent's. When
--   NewSubmodule is called with no CurrentLibrary set, the lib throws
--   a specific error pointing at TOC ordering. Loud failure beats silent
--   miswire.
--
-- SavedVariables note: consumer addons that pass `opts.DB = true` (or use
-- any auto-options path) need to declare `## SavedVariables: <tocName>DB`
-- in their TOC. Cairn-DB creates the table in memory either way, but
-- persistence requires the TOC declaration.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Addon-1.0"
local LIB_MINOR = 20

local Cairn_Addon = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Addon then return end  -- already loaded at this MINOR or newer

local CU = LibStub("Cairn-Util-1.0")
local Pcall = CU.Pcall


-- Internal state. Preserved across MINOR upgrades because LibStub returns
-- the same table on upgrade and `or {}` only initializes once.
--
-- `registry`       lifecycle instances keyed by addon name (returned by :New).
-- `tocRegistry`    rich entries keyed by tocName (created by Cairn.Register).
--                  Two registries because they serve different concerns:
--                  registry holds handler-bearing instances, tocRegistry holds
--                  diagnostic-friendly metadata. An addon can appear in
--                  both — `Cairn.Register` calls `:New` under the hood and
--                  stores the resulting instance on the toc entry as
--                  `entry.cairnAddon`.
Cairn_Addon.registry      = Cairn_Addon.registry      or {}
Cairn_Addon.tocRegistry   = Cairn_Addon.tocRegistry   or {}
Cairn_Addon._loginFired   = Cairn_Addon._loginFired   or false


-- C_AddOns.IsAddOnLoaded landed on Retail; bare-global IsAddOnLoaded still
-- exists on Classic flavors. Bind once so call sites don't branch.
local IsLoaded =
    (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded


-- ---------------------------------------------------------------------------
-- Dispatch primitives
-- ---------------------------------------------------------------------------

-- One bad consumer handler must not break dispatch for the rest. Error
-- isolation routes through Cairn-Util.Pcall.Call (which formats the
-- context with " threw: <err>" and reports via geterrorhandler).
local function safeCall(addon, key)
    local handler = rawget(addon, key)
    if type(handler) ~= "function" then return end
    Pcall.Call(("Cairn-Addon: %s:%s"):format(
        rawget(addon, "_name") or "<unknown>", key), handler, addon)
end


-- Idempotent OnInit dispatch. _initFired is the latch — once set, repeated
-- calls (e.g. from late metatable retro-fire OR the event listener) are
-- no-ops. The contract is "at most once per session per addon".
local function fireInit(addon)
    if rawget(addon, "_initFired") then return end
    rawset(addon, "_initFired", true)
    safeCall(addon, "OnInit")
end


-- Same idempotent latch as fireInit, plus an explicit OnInit-first ordering
-- so OnLogin handlers can assume their addon's init code has completed even
-- if assignment order was Login-then-Init at the consumer site.
local function fireLogin(addon)
    if rawget(addon, "_loginFired") then return end
    rawset(addon, "_loginFired", true)
    fireInit(addon)
    safeCall(addon, "OnLogin")
end


-- ---------------------------------------------------------------------------
-- Per-instance metatable — the retro-fire mechanism
-- ---------------------------------------------------------------------------

-- The defining trick: __newindex on first assignment of OnInit / OnLogin
-- checks whether the matching event already happened, and if so fires the
-- handler synchronously. After the first write the key lives on the instance
-- directly, so subsequent writes bypass the metatable (Lua semantics) and
-- can't re-fire — exactly the desired "at most once" behavior.
--
-- OnDisable intentionally has no retro-fire path: PLAYER_LOGOUT is a
-- terminal event we can't replay.
local AddonMeta = {
    __newindex = function(addon, key, value)
        rawset(addon, key, value)

        if key == "OnInit" then
            -- _initSeen tracks "ADDON_LOADED for this addon has been observed"
            -- (set by the event listener) OR "we detected it as already-loaded
            -- at New() via the IsLoaded probe". Either path means OnInit
            -- assignment is late and the handler should fire now.
            if rawget(addon, "_initSeen") then
                fireInit(addon)
            end
        elseif key == "OnLogin" then
            if Cairn_Addon._loginFired then
                fireLogin(addon)
            end
        end
    end,
}


-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Idempotent on `name` so the addon's main file can call New() unconditionally
-- without worrying about whether an earlier load already created the instance
-- (relevant for /reload paths and dev workflows that re-source files).
--
-- The IsLoaded probe at the end matters for one specific case: Cairn-Addon
-- itself loaded AFTER the consumer's ADDON_LOADED already fired. Without it,
-- the consumer's OnInit handler assignment would have no retro-fire trigger
-- and the handler would never run.
function Cairn_Addon:New(name)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Addon:New: name must be a non-empty string", 2)
    end

    local existing = self.registry[name]
    if existing then return existing end

    local addon = setmetatable({ _name = name }, AddonMeta)
    self.registry[name] = addon

    if IsLoaded and IsLoaded(name) then
        rawset(addon, "_initSeen", true)
    end

    return addon
end


function Cairn_Addon:Get(name)
    return self.registry[name]
end


-- ---------------------------------------------------------------------------
-- Metadata extraction
-- ---------------------------------------------------------------------------

-- C_AddOns.GetAddOnMetadata landed on Retail; bare-global still exists on
-- Classic flavors. Bind once.
local GetAddOnMetadata =
    (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata


-- Read a TOC field and run it through NormalizeWhitespace. TOC fields
-- often pick up hidden CR/LF from authoring editors; consumers checking
-- `Settings.AddonNameWithSpaces == "My Addon"` should match regardless.
local function readTocField(tocName, field)
    if type(GetAddOnMetadata) ~= "function" then return nil end
    local raw = GetAddOnMetadata(tocName, field)
    if type(raw) ~= "string" or raw == "" then return nil end
    return CU.String.NormalizeWhitespace(raw)
end


-- Parse a comma-separated TOC field (Dependencies, OptionalDeps) into a
-- list of trimmed strings. Returns an empty table if the field is absent
-- so consumers can iterate without nil-guarding.
local function readTocList(tocName, field)
    local raw = readTocField(tocName, field)
    if not raw then return {} end
    local list = {}
    for entry in raw:gmatch("[^,]+") do
        entry = entry:gsub("^%s+", ""):gsub("%s+$", "")
        if entry ~= "" then list[#list + 1] = entry end
    end
    return list
end


-- Build the 12-field Metadata table. Eager-populated so the
-- table is self-describing for diagnostic dumps. Cost is 12 string fields
-- per registered addon — irrelevant in practice.
--
-- AccentColor sourcing: opts.accent wins, falls back to TOC X-AccentColor
-- (an "rgb 0.4 0.6 1.0" string), falls back to nil. Callers that want a
-- default colour set their own; Cairn doesn't impose a brand colour on
-- consumers.
local function extractMetadata(tocName, opts)
    local addonName       = readTocField(tocName, "Title") or tocName
    local nameWithSpaces  = readTocField(tocName, "X-Title-With-Spaces") or addonName
    local versionRaw      = readTocField(tocName, "Version")
    local version         = CU.String.NormalizeVersion(versionRaw)
    local nominalVersion  = CU.String.ParseVersion(versionRaw) or 0

    local accentColor = opts.accent
    if not accentColor then
        local rgb = readTocField(tocName, "X-AccentColor")
        if rgb then
            local r, g, b = rgb:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
            if r and g and b then
                accentColor = {
                    r = tonumber(r), g = tonumber(g), b = tonumber(b),
                }
            end
        end
    end

    local iconTexture = opts.icon or readTocField(tocName, "IconTexture")

    -- Pre-format the icon-prefixed name so consumers don't reach for the
    -- escape-string each time they display the addon. Falls back to the
    -- plain name when no icon exists.
    local nameWithIcon = addonName
    if iconTexture then
        nameWithIcon = ("|T%s:0|t %s"):format(iconTexture, addonName)
    end

    return {
        AddonName                = addonName,
        AddonNameWithSpaces      = nameWithSpaces,
        Version                  = version,
        NominalVersion           = nominalVersion,
        Dependencies             = readTocList(tocName, "Dependencies"),
        OptionalDeps             = readTocList(tocName, "OptionalDeps"),
        IconTexture              = iconTexture,
        AccentColor              = accentColor,
        -- AddonDBName uses the FOLDER NAME (tocName), not the Title.
        -- WoW's `## SavedVariables:` line conventionally uses the folder
        -- name + "DB". If we used Title-based naming, any addon with a
        -- spaced/decorated Title would silently fail to persist (Cairn-DB
        -- writes to the wrong global). Caller can override via opts.dbName
        -- if their TOC explicitly declares a non-default SV name.
        AddonDBName              = opts.dbName or (tocName .. "DB"),
        AddonOptionsSlashCommand = "/" .. addonName:lower(),
        AddonTooltipName         = addonName .. "Tooltip",
        AddonNameWithIcon        = nameWithIcon,
    }
end


-- ---------------------------------------------------------------------------
-- Auto-wiring flags
-- ---------------------------------------------------------------------------

-- Map of `opts` flag -> companion-lib spec. Each spec has:
--   lookup(): returns the lib (or nil if not loaded)
--   attach(addon, lib, tocName): optional. Default behavior is
--      `addon[flag] = lib`. Override for libs that need different
--      attach semantics (e.g. Cairn-Log injects methods directly via
--      `:Embed` instead of stashing a reference).
--
-- Cairn-Settings is intentionally excluded — `Addon.Settings` is reserved
-- for the Metadata return value to avoid the name collision.
--
-- Gui is the odd one out among lookups: it uses the `-2.0` MAJOR family
-- and isn't resolved through the `_G.Cairn` namespace (Core.lua hardcodes
-- `Cairn-<k>-1.0`). We look it up explicitly via LibStub.
local AUTO_WIRE_FLAGS = {
    Gui    = { lookup = function() return LibStub("Cairn-Gui-2.0",     true) end },
    Slash  = { lookup = function() return LibStub("Cairn-Slash-1.0",   true) end },
    Events = { lookup = function() return LibStub("Cairn-Events-1.0",  true) end },
    Hooks  = { lookup = function() return LibStub("Cairn-Hooks-1.0",   true) end },
    Timer  = { lookup = function() return LibStub("Cairn-Timer-1.0",   true) end },
    Locale = { lookup = function() return LibStub("Cairn-Locale-1.0",  true) end },
    DB     = { lookup = function() return LibStub("Cairn-DB-1.0",      true) end },
    Media  = { lookup = function() return LibStub("Cairn-Media-1.0",   true) end },
    -- Cairn-Log: injects log methods directly
    -- onto the addon namespace via `:Embed` rather than stashing a lib
    -- reference. Consumer gets `addon:Info(...)` style call sites instead
    -- of `addon.Log:Info(...)`.
    Log    = {
        lookup = function() return LibStub("Cairn-Log-1.0", true) end,
        attach = function(addon, lib, tocName)
            if type(lib.Embed) == "function" then
                lib:Embed(addon, tocName)
            else
                addon.Log = lib  -- defensive fallback if Embed isn't shipped yet
            end
        end,
    },
}


-- Attach companion libs to the consumer's Addon namespace based on
-- truthy `opts.<Flag>` entries. Silently skips flags whose underlying
-- lib isn't loaded — keeps `Cairn.Register` working in degraded
-- environments (e.g. consumer embeds only a subset of Cairn).
local function applyAutoWiring(addon, opts, tocName)
    for flag, spec in pairs(AUTO_WIRE_FLAGS) do
        if opts[flag] then
            local lib = spec.lookup()
            if lib then
                if spec.attach then
                    spec.attach(addon, lib, tocName)
                else
                    addon[flag] = lib
                end
            end
        end
    end
end


-- ---------------------------------------------------------------------------
-- Cairn.Register orchestrator
-- ---------------------------------------------------------------------------

-- Auto-generated default Cairn-Settings schema. Minimal panel:
-- a version header + a "hide minimap button" toggle when opts.minimap is
-- truthy. Consumers who want more pass `opts.options` with their own schema.
local function buildDefaultSchema(metadata, opts)
    local schema = {
        { key = "_about", type = "header",
          label = ("%s — version %s"):format(
              metadata.AddonNameWithSpaces, metadata.Version) },
    }

    if opts.minimap then
        schema[#schema + 1] = {
            key     = "hideMinimap",
            type    = "toggle",
            label   = "Hide minimap button",
            default = false,
            tooltip = ("Hide %s's minimap button."):format(metadata.AddonName),
        }
    end

    return schema
end


-- Cairn.Register(tocName, Addon, opts) -> Metadata
--
-- Headline consumer-facing API. One call chains four phases:
--   1. Metadata extraction
--   2. Cairn-Addon lifecycle instance creation (idempotent)
--   3. Cairn-DB + Cairn-Settings panel registration (gated)
--   4. Companion-lib auto-wiring
--
-- Idempotent on tocName: re-registration during dev reloads or chained
-- registration paths returns the existing rich entry rather than throwing.
--
-- The `_internal` opt is reserved for Cairn's own self-registration
-- on self-load. It skips phases 3 and 4 so the bootstrap entry doesn't
-- pull in Cairn-DB / Cairn-Settings before they've finished loading.
-- Third-party callers should not pass it.
local function registerAddon(tocName, addon, opts)
    if type(tocName) ~= "string" or tocName == "" then
        error("Cairn.Register: tocName must be a non-empty string", 2)
    end
    if type(addon) ~= "table" then
        error("Cairn.Register: addon must be a table", 2)
    end
    opts = opts or {}

    local existing = Cairn_Addon.tocRegistry[tocName]
    if existing then return existing.Metadata end

    local metadata = extractMetadata(tocName, opts)
    local cairnAddon = Cairn_Addon:New(tocName)

    local entry = {
        tocName         = tocName,
        Addon           = addon,
        Metadata        = metadata,
        registeredAt    = (type(GetTime) == "function") and GetTime() or 0,
        cairnAddon      = cairnAddon,
        registerOptions = opts,
        db              = nil,  -- populated below if applicable
        settings        = nil,  -- populated below if applicable (the
                                -- Cairn-Settings INSTANCE; distinct from
                                -- Metadata, which is what consumers store
                                -- as Addon.Settings).
    }
    Cairn_Addon.tocRegistry[tocName] = entry

    -- Phases 3-4: skip for Cairn's own self-registration to avoid the
    -- load-order trap with Cairn-DB / Cairn-Settings.
    if not opts._internal then
        local DB = LibStub("Cairn-DB-1.0", true)
        local CS = LibStub("Cairn-Settings-1.0", true)

        if DB and CS then
            -- Auto-create the DB instance using the Decision-4 derived name.
            -- Consumer is responsible for declaring `## SavedVariables:
            -- <AddonName>DB` in their TOC if they want persistence.
            local dbDefaults = opts.dbDefaults or { profile = {} }
            entry.db = DB:New(metadata.AddonDBName, dbDefaults)

            -- Schema: consumer override wins, else the auto-generated
            -- minimal default panel.
            local schema = opts.options or buildDefaultSchema(metadata, opts)
            entry.settings = CS:New(metadata.AddonName, entry.db, schema)
        end

        applyAutoWiring(addon, opts, tocName)
    end

    return metadata
end


-- ---------------------------------------------------------------------------
-- Library-author shape
-- ---------------------------------------------------------------------------

-- NewSubmodule installed onto libs returned by Cairn.NewLibrary. Does TWO
-- assignments: (1) creates the LibStub entry `<parentName>_<subName>` so
-- other libs can `LibStub("Cairn-Gui-Widgets-Standard-2.0_Button")`, (2)
-- assigns the submodule table to `parentLibrary[subName]` so dotted-namespace
-- lookups Just Work. Returns the submodule for the calling file to populate.
local function newSubmoduleMethod(parentLib, subName, subVersion, parentOverride)
    -- parentOverride is the `parent` arg to :NewSubmodule. Defaults to the
    -- captured `parentLib` from closure. The override path exists so a
    -- submodule file can mount onto a different parent (rare, but useful for
    -- shared widget submodules).
    local parent = parentOverride or parentLib

    if type(parent) ~= "table" then
        error(("Cairn:NewSubmodule(%q): no CurrentLibrary set " ..
               "and no parent override passed. Check TOC order; the " ..
               "parent lib's file must load before any submodule file.")
            :format(tostring(subName)), 2)
    end

    -- LibStub MAJOR for the submodule. Pattern matches Krowi_Util LibMan:
    -- `<parentMajor>_<subName>`. The parent's stored MAJOR lives on the
    -- closure as `parentLibMajor`; if a caller passed a parentOverride that
    -- doesn't have a _libMajor stamp, fall back to <name>_<subName> using
    -- the parent's metatable-style discoverable name.
    local parentMajor = rawget(parent, "_cairnLibMajor")
                     or rawget(parentLib, "_cairnLibMajor")
                     or "UnknownParent"
    local subMajor = parentMajor .. "_" .. subName

    local submodule = LibStub:NewLibrary(subMajor, subVersion or 1)
    -- LibStub returns nil if a same-or-newer MINOR is already registered;
    -- in that case fetch the existing table so the caller still gets it.
    if not submodule then submodule = LibStub(subMajor) end

    -- Stamp the submodule too so its own :NewSubmodule (if installed) has
    -- the right parent prefix.
    rawset(submodule, "_cairnLibMajor", subMajor)

    -- Parent-table assignment: this is the ergonomic win. `Cairn.Gui.Widgets
    -- .Standard.Button` Just Works after this line.
    parent[subName] = submodule

    return submodule
end


-- Cairn.NewLibrary(name, version, opts) -> lib
--
-- Public Cairn API. Wraps `LibStub:NewLibrary` and folds cross-cutting
-- setup into one call. Returns the lib table (or nil if a same-or-newer
-- MINOR is already registered, matching LibStub's contract).
--
-- Options:
--   SetCurrent       (bool, default true) — stash the returned lib at
--                    Cairn.CurrentLibrary for implicit submodule mounting.
--   MountAs          (string) — also assign to `_G.Cairn[MountAs]` so the
--                    namespace lookup returns the lib directly instead of
--                    going through Core.lua's LibStub resolver. Useful for
--                    libs whose MAJOR doesn't match the `Cairn-<X>-1.0`
--                    pattern (e.g. third-party libs riding the namespace).
--
-- The library-author shape is shared with the consumer surface above:
-- LibStub-author convention says the result has `:NewSubmodule`.
function _G.Cairn.NewLibrary(name, version, opts)
    if type(name) ~= "string" or name == "" then
        error("Cairn.NewLibrary: name must be a non-empty string", 2)
    end
    opts = opts or {}

    local lib = LibStub:NewLibrary(name, version or 1)
    -- LibStub returns nil if the same MINOR is already registered. Caller
    -- treats nil as "already loaded; skip the rest of my file" per the
    -- standard `if not lib then return end` pattern.
    if not lib then return nil end

    rawset(lib, "_cairnLibMajor", name)

    -- Inject :NewSubmodule so this lib's submodule files can mount.
    lib.NewSubmodule = function(self, subName, subVersion, parent)
        return newSubmoduleMethod(self, subName, subVersion, parent)
    end

    -- Opt-in CurrentLibrary tracking. Default true because the
    -- common case is a multi-file lib where the next file wants to mount
    -- submodules; explicit `SetCurrent = false` exits the path for libs
    -- that share their MAJOR across non-Cairn-flavored consumers.
    local setCurrent = opts.SetCurrent
    if setCurrent == nil then setCurrent = true end
    if setCurrent then
        _G.Cairn.CurrentLibrary = lib
    end

    -- The `MountAs` opt for cases where the namespace resolver
    -- can't reach the lib (non-`Cairn-X-1.0` MAJOR).
    if type(opts.MountAs) == "string" and opts.MountAs ~= "" then
        rawset(_G.Cairn, opts.MountAs, lib)
    end

    return lib
end


-- Cairn.GetRegistry() -> {[tocName] = entry copy, ...}
--
-- Shallow copy of `tocRegistry` so consumers can iterate / diff / display
-- without mutating Cairn's internal state. Entries are copied at the
-- top level only; the inner tables (Metadata, Addon, registerOptions)
-- are still live references — consumers must not mutate those either.
-- Documented contract: read-only.
function _G.Cairn.GetRegistry()
    local copy = {}
    for tocName, entry in pairs(Cairn_Addon.tocRegistry) do
        local entryCopy = {}
        for k, v in pairs(entry) do entryCopy[k] = v end
        copy[tocName] = entryCopy
    end
    return copy
end


-- Expose registerAddon as Cairn.Register on the namespace.
_G.Cairn.Register = registerAddon


-- ---------------------------------------------------------------------------
-- Event listener
-- ---------------------------------------------------------------------------
-- One frame, three Blizzard events, fanned out to per-addon handlers.
--
-- Anonymous CreateFrame is load-bearing: RegisterEvent on a NAMED frame can
-- trip ADDON_ACTION_FORBIDDEN on current Retail (memory:
-- wow_named_frame_register_event.md). Don't name this frame.

local listener = Cairn_Addon._listener or CreateFrame("Frame")
Cairn_Addon._listener = listener
listener:UnregisterAllEvents()  -- safe on MINOR upgrades; we re-register below
listener:RegisterEvent("ADDON_LOADED")
listener:RegisterEvent("PLAYER_LOGIN")
listener:RegisterEvent("PLAYER_LOGOUT")
listener:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        local addon = Cairn_Addon.registry[arg1]
        if addon then
            rawset(addon, "_initSeen", true)
            fireInit(addon)
        end
    elseif event == "PLAYER_LOGIN" then
        Cairn_Addon._loginFired = true
        for _, addon in pairs(Cairn_Addon.registry) do
            fireLogin(addon)
        end
    elseif event == "PLAYER_LOGOUT" then
        for _, addon in pairs(Cairn_Addon.registry) do
            safeCall(addon, "OnDisable")
        end
    end
end)


-- ---------------------------------------------------------------------------
-- Self-registration
-- ---------------------------------------------------------------------------
-- Cairn appears in its own `Cairn.GetRegistry()` output alongside its
-- consumers. Diagnostic-only — no Cairn-DB instance, no Cairn-Settings
-- panel, no auto-wiring (the `_internal` opt gates those phases).
--
-- Deferred via C_Timer.After(0, ...) so Cairn-DB / Cairn-Settings have
-- finished loading by the time this runs (they load AFTER Cairn-Addon in
-- the TOC). Without the defer, calling Register inline here would race
-- the load order, and even with `_internal` the future-proofing is
-- valuable — anything we add to Register that touches another Cairn lib
-- would silently break self-registration.
if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0, function()
        -- Guarded against re-entry: tocRegistry["Cairn"] check skips on
        -- /reload paths where Cairn-Addon's MINOR upgraded and the entry
        -- already exists.
        if not Cairn_Addon.tocRegistry["Cairn"] then
            _G.Cairn.Register("Cairn", _G.Cairn, { _internal = true })
        end
    end)
end


return Cairn_Addon
