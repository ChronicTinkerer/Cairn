--[[
Cairn-Gui-2.0 / Core / Acquire

Public widget registration and acquisition API.

	Cairn.Gui:RegisterWidget(name, def)
		Register a widget type. `def` is a table:
			frameType = "Frame" | "Button" | etc. (Blizzard CreateFrame type;
			            default "Frame")
			template  = "BackdropTemplate" or comma-separated template list,
			            optional
			mixin     = table of methods to add to widget.Cairn (these layer
			            on top of Mixins.Base; type-specific methods can
			            override Base defaults)
			pool      = boolean, default false. When true, Released widgets
			            of this type are recycled by future Acquire calls.
			reset     = function(cairn) called on a pool-recycled widget
			            before it is handed back to the consumer. Use it
			            to clear residual state (text, colors, hooks, etc.).

	Cairn.Gui:Acquire(name, parent, opts)
		Create or recycle a widget of the registered type. Returns the
		underlying Blizzard Frame, with widget.Cairn populated as the
		namespace for our custom methods.

		parent  defaults to UIParent. If parent has its own widget.Cairn,
		        the new widget is also registered as a Cairn child of it.
		opts    arbitrary options table; merged into widget.Cairn._opts
		        and passed to OnAcquire(opts).

Day 3 status: pool wired. Parent/child registry wired. No theme/layout/
event plumbing yet.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

-- The base mixin must be loaded before this file. It's the foundation
-- every widget shares. If it's missing the .toc load order is wrong.
local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/Acquire requires Mixins/Base to load first; check Cairn.toc order")
end

-- ---------- RegisterWidget ----------------------------------------------

function lib:RegisterWidget(name, def)
	if type(name) ~= "string" or name == "" then
		error("RegisterWidget: name must be a non-empty string", 2)
	end
	if type(def) ~= "table" then
		error("RegisterWidget: def must be a table", 2)
	end
	if self.widgets[name] and lib._log and lib._log.Debug then
		-- Re-registration during dev (e.g., /reload after edits) is
		-- expected. Last-write-wins, with a debug log so the author
		-- knows their type was redefined.
		lib._log:Debug("RegisterWidget: redefining %q", name)
	end

	-- Normalize the def. Mutating in place is fine; callers don't keep
	-- the original around as immutable.
	def.frameType = def.frameType or "Frame"
	def.template  = def.template
	def.mixin     = def.mixin or {}
	def.pool      = def.pool == true
	def.reset     = def.reset

	self.widgets[name] = def
	return def
end

-- ---------- Internal: build a fresh cairn namespace ---------------------

local function makeFreshCairn(def, name, frame, opts)
	local cairn = {
		_frame    = frame,
		_type     = name,
		_opts     = opts or {},
		_children = {},
		_parent   = nil,
	}
	-- Layer mixins: Base first, then the type-specific mixin. Methods
	-- defined later overwrite earlier ones, so type-specific code can
	-- override Base defaults (e.g., GetIntrinsicSize for sizable widgets).
	for k, v in pairs(Base) do
		cairn[k] = v
	end
	for k, v in pairs(def.mixin) do
		cairn[k] = v
	end
	frame.Cairn = cairn
	return cairn
end

-- ---------- Acquire ------------------------------------------------------

function lib:Acquire(name, parent, opts)
	local def = self.widgets[name]
	if not def then
		error(("Acquire: widget type %q is not registered"):format(tostring(name)), 2)
	end

	parent = parent or UIParent

	local cairn

	-- Pool path: pop a recycled cairn if one is waiting. Pooled widgets
	-- already have their frame; we just reset state and reattach.
	if def.pool then
		local p = self._pool[name]
		if p and #p > 0 then
			cairn = table.remove(p)
			cairn._opts     = opts or {}
			cairn._children = {}
			cairn._parent   = nil
			-- Reattach the underlying frame to the new parent and show.
			local frame = cairn._frame
			if frame then
				if frame.SetParent then frame:SetParent(parent) end
				if frame.Show      then frame:Show()           end
			end
			-- def.reset was already called at Release time; the widget
			-- handed out here is "fresh" from the consumer's perspective.
		end
	end

	-- Fresh path: no pool entry available, create a new frame.
	if not cairn then
		local frame = CreateFrame(def.frameType, nil, parent, def.template)
		cairn = makeFreshCairn(def, name, frame, opts)
	end

	-- Cairn-side parent registration: if the parent itself has a Cairn
	-- namespace, this new widget becomes a tracked child for layout
	-- and Release purposes. Plain Blizzard frames (UIParent, etc.)
	-- have no Cairn namespace and are skipped silently.
	if parent and type(parent) == "table" and parent.Cairn and parent.Cairn._addChild then
		parent.Cairn:_addChild(cairn)
	end

	-- Run the lifecycle hook last, after all wiring is in place.
	cairn:OnAcquire(opts)

	return cairn._frame
end
