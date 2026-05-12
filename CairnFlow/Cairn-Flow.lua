--[[
Cairn-Flow-1.0 — Control-flow primitives.

Four sub-namespaces under one MAJOR, all in this single file (mirrors
Cairn-Util's consolidated pattern):

    Sequencer  Linear-action-with-retry pipeline. Each step's `fn` is
               called repeatedly until it returns true; advancing then
               drives the next step. Reset/abort gates, completion +
               abort callbacks, manual drive via :Tick.

    Decision   Table-declarative decision tree. Nodes can be if/then/
               else or value-with-cases. :Evaluate walks root-to-leaf.

    FSM        Hierarchical state machine. Composite states with their
               own `initial` substate. Event dispatch bubbles leaf->root,
               first-match-wins. LCA-based transitions fire onExit
               walking up to LCA, onEnter walking down to the new leaf.
               Transition guards supported.

    Behavior   Game-AI behavior tree. Sequence / Selector / Parallel
               composites, Invert / RetryN / TimeLimit / Cooldown /
               AlwaysSucceed / AlwaysFail decorators, Action / Condition
               leaves, shared blackboard threaded through Tick.

Consumer surface:

    Cairn.Flow.Sequencer:New({ actions = {...}, ... })
    Cairn.Flow.Decision:New({ test = fn, if_true = ..., if_false = ... })
    Cairn.Flow.FSM:New({ initial = "Idle", states = {...} })
    Cairn.Flow.Behavior.Selector({ ... })   -- composite factories

Depends on Cairn-Util (Pcall.Call for error-isolated callback dispatch).
Depends on Cairn-Core for the _G.Cairn namespace bridge.

License: MIT. Author: ChronicTinkerer.
]]

local LIB_MAJOR = "Cairn-Flow-1.0"
local LIB_MINOR = 1

local Cairn_Flow = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Flow then return end


-- ============================================================================
-- Shared helper — safeCall
-- ============================================================================
-- One copy of the pcall+geterrorhandler wrapper for every consumer
-- callback across all four sub-namespaces. Routes errors through the
-- WoW global geterrorhandler so BugSack/BugGrabber catch them, while
-- keeping the dispatch loop alive. Falls back to a raw pcall when
-- Cairn-Util isn't loaded (standalone-embed scenario).
local CU = LibStub("Cairn-Util-1.0", true)
local function safeCall(context, fn, ...)
    if CU and CU.Pcall and CU.Pcall.Call then
        return CU.Pcall.Call(context, fn, ...)
    end
    if type(fn) ~= "function" then return true end
    return pcall(fn, ...)
end


-- ============================================================================
-- ============================================================================
-- == Sequencer
-- ============================================================================
-- ============================================================================
--
-- A linear list of actions, each driven by a `fn` that returns truthy when
-- the step is done. The Sequencer advances on truthy, retries on falsy,
-- and exposes optional reset/abort gates that the consumer's drive loop
-- checks every Tick.
--
-- Typical use shape:
--
--     local s = Cairn.Flow.Sequencer:New({
--         actions = {
--             { id = "wait-for-zone",  fn = function() return GetZoneText() == "Stormwind" end },
--             { id = "fly-to-mailbox", fn = function() return AtMailbox() end },
--             { id = "open-mail",      fn = function() OpenMail(); return true end },
--         },
--         resetCondition = function() return PlayerInCombat() end,
--         abortCondition = function() return PlayerDead() end,
--         onComplete     = function() print("done") end,
--         onAbort        = function(reason) print("aborted:", reason) end,
--     })
--     s:Tick()
--
-- Public API:
--     s:Tick()         drive one step: check gates, run current fn, advance if truthy
--     s:Next()         skip current step manually; returns true if there was a step to advance
--     s:Reset()        back to step 1, clear finished/aborted state
--     s:Abort(reason?) mark aborted, fire onAbort, stop responding to Tick
--     s:IsFinished()   true once the last step returned truthy (or :Abort was called)
--     s:IsAborted()    distinguish abort from clean completion
--     s:CurrentStep()  returns { id, index } for active step, or nil if finished/aborted
--
-- Open question (a) resolution: Tick is the canonical public driver.
-- Next is exposed too but represents a manual skip — bypasses gate
-- checks and the current step's fn. CurrentStep returns BOTH id and
-- index so consumers can branch on either.
--
-- Error isolation: every callback (action fn, resetCondition,
-- abortCondition, onComplete, onAbort) wrapped via safeCall. A
-- throwing callback reports through geterrorhandler and is treated as
-- falsy (action) / no-trigger (gate) / no-op (lifecycle).

local Sequencer = {}
Sequencer.__index = Sequencer
Cairn_Flow.Sequencer = Sequencer


local function seq_validateActions(actions)
    if type(actions) ~= "table" or #actions == 0 then
        error("Cairn-Flow.Sequencer:New: opts.actions must be a non-empty array", 3)
    end
    local seenIds = {}
    for i, step in ipairs(actions) do
        if type(step) ~= "table" then
            error(("Cairn-Flow.Sequencer:New: actions[%d] must be a table"):format(i), 3)
        end
        if type(step.fn) ~= "function" then
            error(("Cairn-Flow.Sequencer:New: actions[%d].fn must be a function"):format(i), 3)
        end
        if step.id ~= nil and type(step.id) ~= "string" then
            error(("Cairn-Flow.Sequencer:New: actions[%d].id must be a string when provided"):format(i), 3)
        end
        if step.id and seenIds[step.id] then
            error(("Cairn-Flow.Sequencer:New: duplicate action id %q at index %d"):format(step.id, i), 3)
        end
        if step.id then seenIds[step.id] = true end
    end
end

local function seq_callOptional(self, hookName, ...)
    -- WHY a single helper for optional lifecycle/gate calls: every
    -- callsite has the same shape (check the opts slot, route through
    -- safeCall with a context string that says which addon's seq +
    -- which hook fired).
    local fn = self._opts[hookName]
    if type(fn) ~= "function" then return end
    safeCall(
        ("Cairn-Flow.Sequencer(%s).%s"):format(self._name or "?", hookName),
        fn, ...)
end


function Sequencer:New(opts)
    if type(opts) ~= "table" then
        error("Cairn-Flow.Sequencer:New: opts must be a table", 2)
    end

    seq_validateActions(opts.actions)

    for _, field in ipairs({ "resetCondition", "abortCondition", "onComplete", "onAbort" }) do
        if opts[field] ~= nil and type(opts[field]) ~= "function" then
            error(("Cairn-Flow.Sequencer:New: opts.%s must be a function when provided"):format(field), 2)
        end
    end

    if opts.name ~= nil and type(opts.name) ~= "string" then
        error("Cairn-Flow.Sequencer:New: opts.name must be a string when provided", 2)
    end

    local self = setmetatable({}, Sequencer)
    self._opts        = opts
    self._actions     = opts.actions
    self._name        = opts.name
    self._index       = 1
    self._finished    = false
    self._aborted     = false
    self._abortReason = nil
    return self
end


function Sequencer:Tick()
    if self._finished or self._aborted then return end

    -- Abort gate (checked first; an abort beats a reset).
    if self._opts.abortCondition then
        local ok, triggered = safeCall(
            ("Cairn-Flow.Sequencer(%s).abortCondition"):format(self._name or "?"),
            self._opts.abortCondition)
        if ok and triggered then
            self:Abort("abortCondition")
            return
        end
    end

    -- Reset gate.
    if self._opts.resetCondition then
        local ok, triggered = safeCall(
            ("Cairn-Flow.Sequencer(%s).resetCondition"):format(self._name or "?"),
            self._opts.resetCondition)
        if ok and triggered then
            self:Reset()
            -- Fall through to action dispatch so the post-reset first
            -- step gets a chance to fire on the same Tick.
        end
    end

    -- Action dispatch.
    local step = self._actions[self._index]
    if not step then
        self._finished = true
        seq_callOptional(self, "onComplete")
        return
    end

    local ok, done = safeCall(
        ("Cairn-Flow.Sequencer(%s).actions[%d]%s")
            :format(self._name or "?", self._index,
                    step.id and (" id=" .. step.id) or ""),
        step.fn)

    if ok and done then
        self._index = self._index + 1
        if self._index > #self._actions then
            self._finished = true
            seq_callOptional(self, "onComplete")
        end
    end
end


function Sequencer:Next()
    if self._finished or self._aborted then return false end
    self._index = self._index + 1
    if self._index > #self._actions then
        self._finished = true
        seq_callOptional(self, "onComplete")
    end
    return true
end


function Sequencer:Reset()
    self._index       = 1
    self._finished    = false
    self._aborted     = false
    self._abortReason = nil
end


function Sequencer:Abort(reason)
    if self._aborted or self._finished then return end
    self._aborted     = true
    self._abortReason = reason
    seq_callOptional(self, "onAbort", reason)
end


function Sequencer:IsFinished() return self._finished == true end
function Sequencer:IsAborted()  return self._aborted == true end
function Sequencer:CurrentStep()
    if self._finished or self._aborted then return nil end
    local step = self._actions[self._index]
    if not step then return nil end
    return { id = step.id, index = self._index }
end


-- ============================================================================
-- ============================================================================
-- == Decision
-- ============================================================================
-- ============================================================================
--
-- A table-declarative decision tree. Nodes are either binary (test +
-- if_true / if_false) or multi-way (value + cases + default). Leaves
-- are returned as-is for nil / bool / string / number, called for
-- function (the function's return value is the leaf), or recursed
-- into for table. Trees compose naturally: any branch can itself be a
-- node.
--
-- Typical use shape (binary):
--
--     local d = Cairn.Flow.Decision:New({
--         test = function() return InCombat() end,
--         if_true  = "fight",
--         if_false = {
--             test = function() return AtTarget() end,
--             if_true  = "interact",
--             if_false = "move",
--         },
--     })
--     print(d:Evaluate())   -- "fight" | "interact" | "move"
--
-- Typical use shape (multi-way):
--
--     local d = Cairn.Flow.Decision:New({
--         value = function() return UnitClass("player") end,
--         cases = { WARRIOR = "tank", HUNTER = "rdps", PRIEST = "healer" },
--         default = "unknown",
--     })
--
-- Args threading: :Evaluate(...) — every test / value / function-leaf
-- in the tree receives those args in order. Useful as a lightweight
-- blackboard so the same tree can be reused across consumers without
-- closure-baked state.
--
-- Error handling: test / value / leaf functions wrapped via safeCall.
-- A throwing function reports through geterrorhandler and is treated
-- as: test = false (take if_false branch), value = nil (no cases
-- match -> default), leaf = nil.
--
-- Validation at :New: the full tree is walked at construction time so
-- malformed shapes surface up front rather than on first :Evaluate.

local Decision = {}
Decision.__index = Decision
Cairn_Flow.Decision = Decision


local dec_validateNode  -- forward declaration; mutual recursion

local function dec_validateBranch(branch, path)
    local t = type(branch)
    if t == "nil" or t == "boolean" or t == "string" or t == "number" or t == "function" then
        return
    end
    if t == "table" then
        dec_validateNode(branch, path)
        return
    end
    error(("Cairn-Flow.Decision:New: branch at %s has unsupported type %q"):format(path, t), 4)
end

function dec_validateNode(node, path)
    if type(node) ~= "table" then
        error(("Cairn-Flow.Decision:New: node at %s must be a table"):format(path), 4)
    end

    local hasTest  = node.test  ~= nil
    local hasValue = node.value ~= nil

    if hasTest and hasValue then
        error(("Cairn-Flow.Decision:New: node at %s has BOTH test and value (pick one)")
              :format(path), 4)
    end
    if not hasTest and not hasValue then
        error(("Cairn-Flow.Decision:New: node at %s has neither test nor value")
              :format(path), 4)
    end

    if hasTest then
        if type(node.test) ~= "function" then
            error(("Cairn-Flow.Decision:New: node at %s .test must be a function"):format(path), 4)
        end
        dec_validateBranch(node.if_true,  path .. ".if_true")
        dec_validateBranch(node.if_false, path .. ".if_false")
    else
        if type(node.value) ~= "function" then
            error(("Cairn-Flow.Decision:New: node at %s .value must be a function"):format(path), 4)
        end
        if type(node.cases) ~= "table" then
            error(("Cairn-Flow.Decision:New: node at %s .cases must be a table"):format(path), 4)
        end
        for caseKey, caseBranch in pairs(node.cases) do
            dec_validateBranch(caseBranch, path .. ".cases[" .. tostring(caseKey) .. "]")
        end
        dec_validateBranch(node.default, path .. ".default")
    end
end


function Decision:New(node)
    dec_validateNode(node, "root")
    local self = setmetatable({}, Decision)
    self._root = node
    return self
end


local dec_resolveBranch  -- forward; mutual recursion with dec_evaluateNode

local function dec_evaluateNode(node, ...)
    if node.test then
        local okCall, took = safeCall("Cairn-Flow.Decision.test", node.test, ...)
        if okCall and took then
            return dec_resolveBranch(node.if_true, ...)
        end
        return dec_resolveBranch(node.if_false, ...)
    end

    local okCall, key = safeCall("Cairn-Flow.Decision.value", node.value, ...)
    if not okCall then key = nil end

    local branch = node.cases[key]
    if branch == nil then branch = node.default end
    return dec_resolveBranch(branch, ...)
end

function dec_resolveBranch(branch, ...)
    local t = type(branch)
    if t == "table" then
        return dec_evaluateNode(branch, ...)
    end
    if t == "function" then
        local ok, result = safeCall("Cairn-Flow.Decision.leaf", branch, ...)
        if ok then return result end
        return nil
    end
    -- nil / bool / string / number — return as-is.
    return branch
end


function Decision:Evaluate(...)
    return dec_evaluateNode(self._root, ...)
end


-- ============================================================================
-- ============================================================================
-- == FSM (hierarchical state machine)
-- ============================================================================
-- ============================================================================
--
-- A declarative HSM. Composite states declare an `initial` child and
-- their own `states` subtree. The machine is always "in" one leaf
-- state, and that leaf plus every ancestor up to root are
-- simultaneously "active." Events bubble from leaf to root; the first
-- state with a matching `on` entry handles the transition.
--
-- Typical use shape:
--
--     local m = Cairn.Flow.FSM:New({
--         initial = "Idle",
--         states  = {
--             Idle = {
--                 on = { START = "Combat" },
--             },
--             Combat = {
--                 initial = "Engaging",
--                 on = { END_COMBAT = "Idle" },
--                 states = {
--                     Engaging = { on = { ENEMY_DEAD = "Looting" } },
--                     Looting  = { on = { LOOT_CLOSED = "Idle" } },
--                 },
--             },
--         },
--     })
--
-- Public API:
--     m:Send(event, ...)     bubble event from active leaf to root, first match wins
--     m:GetState()           name of the active leaf
--     m:GetPath()            root-to-leaf array of state names
--     m:IsIn(name)           true if name is the leaf OR any ancestor
--     m:OnTransition(fn)     subscribe; returns an unsub closure
--
-- Transition entry shapes:
--     EVENT = "TargetStateName"             unconditional
--     EVENT = { target = "X", guard = fn }  conditional; guard returning false
--                                            declines and bubbling continues
--
-- Decision B locked: transition guards supported (declining bubbles).
--
-- Open question (b) resolution: onExit / onEnter receive (event, ...);
-- guard receives (...) only; OnTransition fn receives (oldLeaf,
-- newLeaf, event, ...). At the :New-time initial entry, event=nil.
--
-- LCA-based transition: from old leaf up to (but NOT including) LCA
-- fire onExit; from one-below-LCA down to target fire onEnter; if
-- target is composite, follow its `initial` chain into the deepest
-- leaf firing onEnter at every level.
--
-- Error isolation: every callback (onEnter, onExit, guard, observer)
-- wrapped via safeCall. Throwing guard treated as decline; throwing
-- onExit/onEnter does NOT abort the transition.
--
-- Reference: Miro Samek HSM design + David Harel statecharts.

local FSM = {}
FSM.__index = FSM
Cairn_Flow.FSM = FSM


-- A synthetic root wraps the consumer's top-level states so the LCA
-- walk has a guaranteed common ancestor. Stripped from GetPath output.
local SYNTHETIC_ROOT_NAME = "__cairn_flow_root__"

local fsm_buildState  -- forward declaration; mutual recursion

local function fsm_buildState(stateName, stateDef, parent, byName)
    if type(stateDef) ~= "table" then
        error(("Cairn-Flow.FSM:New: state %q definition must be a table"):format(stateName), 3)
    end
    if byName[stateName] then
        error(("Cairn-Flow.FSM:New: duplicate state name %q"):format(stateName), 3)
    end

    if stateDef.onEnter ~= nil and type(stateDef.onEnter) ~= "function" then
        error(("Cairn-Flow.FSM:New: state %q onEnter must be a function"):format(stateName), 3)
    end
    if stateDef.onExit ~= nil and type(stateDef.onExit) ~= "function" then
        error(("Cairn-Flow.FSM:New: state %q onExit must be a function"):format(stateName), 3)
    end
    if stateDef.on ~= nil and type(stateDef.on) ~= "table" then
        error(("Cairn-Flow.FSM:New: state %q .on must be a table"):format(stateName), 3)
    end
    if stateDef.on then
        for event, entry in pairs(stateDef.on) do
            if type(event) ~= "string" or event == "" then
                error(("Cairn-Flow.FSM:New: state %q .on has non-string event key"):format(stateName), 3)
            end
            local et = type(entry)
            if et == "string" then
                if entry == "" then
                    error(("Cairn-Flow.FSM:New: state %q .on[%q] target is empty string"):format(stateName, event), 3)
                end
            elseif et == "table" then
                if type(entry.target) ~= "string" or entry.target == "" then
                    error(("Cairn-Flow.FSM:New: state %q .on[%q].target must be a non-empty string"):format(stateName, event), 3)
                end
                if entry.guard ~= nil and type(entry.guard) ~= "function" then
                    error(("Cairn-Flow.FSM:New: state %q .on[%q].guard must be a function"):format(stateName, event), 3)
                end
            else
                error(("Cairn-Flow.FSM:New: state %q .on[%q] must be a string or table"):format(stateName, event), 3)
            end
        end
    end

    local node = {
        name     = stateName,
        parent   = parent,
        depth    = parent and (parent.depth + 1) or 0,
        onEnter  = stateDef.onEnter,
        onExit   = stateDef.onExit,
        on       = stateDef.on,
        children = nil,
        childMap = nil,
        initial  = nil,
    }
    byName[stateName] = node

    local hasChildren = stateDef.states ~= nil or stateDef.initial ~= nil
    if hasChildren then
        if type(stateDef.states) ~= "table" then
            error(("Cairn-Flow.FSM:New: composite state %q .states must be a table"):format(stateName), 3)
        end
        if type(stateDef.initial) ~= "string" or stateDef.initial == "" then
            error(("Cairn-Flow.FSM:New: composite state %q .initial must be a non-empty string"):format(stateName), 3)
        end
        node.children = {}
        node.childMap = {}
        node.initial  = stateDef.initial

        for childName, childDef in pairs(stateDef.states) do
            local childNode = fsm_buildState(childName, childDef, node, byName)
            node.children[#node.children + 1] = childNode
            node.childMap[childName] = childNode
        end

        if not node.childMap[node.initial] then
            error(("Cairn-Flow.FSM:New: composite state %q .initial = %q references unknown child state"):format(
                stateName, node.initial), 3)
        end
    end

    return node
end


local function fsm_validateTargets(root, byName)
    local function visit(node)
        if node.on then
            for event, entry in pairs(node.on) do
                local target = type(entry) == "string" and entry or entry.target
                if not byName[target] then
                    error(("Cairn-Flow.FSM:New: state %q .on[%q] target %q is not a known state name"):format(
                        node.name, event, target), 3)
                end
            end
        end
        if node.children then
            for _, child in ipairs(node.children) do visit(child) end
        end
    end
    visit(root)
end


local function fsm_pathOf(node)
    local rev = {}
    while node do
        rev[#rev + 1] = node
        node = node.parent
    end
    local out, n = {}, #rev
    for i = n, 1, -1 do out[#out + 1] = rev[i] end
    return out
end


local function fsm_lcaOf(a, b)
    while a.depth > b.depth do a = a.parent end
    while b.depth > a.depth do b = b.parent end
    while a ~= b do
        a = a.parent
        b = b.parent
    end
    return a
end


local function fsm_resolveLeaf(node)
    while node.children do
        node = node.childMap[node.initial]
    end
    return node
end


function FSM:New(opts)
    if type(opts) ~= "table" then
        error("Cairn-Flow.FSM:New: opts must be a table", 2)
    end
    if type(opts.states) ~= "table" then
        error("Cairn-Flow.FSM:New: opts.states must be a table", 2)
    end
    if type(opts.initial) ~= "string" or opts.initial == "" then
        error("Cairn-Flow.FSM:New: opts.initial must be a non-empty string", 2)
    end

    local byName = {}
    local rootDef = {
        initial = opts.initial,
        states  = opts.states,
    }
    local root = fsm_buildState(SYNTHETIC_ROOT_NAME, rootDef, nil, byName)
    byName[SYNTHETIC_ROOT_NAME] = nil

    fsm_validateTargets(root, byName)

    local self = setmetatable({}, FSM)
    self._root      = root
    self._byName    = byName
    self._observers = {}
    self._active    = nil

    local leaf = fsm_resolveLeaf(root)
    local entryPath = fsm_pathOf(leaf)
    for i = 1, #entryPath do
        local node = entryPath[i]
        if node ~= root and node.onEnter then
            safeCall(("Cairn-Flow.FSM(%s).onEnter"):format(node.name), node.onEnter, nil)
        end
    end
    self._active = leaf
    return self
end


local function fsm_performTransition(self, targetNode, event, ...)
    local oldLeaf = self._active
    local lca     = fsm_lcaOf(oldLeaf, targetNode)

    -- Walk OLD up to (excluding) LCA firing onExit.
    do
        local cur = oldLeaf
        while cur ~= lca do
            if cur.onExit then
                safeCall(("Cairn-Flow.FSM(%s).onExit"):format(cur.name), cur.onExit, event, ...)
            end
            cur = cur.parent
        end
    end

    -- Walk DOWN from one-below-LCA to target firing onEnter.
    local targetPath = fsm_pathOf(targetNode)
    local startIdx
    for i = 1, #targetPath do
        if targetPath[i] == lca then
            startIdx = i + 1
            break
        end
    end
    startIdx = startIdx or 1

    for i = startIdx, #targetPath do
        local node = targetPath[i]
        if node.onEnter then
            safeCall(("Cairn-Flow.FSM(%s).onEnter"):format(node.name), node.onEnter, event, ...)
        end
    end

    -- If target is composite, descend its initial chain firing onEnter.
    local finalLeaf = fsm_resolveLeaf(targetNode)
    if finalLeaf ~= targetNode then
        local descent = fsm_pathOf(finalLeaf)
        local descStart = nil
        for i = 1, #descent do
            if descent[i] == targetNode then descStart = i + 1; break end
        end
        if descStart then
            for i = descStart, #descent do
                local node = descent[i]
                if node.onEnter then
                    safeCall(("Cairn-Flow.FSM(%s).onEnter"):format(node.name), node.onEnter, event, ...)
                end
            end
        end
    end

    self._active = finalLeaf

    -- Observers: snapshot before iterating so an unsub mid-fire doesn't
    -- skip neighbors.
    local snap, n = {}, 0
    for _, fn in ipairs(self._observers) do n = n + 1; snap[n] = fn end
    for i = 1, n do
        safeCall("Cairn-Flow.FSM.observer",
            snap[i], oldLeaf.name, finalLeaf.name, event, ...)
    end
end


function FSM:Send(event, ...)
    if type(event) ~= "string" or event == "" then
        error("Cairn-Flow.FSM:Send: event must be a non-empty string", 2)
    end

    local cur = self._active
    while cur do
        if cur.on then
            local entry = cur.on[event]
            if entry then
                local targetName
                local guardOk = true

                if type(entry) == "string" then
                    targetName = entry
                else
                    targetName = entry.target
                    if entry.guard then
                        local ok, took = safeCall(
                            ("Cairn-Flow.FSM(%s).on[%s].guard"):format(cur.name, event),
                            entry.guard, ...)
                        guardOk = ok and took and true or false
                    end
                end

                if guardOk then
                    local targetNode = self._byName[targetName]
                    fsm_performTransition(self, targetNode, event, ...)
                    return
                end
                -- Guard declined: continue bubbling.
            end
        end
        cur = cur.parent
    end
    -- No handler found; event is dropped (no error).
end


function FSM:GetState()
    return self._active.name
end


function FSM:GetPath()
    local path = fsm_pathOf(self._active)
    local out = {}
    for i = 1, #path do
        if path[i] ~= self._root then
            out[#out + 1] = path[i].name
        end
    end
    return out
end


function FSM:IsIn(name)
    if type(name) ~= "string" then return false end
    local cur = self._active
    while cur do
        if cur.name == name then return true end
        cur = cur.parent
    end
    return false
end


function FSM:OnTransition(fn)
    if type(fn) ~= "function" then
        error("Cairn-Flow.FSM:OnTransition: fn must be a function", 2)
    end
    self._observers[#self._observers + 1] = fn
    return function()
        for i, v in ipairs(self._observers) do
            if v == fn then
                table.remove(self._observers, i)
                return
            end
        end
    end
end


-- ============================================================================
-- ============================================================================
-- == Behavior (game-AI behavior tree)
-- ============================================================================
-- ============================================================================
--
-- Standard hierarchical decision-and-execution structure from game AI.
-- A tree of nodes that, on every :Tick, returns one of three statuses:
-- Success, Failure, or Running.
--
-- Public surface:
--
--     BT = Cairn.Flow.Behavior
--     BT.Status.Success | Failure | Running     -- string sentinels
--
--     -- Composites
--     BT.Sequence({ a, b, c })                  -- AND. Failure on first F. Resume from R.
--     BT.Selector({ a, b, c })                  -- OR.  Success on first S. Resume from R.
--     BT.Parallel({ a, b, c }, {
--         successThreshold = 2,
--         failureThreshold = 2,
--     })                                        -- tick all; thresholds default to (#children, 1).
--
--     -- Decorators (wrap a single child)
--     BT.Invert(child)                          -- S<->F; R passes.
--     BT.RetryN(child, n)                       -- retry on Failure up to n times.
--     BT.TimeLimit(child, secs, nowFn?)         -- Failure if not done in secs from first tick.
--     BT.Cooldown(child, secs, nowFn?)          -- after Success, locks to Failure for secs.
--     BT.AlwaysSucceed(child)                   -- terminal -> Success; R passes.
--     BT.AlwaysFail(child)                      -- terminal -> Failure; R passes.
--
--     -- Leaves
--     BT.Action(function(blackboard, ...) return BT.Status.Success end)
--     BT.Condition(function(blackboard, ...) return true end)
--
-- root:Tick(blackboard, ...) drives one tick. The blackboard (any
-- table — Decision A locked) and additional context args reach every
-- Action and Condition unchanged. root:Reset() cascades through the
-- subtree clearing running indices, retry counters, time-limit clocks,
-- cooldown timestamps.
--
-- Sequence and Selector remember the index of the Running child and
-- resume there next Tick instead of walking from the start. Terminal
-- status clears the resume index.
--
-- Error isolation: Action / Condition wrapped via safeCall. Throwing
-- leaf -> Failure routed to geterrorhandler. Composites and
-- decorators have no consumer code to throw.
--
-- Status validation: an Action returning something other than the
-- three status strings is treated as Failure (without routing
-- through geterrorhandler — the leaf didn't throw, just mis-returned).
--
-- Open question (c) deferred: partial-tick state across /reload is
-- not serialized; consumers should treat the tree as ephemeral.

local BT = {}
Cairn_Flow.Behavior = BT

BT.Status = {
    Success = "Success",
    Failure = "Failure",
    Running = "Running",
}
local S_SUCCESS = BT.Status.Success
local S_FAILURE = BT.Status.Failure
local S_RUNNING = BT.Status.Running


-- Time helper — abstracts GetTime() so test environments without WoW
-- can substitute a mock clock via an optional `nowFn` arg on TimeLimit
-- and Cooldown. Default falls back to os.clock if GetTime is missing.
local defaultNow = _G.GetTime or os.clock or function() return 0 end


local function bt_isNode(v)
    return type(v) == "table" and type(v.Tick) == "function"
end

local function bt_validateChildren(children, kind)
    if type(children) ~= "table" or #children == 0 then
        error(("Cairn-Flow.Behavior.%s: children must be a non-empty array"):format(kind), 3)
    end
    for i, c in ipairs(children) do
        if not bt_isNode(c) then
            error(("Cairn-Flow.Behavior.%s: children[%d] must be a BT node"):format(kind, i), 3)
        end
    end
end

local function bt_validateChild(child, kind)
    if not bt_isNode(child) then
        error(("Cairn-Flow.Behavior.%s: child must be a BT node"):format(kind), 3)
    end
end


-- ----- Composites ----------------------------------------------------

local SequenceMT = { __index = {} }
function SequenceMT.__index:Tick(blackboard, ...)
    local children = self._children
    local startIdx = self._runningIdx or 1
    for i = startIdx, #children do
        local status = children[i]:Tick(blackboard, ...)
        if status == S_FAILURE then
            self._runningIdx = nil
            return S_FAILURE
        elseif status == S_RUNNING then
            self._runningIdx = i
            return S_RUNNING
        end
    end
    self._runningIdx = nil
    return S_SUCCESS
end
function SequenceMT.__index:Reset()
    self._runningIdx = nil
    for _, c in ipairs(self._children) do c:Reset() end
end

function BT.Sequence(children)
    bt_validateChildren(children, "Sequence")
    return setmetatable({ _children = children }, SequenceMT)
end


local SelectorMT = { __index = {} }
function SelectorMT.__index:Tick(blackboard, ...)
    local children = self._children
    local startIdx = self._runningIdx or 1
    for i = startIdx, #children do
        local status = children[i]:Tick(blackboard, ...)
        if status == S_SUCCESS then
            self._runningIdx = nil
            return S_SUCCESS
        elseif status == S_RUNNING then
            self._runningIdx = i
            return S_RUNNING
        end
    end
    self._runningIdx = nil
    return S_FAILURE
end
function SelectorMT.__index:Reset()
    self._runningIdx = nil
    for _, c in ipairs(self._children) do c:Reset() end
end

function BT.Selector(children)
    bt_validateChildren(children, "Selector")
    return setmetatable({ _children = children }, SelectorMT)
end


local ParallelMT = { __index = {} }
function ParallelMT.__index:Tick(blackboard, ...)
    local children     = self._children
    local successCount = 0
    local failureCount = 0
    for i = 1, #children do
        local status = children[i]:Tick(blackboard, ...)
        if status == S_SUCCESS then
            successCount = successCount + 1
        elseif status == S_FAILURE then
            failureCount = failureCount + 1
        end
    end
    if successCount >= self._successThreshold then return S_SUCCESS end
    if failureCount >= self._failureThreshold then return S_FAILURE end
    return S_RUNNING
end
function ParallelMT.__index:Reset()
    for _, c in ipairs(self._children) do c:Reset() end
end

function BT.Parallel(children, opts)
    bt_validateChildren(children, "Parallel")
    opts = opts or {}
    local n    = #children
    local succ = opts.successThreshold or n
    local fail = opts.failureThreshold or 1
    if type(succ) ~= "number" or succ < 1 or succ > n then
        error(("Cairn-Flow.Behavior.Parallel: successThreshold must be 1..%d (got %s)"):format(
            n, tostring(succ)), 2)
    end
    if type(fail) ~= "number" or fail < 1 or fail > n then
        error(("Cairn-Flow.Behavior.Parallel: failureThreshold must be 1..%d (got %s)"):format(
            n, tostring(fail)), 2)
    end
    return setmetatable({
        _children         = children,
        _successThreshold = succ,
        _failureThreshold = fail,
    }, ParallelMT)
end


-- ----- Decorators ----------------------------------------------------

local InvertMT = { __index = {} }
function InvertMT.__index:Tick(blackboard, ...)
    local s = self._child:Tick(blackboard, ...)
    if s == S_SUCCESS then return S_FAILURE end
    if s == S_FAILURE then return S_SUCCESS end
    return S_RUNNING
end
function InvertMT.__index:Reset() self._child:Reset() end

function BT.Invert(child)
    bt_validateChild(child, "Invert")
    return setmetatable({ _child = child }, InvertMT)
end


local RetryNMT = { __index = {} }
function RetryNMT.__index:Tick(blackboard, ...)
    local s = self._child:Tick(blackboard, ...)
    if s == S_SUCCESS then
        self._failures = 0
        return S_SUCCESS
    end
    if s == S_FAILURE then
        self._failures = (self._failures or 0) + 1
        if self._failures <= self._maxRetries then
            self._child:Reset()
            return S_RUNNING
        end
        self._failures = 0
        return S_FAILURE
    end
    return S_RUNNING
end
function RetryNMT.__index:Reset()
    self._failures = 0
    self._child:Reset()
end

function BT.RetryN(child, n)
    bt_validateChild(child, "RetryN")
    if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then
        error("Cairn-Flow.Behavior.RetryN: n must be a non-negative integer", 2)
    end
    return setmetatable({ _child = child, _maxRetries = n }, RetryNMT)
end


local TimeLimitMT = { __index = {} }
function TimeLimitMT.__index:Tick(blackboard, ...)
    local now = self._now()
    if not self._start then self._start = now end
    if now - self._start > self._limit then
        self._start = nil
        self._child:Reset()
        return S_FAILURE
    end
    local s = self._child:Tick(blackboard, ...)
    if s ~= S_RUNNING then self._start = nil end
    return s
end
function TimeLimitMT.__index:Reset()
    self._start = nil
    self._child:Reset()
end

function BT.TimeLimit(child, secs, nowFn)
    bt_validateChild(child, "TimeLimit")
    if type(secs) ~= "number" or secs <= 0 then
        error("Cairn-Flow.Behavior.TimeLimit: secs must be a positive number", 2)
    end
    if nowFn ~= nil and type(nowFn) ~= "function" then
        error("Cairn-Flow.Behavior.TimeLimit: nowFn must be a function when provided", 2)
    end
    return setmetatable({
        _child = child,
        _limit = secs,
        _now   = nowFn or defaultNow,
    }, TimeLimitMT)
end


local CooldownMT = { __index = {} }
function CooldownMT.__index:Tick(blackboard, ...)
    local now = self._now()
    if self._coolingUntil then
        if now < self._coolingUntil then
            return S_FAILURE
        end
        self._coolingUntil = nil
    end
    local s = self._child:Tick(blackboard, ...)
    if s == S_SUCCESS then
        self._coolingUntil = now + self._secs
    end
    return s
end
function CooldownMT.__index:Reset()
    self._coolingUntil = nil
    self._child:Reset()
end

function BT.Cooldown(child, secs, nowFn)
    bt_validateChild(child, "Cooldown")
    if type(secs) ~= "number" or secs <= 0 then
        error("Cairn-Flow.Behavior.Cooldown: secs must be a positive number", 2)
    end
    if nowFn ~= nil and type(nowFn) ~= "function" then
        error("Cairn-Flow.Behavior.Cooldown: nowFn must be a function when provided", 2)
    end
    return setmetatable({
        _child = child,
        _secs  = secs,
        _now   = nowFn or defaultNow,
    }, CooldownMT)
end


local AlwaysSucceedMT = { __index = {} }
function AlwaysSucceedMT.__index:Tick(blackboard, ...)
    local s = self._child:Tick(blackboard, ...)
    if s == S_RUNNING then return S_RUNNING end
    return S_SUCCESS
end
function AlwaysSucceedMT.__index:Reset() self._child:Reset() end

function BT.AlwaysSucceed(child)
    bt_validateChild(child, "AlwaysSucceed")
    return setmetatable({ _child = child }, AlwaysSucceedMT)
end


local AlwaysFailMT = { __index = {} }
function AlwaysFailMT.__index:Tick(blackboard, ...)
    local s = self._child:Tick(blackboard, ...)
    if s == S_RUNNING then return S_RUNNING end
    return S_FAILURE
end
function AlwaysFailMT.__index:Reset() self._child:Reset() end

function BT.AlwaysFail(child)
    bt_validateChild(child, "AlwaysFail")
    return setmetatable({ _child = child }, AlwaysFailMT)
end


-- ----- Leaves --------------------------------------------------------

local ActionMT = { __index = {} }
function ActionMT.__index:Tick(blackboard, ...)
    local ok, status = safeCall("Cairn-Flow.Behavior.Action", self._fn, blackboard, ...)
    if not ok then return S_FAILURE end
    if status == S_SUCCESS or status == S_FAILURE or status == S_RUNNING then
        return status
    end
    return S_FAILURE
end
function ActionMT.__index:Reset() end

function BT.Action(fn)
    if type(fn) ~= "function" then
        error("Cairn-Flow.Behavior.Action: fn must be a function", 2)
    end
    return setmetatable({ _fn = fn }, ActionMT)
end


local ConditionMT = { __index = {} }
function ConditionMT.__index:Tick(blackboard, ...)
    local ok, result = safeCall("Cairn-Flow.Behavior.Condition", self._fn, blackboard, ...)
    if not ok then return S_FAILURE end
    if result then return S_SUCCESS end
    return S_FAILURE
end
function ConditionMT.__index:Reset() end

function BT.Condition(fn)
    if type(fn) ~= "function" then
        error("Cairn-Flow.Behavior.Condition: fn must be a function", 2)
    end
    return setmetatable({ _fn = fn }, ConditionMT)
end


return Cairn_Flow
