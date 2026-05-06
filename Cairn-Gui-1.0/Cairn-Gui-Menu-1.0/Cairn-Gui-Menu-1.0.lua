--[[ Cairn-Gui-Menu-1.0
    Derived from DiesalMenu-1.0 by Diesal (diesal2010), originally
    distributed under the New BSD (3-clause) license:
        $Id: DiesalMenu-1.0.lua 44 2014-02-23 18:42:02Z diesal@reece-tech.com $
        Copyright (c) 2014 Diesal. All rights reserved.

    Modified for Cairn by ChronicTinkerer (2026):
      * Renamed library: DiesalMenu-1.0 -> Cairn-Gui-Menu-1.0.
      * Renamed dependency lookups (DiesalTools / DiesalStyle / DiesalGUI)
        to their Cairn-Gui-* counterparts.
      * Local-variable renames for readability (DiesalMenu -> Menu, etc.).
      * Renamed font globals (DiesalFontNormal -> CairnFontNormal, etc.).
      * (Pending) Per-widget Midnight (Interface 120005) modernization for
        deprecated APIs (SetGradientAlpha, SetTexture(r,g,b), etc.).

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
    3. Neither the name of the original author nor the names of its
       contributors may be used to endorse or promote products derived from
       this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES
    ARE DISCLAIMED. SEE BSD-3-CLAUSE FOR FULL TERMS.
]]
local MAJOR, MINOR = "Cairn-Gui-Menu-1.0", 1
local Menu, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not Menu then return end -- No Upgrade needed.
-- ~~| Libraries |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local Tools = LibStub("Cairn-Gui-Tools-1.0")
local Style = LibStub("Cairn-Gui-Style-1.0")
local Gui 	= LibStub("Cairn-Gui-Core-1.0")
-- ~~| Lua Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local type, select,  tonumber											= type, select, tonumber
local setmetatable, getmetatable, next								= setmetatable, getmetatable, next
local sub, format, lower, upper, match 							= string.sub, string.format, string.lower, string.upper, string.match
local pairs, ipairs														= pairs,ipairs
local tinsert, tremove, tconcat, tsort								= table.insert, table.remove, table.concat, table.sort
local floor, ceil, abs, modf											= math.floor, math.ceil, math.abs, math.modf
-- ~~| WoW Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local CreateFrame, UIParent  											= CreateFrame, UIParent
-- ~~| Menu Values |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	
-- ~~| Menu Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~| Style Locals |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local MENU
local CLOSEDELAY = 2

local closeTimer = CreateFrame('Frame')
closeTimer:Hide()
closeTimer:SetScript('OnUpdate', function(this,elapsed)
	if this.count < 0 then 
		Menu:Close()
		this:Hide()		
	else		
		this.count = this.count - elapsed			
	end	
end)
-- ~~| Menu Local Methods |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

 -- ~~| Menu API |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function Menu:Menu(menuData,anchor,x,y,closeDelay)
	MENU = MENU or Gui:Create('Menu')		
	MENU:ResetSettings()
	MENU:SetSettings({
		check		= menuData.check,
		arrow		= menuData.arrow,			
		menuData	= menuData,							
	},true)	
	
	MENU:Show()		
	MENU:ClearAllPoints()
	MENU:SetPoint('TOPLEFT',anchor,'TOPLEFT',x,y)
	closeTimer.closeDelay = closeDelay or CLOSEDELAY
	Menu:StartCloseTimer()
	Menu:SetFocus()			
end
function Menu:Close()
	Menu:StopCloseTimer()
	if not MENU or not MENU:IsVisible() then return end
	MENU:ResetSettings()
	MENU:ReleaseChildren()	
	MENU:Hide()
	MENU:ClearAllPoints()			
end
function Menu:StartCloseTimer()
	closeTimer.count = closeTimer.closeDelay
	closeTimer:Show()		
end
function Menu:StopCloseTimer()
	closeTimer:Hide()
end
function Menu:ClearFocus()
	Menu:Close()	
end
function Menu:SetFocus()
	Gui:SetFocus(Menu)
end
