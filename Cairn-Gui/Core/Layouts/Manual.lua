--[[
Cairn-Gui-2.0 / Core / Layouts / Manual

The Manual strategy is a no-op. Children are expected to self-anchor
via SetPoint themselves. Calling SetLayout("Manual") is exactly
equivalent to leaving _layout unset; it exists as an explicit name
for code that prefers stating the intent.

Strategy signature: function(containerCairn, opts)
opts: ignored
]]

local lib = LibStub:GetLibrary("Cairn-Gui-2.0", true)
if not lib then return end

lib:RegisterLayout("Manual", function(_container, _opts)
	-- Intentional no-op.
end)
