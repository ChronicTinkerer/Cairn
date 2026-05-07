--[[
Cairn-Demo / Tabs / Sequencer

Live demo of Cairn-Sequencer-1.0. Builds a 4-step sequence that increments
a counter; each click of "Step" calls :Execute. Reset/Abort buttons exercise
the lifecycle. OnStep / OnComplete / OnAbort / OnReset all fan out to the
console.

Cairn-Demo/Tabs/Sequencer (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local Seq = LibStub("Cairn-Sequencer-1.0")

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Sequencer-1.0",
		demo.Snippets.sequencer)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Composable step-runner. Each step returns truthy to advance. The buttons below drive a 4-step demo sequence.")

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 200,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 600 })

	-- Steps just return true (always-advance) for the demo.
	local seq = Seq.New({
		function(s) return true end,
		function(s) return true end,
		function(s) return true end,
		function(s) return true end,
	}, {
		onStep     = function(_, idx)   console:Print(("[onStep]   completed step %d"):format(idx)) end,
		onComplete = function()         console:Print("[onComplete] sequence done") end,
		onAbort    = function()         console:Print("[onAbort]    sequence aborted") end,
		onReset    = function()         console:Print("[onReset]    sequence reset") end,
	})

	-- Status bar.
	local statusLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "small", align = "left",
	})
	local function refresh()
		statusLbl.Cairn:SetText(("status=%s   index=%d/%d   progress=%.0f%%   finished=%s"):format(
			tostring(seq:Status()), seq:Index(), seq:Total(),
			(seq:Progress() or 0) * 100, tostring(seq:Finished())))
	end
	refresh()

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Execute", variant = "primary" })
		.Cairn:On("Click", function() seq:Execute(); refresh() end)
	Gui:Acquire("Button", row, { text = "Reset", variant = "default" })
		.Cairn:On("Click", function() seq:Reset(); refresh() end)
	Gui:Acquire("Button", row, { text = "Abort", variant = "danger" })
		.Cairn:On("Click", function() seq:Abort(); refresh() end)
	Gui:Acquire("Button", row, { text = "Append step", variant = "default" })
		.Cairn:On("Click", function()
			seq:Append(function(s) return true end)
			console:Print(("appended; total=%d"):format(seq:Total()))
			refresh()
		end)
	Gui:Acquire("Button", row, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("sequencer", {
	label = "Sequencer",
	order = 110,
	build = build,
})
