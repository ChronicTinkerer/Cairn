--[[
Cairn-Demo / Tabs / DB

Live demo of Cairn-DB-1.0. Reads/writes the shared Demo.db (created
in Core.lua, force-init'd in OnInit). Counter increments persist across
reloads. Profile switcher demonstrates :GetProfiles / :SetProfile /
:OnProfileChanged.

Cairn-Demo/Tabs/DB (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-DB-1.0",
		demo.Snippets.db)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"SavedVariables wrapper with profile management. The counter below persists across /reload via Demo.db.profile.counter.")

	local db = demo.db

	-- Counter row.
	local counterLbl = Gui:Acquire("Label", live, {
		text    = ("counter = %d"):format(db.profile.counter or 0),
		variant = "body", align = "left",
	})

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "+1", variant = "primary" })
		.Cairn:On("Click", function()
			db.profile.counter = (db.profile.counter or 0) + 1
			counterLbl.Cairn:SetText(("counter = %d"):format(db.profile.counter))
		end)

	Gui:Acquire("Button", row, { text = "-1", variant = "default" })
		.Cairn:On("Click", function()
			db.profile.counter = (db.profile.counter or 0) - 1
			counterLbl.Cairn:SetText(("counter = %d"):format(db.profile.counter))
		end)

	Gui:Acquire("Button", row, { text = "Reset profile", variant = "danger" })
		.Cairn:On("Click", function()
			db:ResetProfile()
			-- Defaults aren't retroactive on existing profiles per the
			-- cairn_db_no_retro_defaults memory; ResetProfile DOES
			-- reapply defaults though.
			counterLbl.Cairn:SetText(("counter = %d"):format(db.profile.counter or 0))
		end)

	-- Profile info + switcher.
	Gui:Acquire("Label", live, {
		text = "Profiles", variant = "heading", align = "left",
	})
	local profileLbl = Gui:Acquire("Label", live, {
		text    = ("current = %q"):format(tostring(db:GetCurrentProfile() or "?")),
		variant = "small", align = "left",
	})
	local listLbl = Gui:Acquire("Label", live, {
		text    = "all = " .. table.concat(db:GetProfiles() or {}, ", "),
		variant = "small", align = "left", wrap = true,
	})

	local prow = Gui:Acquire("Container", live, {})
	prow.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	prow:SetHeight(28)

	local function refresh()
		profileLbl.Cairn:SetText(("current = %q"):format(tostring(db:GetCurrentProfile() or "?")))
		listLbl.Cairn:SetText("all = " .. table.concat(db:GetProfiles() or {}, ", "))
		counterLbl.Cairn:SetText(("counter = %d"):format(db.profile.counter or 0))
	end

	Gui:Acquire("Button", prow, { text = "SetProfile 'Default'", variant = "default" })
		.Cairn:On("Click", function() db:SetProfile("Default"); refresh() end)
	Gui:Acquire("Button", prow, { text = "SetProfile 'PvP'", variant = "default" })
		.Cairn:On("Click", function() db:SetProfile("PvP"); refresh() end)
	Gui:Acquire("Button", prow, { text = "Copy Default -> PvP", variant = "default" })
		.Cairn:On("Click", function() db:CopyProfile("Default", "PvP"); refresh() end)

	-- Subscribe to profile changes (returns unsubscribe).
	db:OnProfileChanged(function(newName, oldName)
		if logger then end
		profileLbl.Cairn:SetText(("current = %q  (was %q)"):format(tostring(newName), tostring(oldName)))
	end, "CairnDemo.DBTab")

	-- Global state inspector. Shows db.global is a separate scope.
	Gui:Acquire("Label", live, {
		text = "Global scope", variant = "heading", align = "left",
	})
	local installedAt = db.global.installed and date("%Y-%m-%d %H:%M:%S", db.global.installed) or "(not set)"
	Gui:Acquire("Label", live, {
		text    = "db.global.installed = " .. tostring(installedAt),
		variant = "small", align = "left",
	})
end

Demo:RegisterTab("db", {
	label = "DB",
	order = 40,
	build = build,
})
