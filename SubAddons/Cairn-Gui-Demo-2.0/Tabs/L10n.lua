--[[
Cairn-Gui-Demo-2.0 / Tabs / L10n

Live "@namespace:key" resolution. Registers a "CairnGuiDemoL10n"
namespace via Cairn-Locale-1.0 with three locale tables; a Dropdown
switches the locale at runtime; the labels using @ prefix re-resolve
on next read (pulled by SetText repaints) and update visibly.

Cairn-Gui-Demo-2.0/Tabs/L10n (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnGuiDemo
if not Demo then return end

local Gui = Demo.lib

-- Best-effort locale registration. The Demo doesn't break if
-- Cairn-Locale isn't loaded; the tab just shows a degraded notice.
local Locale = LibStub("Cairn-Locale-1.0", true)

if Locale and Locale.New then
	-- Cairn-Gui-2.0 MINOR 19 fixed the resolver to rawget against the
	-- prototype, so the demo doesn't need silent=true to suppress the
	-- old "missing key Lookup" warning anymore. Left here as a record
	-- of the workaround in case someone running an older Core wants to
	-- re-enable it: { default = "enUS", silent = true }.
	Locale.New("CairnGuiDemoL10n", {
		enUS = {
			greeting = "Hello!",
			save     = "Save",
			cancel   = "Cancel",
			delete   = "Delete",
			help     = "These strings come from Cairn-Locale via @namespace:key",
		},
		deDE = {
			greeting = "Hallo!",
			save     = "Speichern",
			cancel   = "Abbrechen",
			delete   = "Loeschen",
			help     = "Diese Texte kommen aus Cairn-Locale per @namespace:key",
		},
		frFR = {
			greeting = "Bonjour !",
			save     = "Enregistrer",
			cancel   = "Annuler",
			delete   = "Supprimer",
			help     = "Ces textes viennent de Cairn-Locale via @namespace:key",
		},
	}, { default = "enUS" })
end

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"L10n -- @namespace:key resolution via Cairn-Locale",
		demo.Snippets.l10n)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 8, padding = 12 })

	if not Locale or not Locale.New then
		Gui:Acquire("Label", live, {
			text    = "Cairn-Locale-1.0 isn't loaded; L10n routing has nothing to talk to. Make sure Cairn includes CairnLocale\\Cairn-Locale-1.0.lua in its TOC.",
			variant = "warning",
			wrap    = true,
			align   = "left",
		})
		return
	end

	Gui:Acquire("Label", live, {
		text    = "Switch the active locale below. Labels using the @CairnGuiDemoL10n: prefix re-resolve through Cairn-Locale lazily.",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	-- ---- Locale picker -----------------------------------------------

	local pickerRow = Gui:Acquire("Container", live)
	pickerRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	pickerRow:SetHeight(28)

	Gui:Acquire("Label", pickerRow, { text = "Active locale:", variant = "body" })

	local picker = Gui:Acquire("Dropdown", pickerRow, {
		options = {
			{ value = "enUS", label = "English (enUS)"   },
			{ value = "deDE", label = "Deutsch (deDE)"   },
			{ value = "frFR", label = "Francais (frFR)" },
		},
		selected = "enUS",
		width    = 200,
	})

	-- ---- Localized widgets -------------------------------------------

	Gui:Acquire("Label", live, {
		text    = "Localized widgets (text starts with @CairnGuiDemoL10n:KEY)",
		variant = "heading",
		align   = "left",
	})

	local greeting = Gui:Acquire("Label", live, {
		text    = "@CairnGuiDemoL10n:greeting",
		variant = "body",
		align   = "left",
	})
	local helpLine = Gui:Acquire("Label", live, {
		text    = "@CairnGuiDemoL10n:help",
		variant = "muted",
		wrap    = true,
		align   = "left",
	})

	local actionRow = Gui:Acquire("Container", live)
	actionRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 8, padding = 0 })
	actionRow:SetHeight(36)

	local saveBtn   = Gui:Acquire("Button", actionRow, {
		text = "@CairnGuiDemoL10n:save",   variant = "primary", width = 120,
	})
	local cancelBtn = Gui:Acquire("Button", actionRow, {
		text = "@CairnGuiDemoL10n:cancel", variant = "default", width = 120,
	})
	local deleteBtn = Gui:Acquire("Button", actionRow, {
		text = "@CairnGuiDemoL10n:delete", variant = "danger",  width = 120,
	})

	-- The L10n resolver is lazy; widgets re-resolve on the next read.
	-- Programmatically: each SetText call routes through _resolveText.
	-- To make a switch visible we re-set the same @-prefixed string,
	-- and the resolver reads the now-active locale.
	local function refreshLocalized()
		-- Cairn-Gui-2.0 MINOR 19 made SetText auto-invalidate the parent
		-- layout, so the explicit RelayoutNow() calls that used to live
		-- here are no longer needed. The locale-switch test exercises
		-- exactly that auto-invalidate path on every Button/Label.
		greeting.Cairn:SetText("@CairnGuiDemoL10n:greeting")
		helpLine.Cairn:SetText("@CairnGuiDemoL10n:help")
		saveBtn.Cairn:SetText("@CairnGuiDemoL10n:save")
		cancelBtn.Cairn:SetText("@CairnGuiDemoL10n:cancel")
		deleteBtn.Cairn:SetText("@CairnGuiDemoL10n:delete")
	end

	picker.Cairn:On("Changed", function(_, locale)
		-- Cairn-Locale's runtime switch is a LIBRARY-level override that
		-- repoints every registered instance to the chosen locale. There
		-- is no per-instance SetLocale; the lib walks lib.registry inside
		-- SetOverride and resets each instance's _locale field.
		if Locale.SetOverride then
			Locale.SetOverride(locale)
		end
		refreshLocalized()
	end)

	-- ---- Pass-through demo (plain strings unchanged) -----------------

	Gui:Acquire("Label", live, {
		text    = "Plain strings (no @ prefix) pass through unchanged; malformed @ prefixes also pass through.",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
	-- The label below shows what an unknown-key resolution looks like.
	-- We write the @ prefix as a plain string (no leading @) so the
	-- resolver doesn't actually try to resolve it -- otherwise the
	-- regex captures the whole sentence as the key and the silent
	-- pass-through hides the demo point we're trying to make.
	Gui:Acquire("Label", live, {
		text    = "Example unknown-key fallback: a label with text \"@CairnGuiDemoL10n:no_such_key\" would render that exact string when no_such_key isn't in the locale table.",
		variant = "small",
		align   = "left",
		wrap    = true,
	})
end

Demo:RegisterTab("l10n", {
	label = "L10n",
	order = 100,
	build = build,
})
