--[[
Cairn-Media-1.0

A two-mode media registry for Cairn-using addons. Supports both:

  * PRIVATE entries (default) — stored only in this lib's internal table.
    Visible to consumers that explicitly call `Cairn.Media:Get<Type>(name)`.
    NOT visible to other addons' `LibSharedMedia-3.0` dropdowns
    (WeakAuras, ElvUI, Details!, etc.).

  * PUBLIC entries — stored in the internal table AND registered with
    `LibSharedMedia-3.0` under the name "Cairn <ShortName>". Visible to
    every LSM consumer in the user's client.

Lookup is always uniform: `Media:GetFont(name)` checks both buckets and
returns the path. Public wins on a name collision (rationale: if you took
the trouble to make something public, you probably want consumers to use
that version). Filtered listings (`ListPublicFonts` / `ListPrivateFonts`)
let consumers reason about which entries get cross-addon exposure.

Folder convention for user-supplied assets:

	CairnMedia/Assets/Private/{fonts, statusbars, borders, backgrounds, sounds}/
	CairnMedia/Assets/Public/{fonts,  statusbars, borders, backgrounds, sounds}/

Drop a file into the appropriate folder and add a one-line registration
in the matching `_registerPrivate*` / `_registerPublic*` block below.
The constants `PRIVATE_ASSETS` and `PUBLIC_ASSETS` are pre-built path
prefixes for those folders.

Initial release ships WoW's built-in fonts / textures / sounds as
PRIVATE entries (Blizzard's own paths, no binary files included). The
public bucket starts empty — drop a free-license font in
`Assets/Public/fonts/` and call `registerPublic("font", "Inter", ...)`
to share it through LSM.

Public API:

	local Media = LibStub("Cairn-Media-1.0")

	-- Path lookup (checks both buckets; public wins on collision).
	Media:GetFont("Default")
	Media:GetStatusbar("Plain")
	Media:GetBorder("Tooltip")
	Media:GetBackground("Solid")
	Media:GetSound("Alert")

	-- Listing — visibility arg is optional. nil = merged, "public" / "private"
	-- filter to that bucket.
	Media:ListFonts()                    -- every short name across both buckets
	Media:ListFonts("public")            -- LSM-registered names only
	Media:ListFonts("private")           -- internal-only names

	-- Iteration with optional visibility filter:
	for name, path in Media:Iter("font") do ... end
	for name, path in Media:Iter("font", "public") do ... end

	-- Inspection:
	Media:Has("font", "Default")          -- true if in either bucket
	Media:IsPublic("font", "Default")     -- true if in the public bucket

	-- Direct LSM access for cases the sugar doesn't cover (custom one-off
	-- registrations of consumer assets, IsValid checks, etc.).
	Media.LSM                              -- LibStub("LibSharedMedia-3.0", true)

	-- Icon glyphs (separate from the five media types). Render an icon by
	-- pairing one of the Material* fonts with the glyph string for a name:
	Media:GetIconCodepoint("close")        -- 0xE5CD (integer)
	Media:GetIconGlyph("close")            -- UTF-8 glyph string for SetText
	Media:HasIcon("close")
	Media:ListIcons()                      -- sorted array of names
	for name, cp in Media:IterIcons() do ... end
	Media:RegisterIcon("custom", 0xE9F0)   -- consumer extension

	-- Render example:
	fs:SetFont(Media:GetFont("MaterialOutlined"), 16, "")
	fs:SetText(Media:GetIconGlyph("close"))
	fs:SetTextColor(1, 1, 1)

Soft-dep tie-in:

	Cairn-Gui-Theme-Default-2.0 looks for Cairn-Media at file-scope load
	and prefers `Cairn.Media:GetFontPath("Default")` over STANDARD_TEXT_FONT
	when present. The lookup is mode-agnostic — works whether "Default" is
	currently a private entry (Blizzard built-in) or a public override.

Cairn-Media-1.0 (c) 2026 ChronicTinkerer. MIT license.
The Blizzard asset paths used by the default private registrations
reference Blizzard's own client files, which remain Blizzard's
intellectual property. This addon does not redistribute them; it only
references their canonical paths under friendly names.
]]

local MAJOR, MINOR = "Cairn-Media-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- a same-or-newer version is already loaded

-- ----- LSM (optional) -----------------------------------------------------

-- LSM is loaded by Cairn (vendored under Libs/), but probe defensively so
-- embedded consumers that omit LSM still get private registrations.
local LSM = LibStub("LibSharedMedia-3.0", true)
lib.LSM = LSM

-- ----- Storage ------------------------------------------------------------

-- Reuse the registry across hot reloads so old consumers caching `Media`
-- pick up new entries without recreation. Two parallel buckets keyed by
-- visibility; `:Get*` merges them at lookup time (public wins on collision).
lib._media = lib._media or {
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

-- ----- Asset path helpers -------------------------------------------------

-- Pre-built addon-relative path prefixes for user-supplied assets. Use
-- these when registering files dropped into the corresponding folder so
-- the registration line stays short.
local PRIVATE_ASSETS = [[Interface\AddOns\Cairn\CairnMedia\Assets\Private\]]
local PUBLIC_ASSETS  = [[Interface\AddOns\Cairn\CairnMedia\Assets\Public\]]

-- LSM dropdown prefix. Public entries register as "Cairn <ShortName>"
-- so they group together in alphabetical dropdowns and visually
-- identify their source.
local LSM_PREFIX = "Cairn "

-- Internal: register a private entry. Stores the path; nothing visible to
-- LSM. Idempotent — re-registering the same shortName overwrites the path.
local function registerPrivate(mediaType, shortName, path)
	local bucket = lib._media.private[mediaType]
	if not bucket then
		error("Cairn-Media: unknown media type '" .. tostring(mediaType) .. "'", 2)
	end
	bucket[shortName] = path
end

-- Internal: register a public entry. Stores the path AND registers with
-- LSM under "Cairn <ShortName>". Skips the LSM call silently if LSM isn't
-- loaded (embedded consumers who omitted LibSharedMedia-3.0); the entry
-- still works internally.
local function registerPublic(mediaType, shortName, path)
	local bucket = lib._media.public[mediaType]
	if not bucket then
		error("Cairn-Media: unknown media type '" .. tostring(mediaType) .. "'", 2)
	end
	bucket[shortName] = path
	if LSM then
		LSM:Register(mediaType, LSM_PREFIX .. shortName, path)
	end
end

-- ====================================================================
-- ============ PRIVATE registrations (internal only) =================
-- ====================================================================
-- These entries are NOT visible to other addons via LSM. Use for assets
-- that are only meant for Cairn consumers (Vellum, Forge, the Cairn-Gui-2.0
-- default theme, etc.).

-- ----- Private fonts ------------------------------------------------------
-- Roles:
--   Default  - body / general UI text. The WoW UI default.
--   Numeric  - condensed for tight numeric readouts (nameplates, bars).
--   Heading  - decorative for chapter / section headers.
--   Combat   - heavy display weight for combat text and call-outs.
--
-- Built-in fonts are universally available across every locale of every
-- shipping WoW client (Retail, Classic Era, MoP Classic, TBC Classic,
-- XPTR). Using Blizzard paths avoids per-flavor font availability checks.

local function _registerPrivateFonts()
	registerPrivate("font", "Default",  [[Fonts\FRIZQT__.TTF]])  -- Friz Quadrata
	registerPrivate("font", "Numeric",  [[Fonts\ARIALN.TTF]])    -- Arial Narrow
	registerPrivate("font", "Heading",  [[Fonts\MORPHEUS.TTF]])  -- Morpheus
	registerPrivate("font", "Combat",   [[Fonts\skurri.TTF]])    -- Skurri

	-- Drop-in slot: add free-license fonts to CairnMedia\Assets\Private\fonts\
	-- and register them here. Example:
	--   registerPrivate("font", "Inter", PRIVATE_ASSETS .. [[fonts\Inter-Regular.otf]])
end

-- ----- Private statusbars -------------------------------------------------
local function _registerPrivateStatusbars()
	registerPrivate("statusbar", "Plain",  [[Interface\TargetingFrame\UI-StatusBar]])
	registerPrivate("statusbar", "Solid",  [[Interface\Buttons\WHITE8X8]])

	-- Drop-in: CairnMedia\Assets\Private\statusbars\<file> +
	--   registerPrivate("statusbar", "Smooth", PRIVATE_ASSETS .. [[statusbars\smooth.tga]])
end

-- ----- Private borders ----------------------------------------------------
local function _registerPrivateBorders()
	registerPrivate("border", "Tooltip", [[Interface\Tooltips\UI-Tooltip-Border]])
	registerPrivate("border", "Dialog",  [[Interface\DialogFrame\UI-DialogBox-Border]])

	-- Drop-in: CairnMedia\Assets\Private\borders\<file> + registerPrivate(...)
end

-- ----- Private backgrounds ------------------------------------------------
local function _registerPrivateBackgrounds()
	registerPrivate("background", "Tooltip", [[Interface\Tooltips\UI-Tooltip-Background]])
	registerPrivate("background", "Dialog",  [[Interface\DialogFrame\UI-DialogBox-Background]])
	registerPrivate("background", "Solid",   [[Interface\Buttons\WHITE8X8]])

	-- Drop-in: CairnMedia\Assets\Private\backgrounds\<file> + registerPrivate(...)
end

-- ----- Private sounds -----------------------------------------------------
local function _registerPrivateSounds()
	registerPrivate("sound", "Alert",   [[Sound\Interface\RaidWarning.ogg]])
	registerPrivate("sound", "Notify",  [[Sound\Interface\AuctionWindowOpen.ogg]])
	registerPrivate("sound", "LevelUp", [[Sound\Interface\LevelUp.ogg]])

	-- Drop-in: CairnMedia\Assets\Private\sounds\<file> + registerPrivate(...)
end

-- ====================================================================
-- ============ PUBLIC registrations (also LSM-visible) ===============
-- ====================================================================
-- Entries here ALSO appear in LSM under "Cairn <ShortName>", so other
-- addons (WeakAuras / ElvUI / Details! / etc.) can pick them up via
-- their LSM-backed media dropdowns. Use for assets you want to share
-- with the wider WoW addon ecosystem.
--
-- The buckets start empty in v1. Drop free-license assets in
-- CairnMedia/Assets/Public/<type>/ and add a registerPublic(...) line
-- in the matching block.

local function _registerPublicFonts()
	-- Material Symbols (Apache 2.0). Three style families ship as PUBLIC fonts;
	-- consumers can pick whichever fits their UI and use the icon-glyph registry
	-- below to render specific symbols. Variable fonts only — the static
	-- weight/optical-size instances are deliberately not bundled (each variable
	-- font already covers every weight/fill/optical-size at its default axes).
	-- LICENSE.txt + README.txt ship alongside each font per Apache 2.0.
	registerPublic("font", "MaterialOutlined",
		PUBLIC_ASSETS .. [[fonts\Material_Symbols_Outlined\MaterialSymbolsOutlined-VariableFont_FILL,GRAD,opsz,wght.ttf]])
	registerPublic("font", "MaterialRounded",
		PUBLIC_ASSETS .. [[fonts\Material_Symbols_Rounded\MaterialSymbolsRounded-VariableFont_FILL,GRAD,opsz,wght.ttf]])
	registerPublic("font", "MaterialSharp",
		PUBLIC_ASSETS .. [[fonts\Material_Symbols_Sharp\MaterialSymbolsSharp-VariableFont_FILL,GRAD,opsz,wght.ttf]])

	-- Drop-in slot: more free-license fonts go here. Example:
	-- registerPublic("font", "Inter", PUBLIC_ASSETS .. [[fonts\Inter-Regular.otf]])
	-- registerPublic("font", "Mono",  PUBLIC_ASSETS .. [[fonts\JetBrainsMono-Regular.ttf]])
end

local function _registerPublicStatusbars()
	-- Example:
	-- registerPublic("statusbar", "Smooth", PUBLIC_ASSETS .. [[statusbars\smooth.tga]])
end

local function _registerPublicBorders()
	-- Example:
	-- registerPublic("border", "Pixel", PUBLIC_ASSETS .. [[borders\pixel.tga]])
end

local function _registerPublicBackgrounds()
	-- Example:
	-- registerPublic("background", "Pixel", PUBLIC_ASSETS .. [[backgrounds\pixel.tga]])
end

local function _registerPublicSounds()
	-- Example:
	-- registerPublic("sound", "Soft", PUBLIC_ASSETS .. [[sounds\soft.ogg]])
end

-- Run all registrations. Safe to re-run on a hot reload (idempotent
-- assignments; LSM dedupes too).
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

-- ----- Public API ---------------------------------------------------------

-- Generic resolver. Checks the public bucket first (so a public override
-- wins on collision), then private. Returns the file path string, or nil
-- when not registered in either.
local function fetch(mediaType, shortName)
	local pub = lib._media.public[mediaType]
	if pub and pub[shortName] then return pub[shortName] end
	local priv = lib._media.private[mediaType]
	return priv and priv[shortName] or nil
end

function lib:GetFont(name)        return fetch("font", name) end
function lib:GetStatusbar(name)   return fetch("statusbar", name) end
function lib:GetBorder(name)      return fetch("border", name) end
function lib:GetBackground(name)  return fetch("background", name) end
function lib:GetSound(name)       return fetch("sound", name) end

-- Path-only aliases. Identical to the Get* methods today, but exist as
-- stable names for theme code that reads "the path" semantically rather
-- than "fetch from registry."
lib.GetFontPath        = lib.GetFont
lib.GetStatusbarPath   = lib.GetStatusbar
lib.GetBorderPath      = lib.GetBorder
lib.GetBackgroundPath  = lib.GetBackground
lib.GetSoundPath       = lib.GetSound

-- ----- Listing & iteration ------------------------------------------------

-- Internal: build a sorted array of short names for (mediaType, visibility).
-- visibility is nil (merged across both buckets, deduplicated), "public",
-- or "private". Returns a fresh array each call.
local function listType(mediaType, visibility)
	local names = {}
	local seen  = {}

	local buckets
	if visibility == "public" then
		buckets = { lib._media.public[mediaType] }
	elseif visibility == "private" then
		buckets = { lib._media.private[mediaType] }
	elseif visibility == nil then
		buckets = { lib._media.public[mediaType], lib._media.private[mediaType] }
	else
		error('Cairn.Media: visibility must be nil, "public", or "private"', 3)
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

function lib:ListFonts(visibility)        return listType("font",       visibility) end
function lib:ListStatusbars(visibility)   return listType("statusbar",  visibility) end
function lib:ListBorders(visibility)      return listType("border",     visibility) end
function lib:ListBackgrounds(visibility)  return listType("background", visibility) end
function lib:ListSounds(visibility)       return listType("sound",      visibility) end

-- Convenience: filtered list helpers. Equivalent to ListFonts("public")
-- etc., but read more naturally at call sites that want explicit intent.
function lib:ListPublicFonts()         return listType("font",       "public") end
function lib:ListPrivateFonts()        return listType("font",       "private") end
function lib:ListPublicStatusbars()    return listType("statusbar",  "public") end
function lib:ListPrivateStatusbars()   return listType("statusbar",  "private") end
function lib:ListPublicBorders()       return listType("border",     "public") end
function lib:ListPrivateBorders()      return listType("border",     "private") end
function lib:ListPublicBackgrounds()   return listType("background", "public") end
function lib:ListPrivateBackgrounds()  return listType("background", "private") end
function lib:ListPublicSounds()        return listType("sound",      "public") end
function lib:ListPrivateSounds()       return listType("sound",      "private") end

-- Inspection: was a particular short name registered for the given type
-- in EITHER bucket? Different from LSM:IsValid (which considers any
-- third-party registrant) — this is scoped to Cairn-Media's own entries.
function lib:Has(mediaType, shortName)
	local pub  = lib._media.public[mediaType]
	if pub and pub[shortName] then return true end
	local priv = lib._media.private[mediaType]
	return priv and priv[shortName] ~= nil or false
end

-- Inspection: is a short name in the public bucket? (And therefore
-- LSM-registered when LSM is loaded.)
function lib:IsPublic(mediaType, shortName)
	local pub = lib._media.public[mediaType]
	return pub and pub[shortName] ~= nil or false
end

-- Iteration: walk (shortName, path) pairs for a given type. Optional
-- visibility filter. Stateless; safe to call multiple times. Iteration
-- order is sorted-by-name for deterministic output.
function lib:Iter(mediaType, visibility)
	local names = listType(mediaType, visibility)
	local i = 0
	return function()
		i = i + 1
		local name = names[i]
		if not name then return nil end
		return name, fetch(mediaType, name)
	end
end

-- ====================================================================
-- ============ Icon glyph registry (separate from media types) =======
-- ====================================================================
-- Icon glyphs are name -> codepoint pairs for use with one of the icon
-- fonts registered above (MaterialOutlined / MaterialRounded /
-- MaterialSharp). Render an icon by setting a FontString's font to one of
-- those, then setting text to the glyph string. Sugar:
--
--   local Media = Cairn.Media
--   fs:SetFont(Media:GetFont("MaterialOutlined"), 16, "")
--   fs:SetText(Media:GetIconGlyph("close"))   -- close icon
--   fs:SetTextColor(1, 1, 1)
--
-- The codepoints below are stable Material Design Icons / Material Symbols
-- codepoints in the Unicode Private Use Area (U+E000 - U+F8FF). Curated
-- starter set of ~45 commonly-needed UI / WoW glyphs; consumers can extend
-- via :RegisterIcon(name, codepoint).

lib._icons = lib._icons or {}

local function registerIcon(name, codepoint)
	lib._icons[name] = codepoint
end

local function _registerIcons()
	-- Navigation / chrome (cursor, frame controls, paging)
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
	registerIcon("expand_more",    0xE5CF)  -- down chevron
	registerIcon("expand_less",    0xE5CE)  -- up chevron
	registerIcon("first_page",     0xE5DC)
	registerIcon("last_page",      0xE5DD)

	-- Actions (CRUD, common buttons)
	registerIcon("add",            0xE145)
	registerIcon("remove",         0xE15B)
	registerIcon("check",          0xE5CA)
	registerIcon("cancel",         0xE5C9)
	registerIcon("delete",         0xE872)  -- trash can
	registerIcon("edit",           0xE3C9)  -- pencil
	registerIcon("save",           0xE161)  -- floppy disk
	registerIcon("refresh",        0xE5D5)
	registerIcon("search",         0xE8B6)
	registerIcon("settings",       0xE8B8)  -- cog
	registerIcon("filter_list",    0xE152)
	registerIcon("sort",           0xE164)
	registerIcon("done",           0xE876)

	-- Status (indicators, dialogs)
	registerIcon("info",           0xE88E)
	registerIcon("warning",        0xE002)  -- triangle
	registerIcon("error",          0xE000)  -- circle X
	registerIcon("help",           0xE887)
	registerIcon("check_circle",   0xE86C)

	-- Toggles / state
	registerIcon("visibility",     0xE8F4)  -- eye
	registerIcon("visibility_off", 0xE8F5)
	registerIcon("lock",           0xE897)
	registerIcon("lock_open",      0xE898)
	registerIcon("star",           0xE838)
	registerIcon("favorite",       0xE87D)  -- heart
	registerIcon("bookmark",       0xE866)

	-- Containers / objects
	registerIcon("folder",         0xE2C7)
	registerIcon("description",    0xE873)  -- document / file
	registerIcon("home",           0xE88A)
	registerIcon("person",         0xE7FD)
	registerIcon("group",          0xE7EF)
	registerIcon("notifications",  0xE7F4)  -- bell

	-- WoW-flavored
	registerIcon("emoji_events",   0xEA65)  -- trophy
	registerIcon("bolt",           0xEA0B)  -- lightning
	registerIcon("shield",         0xE9E0)
	registerIcon("speed",          0xE9E4)
	registerIcon("map",            0xE55B)
	registerIcon("explore",        0xE87A)  -- compass
	registerIcon("timer",          0xE425)
	registerIcon("schedule",       0xE8B5)  -- clock
end

_registerIcons()

-- Internal: convert a codepoint to its UTF-8 string. Uses the standard
-- `utf8` library when available (modern WoW clients, 8.0+); falls back to
-- a manual 1/2/3-byte encoder for older clients. All Material Symbols
-- glyphs are in the BMP Private Use Area (U+E000 - U+F8FF), which the
-- 3-byte fallback handles. Returns nil for codepoints outside U+0000 - U+FFFF
-- under the fallback (Material Symbols never goes that high).
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

-- Public icon API ----------------------------------------------------------

-- Returns the integer codepoint for the named icon, or nil if unregistered.
function lib:GetIconCodepoint(name)
	return lib._icons[name]
end

-- Returns the UTF-8 glyph string for the named icon (suitable for SetText),
-- or nil if unregistered. Pair with one of the Material* fonts.
function lib:GetIconGlyph(name)
	local cp = lib._icons[name]
	if not cp then return nil end
	return codepointToUTF8(cp)
end

-- Inspection: was the named icon registered?
function lib:HasIcon(name)
	return lib._icons[name] ~= nil
end

-- Returns a fresh sorted array of every registered icon name.
function lib:ListIcons()
	local names = {}
	for n in pairs(lib._icons) do
		names[#names + 1] = n
	end
	table.sort(names)
	return names
end

-- Iteration: walk (name, codepoint) pairs sorted by name. Stateless.
function lib:IterIcons()
	local names = self:ListIcons()
	local i = 0
	return function()
		i = i + 1
		local name = names[i]
		if not name then return nil end
		return name, lib._icons[name]
	end
end

-- Programmatic add. Use this from consumer code to extend the registry
-- without editing this file. Codepoint must be a number; name must be a
-- non-empty string. Re-registering the same name overwrites silently.
function lib:RegisterIcon(name, codepoint)
	if type(name) ~= "string" or name == "" then
		error("Cairn.Media:RegisterIcon: name must be a non-empty string", 2)
	end
	if type(codepoint) ~= "number" then
		error("Cairn.Media:RegisterIcon: codepoint must be a number", 2)
	end
	lib._icons[name] = codepoint
end
