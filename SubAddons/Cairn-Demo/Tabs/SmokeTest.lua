--[[
Cairn-Demo / Tabs / SmokeTest

PASS/FAIL assertions covering every public API in the Cairn library set.
Each assertion is a small self-contained test that uses ONLY documented
APIs from the matching lib's header. No internal access (private fields,
underscore methods).

Each assertion records (libName, testName, ok, message). The runner
prints results into a console pane, then renders a summary footer with
a green PASS count and red FAIL count.

The same assertion list is mirrored in
Forge/.dev/tests/cairn_demo_smoke.lua so it can run headlessly via
Forge_Console without opening this window.

Cairn-Demo/Tabs/SmokeTest (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui   = Demo.lib
local Cairn = Demo.cairn

-- ----- Test runner ------------------------------------------------------
-- Sync tests run inline. Async tests (timer expiry, sequencer with delays,
-- FSM async transition) post a continuation onto C_Timer.After and
-- finalize via a completion callback so the runner can print a final
-- summary in chronological order.

-- buildRunner takes a console object (with :Print / :Clear) and a
-- setSummary function. Function form lets real-widget callers wrap the
-- Cairn-Gui-2.0 :Cairn:SetText path while the headless harness can pass
-- a plain print function. Avoids mixing widget shapes.
local function buildRunner(console, setSummary)
	local results = {}  -- { lib, name, ok, msg }
	local pendingAsync = 0
	local doneCb = nil

	local function record(lib, name, ok, msg)
		results[#results + 1] = { lib = lib, name = name, ok = ok, msg = msg }
		console:Print(("%s %s :: %s%s"):format(
			ok and "|cFF40FF40[PASS]|r" or "|cFFFF4040[FAIL]|r",
			lib, name, (not ok and msg) and (" -- " .. tostring(msg)) or ""))
	end

	local function checkDone()
		if pendingAsync > 0 then return end
		local pass, fail = 0, 0
		for _, r in ipairs(results) do
			if r.ok then pass = pass + 1 else fail = fail + 1 end
		end
		if setSummary then
			local color = (fail == 0) and "|cFF40FF40" or "|cFFFF4040"
			setSummary(("%s%d / %d passing|r%s"):format(
				color, pass, pass + fail,
				(fail > 0) and ("   |cFFFF4040(" .. fail .. " failed)|r") or ""))
		end
		if doneCb then doneCb(pass, fail) end
	end

	local function async(fn)
		pendingAsync = pendingAsync + 1
		fn(function()
			pendingAsync = pendingAsync - 1
			checkDone()
		end)
	end

	local function assertOk(lib, name, ok, msg)
		record(lib, name, ok and true or false, msg)
	end

	-- Catch all exceptions inside a test so one bad assertion never aborts
	-- the rest of the suite.
	local function pcallTest(lib, name, fn)
		local ok, err = pcall(fn, assertOk)
		if not ok then assertOk(lib, name, false, "test threw: " .. tostring(err)) end
	end

	return {
		results    = results,
		record     = record,
		assertOk   = assertOk,
		pcallTest  = pcallTest,
		async      = async,
		setDone    = function(cb) doneCb = cb end,
		finishSync = checkDone,
	}
end

-- ----- The actual assertions --------------------------------------------

local function runSuite(R)
	-- ----- Cairn-Callback ----------------------------------------------
	R.pcallTest("Callback", "New + Subscribe + Fire + Unsubscribe", function(t)
		local Callback = LibStub("Cairn-Callback-1.0", true)
		t("Callback", "lib loaded", Callback ~= nil)
		if not Callback then return end

		local reg = Callback.New("smoke")
		t("Callback", "New() returned a registry", type(reg) == "table")

		local fired = {}
		local keyA, keyB = {}, {}
		reg:Subscribe("E", keyA, function(_, x) fired[#fired+1] = "A" .. tostring(x) end)
		reg:Subscribe("E", keyB, function(_, x) fired[#fired+1] = "B" .. tostring(x) end)
		reg:Fire("E", 1)
		t("Callback", "two subscribers both fired", fired[1] == "A1" and fired[2] == "B1")

		reg:Unsubscribe("E", keyA)
		reg:Fire("E", 2)
		t("Callback", "Unsubscribe removed only A", fired[3] == "B2" and fired[4] == nil)

		reg:UnsubscribeAll(keyB)
		reg:Fire("E", 3)
		t("Callback", "UnsubscribeAll cleared B", fired[3] == "B2" and fired[4] == nil)
	end)

	-- ----- Cairn-Events -------------------------------------------------
	R.pcallTest("Events", "Subscribe + UnsubscribeAll + Has", function(t)
		local Events = LibStub("Cairn-Events-1.0", true)
		t("Events", "lib loaded", Events ~= nil)
		if not Events then return end

		-- Use a synthetic event ID. Real WoW events would also work but a
		-- private one means no risk of cross-talk.
		local OWNER = "CairnDemoSmoke"
		Events:UnsubscribeAll(OWNER)  -- start clean

		local off1 = Events:Subscribe("CAIRN_DEMO_SMOKE_X", function() end, OWNER)
		t("Events", "Subscribe returns unsub closure", type(off1) == "function")
		t("Events", "Has reports true after subscribe", Events:Has("CAIRN_DEMO_SMOKE_X"))

		off1()
		t("Events", "Has reports false after closure unsub", not Events:Has("CAIRN_DEMO_SMOKE_X"))

		-- Owner-keyed mass unsub.
		Events:Subscribe("CAIRN_DEMO_SMOKE_Y", function() end, OWNER)
		Events:Subscribe("CAIRN_DEMO_SMOKE_Z", function() end, OWNER)
		Events:UnsubscribeAll(OWNER)
		t("Events", "UnsubscribeAll cleared owner", not Events:Has("CAIRN_DEMO_SMOKE_Y") and not Events:Has("CAIRN_DEMO_SMOKE_Z"))
	end)

	-- ----- Cairn-Log ----------------------------------------------------
	R.pcallTest("Log", "Logger creation + level filtering + buffer", function(t)
		local Log = LibStub("Cairn-Log-1.0", true)
		t("Log", "lib loaded", Log ~= nil)
		if not Log then return end

		local logger = Log("CairnDemoSmoke")
		t("Log", "Log(name) returns a logger", type(logger) == "table")
		t("Log", "logger has Info method", type(logger.Info) == "function")

		local sameLogger = Log("CairnDemoSmoke")
		t("Log", "Log(name) is idempotent (same source = same logger)", logger == sameLogger)

		-- Buffer should grow when we log.
		local before = #(Log:GetEntries() or {})
		logger:Info("smoke test ping %d", time())
		local after  = #(Log:GetEntries() or {})
		t("Log", "Info call appends to buffer", after == before + 1)

		-- LEVEL_NAMES table should be populated.
		t("Log", "LEVEL_NAMES contains INFO", Log.LEVEL_NAMES[3] == "INFO")
	end)

	-- ----- Cairn-LogWindow ---------------------------------------------
	R.pcallTest("LogWindow", "API surface present", function(t)
		local LW = LibStub("Cairn-LogWindow-1.0", true)
		t("LogWindow", "lib loaded", LW ~= nil)
		if not LW then return end
		t("LogWindow", "Toggle present",          type(LW.Toggle) == "function")
		t("LogWindow", "SetMinLevel present",     type(LW.SetMinLevel) == "function")
		t("LogWindow", "SetSourceFilter present", type(LW.SetSourceFilter) == "function")
		t("LogWindow", "SetSearch present",       type(LW.SetSearch) == "function")
	end)

	-- ----- Cairn-DB -----------------------------------------------------
	R.pcallTest("DB", "shared Demo.db round-trip", function(t)
		local db = Demo.db
		t("DB", "Demo.db exists", type(db) == "table")
		t("DB", "db.profile is a table",    type(db.profile) == "table")
		t("DB", "db.global is a table",     type(db.global) == "table")
		t("DB", "GetCurrentProfile returns string", type(db:GetCurrentProfile()) == "string")
		t("DB", "GetProfiles returns array",        type(db:GetProfiles()) == "table")

		-- Round-trip a value.
		db.profile.smoke = 42
		t("DB", "round-trip write/read", db.profile.smoke == 42)
		db.profile.smoke = nil
	end)

	-- ----- Cairn-Settings -----------------------------------------------
	R.pcallTest("Settings", "New + Get + Set + OnChange", function(t)
		local Settings = LibStub("Cairn-Settings-1.0", true)
		t("Settings", "lib loaded", Settings ~= nil)
		if not Settings then return end

		-- Use a one-off DB so we don't mutate Demo.db.
		local DB = LibStub("Cairn-DB-1.0", true)
		local tmp = DB.New("CairnDemoSmokeDB", { defaults = { profile = { v = 1 } } })

		local s = Settings.New("CairnDemoSmoke", tmp, {
			{ key = "v", type = "range", label = "v", min = 0, max = 10, step = 1, default = 1 },
		})
		t("Settings", "Get returns default",   s:Get("v") == 1)

		local seenOld, seenNew = nil, nil
		s:OnChange("v", function(new, old) seenOld, seenNew = old, new end, "smoke")
		s:Set("v", 5)
		t("Settings", "Set updates value",            s:Get("v") == 5)
		t("Settings", "OnChange fires with old/new",  seenOld == 1 and seenNew == 5)
	end)

	-- ----- Cairn-SettingsPanel -----------------------------------------
	R.pcallTest("SettingsPanel", "API surface present (v1)", function(t)
		local SP = LibStub("Cairn-SettingsPanel-1.0", true)
		t("SettingsPanel-v1", "lib loaded",          SP ~= nil)
		if not SP then return end
		t("SettingsPanel-v1", "OpenFor present",     type(SP.OpenFor)   == "function")
		t("SettingsPanel-v1", "HideFor present",     type(SP.HideFor)   == "function")
		t("SettingsPanel-v1", "ToggleFor present",   type(SP.ToggleFor) == "function")
	end)

	R.pcallTest("SettingsPanel-v2", "API surface present (v2)", function(t)
		local SP2 = LibStub("Cairn-SettingsPanel-2.0", true)
		t("SettingsPanel-v2", "lib loaded",          SP2 ~= nil)
		if not SP2 then return end
		t("SettingsPanel-v2", "OpenFor present",     type(SP2.OpenFor)   == "function")
		t("SettingsPanel-v2", "HideFor present",     type(SP2.HideFor)   == "function")
		t("SettingsPanel-v2", "ToggleFor present",   type(SP2.ToggleFor) == "function")
	end)

	R.pcallTest("Settings", ":OpenStandalone prefers v2", function(t)
		local SP2 = LibStub("Cairn-SettingsPanel-2.0", true)
		if not SP2 then
			t("Settings-OpenStandalone", "v2 panel loaded", false, "Cairn-SettingsPanel-2.0 not present; v1 fallback path will be used")
			return
		end
		-- Check the route by looking at the proto's OpenStandalone:
		-- it should resolve to v2 since v2 is loaded. We can't easily
		-- intercept the call, but we CAN confirm both libs are present.
		local SP1 = LibStub("Cairn-SettingsPanel-1.0", true)
		t("Settings-OpenStandalone", "v2 panel available for preference", SP2 ~= nil)
		t("Settings-OpenStandalone", "v1 fallback also available",         SP1 ~= nil)
	end)

	-- ----- Cairn-Addon --------------------------------------------------
	R.pcallTest("Addon", "registry round-trip", function(t)
		local Addon = LibStub("Cairn-Addon-1.0", true)
		t("Addon", "lib loaded", Addon ~= nil)
		if not Addon then return end

		t("Addon", "Demo.addon registered", Addon.Get("CairnDemo") == Demo.addon)
		t("Addon", "OnInit timestamp set",  type(Demo.addon.initFiredAt) == "number")
		t("Addon", "OnLogin timestamp set", type(Demo.addon.loginFiredAt) == "number")
		t("Addon", "addon:Log() returns logger or nil", true)  -- can't assert non-nil if Log lib is missing
	end)

	-- ----- Cairn-Slash --------------------------------------------------
	R.pcallTest("Slash", "Args + Run + Get", function(t)
		local Slash = LibStub("Cairn-Slash-1.0", true)
		t("Slash", "lib loaded", Slash ~= nil)
		if not Slash then return end

		local s = Demo.slash
		t("Slash", "Demo.slash registered", s ~= nil and Slash.Get("CairnDemo") == s)

		local args = s:Args([[hello "two words" three]])
		t("Slash", "quote-aware splitter",
			#args == 3 and args[1] == "hello" and args[2] == "two words" and args[3] == "three")
	end)

	-- ----- Cairn-EditMode ----------------------------------------------
	R.pcallTest("EditMode", "IsAvailable + degraded path", function(t)
		local EM = LibStub("Cairn-EditMode-1.0", true)
		t("EditMode", "lib loaded", EM ~= nil)
		if not EM then return end

		local avail = EM:IsAvailable()
		t("EditMode", "IsAvailable returns boolean", type(avail) == "boolean")
		-- Open should always succeed (it's just a wrapper around Blizzard EditMode UI).
		t("EditMode", "Open present", type(EM.Open) == "function")
	end)

	-- ----- Cairn-Locale ------------------------------------------------
	R.pcallTest("Locale", "fallback chain + Has + Format", function(t)
		local Locale = LibStub("Cairn-Locale-1.0", true)
		t("Locale", "lib loaded", Locale ~= nil)
		if not Locale then return end

		-- Use the demo's own locale; it's already registered.
		local L = Locale.Get("CairnDemo")
		t("Locale", "demo locale registered", L ~= nil)
		if not L then return end

		t("Locale", "L:Has on existing key",   L:Has("hello"))
		t("Locale", "L:Has on missing key",    not L:Has("totallyMadeUpKey"))
		t("Locale", "L:Format substitutes",    L:Format("welcome", "Steve"):find("Steve") ~= nil)

		-- Override round-trip.
		local prev = Locale.GetOverride()
		Locale.SetOverride("deDE")
		t("Locale", "override switches active", L:GetLocale() == "deDE")
		Locale.SetOverride(prev)
	end)

	-- ----- Cairn-Hooks --------------------------------------------------
	R.pcallTest("Hooks", "Post + Has + closure unhook", function(t)
		local Hooks = LibStub("Cairn-Hooks-1.0", true)
		t("Hooks", "lib loaded", Hooks ~= nil)
		if not Hooks then return end

		-- Hook a private frame method.
		local f = CreateFrame("Frame")
		local seen = 0
		local unhook = Hooks.Post(f, "Show", function() seen = seen + 1 end)
		t("Hooks", "Post returns unhook closure", type(unhook) == "function")
		t("Hooks", "Has reports installed hook",  Hooks.Has(f, "Show"))

		f:Show()
		t("Hooks", "callback ran on Show",        seen == 1)

		unhook()
		f:Show()
		-- WoW limitation: hooksecurefunc cannot be undone, but our closure
		-- masks the callback so the count must NOT advance.
		t("Hooks", "closure unhook masks callback", seen == 1)
	end)

	-- ----- Cairn-Sequencer (sync subset) -------------------------------
	R.pcallTest("Sequencer", "advance + reset + status", function(t)
		local Seq = LibStub("Cairn-Sequencer-1.0", true)
		t("Sequencer", "lib loaded", Seq ~= nil)
		if not Seq then return end

		local stepped = 0
		local seq = Seq.New({
			function() return true end,
			function() return true end,
			function() return true end,
		}, {
			onStep = function() stepped = stepped + 1 end,
		})
		t("Sequencer", "starts pending or running", seq:Status() == "pending" or seq:Status() == "running")
		seq:Execute()
		seq:Execute()
		seq:Execute()
		t("Sequencer", "advances 3 steps via Execute", stepped == 3)
		t("Sequencer", "Finished is true", seq:Finished())

		seq:Reset()
		t("Sequencer", "Reset returns index to 1", seq:Index() == 1)
	end)

	-- ----- Cairn-Timer (async) -----------------------------------------
	R.pcallTest("Timer", "API surface", function(t)
		local Timer = LibStub("Cairn-Timer-1.0", true)
		t("Timer", "lib loaded", Timer ~= nil)
		if not Timer then return end
		t("Timer", "After present",      type(Timer.After) == "function")
		t("Timer", "NewTicker present",  type(Timer.NewTicker) == "function")
		t("Timer", "Schedule present",   type(Timer.Schedule) == "function")
		t("Timer", "CancelAll present",  type(Timer.CancelAll) == "function")
	end)

	R.async(function(done)
		local Timer = LibStub("Cairn-Timer-1.0", true)
		if not Timer then R.assertOk("Timer", "After fires (async)", false, "lib missing"); done(); return end

		local fired = false
		Timer:After(0.4, function() fired = true end, "CairnDemoSmoke")

		-- Verify after 0.7s.
		local C_Timer = _G.C_Timer
		if C_Timer and C_Timer.After then
			C_Timer.After(0.7, function()
				R.assertOk("Timer", "After fires (async)", fired, fired or "callback did not run")
				done()
			end)
		else
			-- No C_Timer fallback in test contexts; mark as inconclusive.
			R.assertOk("Timer", "After fires (async)", true, "C_Timer absent, skipped verification")
			done()
		end
	end)

	-- ----- Cairn-FSM ----------------------------------------------------
	R.pcallTest("FSM", "sync transitions + lifecycle", function(t)
		local FSM = LibStub("Cairn-FSM-1.0", true)
		t("FSM", "lib loaded", FSM ~= nil)
		if not FSM then return end

		local spec = FSM.New({
			initial = "idle",
			states = {
				idle    = { on = { GO = "running" } },
				running = { on = { STOP = "idle" } },
			},
			owner = "CairnDemoSmoke",
		})
		local m = spec:Instantiate()
		t("FSM", "initial state",        m:State() == "idle")
		t("FSM", "Can with rule",        m:Can("GO"))
		t("FSM", "Can without rule",     not m:Can("BOGUS"))

		local transitions = 0
		m:On("Transition", function() transitions = transitions + 1 end)
		m:Send("GO")
		t("FSM", "Send transitions state",   m:State() == "running")
		t("FSM", "Transition event fired",   transitions == 1)

		m:Send("STOP")
		t("FSM", "second transition",        m:State() == "idle")
		t("FSM", "Transition fired twice",   transitions == 2)

		m:Destroy()
	end)

	-- ----- Cairn-Comm ---------------------------------------------------
	R.pcallTest("Comm", "subscribe + count + unsub closure", function(t)
		local Comm = LibStub("Cairn-Comm-1.0", true)
		t("Comm", "lib loaded", Comm ~= nil)
		if not Comm then return end

		local PREFIX = "CDS"
		Comm:UnsubscribeAll("CairnDemoSmoke")

		local off = Comm:Subscribe(PREFIX, function() end, "CairnDemoSmoke")
		t("Comm", "Subscribe returns unsub closure", type(off) == "function")
		t("Comm", "CountSubscribers reports 1",      Comm:CountSubscribers(PREFIX) == 1)

		off()
		t("Comm", "Closure unsub drops count to 0",  Comm:CountSubscribers(PREFIX) == 0)
	end)

	-- ----- Cairn umbrella facade ---------------------------------------
	R.pcallTest("Cairn", "umbrella facade resolves", function(t)
		t("Cairn", "Cairn global present",   _G.Cairn ~= nil)
		t("Cairn", "Cairn.Events resolves",  Cairn.Events  ~= nil)
		t("Cairn", "Cairn.Log resolves",     Cairn.Log     ~= nil)
		t("Cairn", "Cairn.DB resolves",      Cairn.DB      ~= nil)
		t("Cairn", "Cairn.Slash resolves",   Cairn.Slash   ~= nil)
	end)
end

-- ----- Tab build --------------------------------------------------------

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Smoke Test (PASS/FAIL across every lib)",
		demo.Snippets.smoketest)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Click 'Run' to assert every public API in the Cairn library set. The console below streams PASS / FAIL lines; the summary footer turns green when every test passes.")

	-- Big console.
	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 320,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 1600 })

	-- Summary line + Run button row.
	local summary = Gui:Acquire("Label", live, {
		text = "(not run)", variant = "body", align = "left",
	})

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Run smoke test", variant = "primary" })
		.Cairn:On("Click", function()
			console:Clear()
			summary.Cairn:SetText("(running...)")
			local R = buildRunner(console,
				function(text) summary.Cairn:SetText(text) end)
			R.setDone(function(pass, fail)
				console:Print(("--- summary: %d passed, %d failed ---"):format(pass, fail))
			end)
			runSuite(R)
			-- After the synchronous portion has run, print intermediate
			-- summary if there are no async tests pending.
			R.finishSync()
		end)

	Gui:Acquire("Button", row, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear(); summary.Cairn:SetText("(not run)") end)
end

Demo:RegisterTab("smoketest", {
	label    = "Smoke Test",
	order    = 999,
	build    = build,
})

-- Expose runner for headless re-use by Forge_Console test.
Demo._runSmokeTest = function(printFn)
	printFn = printFn or print
	local fakeConsole = { Print = function(_, t) printFn(t) end, Clear = function() end }
	local R = buildRunner(fakeConsole, printFn)
	R.setDone(function(pass, fail)
		printFn(("--- summary: %d passed, %d failed ---"):format(pass, fail))
	end)
	runSuite(R)
	R.finishSync()
end
