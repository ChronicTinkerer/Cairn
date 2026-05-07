--[[
Cairn-Demo / Tabs / FSM

Live demo of Cairn-FSM-1.0. Builds a small spec with idle/running/error
states plus a delayed transition from idle to ready, and lets the user
drive it with Send buttons. Subscribes to Transition / Enter:* events
to log every state change.

Cairn-Demo/Tabs/FSM (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local FSM = LibStub("Cairn-FSM-1.0")

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-FSM-1.0",
		demo.Snippets.fsm)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Flat state machine with named transitions, async (delayed) transitions, and lifecycle events. Drive the machine with the Send buttons below; transitions stream into the console.")

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 800 })

	-- Spec.
	local spec = FSM.New({
		initial = "idle",
		states = {
			idle    = { on = {
				START = "running",
				GO    = { target = "ready", delay = 1.0 },
			} },
			running = { on = { STOP = "idle", FAIL = "error" } },
			ready   = { on = { GO   = "running" } },
			error   = { onEnter = function(m, payload)
				console:Print(("[onEnter:error] payload=%s"):format(tostring(payload)))
			end },
		},
		owner = "CairnDemo.FSMTab",
	})
	local m = spec:Instantiate()

	m:On("Transition", function(_, machine, from, to, evt)
		console:Print(("[transition] %s -> %s   via %s"):format(from, to, evt))
	end)
	m:On("Rejected", function(_, machine, evt, reason)
		console:Print(("[rejected]  %s   reason=%s"):format(evt, tostring(reason)))
	end)
	m:On("Cancelled", function(_, machine, pending)
		console:Print(("[cancelled] pending=%s"):format(tostring(pending and pending.evt)))
	end)

	-- Status bar.
	local statusLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "small", align = "left",
	})
	local function refresh()
		local pending = m:Pending()
		statusLbl.Cairn:SetText(("state=%s   pending=%s"):format(
			tostring(m:State()),
			pending and (pending.from .. "->" .. pending.to .. " via " .. pending.evt) or "(none)"))
	end
	refresh()

	-- Refresh after every transition.
	m:On("Transition", function() refresh() end)
	m:On("Cancelled",  function() refresh() end)

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Send START", variant = "primary" })
		.Cairn:On("Click", function() m:Send("START"); refresh() end)
	Gui:Acquire("Button", row, { text = "Send STOP", variant = "default" })
		.Cairn:On("Click", function() m:Send("STOP"); refresh() end)
	Gui:Acquire("Button", row, { text = "Send GO (1s delay)", variant = "default" })
		.Cairn:On("Click", function() m:Send("GO"); refresh() end)
	Gui:Acquire("Button", row, { text = "Send FAIL 'boom'", variant = "danger" })
		.Cairn:On("Click", function() m:Send("FAIL", "boom"); refresh() end)

	local row2 = Gui:Acquire("Container", live, {})
	row2.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row2:SetHeight(28)

	Gui:Acquire("Button", row2, { text = "Cancel pending", variant = "default" })
		.Cairn:On("Click", function() m:Cancel(); refresh() end)
	Gui:Acquire("Button", row2, { text = "Reset", variant = "default" })
		.Cairn:On("Click", function() m:Reset(); refresh() end)
	Gui:Acquire("Button", row2, { text = "Can('START')?", variant = "default" })
		.Cairn:On("Click", function()
			console:Print(("Can('START') -> %s"):format(tostring(m:Can("START"))))
		end)
	Gui:Acquire("Button", row2, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("fsm", {
	label = "FSM",
	order = 130,
	build = build,
})
