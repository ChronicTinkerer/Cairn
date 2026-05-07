--[[
Cairn-Demo / Tabs / Events

Live demo of Cairn-Events-1.0. Subscribes a counter to PLAYER_TARGET_CHANGED
(easy to trigger -- click any unit). Two handlers under the same owner show
that owner-keyed subscription allows duplicates without ceremony.

Cairn-Demo/Tabs/Events (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui    = Demo.lib
local Events = LibStub("Cairn-Events-1.0")

-- Live state. Per-tab owner string so the demo's mass-unsubscribe doesn't
-- collide with anyone else's owner.
local OWNER = "CairnDemoEventsTab"

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Events-1.0",
		demo.Snippets.events)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Game-event subscription wrapping a single shared frame. Multiple handlers per (event, owner) without ceremony. Click anything in the world to fire PLAYER_TARGET_CHANGED.")

	-- Stats row.
	local stats = Gui:Acquire("Label", live, {
		text = "subscriptions: 0   |   fires seen: 0", variant = "small", align = "left",
	})
	local fireCount, subCount = 0, 0
	local off1, off2

	local function refresh()
		stats.Cairn:SetText(("subscriptions: %d   |   fires seen: %d"):format(subCount, fireCount))
	end

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 800 })

	local function handlerA()
		fireCount = fireCount + 1
		console:Print(("A: PLAYER_TARGET_CHANGED -> %s"):format(UnitName("target") or "(none)"))
		refresh()
	end
	local function handlerB()
		console:Print("B: same event, second handler under same owner")
	end

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, {
		text = "Subscribe A+B", variant = "primary",
	}).Cairn:On("Click", function()
		if off1 or off2 then return end
		off1 = Events:Subscribe("PLAYER_TARGET_CHANGED", handlerA, OWNER)
		off2 = Events:Subscribe("PLAYER_TARGET_CHANGED", handlerB, OWNER)
		subCount = 2
		console:Print("subscribed two handlers under owner " .. OWNER)
		refresh()
	end)

	Gui:Acquire("Button", row, {
		text = "Unsub A only", variant = "default",
	}).Cairn:On("Click", function()
		if off1 then off1(); off1 = nil; subCount = subCount - 1; console:Print("A off via closure"); refresh() end
	end)

	Gui:Acquire("Button", row, {
		text = "UnsubscribeAll(owner)", variant = "danger",
	}).Cairn:On("Click", function()
		Events:UnsubscribeAll(OWNER)
		off1, off2 = nil, nil
		subCount = 0
		console:Print("UnsubscribeAll: every " .. OWNER .. " handler removed")
		refresh()
	end)

	Gui:Acquire("Button", row, {
		text = "Has?", variant = "default",
	}).Cairn:On("Click", function()
		console:Print(("Events:Has('PLAYER_TARGET_CHANGED') -> %s")
			:format(tostring(Events:Has("PLAYER_TARGET_CHANGED"))))
	end)

	Gui:Acquire("Button", row, {
		text = "Clear log", variant = "default",
	}).Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("events", {
	label = "Events",
	order = 20,
	build = build,
})
