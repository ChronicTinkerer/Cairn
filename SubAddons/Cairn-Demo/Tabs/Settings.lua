--[[
Cairn-Demo / Tabs / Settings

Live demo of Cairn-Settings-1.0 + Cairn-SettingsPanel-1.0. Builds a real
schema against Demo.db, demonstrates :Get/:Set/:OnChange wiring, and gives
buttons to open both the Blizzard Settings panel and the standalone
Cairn-Gui-1.0 panel.

Cairn-Demo/Tabs/Settings (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local Cairn = Demo.cairn

-- Build the schema once at file scope (no DB reads here -- New() doesn't
-- touch db.profile until Get/Set is called).
local _settings = nil
local function ensureSettings(demo)
	if _settings then return _settings end
	_settings = Cairn.Settings.New("Cairn-Demo", demo.db, {
		-- All 8 schema types so the standalone panel renderer exercises
		-- every code path (header / toggle / range / dropdown / text /
		-- anchor / color / keybind).
		{ key = "h1",       type = "header",   label = "Display" },
		{ key = "scale",    type = "range",    label = "Scale",
		  min = 0.5, max = 2.0, step = 0.1, default = 1.0 },
		{ key = "welcome",  type = "toggle",   label = "Show welcome",
		  default = true },
		{ key = "label",    type = "dropdown", label = "Greeting",
		  default = "Hello",
		  choices = { Hello = "Hello", Hi = "Hi", Howdy = "Howdy", Aloha = "Aloha" } },

		{ key = "h2",       type = "header",   label = "Customization" },
		{ key = "tagline",  type = "text",     label = "Tagline",
		  default     = "",
		  placeholder = "type a tagline...",
		  maxLetters  = 60 },
		{ key = "color",    type = "color",    label = "Accent color",
		  default    = { r = 0.30, g = 0.65, b = 1.00 },
		  hasOpacity = false },

		{ key = "h3",       type = "header",   label = "Bindings" },
		{ key = "hotkey",   type = "keybind",  label = "Open Cairn-Demo",
		  default = "" },

		{ key = "h4",       type = "header",   label = "Position" },
		{ key = "anchor",   type = "anchor",   label = "Frame anchor",
		  default = { point = "CENTER", x = 0, y = 0 },
		  frame   = UIParent },
	})
	return _settings
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Settings-1.0  +  Cairn-SettingsPanel-2.0",
		demo.Snippets.settings)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Declarative schema bridged to both Blizzard's modern Settings panel and a standalone Cairn-Gui-2.0-rendered panel. Schema lives in this tab's file; values persist in Demo.db.profile.")

	local settings = ensureSettings(demo)

	-- Live readout of values.
	local readout = Gui:Acquire("Label", live, {
		text = "...", variant = "body", align = "left", wrap = true,
	})
	local function refresh()
		readout.Cairn:SetText(("scale=%.1f   welcome=%s   label=%q"):format(
			settings:Get("scale") or 0,
			tostring(settings:Get("welcome")),
			tostring(settings:Get("label"))))
	end
	refresh()

	-- Subscribe to one of the keys to log change events to chat.
	settings:OnChange("scale", function(v, old)
		print(("|cFF7FBFFF[CairnDemo]|r scale: %s -> %s"):format(tostring(old), tostring(v)))
		refresh()
	end, "CairnDemo.SettingsTab")

	-- Action row.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Open Blizzard Settings", variant = "primary" })
		.Cairn:On("Click", function() settings:Open() end)

	Gui:Acquire("Button", row, { text = "Open Standalone Panel", variant = "primary" })
		.Cairn:On("Click", function()
			-- Settings:OpenStandalone prefers Cairn-SettingsPanel-2.0
			-- (Cairn-Gui-2.0 widgets) with a v1 fallback when only v1 is
			-- present. Same public call regardless.
			if settings.OpenStandalone then
				settings:OpenStandalone()
			else
				print("|cFF7FBFFF[CairnDemo]|r Cairn-Settings:OpenStandalone unavailable")
			end
		end)

	Gui:Acquire("Button", row, { text = "Set scale = 1.0", variant = "default" })
		.Cairn:On("Click", function() settings:Set("scale", 1.0); refresh() end)
	Gui:Acquire("Button", row, { text = "Set scale = 1.5", variant = "default" })
		.Cairn:On("Click", function() settings:Set("scale", 1.5); refresh() end)
	Gui:Acquire("Button", row, { text = "Refresh", variant = "default" })
		.Cairn:On("Click", refresh)
end

Demo:RegisterTab("settings", {
	label = "Settings",
	order = 50,
	build = build,
})
