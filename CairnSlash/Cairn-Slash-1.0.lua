--[[
Cairn-Slash-1.0

Generic slash-command router for any addon. (The /cairn router in
Cairn.lua is for Cairn itself; this module is for your addon's commands.)

Public API:

	local s = Cairn.Slash.Register("MyAddon", "/myaddon", { aliases = {"/ma"} })

	s:Subcommand("config", function(args) MyAddon:OpenConfig() end, "open the config panel")
	s:Subcommand("reset",  function() MyAddon:Reset() end, "reset everything")
	s:Default(function(args) MyAddon:Open() end)        -- runs if no sub matches

	-- Auto-help: if the user types `/myaddon help` (or `?`, or no input
	-- with no Default handler) the router prints a list of subcommands.

	s:Run("config")           -- programmatic dispatch
	s:Aliases({ "/m", "/ma" }) -- add or replace aliases later
	s:Args("hello \"two words\" three")
	  -- => { "hello", "two words", "three" }   (quote-aware splitter)

	Cairn.Slash.Get("MyAddon")  -- look up by addon name

The first whitespace-separated token of input is treated as the
subcommand name (case-insensitive). The rest is passed to the handler
as a single string. Use s:Args(rest) if you want it pre-split with
respect for "double quotes".
]]

-- MINOR history:
--   1  initial: Register / Subcommand / Default / Aliases / Run / Args / PrintHelp
--   2  added :GetSubcommands() and :GetSlashes() so tools can introspect
--      a slash without reaching into the private _subs / _slashes tables.
--      Spotted while building Cairn-Demo's Slash tab (2026-05-07).
local MAJOR, MINOR = "Cairn-Slash-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.registry = lib.registry or {}  -- name -> slash object
lib._uid     = lib._uid     or 0   -- unique counter for SLASH_* globals

-- ----- Helpers -----------------------------------------------------------

local function nextUID()
	lib._uid = lib._uid + 1
	return lib._uid
end

-- Quote-aware whitespace splitter. Handles "double quotes" only; not
-- escapes. Keeps things simple; addons that need shell-grade parsing
-- can do their own thing.
local function splitArgs(str)
	if not str or str == "" then return {} end
	local out, buf, inQuotes = {}, {}, false
	local function flush()
		if #buf > 0 then out[#out + 1] = table.concat(buf); buf = {} end
	end
	for i = 1, #str do
		local c = str:sub(i, i)
		if c == '"' then
			inQuotes = not inQuotes
		elseif (c == " " or c == "\t") and not inQuotes then
			flush()
		else
			buf[#buf + 1] = c
		end
	end
	flush()
	return out
end

-- ----- Slash prototype ---------------------------------------------------

local proto = {}
proto.__index = proto

function proto:Subcommand(name, fn, helpText)
	if type(name) ~= "string" or name == "" then
		error("Cairn.Slash:Subcommand: name must be a non-empty string", 2)
	end
	if type(fn) ~= "function" then
		error("Cairn.Slash:Subcommand: fn must be a function", 2)
	end
	self._subs[name:lower()] = { fn = fn, help = helpText, name = name }
	return self  -- allow chaining
end

function proto:Default(fn)
	if type(fn) ~= "function" then
		error("Cairn.Slash:Default: fn must be a function", 2)
	end
	self._default = fn
	return self
end

function proto:Aliases(list)
	if type(list) ~= "table" then
		error("Cairn.Slash:Aliases: list must be a table of strings", 2)
	end
	self._aliases = {}
	for i = 1, #list do self._aliases[i] = list[i] end
	self:_register()  -- re-register with new aliases
	return self
end

function proto:PrintHelp()
	if not (DEFAULT_CHAT_FRAME or print) then return end
	local primary = self._slashes[1] or ("/" .. self._name:lower())
	local function p(line)
		if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
	end
	p(string.format("|cFF7FBFFF[%s]|r commands:", self._name))
	local names = {}
	for n in pairs(self._subs) do names[#names + 1] = n end
	table.sort(names)
	if #names == 0 then
		p("  (no subcommands registered)")
	else
		for _, n in ipairs(names) do
			local entry = self._subs[n]
			local help = entry.help and ("  " .. entry.help) or ""
			p(string.format("  %s %s%s", primary, entry.name or n, help))
		end
	end
end

function proto:Run(input)
	input = input or ""
	local sub, rest = input:match("^%s*(%S*)%s*(.*)$")
	sub = (sub or ""):lower()

	if sub == "" then
		if self._default then return self._default("") end
		return self:PrintHelp()
	end
	if sub == "help" or sub == "?" then return self:PrintHelp() end

	local entry = self._subs[sub]
	if entry then return entry.fn(rest or "") end

	if self._default then return self._default(input) end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format(
			"|cFF7FBFFF[%s]|r unknown subcommand: %s   (try help)", self._name, sub))
	else
		print("[" .. self._name .. "] unknown subcommand: " .. sub)
	end
end

function proto:Args(rest) return splitArgs(rest) end

-- Introspection: enumerate registered subcommands. Returns a fresh array
-- of { name = "config", help = "open the config panel" } sorted by name.
-- Added in MINOR 2 so dev/debug UIs (e.g. Cairn-Demo's Slash tab, Forge's
-- registry browser) don't have to read the private `_subs` table.
function proto:GetSubcommands()
	local out, names = {}, {}
	for n in pairs(self._subs) do names[#names + 1] = n end
	table.sort(names)
	for _, n in ipairs(names) do
		local entry = self._subs[n]
		out[#out + 1] = {
			name = entry.name or n,   -- preserve original-case display name
			help = entry.help,
		}
	end
	return out
end

-- Introspection: list of every slash string this object responds to
-- (primary + aliases). Returns a fresh array of strings.
function proto:GetSlashes()
	local out = { self._slashes[1] }
	for _, alias in ipairs(self._aliases or {}) do out[#out + 1] = alias end
	return out
end

-- (Re)register all slashes with SlashCmdList.
function proto:_register()
	if not (SlashCmdList and _G) then return end
	local handlerKey = "CAIRN_SLASH_" .. self._handlerSuffix
	SlashCmdList[handlerKey] = function(msg) self:Run(msg) end

	local all = { self._slashes[1] }
	for _, alias in ipairs(self._aliases or {}) do all[#all + 1] = alias end

	-- Clear old SLASH_X_n entries first.
	for i = 1, 16 do _G["SLASH_" .. handlerKey .. i] = nil end
	for i, slash in ipairs(all) do _G["SLASH_" .. handlerKey .. i] = slash end
end

-- ----- Constructor -------------------------------------------------------

function lib.Register(name, primarySlash, opts)
	if type(name) ~= "string" or name == "" then
		error("Cairn.Slash.Register: name must be a non-empty string", 2)
	end
	if type(primarySlash) ~= "string" or primarySlash:sub(1, 1) ~= "/" then
		error("Cairn.Slash.Register: primarySlash must start with '/' (e.g. '/myaddon')", 2)
	end
	opts = opts or {}

	local existing = lib.registry[name]
	if existing then return existing end

	local self = setmetatable({
		_name           = name,
		_slashes        = { primarySlash },
		_aliases        = opts.aliases or {},
		_subs           = {},
		_default        = nil,
		_handlerSuffix  = string.format("%s_%d", name:gsub("[^%w]", "_"), nextUID()),
	}, proto)
	lib.registry[name] = self
	self:_register()
	return self
end

function lib.Get(name) return lib.registry[name] end

setmetatable(lib, { __call = function(self, name, slash, opts) return self.Register(name, slash, opts) end })
