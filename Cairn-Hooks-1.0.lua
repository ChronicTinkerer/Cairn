--[[
Cairn-Hooks-1.0

Shared API for the common hook patterns: post-hook a global function, post-hook
a method on a frame or table, and unhook by closure. Multiple Cairn-using addons
can register hooks against the same function without stomping each other; we
install one underlying `hooksecurefunc` per (target, name) and dispatch to all
active callbacks.

WoW limitation: `hooksecurefunc` cannot be undone within a session. The unhook
closure marks our specific callback inactive, so future fires skip it; the
underlying secure-hook stays registered for the rest of the session.

Public API:

    local Hooks = Cairn.Hooks

    -- Post-hook a global function (two-arg form).
    local unhook = Hooks.Post("seterrorhandler", function(newHandler)
        ...
    end)

    -- Post-hook a method on a frame or table (three-arg form).
    Hooks.Post(SomeFrame, "Show", function(self) ... end)

    -- Sugar alias for the three-arg form.
    Hooks.Method(SomeFrame, "Show", function(self) ... end)

    -- Diagnostics.
    Hooks.Has(target, name)    -- true if at least one hook is wired
    Hooks.Count(target, name)  -- count of *active* (not unhooked) callbacks

The Post callback receives the same arguments the hooked function received. For
methods, the first argument is the receiver (`self`).

Pre-hooks are NOT included in v0.2; secure pre-hooking is risky. v0.3 may add
unsecure-only `Hooks.Pre`.

Ace3 comparison: similar surface to AceHook-3.0 but drastically smaller and
without the embed model. Cairn favors closure unhooks over owner-tracked
unhook-all.
]]

local MAJOR, MINOR = "Cairn-Hooks-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- One entry per (target, name): the underlying hooksecurefunc + a list of
-- callback descriptors. Persists across LibStub upgrades within a session.
lib._registry = lib._registry or {}

local function regKey(target, name)
    if target == nil or target == _G then
        return "_G:" .. name
    end
    return tostring(target) .. ":" .. name
end

local function dispatcherFor(entry)
    return function(...)
        local cbs = entry.callbacks
        for i = 1, #cbs do
            local cb = cbs[i]
            if cb and not cb.removed then
                local ok, err = pcall(cb.fn, ...)
                if not ok and geterrorhandler then
                    pcall(geterrorhandler(), err)
                end
            end
        end
    end
end

local function getOrInstall(target, name)
    local key = regKey(target, name)
    local entry = lib._registry[key]
    if entry then return entry end

    entry = { target = target, name = name, callbacks = {} }
    lib._registry[key] = entry

    local dispatcher = dispatcherFor(entry)
    -- Wrap hooksecurefunc in pcall: Midnight (Interface 120005) and modern
    -- Retail forbid hooking certain protected globals (seterrorhandler,
    -- TOGGLEGAMEMENU, etc.) and throw "X is forbidden for hooking" at the
    -- call site. We still want the registry entry installed so direct
    -- callers via Cairn.Hooks.Run can fire the dispatcher manually -- the
    -- only thing we lose on a failure is the implicit pre/post hook trigger.
    -- entry.hookInstalled records whether the engine accepted the hook.
    if target == nil or target == _G then
        if hooksecurefunc then
            local ok = pcall(hooksecurefunc, name, dispatcher)
            entry.hookInstalled = ok and true or false
        end
    else
        if hooksecurefunc then
            local ok = pcall(hooksecurefunc, target, name, dispatcher)
            entry.hookInstalled = ok and true or false
        end
    end

    return entry
end

-- Internal arg normalization. Accepts:
--   Post("name", fn)
--   Post(target, "name", fn)
local function normalize(a, b, c)
    if c == nil then
        -- two-arg form: a = name (string), b = fn
        return nil, a, b
    end
    return a, b, c
end

function lib.Post(a, b, c)
    local target, name, fn = normalize(a, b, c)
    if type(name) ~= "string" or name == "" then
        error("Cairn.Hooks.Post: name must be a non-empty string", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn.Hooks.Post: fn must be a function", 2)
    end
    if target ~= nil and target ~= _G then
        if type(target) ~= "table" then
            error("Cairn.Hooks.Post: target must be nil/_G or a table", 2)
        end
        if type(target[name]) ~= "function" then
            error("Cairn.Hooks.Post: target." .. name .. " is not a function", 2)
        end
    end

    local entry = getOrInstall(target, name)
    local cb = { fn = fn, removed = false }
    entry.callbacks[#entry.callbacks + 1] = cb
    return function() cb.removed = true end
end

-- Sugar: Method is just Post forced into three-arg form.
function lib.Method(target, name, fn)
    if type(target) ~= "table" then
        error("Cairn.Hooks.Method: target must be a table or frame", 2)
    end
    return lib.Post(target, name, fn)
end

function lib.Has(target, name)
    local entry = lib._registry[regKey(target, name)]
    if not entry then return false end
    for i = 1, #entry.callbacks do
        if not entry.callbacks[i].removed then return true end
    end
    return false
end

function lib.Count(target, name)
    local entry = lib._registry[regKey(target, name)]
    if not entry then return 0 end
    local n = 0
    for i = 1, #entry.callbacks do
        if not entry.callbacks[i].removed then n = n + 1 end
    end
    return n
end

setmetatable(lib, { __call = function(self, a, b, c) return self.Post(a, b, c) end })
