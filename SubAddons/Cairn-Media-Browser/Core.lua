--[[
Cairn-Media-Browser / Core

Root addon shell for the Cairn-Media browser. Internal companion to
Cairn-Demo (which covers non-GUI libs) and Cairn-Gui-Demo-2.0 (which
covers Cairn-Gui-2.0 widgets). This addon is a live viewer over
everything `Cairn-Media-1.0` has registered:

    Fonts (font paths + live preview at multiple sizes)
    Statusbars (visual swatches)
    Borders (sample rectangle wrapped in each border)
    Backgrounds (panel fills)
    Sounds (play buttons)
    Icons (Material Symbols glyph grid with font selector)

Architecture mirrors Cairn-Demo:
    - One file per tab under Tabs/. Each calls Browser:RegisterTab(id, def)
      at file-scope load.
    - Tabs are built lazily on first view via the TabGroup Changed event.
    - Each tab builds its own scrollable list of registered items into
      the live pane provided by Browser:BuildTabShell.

Slash:
    /cmb                  toggle the window
    /cairn-media          long form, same effect

Cairn-Media-Browser/Core (c) 2026 ChronicTinkerer. MIT license.
]]

local ADDON_NAME = ...

-- ----- LibStub handles --------------------------------------------------

local function requireLib(name)
	local lib = LibStub(name, true)
	if not lib then
		error(("[%s] missing dependency: %s. Make sure Cairn is installed and enabled."):format(
			ADDON_NAME, tostring(name)), 2)
	end
	return lib
end

local Gui   = requireLib("Cairn-Gui-2.0")
local Std   = requireLib("Cairn-Gui-Widgets-Standard-2.0")
local Theme = requireLib("Cairn-Gui-Theme-Default-2.0")  -- noqa: side-effect register
local Media = requireLib("Cairn-Media-1.0")

local Cairn = _G.Cairn
if not Cairn then
	error(("[%s] Cairn umbrella facade not present."):format(ADDON_NAME), 2)
end

-- ----- Browser namespace ------------------------------------------------

local Browser = {}
_G.CairnMediaBrowser = Browser

Browser.lib       = Gui
Browser.standard  = Std
Browser.theme     = Theme
Browser.media     = Media
Browser.cairn     = Cairn

-- ----- Tab registry ------------------------------------------------------

Browser._tabs     = {}
Browser._tabOrder = {}
Browser._tabBuilt = {}

function Browser:RegisterTab(id, def)
	if type(id) ~= "string" or id == "" then
		error("RegisterTab: id must be a non-empty string", 2)
	end
	if type(def) ~= "table" then
		error("RegisterTab: def must be a table", 2)
	end
	def.id    = id
	def.label = def.label or id
	def.order = def.order or 100
	if def.build and type(def.build) ~= "function" then
		error("RegisterTab: def.build must be a function or nil", 2)
	end
	self._tabs[id] = def
	table.insert(self._tabOrder, def)
	table.sort(self._tabOrder, function(a, b)
		if a.order == b.order then return a.label < b.label end
		return a.order < b.order
	end)
end

-- ----- Window construction ----------------------------------------------
-- 7 tabs at avg ~80px = ~560px tab strip; pad to 960 wide so font / icon
-- previews have plenty of room. 600 vertical matches the other demos.

-- Module-scope so BuildTabShell can reference them when sizing the body
-- explicitly (anchor-only sizing was leaving body width unknown until
-- after first layout pass, which broke MakeScrollable's GetWidth probe).
Browser.WINDOW_W = 960
Browser.WINDOW_H = 600
local WINDOW_W   = Browser.WINDOW_W
local WINDOW_H   = Browser.WINDOW_H

-- Approximate inner-body dimensions inside a tab pane:
--   width  = WINDOW_W - 24 (12 padding each side)        = 936
--   height = WINDOW_H - title - tabstrip - heading - pad
--          ~ 600 - 28 - 28 - 22 - 12 - 12                = 498
-- Pad to 500 to be safe; rows scroll inside MakeScrollable when they
-- exceed body height.
Browser.BODY_W = WINDOW_W - 24
Browser.BODY_H = WINDOW_H - 100
local BODY_W   = Browser.BODY_W
local BODY_H   = Browser.BODY_H

local function buildWindow(self)
	if self._win then return self._win end

	local win = Gui:Acquire("Window", UIParent, {
		title  = "Cairn Media Browser",
		width  = WINDOW_W,
		height = WINDOW_H,
	})
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

	local content = win.Cairn:GetContent()
	content.Cairn:SetLayoutManual(true)

	local tabsForGroup = {}
	for i, def in ipairs(self._tabOrder) do
		tabsForGroup[i] = { id = def.id, label = def.label }
	end

	local tg = Gui:Acquire("TabGroup", content, {
		tabs      = tabsForGroup,
		selected  = (self._tabOrder[1] and self._tabOrder[1].id) or nil,
		tabHeight = 28,
		gap       = 2,
	})
	tg:ClearAllPoints()
	tg:SetPoint("TOPLEFT",     content, "TOPLEFT",     6, -6)
	tg:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 6)

	local function ensureBuilt(tabId)
		if self._tabBuilt[tabId] then return end
		local def = self._tabs[tabId]
		if not def or not def.build then
			self._tabBuilt[tabId] = true
			return
		end
		local pane = tg.Cairn:GetTabContent(tabId)
		if not pane then return end
		local ok, err = pcall(def.build, pane, self)
		if not ok and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(
				("|cffff5050[CairnMediaBrowser] tab %q build error:|r %s")
				:format(tostring(tabId), tostring(err)))
		end
		self._tabBuilt[tabId] = true
	end

	-- TabGroup handles pane visibility internally via applyVisibility:
	-- SetSelected -> applyVisibility -> _content:SetShown(active) for each
	-- pane. We just need to build tab content lazily on first activation.
	tg.Cairn:On("Changed", function(_, tabId)
		ensureBuilt(tabId)
	end)

	-- The `selected` opt to TabGroup Acquire already activated the first
	-- tab (see TabGroup.OnAcquire); just build it.
	if self._tabOrder[1] then
		ensureBuilt(self._tabOrder[1].id)
	end

	self._win = win
	self._tg  = tg
	return win
end

function Browser:Show()
	local win = buildWindow(self)
	if win and win.Show then win:Show() end
end

function Browser:Hide()
	if self._win and self._win.Hide then self._win:Hide() end
end

function Browser:Toggle()
	if self._win and self._win:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

-- ----- Tab shell helpers ------------------------------------------------
-- Simpler than Cairn-Demo: no live/code split. Each media-type tab just
-- gets one heading and one full-width scrollable pane to render its list
-- of registered items into.

function Browser:BuildTabShell(pane, headingText)
	pane.Cairn:SetLayoutManual(true)

	local heading = Gui:Acquire("Label", pane, {
		text    = headingText or "",
		variant = "heading",
		align   = "left",
	})
	heading.Cairn:SetLayoutManual(true)
	heading:ClearAllPoints()
	heading:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, -10)
	heading:SetSize(BODY_W, 22)

	-- Empty opts on body (no bg / border / borderWidth). Earlier versions
	-- gave it a surface backdrop, but the diagnostic showed widgets were
	-- being created (23+ frames in the pane subtree) and just not visible.
	-- Cairn-Demo's `live` -- the proven-working pattern that this whole
	-- shell mirrors -- uses empty opts; the ScrollFrame inside renders
	-- fine because there's no Container backdrop to interfere with its
	-- clipping or drawlayer ordering.
	local body = Gui:Acquire("Container", pane, {})
	body.Cairn:SetLayoutManual(true)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, -38)
	-- Explicit SetSize instead of a BOTTOMRIGHT anchor. The pane often
	-- isn't sized when build runs (TabGroup lazy layout), so an anchor-
	-- only body has GetWidth() == 0, which makes MakeScrollable fall
	-- back to a hardcoded 900px content width that doesn't match what
	-- Stack expects. Hardcoding body dimensions to BODY_W / BODY_H
	-- gives MakeScrollable real numbers from the start.
	body:SetSize(BODY_W, BODY_H)

	return heading, body
end

-- Wraps the body container in a scrollable pane and returns the inner
-- content Container ready for the tab to populate. Identical mechanics
-- to Cairn-Demo's MakeScrollable.
function Browser:MakeScrollable(body, contentHeight)
	local bw = math.floor(body:GetWidth()  or 0)
	local bh = math.floor(body:GetHeight() or 0)
	if bw <= 1 then bw = 900 end
	if bh <= 1 then bh = 520 end

	local sf = Gui:Acquire("ScrollFrame", body, {
		width         = bw,
		height        = bh,
		contentHeight = contentHeight or 1200,
		showScrollbar = true,
	})
	sf.Cairn:SetLayoutManual(true)
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT",     body, "TOPLEFT",     0, 0)
	sf:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	local content = sf.Cairn:GetContent()
	content._scrollFrame = sf
	return content
end

-- Append a one-line muted intro under the heading inside the body. Same
-- semantics as Cairn-Demo's AppendIntro.
function Browser:AppendIntro(parent, text)
	local hasLayout = false
	if parent.Cairn and parent.Cairn.GetLayout then
		local name = parent.Cairn:GetLayout()
		if name and name ~= "Manual" then hasLayout = true end
	end

	if hasLayout then
		return Gui:Acquire("Label", parent, {
			text    = text or "",
			variant = "muted",
			align   = "left",
			wrap    = true,
		})
	end

	local lbl = Gui:Acquire("Label", parent, {
		text    = text or "",
		variant = "muted",
		align   = "left",
		wrap    = true,
		width   = (parent:GetWidth() or 800) - 16,
	})
	lbl.Cairn:SetLayoutManual(true)
	lbl:ClearAllPoints()
	lbl:SetPoint("TOPLEFT",  parent, "TOPLEFT",   8, -8)
	lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
	local _, ih = lbl.Cairn:GetIntrinsicSize()
	lbl:SetHeight((ih and ih > 0) and (ih + 4) or 32)
	return lbl
end

-- Build a visibility filter row (All / Public / Private buttons) above
-- the list. Returns the row container plus an `onChange(visibility)`
-- subscriber slot the caller fills in. visibility is nil ("All"),
-- "public", or "private".
function Browser:BuildVisibilityFilter(parent, initial, onChange)
	local row = Gui:Acquire("Container", parent, {})
	row.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 4, padding = 0 })
	row:SetHeight(26)

	local current = initial  -- nil | "public" | "private"
	local buttons = {}

	local function refresh()
		for label, btn in pairs(buttons) do
			local active =
				(label == "All"     and current == nil) or
				(label == "Public"  and current == "public") or
				(label == "Private" and current == "private")
			btn.Cairn:SetVariant(active and "primary" or "default")
		end
	end

	for _, spec in ipairs({
		{ "All",     nil },
		{ "Public",  "public" },
		{ "Private", "private" },
	}) do
		local label, value = spec[1], spec[2]
		local btn = Gui:Acquire("Button", row, { text = label, variant = "default" })
		buttons[label] = btn
		btn.Cairn:On("Click", function()
			current = value
			refresh()
			if onChange then onChange(current) end
		end)
	end
	refresh()

	return row, function() return current end
end

-- ----- Boot lifecycle ---------------------------------------------------

local addon = Cairn.Addon.New("CairnMediaBrowser")
Browser.addon = addon

function addon:OnLogin()
	local Log = Cairn.Log
	if Log then
		local logger = Log("CairnMediaBrowser")
		if logger and logger.Info then
			logger:Info("loaded; type /cmb to open the media browser.")
		end
	end
end

-- ----- Slash command ----------------------------------------------------

local slash = Cairn.Slash.Register("CairnMediaBrowser", "/cmb",
	{ aliases = { "/cairn-media" } })
Browser.slash = slash

slash:Default(function() Browser:Toggle() end)
slash:Subcommand("show", function() Browser:Show() end, "open the browser")
slash:Subcommand("hide", function() Browser:Hide() end, "close the browser")
