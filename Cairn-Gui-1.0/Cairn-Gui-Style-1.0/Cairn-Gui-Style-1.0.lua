--[[ Cairn-Gui-Style-1.0
    Texture / outline / FontString styling helpers and a small per-frame
    media registry. Used by the Cairn-Gui-* widget family for visuals.

    --- Provenance ----------------------------------------------------------
    Derived from DiesalStyle-1.0 by Diesal (diesal2010), originally
    distributed under the New BSD (3-clause) license:
        $Id: DiesalStyle-1.0.lua 52 2014-04-08 11:52:40Z diesal@reece-tech.com $
        Copyright (c) 2014 Diesal. All rights reserved.

    Modified for Cairn by ChronicTinkerer (2026):
      * Renamed library: DiesalStyle-1.0 -> Cairn-Gui-Style-1.0.
      * Renamed Tools dependency: DiesalTools-1.0 -> Cairn-Gui-Tools-1.0.
      * Local lib variable renamed DiesalStyle -> Style for readability.
      * Renamed icon-sheet asset: DiesalGUIcons -> CairnGUIcons.
      * Dropped the bundled calibrib.ttf (proprietary Microsoft Calibri
        Bold). The default body-text font now resolves to WoW built-in
        STANDARD_TEXT_FONT, which is locale-aware and always available.
      * Kept Standard0755.ttf (by 04 / Yuji Oshimoto, free for non-
        commercial use) and FFF Intelligent Thin Condensed.ttf (FFFoundation
        / Magnus Cederholm, free for personal/non-commercial use) since
        Cairn is non-commercial and freely distributed. Both are
        registered with LibSharedMedia under their original names.
      * (Pending) Modernization for WoW Interface 120005: SetGradientAlpha
        / SetTexture(r,g,b) calls need migration to SetGradient and
        SetColorTexture respectively.

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

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES HOWSOEVER CAUSED AND ON
    ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
    TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
    THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
    DAMAGE.
]]
local MAJOR, MINOR = "Cairn-Gui-Style-1.0", 1
local Style, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not Style then return end -- No Upgrade needed.
-- ~~| Libraries |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local Tools 	= LibStub("Cairn-Gui-Tools-1.0")
local LibSharedMedia = LibStub("LibSharedMedia-3.0")
-- ~~| Lua Upvalues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local type, select, pairs, tonumber									= type, select, pairs, tonumber
local next																	= next
-- ~~| Style Values |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Style.Media							= Style.Media							or {} 
Style.ReleasedTextures	= Style.ReleasedTextures	or {} 
Style.TextureFrame			= Style.TextureFrame 			or CreateFrame("Frame"); Style.TextureFrame:Hide();
-- ~~| Style UpValues |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local AddonName 			= ...
local ReleasedTextures= Style.ReleasedTextures
local TextureFrame		= Style.TextureFrame
local Media						= Style.Media
-- ~~| Style Locals |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local OUTLINES 			= {'_LEFT','_RIGHT','_TOP','_BOTTOM'}
-- ~~| Style Media |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
local MediaPath = string.format("Interface\\AddOns\\%s\\%s\\Media\\", AddonName, MAJOR)
-- Cairn-Gui-Style ships at the addon root (e.g. Cairn/Cairn-Gui-Style-1.0/Media/),
-- not under a Libs/ subfolder, so a single-form path is sufficient.
local function addMedia(mediaType,name,mediaFile)	
	Media[mediaType] = Media[mediaType] or {}	 
	-- update or create new media entry
	Media[mediaType][name] = MediaPath..mediaFile	
end
local function getMedia(mediaType,name)
	if not Media[mediaType] then error('media type: '..mediaType..' does not exist',2)	return end
	if not Media[mediaType][name] then error('media: "'..name..'" does not exist',2)	return end	
	return Media[mediaType][name]
end
-- ~~ Addmedia ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Calibri (proprietary Microsoft) was dropped during the fork. The two
-- pixel fonts (Standard0755 by 04 / Yuji Oshimoto, FFF Intelligent by
-- FFFoundation) are kept since both are freely redistributable for
-- non-commercial use, which Cairn is.
addMedia('font', 'Standard0755', 'Standard0755.ttf')
addMedia('font', 'FFF Intelligent Thin Condensed', 'FFF Intelligent Thin Condensed.ttf')
addMedia('texture', 'CairnGUIcons', 'CairnGUIcons16x256x128.tga')
addMedia('border', 'shadow', 'shadow.tga')
addMedia('border', 'shadowNoDist', 'shadowNoDist.tga')
-- ~~ SharedMedia registration ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
LibSharedMedia:Register("font", "Standard0755",     getMedia('font', 'Standard0755'))
LibSharedMedia:Register("font", "FFF Intelligent",  getMedia('font', 'FFF Intelligent Thin Condensed'))
-- ~~ Cairn font objects ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- STANDARD_TEXT_FONT is a built-in WoW global that always resolves to a
-- usable, locale-aware font path -- a clean replacement for the dropped
-- Calibri default.
-- WoW Interface 120005 requires the third 'flags' argument on SetFont.
-- Use empty string for no flags.
CreateFont("CairnFontNormal")
CairnFontNormal:SetFont(STANDARD_TEXT_FONT, 11, "")
CreateFont("CairnFontPixel")
CairnFontPixel:SetFont(getMedia('font', 'Standard0755'), 8, "")
CreateFont("CairnFontPixel2")
CairnFontPixel2:SetFont(getMedia('font', 'FFF Intelligent Thin Condensed'), 8, "OUTLINE, MONOCHROME")
-- ~~| Internal methods |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Returns new Texture
local function newTexture()	
	local newTexture = next(ReleasedTextures)
	if not newTexture then
		newTexture = TextureFrame:CreateTexture()	
	else
		newTexture:Show()
		ReleasedTextures[newTexture] = nil		
	end	
	return newTexture
end
-- Releases Texture
local function releaseTexture(texture)	
	-- reset texture	
	texture:ClearAllPoints()
	texture:SetTexture(nil)
	texture:SetDrawLayer("ARTWORK", 0)
	texture:SetTexCoord(0,1,0,1)			
	texture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
		
	texture:SetParent(TextureFrame)	
	texture:Hide()
	texture.style = nil
	
	if ReleasedTextures[texture] then
		error("Attempt to Release a texture that is already released", 2)
	end
	ReleasedTextures[texture] = true
end
-- ~~| Style API |~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--[[ Texture style table format
	style.layer				BACKGROUND | BORDER | ARTWORK | OVERLAY | HIGHLIGHT (texture in this layer is automatically shown when the mouse is over the containing Frame)
	**FontStrings always appear on top of all textures in a given draw layer. avoid using sublayer
	-- ~~ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
	style.alpha				alpha [0 - 1]
	style.alphaEnd			alpha [0 - 1]	
	style.color				hexColor | {Red, Green, Blue} [0-255]
	style.colorEnd			hexColor | {Red, Green, Blue} [0-255]
	style.gradient			VERTICAL | HORIZONTAL
	-- ~~ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
	style.texFile			texture fileName
	style.texTile			true | false	
	style.texCoord			{left, right, top, bottom} [0-1] | {column,row,size,textureWidth,TextureHeight}
	style.texColor			hexColor | {Red,Green,Blue} [0-255]
	style.texColorAlpha	alpha [0 - 1]
	-- ~~ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
	style.offset			offset | {Left, Right, Top, Bottom}
	style.width				width
	style.height			height	
]]
function Style:StyleTexture(texture,style)
	if not texture.style or style.clear then texture.style = {}	end			
		local textureStyle = texture.style			
		-- ~~ Format New Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
		local red,green,blue									= Tools:GetColor(style.color)		
		local redEnd,greenEnd,blueEnd						= Tools:GetColor(style.colorEnd)
		local texColorRed,texColorGreen,texColorBlue	= Tools:GetColor(style.texColor)		
		local offset											= style.offset and type(style.offset)=='number' and {style.offset,style.offset,style.offset,style.offset} or style.offset		
		if type(style.texCoord) == 'table' and #style.texCoord > 4 then style.texCoord = Tools:Pack(Tools:GetIconCoords(style.texCoord[1],style.texCoord[2],style.texCoord[3],style.texCoord[4],style.texCoord[5]))	end 
	-- Setting ~~~~~~~~~~~~~~~~~~~~~~~ New Setting ~~~~~~~~~~~~~~~ Old Setting ~~~~~~~~~~~~~~~~~ Default ~~~~~~~~~~~~~~~~~~
		textureStyle.layer				= style.layer					or textureStyle.layer					or 'ARTWORK'						
					
		textureStyle.red					= red									or textureStyle.red			
		textureStyle.green				= green								or textureStyle.green		
		textureStyle.blue					= blue								or textureStyle.blue
		textureStyle.alpha				= style.alpha					or textureStyle.alpha					or 1 						
		textureStyle.redEnd				= redEnd							or textureStyle.redEnd				or textureStyle.red	 	
		textureStyle.greenEnd			= greenEnd						or textureStyle.greenEnd			or textureStyle.green
		textureStyle.blueEnd			= blueEnd							or textureStyle.blueEnd				or textureStyle.blue
		textureStyle.alphaEnd			= style.alphaEnd			or textureStyle.alphaEnd			or textureStyle.alpha
		textureStyle.gradient			= style.gradient			or textureStyle.gradient
		
		textureStyle.texFile			= style.texFile				or textureStyle.texFile	
		textureStyle.texTile			= style.texTile				or textureStyle.texTile
		textureStyle.texCoord			= style.texCoord			or textureStyle.texCoord			or	{0,1,0,1}
		textureStyle.texColorRed	= texColorRed					or textureStyle.texColorRed		or 1
		textureStyle.texColorGreen= texColorGreen				or textureStyle.texColorGreen	or 1		
		textureStyle.texColorBlue	= texColorBlue				or textureStyle.texColorBlue	or 1	
		textureStyle.texColorAlpha= style.texColorAlpha	or textureStyle.texColorAlpha	or 1
		
		textureStyle.offset				= offset							or textureStyle.offset				or {0,0,0,0} 	
		textureStyle.width				= style.width					or textureStyle.width
		textureStyle.height				= style.height				or textureStyle.height		
		-- ~~ Apply Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
		texture:ClearAllPoints()
		texture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))	
		texture:SetDrawLayer(textureStyle.layer, 0)	
		texture:SetVertexColor(textureStyle.texColorRed,textureStyle.texColorGreen,textureStyle.texColorBlue,textureStyle.texColorAlpha)	
		texture:SetTexCoord(textureStyle.texCoord[1],textureStyle.texCoord[2],textureStyle.texCoord[3],textureStyle.texCoord[4])	
		texture:SetAlpha(textureStyle.alpha)
			
		if textureStyle.offset[1] 	then texture:SetPoint("LEFT", 	-textureStyle.offset[1],0) 		end
		if textureStyle.offset[2] 	then texture:SetPoint("RIGHT", 	textureStyle.offset[2],0) 		end
		if textureStyle.offset[3] 	then texture:SetPoint("TOP", 		0,textureStyle.offset[3])			end		
		if textureStyle.offset[4]		then texture:SetPoint("BOTTOM", 	0,-textureStyle.offset[4]) 	end
		if textureStyle.width 			then texture:SetWidth(textureStyle.width) 										end
		if textureStyle.height			then texture:SetHeight(textureStyle.height) 									end		
		if textureStyle.texFile then 
			if Media.texture[textureStyle.texFile] then textureStyle.texFile = Media.texture[textureStyle.texFile] end		
			texture:SetTexture(textureStyle.texFile,textureStyle.texTile)			
			texture:SetHorizTile(textureStyle.texTile)
			texture:SetVertTile(textureStyle.texTile)		
		else		
			texture:SetColorTexture(textureStyle.red,textureStyle.green,textureStyle.blue)	
		end
		if textureStyle.gradient then
			texture:SetAlpha(1)
			texture:SetColorTexture(1,1,1,1)
			texture:SetGradient(textureStyle.gradient, CreateColor(textureStyle.red, textureStyle.green, textureStyle.blue, textureStyle.alpha), CreateColor(textureStyle.redEnd, textureStyle.greenEnd, textureStyle.blueEnd, textureStyle.alphaEnd))		
		end	
end
function Style:StyleOutline(leftTexture,rightTexture,topTexture,bottomTexture,style)
	if not leftTexture.style or style.clear then leftTexture.style = {}	end			
	local textureStyle = leftTexture.style			
	-- ~~ Format New Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	local red,green,blue									= Tools:GetColor(style.color)		
	local redEnd,greenEnd,blueEnd						= Tools:GetColor(style.colorEnd)
	local offset											= style.offset and type(style.offset)=='number' and {style.offset,style.offset,style.offset,style.offset} or style.offset	
-- Setting ~~~~~~~~~~~~~~~~~~~~~~~ New Setting ~~~~~~~~~~~~~~~ Old Setting ~~~~~~~~~~~~~~~~~ Default ~~~~~~~~~~~~~~~
	textureStyle.layer			= style.layer				or textureStyle.layer			or 'ARTWORK'	
	
	textureStyle.red				= red							or textureStyle.red			
	textureStyle.green			= green						or textureStyle.green		
	textureStyle.blue				= blue						or textureStyle.blue
	textureStyle.alpha			= style.alpha				or textureStyle.alpha			or 1					
	textureStyle.redEnd			= redEnd						or textureStyle.redEnd			or textureStyle.red	 	
	textureStyle.greenEnd		= greenEnd					or textureStyle.greenEnd		or textureStyle.green
	textureStyle.blueEnd			= blueEnd					or textureStyle.blueEnd			or textureStyle.blue
	textureStyle.alphaEnd		= style.alphaEnd			or textureStyle.alphaEnd		or textureStyle.alpha
	textureStyle.gradient		= style.gradient			or textureStyle.gradient						
	
	textureStyle.offset			= offset						or textureStyle.offset			or {0,0,0,0} 	
	textureStyle.width			= style.width				or textureStyle.width
	textureStyle.height			= style.height				or textureStyle.height		
	-- ~~ Apply Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~		
	leftTexture:ClearAllPoints()
	leftTexture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))	
	leftTexture:SetDrawLayer(textureStyle.layer, 0)
	leftTexture:SetWidth(1)	
	leftTexture:SetColorTexture(textureStyle.red,textureStyle.green,textureStyle.blue)
	leftTexture:SetAlpha(textureStyle.alpha)				
	if textureStyle.offset[1] 	then leftTexture:SetPoint("LEFT", 		-textureStyle.offset[1],0) 	
	else								  		  leftTexture:SetPoint("RIGHT", 	-textureStyle.width,0)		end	
	if textureStyle.offset[3] 	then leftTexture:SetPoint("TOP", 		0,textureStyle.offset[3])	end		
	if textureStyle.offset[4]	then leftTexture:SetPoint("BOTTOM", 	0,-textureStyle.offset[4]) end	
	if textureStyle.height		then leftTexture:SetHeight(textureStyle.height) 						end		
	if textureStyle.gradient =='VERTICAL' then
		leftTexture:SetAlpha(1)
		leftTexture:SetColorTexture(1,1,1,1)
		leftTexture:SetGradient(textureStyle.gradient, CreateColor(textureStyle.red, textureStyle.green, textureStyle.blue, textureStyle.alpha), CreateColor(textureStyle.redEnd, textureStyle.greenEnd, textureStyle.blueEnd, textureStyle.alphaEnd))		
	end

	rightTexture:ClearAllPoints()
	rightTexture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))		
	rightTexture:SetDrawLayer(textureStyle.layer, 0)
	rightTexture:SetWidth(1)	
	rightTexture:SetColorTexture(textureStyle.red,textureStyle.green,textureStyle.blue)
	rightTexture:SetAlpha(textureStyle.alpha)			
	if textureStyle.offset[2] 	then rightTexture:SetPoint("RIGHT", 	textureStyle.offset[2],0) 	
	else								  	  rightTexture:SetPoint("LEFT", 		textureStyle.width-(textureStyle.offset[1]+1),0)	end
	if textureStyle.offset[3] 	then rightTexture:SetPoint("TOP", 		0,textureStyle.offset[3])	end		
	if textureStyle.offset[4]	then rightTexture:SetPoint("BOTTOM", 	0,-textureStyle.offset[4]) end		
	if textureStyle.height		then rightTexture:SetHeight(textureStyle.height) 						end		
	if textureStyle.gradient then 		
		if textureStyle.gradient =='VERTICAL' then
			rightTexture:SetAlpha(1)
			rightTexture:SetColorTexture(1,1,1,1)
			rightTexture:SetGradient(textureStyle.gradient, CreateColor(textureStyle.red, textureStyle.green, textureStyle.blue, textureStyle.alpha), CreateColor(textureStyle.redEnd, textureStyle.greenEnd, textureStyle.blueEnd, textureStyle.alphaEnd))		
		else -- HORIZONTAL
			rightTexture:SetAlpha(textureStyle.alphaEnd)
			rightTexture:SetColorTexture(textureStyle.redEnd,textureStyle.greenEnd,textureStyle.blueEnd)
		end	 		
	end
	
	topTexture:ClearAllPoints()
	topTexture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))				
	topTexture:SetDrawLayer(textureStyle.layer, 0)
	topTexture:SetHeight(1)	
	topTexture:SetColorTexture(textureStyle.red,textureStyle.green,textureStyle.blue)
	topTexture:SetAlpha(textureStyle.alpha)		
	if textureStyle.offset[1] 	then topTexture:SetPoint("LEFT", 		-textureStyle.offset[1]+1,0) 	end	
	if textureStyle.offset[2] 	then topTexture:SetPoint("RIGHT", 		(textureStyle.offset[2])-1,0) end	
	if textureStyle.offset[3] 	then topTexture:SetPoint("TOP", 		0,textureStyle.offset[3])		
	else								  		  topTexture:SetPoint("BOTTOM", 	0,textureStyle.height-1)		end	
	if textureStyle.width		then topTexture:SetWidth(textureStyle.width-2) 								end		
	if textureStyle.gradient then 		
		if textureStyle.gradient =='HORIZONTAL' then
			topTexture:SetAlpha(1)
			topTexture:SetColorTexture(1,1,1,1)
			topTexture:SetGradient(textureStyle.gradient, CreateColor(textureStyle.red, textureStyle.green, textureStyle.blue, textureStyle.alpha), CreateColor(textureStyle.redEnd, textureStyle.greenEnd, textureStyle.blueEnd, textureStyle.alphaEnd))		
		else -- VERTICAL							
			topTexture:SetAlpha(textureStyle.alphaEnd)
			topTexture:SetColorTexture(textureStyle.redEnd,textureStyle.greenEnd,textureStyle.blueEnd)
		end	 		
	end
	
	bottomTexture:ClearAllPoints()
	bottomTexture:SetGradient('HORIZONTAL', CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))				
	bottomTexture:SetDrawLayer(textureStyle.layer, 0)
	bottomTexture:SetHeight(1)	
	bottomTexture:SetColorTexture(textureStyle.red,textureStyle.green,textureStyle.blue)
	bottomTexture:SetAlpha(textureStyle.alpha)		
	if textureStyle.offset[1] 	then bottomTexture:SetPoint("LEFT", 		-textureStyle.offset[1]+1,0) 	end	
	if textureStyle.offset[2] 	then bottomTexture:SetPoint("RIGHT", 		textureStyle.offset[2]-1,0) 	end	
	if textureStyle.offset[4]	then bottomTexture:SetPoint("BOTTOM", 	0,-textureStyle.offset[4])
	else								  	  bottomTexture:SetPoint("TOP", 		0,-(textureStyle.height+1)+(textureStyle.offset[3]+2))	end			
	if textureStyle.width		then bottomTexture:SetWidth(textureStyle.width-2) 								end		
	if style.gradient =='HORIZONTAL' then
		bottomTexture:SetAlpha(1)
		bottomTexture:SetColorTexture(1,1,1,1)
		bottomTexture:SetGradient(textureStyle.gradient, CreateColor(textureStyle.red, textureStyle.green, textureStyle.blue, textureStyle.alpha), CreateColor(textureStyle.redEnd, textureStyle.greenEnd, textureStyle.blueEnd, textureStyle.alphaEnd))		
	end
					
end
function Style:StyleShadow(object,frame,style)
		-- Midnight: SetBackdrop requires the BackdropTemplate mixin on the
		-- frame, which is applied via the 4th arg to CreateFrame.
		object.shadow = object.shadow or CreateFrame("Frame", nil, frame, "BackdropTemplate")
		if not object.shadow.style or style.clear then object.shadow.style = {}	end	
		local shadowStyle = object.shadow.style				
		-- ~~ Format New Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
		local red,green,blue									= Tools:GetColor(style.color)		
		local offset											= style.offset and type(style.offset)=='number' and {style.offset,style.offset,style.offset,style.offset} or style.offset		
	-- Setting ~~~~~~~~~~~~~~~~~~~~~~~ New Setting ~~~~~~~~~~~~~~~ Old Setting ~~~~~~~~~~~~~~~~~ Default ~~~~~~~~~~~~~~~~~~			
		shadowStyle.edgeFile				= style.edgeFile				or shadowStyle.edgeFile			or getMedia('border','shadow')
		shadowStyle.edgeSize				= style.edgeSize				or shadowStyle.edgeSize			or 28		
			
		shadowStyle.red					= red								or shadowStyle.red				or 0	
		shadowStyle.green					= green							or shadowStyle.green				or 0
		shadowStyle.blue					= blue							or shadowStyle.blue				or 0
		shadowStyle.alpha					= style.alpha					or shadowStyle.alpha				or .45
		
		shadowStyle.offset				= offset							or shadowStyle.offset			or {20,20,20,20} 					
		-- ~~ Apply Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	

		if shadowStyle.offset[1] 	then object.shadow:SetPoint("LEFT", 	-shadowStyle.offset[1],0) 	end
		if shadowStyle.offset[2] 	then object.shadow:SetPoint("RIGHT", 	shadowStyle.offset[2],0) 	end
		if shadowStyle.offset[3] 	then object.shadow:SetPoint("TOP", 		0,shadowStyle.offset[3])	end		
		if shadowStyle.offset[4]	then object.shadow:SetPoint("BOTTOM", 	0,-shadowStyle.offset[4]) 	end	
		
		object.shadow:SetBackdrop({ edgeFile = shadowStyle.edgeFile, edgeSize = shadowStyle.edgeSize })
		object.shadow:SetBackdropBorderColor(shadowStyle.red, shadowStyle.green, shadowStyle.blue, shadowStyle.alpha)	
end
--[[ Font style table format	
	TODO style.offset		( offset|{ Left, Right, Top, Bottom })
	TODO style.width		( width )
	TODO style.height		( height )	
	
	style.font				( Path to a font file ) 
	style.fontSize 		( Size (point size) of the font to be displayed (in pixels) ) 
	style.flags				( Additional properties specified by one or more of the following tokens: MONOCHROME, OUTLINE | THICKOUTLINE )  (comma delimitered string)
	style.alpha				( alpha ) 
	style.color				( hexColor|{ Red, Green, Blue } [0-255])
	style.lineSpacing		( number - Sets the font instance's amount of spacing between lines)	
]]
function Style:StyleFont(fontInstance,name,style)	
	local filename, fontSize, flags 	= fontInstance:GetFont()	
	local red,green,blue,alpha 				= fontInstance:GetTextColor()	
	local lineSpacing									= fontInstance:GetSpacing()	
	style.red, style.green, style.blue 	= Tools:GetColor(style.color)		
	-- ~~ Set Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~			
	style.filename	= style.filename	or filename
	style.fontSize	= style.fontSize	or fontSize
	style.flags			= style.flags			or flags
	
	style.red 			= style.red 			or red
	style.green 		= style.green 		or green
	style.blue	 		= style.blue 			or blue
	style.alpha			= style.alpha			or alpha			
	style.lineSpacing	= style.lineSpacing	or lineSpacing	
	-- ~~ Apply Settings ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~		
	fontInstance:SetFont( style.filename, style.fontSize, style.flags	)				
	fontInstance:SetTextColor(style.red, style.green, style.blue, style.alpha)		
	fontInstance:SetSpacing(style.lineSpacing)		
	
	fontInstance.style = style	 
end
function Style:SetObjectStyle(object,name,style)	
	if not style or type(style) ~='table' then return end	
	local styleType = Tools:Capitalize(style.type)
	if not Style['Style'..styleType] then geterrorhandler()(style.type..' is not a valid styling method') return end
	
	if type(name) ~='string' then return end 	
	-- ~~ Get Frame ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	local framename = name:match('^[ \t]*([%w%d]*)')
	local frame = object[framename]	
	if not frame then geterrorhandler()('object['..framename..'] frame does not exist on object') return end	
	-- ~~ Style ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
	if styleType == 'Texture' then
		local texture = object.textures[name]
		if not texture then
			texture = newTexture()
			object.textures[name] = texture
		end
		texture:SetParent(frame)
		Style:StyleTexture(texture,style)		
	return end	
	if styleType == 'Outline' then			
		local textures = {}
		for i=1, #OUTLINES do
			local texture = object.textures[name..OUTLINES[i]]
			if not texture then
				texture = newTexture()
				object.textures[name..OUTLINES[i]] = texture					
			end			
			texture:SetParent(frame)			
			textures[i] = texture
		end
		Style:StyleOutline(textures[1],textures[2],textures[3],textures[4],style)
	return end	
	if styleType == 'Shadow' then
		Style:StyleShadow(object,frame,style)
	return end
	if styleType == 'Font' then		
		Style:StyleFont(frame,name,style)					 
	end			
end
function Style:AddObjectStyleSheet(object,stylesheet)
	for name,style in pairs(stylesheet) do 
		self:SetObjectStyle(object,name,style)		
	end
end
function Style:SetFrameStyle(frame,name,style)
	if not style or type(style) ~='table' then return end		
	if not name then error('[Settings.name] missing from style table',2)	return end
	local styleType = Tools:Capitalize(style.type)
	if not Style['Style'..styleType] then error(style.type..' is not a valid styling method',2) return end
		
	-- ~~ Get Texture ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~	
	frame.textures 	= frame.textures or {}
	
	if styleType == 'Texture' then
		local texture = frame.textures[name]
		if not texture then
			texture = newTexture()
			frame.textures[name] = texture
		end
		texture:SetParent(frame)
		Style:StyleTexture(texture,style)		
	return end	
	if styleType == 'Outline' then			
		local textures = {}
		for i=1, #OUTLINES do
			local texture = frame.textures[name..OUTLINES[i]]
			if not texture then
				texture = newTexture()
				frame.textures[name..OUTLINES[i]] = texture					
			end			
			texture:SetParent(frame)			
			textures[i] = texture
		end
		Style:StyleOutline(textures[1],textures[2],textures[3],textures[4],style)
	return end	
	if styleType == 'Shadow'  then
		Style:StyleShadow(object,frame,style)
	return end
	if styleType == 'Font'	  then		
		Style:StyleFont(frame,style)					 
	end	
end
function Style:AddFrameStyleSheet(frame,stylesheet)
	for name,style in pairs(stylesheet) do		 
		self:SetFrameStyle(frame,name,style)		
	end
end
function Style:ReleaseTexture(object,name)
	if not object or not object.textures or not object.textures[name] then
		error('No such texture on ojbect',2)
	return end
	releaseTexture(object.textures[name])	
	object.textures[name] = nil
end
function Style:ReleaseTextures(object)
	for name,texture in pairs(object.textures) do 
		releaseTexture(texture)
		object.textures[name] = nil
	end
end
function Style:GetMedia(mediaType,name)
	return getMedia(mediaType,name)
end
function Style:AddMedia(mediaType,name,mediaFile)
	addMedia(mediaType,name,mediaFile)
end