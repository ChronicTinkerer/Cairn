--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / TreeView

Generic expand/collapse tree view. Consumer provides a tree of nodes;
the widget renders one row per visible node with an indicator and
indentation reflecting depth. Collapsed branches contribute one row
(the branch header) regardless of how many descendants they have, so
the widget naturally handles large data sets that would overwhelm a
flat list.

Public API:

	tv = Cairn.Gui:Acquire("TreeView", parent, {
		nodes      = {
			{ id = "C_Map", label = "C_Map", aux = "namespace",
			  children = {
				{ id = "C_Map.GetMapInfo", label = "GetMapInfo", aux = "function" },
				{ id = "C_Map.GetBestMapForUnit", label = "GetBestMapForUnit", aux = "function" },
			  } },
			{ id = "GetTime", label = "GetTime", aux = "function (global)" },
		},
		rowHeight  = 18,
		indent     = 16,
	})

	-- Methods:
	tv.Cairn:SetNodes(nodes)        -- replace root nodes; refreshes
	tv.Cairn:Expand(id)             -- expand one branch
	tv.Cairn:Collapse(id)
	tv.Cairn:Toggle(id)
	tv.Cairn:IsExpanded(id)
	tv.Cairn:ExpandAll()
	tv.Cairn:CollapseAll()
	tv.Cairn:Refresh()              -- re-flatten + repaint without changing state
	tv.Cairn:GetVisibleCount()      -- how many rows are currently rendered

	-- Events:
	tv.Cairn:On("Click",  function(_, nodeId, node) ... end)
	tv.Cairn:On("Toggle", function(_, nodeId, expanded) ... end)

Node shape:

	{
		id       = "uniqueId",        -- required, must be unique within the tree
		label    = "displayText",     -- shown next to the indicator
		aux      = "right text",      -- optional, muted, right-aligned
		children = { ... }            -- optional array; absent = leaf
	}

	Consumer-supplied extra fields are preserved on the node table; the
	widget never mutates them. The Click event passes the original node
	back as the second arg so consumers can pull whatever metadata they
	stashed there.

Click behavior:

	A single click on a row fires the "Click" event. If the node has
	children, the click ALSO toggles expansion and fires "Toggle".
	Consumers that want click-to-select on branches can still get the
	id via the Click event; they just need to know the branch
	auto-expands on the same gesture. This matches how OS file
	browsers behave.

Auto-sizing:

	The TreeView frame's height auto-grows to fit all visible rows.
	Wrap it in a Cairn-Gui ScrollFrame when you expect the tree to
	exceed the parent's height; the ScrollFrame's content height
	tracks the TreeView height because the TreeView is anchored TOPLEFT
	+ TOPRIGHT inside the scroll content and SetHeight'd by Refresh.

Pool: NOT pooled. Per-acquire row pool is owned by the widget and
released in OnRelease.

Status

	Standard MINOR 14. v1: vertical indented rows, single-click toggle,
	auto-grow height. No drag-reorder, no keyboard navigation, no
	multi-select, no node-level icons beyond the indicator. Deferred.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end


-- ----- Defaults --------------------------------------------------------

local DEFAULT_ROW_HEIGHT = 18
local DEFAULT_INDENT     = 16
local DEFAULT_ROW_GAP    = 2
local TOP_PAD            = 4
local SIDE_PAD           = 4
local AUX_WIDTH          = 120


-- ----- Tree flattening --------------------------------------------------
-- Walk the tree depth-first. Emit visible entries (parent expanded all
-- the way up). Recurse into children only when the current node is
-- expanded.

local function flattenVisible(nodes, expanded, depth, out)
	out = out or {}
	for _, node in ipairs(nodes or {}) do
		local hasChildren = node.children and #node.children > 0
		out[#out + 1] = {
			node        = node,
			depth       = depth,
			hasChildren = hasChildren,
		}
		if hasChildren and expanded[node.id] then
			flattenVisible(node.children, expanded, depth + 1, out)
		end
	end
	return out
end


-- ----- TreeView mixin --------------------------------------------------

local mixin = {}


-- Acquire / position one row inside the TreeView frame. Rows are
-- positioned manually (not Stack-laid) so we can recycle the pool
-- across refreshes without re-ordering tracker indices.
local function acquireRow(self, index)
	local existing = self._rows[index]
	if existing and existing.container then
		existing.container:Show()
		return existing
	end

	local row = {}
	row.container = Core:Acquire("Container", self._frame, {
		height = self._rowHeight,
	})
	row.container:EnableMouse(true)
	row.container.Cairn:SetLayoutManual(true)

	row.indicatorLabel = Core:Acquire("Label", row.container, { text = "" })
	row.indicatorLabel.Cairn:SetLayoutManual(true)

	row.label = Core:Acquire("Label", row.container, { text = "" })
	row.label.Cairn:SetLayoutManual(true)

	row.auxLabel = Core:Acquire("Label", row.container, {
		text = "", variant = "muted",
	})
	row.auxLabel.Cairn:SetLayoutManual(true)

	row.container:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		if not row._nodeId then return end
		if row._hasChildren then
			self:Toggle(row._nodeId)
		end
		self:Fire("Click", row._nodeId, row._node)
	end)

	self._rows[index] = row
	return row
end


-- Render one entry into the supplied row. Indent the indicator/label by
-- depth * self._indent so the visual hierarchy matches the tree depth.
local function renderRow(self, row, entry, index)
	local node        = entry.node
	local hasChildren = entry.hasChildren

	row._nodeId      = node.id
	row._node        = node
	row._hasChildren = hasChildren

	local x = SIDE_PAD + self._indent * entry.depth

	-- Indicator: "+" if collapsible+collapsed, "-" if expanded, "  " for leaf.
	local indicator
	if hasChildren then
		indicator = self._expanded[node.id] and "|cffffd060-|r" or "|cffffd060+|r"
	else
		indicator = "  "
	end
	row.indicatorLabel.Cairn:SetText(indicator)
	row.indicatorLabel:ClearAllPoints()
	row.indicatorLabel:SetPoint("LEFT", row.container, "LEFT", x, 0)
	row.indicatorLabel:SetWidth(14)

	row.label.Cairn:SetText(node.label or tostring(node.id))
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row.indicatorLabel, "RIGHT", 4, 0)

	if node.aux and node.aux ~= "" then
		row.label:SetPoint("RIGHT", row.container, "RIGHT", -(AUX_WIDTH + 8), 0)
		row.auxLabel.Cairn:SetText(node.aux)
		row.auxLabel:ClearAllPoints()
		row.auxLabel:SetPoint("RIGHT", row.container, "RIGHT", -SIDE_PAD, 0)
		row.auxLabel:SetWidth(AUX_WIDTH)
		row.auxLabel:Show()
	else
		row.label:SetPoint("RIGHT", row.container, "RIGHT", -SIDE_PAD, 0)
		row.auxLabel:Hide()
	end

	-- Position the row vertically within the TreeView frame.
	local y = -(index - 1) * (self._rowHeight + DEFAULT_ROW_GAP) - TOP_PAD
	row.container:ClearAllPoints()
	row.container:SetPoint("TOPLEFT",  self._frame, "TOPLEFT",  0, y)
	row.container:SetPoint("TOPRIGHT", self._frame, "TOPRIGHT", 0, y)
end


function mixin:OnAcquire(opts)
	opts = opts or {}
	self._rootNodes = opts.nodes or {}
	self._expanded  = {}
	self._rowHeight = opts.rowHeight or DEFAULT_ROW_HEIGHT
	self._indent    = opts.indent    or DEFAULT_INDENT
	self._rows      = self._rows or {}
	self._frame:Show()
	self:Refresh()
end


function mixin:SetNodes(nodes)
	-- Replacing nodes invalidates the expansion set: ids in the old
	-- tree may not exist in the new one. We do NOT clear _expanded
	-- here so the consumer can restore prior state across filter
	-- rebuilds (where ids stay stable). Consumers that want a fresh
	-- collapsed view can call CollapseAll() before SetNodes.
	self._rootNodes = nodes or {}
	self:Refresh()
end


function mixin:IsExpanded(id)
	return self._expanded[id] and true or false
end


function mixin:Expand(id)
	if self._expanded[id] then return end
	self._expanded[id] = true
	self:Refresh()
	self:Fire("Toggle", id, true)
end


function mixin:Collapse(id)
	if not self._expanded[id] then return end
	self._expanded[id] = nil
	self:Refresh()
	self:Fire("Toggle", id, false)
end


function mixin:Toggle(id)
	if self._expanded[id] then
		self:Collapse(id)
	else
		self:Expand(id)
	end
end


function mixin:ExpandAll()
	-- Walk the whole tree marking every branch expanded. Cheap because
	-- _expanded is keyed by id, not by index, so duplicate writes are
	-- no-ops.
	local function walk(nodes)
		for _, n in ipairs(nodes or {}) do
			if n.children and #n.children > 0 then
				self._expanded[n.id] = true
				walk(n.children)
			end
		end
	end
	walk(self._rootNodes)
	self:Refresh()
end


function mixin:CollapseAll()
	self._expanded = {}
	self:Refresh()
end


function mixin:GetVisibleCount()
	return self._visible and #self._visible or 0
end


function mixin:Refresh()
	self._visible = flattenVisible(self._rootNodes, self._expanded, 0)
	for i, entry in ipairs(self._visible) do
		local row = acquireRow(self, i)
		renderRow(self, row, entry, i)
	end
	for i = #self._visible + 1, #self._rows do
		if self._rows[i].container then
			self._rows[i].container:Hide()
		end
	end
	-- Auto-grow height so a parent ScrollFrame's content tracks us.
	local totalH = #self._visible * (self._rowHeight + DEFAULT_ROW_GAP)
	                + TOP_PAD * 2
	self._frame:SetHeight(math.max(40, totalH))
end


function mixin:OnRelease()
	if self._rows then
		for _, row in ipairs(self._rows) do
			if row.indicatorLabel and row.indicatorLabel.Cairn then
				row.indicatorLabel.Cairn:Release()
			end
			if row.label and row.label.Cairn then
				row.label.Cairn:Release()
			end
			if row.auxLabel and row.auxLabel.Cairn then
				row.auxLabel.Cairn:Release()
			end
			if row.container and row.container.Cairn then
				row.container.Cairn:Release()
			end
		end
		self._rows = nil
	end
	self._rootNodes = nil
	self._expanded  = nil
	self._visible   = nil
end


-- ----- Register --------------------------------------------------------

Core:RegisterWidget("TreeView", {
	frameType = "Frame",
	mixin     = mixin,
	pool      = false,
})
