--[[
Cairn-Locale-1.0

Per-addon localization. Author registers string tables keyed by locale
code (the strings GetLocale() returns: "enUS", "deDE", "frFR", "esES",
"esMX", "ruRU", "koKR", "zhCN", "zhTW", "ptBR", "itIT", etc.). At
runtime, Cairn picks the active locale, falls back to the default
locale for missing keys, and falls back to the key itself if no
translation exists anywhere.

Public API:

	local L = Cairn.Locale.New("MyAddon", {
		enUS = { hello = "Hello", welcome = "Welcome back, %s!" },
		deDE = { hello = "Hallo", welcome = "Willkommen zurueck, %s!" },
	}, { default = "enUS" })

	-- Three ways to read a string:
	print(L.hello)               -- direct table access (recommended)
	print(L["hello"])
	print(L:Get("hello"))        -- explicit method form

	-- Format strings (printf-style on top of Get):
	print(L("welcome", playerName))
	print(L:Format("welcome", playerName))

	-- Introspection:
	L:GetLocale()                -- the active locale code (e.g. "deDE")
	L:GetDefault()               -- the fallback locale (e.g. "enUS")
	L:Has("hello")               -- true if active locale OR default has it
	L:GetMissing()               -- keys present in default but missing in active

	Cairn.Locale.Get("MyAddon")  -- registry lookup, nil if unregistered

Behavior on missing keys:
	1. Active locale lookup. If found, return.
	2. Default locale lookup. If found, return.
	3. Return the key itself. Log a one-time warning per key (suppress
	   with opts.silent = true).
]]

local MAJOR, MINOR = "Cairn-Locale-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.Locale") end
	return lib._log
end

lib.registry = lib.registry or {}

-- ----- Dev override -----------------------------------------------------
-- Setting an override forces every Cairn.Locale instance (existing and
-- future) to behave as though GetLocale() returned the override code. Used
-- by Forge's dev tooling to test localizations without restarting the
-- client in a different language. nil clears the override.

local _override = nil

local function detectLocale()
	if _override then return _override end
	if GetLocale then
		local ok, code = pcall(GetLocale)
		if ok and type(code) == "string" and code ~= "" then return code end
	end
	return "enUS"
end

function lib.SetOverride(code)
	if code ~= nil and (type(code) ~= "string" or code == "") then
		error("Cairn.Locale.SetOverride: code must be a non-empty string or nil", 2)
	end
	_override = code
	-- Refresh every registered instance so subsequent L["..."] reads
	-- resolve through the new locale. If the requested locale has no
	-- table, fall through to default (matches the New() behavior).
	local resolved = detectLocale()
	for _, inst in pairs(lib.registry) do
		if inst._tables[resolved] then
			inst._locale = resolved
		else
			inst._locale = inst._default
		end
		inst._warned = {}
	end
end

function lib.GetOverride()
	return _override
end

-- ----- Locale instance prototype ----------------------------------------

local proto = {}

function proto:Get(key)
	if type(key) ~= "string" then return tostring(key) end
	local active = self._tables[self._locale]
	if active and active[key] ~= nil then return active[key] end
	local def = self._tables[self._default]
	if def and def[key] ~= nil then return def[key] end
	if not self._opts.silent and not self._warned[key] then
		self._warned[key] = true
		if logger() then
			logger():Warn("[%s] missing translation for key %q (locale=%s, default=%s)",
				self._addonName, key, self._locale, self._default)
		end
	end
	return key
end

function proto:Format(key, ...)
	local s = proto.Get(self, key)
	if select("#", ...) == 0 then return s end
	local ok, msg = pcall(string.format, s, ...)
	if ok then return msg end
	return s .. " [LOCALE FORMAT ERROR: " .. tostring(msg) .. "]"
end

function proto:Has(key)
	if type(key) ~= "string" then return false end
	local active = self._tables[self._locale]
	if active and active[key] ~= nil then return true end
	local def = self._tables[self._default]
	if def and def[key] ~= nil then return true end
	return false
end

function proto:GetLocale()  return self._locale  end
function proto:GetDefault() return self._default end

function proto:GetMissing()
	local out = {}
	if self._locale == self._default then return out end
	local def    = self._tables[self._default] or {}
	local active = self._tables[self._locale]  or {}
	for k in pairs(def) do
		if active[k] == nil then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end

local instanceMeta = {
	__index = function(t, key)
		local m = proto[key]
		if m ~= nil then return m end
		if type(key) == "string" then
			return proto.Get(t, key)
		end
		return nil
	end,
	__call = function(t, key, ...)
		return proto.Format(t, key, ...)
	end,
}

-- ----- Constructor -------------------------------------------------------

function lib.New(addonName, locales, opts)
	if type(addonName) ~= "string" or addonName == "" then
		error("Cairn.Locale.New: addonName must be a non-empty string", 2)
	end
	if type(locales) ~= "table" then
		error("Cairn.Locale.New: locales must be a table of {localeCode = stringTable}", 2)
	end
	opts = opts or {}

	local default = opts.default or "enUS"
	if type(default) ~= "string" or default == "" then
		error("Cairn.Locale.New: opts.default must be a non-empty string locale code", 2)
	end

	local detected = detectLocale()

	local self = {
		_addonName = addonName,
		_tables    = locales,
		_default   = default,
		_locale    = detected,
		_opts      = opts,
		_warned    = {},
	}

	-- If the active locale doesn't have its own table, fall through to the
	-- default locale's table so we don't warn on every key.
	if not locales[detected] then
		self._locale = default
	end

	setmetatable(self, instanceMeta)
	lib.registry[addonName] = self
	return self
end

function lib.Get(addonName) return lib.registry[addonName] end

setmetatable(lib, { __call = function(self, name, locales, opts) return self.New(name, locales, opts) end })
