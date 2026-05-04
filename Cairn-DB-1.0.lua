--[[
Cairn-DB-1.0

SavedVariables wrapper with profile support, defaults, and change
callbacks. Modeled on the parts of AceDB-3.0 that authors actually use,
with fewer surprises and a smaller API.

Public API:

	local db = Cairn.DB.New("MyAddonDB", {
		defaults = {
			profile = { scale = 1, enabled = true,
			            colors = { r = 1, g = 1, b = 1 } },
			global  = { dataVersion = 1 },
		},
		profileType = "char",  -- "char" (default) | "default"
	})

	-- After the SavedVariables have loaded (i.e., after your addon's
	-- ADDON_LOADED event), read/write through .profile and .global:
	print(db.profile.scale)    -- 1 (from defaults on first run)
	db.profile.scale = 1.5
	db.global.dataVersion = 2

	-- Profile management
	db:GetCurrentProfile()       -- "MyChar - MyRealm" or "Default" or...
	db:GetProfiles()             -- { "Default", "PvP", ... }
	db:SetProfile("PvP")         -- switch (creates if missing)
	db:ResetProfile()            -- wipe current profile, reapply defaults
	db:DeleteProfile("OldOne")   -- remove a profile (cannot delete current)
	db:CopyProfile("From","To")  -- deep-copy values, To becomes a sibling

	-- Subscribe to profile changes (returns unsubscribe closure)
	local unsub = db:OnProfileChanged(function(newName, oldName)
		-- refresh your UI here
	end, addonName)

Important defaults behavior:
	Defaults are deep-copied into a profile when that profile is FIRST
	CREATED. Adding new keys to your defaults table later does NOT
	retroactively appear in existing profiles. Use ResetProfile() or a
	migration to push new defaults into existing data. This is a
	deliberate v0.1 trade-off (no nested-table __index surprises).

CRITICAL - do not access .profile or .global at file scope:
	WoW loads SavedVariables AFTER your addon's .lua files execute, but
	BEFORE ADDON_LOADED fires. If you touch db.profile / db.global at
	file scope, init() runs while _G[svName] is still nil. The lib then
	creates a fresh empty table, assigns it to _G[svName], and pins the
	wrapper to it via rawset. WoW then OVERWRITES _G[svName] with the
	loaded data, leaving your wrapper pointing at an orphaned table.
	Symptoms: settings appear to save but vanish on /reload; identity
	check `db.profile == _G[svName].profiles[current]` returns false.

	Safe pattern - defer init to ADDON_LOADED (or Cairn.Addon's OnInit):

		local db = Cairn.DB.New("MyAddonDB", { defaults = {...} })
		ns.db = db
		-- Do NOT touch db.profile here.

		local addon = Cairn.Addon.New("MyAddon")
		function addon:OnInit()
		    local _ = db.profile          -- safe: SVs are loaded
		    -- Force-init any missing keys (defaults aren't retroactive):
		    if db.profile.foo == nil then db.profile.foo = {} end
		end

	If you don't use Cairn.Addon, register an ADDON_LOADED handler
	yourself and do the same thing there.

SavedVariables shape (so you can inspect or migrate it):
	_G[svName] = {
		profileKeys = { [charKey] = profileName, ... },
		profiles    = { [profileName] = {...}, ... },
		global      = { ... },
	}
]]

local MAJOR, MINOR = "Cairn-DB-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- ----- Helpers -----------------------------------------------------------

local function deepCopy(src)
	if type(src) ~= "table" then return src end
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then out[k] = deepCopy(v) else out[k] = v end
	end
	return out
end

local function characterKey()
	-- WoW: GetUnitName + GetRealmName. Fall back to plain "Player" so
	-- the lib doesn't crash in tests / offline contexts.
	local name, realm
	if GetUnitName then name = GetUnitName("player", false) end
	if GetRealmName then realm = GetRealmName() end
	if name and realm then return name .. " - " .. realm end
	return name or "Player"
end

local function ensureSVStructure(sv)
	sv.profileKeys = sv.profileKeys or {}
	sv.profiles    = sv.profiles    or {}
	sv.global      = sv.global      or {}
	return sv
end

local function ensureProfile(sv, profileName, profileDefaults)
	if not sv.profiles[profileName] then
		sv.profiles[profileName] = deepCopy(profileDefaults or {})
		return true  -- created
	end
	return false
end

-- ----- DB instance prototype --------------------------------------------

local proto = {}
proto.__index = proto

local function init(self)
	if self._initialized then return end

	local sv = _G[self._svName]
	if type(sv) ~= "table" then
		sv = {}
		_G[self._svName] = sv
	end
	ensureSVStructure(sv)

	-- Decide which profile to use for this character.
	local charKey = characterKey()
	local existing = sv.profileKeys[charKey]
	local profileName = existing
	if not profileName then
		if self._profileType == "default" then
			profileName = self._opts.defaultProfile or "Default"
		else  -- "char" (default)
			profileName = charKey
		end
		sv.profileKeys[charKey] = profileName
	end

	ensureProfile(sv, profileName, self._opts.defaults and self._opts.defaults.profile)

	-- Defaults for global are applied once if global is empty.
	local gDefaults = self._opts.defaults and self._opts.defaults.global
	if gDefaults and next(sv.global) == nil then
		for k, v in pairs(gDefaults) do
			if type(v) == "table" then sv.global[k] = deepCopy(v) else sv.global[k] = v end
		end
	end

	self._sv = sv
	self._charKey = charKey
	self._currentProfile = profileName

	rawset(self, "profile", sv.profiles[profileName])
	rawset(self, "global",  sv.global)

	self._initialized = true
end

-- Lazy init on first access to .profile or .global. Methods are looked up
-- via rawget (fast path) before this metamethod runs, so they're unaffected.
local instanceMeta = {
	__index = function(t, key)
		if key == "profile" or key == "global" then
			init(t)
			return rawget(t, key)
		end
		return proto[key]
	end,
}

-- ----- Profile management ------------------------------------------------

function proto:GetCurrentProfile()
	init(self)
	return self._currentProfile
end

function proto:GetProfiles()
	init(self)
	local out = {}
	for name in pairs(self._sv.profiles) do out[#out + 1] = name end
	table.sort(out)
	return out
end

function proto:SetProfile(name)
	if type(name) ~= "string" or name == "" then
		error("Cairn.DB:SetProfile: name must be a non-empty string", 2)
	end
	init(self)
	local oldName = self._currentProfile
	if oldName == name then return end

	ensureProfile(self._sv, name, self._opts.defaults and self._opts.defaults.profile)
	self._sv.profileKeys[self._charKey] = name
	self._currentProfile = name
	rawset(self, "profile", self._sv.profiles[name])

	-- Fire callbacks.
	for i = 1, #self._profileSubs do
		local sub = self._profileSubs[i]
		if sub and not sub.removed then
			local ok, err = pcall(sub.fn, name, oldName)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
	end
end

function proto:ResetProfile()
	init(self)
	local name = self._currentProfile
	self._sv.profiles[name] = deepCopy(self._opts.defaults and self._opts.defaults.profile or {})
	rawset(self, "profile", self._sv.profiles[name])
end

function proto:DeleteProfile(name)
	if type(name) ~= "string" or name == "" then
		error("Cairn.DB:DeleteProfile: name must be a non-empty string", 2)
	end
	init(self)
	if name == self._currentProfile then
		error("Cairn.DB:DeleteProfile: cannot delete the current profile (" .. name .. ")", 2)
	end
	self._sv.profiles[name] = nil
	-- Drop any character keys that pointed to it.
	for charKey, p in pairs(self._sv.profileKeys) do
		if p == name then self._sv.profileKeys[charKey] = nil end
	end
end

function proto:CopyProfile(from, to)
	if type(from) ~= "string" or type(to) ~= "string" or from == "" or to == "" then
		error("Cairn.DB:CopyProfile: 'from' and 'to' must be non-empty strings", 2)
	end
	init(self)
	local src = self._sv.profiles[from]
	if not src then error("Cairn.DB:CopyProfile: source profile not found: " .. from, 2) end
	self._sv.profiles[to] = deepCopy(src)
	if to == self._currentProfile then
		rawset(self, "profile", self._sv.profiles[to])
	end
end

function proto:OnProfileChanged(fn, owner)
	if type(fn) ~= "function" then
		error("Cairn.DB:OnProfileChanged: fn must be a function", 2)
	end
	init(self)
	local sub = { fn = fn, owner = owner }
	self._profileSubs[#self._profileSubs + 1] = sub
	return function() sub.removed = true end
end

-- ----- Constructor -------------------------------------------------------

function lib.New(svName, opts)
	if type(svName) ~= "string" or svName == "" then
		error("Cairn.DB.New: svName must be a non-empty string (the SavedVariables global name)", 2)
	end
	opts = opts or {}
	if opts.profileType and opts.profileType ~= "char" and opts.profileType ~= "default" then
		error("Cairn.DB.New: profileType must be 'char' or 'default'", 2)
	end

	local self = {
		_svName       = svName,
		_opts         = opts,
		_profileType  = opts.profileType or "char",
		_initialized  = false,
		_profileSubs  = {},
	}
	return setmetatable(self, instanceMeta)
end

-- Allow Cairn.DB("MyAddonDB", opts) as sugar for Cairn.DB.New("MyAddonDB", opts).
setmetatable(lib, { __call = function(self, name, opts) return self.New(name, opts) end })
