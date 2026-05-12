-- Cairn-Util-Memoize smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: top-level function attached to Cairn-Util; basic call caches,
-- repeat call hits, different args miss, nil args supported via sentinel,
-- multiple return values preserved with embedded nils, table args use
-- reference equality, callable tables accepted, non-callable input errors
-- loud, consumer-supplied cache works.

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Memoize"] = function(report)
    -- 1. Library + surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Memoize is a function", type(CU.Memoize) == "function")
    if type(CU.Memoize) ~= "function" then return end


    -- 2. Basic caching
    local calls = 0
    local function add(a, b) calls = calls + 1; return a + b end
    local addM = CU.Memoize(add)

    report("First call computes",       addM(1, 2) == 3 and calls == 1)
    report("Same args cached",          addM(1, 2) == 3 and calls == 1)
    report("Different args compute",    addM(2, 3) == 5 and calls == 2)
    report("Repeated args still cached", addM(1, 2) == 3 and calls == 2)


    -- 3. Arity flexibility (single, zero, three args)
    calls = 0
    local function describe(...) calls = calls + 1; return select("#", ...) end
    local descM = CU.Memoize(describe)
    report("zero-arg call",   descM() == 0 and calls == 1)
    report("zero-arg cached", descM() == 0 and calls == 1)
    report("three-arg call",   descM("a", "b", "c") == 3 and calls == 2)
    report("three-arg cached", descM("a", "b", "c") == 3 and calls == 2)


    -- 4. Nil-arg support via sentinel
    calls = 0
    local function returnFirst(a, b) calls = calls + 1; return a end
    local rfM = CU.Memoize(returnFirst)
    report("nil arg first call",        rfM(nil, 5) == nil and calls == 1)
    report("nil arg cached",            rfM(nil, 5) == nil and calls == 1)
    report("non-nil distinct from nil", rfM("x", 5) == "x" and calls == 2)


    -- 5. Multiple return values (including embedded nils)
    local function multi(x) return x, nil, x * 2 end
    local multiM = CU.Memoize(multi)
    local a, b, c = multiM(3)
    report("multi first return",        a == 3)
    report("multi middle nil preserved", b == nil)
    report("multi third return",        c == 6)

    local a2, b2, c2 = multiM(3)
    report("multi cached first",      a2 == 3)
    report("multi cached middle nil", b2 == nil)
    report("multi cached third",      c2 == 6)


    -- 6. Table args use reference equality
    calls = 0
    local function identity(t) calls = calls + 1; return t end
    local idM = CU.Memoize(identity)
    local t1, t2 = {}, {}
    idM(t1); idM(t1)
    report("Same table reference hits cache", calls == 1)
    idM(t2)
    report("Distinct empty tables miss cache", calls == 2)


    -- 7. Callable tables accepted
    local callable = setmetatable({}, { __call = function(_, x) return x * 10 end })
    local callM    = CU.Memoize(callable)
    report("Callable table memoizes", callM(5) == 50)


    -- 8. Non-callable input errors loud
    local ok  = pcall(CU.Memoize, 42)
    report("Memoize on number errors", not ok)
    local ok2 = pcall(CU.Memoize, "string")
    report("Memoize on string errors", not ok2)


    -- 9. Consumer-supplied cache table works
    local sharedCache = {}
    calls = 0
    local function doubled(x) calls = calls + 1; return x * 2 end
    local d1 = CU.Memoize(doubled, sharedCache)
    d1(5)
    report("Shared cache: first call ran", calls == 1)
    local d2 = CU.Memoize(doubled, sharedCache)
    d2(5)
    report("Shared cache: second closure hits cache", calls == 1)
end
