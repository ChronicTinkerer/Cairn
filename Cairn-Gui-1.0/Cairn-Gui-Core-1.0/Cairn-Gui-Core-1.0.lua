--[[ Cairn-Gui-Core-1.0
    Derived from DiesalGUI-1.0 by Diesal (diesal2010), originally
    distributed under the New BSD (3-clause) license:
        $Id: DiesalGUI-1.0.lua 52 2014-04-08 11:52:40Z diesal@reece-tech.com $
        Copyright (c) 2014 Diesal. All rights reserved.

    Modified for Cairn by ChronicTinkerer (2026):
      * Renamed library: DiesalGUI-1.0 -> Cairn-Gui-Core-1.0.
      * Renamed dependency lookups (DiesalTools / DiesalStyle) to their
        Cairn-Gui-* counterparts.
      * Local-variable renames for readability (DiesalGUI -> Gui, etc.).
      * Renamed font globals (DiesalFontNormal -> CairnFontNormal, etc.).
      * Renamed callback name "DiesalGUI_OnMouse" -> "Cairn_Gui_OnMouse".
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
local MAJOR, MINOR = "Cairn-Gui-Core-1.0", 1
local Gui, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not Gui then return end -- No Upgrade needed.
-- ~~| Libraries |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local CallbackHandler = LibStub("CallbackHandler-1.0")
local Tools 		= LibStub("Cairn-Gui-Tools-1.0")
local Style 		= LibStub("Cairn-Gui-Style-1.0")
-- ~~| Lua Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local type, select,  tonumber									= type, select, tonumber
local setmetatable, getmetatable, next				= setmetatable, getmetatable, next
local pairs, ipairs														= pairs,ipairs
local tinsert, tremove												= table.insert, table.remove
-- ~~| WoW Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local CreateFrame, UIParent  									= CreateFrame, UIParent
-- ~~| Gui Values |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Gui.callbacks 			= Gui.callbacks 			or CallbackHandler:New(Gui)
Gui.ObjectFactory 	= Gui.ObjectFactory 	or {}
Gui.ObjectVersions	= Gui.ObjectVersions	or {}
Gui.ObjectPool		 	= Gui.ObjectPool		 	or {}
Gui.ObjectBase			= Gui.ObjectBase			or {}
-- ~~| Gui Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local ObjectFactory 			= Gui.ObjectFactory
local ObjectVersions 			= Gui.ObjectVersions
local ObjectPool 					= Gui.ObjectPool
local ObjectBase 					= Gui.ObjectBase
-- ~~| Gui Local Methods |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
local function OnMouse(frame,button)	
	Gui:ClearFocus()
end
-- capture mouse clicks on the WorldFrame
local function WorldFrameOnMouse(frame,button)
	-- print(button)
	OnMouse(frame,button)	
end	
_G.WorldFrame:HookScript("OnMouseDown", WorldFrameOnMouse )   
-- Returns a new object
local function newObject(objectType)
	if not ObjectFactory[objectType] then error("Attempt to construct unknown Object type", 2) end		
	
	ObjectPool[objectType] = ObjectPool[objectType] or {}	
	
	local newObj = next(ObjectPool[objectType])
	if not newObj then
		newObj = ObjectFactory[objectType](object)			
	else
		ObjectPool[objectType][newObj] = nil		
	end
	
	return newObj
end
-- Releases an object into ReleasedObjects
local function releaseObject(obj,objectType)	
	ObjectPool[objectType] = ObjectPool[objectType] or {}
	
	if ObjectPool[objectType][obj] then
		error("Attempt to Release Object that is already released", 2)
	end
	ObjectPool[objectType][obj] = true
end
-- ~~| Object Blizzard Base |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ObjectBase.Hide = function(self)
	self.frame:Hide()	
end	
ObjectBase.Show = function(self)
	self.frame:Show()	
end	
ObjectBase.SetParent = function(self, parent)
	local frame = self.frame
	frame:SetParent(nil)
	frame:SetParent(parent)
	self.settings.parent = parent	
end	
ObjectBase.SetWidth = function(self, width)	
	self.settings.width = width
	self.frame:SetWidth(width)	
	self:FireEvent("OnWidthSet",width)
end	
ObjectBase.SetHeight = function(self, height)
	self.settings.height = height	
	self.frame:SetHeight(height)		
	self:FireEvent("OnHeightSet",height)
end
ObjectBase.GetWidth = function(self)
	return self.frame:GetWidth()	
end	
ObjectBase.GetHeight = function(self)
	return self.frame:GetHeight()	
end
ObjectBase.IsVisible = function(self)
	return self.frame:IsVisible()
end
ObjectBase.IsShown = function(self)
	return self.frame:IsShown()
end
ObjectBase.SetPoint = function(self, ...)
	return self.frame:SetPoint(...)
end
ObjectBase.SetAllPoints = function(self, ...)
	return self.frame:SetAllPoints(...)
end
ObjectBase.ClearAllPoints = function(self)
	return self.frame:ClearAllPoints()
end
ObjectBase.GetNumPoints = function(self)
	return self.frame:GetNumPoints()
end	
ObjectBase.GetPoint = function(self, ...)
	return self.frame:GetPoint(...)
end
-- ~~| Object Base |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ObjectBase.CreateRegion = function(self,regionType,regionName,parentRegion,defaultFontObject)
	if regionType == 'FontString' then
		local fontString = parentRegion:CreateFontString()
		-- set Default font properties
		if defaultFontObject then			
			fontString.defaultFontObject = defaultFontObject
		else
			fontString.defaultFontObject = CairnFontNormal			
		end
		fontString:SetFont(fontString.defaultFontObject:GetFont())
		fontString:SetTextColor(fontString.defaultFontObject:GetTextColor())
		fontString:SetSpacing(fontString.defaultFontObject:GetSpacing())
			
		self[regionName] = fontString
		self.fontStrings[regionName] = fontString
		return fontString	
	end
	if regionType == 'Texture' then
		self[regionName] = parentRegion:CreateTexture()		
		return self[regionName]	
	end
	if regionType == 'EditBox' then
		local editBox = CreateFrame(regionType,nil,parentRegion)	
		-- set Default font properties
		if defaultFontObject then			
			editBox.defaultFontObject = defaultFontObject
		else
			editBox.defaultFontObject = CairnFontNormal			
		end
		editBox:SetFont(editBox.defaultFontObject:GetFont())
		editBox:SetTextColor(editBox.defaultFontObject:GetTextColor())
		editBox:SetSpacing(editBox.defaultFontObject:GetSpacing())
		editBox:HookScript('OnEscapePressed', 	function(this)	Gui:ClearFocus();	end)	
		editBox:HookScript('OnEditFocusGained',function(this)	Gui:SetFocus(this); GameTooltip:Hide(); end)	

		self[regionName] = editBox		
		return editBox	
	end
	if regionType == 'ScrollingMessageFrame' then
		local srollingMessageFrame = CreateFrame(regionType,nil,parentRegion)	
		-- set Default font properties
		if defaultFontObject then			
			srollingMessageFrame.defaultFontObject = defaultFontObject
		else
			srollingMessageFrame.defaultFontObject = CairnFontNormal			
		end
		srollingMessageFrame:SetFont(srollingMessageFrame.defaultFontObject:GetFont())
		srollingMessageFrame:SetTextColor(srollingMessageFrame.defaultFontObject:GetTextColor())
		srollingMessageFrame:SetSpacing(srollingMessageFrame.defaultFontObject:GetSpacing())
		
		self[regionName] = srollingMessageFrame		
		return srollingMessageFrame	
	end		
		
	self[regionName] = CreateFrame(regionType,nil,parentRegion)		
	return self[regionName]
end
ObjectBase.ResetFonts = function(self)	
	for name,fontString in pairs(self.fontStrings) do
		fontString:SetFont(fontString.defaultFontObject:GetFont())
		fontString:SetTextColor(fontString.defaultFontObject:GetTextColor())
		fontString:SetSpacing(fontString.defaultFontObject:GetSpacing())
	end	
end
ObjectBase.AddChild = function(self, object)	
	tinsert(self.children, object)
end
ObjectBase.ReleaseChild = function(self,object)
	local children = self.children
	
	for i = 1,#children do
		if children[i] == object then
			children[i]:Release()
			tremove(children,i)			
		break end	
	end		
end	
ObjectBase.ReleaseChildren = function(self)
	local children = self.children	
	for i = 1,#children do
		children[i]:Release()
		children[i] = nil
	end
end
ObjectBase.Release = function(self)		
	Gui:Release(self)
end
ObjectBase.SetParentObject = function(self, parent)
	local frame = self.frame
	local settings = self.settings
	
	frame:SetParent(nil)
	frame:SetParent(parent.content)	
	settings.parent 			= parent.content	
	settings.parentObject 	= parent	
end
ObjectBase.SetSettings = function(self,settings,apply)					
	for key,value in pairs(settings) do
		self.settings[key] = value
	end
	if apply then self:ApplySettings() end									
end
ObjectBase.ResetSettings = function(self,apply)					
	self.settings = Tools:TableCopy( self.defaults )
	if apply then self:ApplySettings() end									
end
ObjectBase.SetEventListener = function(self, event, listener)	
	if type(listener) == "function" then
		self.eventListeners[event] = listener
	else 
		error("listener is required to be a function", 2)
	end
end
ObjectBase.ResetEventListeners = function(self)	
	for k in pairs(self.eventListeners) do
		self.eventListeners[k] = nil
	end	
end	
ObjectBase.FireEvent = function(self, event, ...)	
	if self.eventListeners[event] then
		return self.eventListeners[event]( self, event, ...)				
	end
end
ObjectBase.SetStyle = function(self,name,style)
	Style:SetObjectStyle(self,name,style)		
end
ObjectBase.AddStyleSheet = function(self,stylesheet)
	for name,style in pairs(stylesheet) do 
		self:SetStyle(name,style)		
	end
end
ObjectBase.ReleaseTexture = function(self,name)
	if not self.textures[name] then return end
	Style:ReleaseTexture(self,name)
end
ObjectBase.ReleaseTextures = function(self)
	Style:ReleaseTextures(self)
end
-- ~~| Gui API |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Returns an Object Base	
function Gui:CreateObjectBase(Type)	
	local object = {	
		type						= Type,		
		fontStrings			= {},	
		textures 				= {},
		children 				= {},		
		eventListeners	= {},		
	}
	setmetatable(object, {__index = ObjectBase})
	return object
end
-- Registers an Object constructor in the ObjectFactory
function Gui:RegisterObjectConstructor(Type, constructor, version)
	assert(type(constructor) == "function")
	assert(type(version) == "number") 
	
	local oldVersion = ObjectVersions[Type]
	if oldVersion and oldVersion >= version then return end
	
	ObjectVersions[Type] = version		
	ObjectFactory[Type]	= constructor
end
-- Create a new Object
function Gui:Create(objectType,name)	
	if ObjectFactory[objectType] then
		local object
		if name then -- needs a specific name, bypass the objectPool and create a new object
			object = ObjectFactory[objectType](name)			
		else
			object = newObject(objectType)
		end
		object:ResetSettings()	
		-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
		if object.OnAcquire then object:OnAcquire() end
		return object
	end
end
-- Releases an object ready for reuse by Create
function Gui:Release(object)
	if object.OnRelease then object:OnRelease()	end
	object:FireEvent("OnRelease")
	
	object:ReleaseChildren()		
	object:ReleaseTextures()
	object:ResetFonts()	
	object:ResetEventListeners()
			
	object.frame:ClearAllPoints()
	object.frame:Hide()
	object.frame:SetParent(UIParent)	
	releaseObject(object, object.type)
end
-- Set FocusedObject: Menu, Dropdown, editBox etc....
function Gui:SetFocus(object)	
	if self.FocusedObject and self.FocusedObject ~= object then	Gui:ClearFocus() end
	self.FocusedObject = object
end
-- clear focus from the FocusedObject
function Gui:ClearFocus()
	local FocusedObject = self.FocusedObject
	if FocusedObject then		
		if FocusedObject.ClearFocus then 			-- FocusedObject is Focusable Frame
			FocusedObject:ClearFocus() 		
		end		
		self.FocusedObject = nil
	end
end
-- Mouse Input capture for any Gui interactive region
function Gui:OnMouse(frame,button)
	-- print(button)
	OnMouse(frame,button)	
	Gui.callbacks:Fire("Cairn_Gui_OnMouse", frame, button)
end

Gui.counts = Gui.counts or {}
--- A type-based counter to count the number of widgets created.
function Gui:GetNextObjectNum(type)
	if not self.counts[type] then
		self.counts[type] = 0
	end
	self.counts[type] = self.counts[type] + 1
	return self.counts[type]
end
--- Return the number of created widgets for this type.
function Gui:GetObjectCount(type)
	return self.counts[type] or 0
end