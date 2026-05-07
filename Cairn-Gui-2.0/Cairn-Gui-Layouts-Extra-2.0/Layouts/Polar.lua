--[[
Cairn-Gui-Layouts-Extra-2.0 / Layouts / Polar

Arranges children in a circular / radial pattern around a center point.
Useful for ability radial menus, HUD compass rings, and any UI that
benefits from "spread evenly around a center" placement.

Strategy signature: function(containerCairn, opts)
opts:
    radius     = number, default 80; distance from center to each child's center
    startAngle = number, default 0 (degrees); angle of the FIRST child.
                 0 = right (3 o'clock), 90 = top, 180 = left, 270 = bottom.
    endAngle   = number, optional. When omitted, children fill a full
                 circle (360 degrees) evenly. When set, children fill the
                 sweep from startAngle to endAngle inclusive.
    direction  = "ccw" (default) | "cw"
                 Counter-clockwise increases the angle; clockwise
                 decreases. Standard math convention is ccw.
    cellSize   = number, default 32; square edge for each child's frame.
                 If a child has its own intrinsic size, that's used
                 instead.
    centerX    = number, optional pixel offset of the ring center from
                 container center. Default 0 (centered).
    centerY    = number, optional pixel offset. Default 0.

Use cases: radial ability menus, hub-and-spoke nav, gauge rings.

Children with _layoutManual = true (or _secure during combat per the
Decision 8 lib:_isLayoutable helper) are skipped entirely.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local DEG_TO_RAD = math.pi / 180

lib:RegisterLayout("Polar", function(container, opts)
	if not container._children or #container._children == 0 then return end
	if not container._frame then return end
	opts = opts or {}

	local radius     = opts.radius     or 80
	local startAngle = opts.startAngle or 0
	local endAngle   = opts.endAngle
	local direction  = opts.direction  or "ccw"
	local cellSize   = opts.cellSize   or 32
	local centerX    = opts.centerX    or 0
	local centerY    = opts.centerY    or 0
	local containerF = container._frame

	-- Build the layoutable list to know the count BEFORE we compute
	-- per-child angles (the count drives the angular spacing).
	local kids = {}
	for _, child in ipairs(container._children) do
		if lib:_isLayoutable(child) and child._frame and child._frame.SetPoint then
			kids[#kids + 1] = child
		end
	end
	if #kids == 0 then return end

	-- Compute angular sweep + per-child angle.
	-- Full circle: divide 360 by N children.
	-- Bounded sweep: divide (end - start) by max(1, N - 1) so first and
	-- last children sit exactly at the bounds.
	local sweep, step
	if endAngle then
		sweep = endAngle - startAngle
		step  = (#kids > 1) and (sweep / (#kids - 1)) or 0
	else
		sweep = 360
		step  = sweep / #kids
	end
	if direction == "cw" then step = -step end

	-- Container center in container-local coords. Anchor each child
	-- TOPLEFT relative to the container's TOPLEFT, offset to its
	-- computed (x, y) MINUS half its frame size (so the child's center
	-- sits on the computed point).
	local cw, ch = containerF:GetWidth() or 0, containerF:GetHeight() or 0
	local cxLocal = cw / 2 + centerX
	local cyLocal = -(ch / 2) - centerY  -- negative because Y is inverted

	for i, child in ipairs(kids) do
		local angleDeg = startAngle + step * (i - 1)
		local angleRad = angleDeg * DEG_TO_RAD
		local cx       = cxLocal + radius * math.cos(angleRad)
		local cy       = cyLocal + radius * math.sin(angleRad)

		-- Per-child size: intrinsic if available, else cellSize.
		local iw, ih = child:GetIntrinsicSize()
		local w = iw or cellSize
		local h = ih or cellSize

		local f = child._frame
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", containerF, "TOPLEFT", cx - w / 2, cy + h / 2)
		f:SetSize(w, h)
	end
end)
