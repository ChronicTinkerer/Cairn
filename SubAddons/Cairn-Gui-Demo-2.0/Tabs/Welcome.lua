--[[
Cairn-Gui-Demo-2.0 / Tabs / Welcome

The first tab. Acts as a directory: states what the addon is, lists the
loaded library bundles + version, and spells out what each subsequent
tab demonstrates.

Cairn-Gui-Demo-2.0/Tabs/Welcome (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Welcome to the Cairn-Gui-2.0 Demo",
		demo.Snippets.welcome)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	-- Headline.
	Gui:Acquire("Label", live, {
		text    = "An author-facing showcase of every Cairn-Gui-2.0 feature.",
		variant = "body",
		wrap    = true,
		align   = "left",
	})

	Gui:Acquire("Label", live, {
		text    = "Each tab on the left renders a single capability live, with the exact code on the right.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- Version block.
	local _, libMinor = Gui:GetVersion()
	Gui:Acquire("Label", live, {
		text    = "Loaded bundles",
		variant = "heading",
		align   = "left",
	})

	local function addRow(text, ok)
		Gui:Acquire("Label", live, {
			text    = (ok and "[OK] " or "[--] ") .. text,
			variant = ok and "success" or "muted",
			align   = "left",
			wrap    = true,
		})
	end

	addRow(("Cairn-Gui-2.0 (Core, MINOR=%d)"):format(libMinor), true)
	addRow("Cairn-Gui-Widgets-Standard-2.0", demo.standard ~= nil)
	addRow("Cairn-Gui-Theme-Default-2.0",     demo.theme    ~= nil)
	addRow("Cairn-Gui-Widgets-Secure-2.0",   demo.secure   ~= nil)
	addRow("Cairn-Gui-Layouts-Extra-2.0",    demo.extra    ~= nil)

	-- Tab directory. Lists every tab the demo registers, in display order,
	-- with a one-line summary.
	Gui:Acquire("Label", live, {
		text    = "Tab guide",
		variant = "heading",
		align   = "left",
	})

	local guide = {
		buttons      = "Variants, states, click events, intrinsic sizing.",
		inputs       = "EditBox, Slider, Checkbox, Dropdown, Label.",
		containers   = "Window, ScrollFrame, nested TabGroup.",
		layouts      = "Stack, Fill, Grid, Form, Flex strategies live.",
		layoutsextra = "Hex + Polar from the optional bundle.",
		themes       = "Live theme switcher and per-instance overrides.",
		primitives   = "Six drawing primitives at the raw API level.",
		animations   = "Tween, Sequence, Parallel, Stagger, Spring.",
		events       = "Multi-subscriber, tags, Once, Forward.",
		l10n         = "@namespace:key resolution via Cairn-Locale.",
		inspector    = "Stats, EventLog, and the introspection API.",
		secure       = "ActionButton + combat queue + fake combat toggle.",
		contracts    = "RunContracts() one-shot health check.",
	}

	for _, def in ipairs(demo._tabOrder) do
		if def.id ~= "welcome" then
			local hint = guide[def.id] or ""
			Gui:Acquire("Label", live, {
				text    = ("- %s -- %s"):format(def.label, hint),
				variant = "body",
				align   = "left",
				wrap    = true,
			})
		end
	end
end

Demo:RegisterTab("welcome", {
	label = "Welcome",
	order = 0,
	build = build,
})
