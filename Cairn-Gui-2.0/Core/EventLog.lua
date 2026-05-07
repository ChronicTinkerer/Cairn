--[[
Cairn-Gui-2.0 / Core / EventLog

Ring-buffer record of every Fire dispatched through the widget event
system (Events.lua). Per Decision 10B, the log is OFF by default and
flips ON when `lib.Dev = true`. The buffer's default capacity is 200
entries; the consumer (Forge_Inspector tab, debug snippets, etc.) reads
the most recent entries via `Cairn.EventLog:Tail(n)`.

Why a buffer instead of streaming via callbacks: most events fire
hundreds of times per minute (hover, focus, OnUpdate-driven work). A
fixed-capacity ring buffer is amortized O(1) per push and bounds memory.
Consumers tail the snapshot when they want to look.

Public API:

	Cairn.EventLog:Enable()           -- start recording
	Cairn.EventLog:Disable()          -- stop recording (clears the dirty bit)
	Cairn.EventLog:IsEnabled()
	Cairn.EventLog:Clear()            -- drop all entries; capacity unchanged
	Cairn.EventLog:SetCapacity(n)     -- resize the ring (preserves last n entries)
	Cairn.EventLog:GetCapacity()
	Cairn.EventLog:Count()            -- entries currently held (<= capacity)
	Cairn.EventLog:Tail(n)            -- newest n entries, oldest first; default 50
	Cairn.EventLog:Push(widgetCairn, event, ...)
	                                  -- internal-ish; called from Events.lua's
	                                  -- Base:Fire to record dispatches.

Each entry is a small table:
	{
		t          = GetTime() (seconds since UI loaded),
		widgetType = self._type or "?",     -- e.g. "Button", "ScrollFrame"
		event      = "Click",
		argCount   = N,                      -- count of trailing args (not the args themselves)
	}

We deliberately do NOT capture trailing args. A Click handler might fire
with a mouseButton string, but a Scroll handler might receive the entire
content frame. Capturing all trailing args risks pinning huge tables for
the buffer's lifetime, blowing memory and complicating GC. The argCount
field gives consumers a quick "was anything passed" indicator without
the hazard.

Cairn-Gui-2.0/Core/EventLog (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local DEFAULT_CAPACITY = 200

-- ----- Internal state ---------------------------------------------------

local EventLog = {}

-- Preserve state across LibStub upgrades within a session.
EventLog.entries  = lib._eventLog and lib._eventLog.entries  or {}
EventLog.capacity = lib._eventLog and lib._eventLog.capacity or DEFAULT_CAPACITY
EventLog.head     = lib._eventLog and lib._eventLog.head     or 1
EventLog.count    = lib._eventLog and lib._eventLog.count    or 0
EventLog.enabled  = lib._eventLog and lib._eventLog.enabled  or false

-- ----- Enable / Disable -------------------------------------------------

function EventLog:Enable()
	self.enabled = true
end

function EventLog:Disable()
	self.enabled = false
end

function EventLog:IsEnabled()
	return self.enabled and true or false
end

-- ----- Capacity management ----------------------------------------------

function EventLog:GetCapacity()
	return self.capacity
end

-- Resize the ring while preserving the newest min(count, n) entries. The
-- preserved entries are re-laid-out into a fresh array so the head index
-- can reset to 1 (cleaner than maintaining a wrap index across resizes).
function EventLog:SetCapacity(n)
	if type(n) ~= "number" or n < 1 then return end
	n = math.floor(n)
	if n == self.capacity then return end

	-- Snapshot newest entries (Tail-style) before mutating.
	local keep = math.min(self.count, n)
	local newest = {}
	if keep > 0 then
		-- Walk from oldest preserved to newest. Oldest index in current
		-- ring is (head - count) wrapped to capacity.
		local startIdx = ((self.head - keep - 1) % self.capacity) + 1
		for i = 1, keep do
			local idx = ((startIdx - 1 + i - 1) % self.capacity) + 1
			newest[i] = self.entries[idx]
		end
	end

	self.entries  = {}
	for i = 1, keep do self.entries[i] = newest[i] end
	self.capacity = n
	self.count    = keep
	self.head     = (keep % n) + 1
end

function EventLog:Count()
	return self.count
end

-- ----- Mutation ---------------------------------------------------------

function EventLog:Clear()
	self.entries = {}
	self.head    = 1
	self.count   = 0
end

-- Push a new entry. Called from Events.lua's Base:Fire. Cheap when
-- disabled (early-return). When enabled, allocates one small table per
-- fire; the ring caps total live objects.
function EventLog:Push(widgetCairn, event, ...)
	if not self.enabled then return end
	if type(event) ~= "string" then return end

	local entry = {
		t          = (GetTime and GetTime()) or 0,
		widgetType = (widgetCairn and widgetCairn._type) or "?",
		event      = event,
		argCount   = select("#", ...),
	}

	self.entries[self.head] = entry
	self.head = (self.head % self.capacity) + 1
	if self.count < self.capacity then
		self.count = self.count + 1
	end
end

-- ----- Tail -------------------------------------------------------------
-- Return up to N newest entries, oldest-first (so consumers can iterate
-- with ipairs and see chronological order). Default N = min(count, 50).

function EventLog:Tail(n)
	n = n or 50
	if n < 1 or self.count == 0 then return {} end
	if n > self.count then n = self.count end

	local out = {}
	-- Index of the oldest of the last n entries. The newest is at head-1
	-- (wrapped); we step back n-1 from there.
	local newestIdx = ((self.head - 2) % self.capacity) + 1
	local startIdx  = ((newestIdx - n) % self.capacity) + 1
	for i = 1, n do
		local idx = ((startIdx - 1 + i - 1) % self.capacity) + 1
		out[i] = self.entries[idx]
	end
	return out
end

-- ----- Publish ----------------------------------------------------------

lib.EventLog  = EventLog
lib._eventLog = EventLog
