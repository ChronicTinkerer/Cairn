--[[
Cairn-Demo / Tabs / Addon

Live demo of Cairn-Addon-1.0. Reads the timestamps off the live Demo.addon
object (which IS a Cairn.Addon instance, set up in Core.lua). Shows that
OnInit / OnLogin / OnEnter all fired and when.

Cairn-Demo/Tabs/Addon (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib

local function fmtTs(ts)
	if not ts then return "(not yet)" end
	return ("%s  (%ds ago)"):format(date("%H:%M:%S", ts), time() - ts)
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Addon-1.0",
		demo.Snippets.addon)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Lifecycle helper. Subscribes to ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD / PLAYER_LOGOUT for you. Demo.addon is a real Cairn.Addon for this addon.")

	local addon = demo.addon

	-- One row per lifecycle event. Refreshed on a button click below.
	local rows = {}
	for _, hook in ipairs({
		{ "OnInit",   "initFiredAt"  },
		{ "OnLogin",  "loginFiredAt" },
		{ "OnEnter",  "enterFiredAt" },
		{ "OnLogout", "logoutFiredAt" },
	}) do
		local hookName, fieldName = hook[1], hook[2]
		local lbl = Gui:Acquire("Label", live, {
			text    = ("%-9s %s"):format(hookName, fmtTs(addon[fieldName])),
			variant = "body", align = "left",
		})
		rows[#rows + 1] = { lbl = lbl, hookName = hookName, fieldName = fieldName }
	end

	-- Refresh button.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Refresh", variant = "primary" })
		.Cairn:On("Click", function()
			for _, r in ipairs(rows) do
				r.lbl.Cairn:SetText(("%-9s %s"):format(r.hookName, fmtTs(addon[r.fieldName])))
			end
		end)

	Gui:Acquire("Button", row, { text = "Get('CairnDemo')", variant = "default" })
		.Cairn:On("Click", function()
			local Cairn = demo.cairn
			local got = Cairn.Addon.Get("CairnDemo")
			print(("|cFF7FBFFF[CairnDemo]|r Cairn.Addon.Get('CairnDemo') == Demo.addon? %s")
				:format(tostring(got == addon)))
		end)

	Gui:Acquire("Button", row, { text = "addon:Log():Info(...)", variant = "default" })
		.Cairn:On("Click", function()
			local lg = addon:Log()
			if lg then lg:Info("hello from addon:Log() at %s", date("%H:%M:%S")) end
		end)

	-- First-run flag set in Core.lua's OnInit. Helps the user verify
	-- end-to-end that the OnInit hook actually ran.
	if demo._firstRun then
		Gui:Acquire("Label", live, {
			text    = "[first run for this character; db.global.installed was just set]",
			variant = "success", align = "left", wrap = true,
		})
	else
		Gui:Acquire("Label", live, {
			text    = ("[returning user; installed at %s]"):format(
				date("%Y-%m-%d %H:%M:%S", demo.db.global.installed or 0)),
			variant = "muted", align = "left", wrap = true,
		})
	end
end

Demo:RegisterTab("addon", {
	label = "Addon",
	order = 60,
	build = build,
})
