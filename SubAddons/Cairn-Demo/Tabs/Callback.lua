--[[
Cairn-Demo / Tabs / Callback

Live demo of Cairn-Callback-1.0. Builds a private registry, adds two
subscribers under different keys, fires events, and shows the dispatch
order + the OnUsed/OnUnused hooks firing as subscribers come and go.

Cairn-Demo/Tabs/Callback (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui      = Demo.lib
local Callback = LibStub("Cairn-Callback-1.0")

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Callback-1.0",
		demo.Snippets.callback)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Registry-style :Subscribe / :Fire dispatcher. Subscribers are keyed by (event, key); same key replaces. OnUsed fires on the first subscriber for an event; OnUnused fires when the last one leaves.")

	-- Per-tab fresh registry + a "two subscribers, different keys" demo.
	local reg = Callback.New("CairnDemoCallback")

	-- Console panel for watching events fly.
	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })

	local _, console = demo:Console(consoleHolder, { contentHeight = 800 })

	-- Wire registry hooks to the console.
	reg:SetOnUsed(function(_, evt)   console:Print(("[onUsed]   first sub for %s"):format(evt)) end)
	reg:SetOnUnused(function(_, evt) console:Print(("[onUnused] last  sub for %s gone"):format(evt)) end)

	local keyA, keyB = {}, {}
	local function subA(evt, payload) console:Print(("A got %s -> %s"):format(evt, tostring(payload.id))) end
	local function subB(evt, payload) console:Print(("B got %s -> %s"):format(evt, tostring(payload.id))) end

	-- Action row.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, {
		text = "Subscribe A", variant = "primary",
	}).Cairn:On("Click", function()
		reg:Subscribe("Saved", keyA, subA)
		console:Print("subscribed A")
	end)

	Gui:Acquire("Button", row, {
		text = "Subscribe B", variant = "primary",
	}).Cairn:On("Click", function()
		reg:Subscribe("Saved", keyB, subB)
		console:Print("subscribed B")
	end)

	Gui:Acquire("Button", row, {
		text = "Fire Saved", variant = "default",
	}).Cairn:On("Click", function()
		reg:Fire("Saved", { id = math.random(100) })
	end)

	Gui:Acquire("Button", row, {
		text = "Unsub A", variant = "default",
	}).Cairn:On("Click", function()
		reg:Unsubscribe("Saved", keyA)
		console:Print("unsubscribed A")
	end)

	Gui:Acquire("Button", row, {
		text = "Unsub B", variant = "default",
	}).Cairn:On("Click", function()
		reg:Unsubscribe("Saved", keyB)
		console:Print("unsubscribed B")
	end)

	Gui:Acquire("Button", row, {
		text = "Clear", variant = "default",
	}).Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("callback", {
	label = "Callback",
	order = 10,
	build = build,
})
