-- Cairn-Util-ObjectPool smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; :New creates a pool;
-- Acquire returns (obj, isNew) with isNew flipping correctly across
-- reuse; resetFn runs on Release; AcquireFor tags ownership;
-- ReleaseOwner batch-releases tagged objects; ReleaseAll empties the
-- active set and clears owner tracking; EnumerateActive iterates;
-- mixed tagged + untagged acquisitions don't interfere.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-ObjectPool"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.ObjectPool table exists",      type(CU.ObjectPool) == "table")
    report("CU.ObjectPool.New is a function", type(CU.ObjectPool and CU.ObjectPool.New) == "function")

    if not (CU.ObjectPool and type(CU.ObjectPool.New) == "function") then return end


    -- Helpers for the rest of the test
    local nextId, resetCount = 0, 0
    local function createFn()
        nextId = nextId + 1
        return { id = nextId, dirty = true }
    end
    local function resetFn(obj)
        obj.dirty  = false
        resetCount = resetCount + 1
    end


    -- 2. Basic Acquire / Release
    local pool = CU.ObjectPool:New(createFn, resetFn)
    report("New returns table",          type(pool) == "table")

    local a, isNewA = pool:Acquire()
    report("Acquire returns object",     type(a) == "table" and a.id ~= nil)
    report("First acquire is new",       isNewA == true)
    report("Fresh object is dirty",      a.dirty == true)

    pool:Release(a)
    report("Release ran resetFn",         a.dirty == false)
    report("Reset count after one release", resetCount == 1)

    local b, isNewB = pool:Acquire()
    report("Reacquire returns recycled object", b == a)
    report("Reacquired is NOT new",       isNewB == false)


    -- 3. AcquireFor / ReleaseOwner
    pool:ReleaseAll()
    resetCount = 0

    local ownerA = { tag = "ownerA" }
    local ownerB = { tag = "ownerB" }
    local p1 = pool:AcquireFor(ownerA)
    local p2 = pool:AcquireFor(ownerA)
    local p3 = pool:AcquireFor(ownerB)
    local p4 = pool:Acquire()  -- untagged
    report("Four distinct active objects",
           p1 ~= p2 and p2 ~= p3 and p3 ~= p4 and p1 ~= p3 and p1 ~= p4 and p2 ~= p4)

    pool:ReleaseOwner(ownerA)
    report("ReleaseOwner ran resetFn for tagged objects", resetCount == 2)

    pool:ReleaseOwner(ownerA)
    report("Second ReleaseOwner is a no-op", resetCount == 2)

    pool:Release(p4)
    report("Release on untagged works", resetCount == 3)

    pool:ReleaseOwner(ownerB)
    report("Release remaining tagged",  resetCount == 4)


    -- 4. Release of a tagged object clears its tag (no double-release)
    pool:ReleaseAll()
    resetCount = 0

    local q = pool:AcquireFor(ownerA)
    pool:Release(q)
    pool:ReleaseOwner(ownerA)
    report("Direct Release clears owner tag", resetCount == 1)


    -- 5. ReleaseAll clears everything
    pool:AcquireFor(ownerA)
    pool:AcquireFor(ownerB)
    pool:Acquire()
    pool:ReleaseAll()

    resetCount = 0
    pool:ReleaseOwner(ownerA)
    pool:ReleaseOwner(ownerB)
    report("ReleaseAll cleared owner tracking", resetCount == 0)


    -- 6. EnumerateActive
    pool:ReleaseAll()
    local x = pool:Acquire()
    local y = pool:Acquire()
    local seen = {}
    for obj in pool:EnumerateActive() do seen[obj] = true end
    report("EnumerateActive saw x", seen[x] == true)
    report("EnumerateActive saw y", seen[y] == true)
end
