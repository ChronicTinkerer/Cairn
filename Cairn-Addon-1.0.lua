--[[
Cairn-Addon-1.0

Lifecycle helpers for addons. Removes the boilerplate of subscribing to
ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD, and PLAYER_LOGOUT.

Public API:

	local addon = Cairn.Addon.New("MyAddon")

	function addon:OnInit()    end  -- ADDON_LOADED for your addon (SVs ready)
	function addon:OnLogin()   end  -- PLAYER_LOGIN
	function addon:OnEnter()   end  -- PLAYER_ENTERING_WORLD (fires every world load)
	function addon:OnLogout()  end  -- PLAYER_LOGOUT

	-- Define these as methods on the addon object BEFORE first event arrives.
	-- Methods that aren't defined are simply skipped.

	addon:Log()                     -- lazy Cairn.Log("MyAddon"); cached on addon

	-- Static registry lookup
	Cairn.Addon.Get("MyAddon")      -- returns the addon if registered

`Cairn.Addon` depends on `Cairn.Events`. If you embed it, embed Events
too.
]]

local MAJOR, MINOR = "Cairn-Addon-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Events = LibStub("Cairn-Events-1.0", true)
if not Events then
	error("Cairn-Addon-1.0 requires Cairn-Events-1.0 to be loaded first.", 2)
end

lib.registry = lib.registry or {}  -- name -> addon object

-- ----- Addon prototype --------------------------------------------------

local proto = {}
proto.__index = proto

function proto:Log()
	if self._log then return self._log end
	local Log = LibStub("Cairn-Log-1.0", true)
	if Log then
		self._log = Log(self.name)
		return self._log
	end
	return nil
end

-- Internal: fire a hook by name if the user defined it. Errors are caught.
local function fire(addon, hookName, ...)
	local fn = rawget(addon, hookName)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, addon, ...)
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- ----- Constructor -------------------------------------------------------

function lib.New(name)
	if type(name) ~= "string" or name == "" then
		error("Cairn.Addon.New: name must be a non-empty string", 2)
	end
	local existing = lib.registry[name]
	if existing then return existing end

	local addon = setmetatable({ name = name, _log = nil }, proto)
	lib.registry[name] = addon

	-- ADDON_LOADED filters by addon name; only fire OnInit for our match.
	Events:Subscribe("ADDON_LOADED", function(loadedName)
		if loadedName == name then fire(addon, "OnInit") end
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_LOGIN", function()
		fire(addon, "OnLogin")
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
		fire(addon, "OnEnter", isLogin, isReload)
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_LOGOUT", function()
		fire(addon, "OnLogout")
	end, "Cairn.Addon:" .. name)

	return addon
end

function lib.Get(name) return lib.registry[name] end

setmetatable(lib, { __call = function(self, name) return self.New(name) end })
