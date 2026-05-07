--[[
Cairn-Demo / Tabs / Welcome

The first tab. Acts as a directory: states what the addon is, lists the
loaded library bundles + version, and one-lines what each subsequent tab
demonstrates.

Cairn-Demo/Tabs/Welcome (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui   = Demo.lib
local Cairn = Demo.cairn

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Welcome to the Cairn Library Demo",
		demo.Snippets.welcome)
	if not live then return end

	live = demo:MakeScrollable(live, 1200)
	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "An author-facing showcase of every NON-GUI Cairn library.",
		variant = "body",
		wrap    = true,
		align   = "left",
	})

	Gui:Acquire("Label", live, {
		text    = "Each tab on the left renders a single library live, with the exact code on the right. Companion to Cairn-Gui-Demo-2.0 which covers the GUI side.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ----- Loaded libs ---------------------------------------------------

	Gui:Acquire("Label", live, {
		text = "Loaded libraries", variant = "heading", align = "left",
	})

	local function row(name, ok, extra)
		Gui:Acquire("Label", live, {
			text    = (ok and "[OK] " or "[--] ") .. name .. (extra or ""),
			variant = ok and "success" or "muted",
			align   = "left",
			wrap    = true,
		})
	end

	local function probe(libname)
		local lib = LibStub(libname, true)
		if not lib then return false, "" end
		-- Most Cairn libs expose the MINOR via LibStub:GetLibrary's second
		-- return when called without :NewLibrary. Try a few common shapes.
		local _, minor = LibStub:GetLibrary(libname, true)
		return true, minor and (" (MINOR=" .. tostring(minor) .. ")") or ""
	end

	for _, libname in ipairs({
		"Cairn-Callback-1.0",
		"Cairn-Events-1.0",
		"Cairn-Log-1.0",
		"Cairn-LogWindow-1.0",
		"Cairn-DB-1.0",
		"Cairn-Settings-1.0",
		"Cairn-SettingsPanel-1.0",
		"Cairn-SettingsPanel-2.0",
		"Cairn-Addon-1.0",
		"Cairn-Slash-1.0",
		"Cairn-EditMode-1.0",
		"Cairn-Locale-1.0",
		"Cairn-Hooks-1.0",
		"Cairn-Sequencer-1.0",
		"Cairn-Timer-1.0",
		"Cairn-FSM-1.0",
		"Cairn-Comm-1.0",
	}) do
		local ok, extra = probe(libname)
		row(libname, ok, extra)
	end

	-- LibEditMode is the one optional outside-Cairn dep.
	row("LibEditMode (optional, third-party)",
		LibStub("LibEditMode", true) ~= nil,
		"")

	-- ----- Tab guide -----------------------------------------------------

	Gui:Acquire("Label", live, {
		text = "Tab guide", variant = "heading", align = "left",
	})

	local guide = {
		callback  = "Registry-style :Subscribe/:Fire dispatcher with on-used hooks.",
		events    = "Game-event subscription with owner-keyed mass unsubscribe.",
		log       = "Leveled per-source logger + LogWindow viewer.",
		db        = "SavedVariables wrapper with profile management.",
		settings  = "Declarative schema bridged to Blizzard Settings + standalone.",
		addon     = "ADDON_LOADED / PLAYER_LOGIN / etc lifecycle helpers.",
		slash     = "Slash command router with subcommands and auto-help.",
		editmode  = "Optional LibEditMode wrapper for movable frames.",
		locale    = "Per-addon localization with fallback chain.",
		hooks     = "Multi-callback hooksecurefunc dispatcher.",
		sequencer = "Composable step-runner with reset/abort conditions.",
		timer     = "Owner-grouped timers + named-timer debounce.",
		fsm       = "Flat finite state machine with async transitions.",
		comm      = "Addon-to-addon CHAT_MSG_ADDON messaging.",
		smoketest = "PASS/FAIL assertions covering every public API.",
	}

	for _, def in ipairs(demo._tabOrder) do
		if def.id ~= "welcome" then
			local hint = guide[def.id] or ""
			Gui:Acquire("Label", live, {
				text    = ("- %s -- %s"):format(def.label, hint),
				variant = "body",
				align   = "left",
				wrap    = true,
			})
		end
	end

	-- No explicit RelayoutNow needed: Cairn-Gui-2.0 Mixins/Base:_addChild
	-- already calls _invalidateLayout on the parent, so Stack picks up
	-- every Acquire above on the next layout pass before the user sees it.
end

Demo:RegisterTab("welcome", {
	label = "Welcome",
	order = 0,
	build = build,
})
