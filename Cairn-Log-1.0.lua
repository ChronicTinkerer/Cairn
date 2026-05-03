--[[
Cairn-Log-1.0

Leveled, per-source logger with a ring buffer, optional chat echo, and
configurable persistence to SavedVariables.

Levels (severity descending):
	ERROR (1)  always shown by default
	WARN  (2)  shown by default
	INFO  (3)  shown by default; chat-echoed by default
	DEBUG (4)  hidden by default
	TRACE (5)  hidden by default

Public API:

	local log = Cairn.Log("MyAddon")        -- get or create per-source logger
	log:Info("loaded v%s", "1.2")           -- printf-style
	log:Debug("subscribed to %d events", n)
	log:Warn("config key %q deprecated", k)
	log:Error("parse failed: %s", err)
	log:SetLevel("DEBUG")                   -- raise verbosity for this source

	Cairn.Log:SetGlobalLevel("WARN")        -- default for all sources
	Cairn.Log:SetChatEchoLevel("WARN")      -- only echo WARN+ to chat
	Cairn.Log:SetPersistence(1000)          -- save last N entries to SV (0 = off)
	Cairn.Log:OnNewEntry(fn)                -- subscribe to entries (LogWindow uses this)
	Cairn.Log:GetEntries([filterFn])        -- snapshot of buffer (oldest first)
	Cairn.Log:Clear()                       -- empty the buffer
	Cairn.Log:DumpToSV()                    -- returns table for SavedVariables
	Cairn.Log:LoadFromSV(tbl)               -- restore from SavedVariables

The buffer is a fixed-size ring. Default size 1000 entries. Each entry:
	{ ts = epoch_seconds, level = 1..5, source = "MyAddon", message = "formatted" }
]]

local MAJOR, MINOR = "Cairn-Log-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Level table is intentionally module-local so it can't be mutated externally.
local LEVELS      = { TRACE = 5, DEBUG = 4, INFO = 3, WARN = 2, ERROR = 1 }
local LEVEL_NAMES = { [5] = "TRACE", [4] = "DEBUG", [3] = "INFO", [2] = "WARN", [1] = "ERROR" }
-- Color codes used for chat echo and surfaced for the LogWindow to consume.
local LEVEL_COLORS = {
	[5] = "FF888888",  -- TRACE: dark gray
	[4] = "FFB0B0B0",  -- DEBUG: gray
	[3] = "FFFFFFFF",  -- INFO:  white
	[2] = "FFFFAA00",  -- WARN:  orange
	[1] = "FFFF4040",  -- ERROR: red
}

lib.LEVELS       = LEVELS
lib.LEVEL_NAMES  = LEVEL_NAMES
lib.LEVEL_COLORS = LEVEL_COLORS

-- Preserve state across LibStub upgrades within a session.
lib.loggers       = lib.loggers       or {}    -- source -> logger
lib.buffer        = lib.buffer        or {}    -- ring buffer (1..bufferMax)
lib.bufferMax     = lib.bufferMax     or 1000  -- ring capacity
lib.bufferHead    = lib.bufferHead    or 1     -- next write index
lib.bufferCount   = lib.bufferCount   or 0     -- live entries (<= bufferMax)
lib.persistMax    = lib.persistMax    or 1000  -- entries persisted on logout
lib.chatEchoLevel = lib.chatEchoLevel or LEVELS.INFO
lib.globalLevel   = lib.globalLevel   or LEVELS.INFO
lib.subscribers   = lib.subscribers   or {}    -- ordered list of {fn, owner}

local function resolveLevel(input)
	if type(input) == "number" then
		return LEVEL_NAMES[input] and input or nil
	end
	if type(input) == "string" then
		return LEVELS[input:upper()]
	end
	return nil
end

local function safeFormat(fmt, ...)
	if select("#", ...) == 0 then return tostring(fmt) end
	local ok, msg = pcall(string.format, fmt, ...)
	if ok then return msg end
	-- Don't lose the message if the format string is malformed.
	return tostring(fmt) .. " [LOG FORMAT ERROR: " .. tostring(msg) .. "]"
end

-- Best-effort timestamp; time() exists in WoW and standard Lua.
local function nowTs() return time and time() or os.time() end

local function pushEntry(entry)
	local n = lib.bufferMax
	lib.buffer[lib.bufferHead] = entry
	lib.bufferHead = (lib.bufferHead % n) + 1
	if lib.bufferCount < n then lib.bufferCount = lib.bufferCount + 1 end

	-- Notify subscribers (LogWindow, etc).
	for i = 1, #lib.subscribers do
		local sub = lib.subscribers[i]
		if sub then
			local ok, err = pcall(sub.fn, entry)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
	end
end

local function chatEcho(entry)
	if entry.level > lib.chatEchoLevel then return end
	local color = LEVEL_COLORS[entry.level] or "FFFFFFFF"
	local levelTag = LEVEL_NAMES[entry.level] or "?"
	-- Format: [Cairn] [Source LEVEL] message
	local line = string.format(
		"|cFF7FBFFF[Cairn]|r |c%s[%s %s]|r %s",
		color, entry.source or "?", levelTag, entry.message or ""
	)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(line)
	else
		print(line)
	end
end

-- ----- Logger object -----------------------------------------------------

local loggerMeta = {}
loggerMeta.__index = loggerMeta

local function logAt(self, levelNum, fmt, ...)
	-- Source-level filter wins if set, otherwise global level.
	local maxLevel = self._level or lib.globalLevel
	if levelNum > maxLevel then return end
	local entry = {
		ts      = nowTs(),
		level   = levelNum,
		source  = self.source,
		message = safeFormat(fmt, ...),
	}
	pushEntry(entry)
	chatEcho(entry)
	return entry
end

function loggerMeta:Trace(fmt, ...) return logAt(self, LEVELS.TRACE, fmt, ...) end
function loggerMeta:Debug(fmt, ...) return logAt(self, LEVELS.DEBUG, fmt, ...) end
function loggerMeta:Info(fmt, ...)  return logAt(self, LEVELS.INFO,  fmt, ...) end
function loggerMeta:Warn(fmt, ...)  return logAt(self, LEVELS.WARN,  fmt, ...) end
function loggerMeta:Error(fmt, ...) return logAt(self, LEVELS.ERROR, fmt, ...) end

function loggerMeta:SetLevel(level)
	local n = resolveLevel(level)
	if not n then error("Cairn.Log logger:SetLevel: unknown level " .. tostring(level), 2) end
	self._level = n
end

function loggerMeta:GetLevel()
	return self._level or lib.globalLevel
end

function loggerMeta:ClearLevel()
	-- Revert to global level.
	self._level = nil
end

-- ----- Public module API -------------------------------------------------

function lib.New(source)
	if type(source) ~= "string" or source == "" then
		error("Cairn.Log: source must be a non-empty string", 2)
	end
	local existing = lib.loggers[source]
	if existing then return existing end
	local logger = setmetatable({ source = source, _level = nil }, loggerMeta)
	lib.loggers[source] = logger
	return logger
end

-- Allow Cairn.Log("MyAddon") as syntactic sugar for Cairn.Log.New("MyAddon").
setmetatable(lib, { __call = function(self, source) return self.New(source) end })

function lib:SetGlobalLevel(level)
	local n = resolveLevel(level)
	if not n then error("Cairn.Log:SetGlobalLevel: unknown level " .. tostring(level), 2) end
	self.globalLevel = n
end

function lib:GetGlobalLevel() return self.globalLevel end

function lib:SetChatEchoLevel(level)
	local n = resolveLevel(level)
	if not n then error("Cairn.Log:SetChatEchoLevel: unknown level " .. tostring(level), 2) end
	self.chatEchoLevel = n
end

function lib:GetChatEchoLevel() return self.chatEchoLevel end

function lib:SetPersistence(count)
	if type(count) ~= "number" or count < 0 then
		error("Cairn.Log:SetPersistence: count must be a non-negative number", 2)
	end
	self.persistMax = math.floor(count)
end

function lib:GetPersistence() return self.persistMax end

function lib:OnNewEntry(fn, owner)
	if type(fn) ~= "function" then
		error("Cairn.Log:OnNewEntry: fn must be a function", 2)
	end
	local sub = { fn = fn, owner = owner }
	self.subscribers[#self.subscribers + 1] = sub
	return function()
		for i = #self.subscribers, 1, -1 do
			if self.subscribers[i] == sub then table.remove(self.subscribers, i) end
		end
	end
end

function lib:GetEntries(filterFn)
	-- Walk the ring oldest-first. Returns a fresh array.
	local out, n = {}, self.bufferCount
	if n == 0 then return out end
	local cap = self.bufferMax
	-- Oldest entry is at bufferHead (since head points to the next write slot).
	-- When the buffer is partially full, oldest is at index 1.
	local start = (self.bufferCount < cap) and 1 or self.bufferHead
	local idx = start
	for _ = 1, n do
		local entry = self.buffer[idx]
		if entry and (not filterFn or filterFn(entry)) then
			out[#out + 1] = entry
		end
		idx = (idx % cap) + 1
	end
	return out
end

function lib:Clear()
	for i = 1, self.bufferMax do self.buffer[i] = nil end
	self.bufferHead  = 1
	self.bufferCount = 0
end

function lib:Count() return self.bufferCount end

function lib:DumpToSV()
	if self.persistMax <= 0 then return nil end
	local entries = self:GetEntries()
	local n = #entries
	if n > self.persistMax then
		-- Keep only the most recent N.
		local trimmed = {}
		for i = n - self.persistMax + 1, n do trimmed[#trimmed + 1] = entries[i] end
		entries = trimmed
	end
	return { version = 1, entries = entries }
end

function lib:LoadFromSV(data)
	if type(data) ~= "table" or type(data.entries) ~= "table" then return false end
	self:Clear()
	for i = 1, #data.entries do
		local e = data.entries[i]
		if type(e) == "table" and e.level and e.message then
			pushEntry({
				ts = e.ts or 0, level = e.level,
				source = e.source or "?", message = e.message,
			})
		end
	end
	return true
end

-- Internal helper: change buffer capacity. Re-allocates if shrinking.
function lib:SetBufferSize(n)
	if type(n) ~= "number" or n < 1 then
		error("Cairn.Log:SetBufferSize: n must be >= 1", 2)
	end
	n = math.floor(n)
	if n == self.bufferMax then return end
	local entries = self:GetEntries()
	self.bufferMax  = n
	self.buffer     = {}
	self.bufferHead = 1
	self.bufferCount = 0
	-- Re-push only the most recent N.
	local start = math.max(1, #entries - n + 1)
	for i = start, #entries do pushEntry(entries[i]) end
end
