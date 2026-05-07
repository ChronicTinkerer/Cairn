--[[
Cairn-Gui-Demo-2.0 / Tabs / Themes

Live theme switcher: pick from a Dropdown of registered themes and watch
the demo's preview palette repaint. Includes a per-instance token
override so the cascade hierarchy is visible: instance > subtree >
active global > extends > library default.

The Demo registers two extra themes ("Demo.Vivid" and "Demo.Mono") at
file load and leaves Cairn.Default active so the rest of the demo
window doesn't change appearance until the user opts in.

Cairn-Gui-Demo-2.0/Tabs/Themes (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

-- Register the demo themes at file load (before any tab build), so the
-- Dropdown can list them on first open. Re-registration is idempotent
-- per the architecture's "last-write-wins with a debug log" contract.

Gui:RegisterTheme("Demo.Vivid", {
	extends = "Cairn.Default",
	tokens  = {
		["color.accent.primary"]                    = {0.95, 0.45, 0.20, 1.00},
		["color.accent.primary.hover"]              = {1.00, 0.55, 0.30, 1.00},
		["color.bg.button.primary"]                 = {0.92, 0.40, 0.15, 1.00},
		["color.bg.button.primary.hover"]           = {0.97, 0.50, 0.25, 1.00},
		["color.bg.button.primary.pressed"]         = {0.85, 0.35, 0.10, 1.00},
		["color.bg.panel"]                          = {0.04, 0.04, 0.06, 0.98},
		["color.bg.surface"]                        = {0.07, 0.07, 0.10, 0.98},
		["color.border.accent"]                     = {0.95, 0.45, 0.20, 1.00},
	},
})

Gui:RegisterTheme("Demo.Mono", {
	extends = "Cairn.Default",
	tokens  = {
		["color.accent.primary"]                    = {0.85, 0.85, 0.85, 1.00},
		["color.accent.primary.hover"]              = {0.95, 0.95, 0.95, 1.00},
		["color.bg.button.primary"]                 = {0.30, 0.30, 0.32, 1.00},
		["color.bg.button.primary.hover"]           = {0.40, 0.40, 0.42, 1.00},
		["color.bg.button"]                         = {0.16, 0.16, 0.18, 1.00},
		["color.bg.button.hover"]                   = {0.22, 0.22, 0.24, 1.00},
		["color.bg.panel"]                          = {0.08, 0.08, 0.09, 0.98},
		["color.bg.surface"]                        = {0.12, 0.12, 0.14, 0.98},
		["color.border.accent"]                     = {0.85, 0.85, 0.85, 1.00},
	},
})

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Themes -- live switcher and per-instance overrides",
		demo.Snippets.themes)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "Switching the active theme repaints every tracked widget after a short delay (Inspector walks the registry and calls Repaint on each).",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- Theme picker -------------------------------------------------

	local pickerRow = Gui:Acquire("Container", live)
	pickerRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	pickerRow:SetHeight(28)

	Gui:Acquire("Label", pickerRow, { text = "Active theme:", variant = "body" })

	local picker = Gui:Acquire("Dropdown", pickerRow, {
		options = {
			{ value = "Cairn.Default", label = "Cairn.Default" },
			{ value = "Demo.Vivid",    label = "Demo.Vivid"    },
			{ value = "Demo.Mono",     label = "Demo.Mono"     },
		},
		selected = Gui:GetActiveTheme() or "Cairn.Default",
		width    = 180,
	})

	-- ---- Preview palette ---------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Preview",
		variant = "heading",
		align   = "left",
	})

	local preview = Gui:Acquire("Container", live, {
		bg          = "color.bg.panel",
		border      = "color.border.default",
		borderWidth = 1,
	})
	preview:SetHeight(80)
	preview.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 10 })

	-- One button per variant, plus a primary with a per-instance override
	-- so the cascade order is visible.
	local previewButtons = {}
	for _, v in ipairs({ "default", "primary", "danger", "ghost" }) do
		previewButtons[v] = Gui:Acquire("Button", preview, {
			text    = v,
			variant = v,
			width   = 80,
		})
	end

	local override = Gui:Acquire("Button", preview, {
		text    = "override",
		variant = "primary",
		width   = 110,
	})
	-- Per-instance token override for one of the primary tokens. This
	-- wins over the active theme regardless of what the picker switches to.
	override.Cairn:SetTokenOverride("color.bg.button.primary",
		{0.20, 0.65, 0.40, 1.00})
	override.Cairn:SetTokenOverride("color.bg.button.primary.hover",
		{0.30, 0.75, 0.50, 1.00})
	override.Cairn:Repaint()

	-- Switch handler: SetActiveTheme + repaint each preview button.
	picker.Cairn:On("Changed", function(_, themeName)
		Gui:SetActiveTheme(themeName)
		for _, b in pairs(previewButtons) do
			b.Cairn:Repaint()
		end
		-- Override button: repaint, but instance override stays in effect.
		override.Cairn:Repaint()
	end)

	-- ---- Subtree theme demo ------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Subtree theme (this Container has SetTheme; its descendants paint differently from the rest)",
		variant = "muted",
		align   = "left",
		wrap    = true,
	})

	local subtree = Gui:Acquire("Container", live, {
		bg          = "color.bg.panel",
		border      = "color.border.accent",
		borderWidth = 1,
	})
	subtree:SetHeight(60)
	subtree.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 6, padding = 10 })
	subtree.Cairn:SetTheme("Demo.Vivid")

	for _, t in ipairs({ "Save", "Cancel", "Reset" }) do
		local b = Gui:Acquire("Button", subtree, {
			text = t, variant = (t == "Save") and "primary" or "default",
			width = 80,
		})
		b.Cairn:Repaint()
	end

	-- Status footer.
	Gui:Acquire("Label", live, {
		text    = "Cascade order on every paint: instance override -> subtree theme -> active global -> extends chain -> library defaults.",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
end

Demo:RegisterTab("themes", {
	label = "Themes",
	order = 60,
	build = build,
})
