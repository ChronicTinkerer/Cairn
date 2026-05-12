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
--   String  TitleCase, NormalizeWhitespace
--   Frame   NormalizeSetPointArgs (and future Frame helpers)
--   Hash    MD5 (via vendored AF_MD5), FNV1a32, Combine
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
local LIB_MINOR = 19

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
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            Cairn_Util.Table.MergeDefaults(target[k], v)
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
    local result = 0
    for i = 1, select("#", ...) do
        result = bit.bxor(result, select(i, ...))
    end
    return result % UINT32
end


return Cairn_Util
