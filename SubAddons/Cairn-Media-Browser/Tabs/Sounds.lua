--[[
Cairn-Media-Browser / Tabs / Sounds

Browses every sound reachable to the running client (Cairn-Media private
+ public + third-party LSM). Each row shows visibility badge + display
name + file path + a Play button. PlaySoundFile uses "Master" so the
sound plays even when the user has SFX volume muted. Hover for the exact
code snippet.

Cairn-Media-Browser/Tabs/Sounds (c) 2026 ChronicTinkerer. MIT license.
]]

local Browser = _G.CairnMediaBrowser
if not Browser then return end

local Gui   = Browser.lib
local Media = Browser.media
local LSM   = LibStub("LibSharedMedia-3.0", true)

local function buildList()
	local out = {}
	for _, name in ipairs(Media:ListSounds("private")) do
		out[#out + 1] = { displayName = name, path = Media:GetSound(name),
			source = "private", cairnName = name }
	end
	for _, name in ipairs(Media:ListSounds("public")) do
		out[#out + 1] = { displayName = name, path = Media:GetSound(name),
			source = "public", cairnName = name, lsmName = "Cairn " .. name }
	end
	if LSM then
		for _, lsmName in ipairs(LSM:List("sound") or {}) do
			if not lsmName:match("^Cairn ") then
				out[#out + 1] = { displayName = lsmName, path = LSM:Fetch("sound", lsmName),
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
			('PlaySoundFile(LSM:Fetch("sound", %q), "Master")'):format(entry.lsmName),
		}
	end
	return {
		'local Media = LibStub("Cairn-Media-1.0")',
		('PlaySoundFile(Media:GetSound(%q), "Master")'):format(entry.cairnName),
	}
end

local function buildRow(parent, entry)
	local row = Gui:Acquire("Container", parent, {
		bg          = "color.bg.panel",
		border      = "color.border.subtle",
		borderWidth = 1,
	})
	row:SetHeight(48)

	local path = entry.path or "(unregistered)"
	local badge, badgeVariant = badgeFor(entry.source)

	local header = Gui:Acquire("Label", row, {
		text    = ("%s  %s"):format(badge, entry.displayName),
		variant = badgeVariant,
		align   = "left",
	})
	header.Cairn:SetLayoutManual(true)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
	header:SetHeight(16)
	header:SetWidth(220)

	local pathLbl = Gui:Acquire("Label", row, {
		text    = path,
		variant = "small",
		align   = "left",
	})
	pathLbl.Cairn:SetLayoutManual(true)
	pathLbl:ClearAllPoints()
	pathLbl:SetPoint("TOPLEFT",     row, "TOPLEFT",     236, -8)
	pathLbl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -100, 8)
	pathLbl:SetHeight(32)

	local play = Gui:Acquire("Button", row, {
		text    = "Play",
		variant = "primary",
	})
	play.Cairn:SetLayoutManual(true)
	play:ClearAllPoints()
	play:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	play:SetSize(80, 24)
	play.Cairn:On("Click", function()
		PlaySoundFile(path, "Master")
	end)

	row._currentEntry = entry
	if not row._tooltipHooked then
		row:EnableMouse(true)
		row:HookScript("OnEnter", function(self)
			local e = self._currentEntry
			if not e then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(("sound: %s"):format(e.displayName), 1, 1, 1)
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
	local _, body = browser:BuildTabShell(pane, "Sounds")
	if not body then return end

	local entries = buildList()
	local contentH = math.max(600, #entries * 52 + 200)
	body = browser:MakeScrollable(body, contentH)
	body.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 4, padding = 8 })

	browser:AppendIntro(body,
		("Showing %d sounds (Cairn-private, Cairn-public, third-party LSM). "
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

Browser:RegisterTab("sounds", {
	label = "Sounds",
	order = 50,
	build = build,
})
