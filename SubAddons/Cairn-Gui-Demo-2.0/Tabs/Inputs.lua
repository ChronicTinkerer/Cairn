--[[
Cairn-Gui-Demo-2.0 / Tabs / Inputs

Form-style demo of every input widget the Standard bundle ships:
EditBox (with placeholder), Slider (with readout), Checkbox, Dropdown,
plus Label variants. A live "current values" readout updates from
each widget's events to prove the subscription model works.

Cairn-Gui-Demo-2.0/Tabs/Inputs (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Inputs -- EditBox, Slider, Checkbox, Dropdown, Label",
		demo.Snippets.inputs)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	-- Live readout label, captured by every input's event handler.
	local readout
	-- Forward declaration so handlers below can call updateReadout before
	-- the table itself is fully populated.
	local state = { editText = "", slider = 25, checkbox = false, dropdown = "medium" }
	local function updateReadout()
		if not readout then return end
		readout.Cairn:SetText(string.format(
			"text=%q  slider=%d  check=%s  size=%s",
			state.editText, state.slider, tostring(state.checkbox), state.dropdown))
	end

	Gui:Acquire("Label", live, {
		text    = "All four input widgets feed a single readout below via their semantic events.",
		variant = "muted",
		align   = "left",
		wrap    = true,
	})

	-- ---- EditBox ------------------------------------------------------

	local editRow = Gui:Acquire("Container", live)
	editRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	editRow:SetHeight(28)

	Gui:Acquire("Label", editRow, { text = "EditBox:", variant = "body" })

	local eb = Gui:Acquire("EditBox", editRow, {
		placeholder = "Type something...",
		width       = 220,
	})
	eb.Cairn:On("TextChanged", function(_, t)
		state.editText = t or ""
		updateReadout()
	end)

	-- ---- Slider -------------------------------------------------------

	local sliderRow = Gui:Acquire("Container", live)
	sliderRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	sliderRow:SetHeight(28)

	Gui:Acquire("Label", sliderRow, { text = "Slider:", variant = "body" })

	local sl = Gui:Acquire("Slider", sliderRow, {
		min = 0, max = 100, value = 25, step = 1,
		showValue = true,
		width     = 240,
	})
	sl.Cairn:On("Changed", function(_, v)
		state.slider = math.floor(v + 0.5)
		updateReadout()
	end)

	-- ---- Checkbox -----------------------------------------------------

	local cb = Gui:Acquire("Checkbox", live, {
		text    = "Checkbox: enable feature",
		checked = false,
		width   = 280,
	})
	cb.Cairn:On("Toggled", function(_, v)
		state.checkbox = v and true or false
		updateReadout()
	end)

	-- ---- Dropdown -----------------------------------------------------

	local ddRow = Gui:Acquire("Container", live)
	ddRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	ddRow:SetHeight(28)

	Gui:Acquire("Label", ddRow, { text = "Dropdown:", variant = "body" })

	local dd = Gui:Acquire("Dropdown", ddRow, {
		options = {
			{ value = "small",  label = "Small"  },
			{ value = "medium", label = "Medium" },
			{ value = "large",  label = "Large"  },
			{ value = "huge",   label = "Huge"   },
		},
		selected = "medium",
		width    = 160,
	})
	dd.Cairn:On("Changed", function(_, value)
		state.dropdown = value
		updateReadout()
	end)

	-- ---- Label variants ----------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Label variants",
		variant = "heading",
		align   = "left",
	})

	local variantRow = Gui:Acquire("Container", live)
	variantRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 12, padding = 0 })
	variantRow:SetHeight(20)

	for _, v in ipairs({ "body", "heading", "small", "muted",
	                    "danger", "success", "warning" }) do
		Gui:Acquire("Label", variantRow, {
			text = v, variant = v, align = "left",
		})
	end

	-- ---- Readout ------------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Live readout",
		variant = "heading",
		align   = "left",
	})

	readout = Gui:Acquire("Label", live, {
		text    = "(no inputs touched yet)",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
	updateReadout()
end

Demo:RegisterTab("inputs", {
	label = "Inputs",
	order = 20,
	build = build,
})
