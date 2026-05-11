-- Cairn-Media
-- Two-mode media registry. Every entry is either PRIVATE (visible only to
-- Cairn consumers that call our :Get*) or PUBLIC (also registered with
-- LibSharedMedia-3.0 so cross-addon dropdowns in WeakAuras / ElvUI /
-- Details! / etc. can pick it up). Lookup is uniform across both buckets;
-- public wins on name collision.
--
-- Consumer view:
--
--   local Media = LibStub("Cairn-Media")
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

local LIB_MAJOR = "Cairn-Media"
local LIB_MINOR = 1

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


return Cairn_Media
