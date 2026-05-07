--[[
Cairn-SettingsPanel-2.0

Renders a Cairn.Settings schema into a standalone panel built entirely
on Cairn-Gui-2.0 widgets. Drop-in successor to Cairn-SettingsPanel-1.0
with the same public surface; consumers calling settings:OpenStandalone()
get the v2-rendered panel automatically once both libs are loaded
(Cairn-Settings prefers v2 with a v1 fallback).

Public API (matches v1):

    -- Most common path: just call settings:OpenStandalone(). Cairn.Settings
    -- proxies through to lib.OpenFor under the hood.
    settings:OpenStandalone()

    -- Lower-level entrypoint.
    local panel = LibStub("Cairn-SettingsPanel-2.0").OpenFor(settings)
    panel:Show() / :Hide() / :Toggle()

    Cairn.SettingsPanel.HideFor(settings)
    Cairn.SettingsPanel.ToggleFor(settings)

Schema -> widget mapping (full v1 parity, all 8 types):
    header   -> Cairn-Gui-2.0 Label, variant = "heading"
    toggle   -> Cairn-Gui-2.0 Checkbox
    range    -> Cairn-Gui-2.0 Slider
    dropdown -> Cairn-Gui-2.0 Dropdown
    text     -> Cairn-Gui-2.0 EditBox
    anchor   -> Cairn-Gui-2.0 Label + Button delegating to Cairn.EditMode
    color    -> Cairn-Gui-2.0 Button + Container swatch, opens
                Blizzard ColorPickerFrame on click; round-trips r/g/b/a
                back into the settings via Settings:Set
    keybind  -> Cairn-Gui-2.0 Button; click enters capture mode and the
                next key press is bound (modifier-aware, supports
                Escape to clear)

Why not in Cairn-Gui-2.0 directly: the GUI bundle is widget-only by
design. Mapping a settings SCHEMA to widgets is consumer logic that
sits one layer up, so it lives next to the v1 panel as its own lib.

Cairn-SettingsPanel-2.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-SettingsPanel-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Gui = LibStub("Cairn-Gui-2.0", true)
if not Gui then
	error("Cairn-SettingsPanel-2.0 requires Cairn-Gui-2.0 to be loaded first.", 2)
end

-- Standard widget bundle. We need Window / Container / ScrollFrame /
-- Label / Button / Checkbox / Slider / Dropdown / EditBox. The bundle
-- registers all of those at load.
local Std = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Std then
	error("Cairn-SettingsPanel-2.0 requires Cairn-Gui-Widgets-Standard-2.0 to be loaded first.", 2)
end

local Log = LibStub("Cairn-Log-1.0", true)
local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.SettingsPanel-2.0") end
	return lib._log
end

local PANEL_W = 460
local PANEL_H = 540
local PAD     = 10
local ROW_GAP = 6

-- ----- Helpers -----------------------------------------------------------

-- Format an {r,g,b,a} default into a hex label like "#FFAA00FF" so the
-- color swatch button has something readable when the value is unset.
local function colorToHex(c)
	if type(c) ~= "table" then return "(unset)" end
	local r = math.floor((c.r or 1) * 255 + 0.5)
	local g = math.floor((c.g or 1) * 255 + 0.5)
	local b = math.floor((c.b or 1) * 255 + 0.5)
	if c.a ~= nil then
		local a = math.floor((c.a or 1) * 255 + 0.5)
		return string.format("#%02X%02X%02X%02X", r, g, b, a)
	end
	return string.format("#%02X%02X%02X", r, g, b)
end

-- Open Blizzard's ColorPickerFrame for an entry, wiring round-trip into
-- settings:Set(key, {r, g, b, a}). Modern Retail uses
-- ColorPickerFrame:SetupColorPickerAndShow({...}); we use the field
-- shape that's been stable since DF 10.2.5.
local function openColorPicker(settings, entry, refreshLabel)
	local key = entry.key
	local current = settings:Get(key) or { r = 1, g = 1, b = 1, a = 1 }

	local function onCommit()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a
		if entry.hasOpacity and ColorPickerFrame.GetColorAlpha then
			a = ColorPickerFrame:GetColorAlpha()
		end
		local out = { r = r, g = g, b = b }
		if entry.hasOpacity then out.a = a or 1 end
		settings:Set(key, out)
		if refreshLabel then refreshLabel() end
	end

	local function onCancel(prev)
		settings:Set(key, prev)
		if refreshLabel then refreshLabel() end
	end

	local snapshot = {
		r = current.r or 1, g = current.g or 1, b = current.b or 1,
		a = current.a or 1,
	}

	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = snapshot.r, g = snapshot.g, b = snapshot.b,
			opacity     = entry.hasOpacity and (snapshot.a or 1) or nil,
			hasOpacity  = entry.hasOpacity and true or false,
			swatchFunc  = onCommit,
			opacityFunc = entry.hasOpacity and onCommit or nil,
			cancelFunc  = function() onCancel(snapshot) end,
		})
	else
		-- Pre-DF fallback path (rare in the modern client tier matrix
		-- Cairn ships against, but harmless to keep).
		if logger() then logger():Warn("ColorPickerFrame.SetupColorPickerAndShow not available") end
	end
end

-- A keybind capture overlay. Click the keybind button to enter capture;
-- the next key press is bound (Escape clears). Implemented as a
-- transparent fullscreen Frame that registers OnKeyDown so any key fires.
local _captureFrame
local function captureKeybind(settings, entry, refreshLabel)
	if not _captureFrame then
		_captureFrame = CreateFrame("Frame", nil, UIParent)
		_captureFrame:SetAllPoints(UIParent)
		_captureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		_captureFrame:EnableKeyboard(true)
		_captureFrame:Hide()
	end

	-- Capture handler bound fresh each invocation so it closes over the
	-- right entry / settings.
	_captureFrame:SetScript("OnKeyDown", function(self, key)
		self:Hide()
		self:SetScript("OnKeyDown", nil)
		if key == "ESCAPE" then
			settings:Set(entry.key, "")
		else
			-- Compose modifier prefix the same way Blizzard's keybind UI
			-- does ("ALT-CTRL-SHIFT-X" with sorted modifiers).
			local mods = {}
			if IsAltKeyDown   and IsAltKeyDown()   then mods[#mods + 1] = "ALT"   end
			if IsControlKeyDown and IsControlKeyDown() then mods[#mods + 1] = "CTRL"  end
			if IsShiftKeyDown and IsShiftKeyDown() then mods[#mods + 1] = "SHIFT" end
			local prefix = (#mods > 0) and (table.concat(mods, "-") .. "-") or ""
			settings:Set(entry.key, prefix .. key)
		end
		if refreshLabel then refreshLabel() end
	end)
	_captureFrame:Show()
	if logger() then logger():Info("keybind capture: press a key (Esc to clear)") end
end

-- ----- One row per schema entry -----------------------------------------

local function buildRow(parent, settings, entry)
	local key = entry.key

	if entry.type == "header" then
		return Gui:Acquire("Label", parent, {
			text    = entry.label or key,
			variant = "heading",
			align   = "left",
			wrap    = true,
		})
	end

	-- Toggle / Range / Dropdown / EditBox: their setters round-trip
	-- straight back into Settings:Set via the widget's Changed event.

	-- Helper: build a "label + widget" horizontal row. Slider, Dropdown,
	-- EditBox don't take a built-in label opt in Cairn-Gui-2.0, so we wrap
	-- the widget alongside a Label in a horizontal Stack. (Checkbox takes
	-- its label via opts.text, so no wrapper there.)
	local function labeledRow(labelText)
		local row = Gui:Acquire("Container", parent, {})
		row.Cairn:SetLayout("Stack",
			{ direction = "horizontal", gap = 8, padding = 0 })
		row:SetHeight(28)
		Gui:Acquire("Label", row, {
			text    = labelText,
			variant = "muted",
			align   = "left",
			wrap    = false,
			width   = 140,
		})
		return row
	end

	if entry.type == "toggle" then
		-- Checkbox bakes the label in via opts.text. Event is "Toggled".
		local cb = Gui:Acquire("Checkbox", parent, {
			text    = entry.label or key,
			checked = settings:Get(key) and true or false,
		})
		cb.Cairn:On("Toggled", function(_, value) settings:Set(key, value and true or false) end)
		return cb
	end

	if entry.type == "range" then
		local row = labeledRow(entry.label or key)
		local sl = Gui:Acquire("Slider", row, {
			min       = entry.min  or 0,
			max       = entry.max  or 1,
			step      = entry.step or 0.1,
			value     = settings:Get(key) or entry.default or 0,
			showValue = true,
			width     = 220,
		})
		sl.Cairn:On("Changed", function(_, value) settings:Set(key, value) end)
		return row
	end

	if entry.type == "dropdown" then
		-- Schema uses choices = { value = label } map; v2 Dropdown wants
		-- options = { {value=, label=}, ... }. Convert + sort by label.
		local options = {}
		for v, lbl in pairs(entry.choices or {}) do
			options[#options + 1] = { value = v, label = lbl }
		end
		table.sort(options, function(a, b) return tostring(a.label) < tostring(b.label) end)
		local row = labeledRow(entry.label or key)
		local dd = Gui:Acquire("Dropdown", row, {
			options  = options,
			selected = settings:Get(key) or entry.default,
			width    = 200,
		})
		dd.Cairn:On("Changed", function(_, value) settings:Set(key, value) end)
		return row
	end

	if entry.type == "text" then
		local row = labeledRow(entry.label or key)
		local eb = Gui:Acquire("EditBox", row, {
			text        = settings:Get(key) or "",
			placeholder = entry.placeholder,
			maxLetters  = entry.maxLetters,
			width       = entry.width or 220,
		})
		-- v2 EditBox uses "TextChanged" (not "Changed").
		eb.Cairn:On("TextChanged", function(_, value) settings:Set(key, value) end)
		return row
	end

	if entry.type == "anchor" then
		-- v1 parity: a label + "Open Edit Mode" button delegating to
		-- Cairn-EditMode. Anchor positions are stored by LibEditMode (when
		-- present); the panel doesn't render a draggable preview itself.
		local row = Gui:Acquire("Container", parent, {})
		row.Cairn:SetLayout("Stack",
			{ direction = "horizontal", gap = 8, padding = 0 })
		row:SetHeight(28)

		Gui:Acquire("Label", row, {
			text    = (entry.label or key) .. " (Edit Mode)",
			variant = "muted",
			align   = "left",
			wrap    = false,
		})
		local btn = Gui:Acquire("Button", row, {
			text    = "Open Edit Mode",
			variant = "default",
		})
		btn.Cairn:On("Click", function()
			local EM = LibStub("Cairn-EditMode-1.0", true)
			if EM and EM.Open then EM:Open() end
		end)
		return row
	end

	if entry.type == "color" then
		-- Composite: Label + colored Container swatch + "Pick" Button.
		-- Click the button to open Blizzard's ColorPickerFrame; the
		-- swatch tints itself from settings:Get on commit + cancel.
		local row = Gui:Acquire("Container", parent, {})
		row.Cairn:SetLayout("Stack",
			{ direction = "horizontal", gap = 8, padding = 0 })
		row:SetHeight(28)

		Gui:Acquire("Label", row, {
			text    = entry.label or key,
			variant = "muted",
			align   = "left",
			wrap    = false,
		})

		-- Swatch: a small Container with a colored bg texture. We tint it
		-- via the underlying frame's bg texture since Cairn-Gui-2.0
		-- exposes a bg = "color.token" path that's static; we want a
		-- LIVE color. Use a child texture on the frame directly.
		local swatch = Gui:Acquire("Container", row, {
			border      = "color.border.subtle",
			borderWidth = 1,
		})
		swatch:SetSize(40, 20)
		local tex = swatch:CreateTexture(nil, "BACKGROUND")
		tex:SetAllPoints()

		local hexLbl = Gui:Acquire("Label", row, {
			text    = colorToHex(settings:Get(key)),
			variant = "small",
			align   = "left",
			wrap    = false,
		})

		local function refreshSwatch()
			local c = settings:Get(key) or { r = 1, g = 1, b = 1 }
			tex:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
			hexLbl.Cairn:SetText(colorToHex(c))
		end
		refreshSwatch()

		local btn = Gui:Acquire("Button", row, {
			text    = "Pick...",
			variant = "default",
		})
		btn.Cairn:On("Click", function()
			openColorPicker(settings, entry, refreshSwatch)
		end)
		return row
	end

	if entry.type == "keybind" then
		local row = Gui:Acquire("Container", parent, {})
		row.Cairn:SetLayout("Stack",
			{ direction = "horizontal", gap = 8, padding = 0 })
		row:SetHeight(28)

		Gui:Acquire("Label", row, {
			text    = entry.label or key,
			variant = "muted",
			align   = "left",
			wrap    = false,
		})

		local btn = Gui:Acquire("Button", row, {
			text    = (settings:Get(key) ~= "" and settings:Get(key)) or "(unbound)",
			variant = "default",
		})
		local function refreshBtn()
			btn.Cairn:SetText((settings:Get(key) ~= "" and settings:Get(key)) or "(unbound)")
		end
		btn.Cairn:On("Click", function()
			btn.Cairn:SetText("press a key (Esc clears)")
			captureKeybind(settings, entry, refreshBtn)
		end)
		return row
	end

	-- Unknown type: fall back to a placeholder Label so the panel doesn't
	-- crash on a typo'd schema entry. Mirrors v1's behavior.
	return Gui:Acquire("Label", parent, {
		text    = ("(unsupported entry type: %s)"):format(tostring(entry.type)),
		variant = "muted",
		align   = "left",
		wrap    = true,
	})
end

-- ----- Panel construction -----------------------------------------------

local function buildPanel(settings)
	local title = settings._addonName or "Settings"

	-- Window default strata is HIGH (Cairn-Gui-Widgets-Standard-2.0
	-- MINOR 3+). The settings panel IS itself a popup-ish dialog; pass
	-- DIALOG explicitly so it layers above any host Window calling
	-- :OpenStandalone (per the strata convention from the gap-list pass).
	local win = Gui:Acquire("Window", UIParent, {
		title  = title,
		width  = PANEL_W,
		height = PANEL_H,
		strata = "DIALOG",
	})
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	local content = win.Cairn:GetContent()
	content.Cairn:SetLayoutManual(true)

	-- Scroll frame fills the content area minus the footer Close button.
	local sf = Gui:Acquire("ScrollFrame", content, {
		bg            = "color.bg.surface",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = 800,
		showScrollbar = true,
	})
	sf.Cairn:SetLayoutManual(true)
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT",     content, "TOPLEFT",     PAD, -PAD)
	sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, PAD * 2 + 24)

	local body = sf.Cairn:GetContent()
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = ROW_GAP, padding = PAD })

	-- Render every schema entry.
	for _, entry in ipairs(settings._schema or {}) do
		buildRow(body, settings, entry)
	end

	-- Footer Close button anchored to the bottom-right of the content area.
	local close = Gui:Acquire("Button", content, {
		text    = "Close",
		variant = "default",
	})
	close.Cairn:SetLayoutManual(true)
	close:ClearAllPoints()
	close:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, PAD)
	close:SetSize(80, 22)
	close.Cairn:On("Click", function() win:Hide() end)

	-- Add :Toggle for symmetry with v1's panel API. :Show / :Hide come
	-- with the underlying frame.
	win.Toggle = function(self)
		if self:IsShown() then self:Hide() else self:Show() end
	end

	return win
end

-- ----- Public API -------------------------------------------------------

function lib.OpenFor(settings)
	if not settings or not settings._schema then return nil end
	if not settings._stdPanelV2 then
		settings._stdPanelV2 = buildPanel(settings)
	end
	settings._stdPanelV2:Show()
	return settings._stdPanelV2
end

function lib.HideFor(settings)
	if settings and settings._stdPanelV2 then settings._stdPanelV2:Hide() end
end

function lib.ToggleFor(settings)
	if not settings then return end
	if not settings._stdPanelV2 then return lib.OpenFor(settings) end
	if settings._stdPanelV2:IsShown() then
		settings._stdPanelV2:Hide()
	else
		settings._stdPanelV2:Show()
	end
end
