--[[
Cairn-Demo / Tabs / Locale

Live demo of Cairn-Locale-1.0. Registers a tiny three-locale namespace
and lets the user flip the override at runtime to see L["..."] re-resolve.

Cairn-Demo/Tabs/Locale (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui    = Demo.lib
local Locale = LibStub("Cairn-Locale-1.0")

-- Register at file scope; Get returns it on subsequent loads.
local L = Locale.Get("CairnDemo") or Locale.New("CairnDemo", {
	enUS = {
		hello   = "Hello",
		welcome = "Welcome back, %s!",
		btnGo   = "Go",
		btnStop = "Stop",
	},
	deDE = {
		hello   = "Hallo",
		welcome = "Willkommen zurueck, %s!",
		btnGo   = "Los",
		btnStop = "Halt",
	},
	frFR = {
		hello   = "Bonjour",
		-- 'welcome' missing on purpose -> falls back to enUS
		btnGo   = "Allez",
		btnStop = "Stop",
	},
}, { default = "enUS" })

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Locale-1.0",
		demo.Snippets.locale)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Per-addon localization with active -> default -> key fallback. The buttons below override the active locale at runtime; all the labels re-resolve.")

	local statusLbl = Gui:Acquire("Label", live, {
		text    = "...", variant = "small", align = "left",
	})

	-- Three sample reads.
	local greetingLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "body", align = "left",
	})
	local welcomeLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "body", align = "left",
	})
	local missingLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "muted", align = "left", wrap = true,
	})

	local function refresh()
		statusLbl.Cairn:SetText(("active=%s   default=%s   override=%s"):format(
			tostring(L:GetLocale()), tostring(L:GetDefault()),
			tostring(Locale.GetOverride() or "(none)")))
		greetingLbl.Cairn:SetText("L.hello -> " .. tostring(L.hello))
		welcomeLbl.Cairn:SetText("L('welcome', 'Steven') -> " .. tostring(L("welcome", "Steven")))
		local missing = L:GetMissing() or {}
		local list = {}
		for k in pairs(missing) do list[#list + 1] = k end
		table.sort(list)
		missingLbl.Cairn:SetText("L:GetMissing() -> { " .. table.concat(list, ", ") .. " }")
	end
	refresh()

	-- Override row.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Override -> enUS", variant = "default" })
		.Cairn:On("Click", function() Locale.SetOverride("enUS"); refresh() end)
	Gui:Acquire("Button", row, { text = "Override -> deDE", variant = "default" })
		.Cairn:On("Click", function() Locale.SetOverride("deDE"); refresh() end)
	Gui:Acquire("Button", row, { text = "Override -> frFR", variant = "default" })
		.Cairn:On("Click", function() Locale.SetOverride("frFR"); refresh() end)
	Gui:Acquire("Button", row, { text = "Clear override", variant = "danger" })
		.Cairn:On("Click", function() Locale.SetOverride(nil); refresh() end)

	-- Has() probe row.
	Gui:Acquire("Label", live, {
		text = "L:Has", variant = "heading", align = "left",
	})
	for _, key in ipairs({ "hello", "welcome", "btnGo", "doesNotExist" }) do
		Gui:Acquire("Label", live, {
			text    = ("L:Has(%q) -> %s"):format(key, tostring(L:Has(key))),
			variant = "small", align = "left",
		})
	end
end

Demo:RegisterTab("locale", {
	label = "Locale",
	order = 90,
	build = build,
})
