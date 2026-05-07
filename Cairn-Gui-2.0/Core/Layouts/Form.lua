--[[
Cairn-Gui-2.0 / Core / Layouts / Form

Two-column label/field layout for settings panels and dialogs. Children
come in PAIRS: index 1 = label widget, index 2 = field widget,
index 3 = label, index 4 = field, etc. The label sits in the left
column right-aligned to the divider; the field fills the right column.

Strategy signature: function(containerCairn, opts)
opts:
    labelWidth = number, optional; explicit label-column width. When
                 omitted, computed from the max GetIntrinsicSize().w
                 of every odd-indexed (label) child, falling back to
                 frame:GetWidth, falling back to 100.
    rowGap     = number, default 4; vertical space between rows
    colGap     = number, default 8; horizontal space between label and
                 field columns
    padding    = number, default 0; uniform inset around the form
    rowHeight  = number, optional; explicit row height. When omitted,
                 each row's height is the max GetIntrinsicSize.h of the
                 label and field in that row, falling back to 22.

Behavior

    - Pairs flow top-to-bottom. An odd number of children leaves the
      last child as a "full-width" row spanning both columns (useful
      for section headers, separators, or a final action button).
    - Children with _layoutManual = true are skipped entirely and do
      not consume a label or field slot. Skipping a label-position
      child shifts everything after it.

Use cases:
    - Settings panels (label "Volume", slider field; label "Enabled",
      checkbox field).
    - Login / config dialogs.
    - Any aligned key/value display.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

local DEFAULT_ROW_HEIGHT = 22
local DEFAULT_LABEL_FALLBACK = 100

lib:RegisterLayout("Form", function(container, opts)
    if not container._children or #container._children == 0 then return end
    if not container._frame then return end
    opts = opts or {}

    local rowGap     = opts.rowGap  or 4
    local colGap     = opts.colGap  or 8
    local padding    = opts.padding or 0
    local containerF = container._frame

    -- Build the layoutable list (skip _layoutManual children).
    local kids = {}
    for _, child in ipairs(container._children) do
        if lib:_isLayoutable(child) and child._frame and child._frame.SetPoint then
            kids[#kids + 1] = child
        end
    end
    if #kids == 0 then return end

    -- Compute label-column width: explicit opts.labelWidth, or auto-fit
    -- to the widest label (odd-indexed children).
    local labelW = opts.labelWidth
    if not labelW then
        local maxW = 0
        for i = 1, #kids, 2 do
            local label = kids[i]
            local iw = label:GetIntrinsicSize()
            local w = iw or (label._frame:GetWidth() or 0)
            if w > maxW then maxW = w end
        end
        labelW = (maxW > 0) and maxW or DEFAULT_LABEL_FALLBACK
    end

    -- Right edge of label column, left edge of field column.
    local labelRightX = padding + labelW
    local fieldLeftX  = labelRightX + colGap

    -- Walk pairs.
    local cursor = -padding
    local i = 1
    while i <= #kids do
        local label = kids[i]
        local field = kids[i + 1]

        -- Compute row height: explicit, or max of label + field intrinsic.
        local rowH = opts.rowHeight
        if not rowH then
            local _, lh = label:GetIntrinsicSize()
            local _, fh = field and field:GetIntrinsicSize()
            local h = math.max(lh or 0, fh or 0)
            if h <= 0 then
                h = math.max(label._frame:GetHeight() or 0,
                             (field and field._frame:GetHeight()) or 0)
            end
            if h <= 0 and lib.Dev and lib._log and lib._log.Warn then
                lib._log:Warn("Form: row %d -- neither label %s nor field %s has intrinsic height; using fallback %dpx (pass opts.rowHeight to silence)",
                    math.floor((i + 1) / 2), tostring(label._type or "?"),
                    tostring((field and field._type) or "nil"), DEFAULT_ROW_HEIGHT)
            end
            rowH = (h > 0) and h or DEFAULT_ROW_HEIGHT
        end

        if not field then
            -- Odd-out child: full-width row.
            local f = label._frame
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT",  containerF, "TOPLEFT",  padding, cursor)
            f:SetPoint("TOPRIGHT", containerF, "TOPRIGHT", -padding, cursor)
            f:SetHeight(rowH)
        else
            -- Label: right-aligned in left column.
            local lf = label._frame
            lf:ClearAllPoints()
            lf:SetPoint("TOPLEFT", containerF, "TOPLEFT", padding, cursor)
            lf:SetSize(labelW, rowH)

            -- Field: fills the right column.
            local ff = field._frame
            ff:ClearAllPoints()
            ff:SetPoint("TOPLEFT",  containerF, "TOPLEFT",  fieldLeftX, cursor)
            ff:SetPoint("TOPRIGHT", containerF, "TOPRIGHT", -padding,   cursor)
            ff:SetHeight(rowH)
        end

        cursor = cursor - rowH - rowGap
        i = i + (field and 2 or 1)
    end
end)
