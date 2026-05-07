--[[
Cairn-Gui-Demo-2.0 / Tabs / Containers

Three demos in one tab: a button that pops a secondary Window, an
inline ScrollFrame loaded with rows, and a nested TabGroup. All three
exercise different parts of the parent/child registry and Release
cascade.

Cairn-Gui-Demo-2.0/Tabs/Containers (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Containers -- Window, ScrollFrame, nested TabGroup",
		demo.Snippets.containers)
	if not live then return end

	-- 3 sub-demos (popup button + ScrollFrame + nested TabGroup) plus
	-- their headings sit close to the live pane's vertical limit. Wrap
	-- in a ScrollFrame so adjustments don't push the bottom off-screen.
	live = demo:MakeScrollable(live, 540)

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	-- ---- Pop-up Window ------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Window -- click to spawn a secondary draggable window",
		variant = "heading",
		align   = "left",
	})

	local popupBtn = Gui:Acquire("Button", live, {
		text    = "Open a child Window",
		variant = "primary",
		width   = 200,
	})

	-- We track the popup so repeated clicks don't pile up frames.
	local popup
	popupBtn.Cairn:On("Click", function()
		if popup and popup:IsShown() then
			popup:Hide()
			return
		end
		if not popup then
			-- Cairn-Gui-2.0 MINOR 19 made the host Window default to
			-- HIGH strata, so a default-DIALOG popup automatically
			-- layers above the demo. No explicit strata override
			-- needed; this Acquire uses Window's new default.
			popup = Gui:Acquire("Window", UIParent, {
				title    = "Child Window",
				width    = 320,
				height   = 180,
				closable = true,
				strata   = "DIALOG",  -- explicit: this Window IS a popup
			})
			popup:ClearAllPoints()
			popup:SetPoint("TOP", UIParent, "CENTER", 0, -120)

			local body = popup.Cairn:GetContent()
			body.Cairn:SetLayout("Stack",
				{ direction = "vertical", gap = 6, padding = 12 })

			Gui:Acquire("Label", body, {
				text    = "I'm a separate Window. Drag my title bar; click X to close.",
				variant = "body",
				wrap    = true,
				align   = "left",
			})
			Gui:Acquire("Label", body, {
				text    = "I'm tracked under the demo via the Cairn child registry but parented to UIParent for visibility.",
				variant = "muted",
				wrap    = true,
				align   = "left",
			})
			Gui:Acquire("Button", body, {
				text    = "Re-open me from the parent tab",
				variant = "default",
				width   = 280,
			})
		end
		popup:Show()
	end)

	-- ---- ScrollFrame --------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "ScrollFrame -- vertical scroll, mouse wheel + drag thumb",
		variant = "heading",
		align   = "left",
	})

	local sf = Gui:Acquire("ScrollFrame", live, {
		bg            = "color.bg.surface",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = 30 * 22 + 16,
		showScrollbar = true,
	})
	sf:SetHeight(160)

	local scrollContent = sf.Cairn:GetContent()
	scrollContent.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 2, padding = 6 })

	for i = 1, 30 do
		Gui:Acquire("Label", scrollContent, {
			text    = ("Row %02d -- ScrollFrame content scrolls regardless of how tall it is."):format(i),
			variant = (i % 5 == 0) and "warning" or "body",
			align   = "left",
		})
	end

	-- ---- Nested TabGroup ----------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "TabGroup nested inside another TabGroup -- legal, no special handling required",
		variant = "heading",
		align   = "left",
	})

	local nested = Gui:Acquire("TabGroup", live, {
		tabs = {
			{ id = "first",  label = "Inner 1" },
			{ id = "second", label = "Inner 2" },
			{ id = "third",  label = "Inner 3" },
		},
		selected  = "first",
		tabHeight = 24,
	})
	nested:SetHeight(110)

	for i, id in ipairs({ "first", "second", "third" }) do
		local p = nested.Cairn:GetTabContent(id)
		p.Cairn:SetLayout("Stack",
			{ direction = "vertical", gap = 4, padding = 8 })
		Gui:Acquire("Label", p, {
			text    = ("Inner tab %d content."):format(i),
			variant = "heading",
			align   = "left",
		})
		Gui:Acquire("Label", p, {
			text    = "TabGroup parents tab buttons + content panes through its own internal Container, so nesting works without any special-case code.",
			variant = "muted",
			align   = "left",
			wrap    = true,
		})
	end
end

Demo:RegisterTab("containers", {
	label = "Containers",
	order = 30,
	build = build,
})
