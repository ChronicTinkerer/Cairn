--[[ CallbackHandler-1.0 -- Cairn implementation, byte-equivalent to the
     ElvUI bundled variant of upstream WoWAce CallbackHandler-1.0.

    History
    -------
    First attempt was a thin proxy that delegated to Cairn-Callback-1.0.
    That diverged subtly from upstream and broke ElvUI's unit-frame init
    (see memory file cairn_callbackhandler_shim_breaks_elvui.md).

    Second attempt was a direct port of upstream WoWAce CallbackHandler-1.0
    ($Id: 965 2010-08-09, MINOR=6). That ALSO broke ElvUI in the same way:
    Range.lua kept hitting "self.unitframe is nil" during early dispatch,
    even with byte-equivalent upstream behavior. Conclusion: ElvUI's
    bundled MINOR=8 variant is the implementation ElvUI's own modules are
    actually tested against -- not the 2010-era WoWAce reference.

    Current implementation (2026-05-04) is a port of ElvUI's bundled
    CallbackHandler-1.0 ($Id: 26 2022-12-12 nevcairiel, MINOR=8). The body
    is byte-equivalent so ElvUI's modules see exactly the dispatch
    semantics they expect. We register at MINOR=999 so we win LibStub
    against any other copy in the user's environment, which gives us a
    single consistent backing for every consumer (ElvUI, LibSharedMedia,
    Cairn-Gui-*, AceEvent, etc.). That single backing means every newly
    created registry passes through OUR :New, so the Cairn instance
    tracker at the bottom catches every one of them and Forge_Registry's
    Callbacks source has full visibility.

    Cairn extension
    ---------------
    The only addition over the ElvUI body is a registry-tracking hook at
    the end of :New that records each new registry into
    `LibStub("Cairn-Callback-1.0").instances` with a derived label.
    Forge_Registry reads `reg.events` and `reg.recurse` from each entry,
    both of which the upstream layout provides natively.

    Provenance
    ----------
    Implementation derived from ElvUI's bundled CallbackHandler-1.0
    ($Id: CallbackHandler-1.0.lua 26 2022-12-12 15:09:39Z nevcairiel),
    which is itself a Blizzard-modernized variant of WoWAce
    CallbackHandler-1.0 ($Id: 965 2010-08-09 mikk). Both upstream sources
    are distributed under permissive terms compatible with redistribution.
    Cairn additions (instance-tracking hook, deriveLabel) are MIT.

    Why this implementation specifically
    ------------------------------------
    ElvUI's variant uses `securecallfunction(method, ...)` instead of the
    upstream loadstring-generated per-argcount Dispatcher with
    `xpcall(call, eh)`. In modern Retail (Interface 120005) the
    securecallfunction-based path is what most modern Ace3 consumers are
    tested against, so this is the safest body to ship as the fallback
    when no other CallbackHandler-1.0 is around.

    MINOR strategy
    --------------
    Set to 7. Beats upstream WoWAce ($Id: 965, MINOR=6) so we win when
    nothing else competes (the LSM-and-Cairn-Gui-only case). Loses to
    ElvUI's bundled MINOR=8, so when ElvUI is present ElvUI's body owns
    the dispatch chain. This is intentional: empirically, even minor
    work inside our :New (a single weak-table write to track the new
    registry) races with ElvUI's unitframe-init and breaks Range.lua.
    The race was never fully diagnosed; the safe ground rule is that
    when ElvUI is in the user's environment, ElvUI's CallbackHandler is
    the one consumers see.

    Forge_Registry's "Callbacks" source uses a hybrid discovery path:
    primary = read `Cairn-Callback.instances` (populated by our :New
    hook below, when our shim wins), fallback = lazy LibStub.libs scan
    that duck-types each lib's fields for callback registries. The
    fallback covers the ElvUI-wins case where our :New never runs.
]]

local MAJOR, MINOR = "CallbackHandler-1.0", 7
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)
if not CallbackHandler then return end

local meta = {__index = function(tbl, key) tbl[key] = {} return tbl[key] end}

-- Lua APIs
local securecallfunction, error = securecallfunction, error
local setmetatable, rawget = setmetatable, rawget
local next, select, pairs, type, tostring = next, select, pairs, type, tostring


local function Dispatch(handlers, ...)
    local index, method = next(handlers)
    if not method then return end
    repeat
        securecallfunction(method, ...)
        index, method = next(handlers, index)
    until not method
end

-- Cairn extension. Pick a useful label for `target` so Forge_Registry can
-- show recognizable rows. Intentionally does NOT walk LibStub.libs: an
-- earlier version did, and walking pairs(LibStub.libs) inside :New raced
-- with ElvUI's unit-frame init in ways we never fully diagnosed but
-- empirically reproduced. Targets that expose a name field (MAJOR / name /
-- label) get a clean label; everything else falls back to tostring (table
-- address). Forge_Registry's UI should treat unlabeled rows gracefully.
local function deriveLabel(target)
    if type(target) == "string" then return target end
    if type(target) == "table" then
        return target.MAJOR or target.name or target.label or tostring(target)
    end
    return tostring(target)
end

--------------------------------------------------------------------------
-- CallbackHandler:New
--
--   target            - target object to embed public APIs in
--   RegisterName      - name of the callback registration API, default "RegisterCallback"
--   UnregisterName    - name of the callback unregistration API, default "UnregisterCallback"
--   UnregisterAllName - name of the API to unregister all callbacks, default "UnregisterAllCallbacks". false == don't publish this API.

function CallbackHandler.New(_self, target, RegisterName, UnregisterName, UnregisterAllName)

    RegisterName = RegisterName or "RegisterCallback"
    UnregisterName = UnregisterName or "UnregisterCallback"
    if UnregisterAllName==nil then  -- false is used to indicate "don't want this method"
        UnregisterAllName = "UnregisterAllCallbacks"
    end

    -- we declare all objects and exported APIs inside this closure to quickly gain access
    -- to e.g. function names, the "target" parameter, etc


    -- Create the registry object
    local events = setmetatable({}, meta)
    local registry = { recurse=0, events=events }

    -- registry:Fire() - fires the given event/message into the registry
    function registry:Fire(eventname, ...)
        if not rawget(events, eventname) or not next(events[eventname]) then return end
        local oldrecurse = registry.recurse
        registry.recurse = oldrecurse + 1

        Dispatch(events[eventname], eventname, ...)

        registry.recurse = oldrecurse

        if registry.insertQueue and oldrecurse==0 then
            -- Something in one of our callbacks wanted to register more callbacks; they got queued
            for event,callbacks in pairs(registry.insertQueue) do
                local first = not rawget(events, event) or not next(events[event])  -- test for empty before. not test for one member after. that one member may have been overwritten.
                for object,func in pairs(callbacks) do
                    events[event][object] = func
                    -- fire OnUsed callback?
                    if first and registry.OnUsed then
                        registry.OnUsed(registry, target, event)
                        first = nil
                    end
                end
            end
            registry.insertQueue = nil
        end
    end

    -- Registration of a callback, handles:
    --   self["method"], leads to self["method"](self, ...)
    --   self with function ref, leads to functionref(...)
    --   "addonId" (instead of self) with function ref, leads to functionref(...)
    -- all with an optional arg, which, if present, gets passed as first argument (after self if present)
    target[RegisterName] = function(self, eventname, method, ... --[[actually just a single arg]])
        if type(eventname) ~= "string" then
            error("Usage: "..RegisterName.."(eventname, method[, arg]): 'eventname' - string expected.", 2)
        end

        method = method or eventname

        local first = not rawget(events, eventname) or not next(events[eventname])  -- test for empty before. not test for one member after. that one member may have been overwritten.

        if type(method) ~= "string" and type(method) ~= "function" then
            error("Usage: "..RegisterName.."(\"eventname\", \"methodname\"): 'methodname' - string or function expected.", 2)
        end

        local regfunc

        if type(method) == "string" then
            -- self["method"] calling style
            if type(self) ~= "table" then
                error("Usage: "..RegisterName.."(\"eventname\", \"methodname\"): self was not a table?", 2)
            elseif self==target then
                error("Usage: "..RegisterName.."(\"eventname\", \"methodname\"): do not use Library:"..RegisterName.."(), use your own 'self'", 2)
            elseif type(self[method]) ~= "function" then
                error("Usage: "..RegisterName.."(\"eventname\", \"methodname\"): 'methodname' - method '"..tostring(method).."' not found on self.", 2)
            end

            if select("#",...)>=1 then  -- this is not the same as testing for arg==nil!
                local arg=select(1,...)
                regfunc = function(...) self[method](self,arg,...) end
            else
                regfunc = function(...) self[method](self,...) end
            end
        else
            -- function ref with self=object or self="addonId" or self=thread
            if type(self)~="table" and type(self)~="string" and type(self)~="thread" then
                error("Usage: "..RegisterName.."(self or \"addonId\", eventname, method): 'self or addonId': table or string or thread expected.", 2)
            end

            if select("#",...)>=1 then  -- this is not the same as testing for arg==nil!
                local arg=select(1,...)
                regfunc = function(...) method(arg,...) end
            else
                regfunc = method
            end
        end


        if events[eventname][self] or registry.recurse<1 then
        -- if registry.recurse<1 then
            -- we're overwriting an existing entry, or not currently recursing. just set it.
            events[eventname][self] = regfunc
            -- fire OnUsed callback?
            if registry.OnUsed and first then
                registry.OnUsed(registry, target, eventname)
            end
        else
            -- we're currently processing a callback in this registry, so delay the registration of this new entry!
            -- yes, we're a bit wasteful on garbage, but this is a fringe case, so we're picking low implementation overhead over garbage efficiency
            registry.insertQueue = registry.insertQueue or setmetatable({},meta)
            registry.insertQueue[eventname][self] = regfunc
        end
    end

    -- Unregister a callback
    target[UnregisterName] = function(self, eventname)
        if not self or self==target then
            error("Usage: "..UnregisterName.."(eventname): bad 'self'", 2)
        end
        if type(eventname) ~= "string" then
            error("Usage: "..UnregisterName.."(eventname): 'eventname' - string expected.", 2)
        end
        if rawget(events, eventname) and events[eventname][self] then
            events[eventname][self] = nil
            -- Fire OnUnused callback?
            if registry.OnUnused and not next(events[eventname]) then
                registry.OnUnused(registry, target, eventname)
            end
        end
        if registry.insertQueue and rawget(registry.insertQueue, eventname) and registry.insertQueue[eventname][self] then
            registry.insertQueue[eventname][self] = nil
        end
    end

    -- OPTIONAL: Unregister all callbacks for given selfs/addonIds
    if UnregisterAllName then
        target[UnregisterAllName] = function(...)
            if select("#",...)<1 then
                error("Usage: "..UnregisterAllName.."([whatFor]): missing 'self' or \"addonId\" to unregister events for.", 2)
            end
            if select("#",...)==1 and ...==target then
                error("Usage: "..UnregisterAllName.."([whatFor]): supply a meaningful 'self' or \"addonId\"", 2)
            end


            for i=1,select("#",...) do
                local self = select(i,...)
                if registry.insertQueue then
                    for eventname, callbacks in pairs(registry.insertQueue) do
                        if callbacks[self] then
                            callbacks[self] = nil
                        end
                    end
                end
                for eventname, callbacks in pairs(events) do
                    if callbacks[self] then
                        callbacks[self] = nil
                        -- Fire OnUnused callback?
                        if registry.OnUnused and not next(callbacks) then
                            registry.OnUnused(registry, target, eventname)
                        end
                    end
                end
            end
        end
    end

    -- Cairn extension: track the new registry in Cairn-Callback's instances
    -- table so Forge_Registry's "Callbacks" source can enumerate it. This
    -- hook only runs when our shim wins LibStub (MINOR=7 means we lose to
    -- ElvUI's MINOR=8 but beat upstream WoWAce MINOR=6). Even a trivial
    -- weak-table write here was empirically observed to race with ElvUI's
    -- unitframe-init -- so when ElvUI is present we deliberately lose
    -- LibStub and this code never executes. Forge_Registry has a
    -- LibStub.libs-scan fallback for that case.
    local Cairn_Callback = LibStub("Cairn-Callback-1.0", true)
    if Cairn_Callback then
        Cairn_Callback.instances = Cairn_Callback.instances or setmetatable({}, { __mode = "k" })
        Cairn_Callback.instances[registry] = deriveLabel(target)
    end

    return registry
end


-- CallbackHandler purposefully does NOT do explicit embedding. Nor does it
-- try to upgrade old implicit embeds since the system is selfcontained and
-- relies on closures to work.
