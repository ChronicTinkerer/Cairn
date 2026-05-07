--[[
Cairn-Demo / Tabs / EditMode

Live demo of Cairn-EditMode-1.0. Optional dep on LibEditMode; gracefully
degrades to a "not loaded" notice if absent.

Cairn-Demo/Tabs/EditMode (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local EM  = LibStub("Cairn-EditMode-1.0")

-- A real, named Frame so EM:Register has something legitimate to register.
local demoFrame = nil
local function ensureFrame()
	if demoFrame then return demoFrame end
	demoFrame = CreateFrame("Frame", "CairnDemoEditModeFrame", UIParent)
	demoFrame:SetSize(120, 60)
	demoFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	-- Visible bg so the user sees what they're moving.
	local tex = demoFrame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetColorTexture(0.0, 0.5, 0.7, 0.6)
	local fs = demoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")
	fs:SetText("Cairn-Demo EM target")
	demoFrame:Hide()
	return demoFrame
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-EditMode-1.0",
		demo.Snippets.editmode)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Optional wrapper around LibEditMode. Soft dependency: if LibEditMode is absent, calls return false and nothing crashes.")

	local available = EM:IsAvailable()
	Gui:Acquire("Label", live, {
		text    = available
			and "[OK] LibEditMode is loaded; Register will succeed."
			or  "[--] LibEditMode is NOT loaded; Register will return false (this is the documented degraded path).",
		variant = available and "success" or "muted",
		align   = "left", wrap = true,
	})

	-- Action row.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Show demo frame", variant = "primary" })
		.Cairn:On("Click", function() ensureFrame():Show() end)

	Gui:Acquire("Button", row, { text = "Hide demo frame", variant = "default" })
		.Cairn:On("Click", function()
			if demoFrame then demoFrame:Hide() end
		end)

	Gui:Acquire("Button", row, { text = "EM:Register(frame)", variant = "default" })
		.Cairn:On("Click", function()
			local ok = EM:Register(ensureFrame(),
				{ point = "CENTER", x = 0, y = 0 },
				function() print("|cFF7FBFFF[CairnDemo]|r EditMode commit") end,
				"Cairn Demo EM Frame")
			print(("|cFF7FBFFF[CairnDemo]|r EM:Register -> %s"):format(tostring(ok)))
		end)

	Gui:Acquire("Button", row, { text = "EM:Open()", variant = "default" })
		.Cairn:On("Click", function() EM:Open() end)
end

Demo:RegisterTab("editmode", {
	label = "EditMode",
	order = 80,
	build = build,
})
