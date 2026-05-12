-- Cairn-Log smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: load, public API, New idempotency, log methods push entries
-- with the right shape, Category sub-logger, format args, custom level
-- via :Log, ring buffer wrap, GetEntries filtering (source/category/
-- level/since/limit) and ordering (newest first), SetChatEchoLevel +
-- echo behavior, Clear, SetCapacity (incl. shrink), input validation.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Log"] = function(report)
    -- 1. Library loaded + public API
    local CL = LibStub and LibStub("Cairn-Log-1.0", true)
    report("Cairn-Log is loaded under LibStub", CL ~= nil)
    if not CL then return end

    report("CL:New exists",              type(CL.New) == "function")
    report("CL:Get exists",              type(CL.Get) == "function")
    report("CL:GetEntries exists",       type(CL.GetEntries) == "function")
    report("CL:Clear exists",            type(CL.Clear) == "function")
    report("CL:SetChatEchoLevel exists", type(CL.SetChatEchoLevel) == "function")
    report("CL:SetCapacity exists",      type(CL.SetCapacity) == "function")
    report("CL.loggers is a table",      type(CL.loggers) == "table")
    report("CL.entries is a table",      type(CL.entries) == "table")
    -- MINOR 15 changed LEVELS to Python-style 6-level scheme with gaps.
    -- DEBUG/INFO/WARN/ERROR now at 10/20/30/40; TRACE/FATAL added at 0/50.
    -- WARN preserved as numeric alias for WARNING (both = 30).
    report("CL.LEVELS has DEBUG..ERROR ranks (MINOR 15: 10..40)",
           CL.LEVELS.DEBUG == 10 and CL.LEVELS.INFO == 20
           and CL.LEVELS.WARN == 30 and CL.LEVELS.ERROR == 40)


    -- Snapshot shared buffer + capacity around the test.
    local savedEntries  = CL.entries
    local savedHead     = CL._head
    local savedCount    = CL._count
    local savedCapacity = CL._capacity
    local savedEcho     = CL._echoLevel
    local savedLoggers  = CL.loggers

    CL.entries    = {}
    CL._head      = 1
    CL._count     = 0
    CL._capacity  = savedCapacity
    CL._echoLevel = nil
    CL.loggers    = {}


    -- 2. New() idempotency + registry
    local log = CL:New("CairnLogSmoke")
    report("New returned a table",                type(log) == "table")
    report("registry tracks the logger",          CL.loggers["CairnLogSmoke"] == log)
    report("CL:Get returns the logger",           CL:Get("CairnLogSmoke") == log)
    report("New(same name) is idempotent",        CL:New("CairnLogSmoke") == log)


    -- 3. Log methods push entries with the right shape
    log:Info("loaded successfully")
    local e = CL.entries[1]
    report("entry was written",               type(e) == "table")
    report("entry.source is the logger name", e and e.source == "CairnLogSmoke")
    report("entry.category is nil (no :Category)", e and e.category == nil)
    report("entry.level is INFO",             e and e.level == "INFO")
    report("entry.message is the raw string", e and e.message == "loaded successfully")
    report("entry.timestamp is a number",     e and type(e.timestamp) == "number")


    -- 4. Format args + custom :Log level
    log:Warn("got %d errors in %s", 5, "module-x")
    local entries = CL:GetEntries({ limit = 1 })
    report("Warn with format args produces formatted message",
           entries[1] and entries[1].message == "got 5 errors in module-x")

    log:Log("CUSTOM", "a custom-level message")
    entries = CL:GetEntries({ limit = 1 })
    report(":Log accepts any string as level",
           entries[1] and entries[1].level == "CUSTOM"
           and entries[1].message == "a custom-level message")


    -- 5. Category sub-logger
    local netLog = log:Category("net")
    netLog:Error("packet dropped on %s", "ws://x")

    entries = CL:GetEntries({ limit = 1 })
    report("Category sub-logger sets entry.category",
           entries[1] and entries[1].category == "net")
    report("Category sub-logger preserves entry.source",
           entries[1] and entries[1].source == "CairnLogSmoke")
    report("Category sub-logger is NOT registered as a separate root",
           CL.loggers["net"] == nil)


    -- 6. GetEntries: filtering
    CL:Clear()
    log:Debug("dbg msg")
    log:Info("info msg")
    log:Warn("warn msg")
    log:Error("err msg")
    netLog:Info("net info")
    netLog:Warn("net warn")

    report("GetEntries() no filter returns all 6 newest-first",
           #CL:GetEntries() == 6
           and CL:GetEntries()[1].message == "net warn")

    local warns = CL:GetEntries({ level = "WARN" })
    report("filter level=WARN includes WARN and ERROR only",
           #warns == 3
           and (warns[1].level == "WARN" or warns[1].level == "ERROR"))

    local netEntries = CL:GetEntries({ category = "net" })
    report("filter category='net' returns only sub-logger entries",
           #netEntries == 2
           and netEntries[1].category == "net"
           and netEntries[2].category == "net")

    local sourceFiltered = CL:GetEntries({ source = "CairnLogSmoke" })
    report("filter source returns all entries with that source",
           #sourceFiltered == 6)

    local limited = CL:GetEntries({ limit = 2 })
    report("filter limit=2 returns only 2 entries",  #limited == 2)


    -- 7. Ring buffer wrap (SetCapacity + push past)
    CL:SetCapacity(3)
    CL:Clear()
    log:Info("a")
    log:Info("b")
    log:Info("c")
    log:Info("d")
    log:Info("e")

    entries = CL:GetEntries()
    report("Ring buffer cap=3 holds only 3 entries", #entries == 3)
    report("Newest entry is 'e'",                    entries[1].message == "e")
    report("Oldest retained is 'c'",                 entries[3].message == "c")


    -- 8. SetCapacity shrink
    CL:SetCapacity(2)
    entries = CL:GetEntries()
    report("After shrink to 2, GetEntries returns at most 2", #entries <= 2)


    -- 9. SetChatEchoLevel + chat echo behavior
    CL:SetCapacity(savedCapacity)
    CL:Clear()

    local originalPrint, captured = print, {}
    print = function(...) captured[#captured + 1] = table.concat({...}, "\t") end

    CL:SetChatEchoLevel("WARN")
    log:Info("info no echo")
    log:Warn("warn echo")
    log:Error("err echo")
    log:Debug("debug no echo")

    print = originalPrint

    local joined = table.concat(captured, "\n")
    report("INFO did NOT echo (below threshold)",  not joined:find("info no echo", 1, true))
    report("DEBUG did NOT echo (below threshold)", not joined:find("debug no echo", 1, true))
    report("WARN echoed",                          joined:find("warn echo", 1, true) ~= nil)
    report("ERROR echoed",                         joined:find("err echo",  1, true) ~= nil)
    report("Echo line contains source",            joined:find("CairnLogSmoke", 1, true) ~= nil)

    CL:SetChatEchoLevel(nil)
    captured = {}
    print = function(...) captured[#captured + 1] = table.concat({...}, "\t") end
    log:Error("should be silent now")
    print = originalPrint
    report("After SetChatEchoLevel(nil), no entries echo",
           table.concat(captured, "\n"):find("should be silent now", 1, true) == nil)


    -- 10. Clear
    log:Info("one")
    log:Info("two")
    CL:Clear()
    report("Clear empties the buffer", #CL:GetEntries() == 0)
    report("Clear resets _count",      CL._count == 0)


    -- 11. Input validation
    report("New('') errors",
           not pcall(function() CL:New("") end))
    report("New(nil) errors",
           not pcall(function() CL:New(nil) end))
    report(":Log('', 'msg') errors",
           not pcall(function() log:Log("", "msg") end))
    report(":Category('') errors",
           not pcall(function() log:Category("") end))
    report("SetCapacity(0) errors",
           not pcall(function() CL:SetCapacity(0) end))
    report("SetCapacity('x') errors",
           not pcall(function() CL:SetCapacity("x") end))
    report("SetChatEchoLevel(42) errors",
           not pcall(function() CL:SetChatEchoLevel(42) end))
    report("GetEntries(42) errors (filter must be table or nil)",
           not pcall(function() CL:GetEntries(42) end))


    -- =====================================================================
    -- MINOR 15 additions — Decisions 1-3, 5, 7, 8, 9 from the 2026-05-12 walk
    -- =====================================================================

    -- D1: new 6-level scheme with gaps
    report("LEVELS.TRACE = 0",      CL.LEVELS.TRACE == 0)
    report("LEVELS.DEBUG = 10",     CL.LEVELS.DEBUG == 10)
    report("LEVELS.INFO = 20",      CL.LEVELS.INFO == 20)
    report("LEVELS.WARNING = 30",   CL.LEVELS.WARNING == 30)
    report("LEVELS.WARN = 30 (alias)", CL.LEVELS.WARN == 30)
    report("LEVELS.ERROR = 40",     CL.LEVELS.ERROR == 40)
    report("LEVELS.FATAL = 50",     CL.LEVELS.FATAL == 50)

    -- New methods land on loggers
    local lvlLog = CL:New("ClusterA_LevelMethods_" .. tostring(time and time() or 0))
    report("log:Trace exists",   type(lvlLog.Trace)   == "function")
    report("log:Warning exists", type(lvlLog.Warning) == "function")
    report("log:Fatal exists",   type(lvlLog.Fatal)   == "function")
    report("log:ForceError exists", type(lvlLog.ForceError) == "function")
    report("log:ForceFatal exists", type(lvlLog.ForceFatal) == "function")

    -- D2: entry-shape aliases (t/s/m route to timestamp/level/message)
    CL.entries = {}; CL._head = 1; CL._count = 0
    lvlLog:Trace("first")
    lvlLog:Fatal("second")
    local recent = CL:GetEntries({ limit = 5 })
    if recent[1] then
        report("entry.t aliases timestamp",
               recent[1].t == recent[1].timestamp)
        report("entry.s aliases level",
               recent[1].s == recent[1].level)
        report("entry.m aliases message",
               recent[1].m == recent[1].message)
    end


    -- D3: database backing via :SetDatabase
    report("CL:SetDatabase is a function", type(CL.SetDatabase) == "function")
    local fakeDB = {}
    CL:SetDatabase(fakeDB)
    CL.entries = {}; CL._head = 1; CL._count = 0
    local dbLog = CL:New("ClusterA_DB_" .. tostring(time and time() or 0))
    dbLog:Info("backed by db")
    report("SetDatabase routes entries into the SV table",
           #fakeDB == 1 and fakeDB[1].message == "backed by db")
    CL:SetDatabase(nil)
    report("SetDatabase(nil) disconnects (subsequent entries don't write)",
           CL._database == nil)
    dbLog:Info("not in db")
    report("After disconnect, fakeDB unchanged",
           #fakeDB == 1)


    -- D5: ForceError / ForceFatal bypass echo gate
    CL.entries = {}; CL._head = 1; CL._count = 0
    CL._echoLevel = nil   -- no echo at all
    local fLog = CL:New("ClusterA_Force_" .. tostring(time and time() or 0))
    local ok1 = pcall(function() fLog:ForceError("force err") end)
    local ok2 = pcall(function() fLog:ForceFatal("force fatal") end)
    report("ForceError() runs without error", ok1)
    report("ForceFatal() runs without error", ok2)
    local entries = CL:GetEntries({ limit = 5 })
    report("ForceError entry written to ring buffer",
           #entries >= 1)


    -- D7: performance mode nils method slots below threshold
    report("CL:SetPerformanceMode is a function", type(CL.SetPerformanceMode) == "function")
    CL:SetPerformanceMode("WARNING")
    report("Performance mode hasTrace = false",   CL.hasTrace   == false)
    report("Performance mode hasDebug = false",   CL.hasDebug   == false)
    report("Performance mode hasInfo  = false",   CL.hasInfo    == false)
    report("Performance mode hasWarning = true",  CL.hasWarning == true)
    report("Performance mode hasError = true",    CL.hasError   == true)
    report("Performance mode hasFatal = true",    CL.hasFatal   == true)
    local pmLog = CL:New("ClusterA_PM_" .. tostring(time and time() or 0))
    report("Performance mode nils log:Trace below threshold",
           pmLog.Trace == nil)
    report("Performance mode preserves log:Warning at threshold",
           type(pmLog.Warning) == "function")

    CL:SetPerformanceMode(nil)
    report("Performance mode nil restores hasTrace",
           CL.hasTrace == true)
    local restoreLog = CL:New("ClusterA_PMRestore_" .. tostring(time and time() or 0))
    report("Performance mode nil restores log:Trace",
           type(restoreLog.Trace) == "function")

    report("SetPerformanceMode('BogusLevel') errors",
           not pcall(function() CL:SetPerformanceMode("BogusLevelXYZ") end))


    -- D9: :Embed
    report("CL:Embed is a function", type(CL.Embed) == "function")
    local fakeAddon = {}
    CL:Embed(fakeAddon, "ClusterA_Embed_" .. tostring(time and time() or 0))
    report("Embed injects :Info onto target",  type(fakeAddon.Info)  == "function")
    report("Embed injects :Debug onto target", type(fakeAddon.Debug) == "function")
    report("Embed injects :Warn onto target",  type(fakeAddon.Warn)  == "function")
    report("Embed injects :Error onto target", type(fakeAddon.Error) == "function")
    report("Embed injects :Category onto target", type(fakeAddon.Category) == "function")
    fakeAddon:Info("embed test message")
    local lastEntries = CL:GetEntries({ limit = 1 })
    report("Embed:Info call lands in ring buffer",
           lastEntries[1] and lastEntries[1].message == "embed test message")


    -- Restore state
    CL.entries    = savedEntries
    CL._head      = savedHead
    CL._count     = savedCount
    CL._capacity  = savedCapacity
    CL._echoLevel = savedEcho
    CL.loggers    = savedLoggers
    CL:SetPerformanceMode(nil)
    CL:SetDatabase(nil)
end
