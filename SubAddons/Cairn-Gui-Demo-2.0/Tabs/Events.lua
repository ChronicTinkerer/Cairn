--[[
Cairn-Gui-Demo-2.0 / Tabs / Events

Multi-subscriber events demonstrated by attaching three handlers to one
Button. Each handler increments its own counter; clicking the button
proves they all fire. A "Off by tag" button removes the second handler
to demonstrate selective detach. A Once handler vanishes after one click.

Cairn-Gui-Demo-2.0/Tabs/Events (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Events -- multi-subscriber, tags, Once, Forward",
		demo.Snippets.events)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "One Button, three subscribers, plus a Once handler. Detaching by tag removes only the second.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- The shared button.
	local target = Gui:Acquire("Button", live, {
		text    = "Click me",
		variant = "primary",
		width   = 200,
	})

	-- Counter readouts.
	local counters = { a = 0, b = 0, c = 0, once = 0 }
	local rA = Gui:Acquire("Label", live, { text = "handler A: 0", variant = "body", align = "left" })
	local rB = Gui:Acquire("Label", live, { text = "handler B (tag=plugin): 0", variant = "body", align = "left" })
	local rC = Gui:Acquire("Label", live, { text = "handler C: 0", variant = "body", align = "left" })
	local rOnce = Gui:Acquire("Label", live, { text = "handler Once: 0 (will detach after first click)", variant = "body", align = "left" })

	-- Three regular subscribers + one Once.
	target.Cairn:On("Click", function()
		counters.a = counters.a + 1
		rA.Cairn:SetText(("handler A: %d"):format(counters.a))
	end)
	target.Cairn:On("Click", function()
		counters.b = counters.b + 1
		rB.Cairn:SetText(("handler B (tag=plugin): %d"):format(counters.b))
	end, "plugin")
	target.Cairn:On("Click", function()
		counters.c = counters.c + 1
		rC.Cairn:SetText(("handler C: %d"):format(counters.c))
	end)
	target.Cairn:Once("Click", function()
		counters.once = counters.once + 1
		rOnce.Cairn:SetText(("handler Once: %d (DETACHED)"):format(counters.once))
	end)

	-- Detach controls.
	Gui:Acquire("Label", live, {
		text    = "Detach controls",
		variant = "heading",
		align   = "left",
	})

	local detachRow = Gui:Acquire("Container", live)
	detachRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	detachRow:SetHeight(28)

	local offTag = Gui:Acquire("Button", detachRow, {
		text = "OffByTag('plugin')", variant = "default", width = 180,
	})
	offTag.Cairn:On("Click", function()
		target.Cairn:OffByTag("plugin")
		rB.Cairn:SetVariant("muted")
		rB.Cairn:SetText("handler B (tag=plugin): DETACHED")
	end)

	local offAll = Gui:Acquire("Button", detachRow, {
		text = "Off() (nuke everything)", variant = "danger", width = 200,
	})
	offAll.Cairn:On("Click", function()
		target.Cairn:Off()
		rA.Cairn:SetVariant("muted"); rA.Cairn:SetText("handler A: DETACHED")
		rB.Cairn:SetVariant("muted"); rB.Cairn:SetText("handler B (tag=plugin): DETACHED")
		rC.Cairn:SetVariant("muted"); rC.Cairn:SetText("handler C: DETACHED")
		rOnce.Cairn:SetVariant("muted"); rOnce.Cairn:SetText("handler Once: DETACHED")
	end)

	-- Note: the offAll button itself has its own subscription, attached
	-- separately. target.Cairn:Off() only nukes target's subscriptions,
	-- not offAll's.

	-- ---- Forward demo -------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Forward (re-fire 'Click' from target onto a satellite widget)",
		variant = "heading",
		align   = "left",
	})

	local satellite = Gui:Acquire("Button", live, {
		text    = "Satellite (forwarded counter: 0)",
		variant = "ghost",
		width   = 280,
	})
	local satCount = 0
	satellite.Cairn:On("Click", function()
		satCount = satCount + 1
		satellite.Cairn:SetText(("Satellite (forwarded counter: %d)"):format(satCount))
	end)
	-- The Forward call: when target fires Click, satellite fires Click too.
	-- That triggers satellite's subscriber above.
	target.Cairn:Forward("Click", satellite)
end

Demo:RegisterTab("events", {
	label = "Events",
	order = 90,
	build = build,
})
