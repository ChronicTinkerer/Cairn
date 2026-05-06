--[[
Cairn-Gui-Widgets-Standard-2.0

Standard widget bundle for Cairn-Gui-2.0 per Decision 11. This file is
the bundle's LibStub anchor; sibling Widgets/*.lua files register the
actual widget types against Core (Cairn-Gui-2.0).

The bundle's MAJOR matches the Core MAJOR it targets (2.0), to avoid the
trap that earlier MAJOR=1.0 created where the bundle's name didn't
reflect what it actually depended on.

Distinct LibStub MAJOR from Core so consumers can:
	- Depend on just Core (Cairn-Gui-2.0) and ship their own widgets.
	- Depend on Core + Standard for the bundled widget set.
	- Replace Standard with an alternative bundle (e.g.,
	  Cairn-Gui-Widgets-Cyberpunk-2.0) that registers a different
	  visual language under the same widget type names.

Load order in Cairn.toc:
	1. Cairn-Gui-2.0 Core files (LibStub anchor + Mixins + Core APIs)
	2. This file (Cairn-Gui-Widgets-Standard-2.0.lua)  <-- you are here
	3. Each Widgets/*.lua, in any order

Widget files use LibStub("Cairn-Gui-2.0") to get Core, then call
Core:RegisterWidget(name, def) to register themselves.

Status: Day 15B. Button + Label + Container + Window + Checkbox.

History under previous MAJOR (Cairn-Gui-Widgets-Standard-1.0):
	1: Days 8-13 (Button, Label, Container, Window).
	2: Day 14: Checkbox (uses Core MINOR 2's DrawIcon).
	3: Day 15B: Button variants gain `transition = "duration.fast"` so
	   hover / press / disabled animate via the new Animation engine.

Cairn-Gui-Widgets-Standard-2.0 MINOR bumps:
	1: MAJOR rename only. No API changes from 1.0/MINOR=3. Fresh start
	   to align bundle MAJOR with the Core MAJOR it targets.
]]

local MAJOR, MINOR = "Cairn-Gui-Widgets-Standard-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Core = LibStub("Cairn-Gui-2.0", true)
if not Core then
	error("Cairn-Gui-Widgets-Standard-2.0 requires Cairn-Gui-2.0; check Cairn.toc load order")
end

-- Verify Core is at a compatible revision. RequireCore returns false on
-- mismatch and routes a chat error through Cairn-Log; we abort the
-- bundle's registration in that case so misaligned versions don't ship
-- partial widget sets. Bump the minimum here when a widget starts using
-- a Core API added in a later MINOR.
--   Day 14 (MINOR 2): DrawIcon
--   Day 15B (MINOR 3): Animate / transition pre-wire
if not Core:RequireCore("Cairn-Gui-2.0", 3) then
	return
end

lib._core = Core

-- Sibling Widgets/*.lua files reach into this lib for shared helpers
-- when they need them. Day 8 has nothing shared yet; placeholder.
lib._helpers = lib._helpers or {}
