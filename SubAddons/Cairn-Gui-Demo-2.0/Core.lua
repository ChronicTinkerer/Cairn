--[[
Cairn-Gui-Demo-2.0 / Core

Init, slash command, and the root Window + TabGroup shell every tab
hangs off. The Demo isn't a LibStub-published bundle (it's a consumer
addon, not a library), so this file just builds normal addon plumbing
on top of LibStub("Cairn-Gui-2.0").

Public-ish surface (all under the Demo addon namespace, NOT Cairn.Gui):

	Demo:Show()                      open the demo window
	Demo:Hide()                      close it
	Demo:Toggle()                    toggle visibility
	Demo:RegisterTab(id, def)        called from each Tabs/*.lua file at
	                                 file-scope load to register itself.
	                                 def = {
	                                   id      = "buttons",
	                                   label   = "Buttons",
	                                   order   = 20,
	                                   build   = function(paneFrame, demo)
	                                       -- populate the tab content
	                                   end,
	                                 }

Tabs are registered at file load (TOC order) but built lazily, the first
time the tab is opened. Build order = registration order, with `order`
breaking ties (lower order earlier).

Slash:
	/cgdemo            toggle the window
	/cairn-gui-demo    long form, same effect

Cairn-Gui-Demo-2.0/Core (c) 2026 ChronicTinkerer. MIT license.
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

local Gui     = requireLib("Cairn-Gui-2.0")
local Std     = requireLib("Cairn-Gui-Widgets-Standard-2.0")
local Theme   = requireLib("Cairn-Gui-Theme-Default-2.0")  -- noqa: side-effect register

-- Optional bundles. Not all installs ship them; the Demo gracefully
-- degrades the corresponding tab to a "this bundle isn't loaded" notice.
local Secure  = LibStub("Cairn-Gui-Widgets-Secure-2.0", true)
local Extra   = LibStub("Cairn-Gui-Layouts-Extra-2.0",  true)

-- ----- Demo namespace ---------------------------------------------------

local Demo = {}
_G.CairnGuiDemo = Demo

Demo.lib       = Gui
Demo.standard  = Std
Demo.theme     = Theme
Demo.secure    = Secure  -- nil if bundle absent
Demo.extra     = Extra   -- nil if bundle absent

-- Tab registry. {id -> def} plus a sorted order list maintained as tabs
-- register. Each Tabs/*.lua file calls Demo:RegisterTab(id, def) at file
-- scope load so by the time Show() runs every tab is known.
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
	def.id     = id
	def.label  = def.label or id
	def.order  = def.order or 100
	if def.build and type(def.build) ~= "function" then
		error("RegisterTab: def.build must be a function or nil", 2)
	end
	self._tabs[id] = def
	-- Insert into order list, sorted by .order ascending (stable on ties
	-- via secondary sort by label).
	table.insert(self._tabOrder, def)
	table.sort(self._tabOrder, function(a, b)
		if a.order == b.order then return a.label < b.label end
		return a.order < b.order
	end)
end

-- ----- Window construction ----------------------------------------------

-- 1240 chosen so all 14 tab buttons fit in the horizontal strip without
-- clipping. TabGroup v1 has no scroll affordance for overflowing tabs;
-- measured tab widths run ~70-100px each (intrinsic size = label width
-- + 16px padding) so 14 labels + gaps total ~1180px. 1240 leaves a
-- comfortable buffer for font / locale variation. (Earlier attempts at
-- 920 and 1100 both fell short.)
local WINDOW_W = 1240
local WINDOW_H = 600

local function buildWindow(self)
	if self._win then return self._win end

	-- Window default strata is HIGH (Cairn-Gui-Widgets-Standard-2.0
	-- MINOR 3+), so DIALOG-strata popups (Dropdown's option list,
	-- secondary Windows) layer above us automatically. No explicit
	-- strata override needed; this Acquire takes the new default.
	local win = Gui:Acquire("Window", UIParent, {
		title  = "Cairn-Gui-2.0 Demo",
		width  = WINDOW_W,
		height = WINDOW_H,
	})
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

	-- Build the TabGroup inside Window content. Each registered tab
	-- becomes a TabGroup tab whose content is built lazily on first view.
	local content = win.Cairn:GetContent()
	content.Cairn:SetLayoutManual(true)

	-- Convert the tab registry into TabGroup's expected {id,label} array.
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

	-- Lazy build hook. When the user switches to a tab for the first
	-- time, run its def.build into the tab's content pane.
	local function ensureBuilt(tabId)
		if self._tabBuilt[tabId] then return end
		local def = self._tabs[tabId]
		if not def or not def.build then
			-- Mark built so we don't retry; an empty tab is fine for stubs.
			self._tabBuilt[tabId] = true
			return
		end
		local pane = tg.Cairn:GetTabContent(tabId)
		if not pane then return end
		local ok, err = pcall(def.build, pane, self)
		if not ok and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage(
				("|cffff5050[CairnGuiDemo] tab %q build error:|r %s")
				:format(tostring(tabId), tostring(err)))
		end
		self._tabBuilt[tabId] = true
	end

	tg.Cairn:On("Changed", function(_, tabId)
		ensureBuilt(tabId)
	end)

	-- Build the initially selected tab right away so the user sees content
	-- on first open, not an empty pane.
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

-- ----- Helper utilities exposed to tabs ---------------------------------
-- Most tabs need: a top heading, a "live" panel on the left, and a code
-- panel on the right. Centralizing the helper means the tabs all look
-- consistent and adding a tab is fast.

-- Build the standard 2-panel tab layout: heading on top, then a live
-- demo pane (left, 55%) and a code pane (right, 45%) side by side.
-- Returns (headingLabel, livePane, codeLabel) where livePane is a
-- Cairn Container the tab can populate freely and codeLabel is a Label
-- with monospace-ish font ready to display the snippet.
function Demo:BuildTabShell(pane, headingText, codeText)
	pane.Cairn:SetLayoutManual(true)

	-- Heading anchored to the top of the pane.
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

	-- Live panel: left 55% of the remaining space. Bordered Container so
	-- the boundary is obvious.
	local live = Gui:Acquire("Container", pane, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	live.Cairn:SetLayoutManual(true)
	live:ClearAllPoints()
	live:SetPoint("TOPLEFT",     pane, "TOPLEFT",     12, -38)
	live:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT",  12 + math.floor(WINDOW_W * 0.50), 12)

	-- Code panel: right side, starts where live ends with a small gutter.
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

	-- Re-resize codeContent to fit the (multi-line, wrapped) string so
	-- the ScrollFrame's content area is tall enough to scroll.
	local _, ih = codeLabel.Cairn:GetIntrinsicSize()
	if ih and ih > 0 then
		codeBox.Cairn:SetContentHeight(ih + 24)
		codeLabel:SetHeight(ih + 4)
	end

	return heading, live, codeLabel
end

-- Make a tab's live pane scrollable. Inserts a ScrollFrame filling the
-- whole live area and returns the ScrollFrame's content Container, which
-- the tab should use as its new "live" parent. The tab is responsible
-- for setting a layout strategy on the returned container.
--
-- Use this for any tab whose content can grow taller than ~510px (the
-- live pane's effective vertical space inside the demo window). Tabs
-- with short, fixed content can stick with the plain Container `live`.
--
-- IMPORTANT: ScrollFrame's mixin sizes its scroll-child Container at
-- Acquire time using opts.width / opts.height. If we let it default to
-- 300x200 and only SetPoint the OUTER frame to fill `live` afterward,
-- the inner content stays 292px wide and children added to it anchor
-- against a 292px frame -- visually they'd land in the left strip and
-- look mis-laid-out (or, with Stack vertical that uses TOPLEFT/TOPRIGHT
-- of the content frame, render at the wrong width). We pass live's
-- known dimensions explicitly so the content sizes to match.
function Demo:MakeScrollable(live, contentHeight)
	-- live was already SetPoint'd to fill its half of the pane in
	-- BuildTabShell; its width/height are valid by the time a tab's
	-- build() runs (TabGroup pane is laid out before tab builds fire).
	local lw = math.floor(live:GetWidth()  or 0)
	local lh = math.floor(live:GetHeight() or 0)
	if lw <= 1 or lh <= 1 then
		-- Defensive fallback: if for some reason live hasn't resolved
		-- its size yet, ScrollFrame's defaults (300x200) ship anyway,
		-- and the SetPoint below corrects the OUTER frame after Acquire.
		lw = lw > 1 and lw or 460
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
	-- Stash the ScrollFrame on the content so consumers can adjust the
	-- contentHeight later (e.g., after measuring the populated content).
	content._scrollFrame = sf
	return content
end

-- Convenience: a single-paragraph helper text under the heading inside the
-- live pane, useful for intro lines on each tab.
function Demo:AppendIntro(livePane, text)
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

-- ----- Slash command ----------------------------------------------------

SLASH_CAIRNGUIDEMO1 = "/cgdemo"
SLASH_CAIRNGUIDEMO2 = "/cairn-gui-demo"
SlashCmdList.CAIRNGUIDEMO = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""
	if msg == "show" then
		Demo:Show()
	elseif msg == "hide" then
		Demo:Hide()
	else
		Demo:Toggle()
	end
end

-- ----- Boot log ---------------------------------------------------------
-- One Info-level chat line so the user can confirm the addon loaded.
-- Gated on Cairn-Log so a stripped-down install isn't noisy.
local Log = LibStub("Cairn-Log-1.0", true)
if Log then
	local logger = Log("CairnGuiDemo")
	if logger and logger.Info then
		local _, libMinor = Gui:GetVersion()
		logger:Info("loaded; Cairn-Gui-2.0 MINOR=%d. Type /cgdemo to open.", libMinor)
	end
end
