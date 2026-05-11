--[[
Cairn-Gui-Widgets-Secure-2.0

Secure widget bundle per Decision 8. Contains action / macro / unit
buttons that interact with Blizzard's protected-frame system. Sibling
to Cairn-Gui-Widgets-Standard-2.0; consumers depend on whichever (or
both) they need.

The bundle's MAJOR matches the Core MAJOR it targets (2.0). Distinct
LibStub MAJOR from the Standard bundle so consumers can pull just one.

Each widget def carries `secure = true` which causes:
  * The Acquire path runs `checkMixinTaint` over every method to catch
    forbidden API references at registration time.
  * Layout strategies skip the widget during combat.
  * The widget is pre-warmed at PLAYER_LOGIN+0.5s (8 instances default).
  * The cairn namespace gets `_secure = true` for downstream code.

Load order in Cairn.toc:
    1. Cairn-Gui-2.0 Core files (LibStub anchor + Mixins + Core APIs +
       CombatQueue, which registers `lib.Combat`)
    2. This file (Cairn-Gui-Widgets-Secure-2.0.lua)  <-- you are here
    3. Each Widgets/*.lua, in any order

Cairn-Gui-Widgets-Secure-2.0 (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-Widgets-Secure-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Core = LibStub("Cairn-Gui-2.0", true)
if not Core then
	error("Cairn-Gui-Widgets-Secure-2.0 requires Cairn-Gui-2.0; check Cairn.toc load order")
end

-- Verify Core is at a compatible revision. We need Core MINOR >= 17 for
-- the Decision 8 plumbing (def.secure flag, lib.Combat, layout combat
-- skip). Bump the minimum here when a widget starts using a Core API
-- added in a later MINOR.
if not Core:RequireCore("Cairn-Gui-2.0", 17) then
	return
end

lib._core = Core

-- Helper namespace for sibling Widgets/*.lua files. Currently empty;
-- expand as shared helpers emerge (combat-queue dispatch wrappers,
-- action-attribute setters that consult the queue, etc.).
lib._helpers = lib._helpers or {}
