--[[
Cairn-Gui-Layouts-Extra-2.0

Optional bundle of additional layout strategies. Sibling to the Standard
widget bundle and the Secure widget bundle; consumers depend on whichever
they need (or none). Each strategy registers against Core via the same
lib:RegisterLayout API that the built-in strategies use.

Bundled strategies:

	Hex   -- hexagonal grid arrangement (pointy-top or flat-top).
	Polar -- radial / circular arrangement around a center point.

Use cases: HUD layouts, hex-grid mini-maps, ability-radial menus.

Load order in Cairn.toc:
    1. Cairn-Gui-2.0 Core (Layout.lua + the lib:_isLayoutable helper)
    2. This file (bundle anchor)
    3. Each Layouts/*.lua

Cairn-Gui-Layouts-Extra-2.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-Layouts-Extra-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Core = LibStub("Cairn-Gui-2.0", true)
if not Core then
	error("Cairn-Gui-Layouts-Extra-2.0 requires Cairn-Gui-2.0; check Cairn.toc load order")
end

-- Bundle requires Core MINOR >= 18 for the round-out tasks landing here
-- (lib:_isLayoutable was introduced in MINOR 17 and is what these
-- strategies rely on for combat-skip behavior).
if not Core:RequireCore("Cairn-Gui-2.0", 17) then
	return
end

lib._core = Core
