--[[
Cairn-LogWindow-1.0

Movable, resizable viewer for Cairn.Log. Subscribes to new entries and
maintains a scrolling list, with filters for source and minimum level and
a substring search.

Public API:

	Cairn.LogWindow:Toggle()         -- show or hide
	Cairn.LogWindow:Show()
	Cairn.LogWindow:Hide()
	Cairn.LogWindow:IsShown()
	Cairn.LogWindow:SetSourceFilter(name | nil)
	Cairn.LogWindow:SetMinLevel(name)   -- "TRACE","DEBUG","INFO","WARN","ERROR"
	Cairn.LogWindow:SetSearch(str | nil)
	Cairn.LogWindow:Refresh()           -- rebuild visible rows from buffer

Slash commands (registered by Cairn-Standalone-1.0):
	/cairn log              toggle window
	/cairn log clear        clear buffer
	/cairn log level <lvl>  set window minimum level + global level
	/cairn log source <s>   set source filter (or "all")
	/cairn log search <q>   substring search
	/cairn log echo <lvl>   chat-echo level
	/cairn log stats        show buffer/level summary
]]

-- MINOR history:
--   1  initial: scrollable buffer viewer with filters
--   2  strata HIGH -> DIALOG so the window layers above Cairn-Gui-2.0
--      Window hosts (which default to HIGH since Standard-2.0 MINOR 3).
--      Spotted 2026-05-07 when Cairn-Demo's "Toggle LogWindow" button
--      opened the window successfully but it rendered behind the demo.
local MAJOR, MINOR = "Cairn-LogWindow-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
if not Log then
	error("Cairn-LogWindow-1.0 requires Cairn-Log-1.0 to be loaded first.", 2)
end

local LEVEL_NAMES  = Log.LEVEL_NAMES
local LEVEL_COLORS = Log.LEVEL_COLORS
local LEVELS       = Log.LEVELS

-- Preserve window state across LibStub upgrades.
lib.minLevel     = lib.minLevel     or LEVELS.INFO
lib.sourceFilter = lib.sourceFilter or nil
lib.searchText   = lib.searchText   or nil
lib.maxRows      = lib.maxRows      or 200

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

local function buildFrame()
	if lib.frame then return lib.frame end

	local f = CreateFrame("Frame", "CairnLogWindowFrame", UIParent, "BackdropTemplate")
	f:SetSize(640, 360)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:SetResizable(true)
	-- SetMinResize was deprecated in 10.0 in favor of SetResizeBounds.
	if f.SetResizeBounds then f:SetResizeBounds(360, 200) end
	if f.SetMinResize    then f:SetMinResize(360, 200)    end
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	-- DIALOG so we layer above Cairn-Gui-2.0 Window hosts at HIGH strata.
	-- Bumped from HIGH to DIALOG in MINOR 2 to fix the demo collision.
	f:SetFrameStrata("DIALOG")
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
	end

	local title = CreateFrame("Frame", nil, f)
	title:SetPoint("TOPLEFT", 8, -8)
	title:SetPoint("TOPRIGHT", -8, -8)
	title:SetHeight(20)
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() f:StartMoving() end)
	title:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

	local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT")
	titleText:SetText("Cairn Log")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() lib:Hide() end)

	local resize = CreateFrame("Button", nil, f)
	resize:SetSize(16, 16)
	resize:SetPoint("BOTTOMRIGHT", -4, 4)
	resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resize:SetScript("OnMouseDown", function(self, btn)
		if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
	end)
	resize:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); lib:Refresh() end)

	local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("BOTTOMLEFT", 12, 8)
	status:SetText("")
	lib.statusText = status

	local scroll = CreateFrame("ScrollFrame", "CairnLogWindowScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -36)
	scroll:SetPoint("BOTTOMRIGHT", -28, 24)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local body = content:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetPoint("TOPLEFT", 4, -4)
	body:SetWidth(scroll:GetWidth() - 12)
	body:SetText("")

	f:SetScript("OnSizeChanged", function()
		body:SetWidth(scroll:GetWidth() - 12)
		lib:Refresh()
	end)

	lib.frame   = f
	lib.scroll  = scroll
	lib.content = content
	lib.body    = body

	if not lib._unsubscribe then
		lib._unsubscribe = Log:OnNewEntry(function(entry)
			if lib.frame and lib.frame:IsShown() then lib:Refresh() end
		end, "Cairn-LogWindow")
	end

	return f
end

function lib:Show()
	buildFrame():Show()
	self:Refresh()
end

function lib:Hide()
	if self.frame then self.frame:Hide() end
end

function lib:IsShown()
	if self.frame then return self.frame:IsShown() end
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
	self:Refresh()
end

function lib:SetSearch(str)
	if str == nil or str == "" then
		self.searchText = nil
	else
		self.searchText = str
	end
	self:Refresh()
end

function lib:Refresh()
	if not self.frame or not self.body then return end

	local entries = Log:GetEntries(passesFilter)
	local n = #entries
	local start = math.max(1, n - self.maxRows + 1)
	local lines = {}
	for i = start, n do lines[#lines + 1] = formatEntry(entries[i]) end
	self.body:SetText(table.concat(lines, "\n"))

	local h = self.body:GetStringHeight() + 12
	self.content:SetHeight(h)
	self.content:SetWidth(self.scroll:GetWidth())

	if self.scroll.UpdateScrollChildRect then self.scroll:UpdateScrollChildRect() end
	local maxScroll = math.max(0, h - self.scroll:GetHeight())
	self.scroll:SetVerticalScroll(maxScroll)

	local total = Log:Count()
	local filtered = n
	local srcDesc = self.sourceFilter and ("  |  source=" .. self.sourceFilter) or ""
	local searchDesc = self.searchText and ("  |  search=" .. self.searchText) or ""
	local filterDesc = string.format(
		"showing %d of %d  |  level >=%s%s%s",
		filtered, total, LEVEL_NAMES[self.minLevel] or "?", srcDesc, searchDesc
	)
	if self.statusText then self.statusText:SetText(filterDesc) end
end
