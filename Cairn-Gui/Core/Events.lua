--[[
Cairn-Gui-2.0 / Core / Events

Per-widget multi-subscriber event system layered on top of
Cairn-Callback-1.0 per Decision 6. Each widget gets its own callback
registry, lazily created on first On/Once/Fire call.

Public API on widget.Cairn (added to Mixins.Base by this file):

	widget.Cairn:On(event, handler, tag?)
		Subscribe handler to event. Multi-subscriber: subsequent On
		calls with different handlers all fire on the same event. Same
		handler bound twice replaces (one subscription per handler).
		Optional tag enables bulk detach via OffByTag.

	widget.Cairn:Once(event, handler, tag?)
		Subscribe handler that auto-detaches after first fire.

	widget.Cairn:Off(event?, handler?)
		Detach by reference:
			:Off("Click", fn) -> remove specific binding
			:Off("Click")     -> remove all handlers for "Click"
			:Off(nil, fn)     -> remove fn across all events
			:Off()            -> remove every handler on this widget

	widget.Cairn:OffByTag(tag)
		Remove every handler tagged with `tag`, across all events.

	widget.Cairn:Fire(event, ...)
		Dispatch event to subscribers. Each handler is called with
		(widgetCairn, ...) -- the widget's Cairn namespace as the first
		argument, then whatever extra args were passed to Fire.

	widget.Cairn:Forward(event, target)
		Re-fire `event` from this widget onto `target` whenever it
		fires here. `target` may be the Cairn namespace or the Frame.

Native Blizzard frame events (OnEnter, OnLeave, OnClick, OnUpdate, ...)
are NOT wrapped. Widget definitions wire them via SetScript and
explicitly call :Fire to bridge into the Cairn event stream:

	frame:SetScript("OnClick", function(self, button)
		self.Cairn:Fire("Click", button)
	end)

This keeps the Cairn surface focused on semantic widget events and
leaves Blizzard's native event API untouched for performance-critical
hot paths.

Error handling: each handler runs through Cairn-Callback's safecall,
which routes errors through the standard WoW error handler. One bad
subscriber never aborts the others.

Day 5 status: full event API wired. No bubbling (deferred per Decision 6).
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Events requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Per-widget pub/sub registry -------------------------------------
-- Inlined intentionally. Cairn-Callback-1.0 is the CallbackHandler-1.0
-- upstream-compat shim — it installs Register/Unregister methods on a
-- TARGET object, which is the wrong shape for a private per-widget event
-- registry (we'd be exposing those methods on every widget). Keep the
-- callback lib lean as a pure upstream shim; build the small map we need
-- right here. About 25 lines and zero external coupling.
--
-- Shape:
--   reg.events[event][key] = wrapperFn   -- key is the user's original
--                                           handler so :Off(event, fn) works
--   reg:Subscribe(event, key, fn)
--   reg:Unsubscribe(event, key)
--   reg:UnsubscribeAll(key)
--   reg:Fire(event, ...)                 -- snapshots subs so handlers
--                                           may self-unsubscribe mid-fire

local function newWidgetRegistry()
	local reg = { events = {} }
	function reg:Subscribe(event, key, fn)
		local subs = self.events[event]
		if not subs then subs = {}; self.events[event] = subs end
		subs[key] = fn
	end
	function reg:Unsubscribe(event, key)
		local subs = self.events[event]
		if subs then subs[key] = nil end
	end
	function reg:UnsubscribeAll(key)
		for _, subs in pairs(self.events) do subs[key] = nil end
	end
	function reg:Fire(event, ...)
		local subs = self.events[event]
		if not subs then return end
		-- Snapshot so an in-flight handler can :Off itself or a peer.
		local snap = {}
		for _, fn in pairs(subs) do snap[#snap + 1] = fn end
		for i = 1, #snap do snap[i](event, ...) end
	end
	return reg
end

-- Lazily create the callback registry the first time a widget needs one.
-- Most widgets will never wire any events, so the registry stays nil.
local function ensureRegistry(self)
	if not self._cb then
		self._cb       = newWidgetRegistry()
		self._tags     = {}  -- [event] = { [handler] = tag }
	end
	return self._cb
end

-- Build a wrapper that adapts Cairn-Callback's (eventname, ...) dispatch
-- shape to our public (widgetCairn, ...) handler signature.
local function makeWrapper(widgetCairn, handler)
	return function(_eventname, ...)
		handler(widgetCairn, ...)
	end
end

-- Build a Once-wrapper that auto-unsubscribes before invoking the user's
-- handler. Unsubscribing FIRST means a handler that itself fires the
-- same event again won't reenter this Once subscription.
local function makeOnceWrapper(widgetCairn, event, handler)
	local function wrapper(_eventname, ...)
		if widgetCairn._cb then
			widgetCairn._cb:Unsubscribe(event, handler)
		end
		if widgetCairn._tags and widgetCairn._tags[event] then
			widgetCairn._tags[event][handler] = nil
		end
		handler(widgetCairn, ...)
	end
	return wrapper
end

-- ----- On --------------------------------------------------------------

function Base:On(event, handler, tag)
	if type(event) ~= "string" or event == "" then
		error("On: event must be a non-empty string", 2)
	end
	if type(handler) ~= "function" then
		error("On: handler must be a function", 2)
	end

	local cb      = ensureRegistry(self)
	local wrapper = makeWrapper(self, handler)

	-- Key by the user's original handler so :Off("Click", handler) works.
	-- The wrapper is what actually runs; the key is what the registry
	-- uses to identify this binding.
	cb:Subscribe(event, handler, wrapper)

	if tag ~= nil then
		self._tags[event] = self._tags[event] or {}
		self._tags[event][handler] = tag
	end
end

-- ----- Once ------------------------------------------------------------

function Base:Once(event, handler, tag)
	if type(event) ~= "string" or event == "" then
		error("Once: event must be a non-empty string", 2)
	end
	if type(handler) ~= "function" then
		error("Once: handler must be a function", 2)
	end

	local cb      = ensureRegistry(self)
	local wrapper = makeOnceWrapper(self, event, handler)

	cb:Subscribe(event, handler, wrapper)

	if tag ~= nil then
		self._tags[event] = self._tags[event] or {}
		self._tags[event][handler] = tag
	end
end

-- ----- Off -------------------------------------------------------------

function Base:Off(event, handler)
	if not self._cb then return end

	if event and handler then
		-- Specific binding.
		self._cb:Unsubscribe(event, handler)
		if self._tags[event] then
			self._tags[event][handler] = nil
		end
		return
	end

	if event then
		-- All handlers for this event.
		local handlers = rawget(self._cb.events, event)
		if handlers then
			-- Snapshot keys; Unsubscribe mutates the table during iteration.
			local keys = {}
			for k in pairs(handlers) do keys[#keys + 1] = k end
			for _, k in ipairs(keys) do
				self._cb:Unsubscribe(event, k)
			end
		end
		self._tags[event] = nil
		return
	end

	if handler then
		-- This handler across all events.
		self._cb:UnsubscribeAll(handler)
		for _, byHandler in pairs(self._tags) do
			byHandler[handler] = nil
		end
		return
	end

	-- No args: nuke everything on this widget.
	for ev, handlers in pairs(self._cb.events) do
		local keys = {}
		for k in pairs(handlers) do keys[#keys + 1] = k end
		for _, k in ipairs(keys) do
			self._cb:Unsubscribe(ev, k)
		end
	end
	self._tags = {}
end

-- ----- OffByTag --------------------------------------------------------

function Base:OffByTag(tag)
	if not self._cb or not self._tags then return end
	if tag == nil then return end

	for event, byHandler in pairs(self._tags) do
		-- Snapshot before mutation.
		local toRemove = {}
		for handler, t in pairs(byHandler) do
			if t == tag then
				toRemove[#toRemove + 1] = handler
			end
		end
		for _, handler in ipairs(toRemove) do
			self._cb:Unsubscribe(event, handler)
			byHandler[handler] = nil
		end
	end
end

-- ----- Fire ------------------------------------------------------------

function Base:Fire(event, ...)
	if type(event) ~= "string" or event == "" then
		error("Fire: event must be a non-empty string", 2)
	end
	-- Stats / EventLog instrumentation (Decision 10B). Bumped UP-FRONT,
	-- before the no-subscribers early-return: a Fire attempt with zero
	-- subscribers is still a dispatch, and debugging "why isn't my
	-- event firing?" relies on Stats counting attempts.
	if lib.Stats    then lib.Stats:Inc("event_dispatches")   end
	if lib.EventLog then lib.EventLog:Push(self, event, ...) end
	if not self._cb then return end
	self._cb:Fire(event, ...)
end

-- ----- Forward ---------------------------------------------------------

function Base:Forward(event, target)
	if type(event) ~= "string" or event == "" then
		error("Forward: event must be a non-empty string", 2)
	end
	-- target may be a widget Frame (with .Cairn) or a Cairn namespace directly.
	local targetCairn
	if type(target) == "table" then
		if target.Cairn and target.Cairn.Fire then
			targetCairn = target.Cairn
		elseif target.Fire then
			targetCairn = target
		end
	end
	if not targetCairn then
		error("Forward: target must be a Cairn-Gui-2.0 widget or its Cairn namespace", 2)
	end

	-- A re-fire handler that just dispatches the same event onto target.
	-- Tag with a deterministic string so OffByTag can clean up forwards.
	self:On(event, function(_, ...)
		targetCairn:Fire(event, ...)
	end, ("__forward:%s"):format(tostring(targetCairn)))
end
