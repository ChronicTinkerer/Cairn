--[[
Cairn-Dashboard-1.0

Developer dashboard. Lists every "source" Cairn knows about (any addon
that has registered a logger, lifecycle, or slash router) and lets you
inspect logs and metadata per source.

Open via /cairn dash (also /cairn dashboard, /cairn dev).

Layout:
	+-----------+--------------------------+
	| Sources   |  [Logs]  [Info]          |
	|  All      |                          |
	|  Cairn    |  (selected tab content)  |
	|  CairnTest|                          |
	|  ...      |                          |
	+-----------+--------------------------+

Public API:
	Cairn.Dashboard:Show()
	Cairn.Dashboard:Hide()
	Cairn.Dashboard:Toggle()
	Cairn.Dashboard:IsShown()
	Cairn.Dashboard:SelectSource(name)
	Cairn.Dashboard:Refresh()
	Cairn.Dashboard:GetSources()
	Cairn.Dashboard.FormatLogsForCopy(sourceName, entries)
]]

local MAJOR, MINOR = "Cairn-Dashboard-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
if not Log then
	error("Cairn-Dashboard-1.0 requires Cairn-Log-1.0 to be loaded first.", 2)
end
local Events  = LibStub("Cairn-Events-1.0", true)
local Addon   = LibStub("Cairn-Addon-1.0",  true)
local Slash   = LibStub("Cairn-Slash-1.0",  true)

local LEVEL_NAMES  = Log.LEVEL_NAMES
local LEVEL_COLORS = Log.LEVEL_COLORS
local LEVELS       = Log.LEVELS

lib.selectedSource = lib.selectedSource or "All"
lib.minLevel       = lib.minLevel       or LEVELS.TRACE
lib.searchText     = lib.searchText     or nil
lib.maxRows        = lib.maxRows        or 500

-- ----- Source discovery --------------------------------------------------

function lib:GetSources()
	local seen = { ["All"] = true }
	local out  = { "All" }

	for name in pairs(Log.loggers or {}) do
		if not seen[name] then seen[name] = true; out[#out + 1] = name end
	end
	if Addon and Addon.registry then
		for name in pairs(Addon.registry) do
			if not seen[name] then seen[name] = true; out[#out + 1] = name end
		end
	end
	if Slash and Slash.registry then
		for name in pairs(Slash.registry) do
			if not seen[name] then seen[name] = true; out[#out + 1] = name end
		end
	end

	table.sort(out, function(a, b)
		if a == "All" then return true end
		if b == "All" then return false end
		return a < b
	end)
	return out
end

-- ----- Filter helpers ----------------------------------------------------

local function entryMatches(entry, sourceName, minLevel, search)
	if entry.level > minLevel then return false end
	if sourceName ~= "All" and entry.source ~= sourceName then return false end
	if search and search ~= "" then
		if not entry.message:lower():find(search:lower(), 1, true) then return false end
	end
	return true
end

local function formatLine(entry)
	local color = LEVEL_COLORS[entry.level] or "FFFFFFFF"
	local lvl   = LEVEL_NAMES[entry.level] or "?"
	local timeStr = "?"
	if entry.ts and date then timeStr = date("%H:%M:%S", entry.ts) end
	return string.format(
		"|cFF888888%s|r |c%s[%s %s]|r %s",
		timeStr, color, entry.source or "?", lvl, entry.message or ""
	)
end

local function formatPlainLine(entry)
	local lvl     = LEVEL_NAMES[entry.level] or "?"
	local timeStr = "?"
	if entry.ts and date then timeStr = date("%Y-%m-%d %H:%M:%S", entry.ts) end
	return string.format("[%s] [%s %s] %s",
		timeStr, entry.source or "?", lvl, entry.message or "")
end

function lib.FormatLogsForCopy(sourceName, entries)
	local hdr = string.format("=== Cairn log dump (source: %s, %d entries) ===",
		sourceName or "?", #entries)
	local lines = { hdr, "" }
	for i = 1, #entries do lines[#lines + 1] = formatPlainLine(entries[i]) end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "=== end ==="
	return table.concat(lines, "\n")
end

-- ----- Frame construction (lazy) ----------------------------------------

local function buildFrame()
	if lib.frame then return lib.frame end

	local f = CreateFrame("Frame", "CairnDashboardFrame", UIParent, "BackdropTemplate")
	f:SetSize(820, 480)
	f:SetPoint("CENTER")
	f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true)
	f:SetClampedToScreen(true); f:SetFrameStrata("HIGH")
	if f.SetResizeBounds then f:SetResizeBounds(540, 320) end
	if f.SetMinResize    then f:SetMinResize(540, 320)    end
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
	end

	local title = CreateFrame("Frame", nil, f)
	title:SetPoint("TOPLEFT", 8, -8); title:SetPoint("TOPRIGHT", -8, -8); title:SetHeight(20)
	title:EnableMouse(true); title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function() f:StartMoving() end)
	title:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
	local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT"); titleText:SetText("Cairn Dashboard")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() lib:Hide() end)

	local resize = CreateFrame("Button", nil, f)
	resize:SetSize(16, 16); resize:SetPoint("BOTTOMRIGHT", -4, 4)
	resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resize:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
	resize:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); lib:Refresh() end)

	-- ----- Left pane: source list -----
	local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
	left:SetPoint("TOPLEFT", 12, -32); left:SetPoint("BOTTOMLEFT", 12, 24)
	left:SetWidth(180)
	if left.SetBackdrop then
		left:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		left:SetBackdropColor(0, 0, 0, 0.4)
	end

	local leftScroll = CreateFrame("ScrollFrame", "CairnDashboardSourceScroll", left, "UIPanelScrollFrameTemplate")
	leftScroll:SetPoint("TOPLEFT", 6, -6); leftScroll:SetPoint("BOTTOMRIGHT", -22, 6)
	local leftContent = CreateFrame("Frame", nil, leftScroll)
	leftContent:SetSize(160, 1)
	leftScroll:SetScrollChild(leftContent)
	lib.leftScroll  = leftScroll
	lib.leftContent = leftContent
	lib.sourceButtons = {}

	-- ----- Right pane: tabs + content -----
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	right:SetPoint("BOTTOMRIGHT", -12, 24)

	local function makeTab(label, x)
		local b = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
		b:SetSize(80, 22); b:SetPoint("TOPLEFT", x, 0); b:SetText(label)
		return b
	end
	local logsTabBtn = makeTab("Logs", 0)
	local infoTabBtn = makeTab("Info", 84)

	local tabBody = CreateFrame("Frame", nil, right, "BackdropTemplate")
	tabBody:SetPoint("TOPLEFT", 0, -28); tabBody:SetPoint("BOTTOMRIGHT", 0, 0)
	if tabBody.SetBackdrop then
		tabBody:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		tabBody:SetBackdropColor(0, 0, 0, 0.4)
	end

	-- ----- Logs tab content -----
	local logsTab = CreateFrame("Frame", nil, tabBody)
	logsTab:SetAllPoints(tabBody)

	local toolbar = CreateFrame("Frame", nil, logsTab)
	toolbar:SetPoint("TOPLEFT", 6, -6); toolbar:SetPoint("TOPRIGHT", -6, -6); toolbar:SetHeight(24)

	local lvlLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	lvlLabel:SetPoint("LEFT", 4, 0); lvlLabel:SetText("Min level:")

	local lvlDropdown = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
	lvlDropdown:SetSize(72, 20); lvlDropdown:SetPoint("LEFT", lvlLabel, "RIGHT", 4, 0)
	lvlDropdown:SetText(LEVEL_NAMES[lib.minLevel] or "?")
	lvlDropdown:SetScript("OnClick", function()
		local n = lib.minLevel - 1
		if n < 1 then n = 5 end
		lib.minLevel = n
		lvlDropdown:SetText(LEVEL_NAMES[n] or "?")
		lib:Refresh()
	end)

	local searchLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	searchLabel:SetPoint("LEFT", lvlDropdown, "RIGHT", 12, 0); searchLabel:SetText("Search:")

	local searchBox = CreateFrame("EditBox", nil, toolbar, "InputBoxTemplate")
	searchBox:SetSize(160, 20); searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function(self)
		local txt = self:GetText()
		lib.searchText = (txt and txt ~= "") and txt or nil
		lib:Refresh()
	end)
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local copyBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
	copyBtn:SetSize(60, 20); copyBtn:SetPoint("RIGHT", -4, 0); copyBtn:SetText("Copy")
	copyBtn:SetScript("OnClick", function() lib:OpenCopyPopup() end)

	local clearBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
	clearBtn:SetSize(60, 20); clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -4, 0); clearBtn:SetText("Clear")
	clearBtn:SetScript("OnClick", function() Log:Clear(); lib:Refresh() end)

	local logsScroll = CreateFrame("ScrollFrame", "CairnDashboardLogsScroll", logsTab, "UIPanelScrollFrameTemplate")
	logsScroll:SetPoint("TOPLEFT", 6, -34); logsScroll:SetPoint("BOTTOMRIGHT", -28, 22)

	local logsContent = CreateFrame("Frame", nil, logsScroll)
	logsContent:SetSize(1, 1); logsScroll:SetScrollChild(logsContent)

	local logsBody = logsContent:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
	logsBody:SetJustifyH("LEFT"); logsBody:SetJustifyV("TOP")
	logsBody:SetPoint("TOPLEFT", 4, -4); logsBody:SetWidth(logsScroll:GetWidth() - 12)

	local statusBar = logsTab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	statusBar:SetPoint("BOTTOMLEFT", 6, 4); statusBar:SetText("")

	logsTab:SetScript("OnSizeChanged", function()
		logsBody:SetWidth(logsScroll:GetWidth() - 12)
		lib:Refresh()
	end)

	lib.logsTab     = logsTab
	lib.logsScroll  = logsScroll
	lib.logsContent = logsContent
	lib.logsBody    = logsBody
	lib.statusBar   = statusBar

	-- ----- Info tab content -----
	local infoTab = CreateFrame("Frame", nil, tabBody)
	infoTab:SetAllPoints(tabBody)
	infoTab:Hide()

	local infoBody = infoTab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	infoBody:SetJustifyH("LEFT"); infoBody:SetJustifyV("TOP")
	infoBody:SetPoint("TOPLEFT", 12, -12); infoBody:SetPoint("BOTTOMRIGHT", -12, 12)

	lib.infoTab  = infoTab
	lib.infoBody = infoBody

	local function switchTab(which)
		lib.activeTab = which
		if which == "logs" then logsTab:Show(); infoTab:Hide()
		else                    logsTab:Hide(); infoTab:Show() end
		lib:Refresh()
	end
	logsTabBtn:SetScript("OnClick", function() switchTab("logs") end)
	infoTabBtn:SetScript("OnClick", function() switchTab("info") end)
	lib.activeTab = "logs"

	if not lib._unsub then
		lib._unsub = Log:OnNewEntry(function()
			if lib.frame and lib.frame:IsShown() then lib:Refresh() end
		end, "Cairn-Dashboard")
	end

	lib.frame = f
	return f
end

-- ----- Source list rendering --------------------------------------------

local function rebuildSourceList()
	local content = lib.leftContent
	local sources = lib:GetSources()

	-- CRITICAL: ensure the scroll content frame has a real width so that
	-- TOPLEFT/TOPRIGHT-anchored row buttons aren't 1px wide and unclickable.
	local scrollW = lib.leftScroll:GetWidth()
	if scrollW and scrollW > 0 then content:SetWidth(scrollW) end

	for _, b in ipairs(lib.sourceButtons) do b:Hide() end

	local y = -2
	for i, name in ipairs(sources) do
		local b = lib.sourceButtons[i]
		if not b then
			b = CreateFrame("Button", nil, content)
			b:SetHeight(20)
			b:EnableMouse(true)
			b:RegisterForClicks("LeftButtonUp")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -6, 0)
			b.text:SetJustifyH("LEFT")
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
			lib.sourceButtons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT",  content, "TOPLEFT",  4, y)
		b:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
		b.text:SetText(name)
		b._sourceName = name
		b:SetScript("OnClick", function(self) lib:SelectSource(self._sourceName) end)
		b:Show()
		y = y - 22
	end
	content:SetHeight(math.max(1, -y + 4))

	for _, b in ipairs(lib.sourceButtons) do
		if b._sourceName == lib.selectedSource then
			b.text:SetTextColor(1, 0.82, 0)
		else
			b.text:SetTextColor(1, 1, 1)
		end
	end
end

-- ----- Logs tab refresh --------------------------------------------------

local function refreshLogsTab()
	local entries = Log:GetEntries(function(e)
		return entryMatches(e, lib.selectedSource, lib.minLevel, lib.searchText)
	end)
	local n = #entries
	local start = math.max(1, n - lib.maxRows + 1)
	local lines = {}
	for i = start, n do lines[#lines + 1] = formatLine(entries[i]) end
	lib.logsBody:SetText(table.concat(lines, "\n"))

	local h = lib.logsBody:GetStringHeight() + 12
	lib.logsContent:SetHeight(h)
	lib.logsContent:SetWidth(lib.logsScroll:GetWidth())
	if lib.logsScroll.UpdateScrollChildRect then lib.logsScroll:UpdateScrollChildRect() end
	local maxScroll = math.max(0, h - lib.logsScroll:GetHeight())
	lib.logsScroll:SetVerticalScroll(maxScroll)

	local total = Log:Count()
	lib.statusBar:SetText(string.format(
		"showing %d of %d  |  source=%s  |  min level=%s%s",
		n, total, lib.selectedSource, LEVEL_NAMES[lib.minLevel] or "?",
		lib.searchText and ("  |  search=" .. lib.searchText) or ""
	))
end

-- ----- Info tab refresh --------------------------------------------------

local function countByLevel(sourceName)
	local counts = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
	local entries = Log:GetEntries(function(e)
		return sourceName == "All" or e.source == sourceName
	end)
	for i = 1, #entries do counts[entries[i].level] = (counts[entries[i].level] or 0) + 1 end
	return counts
end

local function eventCountForOwner(name)
	if not Events or not Events.handlers then return 0 end
	local count = 0
	for _, list in pairs(Events.handlers) do
		for i = 1, #list do
			if list[i].owner == name and not list[i].removed then count = count + 1 end
		end
	end
	return count
end

local function fmtTs(ts)
	if not ts then return "never" end
	if date then return date("%Y-%m-%d %H:%M:%S", ts) end
	return tostring(ts)
end

local function refreshInfoTab()
	local name = lib.selectedSource
	local lines = { string.format("|cFFFFD200Source:|r %s", name), "" }

	if name ~= "All" then
		if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
			local ok = pcall(UpdateAddOnMemoryUsage)
			if ok then
				local kb = pcall(GetAddOnMemoryUsage, name) and GetAddOnMemoryUsage(name) or nil
				if kb and kb > 0 then
					lines[#lines + 1] = string.format("|cFFFFD200Memory:|r %.1f KB", kb)
				else
					lines[#lines + 1] = "|cFFFFD200Memory:|r (not a loaded addon, or zero)"
				end
			end
		end

		local addon = Addon and Addon.Get and Addon.Get(name)
		if addon then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "|cFFFFD200Lifecycle (Cairn.Addon):|r"
			lines[#lines + 1] = "  OnInit:   " .. fmtTs(addon.initFiredAt)
			lines[#lines + 1] = "  OnLogin:  " .. fmtTs(addon.loginFiredAt)
			lines[#lines + 1] = "  OnEnter:  " .. fmtTs(addon.enterFiredAt)
			lines[#lines + 1] = "  OnLogout: " .. fmtTs(addon.logoutFiredAt)
		end

		local evCount = eventCountForOwner(name)
		if evCount > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = string.format("|cFFFFD200Event subscriptions (Cairn.Events):|r %d active", evCount)
		end

		local slash = Slash and Slash.Get and Slash.Get(name)
		if slash then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "|cFFFFD200Slash commands (Cairn.Slash):|r"
			lines[#lines + 1] = "  primary: " .. (slash._slashes[1] or "?")
			local subs = {}
			for n in pairs(slash._subs) do subs[#subs + 1] = n end
			table.sort(subs)
			lines[#lines + 1] = "  subs: " .. (#subs > 0 and table.concat(subs, ", ") or "(none)")
		end

		local logger = Log.loggers and Log.loggers[name]
		if logger then
			lines[#lines + 1] = ""
			lines[#lines + 1] = string.format("|cFFFFD200Logger (Cairn.Log):|r level=%s",
				LEVEL_NAMES[logger:GetLevel()] or "?")
		end
	end

	local counts = countByLevel(name)
	local totalForSource = counts[1] + counts[2] + counts[3] + counts[4] + counts[5]
	lines[#lines + 1] = ""
	lines[#lines + 1] = string.format("|cFFFFD200Log entries:|r %d total", totalForSource)
	lines[#lines + 1] = string.format("  ERROR: %d   WARN: %d   INFO: %d   DEBUG: %d   TRACE: %d",
		counts[1], counts[2], counts[3], counts[4], counts[5])

	lib.infoBody:SetText(table.concat(lines, "\n"))
end

-- ----- Copy popup --------------------------------------------------------

function lib:OpenCopyPopup()
	local popup = lib.copyPopup
	if not popup then
		popup = CreateFrame("Frame", "CairnDashboardCopyPopup", UIParent, "BackdropTemplate")
		popup:SetSize(640, 400); popup:SetPoint("CENTER")
		popup:SetMovable(true); popup:EnableMouse(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
		popup:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
		popup:SetFrameStrata("DIALOG")
		if popup.SetBackdrop then
			popup:SetBackdrop({
				bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end

		local hint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		hint:SetPoint("TOP", 0, -12); hint:SetText("Press Ctrl+C to copy, Esc to close")

		local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		close:SetScript("OnClick", function() popup:Hide() end)

		local scroll = CreateFrame("ScrollFrame", "CairnDashboardCopyScroll", popup, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 16, -36); scroll:SetPoint("BOTTOMRIGHT", -32, 16)

		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true); edit:SetAutoFocus(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(scroll:GetWidth()); edit:SetMaxLetters(0)
		edit:SetScript("OnEscapePressed", function(self) popup:Hide() end)
		scroll:SetScrollChild(edit)
		popup._edit = edit
		lib.copyPopup = popup
	end

	local entries = Log:GetEntries(function(e)
		return entryMatches(e, lib.selectedSource, lib.minLevel, lib.searchText)
	end)
	local text = lib.FormatLogsForCopy(lib.selectedSource, entries)
	popup._edit:SetText(text)
	popup._edit:HighlightText()
	popup:Show()
	popup._edit:SetFocus()
end

-- ----- Public API --------------------------------------------------------

function lib:Show()
	buildFrame():Show()
	rebuildSourceList()
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

function lib:SelectSource(name)
	if type(name) ~= "string" or name == "" then return end
	self.selectedSource = name
	if self.frame and self.frame:IsShown() then
		rebuildSourceList()
		self:Refresh()
	end
end

function lib:Refresh()
	if not (self.frame and self.frame:IsShown()) then return end
	rebuildSourceList()
	if self.activeTab == "info" then refreshInfoTab() else refreshLogsTab() end
end
