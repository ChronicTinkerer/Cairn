--[[ Cairn-Callback-1.0
    A registry-style callback dispatcher.

    Cairn-Callback is the canonical implementation that backs the
    CallbackHandler-1.0 LibStub shim (see Libs/CallbackHandler-1.0/) so any
    third-party library expecting upstream CallbackHandler-1.0 (notably
    LibSharedMedia-3.0 and the Diesal-derived Cairn-Gui-* family) keeps
    working without vendoring upstream code.

    --- API -----------------------------------------------------------------

    local Callback = LibStub("Cairn-Callback-1.0")
    local reg = Callback.New()

    reg:Subscribe(eventname, key, fn)   -- key is "self": one fn per (event,key)
    reg:Unsubscribe(eventname, key)
    reg:UnsubscribeAll(key)             -- removes key from every event
    reg:Fire(eventname, ...)            -- subscribers get (eventname, ...trailing)

    reg:SetOnUsed(fn)    -- fn(reg, eventname) on first subscriber for an event
    reg:SetOnUnused(fn)  -- fn(reg, eventname) on last subscriber removed

    Subscribe during Fire is queued and applied after dispatch finishes.
    Errors inside subscribers are routed to the active error handler so one
    bad subscriber never aborts the others.

    --- Provenance ----------------------------------------------------------
    Cairn-Callback is original Cairn code, not a port of CallbackHandler-1.0.
    Its semantics are intentionally compatible with the upstream so that the
    accompanying shim can present an upstream-equivalent API.

    Cairn-Callback-1.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Callback-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Auto-vivifying nested-table metatable.
local meta = { __index = function(t, k) local v = {} t[k] = v return v end }

-- Route subscriber errors to the standard WoW error handler.
local function safecall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local handler = geterrorhandler and geterrorhandler() or print
        handler(err)
    end
end

local Registry = {}
Registry.__index = Registry

-- Build a fresh registry object.
function lib.New()
    return setmetatable({
        events  = setmetatable({}, meta),
        queue   = nil,            -- inserts during Fire land here, applied after
        recurse = 0,
        onUsed  = nil,
        onUnused = nil,
    }, Registry)
end

-- Add or replace the callback bound to (eventname, key).
function Registry:Subscribe(eventname, key, fn)
    if type(eventname) ~= "string" then
        error("Cairn.Callback:Subscribe(eventname, key, fn): eventname must be a string", 2)
    end
    if key == nil then
        error("Cairn.Callback:Subscribe(eventname, key, fn): key is required", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn.Callback:Subscribe(eventname, key, fn): fn must be a function", 2)
    end

    local handlers = rawget(self.events, eventname)
    local first    = (not handlers) or (next(handlers) == nil)

    if self.recurse > 0 and not (handlers and handlers[key]) then
        -- Defer brand-new entries while a Fire is in flight; replacements of an
        -- existing key are safe to apply immediately.
        self.queue = self.queue or setmetatable({}, meta)
        self.queue[eventname][key] = fn
        return
    end

    self.events[eventname][key] = fn
    if first and self.onUsed then
        safecall(self.onUsed, self, eventname)
    end
end

-- Remove a single (eventname, key) binding.
function Registry:Unsubscribe(eventname, key)
    if type(eventname) ~= "string" then
        error("Cairn.Callback:Unsubscribe(eventname, key): eventname must be a string", 2)
    end
    local handlers = rawget(self.events, eventname)
    if handlers and handlers[key] ~= nil then
        handlers[key] = nil
        if next(handlers) == nil and self.onUnused then
            safecall(self.onUnused, self, eventname)
        end
    end
    if self.queue then
        local q = rawget(self.queue, eventname)
        if q then q[key] = nil end
    end
end

-- Remove every binding owned by `key` across all events.
function Registry:UnsubscribeAll(key)
    if key == nil then
        error("Cairn.Callback:UnsubscribeAll(key): key is required", 2)
    end
    for eventname, handlers in pairs(self.events) do
        if handlers[key] ~= nil then
            handlers[key] = nil
            if next(handlers) == nil and self.onUnused then
                safecall(self.onUnused, self, eventname)
            end
        end
    end
    if self.queue then
        for _, q in pairs(self.queue) do q[key] = nil end
    end
end

-- Dispatch eventname to every bound callback. Subscribes during Fire are
-- queued and applied once Fire returns.
function Registry:Fire(eventname, ...)
    local handlers = rawget(self.events, eventname)
    if not handlers or next(handlers) == nil then return end

    self.recurse = self.recurse + 1
    -- Snapshot keys so a callback that unsubscribes neighbors mid-fire does
    -- not skip any.
    local snapshot, n = {}, 0
    for k, fn in pairs(handlers) do
        n = n + 1
        snapshot[n] = k
        snapshot[-n] = fn
    end
    for i = 1, n do
        local fn = snapshot[-i]
        -- Re-check current binding; the snapshotted fn might have been
        -- replaced or removed by an earlier callback in this fire.
        local current = handlers[snapshot[i]]
        if current ~= nil then
            -- Subscribers receive (eventname, ...trailingArgs), matching
            -- the upstream CallbackHandler-1.0 dispatch convention. The
            -- shim relies on this; consumers writing directly to
            -- Cairn-Callback should expect the same.
            safecall(current, eventname, ...)
        elseif fn ~= nil then
            -- Removed mid-fire; we deliberately do NOT call it.
        end
    end
    self.recurse = self.recurse - 1

    if self.recurse == 0 and self.queue then
        local q = self.queue
        self.queue = nil
        for ev, byKey in pairs(q) do
            for key, fn in pairs(byKey) do
                local ehandlers = rawget(self.events, ev)
                local first = (not ehandlers) or (next(ehandlers) == nil)
                self.events[ev][key] = fn
                if first and self.onUsed then
                    safecall(self.onUsed, self, ev)
                end
            end
        end
    end
end

-- Hooks fired the first time an event gains a subscriber / loses its last.
function Registry:SetOnUsed(fn)   self.onUsed   = fn end
function Registry:SetOnUnused(fn) self.onUnused = fn end

-- Introspection helpers.
function Registry:HasSubscribers(eventname)
    local h = rawget(self.events, eventname)
    return h ~= nil and next(h) ~= nil
end

function Registry:CountSubscribers(eventname)
    local h = rawget(self.events, eventname)
    if not h then return 0 end
    local n = 0
    for _ in pairs(h) do n = n + 1 end
    return n
end
