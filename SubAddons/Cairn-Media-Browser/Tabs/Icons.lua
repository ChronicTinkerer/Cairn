--[[
Cairn-Media-Browser / Tabs / Icons

Browses the Material Symbols icon glyph registry. Top: a font picker
(Outlined / Rounded / Sharp). Below: a 5-column grid where each cell
shows the glyph rendered at 36pt with the icon name and codepoint
underneath.

Cairn-Media-Browser/Tabs/Icons (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media

local FONT_CHOICES = { "MaterialOutlined", "MaterialRounded", "MaterialSharp" }
local CELLS_PER_ROW = 5
local CELL_W = 170
local CELL_H = 96
local GLYPH_SIZE = 36

local function buildCell(parent, iconName, fontPath)
	local cell = Gui:Acquire("Container", parent, {
		bg          = "color.bg.panel",
		border      = "color.border.subtle",
		borderWidth = 1,
		width       = CELL_W,
		height      = CELL_H,
	})

	-- One-time wipe of any pre-existing anonymous regions on this frame.
	-- Pool frames (and their regions) persist across /reload, so cells
	-- acquired by an OLDER version of this code that created fresh
	-- FontStrings each Acquire have left stale anonymous FontStrings
	-- attached. We can't release them (frames can't destroy regions in
	-- WoW), but we can Hide and SetText("") so they don't render.
	-- The `_regionsWiped` marker keeps this from running every Acquire.
	if not cell._regionsWiped then
		for _, region in ipairs({ cell:GetRegions() }) do
			if region.Hide   then region:Hide()        end
			if region.SetText then region:SetText("") end
		end
		cell._regionsWiped = true
		-- Drop our previous stashes too -- they were just hidden, force
		-- recreate so they're at the right anchor.
		cell._glyphFs = nil
		cell._nameFs  = nil
		cell._cpFs    = nil
	end

	-- Reuse raw FontStrings across pool recycle. Cairn-Gui cascade-releases
	-- Cairn-mixin children but raw :CreateFontString / :CreateTexture regions
	-- stay attached to the frame. Stash on the frame and reuse.
	if not cell._glyphFs then
		cell._glyphFs = cell:CreateFontString(nil, "OVERLAY")
		cell._glyphFs:SetTextColor(1, 1, 1)
		cell._glyphFs:SetJustifyH("CENTER")
		cell._glyphFs:SetPoint("TOPLEFT",  cell, "TOPLEFT",  4, -8)
		cell._glyphFs:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -8)
		cell._glyphFs:SetHeight(GLYPH_SIZE + 6)
	end
	if not cell._nameFs then
		cell._nameFs = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell._nameFs:SetJustifyH("CENTER")
		cell._nameFs:SetPoint("TOPLEFT",  cell, "TOPLEFT",  2, -(GLYPH_SIZE + 18))
		cell._nameFs:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -(GLYPH_SIZE + 18))
		cell._nameFs:SetHeight(14)
	end
	if not cell._cpFs then
		cell._cpFs = cell:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		cell._cpFs:SetJustifyH("CENTER")
		cell._cpFs:SetPoint("TOPLEFT",  cell, "TOPLEFT",  2, -(GLYPH_SIZE + 36))
		cell._cpFs:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -(GLYPH_SIZE + 36))
		cell._cpFs:SetHeight(12)
	end

	-- Update text + font for current icon.
	local cp    = Media:GetIconCodepoint(iconName)
	local glyph = Media:GetIconGlyph(iconName) or "?"
	cell._glyphFs:SetFont(fontPath, GLYPH_SIZE, "")
	cell._glyphFs:SetText(glyph)
	cell._nameFs:SetText(iconName)
	cell._cpFs:SetText(cp and (("0x%04X"):format(cp)) or "")

	-- Tooltip on hover with the exact code snippet to render this icon.
	-- HookScript only on the FIRST Acquire of this cell (subsequent reuses
	-- already have the script chained); EnableMouse so the hooks fire.
	-- The hook reads iconName / cp from cell._currentIcon so that future
	-- Acquires (with different icon names) get correct tooltip text.
	cell._currentIcon = iconName
	cell._currentCp   = cp
	if not cell._tooltipHooked then
		cell:EnableMouse(true)
		cell:HookScript("OnEnter", function(self)
			if not self._currentIcon then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self._currentIcon, 1, 1, 1)
			if self._currentCp then
				GameTooltip:AddLine(("codepoint: 0x%04X"):format(self._currentCp),
					0.7, 0.7, 0.7)
			end
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine("Code:", 1, 0.85, 0.4)
			GameTooltip:AddLine('local Media = LibStub("Cairn-Media-1.0")',
				0.7, 0.9, 1)
			GameTooltip:AddLine('local font  = Media:GetFont("MaterialOutlined")',
				0.7, 0.9, 1)
			GameTooltip:AddLine('fs:SetFont(font, 16, "")', 0.7, 0.9, 1)
			GameTooltip:AddLine(('fs:SetText(Media:GetIconGlyph(%q))'):format(self._currentIcon),
				0.7, 0.9, 1)
			GameTooltip:Show()
		end)
		cell:HookScript("OnLeave", function() GameTooltip:Hide() end)
		cell._tooltipHooked = true
	end

	return cell
end

local function build(pane, browser)
	local _, body = browser:BuildTabShell(pane, "Icons (Material Symbols)")
	if not body then return end

	-- ~4244 icons / 5 per row = ~849 rows at ~102 px each = ~86,500 px content.
	-- Plus picker row and intro. Round to 90,000 to be safe.
	body = browser:MakeScrollable(body, 90000)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 8 })

	browser:AppendIntro(body,
		"Pick a font style above + type to search. Each cell shows the glyph rendered at 36pt with name + Unicode codepoint. Use Cairn.Media:GetIconGlyph(name) in your code. Hover any cell for the exact code snippet.")

	-- ----- Search box ----------------------------------------------------

	local searchBox = Gui:Acquire("EditBox", body, {
		width       = 400,
		height      = 26,
		placeholder = "Search icons (e.g. \"arrow\", \"lock\", \"check\")...",
	})

	-- ----- Font picker --------------------------------------------------

	local pickerRow = Gui:Acquire("Container", body, {})
	pickerRow.Cairn:SetLayout("Stack",
		{ direction = "horizontal", gap = 4, padding = 0 })
	pickerRow:SetHeight(28)

	local currentFont = "MaterialOutlined"
	local pickerButtons = {}

	local function refreshPicker()
		for name, btn in pairs(pickerButtons) do
			btn.Cairn:SetVariant(name == currentFont and "primary" or "default")
		end
	end

	-- ----- Grid state ---------------------------------------------------
	-- cells / rowContainers grow during the batched build. applySearch
	-- repurposes existing cells (SetText / SetFont on the stashed
	-- FontStrings) to display whatever subset matches the current search,
	-- compacted into the front of the grid. Hidden rowContainers get
	-- SetLayoutManual(true) so body's vertical Stack skips them and the
	-- visible content packs to the top with no gaps.

	local cells          = {}
	local rowContainers  = {}
	local currentSearch  = ""
	local allNames       = Media:ListIcons()  -- captured once; sorted

	local function updateCellContent(cell, iconName, fontPath)
		local cp    = Media:GetIconCodepoint(iconName)
		local glyph = Media:GetIconGlyph(iconName) or "?"
		cell._glyphFs:SetFont(fontPath, GLYPH_SIZE, "")
		cell._glyphFs:SetText(glyph)
		cell._nameFs:SetText(iconName)
		cell._cpFs:SetText(cp and (("0x%04X"):format(cp)) or "")
		cell._currentIcon = iconName
		cell._currentCp   = cp
	end

	local function applySearch()
		local fontPath = Media:GetFont(currentFont)
		if not fontPath then return end

		local q = currentSearch:lower()
		local matched
		if q == "" then
			matched = allNames
		else
			matched = {}
			for _, n in ipairs(allNames) do
				if n:lower():find(q, 1, true) then
					matched[#matched + 1] = n
				end
			end
		end

		-- Update / show / hide cells.
		for i, cell in ipairs(cells) do
			if i <= #matched then
				updateCellContent(cell, matched[i], fontPath)
				cell:Show()
			else
				cell:Hide()
			end
		end

		-- Compact rows: rows with at least one visible cell stay in body's
		-- Stack flow; the rest opt out via SetLayoutManual so Stack skips them.
		local rowsNeeded = math.ceil(#matched / CELLS_PER_ROW)
		for i, container in ipairs(rowContainers) do
			if i <= rowsNeeded then
				container:Show()
				container.Cairn:SetLayoutManual(false)
			else
				container:Hide()
				container.Cairn:SetLayoutManual(true)
			end
		end
	end

	searchBox.Cairn:On("TextChanged", function(_, text)
		currentSearch = text or ""
		applySearch()
	end)

	for _, name in ipairs(FONT_CHOICES) do
		local btn = Gui:Acquire("Button", pickerRow, { text = name, variant = "default" })
		pickerButtons[name] = btn
		btn.Cairn:On("Click", function()
			currentFont = name
			refreshPicker()
			applySearch()  -- re-applies font (via updateCellContent) + filter
		end)
	end
	refreshPicker()

	-- ----- Grid (built lazily in batches) -------------------------------
	-- 4244 icons synchronously would freeze the client for several
	-- seconds. Build BATCH_ROWS rows per frame via C_Timer.After so the
	-- UI stays responsive. ~850 rows / 10 = ~85 batches = ~1.4s smooth.
	-- After the build completes, applySearch reflects any pending search
	-- typed during the build.

	local BATCH_ROWS = 10
	local fontPath   = Media:GetFont(currentFont)
	local i = 1

	local function buildBatch()
		local rowsThisBatch = 0
		while i <= #allNames and rowsThisBatch < BATCH_ROWS do
			local rowContainer = Gui:Acquire("Container", body, { height = CELL_H })
			rowContainer.Cairn:SetLayout("Stack",
				{ direction = "horizontal", gap = 4, padding = 0 })
			rowContainers[#rowContainers + 1] = rowContainer

			for c = 1, CELLS_PER_ROW do
				local name = allNames[i]
				if not name then break end
				local cell = buildCell(rowContainer, name, fontPath)
				cells[#cells + 1] = cell
				i = i + 1
			end
			rowsThisBatch = rowsThisBatch + 1
		end
		if i <= #allNames then
			C_Timer.After(0, buildBatch)
		else
			applySearch()  -- final pass to sync any pending search/font
		end
	end

	buildBatch()
end

Browser:RegisterTab("icons", {
	label = "Icons",
	order = 60,
	build = build,
})
