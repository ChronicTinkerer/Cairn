--[[
Cairn-Gui-Demo-2.0 / Tabs / Layouts

Six built-in layout strategies (Manual, Fill, Stack, Grid, Form, Flex)
each rendered into a small bordered Container so the user can see what
they actually do. Strategy is set via the public RegisterLayout API
exactly the same way third parties would.

Cairn-Gui-Demo-2.0/Tabs/Layouts (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

-- Each demo cell has a title label + a 130px-tall body Container with
-- the requested layout strategy applied. The body is given an explicit
-- height because the parent Grid uses cellHeight (set below) to size
-- each cell, and the body needs to claim a known fraction of that.
local CELL_BODY_H = 150

local function makeCell(parent, title, layoutName, layoutOpts)
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
	body.Cairn:SetLayout(layoutName, layoutOpts or {})
	return body
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Layouts -- Manual, Fill, Stack, Grid, Form, Flex",
		demo.Snippets.layouts)
	if not live then return end

	-- 8 cells x ~176px overflows ~510px of live pane, so swap live for a
	-- scrollable container and let the cells flow inside.
	local CELL_H  = CELL_BODY_H + 26
	local TOTAL_H = 4 * CELL_H + 3 * 10 + 2 * 10  -- 4 rows + gaps + padding
	live = demo:MakeScrollable(live, TOTAL_H)
	live.Cairn:SetLayout("Grid",
		{ columns = 2, rowGap = 10, colGap = 12, padding = 10,
		  cellHeight = CELL_H })

	-- ---- Manual: children self-anchor; we just SetPoint two labels ---

	local manual = makeCell(live, "Manual (children self-anchor)", "Manual")
	local m1 = Gui:Acquire("Label", manual, { text = "TOPLEFT", variant = "body", align = "left" })
	m1.Cairn:SetLayoutManual(true)
	m1:ClearAllPoints()
	m1:SetPoint("TOPLEFT", manual, "TOPLEFT", 8, -8)
	m1:SetSize(80, 16)

	local m2 = Gui:Acquire("Label", manual, { text = "BOTTOMRIGHT", variant = "body", align = "right" })
	m2.Cairn:SetLayoutManual(true)
	m2:ClearAllPoints()
	m2:SetPoint("BOTTOMRIGHT", manual, "BOTTOMRIGHT", -8, 8)
	m2:SetSize(120, 16)

	-- ---- Fill: first child fills the parent ---------------------------

	local fill = makeCell(live, "Fill (first child fills parent)", "Fill",
		{ padding = 8 })
	Gui:Acquire("Container", fill, {
		bg          = "color.bg.button",
		border      = "color.border.accent",
		borderWidth = 1,
	})

	-- ---- Stack vertical -----------------------------------------------

	local stackV = makeCell(live, "Stack (vertical)", "Stack",
		{ direction = "vertical", gap = 4, padding = 8 })
	for i = 1, 4 do
		Gui:Acquire("Button", stackV, {
			text = "Item " .. i,
			variant = (i == 1) and "primary" or "default",
		})
	end

	-- ---- Stack horizontal ---------------------------------------------

	local stackH = makeCell(live, "Stack (horizontal)", "Stack",
		{ direction = "horizontal", gap = 4, padding = 8 })
	for _, t in ipairs({ "OK", "Apply", "Cancel" }) do
		Gui:Acquire("Button", stackH, { text = t })
	end

	-- ---- Grid ---------------------------------------------------------

	local grid = makeCell(live, "Grid (3 columns)", "Grid",
		{ columns = 3, rowGap = 4, colGap = 4, padding = 8, cellHeight = 24 })
	for i = 1, 9 do
		Gui:Acquire("Button", grid, { text = tostring(i), variant = "ghost" })
	end

	-- ---- Form ---------------------------------------------------------

	local form = makeCell(live, "Form (label / field pairs)", "Form",
		{ rowGap = 6, colGap = 8, padding = 8 })
	Gui:Acquire("Label",  form, { text = "Name:",  variant = "body", align = "right" })
	Gui:Acquire("EditBox", form, { width = 140 })
	Gui:Acquire("Label",  form, { text = "Volume:", variant = "body", align = "right" })
	Gui:Acquire("Slider", form, { min = 0, max = 100, value = 50, showValue = true, width = 140 })

	-- ---- Flex: row, justify=between -----------------------------------

	local flex = makeCell(live, "Flex (row, justify=between)", "Flex",
		{ direction = "row", justify = "between", align = "stretch",
		  gap = 4, padding = 8 })
	-- Three buttons: middle one grows.
	local fb1 = Gui:Acquire("Button", flex, { text = "Left",   variant = "default" })
	local fb2 = Gui:Acquire("Button", flex, { text = "Middle (flexGrow=1)", variant = "primary" })
	local fb3 = Gui:Acquire("Button", flex, { text = "Right",  variant = "default" })
	fb2.Cairn._flexGrow = 1

	-- ---- Flex: column align=center ------------------------------------

	local flexCol = makeCell(live, "Flex (column, align=center)", "Flex",
		{ direction = "column", justify = "center", align = "center",
		  gap = 4, padding = 8 })
	for _, t in ipairs({ "Top", "Middle", "Bottom" }) do
		Gui:Acquire("Button", flexCol, { text = t, variant = "ghost" })
	end
end

Demo:RegisterTab("layouts", {
	label = "Layouts",
	order = 40,
	build = build,
})
