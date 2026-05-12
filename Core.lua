-- Cairn-Core
--
-- Bootstraps the `_G.Cairn` namespace. Loads first so any subsequent
-- `Cairn-<Name>-1.0` lib registered via LibStub is reachable as
-- `Cairn.<Name>` instead of via the verbose `LibStub` form.
--
-- Cairn-Core is the FOUNDATION lib for the collection. Every Cairn lib
-- assumes:
--   1. The `_G.Cairn` namespace exists with the resolving metatable
--      installed (this file).
--   2. Shared helpers (`Pcall.Call`, `Table.Snapshot`, `Table.MergeDefaults`,
--      etc.) are available via `LibStub("Cairn-Util-1.0")`.
--
-- Standalone embeds: if you ship a single Cairn lib (e.g. Cairn-Settings)
-- inside your own addon without the full Cairn collection, you MUST also
-- embed Cairn-Core (this file) AND Cairn-Util. Embedding any Cairn lib
-- alone will fail at load. See README "Standalone embeds" for details.
--
-- Idempotent: if some other code already created `_G.Cairn` or installed
-- a metatable on it, we keep the existing table and CHAIN any prior
-- `__index` so we don't drop entries other code put there. Directly
-- `rawset` entries (e.g. `Cairn.LogWindow` set by Cairn-LogWindow-2.0)
-- take precedence over the metatable lookup since they're real keys.
--
-- Gui libs use the `-2.0` MAJOR family and are intentionally NOT reachable
-- through the namespace by default (`Cairn.Gui` would resolve to a missing
-- `Cairn-Gui-1.0`). Use `LibStub("Cairn-Gui-2.0")` directly.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Core-1.0"
local LIB_MINOR = 1

local Cairn_Core = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Core then return end

_G.Cairn = _G.Cairn or {}
local _CairnMT = getmetatable(_G.Cairn) or {}
-- Backcompat: pre-Core-extraction Cairn-Util (MINOR <= 14) installed the
-- resolver under sentinel `__cairn_umbrella_installed`. We check BOTH the
-- current name and the legacy name, and we SET both. Either direction of
-- mixed-version load (old code first or new code first) then short-circuits
-- correctly. Without the dual sentinel the resolver could install twice and
-- the lookup chain would do one redundant `LibStub` call per miss.
if not (_CairnMT.__cairn_namespace_installed or _CairnMT.__cairn_umbrella_installed) then
    _CairnMT.__cairn_namespace_installed = true
    _CairnMT.__cairn_umbrella_installed = true
    local priorIndex = _CairnMT.__index
    _CairnMT.__index = function(t, k)
        local lib = LibStub("Cairn-" .. tostring(k) .. "-1.0", true)
        if lib ~= nil then return lib end
        if type(priorIndex) == "function" then return priorIndex(t, k) end
        if type(priorIndex) == "table"    then return priorIndex[k]    end
        return nil
    end
    setmetatable(_G.Cairn, _CairnMT)
end

return Cairn_Core
