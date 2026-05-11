--[[
Cairn-Gui-Layouts-Extra-2.0 / Layouts / Hex

Arranges children in a hexagonal grid. Children flow in axial coordinates
(q, r) row-by-row; each row is offset horizontally by half a cell to
produce the staggered hex pattern.

Strategy signature: function(containerCairn, opts)
opts:
    columns     = number, default 4; cells per row before wrapping
    cellSize    = number, default 32; outer radius of each hex (the
                  distance from center to a corner). Cells are sized
                  cellSize * 2 wide x cellSize * sqrt(3) tall for
                  pointy-top orientation, or cellSize * sqrt(3) wide x
                  cellSize * 2 tall for flat-top.
    orientation = "pointy" (default) | "flat"
                  Pointy-top: hexes have a vertex at top, flat sides on
                  left/right. Flat-top: hexes have a flat side on top,
                  vertices on left/right.
    gap         = number, default 0; extra spacing between cells along
                  both axes (added to the natural hex spacing)
    padding     = number, default 0; uniform inset around the grid

Use cases: HUD hex maps, mini-map cell grids, hexagonal ability arrays.

Children with _layoutManual = true (or _secure during combat per the
Decision 8 lib:_isLayoutable helper) are skipped entirely.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local SQRT3 = math.sqrt(3)

lib:RegisterLayout("Hex", function(container, opts)
	if not container._children or #container._children == 0 then return end
	if not container._frame then return end
	opts = opts or {}

	local columns     = math.max(1, opts.columns or 4)
	local cellSize    = opts.cellSize or 32
	local orientation = opts.orientation or "pointy"
	local gap         = opts.gap or 0
	local padding     = opts.padding or 0
	local containerF  = container._frame

	-- Compute step sizes per orientation.
	local stepX, stepY, hexW, hexH
	if orientation == "flat" then
		hexW   = cellSize * 2
		hexH   = cellSize * SQRT3
		stepX  = (3 * cellSize) / 2 + gap     -- column-to-column horizontal step
		stepY  = hexH + gap                    -- row-to-row vertical step
	else
		-- pointy-top (default)
		hexW   = cellSize * SQRT3
		hexH   = cellSize * 2
		stepX  = hexW + gap
		stepY  = (3 * cellSize) / 2 + gap
	end

	-- Walk children and place each one.
	local idx = 0
	for _, child in ipairs(container._children) do
		if lib:_isLayoutable(child) and child._frame and child._frame.SetPoint then
			local row = math.floor(idx / columns)
			local col = idx % columns
			-- Pointy-top: odd rows shift X by half a step. Flat-top: odd
			-- columns shift Y by half a step.
			local x, y
			if orientation == "flat" then
				x = padding + col * stepX
				y = -padding - row * stepY
				if (col % 2) == 1 then y = y - stepY / 2 end
			else
				x = padding + col * stepX
				y = -padding - row * stepY
				if (row % 2) == 1 then x = x + stepX / 2 end
			end

			local f = child._frame
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", containerF, "TOPLEFT", x, y)
			f:SetSize(hexW, hexH)

			idx = idx + 1
		end
	end
end)
