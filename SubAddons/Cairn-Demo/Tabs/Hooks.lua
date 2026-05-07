--[[
Cairn-Demo / Tabs / Hooks

Live demo of Cairn-Hooks-1.0. Post-hooks a method on a private throw-away
Frame so the demo doesn't perturb anything else; shows the dispatcher
fanning out to multiple callbacks; demonstrates that closure-unhook only
masks the callback (the underlying hooksecurefunc stays for the session).

Cairn-Demo/Tabs/Hooks (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui   = Demo.lib
local Hooks = LibStub("Cairn-Hooks-1.0")

-- Private target. Frame with a unique-per-tab name (CreateFrame requires
-- a name for our hook target since most use cases hook frame methods).
local hookTarget = nil
local function ensureTarget()
	if hookTarget then return hookTarget end
	hookTarget = CreateFrame("Frame", "CairnDemoHookTarget", UIParent)
	-- Add a table-style "method" we can post-hook. hooksecurefunc accepts
	-- frame methods directly; using SetSize gives us something that fires
	-- on demand without side effects beyond resizing this hidden frame.
	hookTarget:SetSize(1, 1)
	hookTarget:Hide()
	return hookTarget
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Hooks-1.0",
		demo.Snippets.hooks)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Multi-callback hooksecurefunc dispatcher. WoW prevents un-installing a hooksecurefunc within a session, but Cairn.Hooks lets the unhook closure mask just our callback so subsequent fires skip it.")

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 600 })

	-- Track our hooks so the user can call unhook() on each.
	local hookA, hookB
	local target = ensureTarget()

	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Hook A on SetSize", variant = "primary" })
		.Cairn:On("Click", function()
			if hookA then console:Print("A already hooked"); return end
			hookA = Hooks.Post(target, "SetSize", function(self, w, h)
				console:Print(("hook A: SetSize(%s, %s)"):format(tostring(w), tostring(h)))
			end)
			console:Print("hook A installed")
		end)

	Gui:Acquire("Button", row, { text = "Hook B on SetSize", variant = "primary" })
		.Cairn:On("Click", function()
			if hookB then console:Print("B already hooked"); return end
			hookB = Hooks.Post(target, "SetSize", function(self, w, h)
				console:Print(("hook B: also got SetSize(%s, %s)"):format(tostring(w), tostring(h)))
			end)
			console:Print("hook B installed")
		end)

	Gui:Acquire("Button", row, { text = "Fire SetSize", variant = "default" })
		.Cairn:On("Click", function()
			local w = math.random(20, 100)
			target:SetSize(w, w)
			console:Print(("called target:SetSize(%d, %d)"):format(w, w))
		end)

	Gui:Acquire("Button", row, { text = "Unhook A", variant = "danger" })
		.Cairn:On("Click", function()
			if hookA then hookA(); hookA = nil; console:Print("A unhooked (closure masked)") end
		end)

	Gui:Acquire("Button", row, { text = "Unhook B", variant = "danger" })
		.Cairn:On("Click", function()
			if hookB then hookB(); hookB = nil; console:Print("B unhooked") end
		end)

	-- Diagnostics.
	local row2 = Gui:Acquire("Container", live, {})
	row2.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row2:SetHeight(28)

	Gui:Acquire("Button", row2, { text = "Has?", variant = "default" })
		.Cairn:On("Click", function()
			console:Print(("Hooks.Has -> %s   Hooks.Count -> %s"):format(
				tostring(Hooks.Has(target, "SetSize")),
				tostring(Hooks.Count(target, "SetSize"))))
		end)

	Gui:Acquire("Button", row2, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("hooks", {
	label = "Hooks",
	order = 100,
	build = build,
})
