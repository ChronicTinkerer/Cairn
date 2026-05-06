-- $Id: Button.lua 52 2014-04-08 11:52:40Z diesal@reece-tech.com $
-- Copyright (c) 2014 Diesal. New BSD (3-clause) license.
-- Modified for Cairn by ChronicTinkerer (2026): Diesal* refs renamed to
-- Cairn-Gui-* equivalents; SetFont flags arg added for Interface 120005.
-- Full BSD license text in Cairn-Gui-Core-1.0.lua header.

local Gui = LibStub("Cairn-Gui-Core-1.0")
-- ~~| Libraries |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local Tools = LibStub("Cairn-Gui-Tools-1.0")
local Style = LibStub("Cairn-Gui-Style-1.0")
-- ~~| Lua Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local type, tonumber, select 											= type, tonumber, select 	
local pairs, ipairs, next												= pairs, ipairs, next
local min, max					 											= math.min, math.max	
-- ~~| WoW Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local CreateFrame, UIParent, GetCursorPosition 					= CreateFrame, UIParent, GetCursorPosition
local GetScreenWidth, GetScreenHeight								= GetScreenWidth, GetScreenHeight	
local GetSpellInfo, GetBonusBarOffset, GetDodgeChance			= GetSpellInfo, GetBonusBarOffset, GetDodgeChance
local GetPrimaryTalentTree, GetCombatRatingBonus				= GetPrimaryTalentTree, GetCombatRatingBonus
-- ~~| Button |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local TYPE 		= "Button"
local VERSION 	= 5
-- ~~| Button StyleSheets |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Cairn extension: Diesal's original Button shipped with text-only styling
-- (no background, no border). That works in their own demos because the
-- containing frame paints a backdrop, but in normal WoW addon usage you want
-- the button to LOOK like a button. Add a basic frame-background +
-- frame-outline so freshly-acquired buttons render visible chrome out of
-- the box. Consumers can still override via SetStyle/AddStyleSheet.
local styleSheet = {
	['frame-background'] = {
		type			= 'texture',
		layer			= 'BACKGROUND',
		color			= '202020',
	},
	['frame-outline'] = {
		type			= 'outline',
		layer			= 'BORDER',
		color			= '060606',
	},
	['text-color'] = {
		type			= 'Font',
		color			= 'b8c2cc',
	},
}
local wireFrame = {	
	['frame-white'] = {				
		type			= 'outline',
		layer			= 'OVERLAY',
		color			= 'ffffff',	
	},		
}
-- ~~| Button Methods |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local methods = {		
	['OnAcquire'] = function(self)			
		self:ApplySettings()
		self:AddStyleSheet(styleSheet)
		self:Enable()
		-- self:AddStyleSheet(wireFrameSheet)			
		self:Show()		
	end,
	['OnRelease'] = function(self)		
		
	end,	
	['ApplySettings'] = function(self)		
		local settings 	= self.settings
		local frame 		= self.frame	
		
		self:SetWidth(settings.width)
		self:SetHeight(settings.height)								
	end,	
	["SetText"] = function(self, text)
		self.text:SetText(text)
	end,
	["Disable"] = function(self)
		self.settings.disabled = true
		self.frame:Disable()		
	end,
	["Enable"] = function(self)
		self.settings.disabled = false
		self.frame:Enable()		
	end,
	["RegisterForClicks"] = function(self,...)		
		self.frame:RegisterForClicks(...)		
	end,				
}
-- ~~| Button Constructor |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local function Constructor(name)	
	local self 		= Gui:CreateObjectBase(TYPE)
	local frame		= CreateFrame('Button',name,UIParent)		
	self.frame		= frame	
	self.defaults = {		
		height 			= 32,
		width 			= 32,
	}	
	-- ~~ Events ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- OnAcquire, OnRelease, OnHeightSet, OnWidthSet	
	-- OnClick, OnEnter, OnLeave, OnDisable, OnEnable 	
	-- ~~ Construct ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
	local text = self:CreateRegion("FontString", 'text', frame)		
	text:SetPoint("TOPLEFT", 4, -2)
	text:SetPoint("BOTTOMRIGHT", -4, 0)
	text:SetJustifyV("MIDDLE")	
	frame:SetFontString(text)
	
	frame:SetScript("OnClick", function(this,button,...)
		Gui:OnMouse(this,button)
		-- PlaySound("ACTIONBARBUTTONDOWN") was the upstream Diesal call. Modern
		-- Retail (Midnight, Interface 120005) treats the string-name form as
		-- invalid and may throw; if it throws, the rest of OnClick (FireEvent)
		-- never runs and the consumer's click handler silently fails. Wrap in
		-- pcall so a sound failure can't take the click out.
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 856)
		self:FireEvent("OnClick",button,...)
	end)
	frame:SetScript("OnEnter", function(this)
		self:FireEvent("OnEnter")	
	end)
	frame:SetScript("OnLeave", function(this)
		self:FireEvent("OnLeave")	
	end)
	frame:SetScript("OnDisable", function(this)
		self:FireEvent("OnDisable")	
	end)
	frame:SetScript("OnEnable", function(this)
		self:FireEvent("OnEnable")	
	end)	
	-- ~~ Methods ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	for method, func in pairs(methods) do	self[method] = func	end
	-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	return self
end
	
Gui:RegisterObjectConstructor(TYPE,Constructor,VERSION)