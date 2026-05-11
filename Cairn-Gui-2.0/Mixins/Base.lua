--[[
Cairn-Gui-2.0 / Mixins / Base

The base mixin layered onto every widget at Acquire time. Per Decision 1
of the architecture, Cairn-Gui-2.0 widgets ARE Blizzard Frames; our
custom methods live on a `widget.Cairn` subtable to avoid colliding with
Blizzard method names. This file defines the contents of that subtable.

Inside any method below, `self` is widget.Cairn (the subtable), NOT the
frame. The underlying Frame is reachable via self._frame.

What this file provides:
	GetType()           -> registered type name (string)
	GetVersion()        -> "Cairn-Gui-2.0", MINOR
	GetFrame()          -> underlying Blizzard Frame
	GetIntrinsicSize()  -> nil, nil  ("no opinion"; layout assigns size)
	GetParent()         -> parent widget.Cairn or nil
	GetChildren()       -> array of child widget.Cairn (insertion order)
	OnAcquire(opts)     -> no-op default; widget defs override
	OnRelease()         -> no-op default; widget defs override
	Release()           -> children-first cascade, then OnRelease, then
	                       pool-return-or-hide
	Reparent(widget, newParent)
	                    -> move a child from this container (self) to a
	                       different container. Updates both the Cairn
	                       child registry and the Blizzard parent.

Internal helpers:
	_addChild(child)    -> register a child cairn in self._children
	_removeChild(child) -> remove a child cairn from self._children

Day 3 status: registry + cascade + pool wired. No theme/layout/event
plumbing yet (those land in later days).
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = {}

-- ----- Identity / introspection -----------------------------------------

function Base:GetType()
	return self._type
end

function Base:GetVersion()
	return MAJOR, MINOR
end

function Base:GetFrame()
	return self._frame
end

function Base:GetParent()
	return self._parent
end

function Base:GetChildren()
	return self._children
end

-- ----- Measurement protocol (Decision 4) --------------------------------
-- Default returns nil, nil meaning "I have no intrinsic size; layout
-- assigns me one." Widgets with content (Label, Button, etc.) override
-- this to compute their natural size from the rendered content.

function Base:GetIntrinsicSize()
	return nil, nil
end

-- ----- Lifecycle hooks --------------------------------------------------
-- Default no-ops. Widget definitions override these via def.mixin to do
-- type-specific setup and teardown.

function Base:OnAcquire(opts)  -- luacheck: ignore
end

function Base:OnRelease()
end

-- ----- Child registry (private) -----------------------------------------
-- Cairn-side parent/child tracking. Distinct from Blizzard's parent
-- relationship, which is for visibility and strata cascading. Per
-- Decision 3, the Cairn registry is authoritative for layout and Release.

function Base:_addChild(childCairn)
	self._children = self._children or {}
	self._children[#self._children + 1] = childCairn
	childCairn._parent = self
	-- Mark layout dirty if a strategy is bound. Guarded so the call is
	-- safe even if Layout.lua hasn't loaded (it's a no-op in that case).
	if self._invalidateLayout then
		self:_invalidateLayout()
	end
end

-- ----- Auto-invalidate parent layout (Decision 4 follow-up) ------------
-- Setters on widgets (SetText, SetVariant, SetPlaceholder, etc.) that
-- change a child's intrinsic size should call this so the parent's
-- layout strategy re-runs and re-anchors siblings around the new size.
-- Without this, Stack horizontal in particular silently keeps the old
-- width and longer text bleeds into adjacent widgets.
--
-- Called by widget mixins, NOT by consumer code. Safe no-op if the
-- widget has no parent (top-level Window) or the parent has no layout.

function Base:_invalidateParentLayout()
	local p = self._parent
	if p and p._invalidateLayout then
		p:_invalidateLayout()
	end
end

function Base:_removeChild(childCairn)
	if not self._children then return false end
	for i, c in ipairs(self._children) do
		if c == childCairn then
			table.remove(self._children, i)
			-- Only clear _parent if the back-reference still points at us.
			-- Reparent calls _removeChild on the OLD parent before adding
			-- to the NEW; if the new add already updated _parent, leave it.
			if childCairn._parent == self then
				childCairn._parent = nil
			end
			if self._invalidateLayout then
				self:_invalidateLayout()
			end
			return true
		end
	end
	return false
end

-- ----- Reparent ---------------------------------------------------------
-- Public API. Called as `oldContainer.Cairn:Reparent(widget, newContainer)`
-- per Decision 3. Detaches widget from this container's child registry
-- and attaches it to newContainer's. Also updates the Blizzard parent so
-- visibility and strata cascading follow.

function Base:Reparent(widget, newParent)
	if type(widget) ~= "table" or not widget.Cairn then
		error("Reparent: widget must be a Cairn-Gui-2.0 widget", 2)
	end
	if type(newParent) ~= "table" or not newParent.Cairn then
		error("Reparent: newParent must be a Cairn-Gui-2.0 widget", 2)
	end

	local childCairn       = widget.Cairn
	local newParentCairn   = newParent.Cairn

	-- Sanity warning if `self` (the caller) isn't actually the child's
	-- current parent. The operation still proceeds against whatever
	-- parent the registry currently records.
	if childCairn._parent ~= self then
		if lib._log and lib._log.Warn then
			lib._log:Warn("Reparent: widget _parent (%s) != caller (%s); detaching from registered parent",
				tostring(childCairn._parent and childCairn._parent._type or "nil"),
				tostring(self._type or "nil"))
		end
	end

	-- Detach from current registered parent (might be self, might be
	-- something else if Direct widget:SetParent was misused earlier).
	local oldParentCairn = childCairn._parent
	if oldParentCairn and oldParentCairn._removeChild then
		oldParentCairn:_removeChild(childCairn)
	end

	-- Attach to new parent.
	newParentCairn:_addChild(childCairn)

	-- Update the Blizzard parent. Combat-lockdown handling for secure
	-- widgets is a Decision 8 concern; not implemented Day 3.
	widget:SetParent(newParent)
end

-- ----- Release ----------------------------------------------------------
-- Children-first cascade per Decision 2. Order:
--   1. Release each child (recursively).
--   2. Detach this widget from its parent's child registry.
--   2.4. Fire "Release" event so consumer subscribers can run cleanup
--        BEFORE their event subscriptions are nuked in 2.5.
--   2.5. Clear event subscriptions.
--   3. Run OnRelease() lifecycle hook (single-method override).
--   4. If pooled, return to lib._pool[type] for later reuse; else hide.
--
-- Raw-children gotcha: WoW frames CAN'T destroy regions. So
-- :CreateFontString / :CreateTexture / CreateFrame("Frame", nil, parent,
-- "BackdropTemplate") children persist on a pooled frame after Release.
-- A consumer that creates fresh raw children on every Acquire will
-- accumulate stale ones (visible symptom: text overlay / ghosting after
-- pool recycle). The Cairn-internal pattern is stash-and-reuse:
--
--     if not cell._myFs then
--         cell._myFs = cell:CreateFontString(...)
--         cell._myFs:SetPoint(...)  -- one-time anchor
--     end
--     cell._myFs:SetText(currentValue)  -- update on every Acquire
--
-- See `Cairn-Gui-Widgets-Standard-2.0/Widgets/Button.lua`'s `_label`
-- for the canonical example. Released widget cairn-mixin children
-- (added via Acquire) cascade-release through Step 1 and don't need
-- this treatment.

function Base:Release()
	-- Step 1: cascade to children. Iterate a copy because each child's
	-- own Release will call _removeChild on us, mutating self._children.
	if self._children and #self._children > 0 then
		local copy = {}
		for i, c in ipairs(self._children) do copy[i] = c end
		for _, child in ipairs(copy) do
			if child.Release then child:Release() end
		end
	end
	self._children = {}

	-- Step 2: detach from parent's registry.
	if self._parent and self._parent._removeChild then
		self._parent:_removeChild(self)
	end
	self._parent = nil

	-- Step 2.4: fire "Release" event so consumer cleanup callbacks can
	-- run BEFORE Step 2.5 wipes the subscription registry. Lets multiple
	-- consumers register cleanup via widget.Cairn:On("Release", fn) without
	-- clobbering the single-method OnRelease() override below. No-op if no
	-- subscriber ever registered (Fire's no-op path skips the registry).
	if self.Fire then
		self:Fire("Release")
	end

	-- Step 2.5: clear event subscriptions so a pooled widget doesn't
	-- carry handlers from one owner into the next Acquire. self:Off()
	-- with no args nukes everything across every event. No-op if no
	-- registry was ever created.
	if self._cb and self.Off then
		self:Off()
	end

	-- Step 3: user lifecycle hook.
	self:OnRelease()

	-- Step 4: pool-return-or-hide.
	local def   = lib.widgets and lib.widgets[self._type]
	local frame = self._frame

	if def and def.pool then
		-- Reset state so the next Acquire gets a clean widget.
		if def.reset then
			local ok, err = pcall(def.reset, self)
			if not ok and lib._log and lib._log.Error then
				lib._log:Error("widget %q reset() errored: %s", tostring(self._type), tostring(err))
			end
		end
		-- Detach the frame from any parent so it doesn't keep refs alive,
		-- and hide it. Reparent and Show happen on next Acquire.
		if frame then
			if frame.Hide then frame:Hide() end
			if frame.SetParent then frame:SetParent(UIParent) end
			if frame.ClearAllPoints then frame:ClearAllPoints() end
		end
		-- Push to pool.
		lib._pool[self._type] = lib._pool[self._type] or {}
		table.insert(lib._pool[self._type], self)
	else
		-- Non-pooled: just hide the frame. The cairn table becomes
		-- orphaned; if the consumer dropped their reference, it gets
		-- garbage-collected. The frame stays around (Blizzard frames
		-- can't be destroyed) but is hidden and referenceless.
		if frame and frame.Hide then frame:Hide() end
	end
end

-- ----- Publish ----------------------------------------------------------

lib.Mixins      = lib.Mixins or {}
lib.Mixins.Base = Base
