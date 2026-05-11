--[[
Cairn-Gui-Widgets-Standard-2.0 / Widgets / Container

A bare Cairn-aware Frame for grouping. The minimal "I want to put
widgets in a thing" widget. Optional bg / border so it can stand on
its own as a card or panel section. Without those opts it's invisible.

Public API:

	c = Cairn.Gui:Acquire("Container", parent, {
		width  = 200,
		height = 100,
		bg     = "color.bg.surface",     -- optional token spec or state map
		border = "color.border.default", -- optional token spec
		borderWidth = 1,
	})

	c.Cairn:SetLayout("Stack", { ... })
	local btn = Cairn.Gui:Acquire("Button", c, ...)

Pool: enabled (containers are commonly created and destroyed).

Tokens consumed (when bg/border opts present):
	color.bg.* (whatever token the consumer passes)
	color.border.* (whatever token the consumer passes)

Status: Day 13. Used by Window for its title bar and content area as
well as by external consumers who want a generic grouping primitive.
]]

local Bundle = LibStub("Cairn-Gui-Widgets-Standard-2.0", true)
if not Bundle then return end

local Core = Bundle._core
if not Core then return end

local mixin = {}

function mixin:OnAcquire(opts)
	opts = opts or {}
	local frame = self._frame

	if opts.width or opts.height then
		frame:SetSize(opts.width or 100, opts.height or 100)
	end

	if opts.bg then
		self:DrawRect("bg", opts.bg)
	end
	if opts.border then
		self:DrawBorder("frame", opts.border, { width = opts.borderWidth or 1 })
	end
end

local function reset(self)
	-- Primitives stay attached to the frame; OnAcquire on next reuse will
	-- redraw with the new opts and the existing textures will be reused.
end

Core:RegisterWidget("Container", {
	frameType = "Frame",
	mixin     = mixin,
	pool      = true,
	reset     = reset,
})
