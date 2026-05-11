-- Cairn-Util-Table
-- Small table helpers shared across the Cairn libs. Lives under
-- `Cairn-Util` (`local Table = LibStub("Cairn-Util-1.0").Table`).
--
-- Two helpers ship in v1:
--   - Table.Snapshot(arr)          -- shallow array copy, for safe iteration
--   - Table.MergeDefaults(target, defaults)
--                                   -- recursive non-destructive merge
--
-- Both are intentionally narrow. We're NOT building lodash; we're pulling
-- the duplicated 8-line copies out of Events / Callback / Timer / DB and
-- giving them one well-tested home.
--
-- License: MIT. Author: ChronicTinkerer.

local Cairn_Util = LibStub("Cairn-Util-1.0")
if not Cairn_Util then
    error("Cairn-Util-Table.lua: LibStub('Cairn-Util-1.0') is nil; check TOC load order.")
end

Cairn_Util.Table = Cairn_Util.Table or {}
local Table = Cairn_Util.Table


-- Table.Snapshot(arr) -> { copy }
--
-- Shallow copy of an array-shaped table. Used before iterating a list
-- whose entries may unsubscribe or otherwise mutate the source during
-- dispatch (a handler that calls Unsubscribe on itself, a timer callback
-- that schedules another timer that lands in the same bucket, etc).
--
-- We freeze the indices we're going to walk so mutation of `arr` during
-- the loop can't shift entries underneath us, skip an entry, or visit
-- the same entry twice. Callers still have to check whether each snapshot
-- entry is still "live" (handler != nil, cancelled flag not set, etc.)
-- since the snapshot can go stale; the snapshot prevents structural
-- corruption, not logical staleness.
--
-- Returns a new table even when arr is nil/empty (so the caller can do an
-- unconditional `for i = 1, #snap do ... end`).
function Table.Snapshot(arr)
    local out = {}
    if type(arr) ~= "table" then return out end
    local n = #arr
    for i = 1, n do
        out[i] = arr[i]
    end
    return out
end


-- Table.MergeDefaults(target, defaults)
--
-- Recursive deep merge: copy values from `defaults` into `target` only
-- where `target` is missing them. Tables are recursed into; leaf values
-- (including `false` and `0`) are preserved if the caller already set them.
--
-- Used primarily by Cairn-DB.New() to layer defaults onto a fresh
-- SavedVariables table without clobbering user data on relog. Safe to call
-- repeatedly: idempotent on a fully-defaulted target.
--
-- Edge case: if `target[k]` is a non-table value and `defaults[k]` is a
-- table, we DO NOT overwrite. The user's scalar wins. This matches the
-- behavior of the original mergeDefaults in Cairn-DB and avoids surprise
-- data loss if a default schema gets revised mid-flight.
--
-- Mutates `target` in place; also returns it for chaining.
function Table.MergeDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return target
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            Table.MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end


return Table
