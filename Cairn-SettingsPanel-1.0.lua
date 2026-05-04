--[[
Cairn-SettingsPanel-1.0

Renders a Cairn.Settings schema into a Cairn.Gui-based standalone panel.
Independent of Blizzard's Settings panel API - works on any client where
Cairn.Gui works (which is essentially any modern WoW build).

Public API:

    -- Most common path: just call settings:OpenStandalone(). Cairn.Settings
    -- proxies through to lib.OpenFor under the hood.
    settings:OpenStandalone()

    -- Lower-level entrypoint.
    local panel = Cairn.SettingsPanel.OpenFor(settings)
    panel:Hide() / :Show() / :Toggle()

Each schema entry renders as the matching Cairn.Gui widget:
    header   -> Header
    toggle   -> Checkbox
    range    -> Slider
    dropdown -> Dropdown
    text     -> EditBox
    color    -> ColorSwatch
    keybind  -> KeybindButton
    anchor   -> Label + "Open Edit Mode" button (delegates to Cairn.EditMode)
]]

local MAJOR, MINOR = "Cairn-SettingsPanel-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Gui = LibStub("Cairn-Gui-1.0", true)
if not Gui then
    error("Cairn-SettingsPanel-1.0 requires Cairn-Gui-1.0 to be loaded first.", 2)
end

-- Reuse Cairn.Gui's theme tokens so the panel matches other Cairn UIs.
local THEME = Gui.THEME

local PANEL_W = 460
local PANEL_H = 540
local PAD     = 10

-- ----- Build a row for a single schema entry ---------------------------
local function buildEntry(parent, settings, entry)
    local key = entry.key

    if entry.type == "header" then
        return Gui:Header(parent, entry.label or key)
    end

    -- Helper that proxies the widget's OnChange into settings:Set, which
    -- fires the schema's onChange callbacks + OnChange subscribers.
    local function bindWidget(w)
        w:OnChange(function(newV) settings:Set(key, newV) end)
        return w
    end

    if entry.type == "toggle" then
        return bindWidget(Gui:Checkbox(parent, {
            label = entry.label or key,
            value = settings:Get(key),
        }))

    elseif entry.type == "range" then
        return bindWidget(Gui:Slider(parent, {
            label = entry.label or key,
            min   = entry.min, max = entry.max, step = entry.step,
            value = settings:Get(key),
        }))

    elseif entry.type == "dropdown" then
        return bindWidget(Gui:Dropdown(parent, {
            label   = entry.label or key,
            choices = entry.choices,
            value   = settings:Get(key),
        }))

    elseif entry.type == "text" then
        return bindWidget(Gui:EditBox(parent, {
            label      = entry.label or key,
            value      = settings:Get(key),
            maxLetters = entry.maxLetters,
            width      = entry.width or 220,
        }))

    elseif entry.type == "color" then
        return bindWidget(Gui:ColorSwatch(parent, {
            label      = entry.label or key,
            value      = settings:Get(key),
            hasOpacity = entry.hasOpacity,
        }))

    elseif entry.type == "keybind" then
        return bindWidget(Gui:KeybindButton(parent, {
            label = entry.label or key,
            value = settings:Get(key),
        }))

    elseif entry.type == "anchor" then
        -- Cairn.SettingsPanel doesn't render the anchor itself; it delegates
        -- to Cairn.EditMode via a button. The actual frame position is
        -- managed by LibEditMode (when present) per Cairn.Settings's design.
        local row = Gui:HBox(parent, { gap = 8 })
        row:Add(Gui:Label(parent, "|cff" .. string.format("%02x%02x%02x",
            math.floor(THEME.textDim[1]*255), math.floor(THEME.textDim[2]*255), math.floor(THEME.textDim[3]*255))
            .. (entry.label or key) .. " (Edit Mode)|r", { wrap = false, height = 22 }))
        row:Add(Gui:Button(parent, "Open Edit Mode", {
            width = 120,
            onClick = function()
                local EditMode = LibStub("Cairn-EditMode-1.0", true)
                if EditMode and EditMode.Open then EditMode:Open() end
            end,
        }))
        return row
    end

    -- Unknown type: fall back to a label so the panel doesn't crash.
    return Gui:Label(parent, "(unsupported entry type: " .. tostring(entry.type) .. ")")
end

-- ----- The panel frame --------------------------------------------------
local function buildPanel(settings)
    local title = settings._addonName or "Settings"

    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(PANEL_W, PANEL_H)
    f:SetPoint("CENTER")
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    if f.title then
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    end
    if f.TitleText then f.TitleText:SetText(title) end
    if not f.TitleText and f.title then
        f.title:SetPoint("TOP", f.TitleBg or f, "TOP", 0, -3)
        f.title:SetText(title)
    end

    -- Scrollable content area.
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD,   -PAD * 2 - 8)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD * 3, PAD * 2)

    local body = Gui:VBox(sf, { padding = PAD, gap = 6 })
    body:SetSize(PANEL_W - PAD * 4, 1)
    sf:SetScrollChild(body)

    -- Add each schema entry.
    for _, entry in ipairs(settings._schema) do
        local widget = buildEntry(body, settings, entry)
        if widget then body:Add(widget) end
    end
    body:Layout()

    -- Footer close button.
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)

    function f:Toggle() if self:IsShown() then self:Hide() else self:Show() end end
    return f
end

-- ----- Public API -------------------------------------------------------

-- Returns (or lazily creates) the standalone panel for a given settings instance.
function lib.OpenFor(settings)
    if not settings or not settings._schema then return nil end
    if not settings._stdPanel then
        settings._stdPanel = buildPanel(settings)
    end
    settings._stdPanel:Show()
    return settings._stdPanel
end

function lib.HideFor(settings)
    if settings and settings._stdPanel then settings._stdPanel:Hide() end
end

function lib.ToggleFor(settings)
    if not settings then return end
    if not settings._stdPanel then return lib.OpenFor(settings) end
    settings._stdPanel:Toggle()
end
