--[[
Cairn-Media-Browser / Tabs / Statusbars

Browses every statusbar texture reachable to the running client:
  * Cairn-private  -- registered with Cairn-Media but NOT with LSM
  * Cairn-public   -- registered with both Cairn-Media and LSM
  * Third-party LSM -- registered by some other addon via LibSharedMedia-3.0

Each row shows visibility badge + display name + file path + three
filled-bar swatches at increasing widths to expose how the texture
stretches. Hover for the exact code snippet (Cairn-Media or LSM).

Cairn-Media-Browser/Tabs/Statusbars (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media
local LSM   = LibStub("LibSharedMedia-3.0", true)

local SAMPLE_WIDTHS = { 80, 200, 360 }
local TINT          = { 0.30, 0.55, 0.95, 1.00 }

local function buildList()
	local out = {}
	for _, name in ipairs(Media:ListStatusbars("private")) do
		out[#out + 1] = { displayName = name, path = Media:GetStatusbar(name),
			source = "private", cairnName = name }
	end
	for _, name in ipairs(Media:ListStatusbars("public")) do
		out[#out + 1] = { displayName = name, path = Media:GetStatusbar(name),
			source = "public", cairnName = name, lsmName = "Cairn " .. name }
	end
	if LSM then
		for _, lsmName in ipairs(LSM:List("statusbar") or {}) do
			if not lsmName:match("^Cairn ") then
				out[#out + 1] = { displayName = lsmName, path = LSM:Fetch("statusbar", lsmName),
					source = "lsm", lsmName = lsmName }
			end
		end
	end
	local sourceOrder = { private = 1, public = 2, lsm = 3 }
	table.sort(out, function(a, b)
		local oa, ob = sourceOrder[a.source], sourceOrder[b.source]
		if oa ~= ob then return oa < ob end
		return (a.displayName or ""):lower() < (b.displayName or ""):lower()
	end)
	return out
end

local function badgeFor(source)
	if source == "private" then return "[CAIRN PRIVATE]", "muted" end
	if source == "public"  then return "[CAIRN PUBLIC]",  "success" end
	if source == "lsm"     then return "[LSM]",            "body" end
	return "[?]", "body"
end

local function tooltipCodeFor(entry)
	if entry.source == "lsm" then
		return {
			'local LSM  = LibStub("LibSharedMedia-3.0")',
			('local path = LSM:Fetch("statusbar", %q)'):format(entry.lsmName),
			'bar:SetStatusBarTexture(path)',
		}
	end
	return {
		'local Media = LibStub("Cairn-Media-1.0")',
		('local path  = Media:GetStatusbar(%q)'):format(entry.cairnName),
		'bar:SetStatusBarTexture(path)',
	}
end

local function buildRow(parent, entry)
	local row = Gui:Acquire("Container", parent, {
		bg          = "color.bg.panel",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	row:SetHeight(70)

	if not row._regionsWiped then
		for _, region in ipairs({ row:GetRegions() }) do
			if region.Hide    then region:Hide()       end
			if region.SetText then region:SetText("") end
		end
		row._regionsWiped = true
		row._swatches = nil
	end

	local path = entry.path or "(unregistered)"
	local badge, badgeVariant = badgeFor(entry.source)

	local header = Gui:Acquire("Label", row, {
		text    = ("%s  %s"):format(badge, entry.displayName),
		variant = badgeVariant,
		align   = "left",
	})
	header.Cairn:SetLayoutManual(true)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
	header:SetHeight(16)
	header:SetWidth(220)

	local pathLbl = Gui:Acquire("Label", row, {
		text    = path,
		variant = "small",
		align   = "left",
	})
	pathLbl.Cairn:SetLayoutManual(true)
	pathLbl:ClearAllPoints()
	pathLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  236, -6)
	pathLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
	pathLbl:SetHeight(16)

	row._swatches = row._swatches or {}
	local x = 8
	for i, w in ipairs(SAMPLE_WIDTHS) do
		local set = row._swatches[i]
		if not set then
			set = {
				tex = row:CreateTexture(nil, "ARTWORK"),
				lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
			}
			set.tex:SetVertexColor(TINT[1], TINT[2], TINT[3], TINT[4])
			set.lbl:SetJustifyH("CENTER")
			row._swatches[i] = set
		end
		set.tex:SetTexture(path)
		set.tex:SetSize(w, 14)
		set.tex:ClearAllPoints()
		set.tex:SetPoint("TOPLEFT", row, "TOPLEFT", x, -34)
		set.lbl:SetText(("%dpx"):format(w))
		set.lbl:ClearAllPoints()
		set.lbl:SetPoint("TOPLEFT", row, "TOPLEFT", x, -52)
		set.lbl:SetWidth(w)
		x = x + w + 8
	end

	row._currentEntry = entry
	if not row._tooltipHooked then
		row:EnableMouse(true)
		row:HookScript("OnEnter", function(self)
			local e = self._currentEntry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(("statusbar: %s"):format(e.displayName), 1, 1, 1)
			GameTooltip:AddLine(badgeFor(e.source), 0.7, 0.7, 0.7)
			GameTooltip:AddLine("Path: " .. (e.path or "?"), 0.6, 0.6, 0.6)
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine("Code:", 1, 0.85, 0.4)
			for _, line in ipairs(tooltipCodeFor(e)) do
				GameTooltip:AddLine(line, 0.7, 0.9, 1)
			end
			GameTooltip:Show()
		end)
		row:HookScript("OnLeave", function() GameTooltip:Hide() end)
		row._tooltipHooked = true
	end

	return row
end

local function build(pane, browser)
	local _, body = browser:BuildTabShell(pane, "Statusbar textures")
	if not body then return end

	local entries = buildList()
	local contentH = math.max(800, #entries * 74 + 200)
	body = browser:MakeScrollable(body, contentH)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 8 })

	browser:AppendIntro(body,
		("Showing %d statusbars (Cairn-private, Cairn-public, third-party LSM). "
		.. "Hover any row for the exact code snippet."):format(#entries))

	local rows = {}

	local function applyFilter(visibility)
		for i, row in ipairs(rows) do
			local entry = entries[i]
			local show
			if visibility == nil then
				show = true
			elseif visibility == "public" then
				show = entry.source == "public" or entry.source == "lsm"
			elseif visibility == "private" then
				show = entry.source == "private"
			end
			if show then
				row:Show()
				row.Cairn:SetLayoutManual(false)
			else
				row:Hide()
				row.Cairn:SetLayoutManual(true)
			end
		end
	end

	browser:BuildVisibilityFilter(body, nil, function(v) applyFilter(v) end)

	for _, entry in ipairs(entries) do
		rows[#rows + 1] = buildRow(body, entry)
	end

	applyFilter(nil)
end

Browser:RegisterTab("statusbars", {
	label = "Statusbars",
	order = 20,
	build = build,
})
