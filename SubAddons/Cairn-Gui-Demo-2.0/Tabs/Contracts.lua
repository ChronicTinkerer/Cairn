--[[
Cairn-Gui-Demo-2.0 / Tabs / Contracts

Click "Run contracts" to invoke Cairn.Gui:RunContracts() and dump every
per-kind bucket (widgets / layouts / themes / easings) into the live
panel. Includes a "register a deliberately broken widget" toggle so the
warn path actually has something to report.

Cairn-Gui-Demo-2.0/Tabs/Contracts (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Contracts -- one-shot validators across every registration",
		demo.Snippets.contracts)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "RunContracts() walks every registered widget / layout / theme / easing and validates the registration shape. Warnings are gentle: they DON'T unregister the offender, they just notify.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- Action row ---------------------------------------------------

	local actionRow = Gui:Acquire("Container", live)
	actionRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	actionRow:SetHeight(28)

	local runBtn = Gui:Acquire("Button", actionRow, {
		text = "Run contracts now", variant = "primary", width = 200,
	})
	local registerBad = Gui:Acquire("Button", actionRow, {
		text = "Register a broken widget", variant = "default", width = 200,
	})

	-- ---- Output -------------------------------------------------------

	local outBox = Gui:Acquire("ScrollFrame", live, {
		bg            = "color.bg.surface",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = 600,
	})
	outBox:SetHeight(220)

	local outContent = outBox.Cairn:GetContent()
	outContent.Cairn:SetLayoutManual(true)

	local outLabel = Gui:Acquire("Label", outContent, {
		text    = "(click 'Run contracts now' to populate)",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
	outLabel.Cairn:SetLayoutManual(true)
	outLabel:SetPoint("TOPLEFT",  outContent, "TOPLEFT",  6, -6)
	outLabel:SetPoint("TOPRIGHT", outContent, "TOPRIGHT", -6, -6)

	-- ---- Run handler --------------------------------------------------

	runBtn.Cairn:On("Click", function()
		if not Gui.RunContracts then
			outLabel.Cairn:SetText("RunContracts not available on this Core MINOR")
			return
		end
		local result = Gui:RunContracts()
		local lines = {}

		local function appendBucket(name, bucket)
			lines[#lines + 1] = string.format("[%s] ok=%d  warnings=%d",
				name, bucket.ok or 0, (bucket.warn and #bucket.warn) or 0)
			if bucket.warn then
				for _, w in ipairs(bucket.warn) do
					lines[#lines + 1] = string.format("    - %q: %s",
						tostring(w.name), tostring(w.msg))
				end
			end
		end

		appendBucket("widgets", result.widgets)
		appendBucket("layouts", result.layouts)
		appendBucket("themes",  result.themes)
		appendBucket("easings", result.easings)

		outLabel.Cairn:SetText(table.concat(lines, "\n"))
		local _, ih = outLabel.Cairn:GetIntrinsicSize()
		if ih and ih > 0 then
			outBox.Cairn:SetContentHeight(ih + 12)
			outLabel:SetHeight(ih + 4)
		end
	end)

	-- ---- Broken-widget injector --------------------------------------
	-- Intentionally registers a widget def that violates the contract
	-- (mixin missing, frameType missing). RunContracts should report it.

	registerBad.Cairn:On("Click", function()
		Gui:RegisterWidget("CairnGuiDemo.BrokenWidget", {
			-- frameType deliberately omitted (will be defaulted to "Frame"
			-- by RegisterWidget normalization, but we leave reset wrong:)
			pool  = true,
			reset = "this should be a function",  -- contract violation
			-- mixin defaults to {}, which Validate accepts; the failure
			-- is in `reset` being a non-function despite pool=true.
		})
		-- Cairn-Gui-2.0 MINOR 19 made SetText auto-invalidate the
		-- parent layout, so the row re-anchors itself after this call;
		-- we can use the longer descriptive label without the row
		-- shifting unevenly.
		registerBad.Cairn:SetText("Registered (violates 'pool=true with non-function reset')")
		registerBad.Cairn:SetEnabled(false)
	end)
end

Demo:RegisterTab("contracts", {
	label = "Contracts",
	order = 130,
	build = build,
})
