--[[
Cairn-Gui-2.0 / Core / Stats

Counters for everything the Cairn-Gui internals can measure: animations
added/completed, layout recomputes, primitive draws, event dispatches,
and pool occupancy per widget type. Per Decision 10B, this is a
read-only introspection surface that Forge (or any consumer) reads via
`Cairn.Stats:Snapshot()`. The library exposes data; the visualization is
someone else's job.

Counters are bumped via `Cairn.Stats:Inc(key, [delta])` from the
instrumentation points in Animation.lua, Layout.lua, Primitives.lua, and
Events.lua. Every call is gated by a tolerant nil-check on the consumer
side (`if lib.Stats then lib.Stats:Inc(...) end`) so the counters are
zero-cost when this file isn't loaded.

Public API:

	Cairn.Stats:Inc(key, delta?)         -- bump a counter (default delta = 1)
	Cairn.Stats:Get(key)                 -- read a single counter
	Cairn.Stats:Reset()                  -- zero everything
	Cairn.Stats:Snapshot()               -- frozen table of all counters
	                                        plus pool occupancy + event-log
	                                        buffer size at the time of call.

Snapshot shape:
	{
		animations = {
			added     = N,
			completed = N,
			active    = N,    -- derived: added - completed
		},
		layout = {
			recomputes = N,
		},
		primitives = {
			rect   = { draws = N },
			border = { draws = N },
			icon   = { draws = N },
		},
		events = {
			dispatches = N,
		},
		pool = {
			[widgetTypeName] = N,        -- count of widgets in pool per type
			...
			_total = N,
		},
		eventLog = {
			enabled  = bool,
			count    = N,                 -- entries currently held
			capacity = N,                 -- buffer size
		},
		t = GetTime(),                   -- when the snapshot was taken
	}

The dotted key syntax (`primitives.rect.draws`, `animations.added`) is
the wire format for `Inc`. Internal storage is a flat keyed table; the
Snapshot path walks fixed keys to build the nested structure (faster
and easier to evolve than parsing dotted strings on every read).

Cairn-Gui-2.0/Core/Stats (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Stats = {}

-- Preserve state across LibStub upgrades within a session.
Stats.counters = lib._stats and lib._stats.counters or {}

-- ----- Increment / read ------------------------------------------------

function Stats:Inc(key, delta)
	if type(key) ~= "string" then return end
	delta = delta or 1
	self.counters[key] = (self.counters[key] or 0) + delta
end

function Stats:Get(key)
	return self.counters[key] or 0
end

function Stats:Reset()
	self.counters = {}
end

-- ----- Snapshot --------------------------------------------------------
-- Read-only frozen view. We build a fresh nested table each call because
-- consumers might modify it (e.g., flatten for display), and we don't want
-- those edits leaking back into the live counters.

local function poolOccupancy()
	local out, total = {}, 0
	if not lib._pool then return out, 0 end
	for typeName, list in pairs(lib._pool) do
		local n = (type(list) == "table") and #list or 0
		out[typeName] = n
		total = total + n
	end
	out._total = total
	return out, total
end

function Stats:Snapshot()
	local pool = poolOccupancy()
	local elog = lib.EventLog
	local added     = self:Get("animations.added")
	local completed = self:Get("animations.completed")
	return {
		animations = {
			added     = added,
			completed = completed,
			active    = math.max(0, added - completed),
		},
		layout = {
			recomputes = self:Get("layout.recomputes"),
		},
		primitives = {
			rect   = { draws = self:Get("primitives.rect.draws")   },
			border = { draws = self:Get("primitives.border.draws") },
			icon   = { draws = self:Get("primitives.icon.draws")   },
		},
		events = {
			dispatches = self:Get("event_dispatches"),
		},
		pool = pool,
		eventLog = {
			enabled  = elog and elog:IsEnabled() or false,
			count    = elog and elog:Count()     or 0,
			capacity = elog and elog:GetCapacity() or 0,
		},
		t = (GetTime and GetTime()) or 0,
	}
end

-- ----- Publish ---------------------------------------------------------

lib.Stats  = Stats
lib._stats = Stats
