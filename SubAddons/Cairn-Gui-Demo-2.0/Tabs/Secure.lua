--[[
Cairn-Gui-Demo-2.0 / Tabs / Secure

ActionButton + MacroButton + UnitButton, plus a fake-combat toggle that
flips lib.Combat:SetFakeCombat so the queue path is exercisable without
an actual fight. Combat-queue stats display live.

If Cairn-Gui-Widgets-Secure-2.0 isn't loaded, the tab shows a notice and
nothing else.

Cairn-Gui-Demo-2.0/Tabs/Secure (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

local function buildSecureNotLoaded(live)
	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "Cairn-Gui-Widgets-Secure-2.0 isn't loaded.",
		variant = "warning",
		align   = "left",
	})
	Gui:Acquire("Label", live, {
		text    = "The Secure widget bundle is optional and adds ActionButton / MacroButton / UnitButton plus a combat-aware mutation queue. The Cairn distribution ships it; if it's missing, your Cairn.toc may not be including the bundle entries.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Secure widgets -- ActionButton, MacroButton, UnitButton",
		demo.Snippets.secure)
	if not live then return end

	if not demo.secure then
		buildSecureNotLoaded(live)
		return
	end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	Gui:Acquire("Label", live, {
		text    = "All three secure widgets route attribute mutations through lib.Combat:Queue, so the typed wrappers below are safe to call mid-combat. Use the fake-combat toggle to exercise the queue without an actual fight.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- Combat status / fake-combat toggle ---------------------------

	local statusRow = Gui:Acquire("Container", live)
	statusRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	statusRow:SetHeight(28)

	local statusLabel = Gui:Acquire("Label", statusRow, {
		text    = "InCombat: false   queued: 0   drained: 0",
		variant = "body",
		align   = "left",
	})
	-- Force a fixed width so the row's horizontal Stack doesn't crush the
	-- label after long text writes.
	statusLabel:SetWidth(360)
	statusLabel.Cairn:SetLayoutManual(true)
	statusLabel:ClearAllPoints()
	statusLabel:SetPoint("LEFT", statusRow, "LEFT", 0, 0)

	local fakeBtn = Gui:Acquire("Button", statusRow, {
		text    = "Toggle fake combat",
		variant = "default",
		width   = 180,
	})
	fakeBtn.Cairn:SetLayoutManual(true)
	fakeBtn:ClearAllPoints()
	fakeBtn:SetPoint("LEFT", statusRow, "LEFT", 370, 0)

	fakeBtn.Cairn:On("Click", function()
		if Gui.Combat and Gui.Combat.SetFakeCombat then
			Gui.Combat:SetFakeCombat(not Gui.Combat:InCombat())
		end
	end)

	-- ---- ActionButton -------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "ActionButton (type=spell). Visual-only here; real cast needs a SecureActionButtonTemplate-eligible action and a real spell.",
		variant = "heading",
		align   = "left",
	})

	local abRow = Gui:Acquire("Container", live)
	abRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	abRow:SetHeight(40)

	-- Wrap the actual Acquire in pcall: secure widget construction can
	-- fail in a sandboxed test environment.
	local ok, ab = pcall(Gui.Acquire, Gui, "ActionButton", abRow, {
		type = "spell", spell = "Fireball",
		width = 36, height = 36,
	})
	if ok and ab then
		-- Position it via the row's Stack layout.
	else
		Gui:Acquire("Label", abRow, {
			text    = "ActionButton acquire failed (likely sandbox restriction)",
			variant = "danger",
			align   = "left",
		})
	end

	local switchSpell = Gui:Acquire("Button", abRow, {
		text = "SetSpell('Frostbolt')", variant = "default", width = 200,
	})
	switchSpell.Cairn:On("Click", function()
		if ab and ab.Cairn and ab.Cairn.SetSpell then
			ab.Cairn:SetSpell("Frostbolt")
		end
	end)

	-- ---- MacroButton --------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "MacroButton (macrotext)",
		variant = "heading",
		align   = "left",
	})

	local mbRow = Gui:Acquire("Container", live)
	mbRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	mbRow:SetHeight(36)

	local _, mb = pcall(Gui.Acquire, Gui, "MacroButton", mbRow, {
		macrotext = "/say Hello from a Cairn MacroButton!",
		text      = "Say Hello",
		width     = 140,
	})

	local switchMacro = Gui:Acquire("Button", mbRow, {
		text = "SetMacroText('/dance')", variant = "default", width = 220,
	})
	switchMacro.Cairn:On("Click", function()
		if mb and mb.Cairn and mb.Cairn.SetMacroText then
			mb.Cairn:SetMacroText("/dance")
			if mb.Cairn.SetText then mb.Cairn:SetText("Dance") end
		end
	end)

	-- ---- UnitButton ---------------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "UnitButton (unit=player; LeftButton=target, RightButton=menu)",
		variant = "heading",
		align   = "left",
	})

	local ubRow = Gui:Acquire("Container", live)
	ubRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	ubRow:SetHeight(36)

	local _, ub = pcall(Gui.Acquire, Gui, "UnitButton", ubRow, {
		unit = "player", width = 140, height = 28,
	})
	if ub and ub.Cairn and ub.Cairn.SetClickAction then
		ub.Cairn:SetClickAction("LeftButton", "target")
		ub.Cairn:SetClickAction("RightButton", "menu")
	end

	-- ---- Live status updater -----------------------------------------

	-- A 0.5s ticker on the live frame refreshes the combat status line.
	local tick = 0
	live:HookScript("OnUpdate", function(self_, dt)
		tick = tick + dt
		if tick < 0.5 then return end
		tick = 0
		local inCombat = Gui.Combat and Gui.Combat:InCombat()
		local stats = (Gui.Combat and Gui.Combat.Stats) and Gui.Combat:Stats() or nil
		statusLabel.Cairn:SetText(string.format(
			"InCombat: %s   queued: %d   drained: %d   depth: %d",
			tostring(inCombat),
			(stats and stats.queued)  or 0,
			(stats and stats.drained) or 0,
			(stats and stats.depth)   or 0))
	end)
end

Demo:RegisterTab("secure", {
	label = "Secure",
	order = 120,
	build = build,
})
