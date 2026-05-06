--[[
Cairn-Gui-1.0

Small widget kit owned by us. Built on raw CreateFrame so we don't depend
on Blizzard's Settings/AddOn UI APIs (which churn between patches).

Design:
  * Each widget is a function returning a Frame (or FontString) with a
    handful of methods bolted on. No mixin chains, no XML templates, no
    ace3-style registration - just plain functions and tables.
  * Layout helpers (VBox/HBox) auto-arrange children with padding and
    optional fill. They expose :Add(child, opts) to append.
  * Widgets follow a uniform shape: every value-bearing widget exposes
    :Get() / :Set(value) / :OnChange(fn). Subscribe with :OnChange(fn);
    fn receives (newValue, oldValue).

Public API summary:
  Cairn.Gui:Panel(parent, opts)        -> styled Frame with optional title
  Cairn.Gui:VBox(parent, opts)         -> vertical layout container
  Cairn.Gui:HBox(parent, opts)         -> horizontal layout container
  Cairn.Gui:Header(parent, text)       -> section header (FontString)
  Cairn.Gui:Label(parent, text, opts)  -> regular text
  Cairn.Gui:Button(parent, text, opts) -> button with onClick
  Cairn.Gui:Checkbox(parent, opts)     -> Get/Set/OnChange (boolean)
  Cairn.Gui:EditBox(parent, opts)      -> Get/Set/OnChange (string)
  Cairn.Gui:Slider(parent, opts)       -> Get/Set/OnChange (number)
  Cairn.Gui:Dropdown(parent, opts)     -> Get/Set/OnChange (any)
  Cairn.Gui:ColorSwatch(parent, opts)  -> Get/Set/OnChange ({r,g,b,a})
  Cairn.Gui:KeybindButton(parent, opts)-> Get/Set/OnChange (string)
]]

local MAJOR, MINOR = "Cairn-Gui-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- ----- Theme tokens -----------------------------------------------------
local THEME = {
    bg          = { 0.04, 0.04, 0.04, 0.40 },
    bgPanel     = { 0.06, 0.06, 0.06, 0.85 },
    border      = { 0.40, 0.30, 0.15, 1.00 },
    accent      = { 0.85, 0.50, 0.20, 1.00 },  -- forge orange
    text        = { 1.00, 1.00, 1.00, 1.00 },
    textDim     = { 0.85, 0.70, 0.40, 1.00 },
    textMuted   = { 0.60, 0.55, 0.45, 1.00 },
    rowHover    = { 0.45, 0.32, 0.15, 0.30 },
    rowSelected = { 0.85, 0.50, 0.20, 0.35 },
}
lib.THEME = THEME  -- consumers can read; mutate carefully

local DEFAULT_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local PAD = 6

-- ----- Internal helpers -------------------------------------------------
local function safeRun(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- Add :OnChange / :Get / :Set scaffolding to a widget table.
local function attachValueAPI(w)
    w._subs = {}
    function w:OnChange(fn)
        if type(fn) ~= "function" then return function() end end
        local sub = { fn = fn }
        self._subs[#self._subs + 1] = sub
        return function() sub.removed = true end
    end
    function w:_fireChange(newV, oldV)
        for _, sub in ipairs(self._subs) do
            if sub and not sub.removed then safeRun(sub.fn, newV, oldV) end
        end
    end
    return w
end

-- ============================================================================
-- Panel: a styled container frame with optional title bar.
-- ============================================================================
function lib:Panel(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop(DEFAULT_BACKDROP)
    f:SetBackdropColor(unpack(THEME.bgPanel))
    f:SetBackdropBorderColor(unpack(THEME.border))

    if opts.title then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", PAD, -PAD)
        title:SetText(opts.title)
        title:SetTextColor(unpack(THEME.accent))
        f._title = title
    end
    return f
end

-- ============================================================================
-- VBox: vertical stack of children. Handles its own height to fit content.
-- VBox:Add(child, { gap = 6 }) - stacks child below previous sibling.
-- ============================================================================
function lib:VBox(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f._padding = opts.padding or PAD
    f._gap     = opts.gap     or 4
    f._items   = {}

    function f:Add(child, addOpts)
        addOpts = addOpts or {}
        local gap = addOpts.gap or self._gap
        child:ClearAllPoints()
        if #self._items == 0 then
            child:SetPoint("TOPLEFT",  self, "TOPLEFT",   self._padding, -self._padding)
            child:SetPoint("TOPRIGHT", self, "TOPRIGHT", -self._padding, -self._padding)
        else
            local prev = self._items[#self._items]
            child:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT",  0, -gap)
            child:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -gap)
        end
        self._items[#self._items + 1] = child
        return child
    end

    function f:Layout()
        -- Auto-size to total height of children + padding.
        local total = self._padding
        for i, c in ipairs(self._items) do
            total = total + (c:GetHeight() or 0) + (i == 1 and 0 or self._gap)
        end
        total = total + self._padding
        self:SetHeight(math.max(total, 1))
    end

    return f
end

-- ============================================================================
-- HBox: horizontal stack. Children laid out left-to-right.
-- ============================================================================
function lib:HBox(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f._padding = opts.padding or 0
    f._gap     = opts.gap     or 4
    f._items   = {}

    function f:Add(child, addOpts)
        addOpts = addOpts or {}
        local gap = addOpts.gap or self._gap
        child:ClearAllPoints()
        if #self._items == 0 then
            child:SetPoint("LEFT", self, "LEFT", self._padding, 0)
        else
            local prev = self._items[#self._items]
            child:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        end
        self._items[#self._items + 1] = child
        return child
    end

    return f
end

-- ============================================================================
-- Header: section header text, accent-colored.
-- ============================================================================
function lib:Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(THEME.accent))
    fs:SetJustifyH("LEFT")
    -- FontStrings can't be added to layouts that expect SetHeight; wrap.
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20)
    fs:SetParent(f); fs:ClearAllPoints(); fs:SetPoint("LEFT", f, "LEFT", 0, 0)
    fs:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f._fs = fs
    function f:SetText(t) self._fs:SetText(t or "") end
    return f
end

-- ============================================================================
-- Label: regular text. Word-wraps by default.
-- ============================================================================
function lib:Label(parent, text, opts)
    opts = opts or {}
    local fs = parent:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormal")
    fs:SetText(text or "")
    fs:SetJustifyH(opts.align or "LEFT")
    fs:SetWordWrap(opts.wrap ~= false)
    if fs.SetMaxLines then fs:SetMaxLines(opts.maxLines or 0) end
    if opts.color then fs:SetTextColor(unpack(opts.color)) end
    -- Wrap in a Frame so it has a height for layout.
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(opts.height or 18)
    fs:SetParent(f); fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f._fs = fs
    function f:SetText(t)
        self._fs:SetText(t or "")
        local h = math.max(self._fs:GetStringHeight() or 0, 16)
        self:SetHeight(h)
    end
    f:SetText(text)
    return f
end

-- ============================================================================
-- Button.
-- ============================================================================
function lib:Button(parent, text, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(opts.width or 100, opts.height or 22)
    b:SetText(text or "")
    if opts.onClick then b:SetScript("OnClick", function() safeRun(opts.onClick) end) end
    if opts.tooltip then
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(opts.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return b
end

-- ============================================================================
-- Checkbox: boolean Get/Set/OnChange.
-- ============================================================================
function lib:Checkbox(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetChecked(opts.value and true or false)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(opts.label or "")
    row._cb = cb; row._lbl = lbl
    attachValueAPI(row)
    cb:SetScript("OnClick", function(self)
        local newV = self:GetChecked() and true or false
        local oldV = row._lastValue
        row._lastValue = newV
        row:_fireChange(newV, oldV)
    end)
    row._lastValue = cb:GetChecked() and true or false
    function row:Get() return self._cb:GetChecked() and true or false end
    function row:Set(v)
        local old = self:Get()
        self._cb:SetChecked(v and true or false)
        self._lastValue = v and true or false
        if old ~= self._lastValue then self:_fireChange(self._lastValue, old) end
    end
    return row
end

-- ============================================================================
-- EditBox: single-line text input. opts.label = leading label.
-- ============================================================================
function lib:EditBox(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local lbl
    if opts.label then
        lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(opts.label)
        row._lbl = lbl
    end

    local bg = CreateFrame("Frame", nil, row, "BackdropTemplate")
    bg:SetSize(opts.width or 200, 22)
    if lbl then bg:SetPoint("LEFT", lbl, "RIGHT", 8, 0) else bg:SetPoint("LEFT", row, "LEFT", 0, 0) end
    bg:SetBackdrop(DEFAULT_BACKDROP)
    bg:SetBackdropColor(unpack(THEME.bg))
    bg:SetBackdropBorderColor(unpack(THEME.border))

    local edit = CreateFrame("EditBox", nil, bg)
    edit:SetMultiLine(false); edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetPoint("LEFT", 6, 0); edit:SetPoint("RIGHT", -6, 0); edit:SetHeight(18)
    edit:SetText(opts.value or "")
    if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
    row._edit = edit
    attachValueAPI(row)

    row._lastValue = opts.value or ""
    edit:SetScript("OnTextChanged", function(self)
        local newV = self:GetText() or ""
        local oldV = row._lastValue
        if newV == oldV then return end
        row._lastValue = newV
        row:_fireChange(newV, oldV)
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    function row:Get() return self._edit:GetText() or "" end
    function row:Set(v)
        local old = self:Get()
        self._edit:SetText(v or "")
        if old ~= (v or "") then
            self._lastValue = v or ""
            self:_fireChange(self._lastValue, old)
        end
    end
    return row
end

-- ============================================================================
-- Slider: numeric Get/Set/OnChange.
-- ============================================================================
function lib:Slider(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(38)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    lbl:SetText(opts.label or "")
    row._lbl = lbl

    local valFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row._valFs = valFs

    local s = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
    s:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -16)
    s:SetMinMaxValues(opts.min or 0, opts.max or 1)
    s:SetValueStep(opts.step or 0.1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(opts.value or 0)
    if s.Low  then s.Low:SetText(tostring(opts.min or 0))  end
    if s.High then s.High:SetText(tostring(opts.max or 1)) end
    if s.Text then s.Text:SetText("") end
    row._slider = s
    attachValueAPI(row)

    local function showValue(v) valFs:SetText(string.format(opts.format or "%.2f", v)) end
    showValue(s:GetValue())

    row._lastValue = opts.value or 0
    s:SetScript("OnValueChanged", function(self, newV, _)
        local oldV = row._lastValue
        if newV == oldV then return end
        row._lastValue = newV
        showValue(newV)
        row:_fireChange(newV, oldV)
    end)

    function row:Get() return self._slider:GetValue() end
    function row:Set(v)
        self._slider:SetValue(v or 0)
        showValue(self._slider:GetValue())
    end
    return row
end

-- ============================================================================
-- Dropdown: choice from { value = label, ... }.
-- ============================================================================
function lib:Dropdown(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(28)

    local lbl
    if opts.label then
        lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(opts.label)
        row._lbl = lbl
    end

    local dd = CreateFrame("Frame", nil, row, "UIDropDownMenuTemplate")
    if lbl then dd:SetPoint("LEFT", lbl, "RIGHT", -8, -2)
    else        dd:SetPoint("LEFT", row, "LEFT",  -16, 0) end
    UIDropDownMenu_SetWidth(dd, opts.width or 160)
    row._dd = dd
    attachValueAPI(row)

    local choices = opts.choices or {}
    local function labelOf(value)
        return choices[value] or tostring(value)
    end
    UIDropDownMenu_SetText(dd, labelOf(opts.value))

    UIDropDownMenu_Initialize(dd, function(self, level)
        if level ~= 1 then return end
        for value, lab in pairs(choices) do
            local entry = UIDropDownMenu_CreateInfo()
            entry.text = lab
            entry.value = value
            entry.checked = (value == row._lastValue)
            entry.func = function()
                local oldV = row._lastValue
                row._lastValue = value
                UIDropDownMenu_SetText(dd, labelOf(value))
                row:_fireChange(value, oldV)
            end
            UIDropDownMenu_AddButton(entry, level)
        end
    end)

    row._lastValue = opts.value
    function row:Get() return self._lastValue end
    function row:Set(v)
        local old = self._lastValue
        self._lastValue = v
        UIDropDownMenu_SetText(self._dd, labelOf(v))
        if old ~= v then self:_fireChange(v, old) end
    end
    return row
end

-- ============================================================================
-- ColorSwatch: clickable color square; opens ColorPickerFrame.
-- ============================================================================
function lib:ColorSwatch(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local lbl
    if opts.label then
        lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(opts.label)
        row._lbl = lbl
    end

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(22, 22)
    if lbl then btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    else        btn:SetPoint("LEFT", row, "LEFT",  0, 0) end
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    swatch:SetColorTexture(1, 1, 1, 1)
    btn._swatch = swatch
    -- Border ring.
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    ring:SetDrawLayer("BACKGROUND", -1)

    row._btn = btn
    attachValueAPI(row)

    row._lastValue = opts.value or { 1, 1, 1, 1 }
    local function applySwatch(v)
        v = v or { 1, 1, 1, 1 }
        swatch:SetColorTexture(v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1)
    end
    applySwatch(row._lastValue)

    btn:SetScript("OnClick", function()
        local cur = row._lastValue or { 1, 1, 1, 1 }
        if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
            return  -- Older clients without the Setup helper; no-op.
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = cur[1] or 1, g = cur[2] or 1, b = cur[3] or 1, opacity = cur[4] or 1,
            hasOpacity = opts.hasOpacity ~= false,
            opacityFunc = function() end,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()) or (cur[4] or 1)
                local newV = { nr, ng, nb, na }
                local oldV = row._lastValue
                row._lastValue = newV
                applySwatch(newV)
                row:_fireChange(newV, oldV)
            end,
            cancelFunc = function() end,
        })
    end)

    function row:Get() return self._lastValue end
    function row:Set(v)
        local old = self._lastValue
        self._lastValue = v
        applySwatch(v)
        if old ~= v then self:_fireChange(v, old) end
    end
    return row
end

-- ============================================================================
-- KeybindButton: capture next non-modifier key, store as "CTRL-SHIFT-X" string.
-- ============================================================================
local _kbModal
local function ensureKeybindModal()
    if _kbModal then return _kbModal end
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(280, 110)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(false)
    f:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -10)
    f.title:SetText("Press a key combination")
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.body:SetPoint("CENTER", 0, -8)
    f.body:SetText("ESC to cancel.")
    _kbModal = f
    return f
end

function lib:KeybindButton(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local lbl
    if opts.label then
        lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(opts.label)
        row._lbl = lbl
    end

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(opts.width or 140, 22)
    if lbl then btn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    else        btn:SetPoint("LEFT", row, "LEFT",  0, 0) end
    row._btn = btn
    attachValueAPI(row)

    row._lastValue = opts.value or ""
    local function applyText() btn:SetText(row._lastValue ~= "" and row._lastValue or "(unbound)") end
    applyText()

    btn:SetScript("OnClick", function()
        local m = ensureKeybindModal()
        m:SetScript("OnKeyDown", function(self, k)
            if k == "ESCAPE" then self:Hide(); return end
            if k == "LSHIFT" or k == "RSHIFT" or k == "LCTRL" or k == "RCTRL"
                or k == "LALT" or k == "RALT" then return end
            local mods = ""
            if IsControlKeyDown() then mods = mods .. "CTRL-" end
            if IsAltKeyDown()     then mods = mods .. "ALT-"  end
            if IsShiftKeyDown()   then mods = mods .. "SHIFT-" end
            local combo = mods .. k
            local oldV = row._lastValue
            row._lastValue = combo
            applyText()
            row:_fireChange(combo, oldV)
            self:Hide()
        end)
        m:Show()
    end)

    function row:Get() return self._lastValue end
    function row:Set(v)
        local old = self._lastValue
        self._lastValue = v or ""
        applyText()
        if old ~= self._lastValue then self:_fireChange(self._lastValue, old) end
    end
    return row
end
