-- Cairn-Log
-- Categorized ring-buffer log shared across every consumer of the lib.
-- One source-level logger per addon, with optional category sub-loggers.
-- Forge_Logs reads from the shared buffer to render its UI.
--
--   local CL  = LibStub("Cairn-Log-1.0")
--   local log = CL:New("MyAddon")
--
--   log:Info("loaded successfully")
--   log:Warn("connection slow")
--   log:Error("got %d errors", 5)              -- string.format args
--   log:Debug("user clicked %s", buttonName)
--
--   -- Category sub-logger (no category on the parent stays uncategorized)
--   local netLog = log:Category("net")
--   netLog:Warn("packet dropped")               -- entry has category = "net"
--
--   -- Singleton operations on the shared buffer
--   for _, e in ipairs(CL:GetEntries({ level = "WARN", limit = 50 })) do
--       print(e.timestamp, e.source, e.category, e.level, e.message)
--   end
--   CL:SetChatEchoLevel("WARN")     -- WARN/ERROR also print()
--   CL:Clear()                       -- empty the buffer
--   CL:SetCapacity(2000)             -- ring-buffer size (default 1000)
--
-- Entry shape (read-only convention; do not mutate):
--   { timestamp, source, category, level, message }
--   Aliases via metatable __index (MINOR 15):
--     entry.t == entry.timestamp
--     entry.s == entry.level
--     entry.m == entry.message
--   Both shapes work; the short forms exist for Cluster-A renderers that
--   expect the walked compact-field shape.
--
-- Levels (built-in, Python-style numeric scheme with gaps; MINOR 15):
--   TRACE (0)  <  DEBUG (10)  <  INFO (20)  <  WARNING (30) == WARN  <  ERROR (40)  <  FATAL (50)
--   Gaps reserved for consumer-defined intermediate levels (VERBOSE=5,
--   NOTICE=25, etc.) without renumbering the standard set.
--   `WARN` is preserved as a numeric ALIAS for `WARNING` for pre-MINOR-15
--   backcompat; both compare equal in rank-based threshold checks.
--   Custom level strings are accepted via :Log(level, ...) — they get rank 0
--   so they never trigger the chat-echo threshold automatically.
--
-- Design notes:
--   - One shared ring buffer for the entire process. Consumers all log into
--     it; Forge_Logs reads from it. This is what makes "Forge_Logs replaces
--     Cairn.Dashboard" work — one place to look.
--   - Ring is fixed size; old entries roll off as new ones arrive. No
--     manual cleanup. Default capacity 1000 entries.
--   - Persistence is out of scope for this lib. The buffer is in-memory and
--     dies on /reload. Wrap with Cairn-DB if you want SavedVariables-backed
--     log history.
--   - Chat echo is opt-in. Default is silent (log-only). Set a threshold
--     level and matching+higher entries also fire `print()` with a colored
--     prefix.
--
-- Public API (lib):
--   CL:New(name [, db])     -> root logger    -- idempotent on `name`. Optional
--                                                `db` bootstraps lib-level
--                                                persistence.
--   CL:Get(name)                              -- registry lookup
--   CL.loggers                                -- { [name] = root logger }
--   CL.entries                                -- the ring buffer (read-only)
--   CL:GetEntries(filter)                     -- {source,category,level,since,limit}
--   CL:Clear()
--   CL:SetChatEchoLevel(level_or_nil)
--   CL:SetCapacity(n)
--   CL:SetDatabase(svTable_or_nil)            -- opt-in persistence
--   CL:SetPerformanceMode(threshold_or_nil)   -- nils method slots
--   CL:Embed(target, name) -> target          -- mixin
--   CL.LEVELS                                 -- {TRACE=0, DEBUG=10, INFO=20,
--                                                WARNING=30, WARN=30, ERROR=40,
--                                                FATAL=50}
--   CL.hasTrace / hasDebug / hasInfo /        -- gate flags
--   hasWarning / hasError / hasFatal            (reflect current SetPerformanceMode
--                                                state)
--
-- Public API (instance, both root and sub):
--   log:Trace  (fmt, ...)
--   log:Debug  (fmt, ...)
--   log:Info   (fmt, ...)
--   log:Warning(fmt, ...)
--   log:Warn   (fmt, ...)                     -- alias for :Warning
--   log:Error  (fmt, ...)
--   log:Fatal  (fmt, ...)
--   log:ForceError(fmt, ...)                  -- bypass echo gate
--   log:ForceFatal(fmt, ...)                  -- bypass echo gate
--   log:Log(level, fmt, ...)                  -- custom level string
--   log:Category(name) -> sub-logger          -- shares source, fixed category
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Log-1.0"
local LIB_MINOR = 15

local Cairn_Log = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Log then return end


-- Preserve state across MINOR upgrades.
Cairn_Log.loggers     = Cairn_Log.loggers     or {}
Cairn_Log.entries     = Cairn_Log.entries     or {}
Cairn_Log._capacity   = Cairn_Log._capacity   or 1000
Cairn_Log._head       = Cairn_Log._head       or 1
Cairn_Log._count      = Cairn_Log._count      or 0
Cairn_Log._echoLevel  = Cairn_Log._echoLevel  -- nil unless SetChatEchoLevel'd

-- Severity scheme. Python-style
-- numeric values with gaps so consumers can register custom intermediate
-- levels (VERBOSE=5, NOTICE=25, etc.) without renumbering the standard
-- set. `WARN` is preserved as a numeric ALIAS for `WARNING` for
-- backcompat with the pre-MINOR-15 4-level system; both compare equal in
-- rank-based threshold checks.
Cairn_Log.LEVELS = Cairn_Log.LEVELS or {
    TRACE   = 0,
    DEBUG   = 10,
    INFO    = 20,
    WARNING = 30,
    WARN    = 30,   -- alias for WARNING (pre-MINOR-15 backcompat)
    ERROR   = 40,
    FATAL   = 50,
}

local LEVEL_COLOR = {
    TRACE   = "|cff555555",
    DEBUG   = "|cff888888",
    INFO    = "|cffffffff",
    WARNING = "|cffffaa00",
    WARN    = "|cffffaa00",   -- backcompat alias for WARNING
    ERROR   = "|cffff5555",
    FATAL   = "|cffff0000",
}


-- ---------------------------------------------------------------------------
-- Internal: ring-buffer push
-- ---------------------------------------------------------------------------

-- Unknown levels get rank 0 so a custom :Log("AUDIT", ...) call doesn't
-- accidentally meet the chat-echo threshold of a known level.
local function rankOf(level)
    return Cairn_Log.LEVELS[level] or 0
end


-- Compact-aliases metatable. Each entry's full
-- shape stays `{timestamp, source, category, level, message}` for
-- Forge_Logs and existing consumers. Cluster-A renderers expecting the
-- walked `{t, s, m}` short-field shape read via __index aliases —
-- entry.t / entry.s / entry.m route to the same underlying values.
local ENTRY_META = {
    __index = function(entry, key)
        if key == "t" then return rawget(entry, "timestamp") end
        if key == "s" then return rawget(entry, "level")     end
        if key == "m" then return rawget(entry, "message")   end
        return nil
    end,
}


-- Ring write: a head pointer + count counter, no eviction sweep. New
-- entries overwrite the oldest slot in place once the buffer is full, so
-- sustained logging has steady-state cost (no allocations beyond the entry
-- itself, no GC churn from queue reshuffling).
--
-- Chat echo is inline rather than queued because the threshold check is
-- cheap and queueing would just delay visibility.
--
-- `force` — when true, the entry bypasses the chat-
-- echo threshold check and ALWAYS prints. Used by :ForceError / :ForceFatal
-- to guarantee critical failures reach the user even when the logger is
-- configured for quiet operation.
local function pushEntry(source, category, level, message, force)
    local entry = setmetatable({
        timestamp = (time and time()) or 0,
        source    = source,
        category  = category,
        level     = level,
        message   = message,
    }, ENTRY_META)

    local idx = Cairn_Log._head
    Cairn_Log.entries[idx] = entry

    idx = idx + 1
    if idx > Cairn_Log._capacity then idx = 1 end
    Cairn_Log._head = idx

    if Cairn_Log._count < Cairn_Log._capacity then
        Cairn_Log._count = Cairn_Log._count + 1
    end

    -- Database backing. When :SetDatabase has been
    -- called or a per-logger db was passed via :New, entries also write
    -- to the consumer-supplied SV table. Bounded by the same ring capacity
    -- as the in-memory buffer to prevent unbounded SV growth.
    local db = Cairn_Log._database
    if db then
        if type(db) ~= "table" then
            -- defensive: consumer cleared their SV without unhooking us.
            Cairn_Log._database = nil
        else
            db[#db + 1] = entry
            local cap = Cairn_Log._capacity or 1000
            -- Trim oldest entries when over capacity. table.remove(t, 1) is
            -- O(n) but only fires when the SV table is full, so amortized
            -- cost stays low.
            while #db > cap do table.remove(db, 1) end
        end
    end

    local echo = Cairn_Log._echoLevel
    if force or (echo and rankOf(level) >= rankOf(echo)) then
        local color = LEVEL_COLOR[level] or "|cffffffff"
        print(string.format("%s[%s]|r %s%s: %s",
            color, level,
            source,
            category and ("/" .. category) or "",
            message))
    end
end


-- Single-arg call path skips the string.format pass so consumers can log a
-- raw message containing % without escaping (e.g. `log:Info("100% loaded")`).
-- A failing format call is caught and stringified into the message rather
-- than thrown — losing a log line to a bad format string is the WORST
-- possible failure mode for a logging library.
local function formatMessage(fmt, ...)
    if fmt == nil then return "" end
    if select("#", ...) == 0 then
        return tostring(fmt)
    end
    local ok, result = pcall(string.format, fmt, ...)
    if ok then return result end
    return tostring(fmt) .. " [format-error: " .. tostring(result) .. "]"
end


-- ---------------------------------------------------------------------------
-- Logger instance methods (root + sub share the same metatable)
-- ---------------------------------------------------------------------------

local LoggerMethods = {}

local function logAt(self, level, force, fmt, ...)
    pushEntry(self._source, self._category, level, formatMessage(fmt, ...), force)
end

function LoggerMethods:Trace  (fmt, ...) logAt(self, "TRACE",   false, fmt, ...) end
function LoggerMethods:Debug  (fmt, ...) logAt(self, "DEBUG",   false, fmt, ...) end
function LoggerMethods:Info   (fmt, ...) logAt(self, "INFO",    false, fmt, ...) end
function LoggerMethods:Warning(fmt, ...) logAt(self, "WARNING", false, fmt, ...) end
function LoggerMethods:Warn   (fmt, ...) logAt(self, "WARN",    false, fmt, ...) end  -- alias
function LoggerMethods:Error  (fmt, ...) logAt(self, "ERROR",   false, fmt, ...) end
function LoggerMethods:Fatal  (fmt, ...) logAt(self, "FATAL",   false, fmt, ...) end

-- Force-print variants. Bypass the chat-echo
-- threshold so critical failures reach the user even when the logger is
-- configured silent. Entry still lands in the ring buffer same as normal.
-- Use for failures the user MUST see (data corruption, irrecoverable
-- API breakage, etc.).
function LoggerMethods:ForceError(fmt, ...) logAt(self, "ERROR", true, fmt, ...) end
function LoggerMethods:ForceFatal(fmt, ...) logAt(self, "FATAL", true, fmt, ...) end

-- Escape hatch for custom level names (e.g. "AUDIT", "NOTICE"). Custom
-- levels get rank 0, which means they never satisfy a chat-echo threshold
-- of WARN+ by default — experimental levels can't accidentally spam chat.
function LoggerMethods:Log(level, fmt, ...)
    if type(level) ~= "string" or level == "" then
        error("Cairn-Log :Log: level must be a non-empty string", 2)
    end
    logAt(self, level, false, fmt, ...)
end

-- Sub-loggers share the source's identity but tag entries with a category
-- so Forge_Logs can filter. Not registered separately — only the root
-- loggers appear in Cairn_Log.loggers. This keeps the registry view clean
-- (one entry per addon, not one per category).
function LoggerMethods:Category(name)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Log :Category: name must be a non-empty string", 2)
    end
    return setmetatable({
        _source   = self._source,
        _category = name,
    }, getmetatable(self))
end

local LoggerMeta = { __index = LoggerMethods }


-- ---------------------------------------------------------------------------
-- Performance mode + hasX flags (Cairn-Log Decisions 7, 8)
-- ---------------------------------------------------------------------------

-- Canonical (level → method name) pairs. Used by both performance-mode
-- nil-out and hasX flag maintenance. WARN is intentionally omitted (alias
-- for WARNING; consumers using log:Warn(...) keep that method even in
-- performance mode regardless of WARNING's state, to preserve pre-MINOR-15
-- call sites).
local CANONICAL_LEVEL_METHODS = {
    { level = "TRACE",   method = "Trace"   },
    { level = "DEBUG",   method = "Debug"   },
    { level = "INFO",    method = "Info"    },
    { level = "WARNING", method = "Warning" },
    { level = "ERROR",   method = "Error"   },
    { level = "FATAL",   method = "Fatal"   },
}

-- Save originals so we can restore methods when threshold lowers.
local ORIGINAL_METHODS = ORIGINAL_METHODS or {}
for _, pair in ipairs(CANONICAL_LEVEL_METHODS) do
    ORIGINAL_METHODS[pair.method] = LoggerMethods[pair.method]
end


-- Helper: compute hasX flags + nil/restore method slots based on
-- threshold (lib-level operation; affects every logger sharing the
-- LoggerMethods metatable). When threshold is nil, all methods restore
-- to their originals and all hasX flags become true.
local function refreshPerformanceMode()
    local threshold = Cairn_Log._performanceThreshold
    for _, pair in ipairs(CANONICAL_LEVEL_METHODS) do
        local rank = Cairn_Log.LEVELS[pair.level] or 0
        local enabled
        if threshold == nil then
            enabled = true
        else
            local tRank = Cairn_Log.LEVELS[threshold] or 0
            enabled = rank >= tRank
        end
        if enabled then
            LoggerMethods[pair.method] = ORIGINAL_METHODS[pair.method]
        else
            LoggerMethods[pair.method] = nil
        end
        Cairn_Log["has" .. pair.method] = enabled
    end
end

-- Initial hasX flag population (all enabled).
refreshPerformanceMode()


-- :SetPerformanceMode(threshold) — nil method slots below threshold.
--
-- Consumers gate hot calls via:
--   if Cairn.Log.hasDebug then myLog:Debug(expensive_format(...)) end
-- Skipping the expensive argument construction entirely when DEBUG is
-- disabled. Threshold is a level NAME (string) like "INFO" or "WARNING";
-- pass nil to restore all methods.
--
-- Lib-level scope: affects EVERY logger sharing the shared LoggerMethods
-- dispatch table. Per-instance performance mode is a future-work item
-- (would require per-instance method tables instead of the current shared
-- metatable architecture).
function Cairn_Log:SetPerformanceMode(threshold)
    if threshold ~= nil then
        if type(threshold) ~= "string" or self.LEVELS[threshold] == nil then
            error("Cairn-Log:SetPerformanceMode: threshold must be a known level name or nil (got "
                  .. tostring(threshold) .. ")", 2)
        end
    end
    self._performanceThreshold = threshold
    refreshPerformanceMode()
end


-- :SetDatabase(svTable) — opt-in persistence.
--
-- When set, every entry that goes through pushEntry also lands in
-- `svTable` (which the consumer typically connects to a SavedVariables
-- entry). Bounded by the same capacity as the in-memory ring buffer to
-- prevent unbounded SV growth.
--
-- Pass nil to disconnect the database. The in-memory ring buffer is
-- unaffected by both connect and disconnect (it always operates).
--
-- Caveat: the consumer's TOC must declare the SavedVariables for the
-- table to actually persist across sessions. Cairn-Log just appends to
-- it in-memory if SVs aren't declared.
function Cairn_Log:SetDatabase(svTable)
    if svTable ~= nil and type(svTable) ~= "table" then
        error("Cairn-Log:SetDatabase: svTable must be a table or nil", 2)
    end
    self._database = svTable
end


-- ---------------------------------------------------------------------------
-- Public API (lib-level)
-- ---------------------------------------------------------------------------

-- Idempotent on `name`. Many addons have multiple .lua files that all want
-- to grab the same logger; each file's :New() returns the same instance
-- without coordination.
--
-- Optional `db` arg: when supplied AND no lib-
-- level database is currently set, calling :New(name, db) bootstraps
-- the lib-level database from this consumer's table. First-caller wins;
-- subsequent :New calls passing a db are ignored at the lib-level (the
-- per-logger db form would require per-logger SV routing which is bigger
-- work).
function Cairn_Log:New(name, db)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Log:New: name must be a non-empty string", 2)
    end
    if db ~= nil and type(db) ~= "table" then
        error("Cairn-Log:New: db must be a table or nil", 2)
    end

    local existing = self.loggers[name]
    if existing then
        -- Idempotent: if a db is supplied on a re-call AND no lib-level
        -- database is set, accept it as a late-bind. Otherwise ignore.
        if db and not self._database then self._database = db end
        return existing
    end

    if db and not self._database then self._database = db end

    local logger = setmetatable({
        _source   = name,
        _category = nil,
    }, LoggerMeta)

    self.loggers[name] = logger
    return logger
end


function Cairn_Log:Get(name)
    return self.loggers[name]
end


-- Reads the ring buffer in REVERSE write order (newest first) because
-- that's what every consumer of log data actually wants — "show me the
-- recent stuff first". Filter is AND'd across all provided keys.
--
-- `level` filter is rank-based (MINIMUM level), not exact match — so
-- filter.level = "WARN" returns WARN + ERROR. category filter IS exact
-- (nil categories only match a nil category filter, which can't be expressed
-- in the API today; leave the key out to match all categories).
function Cairn_Log:GetEntries(filter)
    filter = filter or {}
    if type(filter) ~= "table" then
        error("Cairn-Log:GetEntries: filter must be a table or nil", 2)
    end

    local results = {}
    local count   = self._count
    if count == 0 then return results end

    local capacity = self._capacity
    local start = self._head - 1
    if start < 1 then start = capacity end

    local limit    = filter.limit or math.huge
    local minRank  = filter.level and rankOf(filter.level) or 0
    local source   = filter.source
    local category = filter.category
    local since    = filter.since
    local hasCatFilter = filter.category ~= nil

    local emitted = 0
    for i = 1, count do
        local idx = start - (i - 1)
        while idx < 1 do idx = idx + capacity end
        local e = self.entries[idx]
        if e then
            local include = true
            if source   and e.source   ~= source   then include = false end
            if hasCatFilter and e.category ~= category then include = false end
            if since    and e.timestamp < since    then include = false end
            if filter.level and rankOf(e.level) < minRank then include = false end

            if include then
                emitted = emitted + 1
                results[emitted] = e
                if emitted >= limit then break end
            end
        end
    end

    return results
end


function Cairn_Log:Clear()
    for i = 1, self._capacity do
        self.entries[i] = nil
    end
    self._head  = 1
    self._count = 0
end


function Cairn_Log:SetChatEchoLevel(level)
    if level ~= nil then
        if type(level) ~= "string" or level == "" then
            error("Cairn-Log:SetChatEchoLevel: level must be a string or nil", 2)
        end
    end
    self._echoLevel = level
end


-- Shrink semantics are crude on purpose: we cap _count and reset _head
-- rather than rebuild the ring to preserve the newest N entries. A
-- consumer shrinking the buffer is making a deliberate "I want a smaller
-- footprint" choice; losing recent history is acceptable. The alternative
-- (preserving the newest entries) would require a full scan + reshuffle on
-- every shrink call, which isn't worth the engineering for this edge case.
function Cairn_Log:SetCapacity(n)
    if type(n) ~= "number" or n < 1 then
        error("Cairn-Log:SetCapacity: capacity must be a positive number", 2)
    end
    n = math.floor(n)
    self._capacity = n
    if self._count > n then self._count = n end
    if self._head  > n then self._head  = 1 end
end


-- ---------------------------------------------------------------------------
-- :Embed(target, name) — mixin
-- ---------------------------------------------------------------------------
-- Injects logger methods (`:Info`, `:Debug`, `:Warn`, `:Error`, `:Category`)
-- directly onto `target` so consumers get short call sites:
--
--   Cairn.Log:Embed(MyAddon, "MyAddon")
--   function MyAddon:doSomething()
--       self:Info("doing stuff")     -- instead of self.log:Info(...)
--   end
--
-- Each injected method routes to a shared logger instance for `name`.
-- Multiple Embed calls on the same target with the same name share the
-- same underlying logger (and thus share rate-limiting, etc.).
--
-- Method-collision policy: `:Log(level, ...)` is INTENTIONALLY NOT
-- embedded. The key `Log` is reserved for the consumer's own use (e.g.
-- the Cairn-Addon AUTO_WIRE_FLAGS Log entry sets a fallback
-- `addon.Log = lib` when Embed isn't available; embedding our `:Log`
-- method would clobber that). Consumers wanting custom-level logging
-- reach through `Cairn.Log:Get(name):Log(level, ...)` directly.
--
-- Surfaced by Cairn-Addon's `opts.Log = true` auto-wire flag.
function Cairn_Log:Embed(target, name)
    if type(target) ~= "table" then
        error("Cairn-Log:Embed: target must be a table", 2)
    end
    if type(name) ~= "string" or name == "" then
        error("Cairn-Log:Embed: name must be a non-empty string", 2)
    end

    local log = self:New(name)

    -- Each injected method dispatches `self` as the target, but routes
    -- args through the bound logger instance. Self gets dropped (we don't
    -- pass it to log:Method since the logger is per-name, not per-target).
    target.Info = function(_, fmt, ...) return log:Info(fmt, ...) end
    target.Debug = function(_, fmt, ...) return log:Debug(fmt, ...) end
    target.Warn = function(_, fmt, ...) return log:Warn(fmt, ...) end
    target.Error = function(_, fmt, ...) return log:Error(fmt, ...) end

    -- Sub-logger access is useful too — `self:Category("net")` returns a
    -- category-bound logger that the consumer can hold a reference to.
    target.Category = function(_, categoryName)
        return log:Category(categoryName)
    end

    return target
end


return Cairn_Log
