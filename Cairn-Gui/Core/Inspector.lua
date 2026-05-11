--[[
Cairn-Gui-2.0 / Core / Inspector

Read-only introspection of the live widget tree. Per Decision 10B, the
library exposes data; the consumer (Forge_Inspector tab, debug snippets)
builds the visualization. Three primary entry points:

	Cairn.Inspector:Walk(rootCairn, fn)
	    Depth-first walk over rootCairn and every descendant. fn is called
	    as fn(widgetCairn, depth) for each one; depth is 0 for the root,
	    1 for direct children, and so on. fn may return false to stop the
	    walk early (returning nil/true continues).

	Cairn.Inspector:WalkAll(fn)
	    Walks every widget tree the inspector knows about. There's no
	    global "all live widgets" registry in Cairn-Gui-2.0 (Decision 3:
	    parent/child is authoritative), so WalkAll iterates the candidate
	    roots maintained by Acquire-time tracking (see Inspector:_track
	    below). Use this when you don't have a specific root and want to
	    find any widget.

	Cairn.Inspector:Find(x, y)
	    Topmost widget whose frame's rectangle contains (x, y) in screen
	    coordinates. Returns the widget.Cairn or nil. Hit-testing walks
	    every tracked widget; topmost is decided by frame strata + level
	    ordering.

	Cairn.Inspector:SelectByName(name)
	    First widget where _type == name. Returns the widget.Cairn or nil.
	    Useful for "show me the Window I just built" style debugging.

	widget.Cairn:Dump()
	    Returns a flat key/value table summarizing the widget's state.
	    Adds the method to Mixins.Base so every Cairn widget has it.

Tracking model
	Acquire creates the Cairn namespace and parents it to a container.
	The Inspector keeps a weak-keyed table of every widget.Cairn it has
	seen via Inspector:_track(cairn). Acquire calls _track on each new
	widget (instrumentation lives in Acquire.lua). Releases drop the
	widget naturally via the weak-key GC; we don't need an explicit
	untrack step.

Cairn-Gui-2.0/Core/Inspector (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Inspector requires Mixins/Base to load first; check Cairn.toc order")
end

local Inspector = {}

-- Weak-keyed set of every widget.Cairn we've ever seen. Released widgets
-- get GC'd naturally when no other references remain.
Inspector.tracked = lib._inspector and lib._inspector.tracked
                    or setmetatable({}, { __mode = "k" })

-- ----- Tracking ---------------------------------------------------------

function Inspector:_track(cairn)
	if type(cairn) ~= "table" then return end
	self.tracked[cairn] = true
end

-- ----- Walk -------------------------------------------------------------

local function walkInternal(cairn, fn, depth)
	if type(cairn) ~= "table" then return end
	local cont = fn(cairn, depth)
	if cont == false then return false end
	local children = cairn._children
	if type(children) == "table" then
		for i = 1, #children do
			local ok = walkInternal(children[i], fn, depth + 1)
			if ok == false then return false end
		end
	end
	return true
end

function Inspector:Walk(rootCairn, fn)
	if type(fn) ~= "function" then return end
	walkInternal(rootCairn, fn, 0)
end

-- WalkAll iterates every tracked root (a tracked widget whose _parent is
-- nil counts as a root). Visits every reachable descendant exactly once
-- because we guard via a "seen" set: a widget tracked AND reachable from
-- a parent tracked-root is only walked through its parent.
function Inspector:WalkAll(fn)
	if type(fn) ~= "function" then return end
	-- Identify roots: tracked widgets with no _parent.
	local roots = {}
	for cairn in pairs(self.tracked) do
		if not cairn._parent then
			roots[#roots + 1] = cairn
		end
	end
	-- Stable order isn't critical, but sort by _type so output is at
	-- least repeatable across walks for testing / display.
	table.sort(roots, function(a, b)
		return tostring(a._type or "") < tostring(b._type or "")
	end)
	for i = 1, #roots do
		local cont = walkInternal(roots[i], fn, 0)
		if cont == false then return end
	end
end

-- ----- Find (hit-test) --------------------------------------------------

local function rectContains(frame, x, y)
	if not frame or not frame.GetRect then return false end
	local left, bottom, w, h = frame:GetRect()
	if not (left and bottom and w and h) then return false end
	return x >= left and x <= left + w and y >= bottom and y <= bottom + h
end

-- Strata + level ordering: higher strata wins; within strata, higher
-- level wins. Returns a comparable score; higher means more on top.
local STRATA_RANK = {
	BACKGROUND        = 1,
	LOW               = 2,
	MEDIUM            = 3,
	HIGH              = 4,
	DIALOG            = 5,
	FULLSCREEN        = 6,
	FULLSCREEN_DIALOG = 7,
	TOOLTIP           = 8,
}

local function zScore(frame)
	if not (frame and frame.GetFrameStrata and frame.GetFrameLevel) then return 0 end
	local s = STRATA_RANK[frame:GetFrameStrata()] or 3
	local l = frame:GetFrameLevel() or 0
	-- Pack into a single comparable number: 1000 levels per strata bucket.
	return s * 10000 + l
end

function Inspector:Find(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end

	local best, bestZ
	for cairn in pairs(self.tracked) do
		local frame = cairn._frame
		if frame and frame.IsShown and frame:IsShown() and rectContains(frame, x, y) then
			local z = zScore(frame)
			if not best or z > bestZ then
				best, bestZ = cairn, z
			end
		end
	end
	return best
end

-- ----- SelectByName -----------------------------------------------------
-- First match by widget type (e.g. "Button"). For more precise lookup
-- (e.g. by an instance label), iterate via Walk and filter manually.

function Inspector:SelectByName(name)
	if type(name) ~= "string" then return nil end
	for cairn in pairs(self.tracked) do
		if cairn._type == name then return cairn end
	end
	return nil
end

-- ----- Per-widget Dump --------------------------------------------------
-- Mixed into Base so every widget.Cairn has it. Returns a flat table
-- summarizing the widget's state. Excludes the children array (use
-- Walk for tree views) and excludes the underlying frame (consumers can
-- read it from the widget directly if they need it).

function Base:Dump()
	local frame  = self._frame
	local left, bottom, w, h
	if frame and frame.GetRect then
		left, bottom, w, h = frame:GetRect()
	end
	return {
		type         = self._type,
		parentType   = self._parent and self._parent._type or nil,
		childCount   = self._children and #self._children or 0,
		shown        = frame and frame.IsShown and frame:IsShown() or false,
		strata       = frame and frame.GetFrameStrata and frame:GetFrameStrata() or nil,
		level        = frame and frame.GetFrameLevel  and frame:GetFrameLevel()  or nil,
		rect         = (left and bottom and w and h) and { left, bottom, w, h } or nil,
		intrinsic    = (function()
			-- `a and b()` truncates b's multi-return to one value, so we
			-- can't write `local iw, ih = self.GetIntrinsicSize and self:GetIntrinsicSize()`
			-- and expect both return values. Guard explicitly instead.
			if not self.GetIntrinsicSize then return nil end
			local iw, ih = self:GetIntrinsicSize()
			if iw or ih then return { iw, ih } end
			return nil
		end)(),
		hasCallbacks = self._cb ~= nil,
		hasLayout    = self._layout ~= nil,
		manualLayout = self._layoutManual and true or false,
	}
end

-- ----- Publish ----------------------------------------------------------

lib.Inspector  = Inspector
lib._inspector = Inspector
