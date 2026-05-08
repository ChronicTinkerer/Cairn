--[[
Cairn-Media-Browser / Tabs / Welcome

The first tab. Lists per-type counts of registered media (split by
public / private), summarizes how to navigate, and notes the soft-dep
tie-in into Cairn-Gui-Theme-Default-2.0.

Cairn-Media-Browser/Tabs/Welcome (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media

local function build(pane, browser)
	local _, body = browser:BuildTabShell(pane, "Cairn Media Browser")
	if not body then return end

	-- Wrap the body in a ScrollFrame BEFORE setting Stack layout. The
	-- ScrollFrame's content Container has an explicit width, which is what
	-- the Stack strategy hands down to children so wrap=true labels know
	-- their max width. Same trick Cairn-Demo uses on its Welcome tab.
	body = browser:MakeScrollable(body, 800)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	browser:AppendIntro(body,
		"A live view of every asset registered with Cairn-Media-1.0. Each tab on the left shows one media type with name + preview. Visibility filter (All / Public / Private) sits above the list on each tab.")

	-- ----- Lib version --------------------------------------------------

	local _, mediaMinor = LibStub:GetLibrary("Cairn-Media-1.0", true)
	Gui:Acquire("Label", body, {
		text    = ("Cairn-Media-1.0 MINOR=%s"):format(tostring(mediaMinor or "?")),
		variant = "small",
		align   = "left",
	})

	-- ----- Per-type counts ----------------------------------------------

	Gui:Acquire("Label", body, {
		text = "Registered media (Cairn + third-party LSM)",
		variant = "heading",
		align = "left",
	})

	local LSM = LibStub("LibSharedMedia-3.0", true)
	local function lsmCount(t)
		if not LSM then return 0 end
		local n = 0
		for _, name in ipairs(LSM:List(t) or {}) do
			-- Exclude "Cairn ..." entries to avoid double-counting Cairn-public
			if not name:match("^Cairn ") then n = n + 1 end
		end
		return n
	end

	local function row(label, mediaType, listFn)
		local pubCount  = #listFn("public")
		local privCount = #listFn("private")
		local lsm       = lsmCount(mediaType)
		Gui:Acquire("Label", body, {
			text = ("- %s: %d Cairn-private, %d Cairn-public, %d third-party LSM (%d browseable total)"):format(
				label, privCount, pubCount, lsm, privCount + pubCount + lsm),
			variant = "body",
			align   = "left",
		})
	end

	row("Fonts",       "font",       function(v) return Media:ListFonts(v) end)
	row("Statusbars",  "statusbar",  function(v) return Media:ListStatusbars(v) end)
	row("Borders",     "border",     function(v) return Media:ListBorders(v) end)
	row("Backgrounds", "background", function(v) return Media:ListBackgrounds(v) end)
	row("Sounds",      "sound",      function(v) return Media:ListSounds(v) end)

	-- Icons aren't public/private; just count.
	local iconNames = Media:ListIcons()
	Gui:Acquire("Label", body, {
		text = ("- Icons: %d glyphs registered (Material Symbols; no public/private split)"):format(#iconNames),
		variant = "body",
		align   = "left",
	})

	-- ----- Theme tie-in note --------------------------------------------

	Gui:Acquire("Label", body, {
		text = "Theme tie-in",
		variant = "heading",
		align = "left",
	})

	Gui:Acquire("Label", body, {
		text    = "Cairn-Gui-Theme-Default-2.0 (MINOR >= 2) soft-deps on Cairn.Media for font.body / font.heading / font.small. The font tokens you see in widgets across this browser ARE pulled from the registry below.",
		variant = "muted",
		align   = "left",
		wrap    = true,
	})

	-- ----- Slash --------------------------------------------------------

	Gui:Acquire("Label", body, {
		text = "Slash commands",
		variant = "heading",
		align = "left",
	})

	for _, line in ipairs({
		"/cmb            toggle this window",
		"/cmb show       open it",
		"/cmb hide       close it",
		"/cairn-media    long-form alias",
	}) do
		Gui:Acquire("Label", body, {
			text = "  " .. line,
			variant = "small",
			align   = "left",
		})
	end
end

Browser:RegisterTab("welcome", {
	label = "Welcome",
	order = 0,
	build = build,
})
