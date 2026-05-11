-- Cairn-Media-Icons
-- Attaches the Icons sub-API to Cairn-Media. Glyph codepoints are
-- name-keyed; pair them with one of the Material Symbols fonts registered
-- in Cairn-Media.lua to render the icons.
--
-- Render example:
--
--   local Media = LibStub("Cairn-Media")
--   fs:SetFont(Media:GetFont("MaterialOutlined"), 16, "")
--   fs:SetText(Media:GetIconGlyph("close"))
--   fs:SetTextColor(1, 1, 1)
--
-- Public API:
--
--   Media:GetIconCodepoint(name)   -> integer or nil
--   Media:GetIconGlyph(name)       -> UTF-8 string or nil (paste into SetText)
--   Media:HasIcon(name)            -> boolean
--   Media:ListIcons()              -> sorted array of names
--   for name, cp in Media:IterIcons() do ... end
--   Media:RegisterIcon(name, codepoint)   -> consumer extension
--
-- The starter set covers ~45 commonly-needed UI / WoW glyphs from Material
-- Symbols. All codepoints are in the Unicode Private Use Area (U+E000 -
-- U+F8FF), which the BMP UTF-8 encoder handles in three bytes. Consumers
-- can extend the registry at runtime via :RegisterIcon — no need to edit
-- this file.
--
-- License: MIT (this file's own code). The Material Symbols glyphs
-- themselves are Apache 2.0; codepoints are integer constants, not
-- copyrightable.
-- Author: ChronicTinkerer.

local Cairn_Media = LibStub and LibStub("Cairn-Media", true)
if not Cairn_Media then
    -- Cairn-Media's main file must load first. Loud failure beats silent
    -- no-op for a misordered .toc.
    error("Cairn-Media-Icons: Cairn-Media main lib is not loaded. " ..
          "Ensure Cairn-Media.lua is listed in the .toc before Cairn-Media-Icons.lua.")
end


-- Preserved across MINOR upgrades so consumer-registered icons survive a
-- hot reload.
Cairn_Media._icons = Cairn_Media._icons or {}


-- ---------------------------------------------------------------------------
-- Internal: codepoint → UTF-8 encoding
-- ---------------------------------------------------------------------------
-- WoW's modern Retail clients ship the utf8 stdlib; older flavors don't.
-- The 3-byte branch covers the entire BMP (U+0000 - U+FFFF), which is all
-- we ever need here — Material Symbols glyphs all live in the Private Use
-- Area (U+E000 - U+F8FF). Returns nil for codepoints above U+FFFF under
-- the fallback so a corrupt registration surfaces as a missing glyph
-- rather than a string of mangled bytes.

local function codepointToUTF8(cp)
    if utf8 and utf8.char then
        return utf8.char(cp)
    end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(
            0xC0 + math.floor(cp / 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor((cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    end
    return nil
end


-- ---------------------------------------------------------------------------
-- Starter icon set
-- ---------------------------------------------------------------------------
-- ~45 commonly-needed glyphs. Codepoints are stable Material Symbols values
-- from the Unicode Private Use Area. Extend in consumer code via
-- :RegisterIcon rather than editing this list — the goal here is a curated
-- baseline, not exhaustive coverage of Material's 3000+ icons.

local function registerIcon(name, codepoint)
    Cairn_Media._icons[name] = codepoint
end


-- Navigation / chrome
registerIcon("close",          0xE5CD)
registerIcon("menu",           0xE5D2)
registerIcon("more_vert",      0xE5D4)
registerIcon("more_horiz",     0xE5D3)
registerIcon("arrow_back",     0xE5C4)
registerIcon("arrow_forward",  0xE5C8)
registerIcon("arrow_upward",   0xE5D8)
registerIcon("arrow_downward", 0xE5DB)
registerIcon("chevron_left",   0xE5CB)
registerIcon("chevron_right",  0xE5CC)
registerIcon("expand_more",    0xE5CF)
registerIcon("expand_less",    0xE5CE)
registerIcon("first_page",     0xE5DC)
registerIcon("last_page",      0xE5DD)

-- Actions
registerIcon("add",            0xE145)
registerIcon("remove",         0xE15B)
registerIcon("check",          0xE5CA)
registerIcon("cancel",         0xE5C9)
registerIcon("delete",         0xE872)
registerIcon("edit",           0xE3C9)
registerIcon("save",           0xE161)
registerIcon("refresh",        0xE5D5)
registerIcon("search",         0xE8B6)
registerIcon("settings",       0xE8B8)
registerIcon("filter_list",    0xE152)
registerIcon("sort",           0xE164)
registerIcon("done",           0xE876)

-- Status / dialogs
registerIcon("info",           0xE88E)
registerIcon("warning",        0xE002)
registerIcon("error",          0xE000)
registerIcon("help",           0xE887)
registerIcon("check_circle",   0xE86C)

-- Toggles / state
registerIcon("visibility",     0xE8F4)
registerIcon("visibility_off", 0xE8F5)
registerIcon("lock",           0xE897)
registerIcon("lock_open",      0xE898)
registerIcon("star",           0xE838)
registerIcon("favorite",       0xE87D)
registerIcon("bookmark",       0xE866)

-- Containers / objects
registerIcon("folder",         0xE2C7)
registerIcon("description",    0xE873)
registerIcon("home",           0xE88A)
registerIcon("person",         0xE7FD)
registerIcon("group",          0xE7EF)
registerIcon("notifications",  0xE7F4)

-- WoW-flavored
registerIcon("emoji_events",   0xEA65)
registerIcon("bolt",           0xEA0B)
registerIcon("shield",         0xE9E0)
registerIcon("speed",          0xE9E4)
registerIcon("map",            0xE55B)
registerIcon("explore",        0xE87A)
registerIcon("timer",          0xE425)
registerIcon("schedule",       0xE8B5)


-- ---------------------------------------------------------------------------
-- Public API (mounted on Cairn-Media itself, not a sub-namespace)
-- ---------------------------------------------------------------------------

function Cairn_Media:GetIconCodepoint(name)
    return self._icons[name]
end


-- Glyph string for direct SetText use. Pairing with a non-Material font
-- renders as the underlying codepoint, which usually shows up as a missing-
-- glyph box — that's fine as a debugging signal.
function Cairn_Media:GetIconGlyph(name)
    local cp = self._icons[name]
    if not cp then return nil end
    return codepointToUTF8(cp)
end


function Cairn_Media:HasIcon(name)
    return self._icons[name] ~= nil
end


-- Sorted-by-name for deterministic UI listings (icon picker dropdowns,
-- documentation tools). Returns a fresh array so callers can mutate freely.
function Cairn_Media:ListIcons()
    local names = {}
    for n in pairs(self._icons) do
        names[#names + 1] = n
    end
    table.sort(names)
    return names
end


-- Stateless iterator with the same sort order as :ListIcons. Safe to nest
-- or call multiple times concurrently.
function Cairn_Media:IterIcons()
    local names = self:ListIcons()
    local i = 0
    return function()
        i = i + 1
        local name = names[i]
        if not name then return nil end
        return name, self._icons[name]
    end
end


-- Consumer extension. Re-registering an existing name is a silent overwrite
-- (matches the media :registerPrivate semantics).
function Cairn_Media:RegisterIcon(name, codepoint)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Media:RegisterIcon: name must be a non-empty string", 2)
    end
    if type(codepoint) ~= "number" then
        error("Cairn-Media:RegisterIcon: codepoint must be a number", 2)
    end
    self._icons[name] = codepoint
end
