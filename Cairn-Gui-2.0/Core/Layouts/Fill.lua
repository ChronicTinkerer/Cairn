--[[
Cairn-Gui-2.0 / Core / Layouts / Fill

The Fill strategy makes the FIRST non-manual child cover the entire
container area, with optional uniform padding.

Strategy signature: function(containerCairn, opts)
opts:
	padding = number, default 0; uniform inset on all four sides.

Use when a container has exactly one significant child that should
occupy the entire space (a window's content area, a panel's body).
Additional children are ignored by this strategy.
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

lib:RegisterLayout("Fill", function(container, opts)
	if not container._children or #container._children == 0 then return end
	local pad        = (opts and opts.padding) or 0
	local containerF = container._frame
	if not containerF then return end

	for _, child in ipairs(container._children) do
		if lib:_isLayoutable(child) then
			local frame = child._frame
			if frame and frame.SetPoint then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT",     containerF, "TOPLEFT",      pad, -pad)
				frame:SetPoint("BOTTOMRIGHT", containerF, "BOTTOMRIGHT", -pad,  pad)
				return  -- Only the first non-manual child fills.
			end
		end
	end
end)
