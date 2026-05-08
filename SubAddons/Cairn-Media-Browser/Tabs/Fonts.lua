--[[
Cairn-Media-Browser / Tabs / Fonts

Browses every font reachable to the running client:
  * Cairn-private  -- registered with Cairn-Media but NOT with LSM
  * Cairn-public   -- registered with both Cairn-Media and LSM
  * Third-party LSM -- registered by some other addon via LibSharedMedia-3.0

Each row shows visibility badge + display name + file path + a live
preview of the font at 12 / 16 / 24 pt. Hover for the exact code
snippet (Cairn-Media or LSM, whichever applies).

For Material Symbols icon fonts (which contain glyphs rather than text),
the preview swaps in a row of icon glyphs from the icon registry instead
of the standard pangram.

Cairn-Media-Browser/Tabs/Fonts (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media
local LSM   = LibStub("LibSharedMedia-3.0", true)

local PANGRAM = "The quick brown fox jumps over the lazy dog 0123456789"

local ICON_SAMPLE_NAMES = {
	"home", "search", "settings", "person", "favorite",
	"check_circle", "warning", "info", "star", "bookmark",
}

local function isIconFont(displayName)
	return displayName == "MaterialOutlined"
		or displayName == "MaterialRounded"
		or displayName == "MaterialSharp"
end

local function iconSampleText()
	local parts = {}
	for _, name in ipairs(ICON_SAMPLE_NAMES) do
		local glyph = Media:GetIconGlyph(name)
		if glyph then parts[#parts + 1] = glyph end
	end
	return table.concat(parts, "  ")
end

-- Build an aggregated list of every reachable font:
--   { displayName, path, source = "private"|"public"|"lsm",
--     cairnName?, lsmName? }
-- Sorted by (sourceOrder, displayName) so Cairn entries float to the top.
local function buildFontList()
	local out = {}
	-- Cairn-private
	for _, name in ipairs(Media:ListFonts("private")) do
		out[#out + 1] = {
			displayName = name,
			path        = Media:GetFont(name),
			source      = "private",
			cairnName   = name,
		}
	end
	-- Cairn-public
	for _, name in ipairs(Media:ListFonts("public")) do
		out[#out + 1] = {
			displayName = name,
			path        = Media:GetFont(name),
			source      = "public",
			cairnName   = name,
			lsmName     = "Cairn " .. name,
		}
	end
	-- Third-party LSM (skip "Cairn ..." entries since we own those)
	if LSM then
		for _, lsmName in ipairs(LSM:List("font") or {}) do
			if not lsmName:match("^Cairn ") then
				out[#out + 1] = {
					displayName = lsmName,
					path        = LSM:Fetch("font", lsmName),
					source      = "lsm",
					lsmName     = lsmName,
				}
			end
		end
	end
	-- Sort: Cairn-private first, then Cairn-public, then LSM, alphabetically within each.
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
			('local font = LSM:Fetch("font", %q)'):format(entry.lsmName),
			'fs:SetFont(font, 12, "")',
		}
	end
	return {
		'local Media = LibStub("Cairn-Media-1.0")',
		('local font  = Media:GetFont(%q)'):format(entry.cairnName),
		'fs:SetFont(font, 12, "")',
	}
end

-- Build one row for a single font entry. Returns the row Container.
local function buildFontRow(parent, entry)
	local row = Gui:Acquire("Container", parent, {
		bg          = "color.bg.panel",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	row:SetHeight(120)

	if not row._regionsWiped then
		for _, region in ipairs({ row:GetRegions() }) do
			if region.Hide    then region:Hide()       end
			if region.SetText then region:SetText("") end
		end
		row._regionsWiped = true
		row._p12, row._p16, row._p24 = nil, nil, nil
	end

	local path = entry.path or "(unregistered)"
	local sample = isIconFont(entry.displayName) and iconSampleText() or PANGRAM
	local badge, badgeVariant = badgeFor(entry.source)

	-- Header: badge + name. Anchored to top-left.
	local header = Gui:Acquire("Label", row, {
		text    = ("%s  %s"):format(badge, entry.displayName),
		variant = badgeVariant,
		align   = "left",
	})
	header.Cairn:SetLayoutManual(true)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
	header:SetHeight(16)
	header:SetWidth(240)

	local pathLbl = Gui:Acquire("Label", row, {
		text    = path,
		variant = "small",
		align   = "left",
	})
	pathLbl.Cairn:SetLayoutManual(true)
	pathLbl:ClearAllPoints()
	pathLbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  256, -6)
	pathLbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
	pathLbl:SetHeight(16)

	local function preview(slot, text, size, yOffset)
		local fs = row[slot]
		if not fs then
			fs = row:CreateFontString(nil, "OVERLAY")
			fs:SetTextColor(1, 1, 1)
			fs:SetJustifyH("LEFT")
			fs:SetPoint("TOPLEFT",  row, "TOPLEFT",  8,  yOffset)
			fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, yOffset)
			row[slot] = fs
		end
		fs:SetFont(path, size, "")
		fs:SetText(text)
		fs:SetHeight(size + 4)
	end

	preview("_p12", ("12pt   %s"):format(sample), 12, -28)
	preview("_p16", ("16pt   %s"):format(sample), 16, -52)
	preview("_p24", ("24pt   %s"):format(sample), 24, -82)

	-- Tooltip data is dynamic (entry can change if row is repurposed in
	-- future builds, though we don't currently repurpose). Stash on the
	-- row frame so the hook reads current state.
	row._currentEntry = entry
	if not row._tooltipHooked then
		row:EnableMouse(true)
		row:HookScript("OnEnter", function(self)
			local e = self._currentEntry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(("font: %s"):format(e.displayName), 1, 1, 1)
			local b = badgeFor(e.source)
			GameTooltip:AddLine(b, 0.7, 0.7, 0.7)
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
	local _, body = browser:BuildTabShell(pane, "Fonts")
	if not body then return end

	-- Build once + show/hide on filter. With LSM aggregation the row count
	-- can be 50-200+ depending on the user's loaded addons; per-row releases
	-- on every filter toggle would mean a lot of pool churn. Keep all rows
	-- alive; filtering just shows/hides + Stack-skips hidden rows.
	local entries = buildFontList()
	local contentH = math.max(1200, #entries * 124 + 200)
	body = browser:MakeScrollable(body, contentH)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 8 })

	browser:AppendIntro(body,
		("Showing %d fonts (Cairn-private, Cairn-public, third-party LSM). "
		.. "Filter buttons: All / Public (LSM-registered) / Private (Cairn-only). "
		.. "Hover any row for the exact code snippet."):format(#entries))

	local rows = {}

	local function applyFilter(visibility)
		-- visibility: nil ("all"), "public" (LSM-visible: Cairn-public OR lsm),
		-- or "private" (Cairn-private only)
		local visibleCount = 0
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
				visibleCount = visibleCount + 1
			else
				row:Hide()
				row.Cairn:SetLayoutManual(true)
			end
		end
	end

	browser:BuildVisibilityFilter(body, nil, function(visibility)
		applyFilter(visibility)
	end)

	-- Build all rows up front.
	for _, entry in ipairs(entries) do
		rows[#rows + 1] = buildFontRow(body, entry)
	end

	applyFilter(nil)
end

Browser:RegisterTab("fonts", {
	label = "Fonts",
	order = 10,
	build = build,
})
