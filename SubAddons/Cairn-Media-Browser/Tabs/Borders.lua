--[[
Cairn-Media-Browser / Tabs / Borders

Browses every border texture reachable to the running client (Cairn-Media
private + public + third-party LSM). Each row shows visibility badge +
display name + file path + a 220x60 sample frame wrapped in the border
via SetBackdrop. Hover for the exact code snippet.

Cairn-Media-Browser/Tabs/Borders (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media
local LSM   = LibStub("LibSharedMedia-3.0", true)

local SAMPLE_W = 220
local SAMPLE_H = 60

local function buildList()
	local out = {}
	for _, name in ipairs(Media:ListBorders("private")) do
		out[#out + 1] = { displayName = name, path = Media:GetBorder(name),
			source = "private", cairnName = name }
	end
	for _, name in ipairs(Media:ListBorders("public")) do
		out[#out + 1] = { displayName = name, path = Media:GetBorder(name),
			source = "public", cairnName = name, lsmName = "Cairn " .. name }
	end
	if LSM then
		for _, lsmName in ipairs(LSM:List("border") or {}) do
			if not lsmName:match("^Cairn ") then
				out[#out + 1] = { displayName = lsmName, path = LSM:Fetch("border", lsmName),
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
			'local LSM = LibStub("LibSharedMedia-3.0")',
			'frame:SetBackdrop({',
			('  edgeFile = LSM:Fetch("border", %q),'):format(entry.lsmName),
			'  edgeSize = 12,',
			'})',
		}
	end
	return {
		'local Media = LibStub("Cairn-Media-1.0")',
		'frame:SetBackdrop({',
		('  edgeFile = Media:GetBorder(%q),'):format(entry.cairnName),
		'  edgeSize = 12,',
		'})',
	}
end

local function buildRow(parent, entry)
	local row = Gui:Acquire("Container", parent, {
		bg          = "color.bg.panel",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	row:SetHeight(96)

	if not row._childrenWiped then
		for _, kid in ipairs({ row:GetChildren() }) do
			if not kid.Cairn and kid.Hide then kid:Hide() end
		end
		row._childrenWiped = true
		row._sample = nil
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
	header:SetPoint("TOPLEFT", row, "TOPLEFT", SAMPLE_W + 24, -8)
	header:SetHeight(16)
	header:SetWidth(280)

	local pathLbl = Gui:Acquire("Label", row, {
		text    = path,
		variant = "small",
		align   = "left",
		wrap    = true,
	})
	pathLbl.Cairn:SetLayoutManual(true)
	pathLbl:ClearAllPoints()
	pathLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  SAMPLE_W + 24, -28)
	pathLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -28)
	pathLbl:SetHeight(40)

	if not row._sample then
		row._sample = CreateFrame("Frame", nil, row, "BackdropTemplate")
		row._sample:SetSize(SAMPLE_W, SAMPLE_H)
		row._sample:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
	end
	row._sample:SetBackdrop({
		bgFile   = [[Interface\Buttons\WHITE8X8]],
		edgeFile = path,
		edgeSize = 12,
		insets   = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	row._sample:SetBackdropColor(0.10, 0.10, 0.12, 1.0)

	row._currentEntry = entry
	if not row._tooltipHooked then
		row:EnableMouse(true)
		row:HookScript("OnEnter", function(self)
			local e = self._currentEntry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(("border: %s"):format(e.displayName), 1, 1, 1)
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
	local _, body = browser:BuildTabShell(pane, "Borders")
	if not body then return end

	local entries = buildList()
	local contentH = math.max(800, #entries * 100 + 200)
	body = browser:MakeScrollable(body, contentH)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 8 })

	browser:AppendIntro(body,
		("Showing %d borders (Cairn-private, Cairn-public, third-party LSM). "
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

Browser:RegisterTab("borders", {
	label = "Borders",
	order = 30,
	build = build,
})
