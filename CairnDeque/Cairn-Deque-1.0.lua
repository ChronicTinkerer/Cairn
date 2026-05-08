--[[
Cairn-Deque-1.0

Double-ended queue with O(1) push/pop at both ends. Exposes deque-native
methods plus queue (FIFO) and stack (LIFO) aliases, so the same instance
can stand in for any of the three depending on which methods you call.

Why one library instead of three?
	A deque is a strict superset of both queue and stack, with the same
	internal storage and the same O(1) cost. Splitting into three libs
	would triplicate the implementation for zero behavioral gain. The
	aliases below let consumer code read naturally regardless of role.

Public API:

	local d = Cairn.Deque.New({
		capacity = 100,            -- optional; nil = unbounded
		onFull   = "drop",         -- "drop" (default) or "error"
		                            -- "drop" evicts the opposite end on
		                            -- overflow and fires the Dropped
		                            -- subscription. "error" raises.
	})

	-- Deque (both ends)
	d:PushBack(v)       d:PopBack()       d:PeekBack()
	d:PushFront(v)      d:PopFront()      d:PeekFront()

	-- Queue (FIFO) aliases
	d:Enqueue(v)        -- = PushBack
	d:Dequeue()         -- = PopFront
	d:Peek()            -- = PeekFront

	-- Stack (LIFO) aliases
	d:Push(v)           -- = PushBack
	d:Pop()             -- = PopBack
	d:Top()             -- = PeekBack

	-- Inspection
	d:Size()            -- current element count
	d:IsEmpty()
	d:IsFull()          -- false when unbounded
	d:Capacity()        -- nil when unbounded
	d:Clear()           -- drops all entries; fires Emptied if non-empty
	d:ToArray()         -- snapshot copy, front -> back
	d:Iter()            -- stateless iterator, front -> back
	d:IterReverse()     -- stateless iterator, back -> front

	-- Subscriptions (always available, lazy storage). Each :OnX returns
	-- an unsubscribe closure; :UnsubscribeAll(owner) clears every
	-- subscription tagged with that owner across all events.
	d:OnPushed(fn,  [owner])   -- fn(deque, value, side)   side = "front"|"back"
	d:OnPopped(fn,  [owner])   -- fn(deque, value, side)
	d:OnDropped(fn, [owner])   -- fn(deque, value)         capacity overflow
	d:OnEmptied(fn, [owner])   -- fn(deque)
	d:UnsubscribeAll(owner)

Behavior contract:

	- PushBack / PushFront on a full deque with onFull="drop" evict the
	  OPPOSITE end (PushBack drops front, PushFront drops back). The
	  evicted value is delivered to Dropped subscribers before the new
	  value lands. Rationale: drop-oldest semantics map naturally to
	  PushBack (the typical ring-buffer / log-tail pattern); the
	  symmetric rule for PushFront keeps the invariant "the newest
	  value always wins a place in the deque."

	- Pop / Peek on an empty deque returns nil. They never error.

	- Subscriber errors are pcall-trapped and routed to the active
	  error handler so one bad subscriber never aborts dispatch for
	  the others.

	- The internal storage is the classic two-index scheme
	  (`_first`, `_last`); indexes monotonically grow/shrink and are
	  reset to 0/-1 on Clear() or natural drain. No element shifting,
	  no ring-buffer modulus arithmetic.

Cairn-Deque-1.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Deque-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- a same-or-newer version is already loaded

-- Reuse the prototype across hot reloads so old instances pick up new
-- methods automatically. Same trick Sequencer / Events use for their
-- internal state tables.
local Deque = lib._Deque or {}
lib._Deque   = Deque
Deque.__index = Deque

-- Validation helpers --------------------------------------------------------

local function validateOpts(opts)
	if opts == nil then return end
	if type(opts) ~= "table" then
		error("Cairn.Deque.New: opts must be a table or nil", 3)
	end
	if opts.capacity ~= nil then
		local c = opts.capacity
		if type(c) ~= "number" or c < 1 or c ~= math.floor(c) then
			error("Cairn.Deque.New: opts.capacity must be a positive integer or nil", 3)
		end
	end
	if opts.onFull ~= nil and opts.onFull ~= "drop" and opts.onFull ~= "error" then
		error('Cairn.Deque.New: opts.onFull must be "drop" or "error"', 3)
	end
end

-- Constructor ---------------------------------------------------------------

function lib.New(opts)
	validateOpts(opts)
	opts = opts or {}
	return setmetatable({
		_items  = {},
		_first  = 0,
		_last   = -1,
		_cap    = opts.capacity,
		_onFull = opts.onFull or "drop",
		_subs   = nil, -- created lazily on first subscription
	}, Deque)
end

-- Subscription plumbing -----------------------------------------------------

local function fire(self, event, ...)
	local subs = self._subs
	if not subs then return end
	local list = subs[event]
	if not list then return end
	-- Snapshot length so handlers that subscribe/unsubscribe themselves don't
	-- skip peers or trip over the freshly-appended entry.
	local count = #list
	for i = 1, count do
		local entry = list[i]
		if entry and not entry.removed then
			local ok, err = pcall(entry.fn, self, ...)
			if not ok then
				local handler = geterrorhandler and geterrorhandler() or print
				handler(err)
			end
		end
	end
	-- Compact removed entries after dispatch.
	for i = #list, 1, -1 do
		if list[i].removed then table.remove(list, i) end
	end
end

local function makeSubscriber(event)
	return function(self, fn, owner)
		if type(fn) ~= "function" then
			error("Cairn.Deque:On" .. event .. ": handler must be a function", 2)
		end
		self._subs = self._subs or {}
		local list = self._subs[event]
		if not list then
			list = {}
			self._subs[event] = list
		end
		local entry = { fn = fn, owner = owner }
		list[#list + 1] = entry
		return function() entry.removed = true end
	end
end

Deque.OnPushed  = makeSubscriber("Pushed")
Deque.OnPopped  = makeSubscriber("Popped")
Deque.OnDropped = makeSubscriber("Dropped")
Deque.OnEmptied = makeSubscriber("Emptied")

function Deque:UnsubscribeAll(owner)
	if owner == nil then
		error("Cairn.Deque:UnsubscribeAll: 'owner' is required", 2)
	end
	if not self._subs then return end
	for _, list in pairs(self._subs) do
		for i = 1, #list do
			if list[i].owner == owner then
				list[i].removed = true
			end
		end
	end
end

-- Inspection ----------------------------------------------------------------

function Deque:Size()      return self._last - self._first + 1 end
function Deque:IsEmpty()   return self._last < self._first end
function Deque:Capacity()  return self._cap end

function Deque:IsFull()
	if not self._cap then return false end
	return (self._last - self._first + 1) >= self._cap
end

-- Mutation ------------------------------------------------------------------

-- Drop the front element silently and return the value. Used by PushBack
-- when capacity is hit with onFull = "drop".
local function dropFront(self)
	local v = self._items[self._first]
	self._items[self._first] = nil
	self._first = self._first + 1
	return v
end

local function dropBack(self)
	local v = self._items[self._last]
	self._items[self._last] = nil
	self._last = self._last - 1
	return v
end

function Deque:PushBack(v)
	if self._cap and (self._last - self._first + 1) >= self._cap then
		if self._onFull == "error" then
			error("Cairn.Deque:PushBack: deque is full (capacity " .. self._cap .. ")", 2)
		end
		local dropped = dropFront(self)
		fire(self, "Dropped", dropped)
	end
	self._last = self._last + 1
	self._items[self._last] = v
	fire(self, "Pushed", v, "back")
end

function Deque:PushFront(v)
	if self._cap and (self._last - self._first + 1) >= self._cap then
		if self._onFull == "error" then
			error("Cairn.Deque:PushFront: deque is full (capacity " .. self._cap .. ")", 2)
		end
		local dropped = dropBack(self)
		fire(self, "Dropped", dropped)
	end
	self._first = self._first - 1
	self._items[self._first] = v
	fire(self, "Pushed", v, "front")
end

function Deque:PopFront()
	if self._last < self._first then return nil end
	local v = self._items[self._first]
	self._items[self._first] = nil
	self._first = self._first + 1
	fire(self, "Popped", v, "front")
	if self._last < self._first then
		-- Reset indexes once drained so they don't drift forever.
		self._first, self._last = 0, -1
		fire(self, "Emptied")
	end
	return v
end

function Deque:PopBack()
	if self._last < self._first then return nil end
	local v = self._items[self._last]
	self._items[self._last] = nil
	self._last = self._last - 1
	fire(self, "Popped", v, "back")
	if self._last < self._first then
		self._first, self._last = 0, -1
		fire(self, "Emptied")
	end
	return v
end

function Deque:PeekFront()
	if self._last < self._first then return nil end
	return self._items[self._first]
end

function Deque:PeekBack()
	if self._last < self._first then return nil end
	return self._items[self._last]
end

function Deque:Clear()
	local wasEmpty = self._last < self._first
	for i = self._first, self._last do
		self._items[i] = nil
	end
	self._first, self._last = 0, -1
	if not wasEmpty then fire(self, "Emptied") end
end

-- Snapshots & iteration -----------------------------------------------------

function Deque:ToArray()
	local arr = {}
	local j = 0
	for i = self._first, self._last do
		j = j + 1
		arr[j] = self._items[i]
	end
	return arr
end

function Deque:Iter()
	local items = self._items
	local i     = self._first - 1
	local last  = self._last
	return function()
		i = i + 1
		if i > last then return nil end
		return items[i]
	end
end

function Deque:IterReverse()
	local items = self._items
	local i     = self._last + 1
	local first = self._first
	return function()
		i = i - 1
		if i < first then return nil end
		return items[i]
	end
end

-- Queue (FIFO) aliases ------------------------------------------------------

Deque.Enqueue = Deque.PushBack
Deque.Dequeue = Deque.PopFront
Deque.Peek    = Deque.PeekFront

-- Stack (LIFO) aliases ------------------------------------------------------

Deque.Push = Deque.PushBack
Deque.Pop  = Deque.PopBack
Deque.Top  = Deque.PeekBack
