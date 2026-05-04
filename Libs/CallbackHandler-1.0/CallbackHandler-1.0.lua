--[[ CallbackHandler-1.0 -- proxy shim for Cairn-Callback-1.0

    This file replaces the upstream WoWAce CallbackHandler-1.0 with a thin
    proxy that delegates to Cairn-Callback-1.0. It registers under the
    upstream LibStub name ("CallbackHandler-1.0") so any third-party library
    that calls LibStub("CallbackHandler-1.0") -- notably LibSharedMedia-3.0
    and the Diesal-derived Cairn-Gui-* family -- transparently uses the
    Cairn implementation.

    Cairn does not ship the original WoWAce CallbackHandler source. The MINOR
    here is set deliberately high so that if another loaded addon DOES embed
    a real upstream copy, LibStub still picks ours and consumers see one
    consistent backing implementation.

    The exposed surface matches the upstream contract:
        local registry = CallbackHandler:New(target,
                                             RegisterName,
                                             UnregisterName,
                                             UnregisterAllName)
        registry:Fire(eventname, ...)
        registry.OnUsed   = function(reg, target, eventname) ... end
        registry.OnUnused = function(reg, target, eventname) ... end

    target gets RegisterName / UnregisterName / UnregisterAllName methods
    installed on it (default "RegisterCallback", "UnregisterCallback",
    "UnregisterAllCallbacks"). All callback-registration calling styles the
    upstream supports are honored:
        target:RegisterCallback(event, "methodname"[, arg])
        target:RegisterCallback(event, fn[, arg])

    CallbackHandler-1.0 shim (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "CallbackHandler-1.0", 999
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)
if not CallbackHandler then return end

local Cairn = LibStub("Cairn-Callback-1.0", true)
if not Cairn then
    error("CallbackHandler-1.0 shim requires Cairn-Callback-1.0; load it first in the .toc.")
end

-- :New(target, RegisterName, UnregisterName, UnregisterAllName) ----------
-- Mirrors WoWAce CallbackHandler-1.0:New behavior. The fifth and sixth
-- arguments (OnUsed, OnUnused) were deprecated upstream around ACE-80; we
-- reject them too so misuse fails loudly rather than silently.
function CallbackHandler:New(target, RegisterName, UnregisterName, UnregisterAllName, deprecatedA, deprecatedB)
    assert(not deprecatedA and not deprecatedB,
        "CallbackHandler-1.0: OnUsed/OnUnused as constructor args are deprecated. Set registry.OnUsed and registry.OnUnused after :New.")

    RegisterName     = RegisterName     or "RegisterCallback"
    UnregisterName   = UnregisterName   or "UnregisterCallback"
    if UnregisterAllName == nil then
        UnregisterAllName = "UnregisterAllCallbacks"
    end

    local backing  = Cairn.New()
    local registry = { recurse = 0 }  -- recurse retained for upstream parity

    -- Bridge OnUsed / OnUnused: read from the registry table at fire time so
    -- consumers can assign these after :New just like upstream allows.
    backing:SetOnUsed(function(_, eventname)
        local fn = registry.OnUsed
        if fn then fn(registry, target, eventname) end
    end)
    backing:SetOnUnused(function(_, eventname)
        local fn = registry.OnUnused
        if fn then fn(registry, target, eventname) end
    end)

    -- registry:Fire(eventname, ...) ---------------------------------------
    -- Upstream Fire passes eventname as the first arg to subscribers when
    -- they registered with a function ref (no method name). Our subscribers
    -- below preserve that calling convention via wrapper closures.
    function registry:Fire(eventname, ...)
        backing:Fire(eventname, ...)
    end

    -- target:RegisterCallback(eventname, method[, arg]) -------------------
    target[RegisterName] = function(self, eventname, method, ...)
        if type(eventname) ~= "string" then
            error(("Usage: %s(eventname, method[, arg]): 'eventname' - string expected."):format(RegisterName), 2)
        end
        method = method or eventname

        if type(method) ~= "string" and type(method) ~= "function" then
            error(("Usage: %s(\"eventname\", \"methodname\"): 'methodname' - string or function expected."):format(RegisterName), 2)
        end

        local hasArg = select("#", ...) >= 1
        local arg    = (...)

        local regfunc
        if type(method) == "string" then
            -- "self[method]" calling style: callback is self:method(...)
            if type(self) ~= "table" then
                error(("Usage: %s(\"eventname\", \"methodname\"): self was not a table?"):format(RegisterName), 2)
            elseif self == target then
                error(("Usage: %s(\"eventname\", \"methodname\"): do not use Library:%s(), use your own 'self'"):format(RegisterName, RegisterName), 2)
            elseif type(self[method]) ~= "function" then
                error(("Usage: %s(\"eventname\", \"methodname\"): 'methodname' - method '%s' not found on self."):format(RegisterName, tostring(method)), 2)
            end
            if hasArg then
                regfunc = function(eventname, ...) self[method](self, arg, eventname, ...) end
            else
                regfunc = function(eventname, ...) self[method](self, eventname, ...) end
            end
        else
            -- Function-ref calling style.
            if type(self) ~= "table" and type(self) ~= "string" and type(self) ~= "thread" then
                error(("Usage: %s(self or \"addonId\", eventname, method): 'self or addonId': table or string or thread expected."):format(RegisterName), 2)
            end
            if hasArg then
                regfunc = function(eventname, ...) method(arg, eventname, ...) end
            else
                regfunc = function(eventname, ...) method(eventname, ...) end
            end
        end

        backing:Subscribe(eventname, self, regfunc)
    end

    -- target:UnregisterCallback(eventname) --------------------------------
    target[UnregisterName] = function(self, eventname)
        if not self or self == target then
            error(("Usage: %s(eventname): bad 'self'"):format(UnregisterName), 2)
        end
        if type(eventname) ~= "string" then
            error(("Usage: %s(eventname): 'eventname' - string expected."):format(UnregisterName), 2)
        end
        backing:Unsubscribe(eventname, self)
    end

    -- target:UnregisterAllCallbacks(...) ---------------------------------
    if UnregisterAllName then
        target[UnregisterAllName] = function(...)
            if select("#", ...) < 1 then
                error(("Usage: %s([whatFor]): missing 'self' or \"addonId\" to unregister events for."):format(UnregisterAllName), 2)
            end
            if select("#", ...) == 1 and ... == target then
                error(("Usage: %s([whatFor]): supply a meaningful 'self' or \"addonId\""):format(UnregisterAllName), 2)
            end
            for i = 1, select("#", ...) do
                backing:UnsubscribeAll((select(i, ...)))
            end
        end
    end

    return registry
end
