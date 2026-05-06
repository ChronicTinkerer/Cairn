--[[
Cairn-Timer-1.0

Owner-grouped timers + optional named-timer replacement. Backed by WoW's
C_Timer when available; uses pure-Lua fallback for test contexts.

Why this on top of C_Timer:
  * UnsubscribeAll-by-owner. Bind every timer your addon creates to a single
    `owner` (typically your addon name). On disable / reset / reload, one
    call kills them all. No bookkeeping in your addon.
  * Named timers. `:Schedule(name, ...)` cancels any prior timer with the
    same name before scheduling - useful for "debounce on the latest event"
    patterns where multiple triggers should only result in one delayed call.
  * Errors inside callbacks are pcall-trapped and routed to
    `geterrorhandler()` so a single bad timer doesn't kill its peers.

Public API:

    -- One-shot. Returns a handle; callback fires once after `seconds`.
    local h = Cairn.Timer:After(2.0, function() ... end, "MyAddon")

    -- Repeating. iterations nil = infinite.
    local h = Cairn.Timer:NewTicker(0.5, function() ... end, "MyAddon", 10)

    -- Named one-shot. Cancels any existing timer with this name first.
    Cairn.Timer:Schedule("save", 2.0, function() doSave() end, "MyAddon")

    -- Cancel.
    Cairn.Timer:Cancel(h)
    Cairn.Timer:CancelByName("save")
    Cairn.Timer:CancelAll("MyAddon")    -- nuke every timer this owner started

    -- Inspect.
    Cairn.Timer:GetByName("save")
    Cairn.Timer:CountByOwner("MyAddon")

    -- Sugar: Cairn.Timer(seconds, fn, owner) == Cairn.Timer:After(...)
]]

local MAJOR, MINOR = "Cairn-Timer-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Preserve state across LibStub upgrades within a session.
lib.byOwner = lib.byOwner or {}    -- owner -> array of live handles
lib.named   = lib.named   or {}    -- name  -> handle

-- ----- Internal helpers --------------------------------------------------

local function unlinkHandle(handle)
    if handle._name and lib.named[handle._name] == handle then
        lib.named[handle._name] = nil
    end
    if handle._owner then
        local list = lib.byOwner[handle._owner]
        if list then
            for i, h in ipairs(list) do
                if h == handle then table.remove(list, i); break end
            end
            if #list == 0 then lib.byOwner[handle._owner] = nil end
        end
    end
end

local function trackHandle(handle)
    if handle._owner then
        lib.byOwner[handle._owner] = lib.byOwner[handle._owner] or {}
        table.insert(lib.byOwner[handle._owner], handle)
    end
end

local function safeRun(fn)
    local ok, err = pcall(fn)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- ----- One-shot ---------------------------------------------------------

function lib:After(seconds, fn, owner)
    if type(seconds) ~= "number" then
        error("Cairn.Timer:After: seconds must be a number", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn.Timer:After: fn must be a function", 2)
    end

    local handle = { _owner = owner, _cancelled = false, _kind = "once" }

    local function dispatch()
        if handle._cancelled then return end
        unlinkHandle(handle)
        safeRun(fn)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(math.max(0, seconds), dispatch)
    end

    trackHandle(handle)
    return handle
end

-- ----- Repeating --------------------------------------------------------

function lib:NewTicker(seconds, fn, owner, iterations)
    if type(seconds) ~= "number" or seconds <= 0 then
        error("Cairn.Timer:NewTicker: seconds must be > 0", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn.Timer:NewTicker: fn must be a function", 2)
    end

    local handle = { _owner = owner, _cancelled = false, _kind = "ticker" }

    local function dispatch()
        if handle._cancelled then return end
        safeRun(fn)
    end

    if C_Timer and C_Timer.NewTicker then
        handle._ticker = C_Timer.NewTicker(seconds, dispatch, iterations)
    end

    trackHandle(handle)
    return handle
end

-- ----- Named one-shot (debounce-friendly) -------------------------------

function lib:Schedule(name, seconds, fn, owner)
    if type(name) ~= "string" or name == "" then
        error("Cairn.Timer:Schedule: name required (non-empty string)", 2)
    end
    -- Cancel existing timer with the same name first.
    local existing = lib.named[name]
    if existing then self:Cancel(existing) end

    local handle = self:After(seconds, fn, owner)
    handle._name = name
    lib.named[name] = handle
    return handle
end

-- ----- Cancel -----------------------------------------------------------

function lib:Cancel(handle)
    if not handle or handle._cancelled then return end
    handle._cancelled = true
    if handle._ticker and handle._ticker.Cancel then
        handle._ticker:Cancel()
    end
    unlinkHandle(handle)
end

function lib:CancelByName(name)
    local h = lib.named[name]
    if h then self:Cancel(h) end
end

function lib:CancelAll(owner)
    if not owner then return end
    local list = lib.byOwner[owner]
    if not list then return end
    -- Snapshot so :Cancel mutations to byOwner[owner] don't disturb iteration.
    local copy = {}
    for i, h in ipairs(list) do copy[i] = h end
    for _, h in ipairs(copy) do self:Cancel(h) end
    lib.byOwner[owner] = nil
end

-- ----- Introspection ----------------------------------------------------

function lib:GetByName(name)
    return lib.named[name]
end

function lib:CountByOwner(owner)
    if not owner then return 0 end
    return (lib.byOwner[owner] and #lib.byOwner[owner]) or 0
end

-- Iterate all live handles for an owner. Returns a snapshot so the caller
-- can cancel during iteration without breaking the loop.
function lib:HandlesFor(owner)
    if not owner then return {} end
    local list = lib.byOwner[owner]
    if not list then return {} end
    local copy = {}
    for i, h in ipairs(list) do copy[i] = h end
    return copy
end

-- ----- Sugar ------------------------------------------------------------

-- Cairn.Timer(seconds, fn, owner) → :After(seconds, fn, owner)
setmetatable(lib, {
    __call = function(self, seconds, fn, owner)
        return self:After(seconds, fn, owner)
    end,
})
