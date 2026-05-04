-- $Id: CheckBox.lua 52 2014-04-08 11:52:40Z diesal@reece-tech.com $
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
local TYPE 		= "CheckBox"
local VERSION 	= 1
-- ~~| Button StyleSheets |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local styleSheet = {
	['frame-shadow'] = {
		type			= 'outline',
		layer			= 'BORDER',
		color			= '000000',
		alpha 		= .17,
		offset		= 0,
	},
	['frame-highlight'] = {
		type			= 'texture',
		layer			= 'BORDER',
		gradient		= 'VERTICAL',
		color			= 'ffffff',
		alpha 		= 0,
		alphaEnd		= .07,
		offset		= -1,
	},
	['frame-innerShadow'] = {
		type			= 'texture',
		layer			= 'BORDER',
		color			= '000000',
		offset		= -2,
	},
	['frame-innerColor'] = {
		type			= 'texture',
		layer			= 'BORDER',
		color			= '080808',
		offset		= -3,
	},
}
local checkStyle = {
		type			= 'texture',
		layer			= 'ARTWORK',
		texFile		= 'Guicons',
		texCoord		= {10,5,16,256,128},
		texColor		= 'ffff00',
		offset		= {1,nil,2,nil},
		width			= 16,
		height		= 16,
}
local checkDisabled = {
		type			= 'texture',
		texColor		= 'ffffff',
}
local checkEnabled = {
		type			= 'texture',
		texColor		= 'ffff00',
		aplha			= 1,
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
	["SetChecked"] = function(self,value)
		self.settings.checked = value
		self.frame:SetChecked(value)

		self[self.settings.disabled and "Disable" or "Enable"](self)
	end,
	["GetChecked"] = function(self)
		return self.settings.checked
	end,
	["Disable"] = function(self)
		self.settings.disabled = true
		Style:StyleTexture(self.check,checkDisabled)
		self.frame:Disable()
	end,
	["Enable"] = function(self)
		self.settings.disabled = false
		Style:StyleTexture(self.check,checkEnabled)
		self.frame:Enable()
	end,
	["RegisterForClicks"] = function(self,...)
		self.frame:RegisterForClicks(...)
	end,
}
-- ~~| Button Constructor |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local function Constructor()
	local self 		= Gui:CreateObjectBase(TYPE)
	local frame		= CreateFrame('CheckButton', nil, UIParent)
	self.frame		= frame

	-- ~~ Default Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	self.defaults = {
		height 		= 12,
		width 		= 12,
	}
	-- ~~ Events ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	-- OnAcquire, OnRelease, OnHeightSet, OnWidthSet
	-- OnValueChanged, OnEnter, OnLeave, OnDisable, OnEnable
	-- ~~ Construct ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

	local check = self:CreateRegion("Texture", 'check', frame)
	Style:StyleTexture(check,checkStyle)
	frame:SetCheckedTexture(check)
	frame:SetScript('OnClick', function(this,button,...)
		Gui:OnMouse(this,button)

		if not self.settings.disabled then
			self:SetChecked(not self.settings.checked)

			if self.settings.checked then
				PlaySound("igMainMenuOptionCheckBoxOn")
			else
				PlaySound("igMainMenuOptionCheckBoxOff")
			end

			self:FireEvent("OnValueChanged", self.settings.checked)
		end
	end)
	frame:SetScript('OnEnter', function(this)
		self:FireEvent("OnEnter")
	end)
	frame:SetScript('OnLeave', function(this)
		self:FireEvent("OnLeave")
	end)
	frame:SetScript("OnDisable", function(this)
		self:FireEvent("OnDisable")
	end)
	frame:SetScript("OnEnable", function(this)
		self:FireEvent("OnEnable")
	end)

	-- ~~ Methods ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	for method, func in pairs(methods) do	self[method] = func	end
	-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	return self
end

Gui:RegisterObjectConstructor(TYPE,Constructor,VERSION)