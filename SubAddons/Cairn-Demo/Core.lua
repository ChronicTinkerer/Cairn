--[[
Cairn-Demo / Core

Root addon shell for the non-GUI Cairn library showcase. Companion to
Cairn-Gui-Demo-2.0 (which covers the GUI side). This addon exercises:

    Cairn-Callback-1.0    Cairn-Hooks-1.0
    Cairn-Events-1.0      Cairn-Sequencer-1.0
    Cairn-Log-1.0         Cairn-Timer-1.0
    Cairn-LogWindow-1.0   Cairn-FSM-1.0
    Cairn-DB-1.0          Cairn-Comm-1.0
    Cairn-Settings-1.0    Cairn-EditMode-1.0  (optional)
    Cairn-SettingsPanel-1.0
    Cairn-Addon-1.0
    Cairn-Slash-1.0
    Cairn-Locale-1.0

Architecture mirrors Cairn-Gui-Demo-2.0:
    - One file per tab under Tabs/. Each calls Demo:RegisterTab(id, def)
      at file-scope load.
    - Tabs are built lazily on first view via the TabGroup Changed event.
    - Each tab gets a 2-pane shell (live demo on the left, code snippet
      on the right) via Demo:BuildTabShell.

The demo window is built on Cairn-Gui-2.0 widgets because they're a hard
dependency of the parent addon -- it would be silly to write a custom
window renderer when the GUI lib is already loaded. Cairn-SettingsPanel-1.0
(which is built on Cairn-Gui-1.0) is demonstrated by spawning its own
panel via :OpenStandalone(); the v1 panel renders independently of this
window.

Slash:
    /cdemo                toggle the window
    /cairn-demo           long form, same effect

Cairn-Demo/Core (c) 2026 ChronicTinkerer. MIT license.
]]

local ADDON_NAME = ...

-- ----- LibStub handles --------------------------------------------------
-- Pulled lazily so a missing dependency surfaces as a clear error rather
-- than a nil-deref deep inside a tab.

local function requireLib(name)
	local lib = LibStub(name, true)
	if not lib then
		error(("[%s] missing dependency: %s. Make sure Cairn is installed and enabled."):format(
			ADDON_NAME, tostring(name)), 2)
	end
	return lib
end

-- The demo's UI is built with Cairn-Gui-2.0. The libraries we DEMO are
-- pulled in by individual tabs from Cairn.<Foo> (or LibStub directly) so
-- a user with a stripped-down Cairn install can still see "this lib not
-- loaded" notices instead of a chain of nils.
local Gui   = requireLib("Cairn-Gui-2.0")
local Std   = requireLib("Cairn-Gui-Widgets-Standard-2.0")
local Theme = requireLib("Cairn-Gui-Theme-Default-2.0")  -- noqa: side-effect register

-- Cairn umbrella facade. Falls back to LibStub("Cairn-Foo-1.0") on demand.
-- All non-GUI libs are accessed through this in tab code (matches the
-- documentation pattern in each lib's header).
local Cairn = _G.Cairn
if not Cairn then
	error(("[%s] Cairn umbrella facade not present. Cairn.lua must load before SubAddons."):format(ADDON_NAME), 2)
end

-- ----- Demo namespace ---------------------------------------------------

local Demo = {}
_G.CairnDemo = Demo

Demo.lib       = Gui      -- Cairn-Gui-2.0 (used to render the demo window)
Demo.standard  = Std
Demo.theme     = Theme
Demo.cairn     = Cairn    -- Umbrella facade; tabs read Cairn.Events, Cairn.Log, etc.

-- ----- Tab registry ------------------------------------------------------
-- {id -> def} plus a sorted order list maintained as tabs register. Each
-- Tabs/*.lua file calls Demo:RegisterTab(id, def) at file scope load so
-- by the time Show() runs every tab is known.

Demo._tabs       = {}
Demo._tabOrder   = {}
Demo._tabBuilt   = {}  -- id -> bool, true once build() ran

function Demo:RegisterTab(id, def)
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
-- 16 tabs at avg ~70-80px each = ~1280px tab strip. Pad to 1320 so font /
-- locale variation has room. 600 vertical matches the GUI demo.

local WINDOW_W = 1320
local WINDOW_H = 600

local function buildWindow(self)
	if self._win then return self._win end

	local win = Gui:Acquire("Window", UIParent, {
		title  = "Cairn Library Demo",
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
				("|cffff5050[CairnDemo] tab %q build error:|r %s")
				:format(tostring(tabId), tostring(err)))
		end
		self._tabBuilt[tabId] = true
	end

	tg.Cairn:On("Changed", function(_, tabId)
		ensureBuilt(tabId)
	end)

	if self._tabOrder[1] then
		ensureBuilt(self._tabOrder[1].id)
	end

	self._win = win
	self._tg  = tg
	return win
end

function Demo:Show()
	local win = buildWindow(self)
	if win and win.Show then win:Show() end
end

function Demo:Hide()
	if self._win and self._win.Hide then self._win:Hide() end
end

function Demo:Toggle()
	if self._win and self._win:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

-- ----- Tab shell helpers ------------------------------------------------
-- Each tab calls BuildTabShell(pane, heading, code) and gets back a
-- (heading, livePane, codeLabel) trio. The live pane fills the left 50%
-- of the tab and is where the tab renders interactive widgets; the code
-- label fills the right 50% inside a ScrollFrame and shows the snippet.

function Demo:BuildTabShell(pane, headingText, codeText)
	pane.Cairn:SetLayoutManual(true)

	local heading = Gui:Acquire("Label", pane, {
		text    = headingText or "",
		variant = "heading",
		align   = "left",
	})
	heading.Cairn:SetLayoutManual(true)
	heading:ClearAllPoints()
	heading:SetPoint("TOPLEFT",  pane, "TOPLEFT",  12, -10)
	heading:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -12, -10)
	heading:SetHeight(22)

	local live = Gui:Acquire("Container", pane, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	live.Cairn:SetLayoutManual(true)
	live:ClearAllPoints()
	live:SetPoint("TOPLEFT",     pane, "TOPLEFT",     12, -38)
	live:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT",  12 + math.floor(WINDOW_W * 0.50), 12)

	local codeBox = Gui:Acquire("ScrollFrame", pane, {
		bg            = "color.bg.panel",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = 1200,
		showScrollbar = true,
	})
	codeBox.Cairn:SetLayoutManual(true)
	codeBox:ClearAllPoints()
	codeBox:SetPoint("TOPLEFT",     pane, "TOPLEFT",     12 + math.floor(WINDOW_W * 0.50) + 8, -38)
	codeBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 12)

	local codeContent = codeBox.Cairn:GetContent()
	codeContent.Cairn:SetLayoutManual(true)

	local codeLabel = Gui:Acquire("Label", codeContent, {
		text    = codeText or "",
		variant = "small",
		align   = "left",
		wrap    = true,
		width   = math.floor(WINDOW_W * 0.45) - 26,
	})
	codeLabel.Cairn:SetLayoutManual(true)
	codeLabel:ClearAllPoints()
	codeLabel:SetPoint("TOPLEFT",  codeContent, "TOPLEFT",  6, -6)
	codeLabel:SetPoint("TOPRIGHT", codeContent, "TOPRIGHT", -6, -6)

	local _, ih = codeLabel.Cairn:GetIntrinsicSize()
	if ih and ih > 0 then
		codeBox.Cairn:SetContentHeight(ih + 24)
		codeLabel:SetHeight(ih + 4)
	end

	return heading, live, codeLabel
end

-- Make a tab's live pane scrollable. Returns the inner content Container
-- the tab should populate. Identical mechanics to Cairn-Gui-Demo-2.0.
function Demo:MakeScrollable(live, contentHeight)
	local lw = math.floor(live:GetWidth()  or 0)
	local lh = math.floor(live:GetHeight() or 0)
	if lw <= 1 or lh <= 1 then
		lw = lw > 1 and lw or 480
		lh = lh > 1 and lh or 480
	end

	local sf = Gui:Acquire("ScrollFrame", live, {
		width         = lw,
		height        = lh,
		contentHeight = contentHeight or 1200,
		showScrollbar = true,
	})
	sf.Cairn:SetLayoutManual(true)
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT",     live, "TOPLEFT",     0, 0)
	sf:SetPoint("BOTTOMRIGHT", live, "BOTTOMRIGHT", 0, 0)

	local content = sf.Cairn:GetContent()
	content._scrollFrame = sf
	return content
end

-- Convenience: a single-paragraph helper text under the heading inside the
-- live pane, used by most tabs as a one-line "what is this?" intro.
--
-- Parent-layout-aware. If the live pane already has a layout strategy
-- bound (Stack / Grid / Form / etc.), we just create the Label as a
-- regular child of that layout so the Stack flow places it cleanly. If
-- the pane is manual-laid (or has no layout), we anchor the Label to
-- the top with manual SetPoint, mark it manual, and size it to its
-- intrinsic height. Mixing the two -- a manual-positioned child inside
-- a Stack-laid pane -- causes the Stack flow to ignore the manual
-- child's position and overlap on top of it. (Caught in-game testing
-- the Callback tab on 2026-05-07.)
function Demo:AppendIntro(livePane, text)
	local hasLayout = false
	if livePane.Cairn and livePane.Cairn.GetLayout then
		local name = livePane.Cairn:GetLayout()
		if name and name ~= "Manual" then hasLayout = true end
	end

	if hasLayout then
		-- Stack / Grid / etc. parent: just append a regular child.
		return Gui:Acquire("Label", livePane, {
			text    = text or "",
			variant = "muted",
			align   = "left",
			wrap    = true,
		})
	end

	-- Manual-laid parent: anchor to the top with absolute SetPoint.
	local lbl = Gui:Acquire("Label", livePane, {
		text    = text or "",
		variant = "muted",
		align   = "left",
		wrap    = true,
		width   = livePane:GetWidth() - 16,
	})
	lbl.Cairn:SetLayoutManual(true)
	lbl:ClearAllPoints()
	lbl:SetPoint("TOPLEFT",  livePane, "TOPLEFT",   8, -8)
	lbl:SetPoint("TOPRIGHT", livePane, "TOPRIGHT", -8, -8)
	local _, ih = lbl.Cairn:GetIntrinsicSize()
	lbl:SetHeight((ih and ih > 0) and (ih + 4) or 32)
	return lbl
end

-- Append a plain log line to a "console" pane on a tab. Used by tabs that
-- want to show the result of an interaction (button press, event fire,
-- timer expiry) inline rather than via /print.
function Demo:Console(parent, opts)
	opts = opts or {}
	local sf = Gui:Acquire("ScrollFrame", parent, {
		bg            = "color.bg.panel",
		border        = "color.border.subtle",
		borderWidth   = 1,
		contentHeight = opts.contentHeight or 600,
		showScrollbar = true,
	})
	local content = sf.Cairn:GetContent()
	content.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 2, padding = 6 })

	local console = { _sf = sf, _content = content, _lines = {} }

	function console:Print(text)
		local line = Gui:Acquire("Label", self._content, {
			text    = tostring(text or ""),
			variant = "small",
			align   = "left",
			wrap    = true,
		})
		self._lines[#self._lines + 1] = line
		-- No manual RelayoutNow: _addChild on the Stack-laid Container
		-- already invalidates the layout. If a dynamic-Acquire lag turns
		-- up in-game, fix it in Mixins/Base or the Stack strategy, not
		-- here.
		return line
	end

	function console:Clear()
		-- Release IS on the Cairn mixin, NOT on the frame. Gui:Acquire
		-- returns the frame, so `line` is the frame and `line.Release`
		-- is nil. Use `line.Cairn:Release()` to actually release the
		-- pooled widget. Caught alongside the same bug pattern in
		-- Cairn-Media-Browser 2026-05-08.
		for _, line in ipairs(self._lines) do
			if line.Cairn and line.Cairn.Release then line.Cairn:Release() end
		end
		self._lines = {}
	end

	return sf, console
end

-- ----- Shared SavedVariables-backed DB ----------------------------------
-- The DB / Settings / Addon tabs all want a Cairn.DB instance to play
-- with. We create ONE shared instance up-front (NOT touching .profile at
-- file scope per the cairn_db_no_retro_defaults memory) and let tabs
-- consume it in OnInit-style lazy reads inside their builders.
--
-- Note: per Cairn-DB docs, defaults are NOT retroactively applied. New
-- keys added here later won't appear in existing Cairn-Demo profiles
-- without a /reload + delete CairnDemoDB step. That's fine for a demo.

Demo.db = Cairn.DB.New("CairnDemoDB", {
	defaults = {
		profile = {
			counter   = 0,
			theme     = "default",
			welcome   = true,
			label     = "Hello",
			scale     = 1.0,
		},
		global = {
			installed = nil,  -- set on first OnInit; lets us show "first run" vs returning
		},
	},
	profileType = "char",
})

-- ----- Boot lifecycle ---------------------------------------------------
-- Use Cairn.Addon to demonstrate the lifecycle hooks AND to defer the
-- DB.profile force-init until SavedVariables are loaded.

local addon = Cairn.Addon.New("CairnDemo")
Demo.addon = addon

function addon:OnInit()
	-- Safe to touch db.profile here; SVs are loaded.
	local db = Demo.db
	if db.profile.counter == nil then db.profile.counter = 0 end
	if db.global.installed == nil then
		db.global.installed = time()
		Demo._firstRun = true
	end
end

function addon:OnLogin()
	-- Lazy logger; gated on Cairn-Log so a stripped install isn't noisy.
	local Log = Cairn.Log
	if Log then
		local logger = Log("CairnDemo")
		if logger and logger.Info then
			local _, libMinor = Gui:GetVersion()
			logger:Info("loaded; Cairn-Gui-2.0 MINOR=%d. Type /cdemo to open.", libMinor)
		end
	end
end

-- ----- Slash command ----------------------------------------------------
-- Demonstrate Cairn.Slash by dogfooding it for our own slash. Subcommands
-- are listed in the Slash tab's snippet.

local slash = Cairn.Slash.Register("CairnDemo", "/cdemo", { aliases = { "/cairn-demo" } })
Demo.slash = slash

slash:Default(function() Demo:Toggle() end)
slash:Subcommand("show", function() Demo:Show() end, "open the demo window")
slash:Subcommand("hide", function() Demo:Hide() end, "close the demo window")
slash:Subcommand("smoke", function()
	Demo:Show()
	-- Programmatic tab switch: select the SmokeTest tab and run.
	if Demo._tg and Demo._tg.Cairn and Demo._tg.Cairn.SetSelected then
		Demo._tg.Cairn:SetSelected("smoketest")
	end
end, "open and run the smoke test")
