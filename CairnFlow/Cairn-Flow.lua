--[[
Cairn-Flow-1.0 — Control-flow primitives.

Four sub-namespaces under one MAJOR:

    Sequencer  Linear-action-with-retry pipeline. Each step's `fn` is
               called repeatedly until it returns true; advancing then
               drives the next step. Reset/abort gates, completion +
               abort callbacks, manual drive via :Tick.
    FSM        Hierarchical state machine. Composite states with their
               own `initial` substate. Event dispatch bubbles leaf→root,
               first-match-wins. LCA-based transitions fire onExit
               walking up to LCA, onEnter walking down to the new leaf.
               Transition guards supported.
    Decision   Table-declarative decision tree. Nodes can be if/then/
               else or value-with-cases. :Evaluate walks root-to-leaf.
    Behavior   Game-AI behavior tree. Sequence / Selector / Parallel
               composites, Invert / RetryN / TimeLimit / Cooldown /
               AlwaysSucceed / AlwaysFail decorators, Action / Condition
               leaves, shared blackboard threaded through Tick.

Consumer surface:
    Cairn.Flow.Sequencer:New({ actions = {...}, ... })
    Cairn.Flow.FSM:New({ initial = "Idle", states = {...} })
    Cairn.Flow.Decision:New({ test = fn, if_true = ..., if_false = ... })
    Cairn.Flow.Behavior.Selector({ ... })  -- composite factories

Each sub-namespace lives in its own sibling file (Cairn-Flow-Sequencer.lua,
Cairn-Flow-FSM.lua, Cairn-Flow-Decision.lua, Cairn-Flow-Behavior.lua) and
attaches to this lib's table at load time. The main file is just the
LibStub registration + sub-namespace slot prep.

Depends on Cairn-Util (Pcall.Call for error-isolated leaf execution).
Depends on Cairn-Core for the _G.Cairn namespace bridge.

License: MIT. Author: ChronicTinkerer.
]]

local LIB_MAJOR = "Cairn-Flow-1.0"
local LIB_MINOR = 1

local Cairn_Flow = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Flow then return end


-- Sub-namespace slots. Sibling files populate these on load. We pre-
-- create the tables here so the slots are non-nil even if a sub-
-- namespace file is missing from the TOC (consumers see "function is
-- nil" rather than "Sequencer is nil", which is a clearer error
-- shape).
Cairn_Flow.Sequencer = Cairn_Flow.Sequencer or {}
Cairn_Flow.FSM       = Cairn_Flow.FSM       or {}
Cairn_Flow.Decision  = Cairn_Flow.Decision  or {}
Cairn_Flow.Behavior  = Cairn_Flow.Behavior  or {}


return Cairn_Flow
