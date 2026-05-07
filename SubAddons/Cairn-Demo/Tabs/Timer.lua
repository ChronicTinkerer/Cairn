--[[
Cairn-Demo / Tabs / Timer

Live demo of Cairn-Timer-1.0. Demonstrates one-shot, ticker, named
debounce, and CancelAll-by-owner.

Cairn-Demo/Tabs/Timer (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui   = Demo.lib
local Timer = LibStub("Cairn-Timer-1.0")

local OWNER = "CairnDemo.TimerTab"

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Timer-1.0",
		demo.Snippets.timer)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Owner-grouped timers + named-timer debounce. Every timer registered here uses owner '" .. OWNER .. "' so 'Cancel all' nukes them in one call.")

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 800 })

	local statusLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "small", align = "left",
	})
	local function refresh()
		statusLbl.Cairn:SetText(("CountByOwner('%s') = %d"):format(
			OWNER, Timer:CountByOwner(OWNER) or 0))
	end
	refresh()

	-- Auto-refresh status every 0.25s while the tab is open. (Uses a
	-- separate owner so "Cancel all" doesn't kill our refresher.)
	Timer:NewTicker(0.25, refresh, "CairnDemo.TimerTab.refresh")

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "After 1.0s", variant = "primary" })
		.Cairn:On("Click", function()
			Timer:After(1.0, function() console:Print("[After]    1.0s elapsed -> ping") end, OWNER)
			console:Print("scheduled After 1.0s")
		end)

	Gui:Acquire("Button", row, { text = "NewTicker 0.5s x5", variant = "primary" })
		.Cairn:On("Click", function()
			local count = 0
			Timer:NewTicker(0.5, function()
				count = count + 1
				console:Print(("[Ticker]   tick %d/5"):format(count))
			end, OWNER, 5)
			console:Print("scheduled NewTicker 0.5s x5")
		end)

	Gui:Acquire("Button", row, { text = "Schedule 'save' 2.0s (debounce)", variant = "default" })
		.Cairn:On("Click", function()
			Timer:Schedule("save", 2.0, function() console:Print("[Schedule] save fired") end, OWNER)
			console:Print("Schedule('save', 2.0s) -- click again within 2s to debounce")
		end)

	Gui:Acquire("Button", row, { text = "CancelByName 'save'", variant = "default" })
		.Cairn:On("Click", function()
			local removed = Timer:CancelByName("save")
			console:Print(("CancelByName('save') -> %s"):format(tostring(removed)))
		end)

	Gui:Acquire("Button", row, { text = "Cancel all (owner)", variant = "danger" })
		.Cairn:On("Click", function()
			local n = Timer:CountByOwner(OWNER) or 0
			Timer:CancelAll(OWNER)
			console:Print(("CancelAll('%s') -> killed %d timers"):format(OWNER, n))
		end)

	Gui:Acquire("Button", row, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("timer", {
	label = "Timer",
	order = 120,
	build = build,
})
