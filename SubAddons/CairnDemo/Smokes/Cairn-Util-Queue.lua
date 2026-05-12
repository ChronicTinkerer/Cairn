-- Cairn-Util-Queue smoke. Wrapped for the CairnDemo runner.
--
-- Coverage: sub-namespace attaches to Cairn-Util; :New / :Push / :Pop /
-- :Peek / :Size / :IsEmpty work in isolation; FIFO order preserved
-- across many operations; Pop on empty returns nil; shrink-on-pop
-- doesn't break sequential behavior (push 2000, pop 1500, push 500
-- more, pop all — final order matches insertion order).

_G.CairnDemo       = _G.CairnDemo or {}
_G.CairnDemo.Smokes = _G.CairnDemo.Smokes or {}

_G.CairnDemo.Smokes["Cairn-Util-Queue"] = function(report)
    -- 1. Library + sub-namespace surface
    local CU = LibStub and LibStub("Cairn-Util-1.0", true)
    report("Cairn-Util is loaded under LibStub", CU ~= nil)
    if not CU then return end

    report("CU.Queue table exists",      type(CU.Queue) == "table")
    report("CU.Queue.New is a function", type(CU.Queue and CU.Queue.New) == "function")

    if not (CU.Queue and type(CU.Queue.New) == "function") then return end


    -- 2. Empty queue surface
    local q = CU.Queue:New()
    report("New returns a table",         type(q) == "table")
    report("IsEmpty on new queue",        q:IsEmpty() == true)
    report("Size 0 on new queue",         q:Size() == 0)
    report("Peek empty returns nil",      q:Peek() == nil)
    report("Pop empty returns nil",       q:Pop() == nil)


    -- 3. Push / Pop FIFO ordering
    q:Push("a")
    q:Push("b")
    q:Push("c")
    report("Size after 3 pushes",         q:Size() == 3)
    report("IsEmpty false after pushes",  not q:IsEmpty())
    report("Peek shows head",             q:Peek() == "a")
    report("Peek doesn't remove",         q:Size() == 3)
    report("Pop returns head",            q:Pop() == "a")
    report("Pop again",                   q:Pop() == "b")
    report("Size 1 after two pops",       q:Size() == 1)
    report("Pop last",                    q:Pop() == "c")
    report("Empty after draining",        q:IsEmpty() and q:Size() == 0)
    report("Pop after drain returns nil", q:Pop() == nil)


    -- 4. Interleaved push/pop preserves order
    q:Push(1)
    q:Push(2)
    report("Interleave: pop 1",       q:Pop() == 1)
    q:Push(3)
    report("Interleave: pop 2",       q:Pop() == 2)
    report("Interleave: pop 3",       q:Pop() == 3)
    report("Interleave: empty after", q:IsEmpty())


    -- 5. Large run that exercises shrink-on-pop
    local big = CU.Queue:New()
    for i = 1, 2000 do big:Push(i) end
    report("After 2000 pushes Size==2000", big:Size() == 2000)

    local sumPopped = 0
    for i = 1, 1500 do sumPopped = sumPopped + big:Pop() end
    report("Popped first 1500 in order",  sumPopped == 1125750)
    report("Size 500 after popping 1500", big:Size() == 500)

    for i = 2001, 2500 do big:Push(i) end
    report("After 500 more pushes Size==1000", big:Size() == 1000)

    local lastPopped, drainErrors = 1500, 0
    for i = 1, 1000 do
        local v = big:Pop()
        if v ~= lastPopped + 1 then drainErrors = drainErrors + 1 end
        lastPopped = v
    end
    report("FIFO order across shrink", drainErrors == 0)
    report("Final value popped 2500", lastPopped == 2500)
    report("Empty after full drain",  big:IsEmpty())
end
