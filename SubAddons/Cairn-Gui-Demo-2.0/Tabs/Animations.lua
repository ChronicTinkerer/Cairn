--[[
Cairn-Gui-Demo-2.0 / Tabs / Animations

Click-to-play demos for every animation primitive: Animate, Sequence,
Parallel, Stagger, Tween, plus Spring physics. A ReduceMotion checkbox
toggles the global flag so the user can see the accessibility behavior.

Each demo button drives an "actor" Container (a small bordered square)
sitting in the panel below it. Repeated clicks restart the animation
mid-flight; the engine captures current value (and velocity for springs)
as the new from-state.

Cairn-Gui-Demo-2.0/Tabs/Animations (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

-- Build a "stage" panel with N actor squares the demo manipulates.
-- Returns the array of actors (Containers).
local function buildStage(parent, count)
	local stage = Gui:Acquire("Container", parent, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	stage:SetHeight(60)
	stage.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 12, padding = 12 })

	local actors = {}
	for i = 1, (count or 4) do
		local actor = Gui:Acquire("Container", stage)
		actor:SetSize(32, 32)
		actor.Cairn:DrawRect("bg", "color.accent.primary")
		actor.Cairn:DrawBorder("frame", "color.border.default", { width = 1 })
		actors[i] = actor
	end
	return actors, stage
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Animations -- Animate / Sequence / Parallel / Stagger / Spring",
		demo.Snippets.animations)
	if not live then return end

	-- 4 sections x ~120px + intro overflows the live pane. Scroll wrap.
	live = demo:MakeScrollable(live, 700)

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "Click each button to run the animation. Re-clicking captures the in-flight state as the new from-value, including spring velocity.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- ReduceMotion toggle -----------------------------------------

	local reduceCB = Gui:Acquire("Checkbox", live, {
		text    = "ReduceMotion (clamp every duration to zero)",
		checked = Gui.ReduceMotion and true or false,
		width   = 360,
	})
	reduceCB.Cairn:On("Toggled", function(_, v)
		Gui.ReduceMotion = v and true or false
	end)

	-- ---- Animate (multi-property) ------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Animate (multi-property: alpha + scale together)",
		variant = "heading",
		align   = "left",
	})

	local btnRow1 = Gui:Acquire("Container", live)
	btnRow1.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	btnRow1:SetHeight(28)

	local actors1 = buildStage(live, 4)

	local playMulti = Gui:Acquire("Button", btnRow1, {
		text = "Run alpha+scale", variant = "primary", width = 160,
	})
	local resetMulti = Gui:Acquire("Button", btnRow1, {
		text = "Reset", variant = "default", width = 80,
	})
	playMulti.Cairn:On("Click", function()
		for _, a in ipairs(actors1) do
			a.Cairn:Animate({
				alpha = { to = 0.4,  dur = 0.30, ease = "easeOut" },
				scale = { to = 1.20, dur = 0.30, ease = "easeOut" },
			})
		end
	end)
	resetMulti.Cairn:On("Click", function()
		for _, a in ipairs(actors1) do
			a.Cairn:Animate({
				alpha = { to = 1.0, dur = 0.20 },
				scale = { to = 1.0, dur = 0.20 },
			})
		end
	end)

	-- ---- Spring -------------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Spring physics (stiffness 220, damping 18)",
		variant = "heading",
		align   = "left",
	})

	local btnRow2 = Gui:Acquire("Container", live)
	btnRow2.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	btnRow2:SetHeight(28)

	local actors2 = buildStage(live, 4)

	local springBtn = Gui:Acquire("Button", btnRow2, {
		text = "Bounce!", variant = "primary", width = 120,
	})
	local toggle2 = false
	springBtn.Cairn:On("Click", function()
		toggle2 = not toggle2
		local target = toggle2 and 1.30 or 1.0
		for _, a in ipairs(actors2) do
			a.Cairn:Animate({
				scale = {
					to     = target,
					spring = { stiffness = 220, damping = 18, mass = 1 },
				},
			})
		end
	end)

	-- ---- Sequence -----------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Sequence (alpha out, alpha in)",
		variant = "heading",
		align   = "left",
	})

	local btnRow3 = Gui:Acquire("Container", live)
	btnRow3.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	btnRow3:SetHeight(28)

	local actors3 = buildStage(live, 4)

	local seqBtn = Gui:Acquire("Button", btnRow3, {
		text = "Blink", variant = "primary", width = 120,
	})
	seqBtn.Cairn:On("Click", function()
		for _, a in ipairs(actors3) do
			a.Cairn:Sequence({
				{ alpha = { to = 0.0, dur = 0.15 } },
				{ alpha = { to = 1.0, dur = 0.30 } },
			})
		end
	end)

	-- ---- Stagger ------------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Stagger (each actor starts 0.08s after the previous)",
		variant = "heading",
		align   = "left",
	})

	local btnRow4 = Gui:Acquire("Container", live)
	btnRow4.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	btnRow4:SetHeight(28)

	local actors4 = buildStage(live, 4)

	local stagBtn = Gui:Acquire("Button", btnRow4, {
		text = "Stagger pulse", variant = "primary", width = 160,
	})
	stagBtn.Cairn:On("Click", function()
		for i, a in ipairs(actors4) do
			-- Sequence per actor: scale up, then back down. The first
			-- step's `delay` defers the whole sequence start by
			-- (i-1)*0.08s so each actor visibly lags the previous.
			--
			-- Two back-to-back Animate calls on the same property would
			-- collide: the second replaces the first immediately, so the
			-- bounce never plays. Sequence is the correct primitive when
			-- you want N steps that flow into each other.
			a.Cairn:Sequence({
				{ scale = { to = 1.30, dur = 0.20, delay = (i - 1) * 0.08 } },
				{ scale = { to = 1.00, dur = 0.20 } },
			})
		end
	end)
end

Demo:RegisterTab("animations", {
	label = "Animations",
	order = 80,
	build = build,
})
