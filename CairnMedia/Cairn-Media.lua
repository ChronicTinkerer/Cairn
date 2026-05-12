-- Cairn-Media
-- Two-mode media registry. Every entry is either PRIVATE (visible only to
-- Cairn consumers that call our :Get*) or PUBLIC (also registered with
-- LibSharedMedia-3.0 so cross-addon dropdowns in WeakAuras / ElvUI /
-- Details! / etc. can pick it up). Lookup is uniform across both buckets;
-- public wins on name collision.
--
-- Consumer view:
--
--   local Media = LibStub("Cairn-Media-1.0")
--
--   -- Path lookup (checks public then private; nil if neither has it)
--   Media:GetFont("Default")           -- "Fonts\\FRIZQT__.TTF"
--   Media:GetStatusbar("Plain")
--   Media:GetBorder("Tooltip")
--   Media:GetBackground("Solid")
--   Media:GetSound("Alert")
--
--   -- Listing
--   Media:ListFonts()                  -- every short name across both buckets
--   Media:ListFonts("public")          -- LSM-registered only
--   Media:ListFonts("private")         -- internal only
--   Media:ListPublicFonts()            -- sugar for the above
--   Media:ListPrivateFonts()
--
--   -- Iteration (sorted-by-name for deterministic output)
--   for name, path in Media:Iter("font") do ... end
--
--   -- Inspection
--   Media:Has("font", "Default")       -- registered in either bucket?
--   Media:IsPublic("font", "Default")  -- LSM-registered?
--
--   -- Direct LSM handle for one-off registrations or :IsValid checks
--   Media.LSM                          -- LibStub("LibSharedMedia-3.0", true)
--
--   -- Color helpers (Decisions 1-3, 5 from the 2026-05-12 walk; MINOR 15)
--   Media:GetExpansionColor("legion")   -- "FFA335EE" (nil for unknown)
--   Media:GetQualityColor("Epic")        -- ITEM_QUALITY_COLORS-backed
--   Media:GetFactionColor("Alliance")    -- FACTION_BAR_COLORS-backed
--   Media:GetThresholdColor(value, stops...) -> r, g, b
--   Media:GetThresholdColorHex(value, stops...) -> "FFAARRGGBB"
--
-- Five media types are supported: font, statusbar, border, background, sound.
-- v1 ships only Blizzard's own built-in paths as PRIVATE entries (no binary
-- files included; we just reference the canonical paths under friendly
-- names). The PUBLIC bucket starts empty — drop a free-license asset under
-- Cairn/CairnMedia/Assets/Public/<type>/ and add a `registerPublic`
-- line in the matching `_registerPublic*()` function below.
--
-- License: MIT.
-- Note: built-in Blizzard paths reference Blizzard's own client files,
-- which remain Blizzard's IP. This addon does not redistribute them —
-- it only references their canonical paths under friendly names.
-- Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Media-1.0"
local LIB_MINOR = 15

local Cairn_Media = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Media then return end


-- ---------------------------------------------------------------------------
-- LSM (soft dependency)
-- ---------------------------------------------------------------------------
-- LSM is the de facto cross-addon media registry. If a consumer ships an
-- embedded build that omits it, public registrations silently skip the LSM
-- call but still land in our private/public buckets — Cairn consumers using
-- :GetFont etc. don't notice. Don't add a hard LSM dep.

local LSM = LibStub("LibSharedMedia-3.0", true)
Cairn_Media.LSM = LSM


-- ---------------------------------------------------------------------------
-- Internal storage
-- ---------------------------------------------------------------------------
-- Two parallel buckets keyed by visibility. Preserved across MINOR upgrades
-- so consumers holding a cached reference to the lib pick up new entries
-- automatically.

Cairn_Media._media = Cairn_Media._media or {
    private = {
        font       = {},
        statusbar  = {},
        border     = {},
        background = {},
        sound      = {},
    },
    public = {
        font       = {},
        statusbar  = {},
        border     = {},
        background = {},
        sound      = {},
    },
}


-- Pre-built path prefixes for consumer assets dropped under the convention
-- folders. Use them to keep registration lines short:
--   registerPrivate("font", "Inter", PRIVATE_ASSETS .. [[fonts\Inter-Regular.otf]])
local PRIVATE_ASSETS = [[Interface\AddOns\Cairn\CairnMedia\Assets\Private\]]
local PUBLIC_ASSETS  = [[Interface\AddOns\Cairn\CairnMedia\Assets\Public\]]

-- Public-bucket entries register with LSM under "Cairn <ShortName>" so they
-- group alphabetically in third-party dropdowns and identify their source
-- at a glance.
local LSM_PREFIX = "Cairn "


-- ---------------------------------------------------------------------------
-- Internal: registration
-- ---------------------------------------------------------------------------

-- Private: lands in the private bucket only. Other addons' LSM dropdowns
-- never see it; only Cairn consumers calling :Get* find it.
local function registerPrivate(mediaType, shortName, path)
    local bucket = Cairn_Media._media.private[mediaType]
    if not bucket then
        error("Cairn-Media: unknown media type '" .. tostring(mediaType) .. "'", 2)
    end
    bucket[shortName] = path
end


-- Public: lands in the public bucket AND fires LSM:Register (when LSM is
-- loaded). The LSM_PREFIX namespacing means consumers of other addons see
-- "Cairn Inter" rather than just "Inter", which makes attribution clear in
-- their UI dropdowns.
local function registerPublic(mediaType, shortName, path)
    local bucket = Cairn_Media._media.public[mediaType]
    if not bucket then
        error("Cairn-Media: unknown media type '" .. tostring(mediaType) .. "'", 2)
    end
    bucket[shortName] = path
    if LSM then
        LSM:Register(mediaType, LSM_PREFIX .. shortName, path)
    end
end


-- ---------------------------------------------------------------------------
-- Default PRIVATE registrations (WoW built-ins)
-- ---------------------------------------------------------------------------
-- These are Blizzard's own font / texture / sound paths exposed under
-- friendly names. They work across every flavor (Retail / Mists / TBC /
-- Vanilla / XPTR) because Blizzard ships them with every client, so we
-- don't need per-flavor conditionals.

local function _registerPrivateFonts()
    registerPrivate("font", "Default",  [[Fonts\FRIZQT__.TTF]])  -- Friz Quadrata, WoW UI default
    registerPrivate("font", "Numeric",  [[Fonts\ARIALN.TTF]])    -- Arial Narrow, condensed for bars
    registerPrivate("font", "Heading",  [[Fonts\MORPHEUS.TTF]])  -- Morpheus, decorative headings
    registerPrivate("font", "Combat",   [[Fonts\skurri.TTF]])    -- Skurri, heavy display for combat text
end


local function _registerPrivateStatusbars()
    registerPrivate("statusbar", "Plain",  [[Interface\TargetingFrame\UI-StatusBar]])
    registerPrivate("statusbar", "Solid",  [[Interface\Buttons\WHITE8X8]])
end


local function _registerPrivateBorders()
    registerPrivate("border", "Tooltip", [[Interface\Tooltips\UI-Tooltip-Border]])
    registerPrivate("border", "Dialog",  [[Interface\DialogFrame\UI-DialogBox-Border]])
end


local function _registerPrivateBackgrounds()
    registerPrivate("background", "Tooltip", [[Interface\Tooltips\UI-Tooltip-Background]])
    registerPrivate("background", "Dialog",  [[Interface\DialogFrame\UI-DialogBox-Background]])
    registerPrivate("background", "Solid",   [[Interface\Buttons\WHITE8X8]])
end


local function _registerPrivateSounds()
    registerPrivate("sound", "Alert",   [[Sound\Interface\RaidWarning.ogg]])
    registerPrivate("sound", "Notify",  [[Sound\Interface\AuctionWindowOpen.ogg]])
    registerPrivate("sound", "LevelUp", [[Sound\Interface\LevelUp.ogg]])
end


-- ---------------------------------------------------------------------------
-- Default PUBLIC registrations
-- ---------------------------------------------------------------------------
-- Empty in v1. To share an asset through LSM (so WeakAuras / ElvUI / etc.
-- can use it), drop the file under Cairn/CairnMedia/Assets/Public/<type>/
-- and add a registerPublic line in the matching block.

local function _registerPublicFonts()
    -- Material Symbols (Apache 2.0). Three style families ship as PUBLIC
    -- fonts; consumers pair them with the icon-glyph registry in
    -- Cairn-Media-Icons.lua to render specific symbols. Variable-font
    -- files only — the static weight/optical-size instances aren't shipped
    -- because each variable font already covers every weight/fill/opsz
    -- combination at its default axes. LICENSE.txt + README.txt sit
    -- alongside each font file per the Apache 2.0 distribution terms.
    registerPublic("font", "MaterialOutlined",
        PUBLIC_ASSETS .. [[fonts\Material_Symbols_Outlined\MaterialSymbolsOutlined-VariableFont_FILL,GRAD,opsz,wght.ttf]])
    registerPublic("font", "MaterialRounded",
        PUBLIC_ASSETS .. [[fonts\Material_Symbols_Rounded\MaterialSymbolsRounded-VariableFont_FILL,GRAD,opsz,wght.ttf]])
    registerPublic("font", "MaterialSharp",
        PUBLIC_ASSETS .. [[fonts\Material_Symbols_Sharp\MaterialSymbolsSharp-VariableFont_FILL,GRAD,opsz,wght.ttf]])
end

local function _registerPublicStatusbars() end
local function _registerPublicBorders()    end
local function _registerPublicBackgrounds() end
local function _registerPublicSounds()     end


-- Run all default registrations. Idempotent on hot-reload: re-registering
-- the same shortName overwrites the path, and LSM dedupes on its end.
_registerPrivateFonts()
_registerPrivateStatusbars()
_registerPrivateBorders()
_registerPrivateBackgrounds()
_registerPrivateSounds()

_registerPublicFonts()
_registerPublicStatusbars()
_registerPublicBorders()
_registerPublicBackgrounds()
_registerPublicSounds()


-- ---------------------------------------------------------------------------
-- Public API: path lookup
-- ---------------------------------------------------------------------------

-- Public wins on collision: if you took the trouble to make something
-- public, you probably want consumers to use that version. Returns nil
-- (not the key) when neither bucket has the name — that's by design here,
-- because the typical use of Get* is "feed this directly to SetFont" and
-- a nil makes the failure visible at the call site.
local function fetch(mediaType, shortName)
    local pub = Cairn_Media._media.public[mediaType]
    if pub and pub[shortName] then return pub[shortName] end
    local priv = Cairn_Media._media.private[mediaType]
    return priv and priv[shortName] or nil
end


function Cairn_Media:GetFont(name)        return fetch("font",       name) end
function Cairn_Media:GetStatusbar(name)   return fetch("statusbar",  name) end
function Cairn_Media:GetBorder(name)      return fetch("border",     name) end
function Cairn_Media:GetBackground(name)  return fetch("background", name) end
function Cairn_Media:GetSound(name)       return fetch("sound",      name) end


-- ---------------------------------------------------------------------------
-- Public API: listing + iteration
-- ---------------------------------------------------------------------------

-- Sorts for deterministic output across runs. Returns a fresh array each
-- call so callers can mutate freely. Dedupes when merging buckets (public
-- entry hides a same-named private entry from the merged listing, which
-- matches the fetch() semantics).
local function listType(mediaType, visibility)
    local names = {}
    local seen  = {}

    local buckets
    if visibility == "public" then
        buckets = { Cairn_Media._media.public[mediaType] }
    elseif visibility == "private" then
        buckets = { Cairn_Media._media.private[mediaType] }
    elseif visibility == nil then
        buckets = { Cairn_Media._media.public[mediaType], Cairn_Media._media.private[mediaType] }
    else
        error('Cairn-Media: visibility must be nil, "public", or "private"', 3)
    end

    for _, bucket in ipairs(buckets) do
        if bucket then
            for shortName in pairs(bucket) do
                if not seen[shortName] then
                    seen[shortName] = true
                    names[#names + 1] = shortName
                end
            end
        end
    end
    table.sort(names)
    return names
end


function Cairn_Media:ListFonts(v)        return listType("font",       v) end
function Cairn_Media:ListStatusbars(v)   return listType("statusbar",  v) end
function Cairn_Media:ListBorders(v)      return listType("border",     v) end
function Cairn_Media:ListBackgrounds(v)  return listType("background", v) end
function Cairn_Media:ListSounds(v)       return listType("sound",      v) end


-- Sugar for the common "I want the public-only / private-only list" intent.
-- Equivalent to passing the visibility arg, but reads better at call sites
-- where the intent is explicit.
function Cairn_Media:ListPublicFonts()         return listType("font",       "public")  end
function Cairn_Media:ListPrivateFonts()        return listType("font",       "private") end
function Cairn_Media:ListPublicStatusbars()    return listType("statusbar",  "public")  end
function Cairn_Media:ListPrivateStatusbars()   return listType("statusbar",  "private") end
function Cairn_Media:ListPublicBorders()       return listType("border",     "public")  end
function Cairn_Media:ListPrivateBorders()      return listType("border",     "private") end
function Cairn_Media:ListPublicBackgrounds()   return listType("background", "public")  end
function Cairn_Media:ListPrivateBackgrounds()  return listType("background", "private") end
function Cairn_Media:ListPublicSounds()        return listType("sound",      "public")  end
function Cairn_Media:ListPrivateSounds()       return listType("sound",      "private") end


-- Stateless iterator with sorted-by-name order. Each call yields
-- (shortName, path) pairs for the requested type, optionally filtered by
-- visibility. Safe to call repeatedly or nest with other iterators.
function Cairn_Media:Iter(mediaType, visibility)
    local names = listType(mediaType, visibility)
    local i = 0
    return function()
        i = i + 1
        local name = names[i]
        if not name then return nil end
        return name, fetch(mediaType, name)
    end
end


-- ---------------------------------------------------------------------------
-- Public API: inspection
-- ---------------------------------------------------------------------------

-- Scoped to OUR registry, unlike LSM:IsValid which considers any registrant.
-- A consumer asking "does Cairn-Media know about this name?" wants this,
-- not LSM's global answer.
function Cairn_Media:Has(mediaType, shortName)
    local pub  = Cairn_Media._media.public[mediaType]
    if pub and pub[shortName] then return true end
    local priv = Cairn_Media._media.private[mediaType]
    return priv and priv[shortName] ~= nil or false
end


-- True iff the name is in the public bucket (and therefore LSM-registered
-- when LSM is loaded).
function Cairn_Media:IsPublic(mediaType, shortName)
    local pub = Cairn_Media._media.public[mediaType]
    return pub and pub[shortName] ~= nil or false
end


-- ---------------------------------------------------------------------------
-- Color palettes + value-to-color (Decisions 1-3, 5 from the 2026-05-12 walk)
-- ---------------------------------------------------------------------------
-- Cairn-Media's color helpers are a separate concern from the media-asset
-- registry above. Decision 4 (Colorize / ColorizeRGB string helpers) was
-- scoped to Cairn-Util.String per the walk; only the palette-style helpers
-- live here.

-- Expansion color palette (Decision 1). NOT in WoW globals. Centralized
-- here so Vellum zone displays, LibCodex catalog renderers, Forge_Addon-
-- Manager "loaded from" columns, etc. all reference the same canonical
-- hex. Recent expansions (TWW, Midnight) added with community-canonical
-- values when confirmed; current entries below match the row text from
-- the 2026-05-12 walk.
Cairn_Media._expansionColors = Cairn_Media._expansionColors or {
    classic      = "FFE6CC80",
    tbc          = "FF1EFF00",
    wotlk        = "FF66CCFF",
    cata         = "FFFF3300",
    mop          = "FF00FF96",
    wod          = "FFFF8C1A",
    legion       = "FFA335EE",
    bfa          = "FFFF7D0A",
    shadowlands  = "FFE6CC80",
    dragonflight = "FF33937F",
    -- TWW + Midnight: TBD pending community-canonical hex confirmation.
    -- Returning nil for these keeps consumers nil-safe; downstream UIs
    -- can fall back to a neutral color when the entry doesn't exist.
}


-- :GetExpansionColor(name) -> hex string or nil
--
-- Case-insensitive on `name` so consumers can pass `"Legion"` or `"LEGION"`
-- or `"legion"` interchangeably. Returns the 8-char AARRGGBB hex (the form
-- consumed by Cairn.Util.String.Colorize). nil for unknown names — caller
-- decides whether to default-color or skip.
function Cairn_Media:GetExpansionColor(name)
    if type(name) ~= "string" then return nil end
    return self._expansionColors[name:lower()]
end


-- :GetQualityColor(name) -> hex string or nil (Decision 2)
--
-- Thin name-based wrapper around WoW's `ITEM_QUALITY_COLORS` globals.
-- Maps standard quality names ("Poor", "Common", "Uncommon", "Rare",
-- "Epic", "Legendary", "Artifact", "Heirloom", "WowToken") to their
-- Blizzard-global hex values. Cairn-Media doesn't hardcode the hexes —
-- Blizzard's globals stay the source of truth.
--
-- Case-insensitive on name. Returns the `.hex` field directly (already
-- in AARRGGBB form).
local QUALITY_NAME_TO_INDEX = {
    poor       = 0,
    common     = 1,
    uncommon   = 2,
    rare       = 3,
    epic       = 4,
    legendary  = 5,
    artifact   = 6,
    heirloom   = 7,
    wowtoken   = 8,
}

function Cairn_Media:GetQualityColor(name)
    if type(name) ~= "string" then return nil end
    local idx = QUALITY_NAME_TO_INDEX[name:lower()]
    if not idx then return nil end
    local q = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[idx]
    if not q or not q.hex then return nil end

    -- Blizzard's `q.hex` is prefixed with the color escape ("|cff" + 6 hex
    -- digits = 10 chars). Strip the prefix and uppercase to return the raw
    -- 8-char AARRGGBB form matching GetExpansionColor / GetFactionColor /
    -- GetThresholdColorHex. Caller that wants the |cff... colorize-prefix
    -- form pipes through `Cairn.Util.String.Colorize(text, returnedHex)`.
    return q.hex:sub(3):upper()
end


-- :GetFactionColor(name) -> hex string or nil (Decision 3)
--
-- Same shape as GetQualityColor but for Alliance / Horde factions. WoW
-- exposes `FACTION_BAR_COLORS[i]` with `.r/.g/.b` floats — we read those
-- and format to AARRGGBB. Falls back to community-canonical hex when the
-- global isn't available (Classic Era clients), so the lookup never
-- silently fails on a known faction.
local FACTION_NAME_TO_INDEX = {
    alliance = 1,
    horde    = 2,
}

-- Fallback hexes for when FACTION_BAR_COLORS isn't loaded. Match the row
-- text from the 2026-05-12 walk (FF4A54E8 / FFE50D12).
local FACTION_FALLBACK_HEX = {
    alliance = "FF4A54E8",
    horde    = "FFE50D12",
}

function Cairn_Media:GetFactionColor(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    local idx = FACTION_NAME_TO_INDEX[key]
    if not idx then return nil end

    local fc = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[idx]
    if fc and fc.r and fc.g and fc.b then
        return string.format("FF%02X%02X%02X",
            math.floor((fc.r or 0) * 255 + 0.5),
            math.floor((fc.g or 0) * 255 + 0.5),
            math.floor((fc.b or 0) * 255 + 0.5))
    end
    return FACTION_FALLBACK_HEX[key]
end


-- :GetThresholdColor(value, ...) -> (r, g, b) (Decision 5)
-- :GetThresholdColorHex(value, ...) -> "FFAARRGGBB" or nil
--
-- Multi-stop value-to-color interpolator on a green-yellow-red gradient.
-- Variadic threshold stops; can be ascending or descending. The position
-- of `value` within the stops determines the interpolated color along
-- the gradient.
--
-- Example use cases:
--   :GetThresholdColor(latencyMs, 1000, 500, 250, 100, 0)
--     -> color for "350ms" interpolates between the 500 and 250 stops
--   :GetThresholdColor(quality, 0, 0.25, 0.5, 0.75, 1.0)
--     -> color for a [0, 1] quality input
--
-- NaN guard: `q ~= q` is the canonical Lua NaN test (only NaN doesn't
-- equal itself). Returns the midpoint gradient color on NaN/Inf to avoid
-- crashing consumer UIs.
--
-- The gradient: red (1, 0, 0) → yellow (1, 1, 0) → green (0, 1, 0) when
-- value runs from "worst" to "best." "Worst" is the first stop when stops
-- are descending (e.g. latency: 1000ms is worst), the last stop when
-- ascending (e.g. quality: 0.0 is worst).

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Returns (r, g, b) for a [0, 1] position along green (good) → red (bad).
-- 0.0 = green, 0.5 = yellow, 1.0 = red.
local function gradientGYR(pos)
    if pos <= 0.5 then
        -- green → yellow
        return lerp(0, 1, pos * 2), 1, 0
    else
        -- yellow → red
        return 1, lerp(1, 0, (pos - 0.5) * 2), 0
    end
end

function Cairn_Media:GetThresholdColor(value, ...)
    local nStops = select("#", ...)
    if nStops < 2 then
        -- Need at least 2 stops to interpolate. Return neutral yellow.
        return 1, 1, 0
    end

    -- NaN / Inf guards.
    if value ~= value then return 1, 1, 0 end           -- NaN
    if value == math.huge or value == -math.huge then
        return 1, 1, 0                                   -- Inf
    end

    -- Build stops array; detect direction.
    local stops = {}
    for i = 1, nStops do stops[i] = select(i, ...) end
    local descending = stops[1] > stops[nStops]

    -- For descending stops (worst-first), invert so we map highest-value
    -- to "bad" (red, pos=1). For ascending stops (best-first → worst-last
    -- OR ambiguous), bad is at the last stop.
    --
    -- Convention from the row text: descending list (1000, 500, 250, 100,
    -- 0) means 1000 = worst. So when descending: clamp(value, last, first)
    -- and the position-of-bad is the first stop.
    local lo, hi
    if descending then
        lo, hi = stops[nStops], stops[1]
    else
        lo, hi = stops[1], stops[nStops]
    end

    -- Clamp to range.
    local clamped = value
    if clamped < lo then clamped = lo end
    if clamped > hi then clamped = hi end

    -- Normalize to [0, 1] where 0 = best (green), 1 = worst (red).
    local pos
    if hi == lo then
        pos = 0
    elseif descending then
        -- Higher value = worse.
        pos = (clamped - lo) / (hi - lo)
    else
        -- Lower value = worse. Invert.
        pos = 1 - (clamped - lo) / (hi - lo)
    end

    return gradientGYR(pos)
end


function Cairn_Media:GetThresholdColorHex(value, ...)
    local r, g, b = self:GetThresholdColor(value, ...)
    return string.format("FF%02X%02X%02X",
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end


return Cairn_Media
