-- Cairn-Util-Pcall
-- Shared pcall wrappers used by the other Cairn libs to isolate consumer
-- handler errors. Every dispatch path in Cairn (Events, Hooks, Timer,
-- Callback, Settings, Addon, Slash) was carrying its own near-identical
-- safeCall: pcall the handler, route any throw through `geterrorhandler()`
-- with a library-prefixed context string. This file consolidates that.
--
-- Why route through `geterrorhandler` instead of letting pcall swallow:
-- BugGrabber / BugSack hook geterrorhandler to capture the trace, and
-- users have come to expect "errors I cause show up in BugSack". A raw
-- pcall would drop the error on the floor. We also do NOT use error() to
-- re-raise after catching, because re-raising inside a dispatch loop kills
-- the rest of the subscribers; routing through geterrorhandler reports the
-- failure without affecting siblings.
--
-- Public API:
--   local Pcall = LibStub("Cairn-Util-1.0").Pcall
--   local ok, err = Pcall.Call("Cairn-Events: handler for FOO", fn, a, b, c)
--
--   -- Returns: (ok, err)        on failure (after routing to errorhandler)
--   --          (true, ...)      on success (forwards fn's return values)
--
-- The context string is the WHOLE prefix that ends up in the error report
-- (no built-in lib name). Each call site formats it however it wants so we
-- don't have to commit to a uniform shape across libs.
--
-- License: MIT. Author: ChronicTinkerer.

local Cairn_Util = LibStub("Cairn-Util-1.0")
if not Cairn_Util then
    -- Loading order is wrong: Cairn-Util.lua must load before this file.
    error("Cairn-Util-Pcall.lua: LibStub('Cairn-Util-1.0') is nil; check TOC load order.")
end

Cairn_Util.Pcall = Cairn_Util.Pcall or {}
local Pcall = Cairn_Util.Pcall


-- Pcall.Call(context, fn, ...)
--
-- pcall(fn, ...) with errorhandler-routed failure reporting.
--
-- Returns whatever pcall returns: (true, fn-returns...) or (false, err).
-- Callers usually ignore the return value; the geterrorhandler side effect
-- is the point. The return is exposed for the rare callsite that wants to
-- branch on success (e.g. timer cancellation on handler error).
function Pcall.Call(context, fn, ...)
    if type(fn) ~= "function" then
        -- Defensive: lets dispatch loops pass through entries whose handler
        -- was nil'd out concurrently without crashing. Mirrors what the
        -- per-lib safeCall functions did with `if type(handler) ~= function
        -- then return end`.
        return true
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        geterrorhandler()(("%s threw: %s"):format(
            tostring(context or "<unknown>"), tostring(err)))
    end
    return ok, err
end


return Pcall
