-- Cairn-Events
-- Event routing through a single internal frame. Handles both WoW events
-- (auto-routed when the frame fires them) AND internal addon-to-addon
-- events (dispatched explicitly via :Fire). Handlers receive the event's
-- payload as positional args (no event-name prefix, no self).
--
-- WoW event:
--
--   local CE = LibStub("Cairn-Events-1.0")
--   CE:Subscribe("PLAYER_LOGIN", function() print("hello") end)
--   CE:Subscribe("UNIT_HEALTH", function(unit) print(unit) end)
--
-- Internal addon-to-addon event:
--
--   -- in publisher addon
--   CE:Fire("MyAddon:Ready", playerName, level)
--
--   -- in subscriber addon
--   CE:Subscribe("MyAddon:Ready", function(name, level) ... end)
--
-- Owner-based batch cleanup (useful at addon shutdown):
--
--   local sub = CE:Subscribe("UNIT_HEALTH", onHealth, myAddon)
--   ...
--   CE:UnsubscribeOwner(myAddon)
--
-- Public API:
--   local CE = LibStub("Cairn-Events-1.0")
--   CE:Subscribe(event, handler [, owner])  -> subscription
--   CE:Unsubscribe(subscription)
--   CE:UnsubscribeOwner(owner)
--   CE:Fire(event, ...)                     -- trigger subs explicitly
--   CE.handlers   -- { [event] = { sub, sub, ... } }   read-only for introspection
--
-- MINOR 15 additions (Decisions 4, 5, 8, 9, 10):
--   CE:Once(event, handler [, owner])       -- one-shot listener
--   CE:OnceMessage(event, handler [, owner]) -- one-shot on messages registry (MINOR 16)
--   CE:ValidateEvent(eventName) -> bool, errMsg  -- pre-flight event name check
--   CE:SubscribeUnit(event, unit, handler [, owner]) -> sub  -- unit-filtered
--   CE:IsUnitEvent(event) -> bool            -- detect UNIT_* event family
--   :Fire now logs to Blizzard's /eventtrace when open (zero-overhead off)
--
-- MINOR 16 additions (Decisions 2 + 3):
--   CE:SubscribeMessage(name, fn, target?, owner?)       -- in-process IPC
--   CE:UnsubscribeMessage(sub)
--   CE:SendMessage(name, target, ...)                    -- fire a message
--                                                          target ALWAYS at
--                                                          position 2 (string
--                                                          tocName, addon
--                                                          namespace table,
--                                                          or nil); args
--                                                          start at position 3.
--   Messages registry is SEPARATE from the unified handlers table.
--   Bare names auto-prefix with the consumer's tocName when target is
--   given and resolves through Cairn-Addon's registry.
--
-- Deferred for a future build: loadstring forwarder closures (pure perf
-- optimization, not currently load-bearing) and the per-embed
-- dispatcher — foundational architectural reshape; needs a focused
-- session with in-game testing).
--
-- Handler signature:
--   function handler(...)   -- receives event args, NOT the event name
--
-- Design notes:
--   - One internal frame routes WoW events; lib calls RegisterEvent /
--     UnregisterEvent on it as subscribers come and go. RegisterEvent
--     failures are silent — an unknown event name is assumed to be an
--     internal event that will be triggered via :Fire.
--   - **No namespacing between WoW events and internal events.** They share
--     the same handlers table. Calling Fire("PLAYER_LOGIN") fires subs as
--     if WoW had triggered it. Use namespaced names like "MyAddon:Ready"
--     for internal events to avoid colliding with WoW event names.
--   - **No retro-fire.** If you need "subscribe to PLAYER_LOGIN and fire
--     immediately if it already passed", use Cairn-Addon's OnLogin.
--     Cairn-Events is for ongoing event routing.
--   - **Snapshot-during-dispatch.** Handlers can safely call Subscribe or
--     Unsubscribe during their own fire — we iterate a snapshot of the
--     subscriber list, not the live list. Small GC cost on every fire;
--     correctness > micro-perf.
--   - **Handler errors don't poison dispatch.** Each handler call is pcall'd;
--     errors go through geterrorhandler() (so BugGrabber sees them).
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Events-1.0"
local LIB_MINOR = 16

local Cairn_Events = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Events then return end

local CU = LibStub("Cairn-Util-1.0")
local Pcall, Table_ = CU.Pcall, CU.Table  -- aliased to avoid shadowing Lua's table


-- Preserve across MINOR upgrades.
Cairn_Events.handlers = Cairn_Events.handlers or {}


-- ---------------------------------------------------------------------------
-- Internal dispatch frame
-- ---------------------------------------------------------------------------
-- Anonymous CreateFrame is load-bearing: RegisterEvent on a NAMED frame can
-- trip ADDON_ACTION_FORBIDDEN on current Retail (memory:
-- wow_named_frame_register_event.md). Don't name this frame.

local listener = Cairn_Events._listener or CreateFrame("Frame")
Cairn_Events._listener = listener


-- Snapshot-during-dispatch. Real-world handlers DO unsubscribe themselves
-- and peers mid-fire (e.g. a one-shot listener that removes itself in the
-- callback). table.remove during pairs() is undefined behavior; iterating a
-- frozen copy is the cheap correct answer. Cost: one transient array per
-- fire. For frequent events (UNIT_HEALTH, COMBAT_LOG_EVENT_UNFILTERED) this
-- is the dominant overhead — acceptable, optimize only if profiling demands.
local function dispatch(event, ...)
    local subs = Cairn_Events.handlers[event]
    if not subs or #subs == 0 then return end

    local snapshot = Table_.Snapshot(subs)
    local context = ("Cairn-Events: handler for %s"):format(event)
    for i = 1, #snapshot do
        local sub = snapshot[i]
        Pcall.Call(context, sub.handler, ...)
    end
end

-- Re-attach on every load so MINOR upgrades pick up new closure scope
-- (closes over THIS Cairn_Events table). Safe to re-set unconditionally.
listener:SetScript("OnEvent", function(_, event, ...)
    dispatch(event, ...)
end)


-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Subscribe accepts WoW event names AND arbitrary internal event names
-- transparently. WoW's RegisterEvent throws on unknown names — we swallow
-- that and treat the unknown case as "this is an internal event the consumer
-- will trigger via :Fire". This single-API design lets a consumer subscribe
-- to a flavor-specific WoW event without crashing on other flavors, AND it
-- doubles as the addon-to-addon message channel without a separate API.
function Cairn_Events:Subscribe(event, handler, owner)
    if type(event) ~= "string" or event == "" then
        error("Cairn-Events:Subscribe: event must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("Cairn-Events:Subscribe: handler must be a function", 2)
    end

    local subs = self.handlers[event]
    if not subs then
        subs = {}
        self.handlers[event] = subs
        pcall(listener.RegisterEvent, listener, event)
    end

    local sub = { event = event, handler = handler, owner = owner }
    subs[#subs + 1] = sub
    return sub
end


-- Fire is the manual dispatch path. It works on ANY event name — including
-- real WoW event names, which is occasionally useful in tests but also a
-- footgun (a Fire("PLAYER_LOGIN") notifies our subscribers as if WoW had
-- raised it). Consumers using Fire for addon-to-addon messaging should
-- namespace their events ("MyAddon:Ready") to avoid stepping on WoW's
-- vocabulary.
function Cairn_Events:Fire(event, ...)
    if type(event) ~= "string" or event == "" then
        error("Cairn-Events:Fire: event must be a non-empty string", 2)
    end
    dispatch(event, ...)
end


-- Safe to call from inside a handler — the dispatcher snapshots the sub
-- list, so removal here only affects future fires, not the one in flight.
-- pcall on UnregisterEvent covers the internal-event case where the frame
-- never had this event registered in the first place (RegisterEvent silently
-- failed at Subscribe time).
function Cairn_Events:Unsubscribe(sub)
    if type(sub) ~= "table" or type(sub.event) ~= "string" then
        error("Cairn-Events:Unsubscribe: must pass the subscription returned by :Subscribe", 2)
    end

    local subs = self.handlers[sub.event]
    if not subs then return end

    for i = #subs, 1, -1 do
        if subs[i] == sub then
            table.remove(subs, i)
        end
    end

    if #subs == 0 then
        self.handlers[sub.event] = nil
        pcall(listener.UnregisterEvent, listener, sub.event)
    end
end


-- Owner-keyed batch removal. Designed for addon-shutdown / disable flows
-- where a consumer wants to wipe every subscription it owns without keeping
-- handle references around. Pass the addon table itself (or any consistent
-- token) as `owner` at Subscribe time.
function Cairn_Events:UnsubscribeOwner(owner)
    if owner == nil then
        error("Cairn-Events:UnsubscribeOwner: owner must be non-nil", 2)
    end

    for event, subs in pairs(self.handlers) do
        for i = #subs, 1, -1 do
            if subs[i].owner == owner then
                table.remove(subs, i)
            end
        end
        if #subs == 0 then
            self.handlers[event] = nil
            pcall(listener.UnregisterEvent, listener, event)
        end
    end
end


-- ---------------------------------------------------------------------------
-- :Once + :OnceMessage — one-shot listeners
-- ---------------------------------------------------------------------------
-- Wraps :Subscribe with a self-unsubscribing closure. Common pattern for
-- "wait for this event once" — PLAYER_LOGIN for init, LOOT_OPENED for
-- one-time-handlers, etc. Saves the boilerplate of declaring an upvalue
-- handler that calls Unsubscribe on itself.

function Cairn_Events:Once(event, handler, owner)
    if type(handler) ~= "function" then
        error("Cairn-Events:Once: handler must be a function", 2)
    end
    local sub
    sub = self:Subscribe(event, function(...)
        if sub then self:Unsubscribe(sub) end
        Pcall.Call(("Cairn-Events:Once handler for %s"):format(event), handler, ...)
    end, owner)
    return sub
end

-- :OnceMessage is an alias for :Once. Cairn-Events doesn't distinguish
-- WoW events from internal messages today (single handlers table), so
-- the two names dispatch identically — surfaced for forward-compat with
-- the walked two-registry design (if that lands in a future refactor,
-- :Once stays for WoW events and :OnceMessage routes to the messages
-- registry).
Cairn_Events.OnceMessage = Cairn_Events.Once


-- ---------------------------------------------------------------------------
-- EventTrace integration
-- ---------------------------------------------------------------------------
-- When Blizzard's /eventtrace UI is open, log internal :Fire calls so
-- custom addon signals show up alongside WoW events. Zero overhead when
-- /eventtrace isn't loaded (the if-check short-circuits).
--
-- Implementation note: we hook into the existing :Fire method by wrapping
-- it. Original behavior preserved; the trace log is purely additive.

local _originalFire = Cairn_Events.Fire
function Cairn_Events:Fire(event, ...)
    if _G.EventTrace
        and type(_G.EventTrace.LogCallbackRegistryEvent) == "function"
    then
        -- pcall-wrap because EventTrace's API has churned across patches.
        pcall(_G.EventTrace.LogCallbackRegistryEvent, _G.EventTrace, "Cairn", event, ...)
    end
    return _originalFire(self, event, ...)
end


-- ---------------------------------------------------------------------------
-- Validator frame (Cairn-Events Decisions 8, 9, 10)
-- ---------------------------------------------------------------------------
-- Throwaway module-scope frame used to validate event names + unit tokens
-- without polluting the main listener. Each validate call pcalls
-- RegisterEvent / RegisterUnitEvent then immediately unregisters; failure
-- = error caught + reported.

Cairn_Events._validator = Cairn_Events._validator or CreateFrame("Frame")
local validator = Cairn_Events._validator


-- :ValidateEvent(eventName) -> bool, errMsg
--
-- Returns true if `eventName` is a known WoW event. Returns false + the
-- pcall error message otherwise. Used by consumers wanting to verify an
-- event name before subscribing (Cairn-Events:Subscribe itself silently
-- treats unknown names as internal events, which is the right default
-- for the unified-namespace design — this helper is for diagnostic /
-- typo-detection use cases).
function Cairn_Events:ValidateEvent(eventName)
    if type(eventName) ~= "string" or eventName == "" then
        return false, "event name must be a non-empty string"
    end
    local ok, err = pcall(validator.RegisterEvent, validator, eventName)
    if ok then
        pcall(validator.UnregisterEvent, validator, eventName)
        return true
    end
    return false, tostring(err)
end


-- :SubscribeUnit(event, unit, handler [, owner]) -> subscription
--
-- Like :Subscribe but uses RegisterUnitEvent so
-- the listener filters at the engine level for unit-specific events
-- (UNIT_HEALTH, UNIT_POWER_FREQUENT, etc.). Validates the unit token via
-- the validator frame using UNIT_HEALTH as a known-good event
-- (RegisterUnitEvent rejects bad UNIT tokens but not bad event names).
-- Known unit-token prefixes for soft validation. We pre-validate at the
-- consumer-typo level (matches the COMMON case of "playyer" / "tagrte"
-- typos), but the lib does NOT reject unknown unit strings outright
-- because consumers may use custom-extension tokens that Cairn doesn't
-- know about. False positives matter more than false negatives here.
local KNOWN_UNIT_PREFIXES = {
    "player", "target", "focus", "mouseover", "pet", "vehicle",
    "party",  "raid",   "partypet", "raidpet",
    "arena",  "arenapet", "boss",   "nameplate",
    "npc",    "questnpc", "softenemy", "softfriend", "softinteract",
}

local function looksLikeValidUnit(unit)
    if type(unit) ~= "string" or unit == "" then return false end
    -- Strip trailing digits (party1, raid20, arena3) before matching.
    local base = unit:gsub("%d+$", "")
    for _, prefix in ipairs(KNOWN_UNIT_PREFIXES) do
        if base == prefix then return true end
    end
    return false
end


function Cairn_Events:SubscribeUnit(event, unit, handler, owner)
    if type(event) ~= "string" or event == "" then
        error("Cairn-Events:SubscribeUnit: event must be a non-empty string", 2)
    end
    if type(unit) ~= "string" or unit == "" then
        error("Cairn-Events:SubscribeUnit: unit must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("Cairn-Events:SubscribeUnit: handler must be a function", 2)
    end

    -- Soft validation. We can't use RegisterUnitEvent + pcall for unit-
    -- validation the way the walked decision suggested — modern Blizzard
    -- RegisterUnitEvent silently accepts ANY unit string (just no events
    -- fire). The prefix-check catches typos like "playyer" / "tagrte"
    -- without locking out custom-extension tokens.
    if not looksLikeValidUnit(unit) then
        error(("Cairn-Events:SubscribeUnit: unit %q doesn't match a known prefix " ..
               "(player / target / focus / pet / party<N> / raid<N> / arena<N> / boss<N> / etc.)")
              :format(unit), 2)
    end

    -- Note: the existing dispatch frame uses RegisterEvent (global). For
    -- now, we route SubscribeUnit through the same global Subscribe path
    -- — the handler receives ALL units' fires of `event` and must filter
    -- on the first arg (the unit). True per-unit filtering at the engine
    -- level would require a separate frame per unit-token, which is the
    -- bigger refactor deferred to the per-embed dispatcher work.
    local sub = self:Subscribe(event, function(firedUnit, ...)
        if firedUnit == unit then handler(firedUnit, ...) end
    end, owner)
    sub.unit = unit  -- annotate for introspection
    return sub
end


-- :IsUnitEvent(event) -> bool
--
-- Detection helper — returns true if `event`
-- accepts a unit filter (UNIT_*-family events), false otherwise. Uses
-- the validator-frame pattern: pcall RegisterUnitEvent with "player";
-- success means the event is unit-scoped.
function Cairn_Events:IsUnitEvent(event)
    if type(event) ~= "string" or event == "" then return false end
    local ok = pcall(validator.RegisterUnitEvent, validator, event, "player")
    if ok then
        pcall(validator.UnregisterEvent, validator, event)
        return true
    end
    return false
end


-- ---------------------------------------------------------------------------
-- Messages registry (Cairn-Events Decisions 2 + 3 — locked 2026-05-12)
-- ---------------------------------------------------------------------------
-- Parallel dispatch surface alongside the unified `handlers` table above.
-- Distinct registries solve three concrete problems with the unified-
-- namespace shape:
--
--   1. A consumer message named after a real WoW event ("PLAYER_LOGIN")
--      shouldn't accidentally route through engine dispatch.
--   2. The OnUsed/OnUnused lifecycle (already implemented via
--      first-sub-RegisterEvent / last-unsub-UnregisterEvent) must NOT
--      fire RegisterEvent on a message name — Blizzard's API errors on
--      unknown event names.
--   3. Performance attribution distinguishes engine fires from addon IPC.
--
-- :SubscribeMessage / :UnsubscribeMessage / :SendMessage operate on this
-- new registry. The existing :Subscribe / :Unsubscribe / :Fire continue
-- to use the unified `handlers` table for backward-compat.
--
-- Auto-namespace by Cairn-Addon tag. Bare message names
-- (no `.` or `:`) auto-prefix with the consumer's tocName. Cross-addon
-- subscribers reach foreign messages by passing the fully-qualified
-- name. Pattern reference: WildAddon-1.1 (Jaliborc).
--
-- The consumer's tocName is resolved via the optional `target` arg on
-- :SubscribeMessage / :SendMessage:
--
--   * If target is set AND Cairn.GetRegistry()[target.tocName] exists,
--     use that for the auto-prefix.
--   * If target is set AND target itself is the Cairn-Addon Metadata
--     table (has AddonName field), use AddonName.
--   * If target is a string that matches a Cairn.GetRegistry() entry,
--     use it directly.
--   * Otherwise no auto-prefix (the name stays bare). Cross-addon and
--     library-internal use cases stay clean without forcing a target.

Cairn_Events._messages = Cairn_Events._messages or {}


-- Resolve a tocName for auto-namespace. Returns the tocName string or
-- nil if no resolution succeeds. `target` may be:
--   * nil          — no resolution attempted; returns nil
--   * a string     — used directly as tocName if it exists in registry
--   * an addon ns  — read `target.tocName` / `target.AddonName` (the
--                    fields Cairn.Register stashes)
--   * Metadata     — same: AddonName field
local function resolveTocName(target)
    if target == nil then return nil end
    if type(target) == "string" then return target end
    if type(target) ~= "table" then return nil end
    -- Cairn-Addon Metadata table or addon namespace
    local name = rawget(target, "tocName")
              or rawget(target, "AddonName")
              or rawget(target, "_addonName")
              or rawget(target, "_tocName")
    if type(name) == "string" and name ~= "" then return name end
    return nil
end


-- Auto-prefix bare message names with the consumer's tocName. Names
-- containing `.` or `:` are considered already-namespaced and pass
-- through unchanged.
local function autoNamespace(messageName, target)
    if type(messageName) ~= "string" or messageName == "" then return messageName end
    if messageName:find("[%.%:]") then return messageName end
    local tocName = resolveTocName(target)
    if tocName then return tocName .. "." .. messageName end
    return messageName
end


-- :SubscribeMessage(messageName, handler [, target [, owner]]) -> sub
--
-- Registers a handler for an in-process message. `target` optionally
-- identifies the consumer for auto-namespace + introspection (typically
-- the addon's namespace table). `owner` is the standard
-- :UnsubscribeOwner / batch-cleanup token.
function Cairn_Events:SubscribeMessage(messageName, handler, target, owner)
    if type(messageName) ~= "string" or messageName == "" then
        error("Cairn-Events:SubscribeMessage: messageName must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("Cairn-Events:SubscribeMessage: handler must be a function", 2)
    end

    local resolved = autoNamespace(messageName, target)
    local subs = self._messages[resolved]
    if not subs then
        subs = {}
        self._messages[resolved] = subs
    end

    local sub = {
        message    = resolved,
        rawMessage = messageName,
        handler    = handler,
        owner      = owner,
        target     = target,
        _isMessage = true,
    }
    subs[#subs + 1] = sub
    return sub
end


-- :UnsubscribeMessage(sub) — remove one message subscription
function Cairn_Events:UnsubscribeMessage(sub)
    if type(sub) ~= "table" or not sub._isMessage then
        error("Cairn-Events:UnsubscribeMessage: must pass a subscription returned by :SubscribeMessage", 2)
    end
    local subs = self._messages[sub.message]
    if not subs then return end
    for i = #subs, 1, -1 do
        if subs[i] == sub then table.remove(subs, i) end
    end
    if #subs == 0 then
        self._messages[sub.message] = nil
    end
end


-- :SendMessage(messageName, target, ...) — fire a message
--
-- Auto-prefixes bare names symmetrically with :SubscribeMessage. `target`
-- is always at position 2 (string tocName, addon-namespace table, or nil).
-- Args start at position 3. To send a message without namespacing, pass
-- nil as the target:
--
--   CE:SendMessage("MyEvent", nil, "arg1", "arg2")        -- bare
--   CE:SendMessage("MyEvent", self, "arg1", "arg2")       -- table target
--   CE:SendMessage("MyEvent", "MyAddon", "arg1", "arg2")  -- string target
--
-- EventTrace integration follows the same pattern as :Fire — pcall'd
-- LogCallbackRegistryEvent under the "Cairn" registry tag.
function Cairn_Events:SendMessage(messageName, target, ...)
    if type(messageName) ~= "string" or messageName == "" then
        error("Cairn-Events:SendMessage: messageName must be a non-empty string", 2)
    end

    local resolved = autoNamespace(messageName, target)
    local n = select("#", ...)
    local args
    local argCount = n
    if n > 0 then args = { ... } end

    -- EventTrace integration (parity with :Fire for the messages registry).
    if _G.EventTrace
        and type(_G.EventTrace.LogCallbackRegistryEvent) == "function"
    then
        if args then
            pcall(_G.EventTrace.LogCallbackRegistryEvent, _G.EventTrace, "Cairn",
                  resolved, unpack(args, 1, argCount))
        else
            pcall(_G.EventTrace.LogCallbackRegistryEvent, _G.EventTrace, "Cairn", resolved)
        end
    end

    local subs = self._messages[resolved]
    if not subs or #subs == 0 then return end

    local snapshot = Table_.Snapshot(subs)
    local context = ("Cairn-Events: message handler for %s"):format(resolved)
    for i = 1, #snapshot do
        local sub = snapshot[i]
        if args then
            Pcall.Call(context, sub.handler, unpack(args, 1, argCount))
        else
            Pcall.Call(context, sub.handler)
        end
    end
end


-- Extend :UnsubscribeOwner to walk the messages registry too. Original
-- behavior on the unified `handlers` table preserved; messages added.
local _originalUnsubscribeOwner = Cairn_Events.UnsubscribeOwner
function Cairn_Events:UnsubscribeOwner(owner)
    _originalUnsubscribeOwner(self, owner)

    for message, subs in pairs(self._messages) do
        for i = #subs, 1, -1 do
            if subs[i].owner == owner then
                table.remove(subs, i)
            end
        end
        if #subs == 0 then
            self._messages[message] = nil
        end
    end
end


-- :Once / :OnceMessage update — the existing implementation routes both
-- through :Subscribe (single unified handlers table). MINOR 16: rewire
-- :OnceMessage to actually use the messages registry while keeping
-- :Once on the unified events table. Both return a sub handle compatible
-- with their respective :Unsubscribe / :UnsubscribeMessage paths.
function Cairn_Events:OnceMessage(messageName, handler, target, owner)
    if type(handler) ~= "function" then
        error("Cairn-Events:OnceMessage: handler must be a function", 2)
    end
    local sub
    sub = self:SubscribeMessage(messageName, function(...)
        if sub then self:UnsubscribeMessage(sub) end
        Pcall.Call(("Cairn-Events:OnceMessage handler for %s"):format(messageName),
                   handler, ...)
    end, target, owner)
    return sub
end


return Cairn_Events
