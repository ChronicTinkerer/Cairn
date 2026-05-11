-- Cairn-Util
-- A collection of small utilities organized into named sub-namespaces.
-- The main lib file is just a registration skeleton; each category lives in
-- its own file under the same folder and attaches itself to this lib's
-- table at load time.
--
-- Consumer view:
--
--   local CU = LibStub("Cairn-Util-1.0")
--   CU.Hash.MD5("hello")              -- defined in Cairn-Util-Hash.lua
--   CU.Math.Clamp(x, 0, 1)            -- defined in Cairn-Util-Math.lua (future)
--   CU.String.IsBlank(s)              -- defined in Cairn-Util-String.lua (future)
--
-- File layout for adding a new category:
--
--   1. Create Cairn-Util-<Category>.lua in this folder.
--   2. In the file: grab the lib via LibStub("Cairn-Util-1.0"), attach a
--      sub-table (`CU.<Category> = CU.<Category> or {}`), define functions
--      under it.
--   3. Add the new file to the .toc AFTER Cairn-Util.lua (so the lib is
--      registered first) and after any vendored deps it needs.
--
-- Sizing rule (from OBJECTIVES.md): the COLLECTION can grow as needed,
-- but Cairn-Util only earns its keep as a place for helpers that are too
-- small to justify their own lib. If a category file grows past ~300 lines
-- of its own code (vendored algorithms don't count), that's a signal to
-- split it into a dedicated Cairn-<Name> lib instead of stuffing it here.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Util-1.0"
local LIB_MINOR = 14

local Cairn_Util = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Util then return end


-- ---------------------------------------------------------------------------
-- _G.Cairn umbrella table
-- ---------------------------------------------------------------------------
-- Consumers prefer `Cairn.Addon:New("Foo")` over the verbose
-- `LibStub("Cairn-Addon-1.0"):New("Foo")`. We set up `_G.Cairn` as a thin
-- shim with a `__index` metamethod that resolves `Cairn.<Name>` to
-- `LibStub("Cairn-<Name>-1.0")` lazily.
--
-- Cairn-Util loads first in the TOC, so the umbrella is in place BEFORE any
-- other Cairn lib registers. The lazy lookup means we don't have to know
-- which libs exist at umbrella-creation time — any `Cairn-X-1.0` registered
-- later (in the same TOC pass OR in a downstream addon) just works.
--
-- Idempotent: if some other code already created `_G.Cairn` (e.g. an old v1
-- addon, or a previously-loaded copy of this lib at lower MINOR), we keep
-- the existing table, install our metatable, and CHAIN any prior `__index`
-- so we don't drop entries other code put there. Directly-`rawset` entries
-- (e.g. `Cairn.LogWindow` set by `Cairn-LogWindow-2.0.lua`) take precedence
-- over the metatable lookup since they're real keys in the table.
--
-- Gui libs use the `-2.0` MAJOR and are NOT reachable through this umbrella
-- by default (Cairn.Gui would resolve to a missing `Cairn-Gui-1.0`). Gui
-- consumers should use `LibStub("Cairn-Gui-2.0")` directly, or rely on
-- libs that rawset themselves into the umbrella (Cairn-LogWindow-2.0 does
-- this for `Cairn.LogWindow`).

_G.Cairn = _G.Cairn or {}
local _CairnMT = getmetatable(_G.Cairn) or {}
if not _CairnMT.__cairn_umbrella_installed then
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


return Cairn_Util
