--[[
Cairn-Gui-2.0 / Core / Theme

Cascading theme system per Decision 5. Themes are named registered
objects that map tokens (e.g. "color.bg.panel") to typed values. Tokens
resolve through a five-step cascade so every consumer (widget primitive,
custom drawing code, animation transition) reads them the same way.

Public API on the lib:

	Cairn.Gui:RegisterTheme(name, def)
		def: {
			extends = "Cairn.Default" or nil,    -- single inheritance
			tokens  = { ["color.bg.panel"] = {0.05, 0.05, 0.06, 0.98}, ... },
		}
		Validates each token's value against its type (inferred from the
		name prefix). Throws on bad type or unknown prefix.

	Cairn.Gui:SetActiveTheme(name)
	Cairn.Gui:GetActiveTheme() -> name or nil

	Cairn.Gui:ResolveToken(tokenName, widgetCairn?) -> value or nil
		Five-step resolution:
			1. widgetCairn._tokenOverrides[tokenName] (per-instance)
			2. nearest ancestor cairn._theme tokens (subtree theme)
			3. active global theme tokens
			4. active theme's `extends` chain
			5. library hardcoded default
		Returns nil if not registered anywhere and no default exists.

Public API on widget.Cairn (added to Mixins.Base by this file):

	widget.Cairn:SetTheme(themeName)       -- bind a subtree theme
	widget.Cairn:GetTheme() -> name or nil
	widget.Cairn:SetTokenOverride(tokenName, value)
	widget.Cairn:ClearTokenOverride(tokenName)
	widget.Cairn:ResolveToken(tokenName) -> value (sugar for lib:ResolveToken)

Token types are inferred from the name prefix:
	color.*     -> {r, g, b, a} table, each in [0,1]
	length.*    -> number (pixels, non-negative not enforced)
	font.*      -> { face = string, size = number, flags = string? }
	texture.*   -> string (atlas key OR file path)
	flag.*      -> boolean
	duration.*  -> number, non-negative (seconds)

Type validation runs at RegisterTheme time. Bad type errors there
rather than at paint time -- the failure mode the architecture wants.

Day 4 status: registry + cascade + per-instance overrides wired. No
repaint walk on theme change yet; widgets that read tokens get the new
value on next read but don't re-render automatically. Repaint queue is
a Day 5+ concern, after we have something visible to repaint.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Theme requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Token type inference --------------------------------------------

local TYPE_PREFIXES = {
	{ prefix = "color.",    type = "color"    },
	{ prefix = "length.",   type = "length"   },
	{ prefix = "font.",      type = "font"     },
	{ prefix = "texture.",  type = "texture"  },
	{ prefix = "flag.",      type = "flag"     },
	{ prefix = "duration.", type = "duration" },
}

local function tokenType(name)
	if type(name) ~= "string" then return nil end
	for _, entry in ipairs(TYPE_PREFIXES) do
		if name:sub(1, #entry.prefix) == entry.prefix then
			return entry.type
		end
	end
	return nil
end

-- ----- Type validators -------------------------------------------------
-- Each validator returns (true) on success or (false, errorMsg) on failure.

local function validateColor(v)
	if type(v) ~= "table" then return false, "expected {r,g,b,a} table" end
	for i = 1, 4 do
		if type(v[i]) ~= "number" then
			return false, ("[%d] is %s, expected number"):format(i, type(v[i]))
		end
		if v[i] < 0 or v[i] > 1 then
			return false, ("[%d] = %s, expected in [0,1]"):format(i, tostring(v[i]))
		end
	end
	return true
end

local function validateLength(v)
	if type(v) ~= "number" then return false, "expected number" end
	return true
end

local function validateFont(v)
	if type(v) ~= "table" then return false, "expected {face,size,flags} table" end
	if type(v.face) ~= "string" then return false, ".face must be a string" end
	if type(v.size) ~= "number" then return false, ".size must be a number" end
	if v.flags ~= nil and type(v.flags) ~= "string" then
		return false, ".flags must be a string or nil"
	end
	return true
end

local function validateTexture(v)
	if type(v) ~= "string" then return false, "expected string" end
	return true
end

local function validateFlag(v)
	if type(v) ~= "boolean" then return false, "expected boolean" end
	return true
end

local function validateDuration(v)
	if type(v) ~= "number" then return false, "expected number" end
	if v < 0 then return false, "must be >= 0" end
	return true
end

local VALIDATORS = {
	color    = validateColor,
	length   = validateLength,
	font     = validateFont,
	texture  = validateTexture,
	flag     = validateFlag,
	duration = validateDuration,
}

-- ----- Library hardcoded fallbacks (cascade step 5) --------------------
-- Sane minimum for tokens widgets are likely to ask for. Themes
-- override these for actual visual style. Keeping the set small on
-- purpose; better to return nil for unrecognized tokens than to
-- pretend a default looks right.

local DEFAULTS = {
	["color.bg.panel"]       = {0.10, 0.10, 0.12, 0.95},
	["color.bg.button"]      = {0.14, 0.14, 0.17, 1.00},
	["color.fg.text"]        = {0.92, 0.92, 0.94, 1.00},
	["color.fg.text.muted"]  = {0.65, 0.65, 0.70, 1.00},
	["color.border.default"] = {0.22, 0.22, 0.26, 1.00},
	["color.accent.primary"] = {0.40, 0.65, 1.00, 1.00},
	["color.accent.danger"]  = {1.00, 0.40, 0.40, 1.00},

	["length.padding.sm"]    = 4,
	["length.padding.md"]    = 8,
	["length.padding.lg"]    = 12,
	["length.gap.sm"]        = 2,
	["length.gap.md"]        = 4,
	["length.gap.lg"]        = 8,

	-- Font tokens. STANDARD_TEXT_FONT is Blizzard's locale-aware default
	-- font and is defined globally before any addon loads.
	["font.body"]            = { face = STANDARD_TEXT_FONT, size = 12, flags = "" },
	["font.heading"]         = { face = STANDARD_TEXT_FONT, size = 16, flags = "" },
	["font.small"]           = { face = STANDARD_TEXT_FONT, size = 10, flags = "" },

	["duration.fast"]        = 0.15,
	["duration.normal"]      = 0.25,
	["duration.slow"]        = 0.40,
}

lib._defaults    = lib._defaults    or DEFAULTS
lib._activeTheme = lib._activeTheme or nil

-- ----- RegisterTheme ---------------------------------------------------

function lib:RegisterTheme(name, def)
	if type(name) ~= "string" or name == "" then
		error("RegisterTheme: name must be a non-empty string", 2)
	end
	if type(def) ~= "table" then
		error("RegisterTheme: def must be a table", 2)
	end

	-- Normalize.
	def.tokens = def.tokens or {}
	-- def.extends stays as-is (string or nil).

	-- Validate every token in this theme. We don't follow the extends
	-- chain here; if a parent theme has bad data, that error fires
	-- when the parent registered (or it's a library default that we
	-- guarantee is valid).
	for tokenName, value in pairs(def.tokens) do
		local t = tokenType(tokenName)
		if not t then
			error(("RegisterTheme[%s]: token %q has no recognized prefix (color.*, length.*, font.*, texture.*, flag.*, duration.*)")
				:format(name, tokenName), 2)
		end
		local validator = VALIDATORS[t]
		local ok, err = validator(value)
		if not ok then
			error(("RegisterTheme[%s]: token %q (%s) invalid: %s")
				:format(name, tokenName, t, err), 2)
		end
	end

	self.themes[name] = def
	return def
end

-- ----- SetActiveTheme / GetActiveTheme ---------------------------------

function lib:SetActiveTheme(name)
	if name ~= nil and not self.themes[name] then
		error(("SetActiveTheme: %q is not a registered theme"):format(tostring(name)), 2)
	end
	self._activeTheme = name
	-- Day 4: no repaint walk yet. Widgets that read tokens after this
	-- call will see the new active theme; widgets that already read
	-- and cached values will not. Repaint queue is a Day 5+ concern.
end

function lib:GetActiveTheme()
	return self._activeTheme
end

-- ----- Resolution helper: walk a theme's extends chain ----------------

local function resolveInThemeChain(themes, themeName, tokenName, seen)
	seen = seen or {}
	if seen[themeName] then
		-- Cycle detected. Bail rather than infinite-loop.
		return nil
	end
	seen[themeName] = true
	local theme = themes[themeName]
	if not theme then return nil end
	if theme.tokens[tokenName] ~= nil then
		return theme.tokens[tokenName]
	end
	if theme.extends then
		return resolveInThemeChain(themes, theme.extends, tokenName, seen)
	end
	return nil
end

-- ----- ResolveToken (the cascade) --------------------------------------

function lib:ResolveToken(tokenName, widgetCairn)
	if type(tokenName) ~= "string" then return nil end

	-- Steps 1 + 2: walk the Cairn parent chain. Per-instance overrides
	-- on a widget beat any subtree theme above it; subtree theme on
	-- an ancestor beats the global active theme.
	local cairn = widgetCairn
	while cairn do
		if cairn._tokenOverrides and cairn._tokenOverrides[tokenName] ~= nil then
			return cairn._tokenOverrides[tokenName]
		end
		if cairn._theme then
			local v = resolveInThemeChain(self.themes, cairn._theme, tokenName)
			if v ~= nil then return v end
		end
		cairn = cairn._parent
	end

	-- Steps 3 + 4: active global theme + its extends chain.
	if self._activeTheme then
		local v = resolveInThemeChain(self.themes, self._activeTheme, tokenName)
		if v ~= nil then return v end
	end

	-- Step 5: library hardcoded default.
	return self._defaults[tokenName]
end

-- ----- Per-widget API on Mixins.Base -----------------------------------

function Base:SetTheme(themeName)
	if themeName ~= nil and not lib.themes[themeName] then
		error(("SetTheme: %q is not a registered theme"):format(tostring(themeName)), 2)
	end
	self._theme = themeName
end

function Base:GetTheme()
	return self._theme
end

function Base:SetTokenOverride(tokenName, value)
	if type(tokenName) ~= "string" or tokenName == "" then
		error("SetTokenOverride: tokenName must be a non-empty string", 2)
	end
	-- Validate the override value matches the token's inferred type.
	local t = tokenType(tokenName)
	if t and value ~= nil and VALIDATORS[t] then
		local ok, err = VALIDATORS[t](value)
		if not ok then
			error(("SetTokenOverride: %q (%s) invalid: %s"):format(tokenName, t, err), 2)
		end
	end
	self._tokenOverrides = self._tokenOverrides or {}
	self._tokenOverrides[tokenName] = value
end

function Base:ClearTokenOverride(tokenName)
	if self._tokenOverrides then
		self._tokenOverrides[tokenName] = nil
	end
end

-- Sugar so consumers can ask the widget directly without threading lib.
function Base:ResolveToken(tokenName)
	return lib:ResolveToken(tokenName, self)
end
