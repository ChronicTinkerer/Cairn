--[[
Cairn-Gui-Demo-2.0 / Tabs / Buttons

Renders one of every Button variant: default, primary, danger, ghost.
Plus a disabled-state demo and a click-counter that proves multi-
subscriber events fire. The right-side code panel quotes the exact
Acquire calls.

Cairn-Gui-Demo-2.0/Tabs/Buttons (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Buttons -- variants, states, click events",
		demo.Snippets.buttons)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 10, padding = 12 })

	-- Intro line.
	Gui:Acquire("Label", live, {
		text    = "Four built-in variants, automatic hover/press transitions via the state machine, and the disabled state.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- Variant row ---------------------------------------------------
	-- A horizontal Stack of one button per variant. Wrap that row in a
	-- Container so the parent's vertical Stack treats it as one entry.

	local variantRow = Gui:Acquire("Container", live)
	variantRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	-- Manual height so the parent vertical Stack reserves space.
	variantRow:SetHeight(36)

	local variants = { "default", "primary", "danger", "ghost" }
	local clickCounter = { count = 0 }
	local counterLabel  -- forward decl for closure capture below

	for _, v in ipairs(variants) do
		local btn = Gui:Acquire("Button", variantRow, {
			text    = v,
			variant = v,
			width   = 86,
		})
		-- First subscriber: bump the global counter.
		btn.Cairn:On("Click", function(_, mouseButton)
			clickCounter.count = clickCounter.count + 1
			if counterLabel then
				counterLabel.Cairn:SetText(("Last clicked: %s (%s) -- total %d"):format(
					v, tostring(mouseButton), clickCounter.count))
			end
		end)
		-- Second subscriber on a tag: prove multi-subscriber works.
		-- (No-op visually, but the EventLog on the Inspector tab will
		-- show two entries per click.)
		btn.Cairn:On("Click", function() end, "demo-buttons")
	end

	counterLabel = Gui:Acquire("Label", live, {
		text    = "Last clicked: (none yet)",
		variant = "small",
		align   = "left",
		wrap    = true,
	})

	-- ---- Disabled state row -------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Disabled state",
		variant = "heading",
		align   = "left",
	})

	local disabledRow = Gui:Acquire("Container", live)
	disabledRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	disabledRow:SetHeight(36)

	-- One enabled, one disabled, side by side.
	Gui:Acquire("Button", disabledRow, {
		text = "Enabled", variant = "primary", width = 100,
	})

	local disabledBtn = Gui:Acquire("Button", disabledRow, {
		text = "Disabled", variant = "primary", width = 100,
	})
	disabledBtn.Cairn:SetEnabled(false)

	-- Toggle helper: a third button flips the disabled one back and forth.
	local toggleBtn = Gui:Acquire("Button", disabledRow, {
		text = "Toggle disabled state", variant = "default", width = 180,
	})
	local toggled = true
	toggleBtn.Cairn:On("Click", function()
		toggled = not toggled
		disabledBtn.Cairn:SetEnabled(not toggled)
		disabledBtn.Cairn:SetText(toggled and "Disabled" or "Enabled now")
	end)

	-- ---- Intrinsic sizing demo ----------------------------------------
	-- Buttons report their own intrinsic size via GetIntrinsicSize, which
	-- the Stack layout uses to wrap them. Show three buttons with very
	-- different label lengths and let the row size them naturally.

	Gui:Acquire("Label", live, {
		text    = "Intrinsic sizing -- horizontal Stack reads each child's GetIntrinsicSize() to decide widths.",
		variant = "muted",
		align   = "left",
		wrap    = true,
	})

	local intrinsicRow = Gui:Acquire("Container", live)
	intrinsicRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 6, padding = 0 })
	intrinsicRow:SetHeight(36)

	for _, label in ipairs({ "OK", "Apply", "A much longer label" }) do
		Gui:Acquire("Button", intrinsicRow, { text = label, variant = "default" })
	end
end

Demo:RegisterTab("buttons", {
	label = "Buttons",
	order = 10,
	build = build,
})
