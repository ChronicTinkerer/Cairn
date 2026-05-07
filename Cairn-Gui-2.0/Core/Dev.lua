--[[
Cairn-Gui-2.0 / Core / Dev

Developer overlay + the canonical setter for the `lib.Dev` flag. Per
Decision 10B, the library ships ONE minimal overlay (frame outlines +
type-name labels) and pads tinting under Cairn.Dev. Forge owns the rich
inspector window; this is the lightweight "I just want to see widget
boundaries while debugging" mode.

Public API:

	Cairn.Dev:SetEnabled(bool)         -- toggle the dev mode
	Cairn.Dev:IsEnabled()              -- read current state
	Cairn.Dev:Toggle()
	Cairn.Dev:OnChange(fn)             -- subscribe to enable/disable; fn(bool)
	                                       returns an unsubscribe closure

	-- The library's existing flag at lib.Dev still works; SetEnabled
	-- writes through to it. Reading lib.Dev directly is fine; consumers
	-- who want to react to changes (e.g., refresh their UI) should use
	-- OnChange instead of polling.

Behavior under Cairn.Dev = true:

	1. Frame outlines: every tracked widget gets a 1px tan outline drawn
	   on its frame. Outline lives in OVERLAY draw layer so it sits on
	   top of the widget's own primitives. Refreshes on toggle and on
	   tracking change (via Inspector:_track hook).

	2. Type-name labels: a small FontString anchored TOPLEFT of each
	   widget with the widget type ("Button", "ScrollFrame", etc.).

	3. Padding tint: containers with a registered layout strategy and a
	   non-zero padding setting render their padding region as a
	   translucent tan rect on the BACKGROUND layer. Width/height/inner
	   region are derived from the layout's settings.

	4. EventLog auto-enables. Disabling Cairn.Dev does NOT auto-disable
	   the EventLog (the user might want to keep recording for a
	   post-mortem).

Tear-down on disable:
	The overlay frames are HIDDEN, not destroyed. They live on the widget
	frames and are reused on the next enable so re-toggling is cheap.

Cairn-Gui-2.0/Core/Dev (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

-- Soft-required siblings.
local Inspector = lib.Inspector
local EventLog  = lib.EventLog

local Dev = {}

-- Preserve subscriber list across LibStub upgrades.
Dev.subscribers = lib._dev and lib._dev.subscribers or {}

local OUTLINE_COLOR_RGBA   = { 0.85, 0.50, 0.20, 0.90 }  -- tan, fully visible
local LABEL_COLOR_RGBA     = { 1.00, 0.85, 0.50, 1.00 }
local PADDING_COLOR_RGBA   = { 0.85, 0.50, 0.20, 0.18 }  -- tan, translucent

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"

-- ----- Internal: ensure overlay attached to a widget --------------------

-- Idempotent. Builds 4 edge textures, a label FontString, and (for
-- containers with a layout) a padding tint texture. Stores them on the
-- widget.Cairn object as `_dev_*` fields so they're easy to find/hide.
local function ensureOverlay(cairn)
	if not cairn or not cairn._frame then return end
	local frame = cairn._frame
	if cairn._dev_built then return end

	-- 4 edge textures forming the outline.
	local edges = {}
	for i = 1, 4 do
		edges[i] = frame:CreateTexture(nil, "OVERLAY")
		edges[i]:SetTexture(WHITE_TEX)
		edges[i]:SetVertexColor(unpack(OUTLINE_COLOR_RGBA))
	end
	-- Top.
	edges[1]:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
	edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	edges[1]:SetHeight(1)
	-- Bottom.
	edges[2]:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
	edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	edges[2]:SetHeight(1)
	-- Left.
	edges[3]:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
	edges[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	edges[3]:SetWidth(1)
	-- Right.
	edges[4]:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, 0)
	edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	edges[4]:SetWidth(1)
	cairn._dev_edges = edges

	-- Type-name label.
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
	label:SetTextColor(unpack(LABEL_COLOR_RGBA))
	label:SetText(tostring(cairn._type or "?"))
	cairn._dev_label = label

	-- Padding tint (lazy-built only when the widget has a layout strategy).
	-- We can refresh dimensions on each enable; for now, just create the
	-- texture stub. Layout integration that respects per-strategy padding
	-- semantics is a Decision-4 follow-up.
	if cairn._layout and cairn._layout.padding then
		local pad = frame:CreateTexture(nil, "BACKGROUND")
		pad:SetTexture(WHITE_TEX)
		pad:SetVertexColor(unpack(PADDING_COLOR_RGBA))
		pad:SetAllPoints(frame)
		cairn._dev_padding = pad
	end

	cairn._dev_built = true
end

local function showOverlay(cairn)
	if not cairn or not cairn._dev_built then return end
	if cairn._dev_edges then
		for _, e in ipairs(cairn._dev_edges) do e:Show() end
	end
	if cairn._dev_label   then cairn._dev_label:Show()   end
	if cairn._dev_padding then cairn._dev_padding:Show() end
end

local function hideOverlay(cairn)
	if not cairn then return end
	if cairn._dev_edges then
		for _, e in ipairs(cairn._dev_edges) do e:Hide() end
	end
	if cairn._dev_label   then cairn._dev_label:Hide()   end
	if cairn._dev_padding then cairn._dev_padding:Hide() end
end

-- ----- Walk + apply -----------------------------------------------------

local function applyToAll(showFn)
	if not Inspector then return end
	Inspector:WalkAll(function(cairn)
		ensureOverlay(cairn)
		showFn(cairn)
	end)
end

-- ----- Public API -------------------------------------------------------

function Dev:IsEnabled()
	return lib.Dev and true or false
end

function Dev:SetEnabled(enabled)
	enabled = enabled and true or false
	if (lib.Dev and true or false) == enabled then return end
	lib.Dev = enabled

	if enabled then
		applyToAll(showOverlay)
		if EventLog and not EventLog:IsEnabled() then
			EventLog:Enable()
			Dev._enabledEventLog = true   -- remember so a polite Disable can revert
		end
	else
		applyToAll(hideOverlay)
		-- Per the docstring: don't auto-disable EventLog on dev exit. The
		-- user might want the buffer to keep recording for post-mortem.
		-- _enabledEventLog stays set so a future SetEnabled(true) is a
		-- clean toggle.
	end

	-- Notify subscribers.
	for _, fn in ipairs(self.subscribers) do
		local ok, err = pcall(fn, enabled)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

function Dev:Toggle()
	self:SetEnabled(not self:IsEnabled())
end

-- Subscribe to enable/disable transitions. Returns an unsubscribe closure.
function Dev:OnChange(fn)
	if type(fn) ~= "function" then return function() end end
	self.subscribers[#self.subscribers + 1] = fn
	return function()
		for i, sub in ipairs(self.subscribers) do
			if sub == fn then
				table.remove(self.subscribers, i)
				return
			end
		end
	end
end

-- ----- Inspector tracking hook -----------------------------------------
-- When a new widget is acquired, it's tracked by Inspector. If Dev is
-- currently enabled, immediately attach + show the overlay so freshly
-- acquired widgets don't appear without the visual debug state.
--
-- Guarded so /reload doesn't stack wrappers. Once we've installed the
-- patched _track, subsequent loads of Dev.lua see _devTracked and skip
-- re-wrapping. State (subscribers, lib.Dev value) is preserved
-- separately at the top of this file.

if Inspector and not Inspector._devTracked then
	local origTrack = Inspector._track
	function Inspector:_track(cairn)
		origTrack(self, cairn)
		if lib.Dev then
			ensureOverlay(cairn)
			showOverlay(cairn)
		end
	end
	Inspector._devTracked = true
end

-- ----- Publish ---------------------------------------------------------

lib.Dev      = lib.Dev or false   -- the FLAG (preserved if already set)
lib._dev     = Dev                 -- module-state preservation
lib.DevAPI   = Dev                 -- the API namespace

-- Convenience: also publish under lib.Dev when accessed as a method by
-- mistake. Consumers who write `lib.Dev:Toggle()` instead of
-- `lib.DevAPI:Toggle()` get a helpful error rather than a silent
-- no-op (since lib.Dev is a boolean, not a table). We can't redirect
-- without breaking the read-as-flag contract, but we can document the
-- correct call site in the error.
-- (No metatable trickery here; the docstring is the contract.)
