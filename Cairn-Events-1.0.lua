--[[
Cairn-Events-1.0

Modern game-event subscription with closure handlers and owner-based mass
unsubscribe. Wraps a single shared frame and dispatches to per-event
subscriber lists.

Why not CallbackHandler-1.0?
	CallbackHandler is excellent when a *library* fires events to addons,
	but it forces a unique (owner, event) pair per subscription. Addon
	code routinely wants two handlers for the same event in the same
	addon (e.g., one in your UI module and one in your data module).
	Cairn.Events allows that without ceremony.

Public API:

	Cairn.Events:Subscribe(event, handler, [owner])
		Returns an unsubscribe closure. Call it (no args) to remove just
		this subscription. `owner` is optional but recommended; pass your
		addon name or any stable key. Handler receives event payload args
		(NOT the event name; matches the modern WoW pattern).

	Cairn.Events:UnsubscribeAll(owner)
		Removes every subscription registered with `owner`. Use this in
		your addon's disable/teardown path.

	Cairn.Events:Has(event)
		Returns true if any handler is currently registered for `event`.
]]

local MAJOR, MINOR = "Cairn-Events-1.0", 1
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end -- a same-or-newer version is already loaded

-- Preserve state across upgrades within a session.
lib.handlers   = lib.handlers   or {}                 -- event -> array of entries
lib.frame      = lib.frame      or CreateFrame("Frame", "CairnEventsFrame")

-- (Re)bind OnEvent every load so a hot-reload picks up the latest closure.
lib.frame:SetScript("OnEvent", function(_, event, ...)
	local list = lib.handlers[event]
	if not list then return end
	-- Snapshot length so handlers that unsubscribe themselves don't skip peers.
	local count = #list
	for i = 1, count do
		local entry = list[i]
		if entry and not entry.removed then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
	-- Compact removed entries after dispatch.
	for i = #list, 1, -1 do
		if list[i] and list[i].removed then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		lib.handlers[event] = nil
		lib.frame:UnregisterEvent(event)
	end
end)

local function validate(event, handler)
	if type(event) ~= "string" or event == "" then
		error("Cairn.Events:Subscribe: 'event' must be a non-empty string", 3)
	end
	if type(handler) ~= "function" then
		error("Cairn.Events:Subscribe: 'handler' must be a function", 3)
	end
end

function lib:Subscribe(event, handler, owner)
	validate(event, handler)

	local list = self.handlers[event]
	if not list then
		list = {}
		self.handlers[event] = list
		self.frame:RegisterEvent(event)
	end

	local entry = { fn = handler, owner = owner }
	list[#list + 1] = entry

	-- Closure unsubscribes just this entry. Marking + later compaction
	-- avoids mutating the array mid-dispatch.
	return function()
		entry.removed = true
	end
end

function lib:UnsubscribeAll(owner)
	if owner == nil then
		error("Cairn.Events:UnsubscribeAll: 'owner' is required", 2)
	end
	for event, list in pairs(self.handlers) do
		for i = 1, #list do
			if list[i].owner == owner then
				list[i].removed = true
			end
		end
	end
	-- Compaction happens lazily on next dispatch; force one for events with
	-- no remaining live entries so we can unregister immediately.
	for event, list in pairs(self.handlers) do
		local anyLive = false
		for i = 1, #list do
			if not list[i].removed then anyLive = true; break end
		end
		if not anyLive then
			self.handlers[event] = nil
			self.frame:UnregisterEvent(event)
		end
	end
end

function lib:Has(event)
	local list = self.handlers[event]
	if not list then return false end
	for i = 1, #list do
		if not list[i].removed then return true end
	end
	return false
end
