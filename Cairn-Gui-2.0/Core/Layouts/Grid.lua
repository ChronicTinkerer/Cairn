--[[
Cairn-Gui-2.0 / Core / Layouts / Grid

Arranges children in a fixed-column grid. Children flow LEFT-to-RIGHT,
TOP-to-BOTTOM filling each row before wrapping. Cell size is uniform
within the grid and either derived from the container width (default)
or set explicitly via opts.cellWidth / opts.cellHeight.

Strategy signature: function(containerCairn, opts)
opts:
    columns    = number, default 2; cells per row
    rowGap     = number, default 0; vertical space between rows
    colGap     = number, default 0; horizontal space between columns
    padding    = number, default 0; uniform inset around the grid
    cellWidth  = number, optional; explicit cell width. When omitted,
                 width is computed as
                 (containerWidth - 2*padding - colGap*(columns-1)) / columns
    cellHeight = number, optional; explicit cell height. When omitted,
                 row height is the max GetIntrinsicSize height of the
                 children in that row, falling back to frame:GetHeight,
                 falling back to 20.

Children with _layoutManual = true are skipped entirely; they keep
whatever anchoring they already have.

Use cases:
    - Icon grids (3-column inventory, 4-column ability bar layouts).
    - Uniform card grids where each cell holds a Container of the same
      size (gallery, pet roster).
    - Settings panels where related toggles are arranged in 2 columns.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local DEFAULT_FALLBACK_SIZE = 20

lib:RegisterLayout("Grid", function(container, opts)
    if not container._children or #container._children == 0 then return end
    if not container._frame then return end
    opts = opts or {}

    local columns    = math.max(1, opts.columns or 2)
    local rowGap     = opts.rowGap  or 0
    local colGap     = opts.colGap  or 0
    local padding    = opts.padding or 0
    local containerF = container._frame

    -- Build a list of layoutable children (skip _layoutManual ones).
    local kids = {}
    for _, child in ipairs(container._children) do
        if lib:_isLayoutable(child) and child._frame and child._frame.SetPoint then
            kids[#kids + 1] = child
        end
    end
    if #kids == 0 then return end

    -- Compute cell width: either explicit opts.cellWidth, or derived from
    -- the container width minus padding and inter-column gaps. We use
    -- GetWidth() rather than a stored measurement because the container
    -- might have been resized between layouts.
    local cellW = opts.cellWidth
    if not cellW then
        local available = (containerF:GetWidth() or 0) - 2 * padding - colGap * (columns - 1)
        cellW = math.max(1, available / columns)
    end

    -- Pass 1: per-row max height (only matters when opts.cellHeight is
    -- nil; otherwise every row is the explicit height).
    local rowHeights = {}
    local explicitH  = opts.cellHeight
    for i, child in ipairs(kids) do
        local row = math.floor((i - 1) / columns) + 1
        local h
        if explicitH then
            h = explicitH
        else
            local _, ih = child:GetIntrinsicSize()
            h = ih or (child._frame:GetHeight() or 0)
            if h <= 0 then
                -- Dev-mode warning: silent fallback to 20px collapses
                -- cells on top of each other (the "jumbled" symptom).
                -- Consumers should pass opts.cellHeight or give the
                -- child an intrinsic size.
                if lib.Dev and lib._log and lib._log.Warn then
                    lib._log:Warn("Grid: child %s has no intrinsic height and frame:GetHeight()=0; using fallback %dpx (pass opts.cellHeight to silence)",
                        tostring(child._type or "?"), DEFAULT_FALLBACK_SIZE)
                end
                h = DEFAULT_FALLBACK_SIZE
            end
        end
        rowHeights[row] = math.max(rowHeights[row] or 0, h)
    end

    -- Pass 2: position each child. y advances as we cross row boundaries.
    -- Row tops are the cumulative sum of (rowHeights[1..row-1] + rowGap).
    local rowTops = { [1] = -padding }
    for r = 2, #rowHeights do
        rowTops[r] = rowTops[r - 1] - rowHeights[r - 1] - rowGap
    end

    for i, child in ipairs(kids) do
        local row = math.floor((i - 1) / columns) + 1
        local col = ((i - 1) % columns) + 1
        local x = padding + (col - 1) * (cellW + colGap)
        local y = rowTops[row]

        local frame = child._frame
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", containerF, "TOPLEFT", x, y)
        frame:SetSize(cellW, rowHeights[row])
    end
end)
