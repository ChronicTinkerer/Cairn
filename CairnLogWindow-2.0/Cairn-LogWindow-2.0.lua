--[[
Cairn-LogWindow-2.0

Movable viewer for Cairn-Log, rebuilt on Cairn-Gui-2.0 widgets. Drop-in
successor to Cairn-LogWindow-1.0 with the same public API plus inline
filter controls (level dropdown, source dropdown, search field, clear
button) so the filters are discoverable without slash commands.

Public API (matches v1):

    Cairn.LogWindow:Toggle()          -- show or hide
    Cairn.LogWindow:Show()
    Cairn.LogWindow:Hide()
    Cairn.LogWindow:IsShown()
    Cairn.LogWindow:SetSourceFilter(name | "all" | nil)
    Cairn.LogWindow:SetMinLevel(name) -- "TRACE","DEBUG","INFO","WARN","ERROR"
    Cairn.LogWindow:SetSearch(str | nil)
    Cairn.LogWindow:Refresh()         -- rebuild visible rows from buffer

Slash commands (registered by Cairn-Standalone-1.0):
    /cairn log              toggle window
    /cairn log clear        clear buffer
    /cairn log level <lvl>  set window minimum level + global level
    /cairn log source <s>   set source filter (or "all")
    /cairn log search <q>   substring search
    /cairn log echo <lvl>   chat-echo level
    /cairn log stats        show buffer/level summary

Why this exists: Cairn-LogWindow-1.0 uses raw CreateFrame + Blizzard
templates. Cairn's v2-only strategy (memory: cairn_v2_only_strategy)
calls for every UI surface to live on Cairn-Gui-2.0. This is the final
v1 conversion before the v1 family extracts to Diesal-Continued.

Strata: explicit DIALOG. v2 Window default is HIGH (so popups owned by
a Window's interior layer above it). The LogWindow IS itself a popup-
style debug surface that should layer above any consumer Window, so
DIALOG matches v1 MINOR 2's fix and the SettingsPanel-2.0 precedent.

Known gaps vs v1:
    * No drag-to-resize handle. v2 Window doesn't ship a resize affordance
      (per Window.lua header status note). Window comes up at a fixed
      720x420 and can be SetSize'd by consumers if they really need to.

Cairn-LogWindow-2.0 (c) 2026 ChronicTinkerer. MIT license.
]]

-- MINOR history:
--   1  initial v2 build: Window + Toolbar (Level/Source Dropdowns + Search
--      EditBox + Clear Button) + ScrollFrame body (single multiline Label
--      rendered as concatenated entries) + status footer Label. Same
--      public API as v1; auto-installs as Cairn.LogWindow when the
--      umbrella facade is present.
local MAJOR, MINOR = "Cairn-LogWindow-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
if not Log then
	error("Cairn-LogWindow-2.0 requires Cairn-Log-1.0 to be loaded first.", 2)
end

local Gui = LibStub("Cairn-Gui-2.0", true)
if not Gui then
	error("Cairn-LogWindow-2.0 requires Cairn-Gui-2.0 to be loaded first.", 2)
end

local Std = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Std then
	error("Cairn-LogWindow-2.0 requires Cairn-Gui-Widgets-Standard-2.0 to be loaded first.", 2)
end

local LEVEL_NAMES  = Log.LEVEL_NAMES
local LEVEL_COLORS = Log.LEVEL_COLORS
local LEVELS       = Log.LEVELS

-- Preserve window state across LibStub upgrades.
lib.minLevel     = lib.minLevel     or LEVELS.INFO
lib.sourceFilter = lib.sourceFilter or nil
lib.searchText   = lib.searchText   or nil
lib.maxRows      = lib.maxRows      or 200

-- ----- Layout constants -------------------------------------------------

local WIN_W       = 720
local WIN_H       = 420
local PAD         = 10
local TOOLBAR_H   = 28
local STATUS_H    = 18
local DD_LEVEL_W  = 110
local DD_SOURCE_W = 160
local SEARCH_W    = 220
local CLEAR_W     = 70

-- ----- Helpers ----------------------------------------------------------

local function passesFilter(entry)
	if entry.level > lib.minLevel then return false end
	if lib.sourceFilter and entry.source ~= lib.sourceFilter then return false end
	if lib.searchText and lib.searchText ~= "" then
		if not entry.message:lower():find(lib.searchText:lower(), 1, true) then
			return false
		end
	end
	return true
end

local function formatEntry(entry)
	-- LEVEL_COLORS values are 8-hex AARRGGBB strings (FF prefix). Use the
	-- `|c` + 8-hex form to avoid the leak documented in
	-- memory:wow_color_escape_format.
	local color = LEVEL_COLORS[entry.level] or "FFFFFFFF"
	local levelTag = LEVEL_NAMES[entry.level] or "?"
	local timeStr = "?"
	if entry.ts and date then
		timeStr = date("%H:%M:%S", entry.ts)
	end
	return string.format(
		"|cFF888888%s|r |c%s[%s %s]|r %s",
		timeStr, color, entry.source or "?", levelTag, entry.message or ""
	)
end

-- Snapshot of currently-known sources, sorted alphabetically. Used to
-- populate the source-filter Dropdown each time the window opens. Live
-- regeneration on every refresh is overkill (sources don't churn), so we
-- only refresh the list on Show or when an unknown source appears.
local function collectSources()
	local set, list = {}, {}
	if Log.loggers then
		for src in pairs(Log.loggers) do
			if not set[src] then set[src] = true; list[#list + 1] = src end
		end
	end
	-- Also seed from the live buffer in case a source has logged but isn't
	-- a registered logger (rare, but cheap to cover).
	for _, e in ipairs(Log:GetEntries()) do
		local s = e.source
		if s and not set[s] then set[s] = true; list[#list + 1] = s end
	end
	table.sort(list)
	local out = { { value = "__all__", label = "all" } }
	for _, s in ipairs(list) do out[#out + 1] = { value = s, label = s } end
	return out
end

-- ----- Frame construction -----------------------------------------------

local function buildFrame()
	if lib.win then return lib.win end

	local win = Gui:Acquire("Window", UIParent, {
		title    = "Cairn Log",
		width    = WIN_W,
		height   = WIN_H,
		strata   = "DIALOG",
		closable = true,
		movable  = true,
	})
	win:ClearAllPoints()
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	local content = win.Cairn:GetContent()
	content.Cairn:SetLayoutManual(true)

	-- ----- Toolbar (top) -------------------------------------------------
	-- Manual layout so each control gets its own pixel-precise placement;
	-- a Stack-horizontal would also work but a Dropdown popup that anchors
	-- to its header doesn't love being repositioned mid-relayout.
	local toolbar = Gui:Acquire("Container", content, {})
	toolbar.Cairn:SetLayoutManual(true)
	toolbar:ClearAllPoints()
	toolbar:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, -PAD)
	toolbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, -PAD)
	toolbar:SetHeight(TOOLBAR_H)

	-- Level Dropdown.
	local levelOpts = {
		{ value = LEVELS.ERROR, label = "ERROR" },
		{ value = LEVELS.WARN,  label = "WARN"  },
		{ value = LEVELS.INFO,  label = "INFO"  },
		{ value = LEVELS.DEBUG, label = "DEBUG" },
		{ value = LEVELS.TRACE, label = "TRACE" },
	}
	local lvlLbl = Gui:Acquire("Label", toolbar, {
		text = "Level:", variant = "muted", align = "left", wrap = false,
	})
	lvlLbl.Cairn:SetLayoutManual(true)
	lvlLbl:ClearAllPoints()
	lvlLbl:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
	lvlLbl:SetSize(40, TOOLBAR_H)

	local lvlDD = Gui:Acquire("Dropdown", toolbar, {
		options  = levelOpts,
		selected = lib.minLevel,
		width    = DD_LEVEL_W,
	})
	lvlDD.Cairn:SetLayoutManual(true)
	lvlDD:ClearAllPoints()
	lvlDD:SetPoint("LEFT", lvlLbl, "RIGHT", 4, 0)
	lvlDD:SetSize(DD_LEVEL_W, 24)
	lvlDD.Cairn:On("Changed", function(_, value)
		-- Dropdown returns the value as set in opts (a number from LEVELS).
		if type(value) == "number" then
			lib.minLevel = value
			lib:Refresh()
		end
	end)

	-- Source Dropdown.
	local srcLbl = Gui:Acquire("Label", toolbar, {
		text = "Source:", variant = "muted", align = "left", wrap = false,
	})
	srcLbl.Cairn:SetLayoutManual(true)
	srcLbl:ClearAllPoints()
	srcLbl:SetPoint("LEFT", lvlDD, "RIGHT", 12, 0)
	srcLbl:SetSize(48, TOOLBAR_H)

	local srcDD = Gui:Acquire("Dropdown", toolbar, {
		options  = collectSources(),
		selected = lib.sourceFilter or "__all__",
		width    = DD_SOURCE_W,
	})
	srcDD.Cairn:SetLayoutManual(true)
	srcDD:ClearAllPoints()
	srcDD:SetPoint("LEFT", srcLbl, "RIGHT", 4, 0)
	srcDD:SetSize(DD_SOURCE_W, 24)
	srcDD.Cairn:On("Changed", function(_, value)
		lib.sourceFilter = (value == "__all__") and nil or value
		lib:Refresh()
	end)

	-- Search EditBox.
	local searchLbl = Gui:Acquire("Label", toolbar, {
		text = "Search:", variant = "muted", align = "left", wrap = false,
	})
	searchLbl.Cairn:SetLayoutManual(true)
	searchLbl:ClearAllPoints()
	searchLbl:SetPoint("LEFT", srcDD, "RIGHT", 12, 0)
	searchLbl:SetSize(50, TOOLBAR_H)

	local searchEB = Gui:Acquire("EditBox", toolbar, {
		text        = lib.searchText or "",
		placeholder = "substring filter",
		width       = SEARCH_W,
		height      = 24,
	})
	searchEB.Cairn:SetLayoutManual(true)
	searchEB:ClearAllPoints()
	searchEB:SetPoint("LEFT", searchLbl, "RIGHT", 4, 0)
	searchEB:SetSize(SEARCH_W, 24)
	searchEB.Cairn:On("TextChanged", function(_, text)
		lib.searchText = (text ~= "" and text) or nil
		lib:Refresh()
	end)

	-- Clear Button (clears the LOG BUFFER, not the search field; matches
	-- "/cairn log clear" semantics. The search field is cleared by typing
	-- backspace or pressing Escape, which is the standard EditBox idiom).
	local clearBtn = Gui:Acquire("Button", toolbar, {
		text    = "Clear",
		variant = "default",
	})
	clearBtn.Cairn:SetLayoutManual(true)
	clearBtn:ClearAllPoints()
	clearBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
	clearBtn:SetSize(CLEAR_W, 24)
	clearBtn.Cairn:On("Click", function()
		Log:Clear()
		lib:Refresh()
	end)

	-- ----- ScrollFrame body (middle) ------------------------------------
	local sf = Gui:Acquire("ScrollFrame", content, {
		bg            = "color.bg.surface",
		border        = "color.border.subtle",
		borderWidth   = 1,
		showScrollbar = true,
		contentHeight = 200,
	})
	sf.Cairn:SetLayoutManual(true)
	sf:ClearAllPoints()
	sf:SetPoint("TOPLEFT",     toolbar, "BOTTOMLEFT",  0, -6)
	sf:SetPoint("TOPRIGHT",    toolbar, "BOTTOMRIGHT", 0, -6)
	sf:SetPoint("BOTTOMLEFT",  content, "BOTTOMLEFT",  PAD, PAD + STATUS_H + 2)
	sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, PAD + STATUS_H + 2)

	local scrollContent = sf.Cairn:GetContent()
	scrollContent.Cairn:SetLayoutManual(true)

	-- The body is a single wrapping Label. Cairn-Gui-2.0 Label uses a
	-- FontString underneath, so it accepts WoW color escapes natively.
	-- Width is bound to the scroll content width via the ScrollFrame's
	-- outer-resize hook (memory:cairn_gui_2_framework_gaps - ScrollFrame
	-- MINOR 3+ keeps content width in sync with viewport).
	local body = Gui:Acquire("Label", scrollContent, {
		text    = "",
		variant = "body",
		align   = "left",
		wrap    = true,
	})
	body.Cairn:SetLayoutManual(true)
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT",  scrollContent, "TOPLEFT",  4, -4)
	body:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -4, -4)
	body:SetHeight(20)  -- placeholder; set from string height each Refresh

	-- ----- Status footer (bottom) ---------------------------------------
	local status = Gui:Acquire("Label", content, {
		text    = "",
		variant = "small",
		align   = "left",
		wrap    = false,
	})
	status.Cairn:SetLayoutManual(true)
	status:ClearAllPoints()
	status:SetPoint("BOTTOMLEFT",  content, "BOTTOMLEFT",  PAD, PAD)
	status:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, PAD)
	status:SetHeight(STATUS_H)

	-- ----- Stash refs ---------------------------------------------------
	lib.win        = win
	lib.toolbar    = toolbar
	lib.lvlDD      = lvlDD
	lib.srcDD      = srcDD
	lib.searchEB   = searchEB
	lib.scrollFrame = sf
	lib.scrollContent = scrollContent
	lib.body       = body
	lib.status     = status

	-- ----- Subscribe to new log entries ---------------------------------
	if not lib._unsubscribe then
		lib._unsubscribe = Log:OnNewEntry(function(entry)
			if lib.win and lib.win:IsShown() then
				-- New source might have arrived; refresh source dropdown
				-- only if the entry's source isn't in our current options.
				local s = entry and entry.source
				if s and lib.srcDD then
					local opts = collectSources()
					local known = false
					for _, o in ipairs(opts) do
						if o.value == s then known = true; break end
					end
					if not known then
						lib.srcDD.Cairn:SetOptions(opts)
					end
				end
				lib:Refresh()
			end
		end, "Cairn-LogWindow-2.0")
	end

	return win
end

-- ----- Public API -------------------------------------------------------

function lib:Show()
	local win = buildFrame()
	-- Refresh the source Dropdown each Show in case loggers came online
	-- between sessions of the window.
	if self.srcDD then
		self.srcDD.Cairn:SetOptions(collectSources())
		self.srcDD.Cairn:SetSelected(self.sourceFilter or "__all__")
	end
	if self.lvlDD then
		self.lvlDD.Cairn:SetSelected(self.minLevel)
	end
	if self.searchEB then
		self.searchEB.Cairn:SetText(self.searchText or "")
	end
	win:Show()
	self:Refresh()
end

function lib:Hide()
	if self.win then self.win:Hide() end
end

function lib:IsShown()
	if self.win then return self.win:IsShown() end
	return false
end

function lib:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function lib:SetSourceFilter(source)
	if source == nil or source == "all" or source == "" then
		self.sourceFilter = nil
	else
		self.sourceFilter = source
	end
	if self.srcDD then
		self.srcDD.Cairn:SetSelected(self.sourceFilter or "__all__")
	end
	self:Refresh()
end

function lib:SetMinLevel(level)
	local n
	if type(level) == "number" then
		n = level
	else
		n = LEVELS[tostring(level):upper()]
	end
	if not n then
		error("Cairn.LogWindow:SetMinLevel: unknown level " .. tostring(level), 2)
	end
	self.minLevel = n
	if self.lvlDD then
		self.lvlDD.Cairn:SetSelected(n)
	end
	self:Refresh()
end

function lib:SetSearch(str)
	if str == nil or str == "" then
		self.searchText = nil
	else
		self.searchText = str
	end
	if self.searchEB then
		self.searchEB.Cairn:SetText(self.searchText or "")
	end
	self:Refresh()
end

function lib:Refresh()
	if not self.win or not self.body then return end

	local entries = Log:GetEntries(passesFilter)
	local n = #entries
	local startIdx = math.max(1, n - self.maxRows + 1)
	local lines = {}
	for i = startIdx, n do lines[#lines + 1] = formatEntry(entries[i]) end
	local text = table.concat(lines, "\n")
	self.body.Cairn:SetText(text)

	-- Body height comes from the rendered string height. Use Label's
	-- public GetIntrinsicSize mixin (returns w, h from the underlying
	-- FontString); falls back to the frame's height if the mixin shape
	-- ever changes.
	local h
	if self.body.Cairn and self.body.Cairn.GetIntrinsicSize then
		local _, sh = self.body.Cairn:GetIntrinsicSize()
		h = (sh or 0) + 8
	else
		h = self.body:GetHeight() + 8
	end
	if h < 20 then h = 20 end
	self.body:SetHeight(h)
	self.scrollFrame.Cairn:SetContentHeight(h)
	self.scrollFrame.Cairn:ScrollToBottom()

	-- Status footer text: filter summary + counts.
	local total = Log:Count()
	local srcDesc = self.sourceFilter and ("  |  source=" .. self.sourceFilter) or ""
	local searchDesc = self.searchText and ("  |  search=" .. self.searchText) or ""
	local filterDesc = string.format(
		"showing %d of %d  |  level >=%s%s%s",
		n, total, LEVEL_NAMES[self.minLevel] or "?", srcDesc, searchDesc
	)
	self.status.Cairn:SetText(filterDesc)
end

-- ----- Umbrella facade install -----------------------------------------
-- Cairn umbrella's __index hardcodes the "-1.0" suffix, so Cairn.LogWindow
-- would otherwise resolve to the v1 lib forever once cached. Install
-- ourselves directly via rawset so subsequent Cairn.LogWindow accesses
-- return v2. Ordering is safe: this file loads after Cairn.lua and after
-- Cairn-LogWindow-1.0, so any consumer that hasn't called Cairn.LogWindow
-- yet (the standard case at file-scope load) will see v2.
if _G.Cairn then
	rawset(_G.Cairn, "LogWindow", lib)
end
