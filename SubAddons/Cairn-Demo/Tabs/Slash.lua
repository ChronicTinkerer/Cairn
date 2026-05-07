--[[
Cairn-Demo / Tabs / Slash

Live demo of Cairn-Slash-1.0. Demo.slash is the /cdemo router itself
(registered in Core.lua), so this tab inspects it and exercises :Run /
:Args programmatically.

Cairn-Demo/Tabs/Slash (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local Cairn = Demo.cairn

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Slash-1.0",
		demo.Snippets.slash)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Generic slash-command router. The /cdemo command this addon registers IS a Cairn.Slash. The buttons below trigger its subcommands programmatically via :Run.")

	local s = demo.slash

	-- Inspect existing subcommands.
	Gui:Acquire("Label", live, {
		text = "Registered subcommands", variant = "heading", align = "left",
	})
	-- Public introspection (Cairn-Slash MINOR 2+). Falls back to a
	-- "lib too old" notice if the user has an older Cairn-Slash.
	if s and s.GetSubcommands then
		for _, def in ipairs(s:GetSubcommands()) do
			Gui:Acquire("Label", live, {
				text    = ("/cdemo %s   %s"):format(def.name, def.help or ""),
				variant = "small", align = "left", wrap = true,
			})
		end
	else
		Gui:Acquire("Label", live, {
			text    = "[Cairn-Slash MINOR < 2 -- :GetSubcommands() not available]",
			variant = "muted", align = "left",
		})
	end

	-- :Run programmatic dispatch.
	Gui:Acquire("Label", live, {
		text = "Programmatic dispatch", variant = "heading", align = "left",
	})

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = ":Run('show')", variant = "default" })
		.Cairn:On("Click", function() s:Run("show") end)
	Gui:Acquire("Button", row, { text = ":Run('hide')", variant = "default" })
		.Cairn:On("Click", function() s:Run("hide") end)
	Gui:Acquire("Button", row, { text = ":Run('help')", variant = "default" })
		.Cairn:On("Click", function() s:Run("help") end)

	-- :Args quote-aware splitter.
	Gui:Acquire("Label", live, {
		text = ":Args splitter", variant = "heading", align = "left",
	})
	local sample = [[hello "two words" three]]
	Gui:Acquire("Label", live, {
		text    = ("input: %s"):format(sample),
		variant = "small", align = "left",
	})
	local out = s:Args(sample)
	Gui:Acquire("Label", live, {
		text    = "tokens: " .. table.concat(out or {}, "  |  "),
		variant = "success", align = "left", wrap = true,
	})

	-- Lookup by name.
	Gui:Acquire("Label", live, {
		text = "Cairn.Slash.Get('CairnDemo')", variant = "heading", align = "left",
	})
	local fetched = Cairn.Slash.Get("CairnDemo")
	Gui:Acquire("Label", live, {
		text    = ("identity check: %s"):format(tostring(fetched == s)),
		variant = (fetched == s) and "success" or "muted",
		align   = "left",
	})
end

Demo:RegisterTab("slash", {
	label = "Slash",
	order = 70,
	build = build,
})
