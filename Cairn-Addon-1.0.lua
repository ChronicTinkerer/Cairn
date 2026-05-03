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

	addon:Log()                     -- lazy Cairn.Log("MyAddon"); cached on addon

	Cairn.Addon.Get("MyAddon")      -- returns the addon if registered

Tracking fields (read-only; used by Cairn.Dashboard for the Info tab):
	addon.initFiredAt   - epoch seconds when OnInit last fired (or nil)
	addon.loginFiredAt  - epoch seconds when OnLogin last fired
	addon.enterFiredAt  - epoch seconds when OnEnter last fired
	addon.logoutFiredAt - epoch seconds when OnLogout last fired

`Cairn.Addon` depends on `Cairn.Events`. If you embed it, embed Events
too.
]]

local MAJOR, MINOR = "Cairn-Addon-1.0", 2  -- bumped: added timestamp tracking
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Events = LibStub("Cairn-Events-1.0", true)
if not Events then
	error("Cairn-Addon-1.0 requires Cairn-Events-1.0 to be loaded first.", 2)
end

lib.registry = lib.registry or {}

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

local function nowTs() return time and time() or os.time() end

local function fire(addon, hookName, fieldName, ...)
	addon[fieldName] = nowTs()
	local fn = rawget(addon, hookName)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, addon, ...)
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

function lib.New(name)
	if type(name) ~= "string" or name == "" then
		error("Cairn.Addon.New: name must be a non-empty string", 2)
	end
	local existing = lib.registry[name]
	if existing then return existing end

	local addon = setmetatable({
		name           = name,
		_log           = nil,
		initFiredAt    = nil,
		loginFiredAt   = nil,
		enterFiredAt   = nil,
		logoutFiredAt  = nil,
	}, proto)
	lib.registry[name] = addon

	Events:Subscribe("ADDON_LOADED", function(loadedName)
		if loadedName == name then fire(addon, "OnInit", "initFiredAt") end
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_LOGIN", function()
		fire(addon, "OnLogin", "loginFiredAt")
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
		fire(addon, "OnEnter", "enterFiredAt", isLogin, isReload)
	end, "Cairn.Addon:" .. name)

	Events:Subscribe("PLAYER_LOGOUT", function()
		fire(addon, "OnLogout", "logoutFiredAt")
	end, "Cairn.Addon:" .. name)

	return addon
end

function lib.Get(name) return lib.registry[name] end

function lib.GetAll()
	local out = {}
	for n, a in pairs(lib.registry) do out[n] = a end
	return out
end

setmetatable(lib, { __call = function(self, name) return self.New(name) end })
