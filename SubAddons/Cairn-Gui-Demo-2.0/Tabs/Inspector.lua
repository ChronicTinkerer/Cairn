--[[
Cairn-Gui-Demo-2.0 / Tabs / Inspector

Live readout of the introspection surface: Stats:Snapshot(),
EventLog:Tail(), Inspector:Walk over the demo's own widget tree. A
"Refresh" button repaints the panel; an OnUpdate timer auto-refreshes
once a second so the user can watch counters move while they interact
with other tabs.

Cairn-Gui-Demo-2.0/Tabs/Inspector (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function fmtNumber(n)
	if type(n) ~= "number" then return tostring(n) end
	if n >= 10000 then return string.format("%.1fk", n / 1000) end
	return tostring(n)
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Inspector / Stats / EventLog",
		demo.Snippets.inspector)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	-- ---- Stats panel --------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Cairn.Stats:Snapshot()",
		variant = "heading",
		align   = "left",
	})

	local statsLabel = Gui:Acquire("Label", live, {
		text    = "(refreshing...)",
		variant = "small",
		wrap    = true,
		align   = "left",
	})

	-- ---- Tree walk panel ----------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Cairn.Inspector:Walk(this tab) -- depth-first widget tree",
		variant = "heading",
		align   = "left",
	})

	local treeBox = Gui:Acquire("ScrollFrame", live, {
		bg            = "color.bg.surface",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = 600,
	})
	treeBox:SetHeight(140)

	local treeContent = treeBox.Cairn:GetContent()
	treeContent.Cairn:SetLayoutManual(true)

	local treeLabel = Gui:Acquire("Label", treeContent, {
		text    = "(populating...)",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
	treeLabel.Cairn:SetLayoutManual(true)
	treeLabel:SetPoint("TOPLEFT",  treeContent, "TOPLEFT",  6, -6)
	treeLabel:SetPoint("TOPRIGHT", treeContent, "TOPRIGHT", -6, -6)

	-- ---- EventLog panel -----------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Cairn.EventLog:Tail(20)",
		variant = "heading",
		align   = "left",
	})

	local eventLogLabel = Gui:Acquire("Label", live, {
		text    = "(EventLog disabled; click Enable below)",
		variant = "small",
		wrap    = true,
		align   = "left",
	})

	local controlRow = Gui:Acquire("Container", live)
	controlRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	controlRow:SetHeight(28)

	local enableLog = Gui:Acquire("Button", controlRow, {
		text = "EventLog: Enable", variant = "default", width = 160,
	})
	local disableLog = Gui:Acquire("Button", controlRow, {
		text = "EventLog: Disable", variant = "ghost", width = 160,
	})
	local clearLog = Gui:Acquire("Button", controlRow, {
		text = "Clear", variant = "ghost", width = 80,
	})
	local refresh = Gui:Acquire("Button", controlRow, {
		text = "Refresh now", variant = "primary", width = 120,
	})

	enableLog.Cairn:On("Click", function()
		if Gui.EventLog and Gui.EventLog.Enable then Gui.EventLog:Enable() end
	end)
	disableLog.Cairn:On("Click", function()
		if Gui.EventLog and Gui.EventLog.Disable then Gui.EventLog:Disable() end
	end)
	clearLog.Cairn:On("Click", function()
		if Gui.EventLog and Gui.EventLog.Clear then Gui.EventLog:Clear() end
	end)

	-- ---- Refresh function ---------------------------------------------

	local function refreshAll()
		-- Stats.
		if Gui.Stats and Gui.Stats.Snapshot then
			local s = Gui.Stats:Snapshot()
			local poolText = ""
			if s.pool then
				for k, v in pairs(s.pool) do
					if k ~= "_total" then
						poolText = poolText .. ("  %s=%d"):format(k, v)
					end
				end
			end
			statsLabel.Cairn:SetText(string.format(
				"animations: added=%s completed=%s active=%s    layout: recomputes=%s\n" ..
				"primitives: rect=%s border=%s icon=%s    events: dispatches=%s\n" ..
				"pool[_total]=%s%s\n" ..
				"eventLog: enabled=%s count=%s/%s",
				fmtNumber(s.animations and s.animations.added     or 0),
				fmtNumber(s.animations and s.animations.completed or 0),
				fmtNumber(s.animations and s.animations.active    or 0),
				fmtNumber(s.layout     and s.layout.recomputes    or 0),
				fmtNumber(s.primitives and s.primitives.rect   and s.primitives.rect.draws   or 0),
				fmtNumber(s.primitives and s.primitives.border and s.primitives.border.draws or 0),
				fmtNumber(s.primitives and s.primitives.icon   and s.primitives.icon.draws   or 0),
				fmtNumber(s.events     and s.events.dispatches   or 0),
				fmtNumber(s.pool and s.pool._total or 0),
				poolText,
				tostring(s.eventLog and s.eventLog.enabled),
				fmtNumber(s.eventLog and s.eventLog.count    or 0),
				fmtNumber(s.eventLog and s.eventLog.capacity or 0)))
		else
			statsLabel.Cairn:SetText("Cairn.Stats not loaded")
		end

		-- Tree walk over THIS tab pane.
		if Gui.Inspector and Gui.Inspector.Walk and pane and pane.Cairn then
			local lines = {}
			Gui.Inspector:Walk(pane.Cairn, function(c, depth)
				if depth > 6 then return end  -- Cap depth so the panel stays readable.
				lines[#lines + 1] = string.rep("  ", depth)
					.. (c._type or "?")
					.. (c._secure and "  [secure]" or "")
					.. (c._layoutManual and "  [manual]" or "")
				if #lines > 200 then return false end
			end)
			treeLabel.Cairn:SetText(table.concat(lines, "\n"))
			-- Recompute scroll content height after the text changed.
			local _, ih = treeLabel.Cairn:GetIntrinsicSize()
			if ih and ih > 0 then
				treeBox.Cairn:SetContentHeight(ih + 12)
				treeLabel:SetHeight(ih + 4)
			end
		end

		-- EventLog tail.
		if Gui.EventLog and Gui.EventLog.Tail then
			local tail = Gui.EventLog:Tail(20)
			if not tail or #tail == 0 then
				eventLogLabel.Cairn:SetText("(empty)")
			else
				local lines = {}
				for i = math.max(1, #tail - 19), #tail do
					local e = tail[i]
					lines[#lines + 1] = string.format("[%6.2f] %s :: %s (%d args)",
						e.t or 0,
						tostring(e.widgetType or "?"),
						tostring(e.event or "?"),
						e.argCount or 0)
				end
				eventLogLabel.Cairn:SetText(table.concat(lines, "\n"))
			end
		end
	end

	refresh.Cairn:On("Click", refreshAll)

	-- Initial render.
	refreshAll()

	-- Auto-refresh once a second using a timer parented to the live
	-- container's frame, so it auto-pauses on Hide (Blizzard cascade).
	live._inspectorTicker = (live._inspectorTicker == nil) and 0 or live._inspectorTicker
	live:HookScript("OnUpdate", function(self_, dt)
		live._inspectorTicker = live._inspectorTicker + dt
		if live._inspectorTicker >= 1.0 then
			live._inspectorTicker = 0
			refreshAll()
		end
	end)
end

Demo:RegisterTab("inspector", {
	label = "Inspector",
	order = 110,
	build = build,
})
