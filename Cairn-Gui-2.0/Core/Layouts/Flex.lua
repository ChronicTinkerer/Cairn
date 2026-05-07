--[[
Cairn-Gui-2.0 / Core / Layouts / Flex

CSS-flexbox-inspired layout strategy. Children are arranged along a
main axis (horizontal or vertical) with configurable distribution,
cross-axis alignment, and per-child grow factors.

Strategy signature: function(containerCairn, opts)
opts:
    direction = "row" (default) | "column"
                "row" arranges children left-to-right along the X axis;
                "column" arranges them top-to-bottom along the Y axis.
    justify   = "start" (default) | "end" | "center" | "between" |
                "around" | "evenly"
                Distribution along the MAIN axis.
                "start"   - pack at the start; trailing free space.
                "end"     - pack at the end; leading free space.
                "center"  - pack centered; equal free space at start and end.
                "between" - first child at start, last at end, free space
                            distributed equally between siblings.
                "around"  - each child wrapped in equal half-gap space, so
                            outer half-gaps + N-1 full gaps between children.
                "evenly"  - equal full-gap space between every pair AND at
                            both ends.
    align     = "stretch" (default) | "start" | "end" | "center"
                Cross-axis sizing/alignment for each child.
                "stretch" - child fills the cross-axis (height for row,
                            width for column) minus 2*padding.
                "start"   - child sized to its intrinsic cross size,
                            anchored to the start cross-edge.
                "end"     - same sizing, anchored to the end cross-edge.
                "center"  - same sizing, centered on the cross axis.
    gap       = number, default 0; minimum space between adjacent
                children before any justify-driven distribution.
    padding   = number, default 0; uniform inset around the flex line.

Per-child opts (read off the child cairn):
    child._flexGrow   = number, default 0
                       The child's share of any leftover free space
                       along the main axis. If totalGrow > 0, leftover
                       is distributed proportionally.
    child._flexBasis  = number, optional; override for the child's
                       initial main-axis size. When omitted, the
                       child's intrinsic main-axis size is used,
                       falling back to its current frame size,
                       falling back to 20.

Children with _layoutManual = true are skipped entirely.

What this is NOT (cuts from a full flexbox spec):

    - No `wrap`. Children always lay out on a single line. Wrapping
      to multiple lines is what Grid is for; combining the two is a
      future opt-in (`wrap = true` could land in a follow-up MINOR).
    - No flex-shrink. Children that don't fit are NOT clipped or
      shrunk; they simply overflow the container. Use `align = stretch`
      with a parent-bounded container if you need overflow control.
    - No order property. Children lay out in their _children array
      order (insertion order) regardless of any ordering hint.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local DEFAULT_FALLBACK_SIZE = 20

-- Resolve the main-axis size for a child (basis or intrinsic).
local function mainSize(child, isRow, basisField)
    local explicit = child[basisField]
    if explicit then return explicit end
    local iw, ih = child:GetIntrinsicSize()
    local s = isRow and iw or ih
    if not s or s <= 0 then
        s = isRow and (child._frame:GetWidth() or 0)
                 or (child._frame:GetHeight() or 0)
    end
    if s <= 0 then s = DEFAULT_FALLBACK_SIZE end
    return s
end

-- Resolve the cross-axis size for a child.
local function crossSize(child, isRow)
    local iw, ih = child:GetIntrinsicSize()
    local s = isRow and ih or iw
    if not s or s <= 0 then
        s = isRow and (child._frame:GetHeight() or 0)
                 or (child._frame:GetWidth() or 0)
    end
    if s <= 0 then s = DEFAULT_FALLBACK_SIZE end
    return s
end

-- Build the per-child main-axis offsets array given pre-distribution
-- main sizes, container main size, justify mode, and gap.
-- Returns an array `offsets` such that child i sits at offsets[i] on
-- the main axis.
local function computeOffsets(sizes, containerMain, justify, gap, padding)
    local n = #sizes
    if n == 0 then return {} end

    local available = containerMain - 2 * padding
    local sumSizes  = 0
    for i = 1, n do sumSizes = sumSizes + sizes[i] end
    local sumGaps   = (n - 1) * gap
    local free      = available - sumSizes - sumGaps
    if free < 0 then free = 0 end

    local offsets = {}
    if justify == "end" then
        local x = padding + free
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap
        end
    elseif justify == "center" then
        local x = padding + free / 2
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap
        end
    elseif justify == "between" and n > 1 then
        local extra = free / (n - 1)
        local x = padding
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap + extra
        end
    elseif justify == "around" and n > 0 then
        local extra = free / n
        local x = padding + extra / 2
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap + extra
        end
    elseif justify == "evenly" then
        local extra = free / (n + 1)
        local x = padding + extra
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap + extra
        end
    else
        -- "start" (default).
        local x = padding
        for i = 1, n do
            offsets[i] = x
            x = x + sizes[i] + gap
        end
    end
    return offsets
end

lib:RegisterLayout("Flex", function(container, opts)
    if not container._children or #container._children == 0 then return end
    if not container._frame then return end
    opts = opts or {}

    local direction = opts.direction or "row"
    local isRow     = (direction ~= "column")
    local justify   = opts.justify or "start"
    local align     = opts.align   or "stretch"
    local gap       = opts.gap     or 0
    local padding   = opts.padding or 0
    local containerF = container._frame

    -- Build the layoutable list (skip _layoutManual children).
    local kids = {}
    for _, child in ipairs(container._children) do
        if lib:_isLayoutable(child) and child._frame and child._frame.SetPoint then
            kids[#kids + 1] = child
        end
    end
    if #kids == 0 then return end

    -- Initial main-axis sizes (from basis or intrinsic).
    local sizes = {}
    local totalGrow = 0
    for i, child in ipairs(kids) do
        sizes[i] = mainSize(child, isRow, "_flexBasis")
        totalGrow = totalGrow + (child._flexGrow or 0)
    end

    -- Distribute leftover free space proportionally to flexGrow factors.
    -- Done BEFORE justify computes offsets so grown children consume the
    -- "free" pool that justify would otherwise distribute.
    if totalGrow > 0 then
        local containerMain = isRow and (containerF:GetWidth() or 0)
                                  or (containerF:GetHeight() or 0)
        local sumSizes = 0
        for i = 1, #sizes do sumSizes = sumSizes + sizes[i] end
        local sumGaps = (#sizes - 1) * gap
        local free    = (containerMain - 2 * padding) - sumSizes - sumGaps
        if free > 0 then
            for i, child in ipairs(kids) do
                local g = child._flexGrow or 0
                if g > 0 then
                    sizes[i] = sizes[i] + free * (g / totalGrow)
                end
            end
        end
    end

    -- Compute main-axis offsets.
    local containerMain = isRow and (containerF:GetWidth() or 0)
                              or (containerF:GetHeight() or 0)
    local offsets = computeOffsets(sizes, containerMain, justify, gap, padding)

    -- Compute cross-axis size (full inner width/height).
    local containerCross = isRow and (containerF:GetHeight() or 0)
                                or (containerF:GetWidth() or 0)
    local crossInner     = math.max(0, containerCross - 2 * padding)

    -- Position + size each child.
    for i, child in ipairs(kids) do
        local frame = child._frame
        local mainOff  = offsets[i]
        local mainSz   = sizes[i]
        local crossSz  = (align == "stretch") and crossInner or crossSize(child, isRow)
        local crossOff
        if align == "stretch" or align == "start" then
            crossOff = padding
        elseif align == "end" then
            crossOff = padding + (crossInner - crossSz)
        elseif align == "center" then
            crossOff = padding + (crossInner - crossSz) / 2
        else
            crossOff = padding
        end

        frame:ClearAllPoints()
        if isRow then
            -- Main = X (right-positive), Cross = Y (down-negative in WoW).
            frame:SetPoint("TOPLEFT", containerF, "TOPLEFT", mainOff, -crossOff)
            frame:SetSize(mainSz, crossSz)
        else
            -- Main = Y (down-negative), Cross = X (right-positive).
            frame:SetPoint("TOPLEFT", containerF, "TOPLEFT", crossOff, -mainOff)
            frame:SetSize(crossSz, mainSz)
        end
    end
end)
