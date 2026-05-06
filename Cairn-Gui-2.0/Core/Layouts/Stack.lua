--[[
Cairn-Gui-2.0 / Core / Layouts / Stack

The Stack strategy arranges children in a single line, vertically or
horizontally, with optional gap between children and padding around
the group.

Strategy signature: function(containerCairn, opts)
opts:
	direction = "vertical" (default) | "horizontal"
	gap       = number, default 0; space between adjacent children
	padding   = number, default 0; uniform inset around the stack

For vertical direction:
	- Each child anchored TOPLEFT/TOPRIGHT to the container so width
	  fills the container minus 2*padding.
	- Height comes from the child's GetIntrinsicSize (preferred) or
	  the child's current frame height (fallback). Default 20 if both
	  are unavailable.
	- Children stack downward from the top.

For horizontal direction:
	- Each child anchored TOPLEFT/BOTTOMLEFT so height fills the
	  container minus 2*padding.
	- Width comes from GetIntrinsicSize, then frame:GetWidth, then 20.
	- Children stack rightward from the left.

Children with _layoutManual = true are skipped entirely; they keep
whatever anchoring they already have.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local DEFAULT_FALLBACK_SIZE = 20

local function vertical(container, opts)
	local gap        = opts.gap or 0
	local padding    = opts.padding or 0
	local containerF = container._frame
	local cursor     = -padding

	for _, child in ipairs(container._children) do
		if not child._layoutManual then
			local frame = child._frame
			if frame and frame.SetPoint then
				local _, ih = child:GetIntrinsicSize()
				local h = ih or frame:GetHeight()
				if not h or h <= 0 then h = DEFAULT_FALLBACK_SIZE end

				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT",  containerF, "TOPLEFT",   padding, cursor)
				frame:SetPoint("TOPRIGHT", containerF, "TOPRIGHT", -padding, cursor)
				frame:SetHeight(h)

				cursor = cursor - h - gap
			end
		end
	end
end

local function horizontal(container, opts)
	local gap        = opts.gap or 0
	local padding    = opts.padding or 0
	local containerF = container._frame
	local cursor     = padding

	for _, child in ipairs(container._children) do
		if not child._layoutManual then
			local frame = child._frame
			if frame and frame.SetPoint then
				local iw = child:GetIntrinsicSize()
				local w = iw or frame:GetWidth()
				if not w or w <= 0 then w = DEFAULT_FALLBACK_SIZE end

				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT",    containerF, "TOPLEFT",    cursor, -padding)
				frame:SetPoint("BOTTOMLEFT", containerF, "BOTTOMLEFT", cursor,  padding)
				frame:SetWidth(w)

				cursor = cursor + w + gap
			end
		end
	end
end

lib:RegisterLayout("Stack", function(container, opts)
	if not container._children or #container._children == 0 then return end
	if not container._frame then return end

	local direction = opts and opts.direction or "vertical"
	if direction == "horizontal" then
		horizontal(container, opts or {})
	else
		vertical(container, opts or {})
	end
end)
