--[[
Cairn-Standalone-1.0

This file is loaded ONLY by the standalone Cairn addon (it's listed in
Cairn.toc but should NOT be embedded in other addons). It wires up
SavedVariables persistence for Cairn.Log and provides the user-facing
slash commands routed through Cairn:RegisterSlashSub().

Embedded users get the libraries without this glue. They can wire their
own SavedVariables to Cairn.Log:DumpToSV / LoadFromSV if they want
persistence.
]]

local Log       = LibStub("Cairn-Log-1.0", true)
local LogWindow = LibStub("Cairn-LogWindow-1.0", true)
local Dashboard = LibStub("Cairn-Dashboard-1.0", true)

if not Log then return end

-- ----- Slash subcommands -------------------------------------------------

Cairn:RegisterSlashSub("log", function(args)
	args = args or ""
	local sub, rest = args:match("^%s*(%S*)%s*(.*)$")
	sub = (sub or ""):lower()

	if sub == "" then
		if LogWindow then LogWindow:Toggle()
		else print("|cFF7FBFFF[Cairn]|r LogWindow module not loaded.") end
		return
	end

	if sub == "clear" then
		Log:Clear()
		if LogWindow and LogWindow.Refresh then LogWindow:Refresh() end
		print("|cFF7FBFFF[Cairn]|r log buffer cleared")
		return
	end

	if sub == "level" then
		local lvl = (rest or ""):match("^(%S+)") or ""
		if lvl == "" then
			print("|cFF7FBFFF[Cairn]|r usage: /cairn log level TRACE|DEBUG|INFO|WARN|ERROR")
			return
		end
		local ok, err = pcall(function()
			if LogWindow then LogWindow:SetMinLevel(lvl) end
			Log:SetGlobalLevel(lvl)
		end)
		if ok then print("|cFF7FBFFF[Cairn]|r global level + window min-level set to " .. lvl:upper())
		else print("|cFF7FBFFF[Cairn]|r " .. tostring(err)) end
		return
	end

	if sub == "source" then
		local src = (rest or ""):match("^(%S+)") or "all"
		if LogWindow then LogWindow:SetSourceFilter(src) end
		print("|cFF7FBFFF[Cairn]|r source filter: " .. src)
		return
	end

	if sub == "search" then
		local q = rest or ""
		if LogWindow then LogWindow:SetSearch(q ~= "" and q or nil) end
		print("|cFF7FBFFF[Cairn]|r search: " .. (q ~= "" and q or "(cleared)"))
		return
	end

	if sub == "echo" then
		local lvl = (rest or ""):match("^(%S+)") or ""
		if lvl == "" then
			print("|cFF7FBFFF[Cairn]|r usage: /cairn log echo TRACE|DEBUG|INFO|WARN|ERROR")
			return
		end
		local ok, err = pcall(function() Log:SetChatEchoLevel(lvl) end)
		if ok then print("|cFF7FBFFF[Cairn]|r chat echo level set to " .. lvl:upper())
		else print("|cFF7FBFFF[Cairn]|r " .. tostring(err)) end
		return
	end

	if sub == "stats" then
		print(string.format(
			"|cFF7FBFFF[Cairn]|r log: %d entries, global=%s, echo=%s, persist=%d",
			Log:Count(),
			Log.LEVEL_NAMES[Log:GetGlobalLevel()] or "?",
			Log.LEVEL_NAMES[Log:GetChatEchoLevel()] or "?",
			Log:GetPersistence()
		))
		return
	end

	print("|cFF7FBFFF[Cairn]|r unknown log subcommand: " .. sub ..
		"  (try: clear, level, source, search, echo, stats)")
end, "open log window or manage logging")

-- The developer dashboard moved out of Cairn into the Forge dev-tools
-- suite. /cairn dash now points the user at /forge logs.
local function dashRedirect()
	print("|cFF7FBFFF[Cairn]|r The developer dashboard moved to Forge_Logs. Use |cffd87f3a/forge logs|r.")
end
Cairn:RegisterSlashSub("dash",      dashRedirect, "(moved) /forge logs")
Cairn:RegisterSlashSub("dashboard", dashRedirect, "(moved) /forge logs")
Cairn:RegisterSlashSub("dev",       dashRedirect, "(moved) /forge logs")

-- ----- SavedVariables wiring (PLAYER_LOGOUT save, ADDON_LOADED restore) --

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == "Cairn" then
		_G.CairnLogSV = _G.CairnLogSV or {}
		Log:LoadFromSV(_G.CairnLogSV)
		Log("Cairn"):Info("Cairn v%s ready (loaded %d archived log entries).",
			(Cairn._VERSION or "?"), #(_G.CairnLogSV.entries or {}))
	elseif event == "PLAYER_LOGOUT" then
		_G.CairnLogSV = Log:DumpToSV() or {}
	end
end)
