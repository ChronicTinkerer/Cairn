--[[
Cairn-Gui-Demo-2.0 / Tabs / Primitives

Six drawing primitives in isolation: Rect, Border, Icon, Divider, Glow,
Mask. Each one is rendered onto a small Container the demo registers as
a custom widget so it has access to the primitive draw methods on its
.Cairn namespace. (Standard Container already exposes them via Base.)

The state machine is also visible: the "state variants" demo wires a
hover/press/disabled bg variant table; mouse over and the rect color
animates via the transition token + Animation engine wiring.

Cairn-Gui-Demo-2.0/Tabs/Primitives (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local CELL_BODY_H = 80

local function makeCell(parent, title, w, h)
	local outer = Gui:Acquire("Container", parent)
	outer.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 0 })

	Gui:Acquire("Label", outer, {
		text    = title,
		variant = "small",
		align   = "left",
	})

	local body = Gui:Acquire("Container", outer)
	body:SetSize(w or 160, h or CELL_BODY_H)
	return body
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Primitives -- Rect, Border, Icon, Divider, Glow, Mask",
		demo.Snippets.primitives)
	if not live then return end

	-- 6 small cells in 3 cols + a full-width state cell beneath. Wrap in
	-- a ScrollFrame so the state cell never overflows.
	-- Layout: a vertical Stack with a Grid (small cells) on top and the
	-- state cell beneath; the Grid claims a fixed height itself.
	live = demo:MakeScrollable(live, 380)
	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 12, padding = 10 })

	-- Holder Container for the small-cells Grid. Set explicit height so
	-- the parent Stack reserves the right amount of space.
	local gridHolder = Gui:Acquire("Container", live)
	local CELL_H  = CELL_BODY_H + 28
	local GRID_H  = 2 * CELL_H + 12 + 2 * 10  -- 2 rows of 3 cells
	gridHolder:SetHeight(GRID_H)
	gridHolder.Cairn:SetLayout("Grid",
		{ columns = 3, rowGap = 12, colGap = 12, padding = 10,
		  cellHeight = CELL_H })

	-- Re-bind `live` for the small-cell makeCell calls below.
	local stateLive = live
	live = gridHolder

	-- ---- Rect ---------------------------------------------------------

	local rect = makeCell(live, "DrawRect (solid fill)")
	rect.Cairn:DrawRect("bg", "color.bg.button")

	-- ---- Border -------------------------------------------------------

	local border = makeCell(live, "DrawBorder (4-edge rectangle)")
	border.Cairn:DrawRect("bg", "color.bg.surface")
	border.Cairn:DrawBorder("frame", "color.border.accent", { width = 2 })

	-- ---- Icon ---------------------------------------------------------

	local icon = makeCell(live, "DrawIcon (atlas-or-path)")
	icon.Cairn:DrawRect("bg", "color.bg.surface")
	icon.Cairn:DrawIcon("check", "icon.check", {
		size    = 32,
		anchor  = "CENTER",
		color   = "color.accent.primary",
	})

	-- ---- Divider ------------------------------------------------------

	local divider = makeCell(live, "DrawDivider (thin line)")
	divider.Cairn:DrawRect("bg", "color.bg.surface")
	if divider.Cairn.DrawDivider then
		divider.Cairn:DrawDivider("hr", "color.border.accent", {
			orientation = "horizontal",
			thickness   = 1,
			inset       = 12,
		})
	end

	-- ---- Glow ---------------------------------------------------------

	local glow = makeCell(live, "DrawGlow (4-edge halo)")
	glow.Cairn:DrawRect("bg", "color.bg.surface")
	glow.Cairn:DrawBorder("frame", "color.border.subtle", { width = 1 })
	if glow.Cairn.DrawGlow then
		glow.Cairn:DrawGlow("halo", "color.accent.primary", { spread = 8 })
	end

	-- ---- Mask ---------------------------------------------------------

	local mask = makeCell(live, "DrawMask (clip a primitive)")
	mask.Cairn:DrawRect("bg", "color.bg.surface")
	if mask.Cairn.DrawMask then
		mask.Cairn:DrawMask("clip", { shape = "rounded", radius = 12 })
	end
	mask.Cairn:DrawRect("highlight", "color.accent.primary", { mask = "clip" })

	-- ---- State variants demo (full-row, parented under the scrollable
	-- live so it sits below the grid of small cells) ------------------

	local stateCell = Gui:Acquire("Container", stateLive)
	stateCell:SetHeight(90)
	stateCell.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 0 })

	Gui:Acquire("Label", stateCell, {
		text    = "State-variant DrawRect (hover / press) -- driven by the same primitive system",
		variant = "small",
		align   = "left",
	})

	local stateBox = Gui:Acquire("Container", stateCell)
	stateBox:SetSize(440, 60)
	stateBox.Cairn:DrawRect("bg", {
		default    = "color.bg.button",
		hover      = "color.bg.button.hover",
		pressed    = "color.bg.button.pressed",
		disabled   = "color.bg.button.disabled",
		transition = "duration.fast",
	})
	stateBox.Cairn:DrawBorder("frame", "color.border.default", { width = 1 })

	-- A label inside the state cell for affordance. Centered.
	local hint = Gui:Acquire("Label", stateBox, {
		text    = "Hover or click me",
		variant = "body",
		align   = "center",
	})
	hint.Cairn:SetLayoutManual(true)
	hint:SetAllPoints(stateBox)
end

Demo:RegisterTab("primitives", {
	label = "Primitives",
	order = 70,
	build = build,
})
