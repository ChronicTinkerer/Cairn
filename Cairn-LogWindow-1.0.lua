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

Slash command (registered by the standalone Cairn addon):
	/cairn log              toggle window
	/cairn log clear        clear buffer
	/cairn log level <lvl>  set window minimum level
	/cairn log source <s>   set source filter (or "all")
]]

local MAJOR, MINOR = "Cairn-LogWindow-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
if not Log then
	-- Cairn.Log is required.
	error("Cairn-LogWindow-1.0 requires Cairn-Log-1.0 to be loaded first.", 2)
end

local LEVEL_NAMES  = Log.LEVEL_NAMES
local LEVEL_COLORS = Log.LEVEL_COLORS
local LEVELS       = Log.LEVELS

-- Preserve window state across LibStub upgrades.
lib.minLevel     = lib.minLevel     or LEVELS.INFO
lib.sourceFilter = lib.sourceFilter or nil   -- nil = all
lib.searchText   = lib.searchText   or nil
lib.maxRows      = lib.maxRows      or 200   -- visible rows cap

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

-- Format an entry for the row text.
local function formatEntry(entry)
	local color  = LEVEL_COLORS[entry.level] or "FFFFFFFF"
	local levelTag = LEVEL_NAMES[entry.level] or "?"
	local timeStr  = "?"
	if entry.ts and date then
		timeStr = date("%H:%M:%S", entry.ts)
	end
	return string.format(
		"|cFF888888%s|r |c%s[%s %s]|r %s",
		timeStr, color, entry.source or "?", levelTag, entry.message or ""
	)
end

-- ----- Frame construction (lazy, on first Show) --------------------------

local function buildFrame()
	if lib.frame then return lib.frame end

	local f = CreateFrame("Frame", "CairnLogWindowFrame", UIParent, "BackdropTemplate")
	f:SetSize(640, 360)
	f:SetPoint("CENTER")
	f:SetMovable(true); f:SetResizable(true)
	f:SetMinResize and f:SetMinResize(360, 200)
	f:SetResizeBounds and f:SetResizeBounds(360, 200)  -- 10.0+ replacement
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetFrameStrata("HIGH")
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
	end

	-- Title bar (drag handle).
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

	-- Resize grip (bottom-right).
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

	-- Status bar (counts).
	local status = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	status:SetPoint("BOTTOMLEFT", 12, 8)
	status:SetText("")
	lib.statusText = status

	-- ScrollFrame for messages.
	local scroll = CreateFrame("ScrollFrame", "CairnLogWindowScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -36)
	scroll:SetPoint("BOTTOMRIGHT", -28, 24)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local body = content:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
	body:SetPoint("TOPLEFT", 4, -4)
	body:SetWidth(scroll:GetWidth() - 12)
	body:SetText("")

	-- Reflow body width when frame resizes.
	f:SetScript("OnSizeChanged", function()
		body:SetWidth(scroll:GetWidth() - 12)
		lib:Refresh()
	end)

	lib.frame   = f
	lib.scroll  = scroll
	lib.content = content
	lib.body    = body

	-- Subscribe to new entries while window exists.
	if not lib._unsubscribe then
		lib._unsubscribe = Log:OnNewEntry(function(entry)
			if lib.frame and lib.frame:IsShown() then lib:Refresh() end
		end, "Cairn-LogWindow")
	end

	return f
end

-- ----- Public methods ----------------------------------------------------

function lib:Show()
	buildFrame():Show()
	self:Refresh()
end

function lib:Hide()
	if self.frame then self.frame:Hide() end
end

function lib:IsShown()
	return self.frame and self.frame:IsShown() or false
end

function lib:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

function lib:SetSourceFilter(source)
	self.sourceFilter = (source == nil or source == "all" or source == "") and nil or source
	self:Refresh()
end

function lib:SetMinLevel(level)
	local n = (type(level) == "number") and level or LEVELS[tostring(level):upper()]
	if not n then error("Cairn.LogWindow:SetMinLevel: unknown level " .. tostring(level), 2) end
	self.minLevel = n
	self:Refresh()
end

function lib:SetSearch(str)
	self.searchText = (str == nil or str == "") and nil or str
	self:Refresh()
end

function lib:Refresh()
	if not self.frame or not self.body then return end

	local entries = Log:GetEntries(passesFilter)
	local n = #entries
	-- Cap to maxRows by keeping the most recent.
	local start = math.max(1, n - self.maxRows + 1)
	local lines = {}
	for i = start, n do lines[#lines + 1] = formatEntry(entries[i]) end
	self.body:SetText(table.concat(lines, "\n"))

	-- Resize content to body so scrollbar maths work.
	local h = self.body:GetStringHeight() + 12
	self.content:SetHeight(h)
	self.content:SetWidth(self.scroll:GetWidth())

	-- Scroll to bottom (newest).
	if self.scroll.UpdateScrollChildRect then self.scroll:UpdateScrollChildRect() end
	local maxScroll = math.max(0, h - self.scroll:GetHeight())
	self.scroll:SetVerticalScroll(maxScroll)

	-- Status line.
	local total = Log:Count()
	local filtered = n
	local filterDesc = string.format(
		"showing %d of %d  |  level >=%s%s%s",
		filtered, total, LEVEL_NAMES[self.minLevel] or "?",
		self.sourceFilter and ("  |  source=" .. self.sourceFilter) or "",
		self.searchText and ("  |  search=" .. self.searchText) or ""
	)
	if self.statusText then self.statusText:SetText(filterDesc) end
end
