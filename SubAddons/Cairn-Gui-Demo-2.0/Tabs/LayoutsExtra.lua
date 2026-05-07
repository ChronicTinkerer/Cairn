--[[
Cairn-Gui-Demo-2.0 / Tabs / LayoutsExtra

The optional Cairn-Gui-Layouts-Extra-2.0 bundle ships two extra layout
strategies: Hex (axial-coord hex grid) and Polar (radial arrangement).
This tab renders both. If the bundle isn't loaded, the tab shows a
gentle notice instead of trying to lay out things that can't move.

Cairn-Gui-Demo-2.0/Tabs/LayoutsExtra (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local CELL_BODY_H = 220

local function makeCell(parent, title)
	local outer = Gui:Acquire("Container", parent)
	outer.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 0 })

	Gui:Acquire("Label", outer, {
		text    = title,
		variant = "small",
		align   = "left",
	})

	local body = Gui:Acquire("Container", outer, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	body:SetHeight(CELL_BODY_H)
	return body
end

local function buildExtraNotLoaded(live)
	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "Cairn-Gui-Layouts-Extra-2.0 isn't loaded.",
		variant = "warning",
		align   = "left",
	})
	Gui:Acquire("Label", live, {
		text    = "It's an OPTIONAL bundle separate from the Standard widgets. The library still works without it; only Hex and Polar layouts are unavailable. The Cairn distribution ships it; if you don't see it loaded, your Cairn.toc may not be including it.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Layouts Extra -- Hex, Polar (optional bundle)",
		demo.Snippets.layoutsextra)
	if not live then return end

	if not demo.extra then
		buildExtraNotLoaded(live)
		return
	end

	-- 4 cells x ~248px in 2 columns = 2 rows of ~496px, exceeds the live
	-- pane's vertical space. Wrap in scroll.
	local CELL_H = CELL_BODY_H + 28
	live = demo:MakeScrollable(live, 2 * CELL_H + 10 + 2 * 10)
	live.Cairn:SetLayout("Grid",
		{ columns = 2, rowGap = 10, colGap = 12, padding = 10,
		  cellHeight = CELL_H })

	-- ---- Hex pointy-top ----------------------------------------------

	local hexPointy = makeCell(live, "Hex (pointy-top, 4 columns)")
	hexPointy.Cairn:SetLayout("Hex", {
		columns     = 4,
		cellSize    = 22,
		orientation = "pointy",
		gap         = 2,
		padding     = 4,
	})
	for i = 1, 12 do
		Gui:Acquire("Button", hexPointy, {
			text    = tostring(i),
			variant = (i % 4 == 0) and "primary" or "ghost",
		})
	end

	-- ---- Hex flat-top -------------------------------------------------

	local hexFlat = makeCell(live, "Hex (flat-top, 5 columns)")
	hexFlat.Cairn:SetLayout("Hex", {
		columns     = 5,
		cellSize    = 18,
		orientation = "flat",
		gap         = 2,
		padding     = 4,
	})
	for i = 1, 15 do
		Gui:Acquire("Button", hexFlat, {
			text    = "",
			variant = (i % 3 == 0) and "danger" or "default",
		})
	end

	-- ---- Polar full-circle -------------------------------------------

	local polarFull = makeCell(live, "Polar (full circle)")
	polarFull.Cairn:SetLayout("Polar", {
		radius     = 70,
		startAngle = 90,
		direction  = "ccw",
		cellSize   = 28,
	})
	for i = 1, 8 do
		Gui:Acquire("Button", polarFull, {
			text    = tostring(i),
			variant = "primary",
		})
	end

	-- ---- Polar arc ---------------------------------------------------

	local polarArc = makeCell(live, "Polar (arc, 0..180 deg)")
	polarArc.Cairn:SetLayout("Polar", {
		radius     = 70,
		startAngle = 0,
		endAngle   = 180,
		direction  = "ccw",
		cellSize   = 26,
	})
	for _, label in ipairs({ "A", "B", "C", "D", "E" }) do
		Gui:Acquire("Button", polarArc, { text = label, variant = "default" })
	end
end

Demo:RegisterTab("layoutsextra", {
	label = "Layouts Extra",
	order = 50,
	build = build,
})
