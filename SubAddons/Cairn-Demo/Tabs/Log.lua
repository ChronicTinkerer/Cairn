--[[
Cairn-Demo / Tabs / Log

Live demo of Cairn-Log-1.0 + Cairn-LogWindow-1.0. Logs entries at every
level from a per-tab source, lets the user fiddle with global level / chat-
echo level, and toggles the LogWindow viewer.

Cairn-Demo/Tabs/Log (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui = Demo.lib
local Log = LibStub("Cairn-Log-1.0")
local LogWindow = LibStub("Cairn-LogWindow-1.0", true)

local logger = Log("CairnDemo.LogTab")

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Log-1.0  +  Cairn-LogWindow-1.0",
		demo.Snippets.log)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Leveled per-source logger backed by a ring buffer, with a movable LogWindow viewer. Use the buttons below to log entries at each level, then toggle the LogWindow to see them.")

	-- Level buttons row.
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Trace", variant = "default" })
		.Cairn:On("Click", function() logger:Trace("trace at %s", date("%H:%M:%S")) end)
	Gui:Acquire("Button", row, { text = "Debug", variant = "default" })
		.Cairn:On("Click", function() logger:Debug("debug at %s", date("%H:%M:%S")) end)
	Gui:Acquire("Button", row, { text = "Info", variant = "primary" })
		.Cairn:On("Click", function() logger:Info("info at %s", date("%H:%M:%S")) end)
	Gui:Acquire("Button", row, { text = "Warn", variant = "default" })
		.Cairn:On("Click", function() logger:Warn("warn at %s", date("%H:%M:%S")) end)
	Gui:Acquire("Button", row, { text = "Error", variant = "danger" })
		.Cairn:On("Click", function() logger:Error("error at %s", date("%H:%M:%S")) end)

	-- Settings row.
	local row2 = Gui:Acquire("Container", live, {})
	row2.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row2:SetHeight(28)

	Gui:Acquire("Button", row2, { text = "GlobalLevel = TRACE", variant = "default" })
		.Cairn:On("Click", function() Log:SetGlobalLevel("TRACE") end)
	Gui:Acquire("Button", row2, { text = "GlobalLevel = INFO", variant = "default" })
		.Cairn:On("Click", function() Log:SetGlobalLevel("INFO") end)
	Gui:Acquire("Button", row2, { text = "ChatEcho = WARN", variant = "default" })
		.Cairn:On("Click", function() Log:SetChatEchoLevel("WARN") end)
	Gui:Acquire("Button", row2, { text = "ChatEcho = INFO", variant = "default" })
		.Cairn:On("Click", function() Log:SetChatEchoLevel("INFO") end)

	-- Stats label.
	local stats = Gui:Acquire("Label", live, {
		text = "buffer: 0 entries", variant = "small", align = "left",
	})
	local function refresh()
		local entries = Log:GetEntries() or {}
		stats.Cairn:SetText(("buffer: %d entries  |  globalLevel=%s  chatEcho=%s")
			:format(#entries,
				Log.LEVEL_NAMES[Log.globalLevel] or "?",
				Log.LEVEL_NAMES[Log.chatEchoLevel] or "?"))
	end

	-- Re-poll the buffer every half second so the count tracks live.
	local Timer = LibStub("Cairn-Timer-1.0", true)
	if Timer then
		Timer:NewTicker(0.5, refresh, "CairnDemo.LogTab")
	end
	refresh()

	-- LogWindow row.
	local row3 = Gui:Acquire("Container", live, {})
	row3.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row3:SetHeight(28)

	if LogWindow then
		Gui:Acquire("Button", row3, { text = "Toggle LogWindow", variant = "primary" })
			.Cairn:On("Click", function() LogWindow:Toggle() end)
		Gui:Acquire("Button", row3, { text = "Filter to CairnDemo.LogTab", variant = "default" })
			.Cairn:On("Click", function() LogWindow:SetSourceFilter("CairnDemo.LogTab") end)
		Gui:Acquire("Button", row3, { text = "Filter all", variant = "default" })
			.Cairn:On("Click", function() LogWindow:SetSourceFilter(nil) end)
		Gui:Acquire("Button", row3, { text = "MinLevel TRACE", variant = "default" })
			.Cairn:On("Click", function() LogWindow:SetMinLevel("TRACE") end)
	else
		Gui:Acquire("Label", row3, {
			text    = "[Cairn-LogWindow-1.0 not loaded]",
			variant = "muted", align = "left",
		})
	end

	-- Clear-buffer.
	local row4 = Gui:Acquire("Container", live, {})
	row4.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row4:SetHeight(28)
	Gui:Acquire("Button", row4, { text = "Clear buffer", variant = "danger" })
		.Cairn:On("Click", function() Log:Clear(); refresh() end)
end

Demo:RegisterTab("log", {
	label = "Log",
	order = 30,
	build = build,
})
