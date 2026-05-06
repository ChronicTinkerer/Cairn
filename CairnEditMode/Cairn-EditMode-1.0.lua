--[[
Cairn-EditMode-1.0

Optional wrapper around LibEditMode (https://github.com/p3lim-wow/LibEditMode).

If LibEditMode is loaded (the user has it installed standalone OR another
addon embedded it), Cairn.EditMode lets your addon register frames as
EditMode-movable. If LibEditMode is NOT loaded, all calls return false /
nil and `IsAvailable()` reports the situation; nothing crashes.

Why optional? LibEditMode is a single-maintainer community library. We
don't want every Cairn user to inherit a hard dependency on it. Authors
who want EditMode integration document LibEditMode as an optional dep
in their own .toc; users who don't install it just don't get the
EditMode UI. Everything else still works.

Public API:

	Cairn.EditMode:IsAvailable()
	    Returns true if LibEditMode is loaded.

	Cairn.EditMode:Register(frame, defaults, callback, [name])
	    Registers a frame as EditMode-movable.
	    frame    : a Frame with a non-nil :GetName()
	    defaults : { point = "CENTER", x = 0, y = 0 } (any subset)
	    callback : function() called when EditMode commits position changes
	    name     : optional display name (defaults to frame:GetName())
	    Returns true on success, false if LibEditMode isn't loaded.

	Cairn.EditMode:Open()
	    Opens Blizzard's Edit Mode panel (works whether LibEditMode is
	    loaded or not, since it just toggles the standard EditMode UI).
]]

local MAJOR, MINOR = "Cairn-EditMode-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Log = LibStub("Cairn-Log-1.0", true)
local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.EditMode") end
	return lib._log
end

-- Lazy lookup so embedded users who load LibEditMode after Cairn don't
-- get a stale "not available" result.
function lib:IsAvailable()
	if self._lib then return true end
	local found = LibStub("LibEditMode", true)
	if found then
		self._lib = found
		return true
	end
	return false
end

function lib:Register(frame, defaults, callback, name)
	if type(frame) ~= "table" or type(frame.GetName) ~= "function" then
		error("Cairn.EditMode:Register: frame must be a Frame", 2)
	end
	local fname = frame:GetName()
	if not fname or fname == "" then
		error("Cairn.EditMode:Register: frame must have a name (call CreateFrame with a name, or frame:SetName)", 2)
	end

	if not self:IsAvailable() then
		if logger() then
			logger():Debug("LibEditMode not loaded; %s will not be EditMode-movable.", name or fname)
		end
		return false
	end

	defaults = defaults or {}
	-- LibEditMode expects { point, x, y }; fill missing with safe defaults.
	local d = {
		point = defaults.point or "CENTER",
		x     = defaults.x     or 0,
		y     = defaults.y     or 0,
	}

	-- LibEditMode:AddFrame(frame, callback, defaults, [name])
	local ok, err = pcall(function()
		self._lib:AddFrame(frame, callback, d, name or fname)
	end)
	if not ok then
		if logger() then
			logger():Error("LibEditMode:AddFrame failed for %s: %s", name or fname, tostring(err))
		end
		return false
	end
	return true
end

function lib:Open()
	if EditModeManagerFrame and ShowUIPanel then
		ShowUIPanel(EditModeManagerFrame)
		return true
	end
	if logger() then
		logger():Warn("Cairn.EditMode:Open: EditModeManagerFrame not available on this client.")
	end
	return false
end
