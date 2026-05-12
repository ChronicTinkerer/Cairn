-- Cairn-Util
-- The collection's small-utilities lib. All helpers live in this file,
-- organized into sub-namespaces.
--
-- Consumer view:
--
--   local CU = LibStub("Cairn-Util-1.0")
--   CU.Hash.MD5("hello")             --> 32-char hex digest
--   CU.String.TitleCase("o'connor")  --> "O'Connor"
--   CU.Table.DeepCopy(myTable)
--   CU.Pcall.Call(ctx, fn, args)
--   ...
--
-- Sub-namespaces today:
--   Pcall   error-isolated function dispatch
--   Table   Snapshot, MergeDefaults, DeepCopy
--   String  TitleCase, NormalizeWhitespace, ParseVersion, NormalizeVersion
--   Path    Get, Set (dot-separated nested-table access)
--   Numbers FormatWithCommas, FormatWithCommasToThousands (K/M)
--   Queue   FIFO with shrink-on-pop
--   ObjectPool wraps CreateObjectPool with owner-keyed batch release
--   Bitfield named-flag-bit primitive for sparse state tracking
--   Array   22 functional helpers (Map / Filter / Reduce / etc.)
--   Frame   NormalizeSetPointArgs (and future Frame helpers)
--   Texture AnimateSpriteSheet (sprite-sheet UV animation wrapper)
--   Hash    MD5 (via vendored AF_MD5), FNV1a32, Combine
--
-- Plus the top-level functions:
--   Cairn_Util.Memoize(fn, cache?)              tree-cache memoization
--   Cairn_Util.ResolveProviderMethod(...)       string -> bound-closure resolver
--                                               for declarative config tables
--
-- Vendored third-party algorithms (AF_MD5) live in separate files for
-- license attribution and update-path clarity. Cairn-Util-1.0 itself is
-- a single file.
--
-- Depends on Cairn-Core (root `Core.lua`) for the `_G.Cairn` namespace.
-- Any standalone embed of a Cairn lib must include BOTH Core.lua AND
-- Cairn-Util.lua (every other Cairn lib pulls shared helpers from here).
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Util-1.0"
local LIB_MINOR = 31

local Cairn_Util = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Util then return end


-- ============================================================================
-- Pcall
-- ============================================================================
-- Shared pcall wrappers used by other Cairn libs to isolate consumer
-- handler errors. Every dispatch path in Cairn (Events, Hooks, Timer,
-- Callback, Settings, Addon, Slash) was carrying its own near-identical
-- safeCall; this consolidates them.
--
-- Why route through `geterrorhandler` instead of letting pcall swallow:
-- BugGrabber / BugSack hook geterrorhandler to capture the trace, and
-- users have come to expect "errors I cause show up in BugSack". A raw
-- pcall would drop the error on the floor. We also do NOT use error()
-- to re-raise after catching, because re-raising inside a dispatch
-- loop kills the rest of the subscribers; routing through
-- geterrorhandler reports the failure without affecting siblings.

Cairn_Util.Pcall = Cairn_Util.Pcall or {}


-- Pcall.Call(context, fn, ...) -> (ok, ...)
--
-- pcall(fn, ...) with errorhandler-routed failure reporting. Returns
-- whatever pcall returns: (true, fn-returns...) or (false, err).
-- Callers usually ignore the return value; the geterrorhandler side
-- effect is the point. The return is exposed for the rare callsite
-- that wants to branch on success (e.g. timer cancellation on handler
-- error).
--
-- `context` is the whole prefix that ends up in the error report (no
-- built-in lib name). Each call site formats it however it wants so we
-- don't have to commit to a uniform shape across libs.
--
-- nil fn is treated as no-op success (true). Lets dispatch loops pass
-- through entries whose handler was nil'd out concurrently without
-- crashing — mirrors what the per-lib safeCall functions did.
function Cairn_Util.Pcall.Call(context, fn, ...)
    if type(fn) ~= "function" then
        return true
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        geterrorhandler()(("%s threw: %s"):format(
            tostring(context or "<unknown>"), tostring(err)))
    end
    return ok, err
end


-- ============================================================================
-- Table
-- ============================================================================
-- Small table helpers. NOT lodash; just the duplicated copies pulled
-- out of Events / Callback / Timer / DB and given one home.

Cairn_Util.Table = Cairn_Util.Table or {}


-- Table.Snapshot(arr) -> { copy }
--
-- Shallow copy of an array-shaped table. Used before iterating a list
-- whose entries may unsubscribe or otherwise mutate the source during
-- dispatch (a handler that calls Unsubscribe on itself, a timer
-- callback that schedules another timer that lands in the same bucket,
-- etc).
--
-- We freeze the indices we're going to walk so mutation of `arr`
-- during the loop can't shift entries underneath us, skip an entry, or
-- visit the same entry twice. Callers still have to check whether each
-- snapshot entry is still "live" (handler != nil, cancelled flag not
-- set, etc.) since the snapshot can go stale; the snapshot prevents
-- structural corruption, not logical staleness.
--
-- Returns a new table even when arr is nil/empty (so the caller can do
-- an unconditional `for i = 1, #snap do ... end`).
function Cairn_Util.Table.Snapshot(arr)
    local out = {}
    if type(arr) ~= "table" then return out end
    local n = #arr
    for i = 1, n do
        out[i] = arr[i]
    end
    return out
end


-- Table.MergeDefaults(target, defaults) -> target
--
-- Recursive deep merge: copy values from `defaults` into `target` only
-- where `target` is missing them. Tables are recursed into; leaf
-- values (including `false` and `0`) are preserved if the caller
-- already set them.
--
-- Used primarily by Cairn-DB.New() to layer defaults onto a fresh
-- SavedVariables table without clobbering user data on relog. Safe to
-- call repeatedly: idempotent on a fully-defaulted target.
--
-- Edge case: if `target[k]` is a non-table value and `defaults[k]` is
-- a table, we DO NOT overwrite. The user's scalar wins. This matches
-- the behavior of the original mergeDefaults in Cairn-DB and avoids
-- surprise data loss if a default schema gets revised mid-flight.
--
-- Mutates `target` in place; also returns it for chaining.
function Cairn_Util.Table.MergeDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return target
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            -- WHY the three-way branch: a default-side table only gets
            -- recursed into when the target either has no value yet (we
            -- create an empty subtable to merge into) or already has a
            -- table-shaped value. If the target has a non-nil scalar at
            -- this key, the user's scalar wins -- preserving user data
            -- under a schema change beats silently clobbering it with a
            -- defaults-shaped subtable, which is the documented intent
            -- of this function.
            if target[k] == nil then
                target[k] = {}
                Cairn_Util.Table.MergeDefaults(target[k], v)
            elseif type(target[k]) == "table" then
                Cairn_Util.Table.MergeDefaults(target[k], v)
            end
            -- target[k] is a non-nil scalar: preserve, do not recurse.
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end


-- Table.DeepCopy(t, memo?) -> copy
--
-- Recursive table copy. Each visited table is recorded in `memo` so
-- cycles terminate cleanly: `t.self = t` produces a copy where
-- `copy.self = copy` rather than infinite-looping.
--
-- Metatables are preserved by SHARING the reference (not by deep-
-- copying the metatable itself). Most metatables are class
-- definitions: shared, immutable, single-instance. Preserving the
-- reference means the copy still behaves like an instance of the same
-- class. Consumers who want a detached copy call
-- `setmetatable(copy, nil)` after — that's a different use case, not
-- a workaround.
--
-- Functions, userdata, and tables-as-keys are passed by reference.
-- Deep-copying keys was rejected as a vanishingly rare use case with
-- significant memo-logic complexity cost.
--
-- Non-table input is returned unchanged so consumers can call DeepCopy
-- on values of mixed types without pre-checking.
--
-- `memo` is internal; consumers call `Table.DeepCopy(t)` with no
-- second arg. The internal recursion threads memo through to handle
-- cycles.
function Cairn_Util.Table.DeepCopy(t, memo)
    if type(t) ~= "table" then return t end
    memo = memo or {}
    if memo[t] then return memo[t] end
    local ret = {}
    memo[t] = ret
    for k, v in pairs(t) do
        ret[k] = type(v) == "table" and Cairn_Util.Table.DeepCopy(v, memo) or v
    end
    setmetatable(ret, getmetatable(t))
    return ret
end


-- ============================================================================
-- String
-- ============================================================================

Cairn_Util.String = Cairn_Util.String or {}


-- String.TitleCase(s) -> string
--
-- Title-case each contiguous letter-run independently. Word-boundary
-- characters (apostrophes, hyphens, spaces, digits, punctuation) break
-- runs naturally, so multi-component names round-trip cleanly:
--
--   "o'connor"   -> "O'Connor"
--   "jean-luc"   -> "Jean-Luc"
--   "de la cruz" -> "De La Cruz"
--   "a"          -> "A"
--
-- The idiomatic `(%a)(%a+)` pattern was rejected because it requires
-- at least two consecutive letters; single-letter words at word
-- boundaries would stay lowercase ("o'connor" -> "o'Connor"). Pushing
-- that fix to consumers would violate Cairn's
-- simplicity-applies-to-consumer pillar.
--
-- Idempotent: TitleCase(TitleCase(s)) == TitleCase(s).
--
-- Non-string input raises a Lua type error on the gsub call.
function Cairn_Util.String.TitleCase(s)
    return (s:gsub("(%a+)", function(word)
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end))
end


-- String.NormalizeWhitespace(s) -> string
--
-- Strip CR/LF, trim leading/trailing whitespace, collapse internal
-- whitespace runs to a single space. Built for TOC-metadata reads
-- where consumer-authoring text editors slip hidden newlines into
-- Notes / Description / Author fields.
--
-- Order of operations matters:
--   1. Strip CR/LF first so embedded newlines become "" (not " "),
--      which means "first\r\nsecond" -> "firstsecond" rather than
--      "first second".
--   2. Trim edges so a leading newline doesn't leave a residual space
--      after step 1 runs.
--   3. Collapse internal runs to a single space.
function Cairn_Util.String.NormalizeWhitespace(s)
    return (s
        :gsub("[\r\n]", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("%s+", " "))
end


-- String.ParseVersion(s) -> integer or nil
--
-- Extract the first integer found in a version-shaped value. Accepts both
-- strings and numbers (`tostring` is applied so callers don't have to
-- pre-coerce). Returns nil when no digit run is found; callers choose the
-- fallback (typically 0 or 1).
--
--   ParseVersion("2.4.1")    -->  2
--   ParseVersion("v3-beta")  -->  3
--   ParseVersion(2)          -->  2
--   ParseVersion("none")     -->  nil
--
-- Intended for the narrow case where a Cairn-internal lib writes
-- `## Version: 2.2` in its TOC and wants to reuse the same string as its
-- LibStub MINOR. Cairn's collection-wide convention is that per-lib
-- LIB_MINORs evolve INDEPENDENTLY of per-addon TOC Version (see memory
-- `cairn_lib_minor_convention`); this helper exists for the rare
-- one-source-of-truth case, NOT as a mandate to couple them.
function Cairn_Util.String.ParseVersion(s)
    if s == nil then return nil end
    return tonumber(string.match(tostring(s), "%d+"))
end


-- String.NormalizeVersion(s) -> string
--
-- Display-friendly version-string normalization. Handles three input shapes:
--
--   1. Clean version strings pass through unchanged.
--          "2.4.1" -> "2.4.1"
--
--   2. BigWigs packager unsubstituted placeholders -> "Developer Build".
--          "@project-revision@" -> "Developer Build"
--      The load-bearing rule: `version:gsub("@.+", "Developer Build")`.
--      Cairn ships via BigWigs packager (memory `cairn_distribution`); dev
--      checkouts that haven't been tagged yet contain raw placeholders.
--
--   3. SVN keyword expansion: `$Revision: 123 $` -> "123".
--      Mostly legacy; costs nothing to handle and lets the same code work
--      for occasional SVN-hosted dependencies.
--
-- nil / empty input returns "Unknown" so consumer code can safely chain
-- this into UI without nil-guarding.
--
-- Used by `Cairn.Register`'s metadata extraction before assigning
-- `Settings.Version`. Reference: LibAboutPanel-2.0 (inspected 2026-05-11).
function Cairn_Util.String.NormalizeVersion(s)
    if s == nil or s == "" then return "Unknown" end
    s = tostring(s)

    -- SVN keyword first: "$Revision: 123 $" -> "123".
    -- Pattern is anchored on the literal "$" delimiters so a stray "$" in
    -- a normal version string won't trigger spurious replacement.
    local svn = s:match("^%$Revision:%s*(%d+)%s*%$$")
    if svn then return svn end

    -- BigWigs unsubstituted placeholder: any "@...@" run.
    -- We replace the entire string (not just the placeholder) because
    -- a partially-substituted version like "1.0-@project-revision@" is
    -- meaningless and reading "Developer Build" is more useful.
    if s:find("@", 1, true) then
        return "Developer Build"
    end

    return s
end


-- ============================================================================
-- Path
-- ============================================================================

Cairn_Util.Path = Cairn_Util.Path or {}


-- Path.Get(tbl, path) -> value or nil
--
-- Walk a dot-separated string path through nested tables. Returns the
-- terminal value, or nil if any intermediate is missing or non-table.
--
--   Path.Get(t, "window.position.x")
--
-- Safe against missing intermediates: walks as deep as it can, returns
-- nil for the rest. Equivalent to
-- `t and t.window and t.window.position and t.window.position.x` but
-- without the long conjunction.
function Cairn_Util.Path.Get(tbl, path)
    for key in path:gmatch("[^.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[key]
    end
    return tbl
end


-- Path.Set(tbl, path, value) -> tbl
--
-- Walk a dot-separated string path, creating intermediate tables as
-- needed, and set the terminal key to `value`.
--
--   Path.Set(db, "window.position.x", 100)
--   -- equivalent to:
--   --   db.window = db.window or {}
--   --   db.window.position = db.window.position or {}
--   --   db.window.position.x = 100
--
-- Non-table collisions raise an error rather than silently overwriting:
--   Path.Set({a=5}, "a.b", 10)  -- ERRORS; won't replace `a=5` with
--                               --   `a={b=10}`.
-- Loud failure beats silent data loss.
--
-- Dot is the only separator. Keys containing literal dots aren't
-- supported (documented limitation; consumers don't use them in Cairn-
-- Settings SV paths, the named consumer).
--
-- Mutates `tbl` in place; also returns it for chaining.
function Cairn_Util.Path.Set(tbl, path, value)
    local keys = {}
    for key in path:gmatch("[^.]+") do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        error("Cairn-Util.Path.Set: empty path", 2)
    end
    local cursor = tbl
    for i = 1, #keys - 1 do
        local key = keys[i]
        if cursor[key] == nil then
            cursor[key] = {}
        elseif type(cursor[key]) ~= "table" then
            error(("Cairn-Util.Path.Set: cannot descend through non-table at '%s'"):format(
                table.concat(keys, ".", 1, i)), 2)
        end
        cursor = cursor[key]
    end
    cursor[keys[#keys]] = value
    return tbl
end


-- ============================================================================
-- Numbers
-- ============================================================================

Cairn_Util.Numbers = Cairn_Util.Numbers or {}


-- Numbers.FormatWithCommas(num) -> string
--
-- Insert thousands separators into a number's string representation.
-- Operates on `tostring(num)`, so fractional parts pass through
-- untouched:
--
--   FormatWithCommas(1234567)        -> "1,234,567"
--   FormatWithCommas(1234567.89)     -> "1,234,567.89"
--   FormatWithCommas(-1234567)       -> "-1,234,567"
--
-- The anchored gsub `^(-?%d+)(%d%d%d)` is iterated to fixed point:
-- each pass inserts one comma three digits from the right end of the
-- leading integer run. The loop terminates when the integer run has
-- fewer than four digits remaining (the pattern stops matching).
function Cairn_Util.Numbers.FormatWithCommas(num)
    local s = tostring(num)
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return s
end


-- Numbers.FormatWithCommasToThousands(num) -> string
--
-- Compact human-readable display of large numbers with K / M unit
-- suffixes:
--
--   FormatWithCommasToThousands(999)            -> "999"
--   FormatWithCommasToThousands(12500)          -> "12.50K"
--   FormatWithCommasToThousands(1234567)        -> "1.23M"
--   FormatWithCommasToThousands(1500000000)     -> "1,500.00M"
--   FormatWithCommasToThousands(-1500000)       -> "-1.50M"
--
-- Branches on `math.abs(num)` so negatives format correctly. Values
-- >= 1B render as `"<int>.00M"` with commas in the integer part —
-- there's no B/T variant in v1 (add when a named consumer asks).
--
-- Known quirk: values just under 1M (like 999999) format as
-- `"1000.00K"` because `%.2f` rounds 999.999 up to 1000.00. Technically
-- correct (1000K = 1M) but cosmetically odd. Sub-pixel issue; document
-- but don't engineer around.
function Cairn_Util.Numbers.FormatWithCommasToThousands(num)
    local abs = math.abs(num)
    if abs < 1000 then
        return tostring(num)
    elseif abs < 1000000 then
        return string.format("%.2fK", num / 1000)
    else
        local s = string.format("%.2f", num / 1000000)
        local intPart, fracPart = s:match("^(-?%d+)(%.%d+)$")
        if intPart then
            intPart = Cairn_Util.Numbers.FormatWithCommas(tonumber(intPart))
            return intPart .. fracPart .. "M"
        end
        return s .. "M"
    end
end


-- ============================================================================
-- Memoize
-- ============================================================================
-- Top-level function (not a sub-namespace), per the API shape locked in
-- OBJECTIVES.md: consumer calls `Cairn.Util.Memoize(fn)` directly.

-- Sentinel keys. NIL_KEY substitutes for nil args (Lua tables can't
-- have nil keys). CACHED_RESULT is a unique-table subkey so the
-- cached return packet can't collide with any user-supplied argument.
local NIL_KEY = {}
local CACHED_RESULT = {}

-- Pack ... into a table with `.n` count, preserving embedded nils.
-- Equivalent to Lua 5.2's `table.pack`; backfilled for the 5.1 the
-- WoW client runs.
local function pack(...)
    return { n = select("#", ...), ... }
end


-- Cairn_Util.Memoize(fn, cache?) -> closure
--
-- Tree-cache memoization for arbitrary-arity functions. Returns a
-- closure wrapping `fn`; the closure walks a tree of cache nodes
-- keyed by each argument in sequence (handles arbitrary arity
-- without flat-key serialization).
--
-- Optional `cache` lets consumers manage lifetime themselves, e.g.
-- a weak-keyed table for GC-friendly storage:
--
--   local cache = setmetatable({}, { __mode = "v" })
--   local memoized = Cairn.Util.Memoize(expensiveFn, cache)
--
-- Callable tables (tables with a `__call` metamethod) are accepted as
-- `fn`.
--
-- Caveats:
--   * Table-typed args compared by REFERENCE, not value.
--     `memoized({}, {})` with two NEW empty tables misses;
--     `memoized(t, t)` with the same `t` reference hits.
--   * Cache grows unbounded — no LRU eviction. Consumers needing
--     bounded caches pass their own cache table and lifecycle it.
--   * Multiple return values are preserved (count-tracked via `n`),
--     including embedded nils.
function Cairn_Util.Memoize(fn, cache)
    cache = cache or {}

    local fnType = type(fn)
    local callable = fnType == "function"
    if not callable and fnType == "table" then
        local mt = getmetatable(fn)
        callable = mt and type(mt.__call) == "function"
    end
    if not callable then
        error("Cairn-Util.Memoize: fn must be a function or callable table", 2)
    end

    return function(...)
        local node = cache
        local nargs = select("#", ...)
        for i = 1, nargs do
            local arg = select(i, ...)
            local key = (arg == nil) and NIL_KEY or arg
            local child = node[key]
            if child == nil then
                child = {}
                node[key] = child
            end
            node = child
        end
        local cached = node[CACHED_RESULT]
        if cached == nil then
            cached = pack(fn(...))
            node[CACHED_RESULT] = cached
        end
        return unpack(cached, 1, cached.n)
    end
end


-- ============================================================================
-- ResolveProviderMethod
-- ============================================================================
-- Top-level helper for declarative config tables that reference handler
-- methods by string name rather than by direct function reference.
--
-- Usage:
--   Cairn.Register("MyAddon", Addon, {
--     minimap = {
--       provider = "TooltipProvider",
--       onClick  = "OnIconClick",
--     },
--   })
--
--   -- Cairn-Addon internally:
--   local handler = Cairn.Util.ResolveProviderMethod(
--       Addon, "TooltipProvider", "OnIconClick")
--   handler(button, "LeftButton")
--   -- equivalent to: Addon.TooltipProvider:OnIconClick(button, "LeftButton")
--
-- Why string-based: declarative config tables can be defined in any file
-- load order. A direct function reference forces the function to exist
-- BEFORE the config is built. String lookup defers the binding to use
-- time, when all files have loaded.
--
-- Returns a self-bound closure: `fn(...)` is equivalent to
-- `addon[providerField]:method(...)`. The provider table is captured by
-- closure, so if the consumer reassigns `addon.TooltipProvider` later
-- the original closure still calls the original provider — matches "the
-- binding was the answer at resolve time."
--
-- Loud errors on miss (typo protection): if the provider field or the
-- method name doesn't resolve, raises with a clear message.

function Cairn_Util.ResolveProviderMethod(addon, providerField, methodName)
    if type(addon) ~= "table" then
        error("Cairn-Util.ResolveProviderMethod: addon must be a table", 2)
    end
    if type(providerField) ~= "string" or providerField == "" then
        error("Cairn-Util.ResolveProviderMethod: providerField must be a non-empty string", 2)
    end
    if type(methodName) ~= "string" or methodName == "" then
        error("Cairn-Util.ResolveProviderMethod: methodName must be a non-empty string", 2)
    end

    local provider = addon[providerField]
    if type(provider) ~= "table" then
        error(("Cairn-Util.ResolveProviderMethod: addon.%s is not a table (got %s)")
            :format(providerField, type(provider)), 2)
    end

    local method = provider[methodName]
    if type(method) ~= "function" then
        error(("Cairn-Util.ResolveProviderMethod: addon.%s.%s is not a function (got %s)")
            :format(providerField, methodName, type(method)), 2)
    end

    return function(...) return method(provider, ...) end
end


-- ============================================================================
-- Queue
-- ============================================================================

Cairn_Util.Queue = Cairn_Util.Queue or {}
local Queue = Cairn_Util.Queue
Queue.__index = Queue


-- Threshold for re-indexing the underlying array. When `head` advances
-- past this position AND it's past the midpoint of the consumed range,
-- we shrink the array back to start at index 1. Tuned for "push some,
-- pop some, repeat" patterns common in producer/consumer queues; pure
-- push-only or pure pop-only paths never trigger.
local SHRINK_HEAD_THRESHOLD = 1000


-- Queue:New() -> queue
--
-- Construct an empty FIFO queue. Internally an `items` array plus
-- `head` / `tail` integer indices: Push increments tail, Pop
-- increments head. Periodic re-indexing (see Pop) keeps the array
-- from growing unboundedly under push-then-pop sequences.
function Queue:New()
    return setmetatable({ items = {}, head = 1, tail = 0 }, Queue)
end


-- Queue:Push(item) -> nil
--
-- Append `item` to the tail of the queue.
function Queue:Push(item)
    self.tail = self.tail + 1
    self.items[self.tail] = item
end


-- Queue:Pop() -> item or nil
--
-- Remove and return the head item. Returns nil if the queue is empty.
--
-- Triggers a re-index of the underlying array when `head` has advanced
-- past SHRINK_HEAD_THRESHOLD AND the consumed prefix exceeds half the
-- tail position. This collapses long-running queues back to start at
-- index 1 so we don't leak memory in producer/consumer patterns.
function Queue:Pop()
    if self.head > self.tail then return nil end
    local item = self.items[self.head]
    self.items[self.head] = nil
    self.head = self.head + 1
    if self.head > SHRINK_HEAD_THRESHOLD and self.head > self.tail / 2 then
        local n = 0
        for i = self.head, self.tail do
            n = n + 1
            self.items[n] = self.items[i]
            if i ~= n then self.items[i] = nil end
        end
        self.head = 1
        self.tail = n
    end
    return item
end


-- Queue:Peek() -> item or nil
--
-- Return the head item without removing it. nil if the queue is empty.
function Queue:Peek()
    return self.items[self.head]
end


-- Queue:Size() -> count
--
-- Number of items currently in the queue. Computed from head/tail
-- rather than walking; O(1).
function Queue:Size()
    return self.tail - self.head + 1
end


-- Queue:IsEmpty() -> bool
function Queue:IsEmpty()
    return self.head > self.tail
end


-- ============================================================================
-- ObjectPool
-- ============================================================================

Cairn_Util.ObjectPool = Cairn_Util.ObjectPool or {}
local ObjectPool = Cairn_Util.ObjectPool
ObjectPool.__index = ObjectPool


-- ObjectPool:New(creationFn, resetFn) -> pool
--
-- Wrap Blizzard's CreateObjectPool with Cairn-idiomatic owner tracking.
-- The underlying Blizzard pool handles acquire/release/active-set
-- bookkeeping; we layer owner-keyed batch release on top so consumers
-- can group acquisitions by parent or scope and release them all at
-- once (matching the pattern in Cairn-Timer's CancelOwner, Cairn-Events'
-- UnsubscribeOwner, Cairn-Hooks' UnhookOwner).
--
-- Callback conventions (Cairn-style, NOT Blizzard-style):
--
--   creationFn: function() return obj end
--               Called on cache miss; returns a fresh object. No args.
--               (Blizzard passes the underlying pool as arg 1, which is
--               an implementation detail consumers shouldn't have to
--               know about. If you actually need the Cairn pool inside
--               creationFn, capture it via upvalue from outside.)
--
--   resetFn:    function(obj) end
--               Called on Release; receives the object and returns it
--               to a clean state (Hide, ClearAllPoints, etc.). Fires
--               exactly once per Release. NOT called on Acquire-of-new.
--
-- The Cairn shim does NOT register resetFn with the underlying Blizzard
-- pool. Instead it holds the reset callback itself and fires it from
-- this lib's own :Release. Rationale: Blizzard's `disallowResetIfNew`
-- flag was observed not to take effect on current retail (verified via
-- the in-game smoke), so the pool would otherwise reset on Acquire-of-
-- new too. Owning the reset path also gives us deterministic ordering
-- (reset before return-to-inactive-pool, every time).
function ObjectPool:New(creationFn, resetFn)
    -- Wrap creationFn so the Blizzard pool's (pool) signature never
    -- reaches the consumer. Don't pass resetFn to Blizzard at all --
    -- we fire it ourselves from :Release.
    local wrappedCreate = function() return creationFn() end
    local blz = CreateObjectPool(wrappedCreate, nil)

    local pool = setmetatable({}, ObjectPool)
    pool._pool    = blz
    pool._resetFn = resetFn
    -- _ownerMap[owner][obj] = true for batch release tracking. Lazy:
    -- only owners passed to AcquireFor get a sub-table.
    pool._ownerMap = {}
    -- _objOwners[obj] = owner — reverse lookup so Release can clean up
    -- the ownerMap entry in O(1) without scanning every owner bucket.
    pool._objOwners = {}
    return pool
end


-- ObjectPool:Acquire() -> (obj, isNew)
--
-- Untagged acquisition. `isNew` is true on cache miss (creationFn just
-- ran), false on cache hit (reused object).
function ObjectPool:Acquire()
    return self._pool:Acquire()
end


-- ObjectPool:AcquireFor(owner) -> (obj, isNew)
--
-- Acquire and tag the acquisition with `owner` for batch release later
-- via :ReleaseOwner(owner). The owner can be any table or string —
-- consumer's choice (typically a parent frame, route handle, etc.).
function ObjectPool:AcquireFor(owner)
    local obj, isNew = self._pool:Acquire()
    local bucket = self._ownerMap[owner]
    if not bucket then
        bucket = {}
        self._ownerMap[owner] = bucket
    end
    bucket[obj] = true
    self._objOwners[obj] = owner
    return obj, isNew
end


-- ObjectPool:Release(obj) -> nil
--
-- Return an object to the pool. Fires resetFn(obj) first, then clears
-- any owner-tag, then hands the object back to the Blizzard pool.
-- Order matters: resetFn runs BEFORE the obj returns to inactive so
-- consumers can rely on "by the time my pool reuses this, reset has
-- completed."
function ObjectPool:Release(obj)
    if self._resetFn then self._resetFn(obj) end

    local owner = self._objOwners[obj]
    if owner then
        local bucket = self._ownerMap[owner]
        if bucket then
            bucket[obj] = nil
            if not next(bucket) then
                self._ownerMap[owner] = nil
            end
        end
        self._objOwners[obj] = nil
    end
    self._pool:Release(obj)
end


-- ObjectPool:ReleaseOwner(owner) -> nil
--
-- Release every object tagged with `owner`. No-op if no objects are
-- tagged with that owner. Snapshots the bucket first because Release
-- mutates _ownerMap during iteration.
function ObjectPool:ReleaseOwner(owner)
    local bucket = self._ownerMap[owner]
    if not bucket then return end
    local objs, n = {}, 0
    for obj in pairs(bucket) do
        n = n + 1
        objs[n] = obj
    end
    for i = 1, n do
        self:Release(objs[i])
    end
end


-- ObjectPool:ReleaseAll() -> nil
--
-- Release every active object back to the pool and clear all owner-
-- tags en masse. Goes through our own :Release for each active object
-- so resetFn fires consistently with single-object Release. Snapshot
-- the active set first because :Release mutates the Blizzard pool's
-- active iterator out from under us.
function ObjectPool:ReleaseAll()
    local snapshot, n = {}, 0
    for obj in self._pool:EnumerateActive() do
        n = n + 1
        snapshot[n] = obj
    end
    for i = 1, n do
        self:Release(snapshot[i])
    end
    -- Defensive: in case Release for some reason didn't clear an entry,
    -- wipe the owner tables. Should be empty already.
    for owner in pairs(self._ownerMap) do self._ownerMap[owner] = nil end
    for obj in pairs(self._objOwners) do self._objOwners[obj] = nil end
end


-- ObjectPool:EnumerateActive() -> iterator
--
-- Pass-through to Blizzard's pool iterator over active objects.
function ObjectPool:EnumerateActive()
    return self._pool:EnumerateActive()
end


-- ============================================================================
-- Bitfield
-- ============================================================================
-- Named-flag-bit primitive for sparse entity-state tracking. One
-- Bitfield instance per consumer-defined flag set; the instance
-- stores the bit-to-name mapping and operates on consumer-provided
-- entities (any table) by reading/writing a single field on them.
--
-- Storage on entity[self.field] is a Lua number (or array of numbers
-- when the flag set exceeds 32 flags). When all flags are off, the
-- field is unset (nil) rather than left as 0 — keeps entities with no
-- state sparse in SavedVariables.
--
-- Bit-to-name mapping is by array position in `flags = { ... }`.
-- Consumers MUST treat the array as APPEND-ONLY across releases:
-- reordering or inserting in the middle reassigns bits and breaks any
-- persisted state. Add new flags at the end.

Cairn_Util.Bitfield = Cairn_Util.Bitfield or {}
local Bitfield = Cairn_Util.Bitfield
Bitfield.__index = Bitfield


-- Bitfield:New(opts) -> bitfield
--
-- opts = {
--     flags = { "KNOWN", "CAN_USE", ... },  -- ORDERED, APPEND-ONLY
--     field = "states",                     -- key on entity tables
-- }
--
-- field defaults to "_bitfield". Storage on entity[field] is a Lua
-- number for <= 32 flags; auto-promotes to a sparse word-array
-- ({ word1, word2, ... }) when the flag count exceeds 32.
function Bitfield:New(opts)
    if type(opts) ~= "table" or type(opts.flags) ~= "table" then
        error("Cairn-Util.Bitfield:New: opts.flags must be an array of flag names", 2)
    end
    local bf = setmetatable({}, Bitfield)
    bf.field = opts.field or "_bitfield"
    bf.numFlags = #opts.flags
    bf.multiword = bf.numFlags > 32
    bf.numWords = math.ceil(bf.numFlags / 32)
    bf.lookup = {}
    for i, name in ipairs(opts.flags) do
        if bf.multiword then
            bf.lookup[name] = {
                word = math.floor((i - 1) / 32) + 1,
                mask = 2 ^ ((i - 1) % 32),
            }
        else
            bf.lookup[name] = 2 ^ (i - 1)
        end
    end
    return bf
end


-- Bitfield:Has(entity, name) -> bool
--
-- Unknown `name` errors loudly (typo protection). Consumers probing
-- for flag existence should query `self.lookup` directly or wrap in
-- pcall.
function Bitfield:Has(entity, name)
    local mask = self.lookup[name]
    if not mask then
        error("Cairn-Util.Bitfield:Has: unknown flag '" .. tostring(name) .. "'", 2)
    end
    local v = entity[self.field]
    if not v then return false end
    if self.multiword then
        return bit.band(v[mask.word] or 0, mask.mask) ~= 0
    else
        return bit.band(v, mask) ~= 0
    end
end


-- Bitfield:Add(entity, name) -> nil
--
-- Sets the named flag on the entity. Auto-creates the storage field
-- on first set. Modulo 2^32 keeps stored values in the unsigned
-- range (WoW's bit library can return signed representations of the
-- same bit pattern; normalizing to unsigned makes SV inspection less
-- surprising).
function Bitfield:Add(entity, name)
    local mask = self.lookup[name]
    if not mask then
        error("Cairn-Util.Bitfield:Add: unknown flag '" .. tostring(name) .. "'", 2)
    end
    if self.multiword then
        local v = entity[self.field] or {}
        v[mask.word] = bit.bor(v[mask.word] or 0, mask.mask) % 4294967296
        entity[self.field] = v
    else
        entity[self.field] = bit.bor(entity[self.field] or 0, mask) % 4294967296
    end
end


-- Bitfield:Remove(entity, name) -> nil
--
-- Clears the named flag. When ALL flags are off after the remove,
-- the storage field is unset (entity[field] = nil) so empty entities
-- stay sparse in SavedVariables. Multi-word entities are checked
-- across all populated words.
function Bitfield:Remove(entity, name)
    local mask = self.lookup[name]
    if not mask then
        error("Cairn-Util.Bitfield:Remove: unknown flag '" .. tostring(name) .. "'", 2)
    end
    local v = entity[self.field]
    if not v then return end
    if self.multiword then
        if not v[mask.word] then return end
        v[mask.word] = bit.band(v[mask.word], bit.bnot(mask.mask)) % 4294967296
        local empty = true
        for i = 1, self.numWords do
            if v[i] and v[i] ~= 0 then empty = false; break end
        end
        if empty then entity[self.field] = nil end
    else
        local result = bit.band(v, bit.bnot(mask)) % 4294967296
        if result == 0 then
            entity[self.field] = nil
        else
            entity[self.field] = result
        end
    end
end


-- Bitfield:IsEmpty(entity) -> bool
--
-- True when the entity has no flags set (storage field is nil).
function Bitfield:IsEmpty(entity)
    return entity[self.field] == nil
end


-- ============================================================================
-- Array
-- ============================================================================
-- Stateless module functions for array iteration, search, counting,
-- extremes, taking, and shallow comparison. Functional-style: most
-- functions return NEW arrays; `Remove` is the sole in-place mutator
-- and is documented loudly. Iteration walks left-to-right using `#t`,
-- so sparse arrays past the first gap aren't fully traversed — use
-- `Array.Length(t)` to count gap-safely.
--
-- Five locked sanjo-style design rules (per OBJECTIVES.md):
--   (1) Length is gap-safe; Size is `#t` fast path; IsDense compares.
--   (2) Strict `==` default. IndexOfApprox is separate for fuzzy
--       floats.
--   (3) Max / MaxBy / MaxWith match lodash naming. No universal
--       extreme primitive.
--   (4) PickWhile takes `(current)`, matching JS/lodash takeWhile.
--   (5) Functional-only — no fluent metatable chain. Consumers who
--       want chaining wrap once themselves.

Cairn_Util.Array = Cairn_Util.Array or {}
local Array = Cairn_Util.Array


-- ----- Iteration ------------------------------------------------------------

-- Array.Map(t, fn) -> new array
-- Apply fn to each element; returns a NEW array of results.
function Array.Map(t, fn)
    local out = {}
    for i = 1, #t do
        out[i] = fn(t[i])
    end
    return out
end


-- Array.Filter(t, predicate) -> new array
-- Returns a NEW array of elements where predicate(element) is truthy.
function Array.Filter(t, predicate)
    local out, n = {}, 0
    for i = 1, #t do
        if predicate(t[i]) then
            n = n + 1
            out[n] = t[i]
        end
    end
    return out
end


-- Array.Find(t, predicate) -> element or nil
-- First element where predicate returns truthy. nil if none match.
function Array.Find(t, predicate)
    for i = 1, #t do
        if predicate(t[i]) then return t[i] end
    end
    return nil
end


-- Array.ForEach(t, fn) -> nil
-- Side-effect iteration. No return.
function Array.ForEach(t, fn)
    for i = 1, #t do
        fn(t[i])
    end
end


-- Array.Reduce(t, fn, initial) -> acc
-- Left fold. `initial` is REQUIRED (no "use first element" overload —
-- forces the consumer to be explicit and avoids the empty-array
-- foot-gun).
function Array.Reduce(t, fn, initial)
    local acc = initial
    for i = 1, #t do
        acc = fn(acc, t[i])
    end
    return acc
end


-- ----- Search ---------------------------------------------------------------

-- Array.IndexOf(t, value) -> index or nil
-- Strict `==` comparison. For floats with rounding error, use
-- IndexOfApprox.
function Array.IndexOf(t, value)
    for i = 1, #t do
        if t[i] == value then return i end
    end
    return nil
end


-- Array.IndexOfApprox(t, value, epsilon?) -> index or nil
-- Numeric fuzzy match for floats. Non-number elements are skipped.
-- `epsilon` defaults to 1e-9.
function Array.IndexOfApprox(t, value, epsilon)
    epsilon = epsilon or 1e-9
    for i = 1, #t do
        if type(t[i]) == "number" and math.abs(t[i] - value) < epsilon then
            return i
        end
    end
    return nil
end


-- Array.Contains(t, value) -> bool
-- Shorthand for `IndexOf(t, value) ~= nil`.
function Array.Contains(t, value)
    return Array.IndexOf(t, value) ~= nil
end


-- Array.Equals(a, b) -> bool
-- Shallow length + element-wise `==`. Nested tables aren't recursed
-- into; compare by reference. For deep equality consumers wrap or use
-- a dedicated deep-equal helper (not in v1).
function Array.Equals(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end


-- ----- Mutation -------------------------------------------------------------

-- Array.Remove(t, value) -> index or nil
--
-- MUTATES `t`. Removes the FIRST element equal to `value` (strict `==`)
-- via `table.remove`, shifting subsequent elements down. Returns the
-- index that was removed, or nil if no match.
--
-- The only in-place mutator in this sub-namespace; loudly documented
-- so consumers don't accidentally think it returns a new array like
-- Filter / Reverse.
function Array.Remove(t, value)
    for i = 1, #t do
        if t[i] == value then
            table.remove(t, i)
            return i
        end
    end
    return nil
end


-- ----- Counting -------------------------------------------------------------

-- Array.Length(t) -> count
--
-- Gap-safe count of integer-keyed entries (k >= 1, k is an integer).
-- Walks via pairs, so sparse arrays are counted correctly. O(n).
function Array.Length(t)
    local n = 0
    for k in pairs(t) do
        if type(k) == "number" and k >= 1 and k % 1 == 0 then
            n = n + 1
        end
    end
    return n
end


-- Array.Size(t) -> count
-- Fast path via `#t`. Behavior past the first nil-gap is undefined in
-- Lua 5.1; use Length when correctness on sparse arrays matters.
function Array.Size(t)
    return #t
end


-- Array.IsDense(t) -> bool
-- True iff Length and Size agree (no gaps).
function Array.IsDense(t)
    return Array.Length(t) == #t
end


-- ----- Extremes -------------------------------------------------------------

-- Array.Max(t) / Array.Min(t) -> element or nil
-- Direct comparison via `>` / `<`. Empty array returns nil.
function Array.Max(t)
    if #t == 0 then return nil end
    local best = t[1]
    for i = 2, #t do
        if t[i] > best then best = t[i] end
    end
    return best
end

function Array.Min(t)
    if #t == 0 then return nil end
    local best = t[1]
    for i = 2, #t do
        if t[i] < best then best = t[i] end
    end
    return best
end


-- Array.MaxBy / MinBy(t, projectFn) -> element or nil
-- Project each element to a comparable via `projectFn`; the element
-- whose projection is largest/smallest wins. Projection cached per
-- element so projectFn runs exactly once per element. Empty array
-- returns nil.
function Array.MaxBy(t, projectFn)
    if #t == 0 then return nil end
    local best = t[1]
    local bestKey = projectFn(best)
    for i = 2, #t do
        local key = projectFn(t[i])
        if key > bestKey then
            best = t[i]
            bestKey = key
        end
    end
    return best
end

function Array.MinBy(t, projectFn)
    if #t == 0 then return nil end
    local best = t[1]
    local bestKey = projectFn(best)
    for i = 2, #t do
        local key = projectFn(t[i])
        if key < bestKey then
            best = t[i]
            bestKey = key
        end
    end
    return best
end


-- Array.MaxWith / MinWith(t, cmpFn) -> element or nil
--
-- `cmpFn(a, b)` follows Lua's standard "less-than" convention
-- (matches `table.sort`): returns true when `a` should rank BEFORE
-- `b` in ascending order. Under that convention:
--   - MinWith picks the element that ranks first (cmpFn(t[i], best))
--   - MaxWith picks the element that ranks last  (cmpFn(best, t[i]))
function Array.MaxWith(t, cmpFn)
    if #t == 0 then return nil end
    local best = t[1]
    for i = 2, #t do
        if cmpFn(best, t[i]) then best = t[i] end
    end
    return best
end

function Array.MinWith(t, cmpFn)
    if #t == 0 then return nil end
    local best = t[1]
    for i = 2, #t do
        if cmpFn(t[i], best) then best = t[i] end
    end
    return best
end


-- ----- Taking ---------------------------------------------------------------

-- Array.PickWhile(t, predicate) -> new array
-- Take leading elements while predicate(element) is true. Stops at
-- first miss. Predicate takes `(current)`, not `(acc, current)`,
-- matching JS / lodash / Python takeWhile.
function Array.PickWhile(t, predicate)
    local out, n = {}, 0
    for i = 1, #t do
        if predicate(t[i]) then
            n = n + 1
            out[n] = t[i]
        else
            break
        end
    end
    return out
end


-- Array.DropWhile(t, predicate) -> new array
-- Skip leading elements while predicate matches; return everything
-- after the first miss (inclusive).
function Array.DropWhile(t, predicate)
    local out, n = {}, 0
    local dropping = true
    for i = 1, #t do
        if dropping and predicate(t[i]) then
            -- still dropping
        else
            dropping = false
            n = n + 1
            out[n] = t[i]
        end
    end
    return out
end


-- ----- Builder --------------------------------------------------------------

-- Array.Reverse(t) -> new array
-- Returns a NEW array with the elements in reverse order.
function Array.Reverse(t)
    local out, n = {}, #t
    for i = 1, n do
        out[n - i + 1] = t[i]
    end
    return out
end


-- ============================================================================
-- Frame
-- ============================================================================

Cairn_Util.Frame = Cairn_Util.Frame or {}


-- Module-scope hidden helper. Reused across every NormalizeSetPointArgs
-- call; ClearAllPoints + SetPoint + GetPoint is fast enough that
-- there's no win to pooling, and a single allocation per session is
-- fine.
local pointGetter = CreateFrame("Frame")


-- Frame.NormalizeSetPointArgs(...) -> point, relativeTo, relativePoint, offsetX, offsetY
--
-- Variadic SetPoint args in, canonical 5-tuple out. Blizzard's
-- SetPoint accepts 5+ legal call signatures (single-arg, two-arg with
-- offsets, three-arg with relativeTo + relativePoint, four-arg with
-- relativeTo + offsets, full five-arg). Hand-parsing those signatures
-- is bug-prone; here we delegate to Blizzard's own parser via a
-- hidden helper frame, then ask it back via GetPoint(1) which always
-- returns the canonical form.
--
-- Examples:
--   NormalizeSetPointArgs("CENTER")              -> "CENTER", UIParent, "CENTER", 0, 0
--   NormalizeSetPointArgs("TOPLEFT")             -> "TOPLEFT", UIParent, "TOPLEFT", 0, 0
--   NormalizeSetPointArgs("LEFT", parent, 5, 0)  -> "LEFT", parent, "LEFT", 5, 0
--   NormalizeSetPointArgs(frame:GetPoint(1))     -> round-trips a frame's anchor
--
-- Returns ONE anchor (the first). Frames with multi-point anchors
-- call NormalizeSetPointArgs once per anchor.
--
-- `relativeTo` may be returned as nil when the anchor resolves to the
-- default parent. Consumers persisting the result for later replay
-- should handle the nil case (treat as UIParent, or store the
-- relativeTo's name via GetName() and resolve at apply time).
--
-- Bad SetPoint args surface Blizzard's error directly. Not
-- pcall-wrapped: programming-error class, deserves to be loud.
function Cairn_Util.Frame.NormalizeSetPointArgs(...)
    pointGetter:ClearAllPoints()
    pointGetter:SetPoint(...)
    return pointGetter:GetPoint(1)
end


-- ============================================================================
-- Texture
-- ============================================================================

Cairn_Util.Texture = Cairn_Util.Texture or {}


-- Texture.AnimateSpriteSheet(texture, sheetW, sheetH, frameW, frameH, frameCount, elapsed, secondsPerFrame) -> nil
--
-- Animate a texture's UV coordinates to play through a sprite sheet
-- frame-by-frame. Thin wrapper around Blizzard's global
-- `AnimateTexCoords`, exposed here for namespace discoverability —
-- the Blizzard global exists in FrameXML but is non-obvious and
-- undocumented in most addon dev material; consumers naturally look
-- in `Cairn.Util.Texture` for sprite-sheet animation.
--
-- Sprite-sheet layout: the texture file is `sheetW x sheetH` pixels,
-- divided into a grid of `frameW x frameH` cells. `frameCount` is the
-- number of cells actually used (top-left scanned row-major).
--
-- Drive from an OnUpdate handler with an accumulating `elapsed` and a
-- `secondsPerFrame` step:
--
--   local elapsed = 0
--   tex.frame:HookScript("OnUpdate", function(_, dt)
--       elapsed = elapsed + dt
--       Cairn.Util.Texture.AnimateSpriteSheet(
--           tex, 256, 256, 64, 64, 16, elapsed, 0.04
--       )
--   end)
--
-- Different abstraction layer from the deferred `Cairn-Animation` lib
-- (frame-by-frame UV coords vs declarative timeline); does not
-- migrate when Cairn-Animation unlocks.
function Cairn_Util.Texture.AnimateSpriteSheet(texture, sheetW, sheetH, frameW, frameH, frameCount, elapsed, secondsPerFrame)
    AnimateTexCoords(texture, sheetW, sheetH, frameW, frameH, frameCount, elapsed, secondsPerFrame)
end


-- ============================================================================
-- Hash
-- ============================================================================
-- MD5 (via vendored AF_MD5) + 32-bit FNV-1a + XOR-combine. SHA and
-- other digests get added here as consumers materialize.
--
-- MD5 implementation is vendored AF_MD5 (kikito md5.lua + enderneko's
-- WoW compatibility tweaks, MIT licensed — see AF_MD5.lua for the
-- full attribution). FNV-1a is pure-Lua here.

Cairn_Util.Hash = Cairn_Util.Hash or {}


-- AF_MD5 is the vendored implementation. Retrieve once per call
-- rather than caching at file scope — a re-load (different MINOR)
-- might swap the registered impl while Cairn-Util stays the same.
-- The cost of one extra LibStub lookup per hash call is negligible
-- against the MD5 computation itself.
local function getMD5()
    local md5 = LibStub and LibStub("AF_MD5", true)
    if not md5 then
        error("Cairn-Util.Hash.MD5: AF_MD5 vendored lib is not loaded. " ..
              "Check that AF_MD5.lua is listed in the .toc.", 3)
    end
    return md5
end


-- FNV-1a 32-bit constants.
local FNV_OFFSET = 2166136261
local FNV_PRIME  = 16777619
local UINT32     = 4294967296  -- 2^32


-- 32-bit unsigned multiplication.
--
-- Native Lua `a * b` would lose precision past 2^53 for `a` near 2^32
-- and `b` near 2^24 (the FNV prime is 16777619 ≈ 2^24). Splitting `a`
-- into 16-bit halves keeps every intermediate within 2^41, well
-- inside double precision. The result is exact modulo 2^32.
local function mul32(a, b)
    local a_lo = a % 65536
    local a_hi = (a - a_lo) / 65536
    return (((a_hi * b) % 65536) * 65536 + a_lo * b) % UINT32
end


-- Hash.MD5(input) -> 32-char lowercase hex digest.
-- Use for fingerprinting / dedupe / identity. NOT a cryptographic
-- primitive; MD5 is broken for security purposes. The "ID for a
-- chunk of content" use case is the legitimate one.
function Cairn_Util.Hash.MD5(input)
    if type(input) ~= "string" then
        error("Cairn-Util.Hash.MD5: input must be a string", 2)
    end
    return getMD5().sumhexa(input)
end


-- Hash.MD5Raw(input) -> 16 raw bytes.
-- The undisplayable form, useful when embedding the digest in a
-- binary stream. Most consumers want the hex variant instead.
function Cairn_Util.Hash.MD5Raw(input)
    if type(input) ~= "string" then
        error("Cairn-Util.Hash.MD5Raw: input must be a string", 2)
    end
    return getMD5().sum(input)
end


-- Hash.FNV1a32(value, seed?) -> 32-bit unsigned integer
--
-- Fast non-cryptographic hash for table-key derivation, content
-- fingerprinting, divergence detection, bloom filters. FNV-1a is
-- BROKEN for cryptographic purposes; do not use for security.
--
-- Algorithm: offset basis 2166136261, prime 16777619, per-byte
-- XOR-then-multiply, modulo 2^32.
--
-- Optional `seed` differentiates hash spaces. The `seed * 13`
-- multiplier spreads the seed's influence so distinct small seeds
-- yield meaningfully distinct hashes even for short inputs (without
-- the multiplier, seeds 1/2/3 produce near-identical hashes for
-- single-byte inputs).
--
-- `bit.bxor` in WoW Lua returns the signed interpretation when the
-- high bit is set, so each bxor is followed by `% UINT32` to
-- normalize to the unsigned representation. mul32 already clamps.
--
-- Non-string `value` is converted via tostring.
function Cairn_Util.Hash.FNV1a32(value, seed)
    local s = tostring(value)
    local hash = FNV_OFFSET
    if seed then
        hash = bit.bxor(hash, (seed * 13) % UINT32) % UINT32
    end
    for i = 1, #s do
        hash = bit.bxor(hash, s:byte(i)) % UINT32
        hash = mul32(hash, FNV_PRIME)
    end
    return hash
end


-- Hash.Combine(...) -> 32-bit unsigned integer
--
-- XOR-folds N hashes with uint32 clamp.
--
--   Combine()                          -> 0
--   Combine(a)                         -> a (mod 2^32)
--   Combine(a, b) == Combine(b, a)        (order-independent)
--   Combine(x, x)                      -> 0  (dup-removing)
--
-- The dup-removing property is INTENTIONAL for anti-entropy bucket
-- aggregation where a bucket represents a SET, not a multiset. If you
-- expect "incremental insert" semantics where Combine(h, h)
-- accumulates, do NOT use this primitive — use a different aggregator.
function Cairn_Util.Hash.Combine(...)
    -- WHY the explicit `local arg = select(i, ...)`: bare `select(i, ...)`
    -- in a function-call position expands to ALL remaining args, so
    -- bit.bxor(result, select(i, ...)) becomes bit.bxor(result, args[i],
    -- args[i+1], ..., args[n]) on every iteration -- folding the suffix
    -- into result over and over. Order-dependence and dup-non-removal
    -- fall out of that. Forcing single-value capture restores the
    -- intended fold semantics.
    local result = 0
    for i = 1, select("#", ...) do
        local arg = select(i, ...)
        result = bit.bxor(result, arg)
    end
    return result % UINT32
end


return Cairn_Util
