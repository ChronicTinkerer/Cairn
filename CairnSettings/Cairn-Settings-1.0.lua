--[[
Cairn-Settings-1.0

Declarative settings schema bridging to Blizzard's native Settings panel
(the modern Settings API introduced in Dragonflight, refined through
Midnight). Backed by a Cairn.DB instance the author provides.

v0.1 schema types: toggle | range | dropdown | header
v0.2 added:        anchor (EditMode integration via Cairn.EditMode + LibEditMode)
Planned for v0.3:  text, color, keybind.

Public API:

	local db = Cairn.DB.New("MyAddonDB", { defaults = { profile = {
		scale = 1.0, enabled = true, anchor = "TOPLEFT",
	}}})

	local settings = Cairn.Settings.New("MyAddon", db, {
		{ key = "header1", type = "header", label = "Display" },
		{ key = "scale",   type = "range",  label = "Scale",
		  min = 0.5, max = 2.0, step = 0.1, default = 1.0,
		  tooltip = "How big the frame is",
		  onChange = function(value, oldValue) MyAddon:Rescale(value) end },
		{ key = "enabled", type = "toggle", label = "Enable",
		  default = true },
		{ key = "anchor",  type = "dropdown", label = "Anchor",
		  default = "TOPLEFT",
		  choices = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right",
		              BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right" } },
		-- v0.2 anchor type (requires LibEditMode to do anything useful):
		{ key = "framePos", type = "anchor", label = "Frame position",
		  frame = MyAddonFrame,
		  default = { point = "CENTER", x = 0, y = 0 },
		  tooltip = "Adjust position via Edit Mode.",
		  onChange = function() MyAddon:Reanchor() end },
	})

	settings:Open()                    -- open Blizzard Settings to this addon
	settings:Get("scale")              -- read current value
	settings:Set("scale", 1.5)         -- write (fires onChange + subscribers)
	settings:OnChange("scale", fn, owner)  -- subscribe; returns unsubscribe

Schema entry shape (common fields):
	key      string  required, unique within this category
	type     string  required, one of: toggle, range, dropdown, header, anchor
	label    string  required, the user-facing label
	default  any     required EXCEPT for type="header"; deep-copied into db.profile
	                 for anchor type, default is { point = ..., x = ..., y = ... }
	tooltip  string  optional, hover text
	onChange function optional, fired after the value updates: fn(newValue, oldValue)
	                 for anchor type, fires when EditMode commits position with no args

Type-specific fields:
	range:    min, max, step (defaults: 0, 1, 0.1)
	dropdown: choices (table {value = label, ...})
	anchor:   frame (Frame with a non-nil :GetName())
	text:     placeholder, maxLetters, width (string default required)
	color:    hasOpacity (bool); default = { r=, g=, b=[, a=] } (canonical)
	          or { r, g, b[, a] } positional (also accepted, normalized
	          to named at validate time). Each component 0..1.
	keybind:  default is the binding string ("CTRL-SHIFT-X") or "" for unbound

If Blizzard's Settings global is unavailable (e.g., Classic builds),
Settings.New returns a stub that supports Get/Set/OnChange but cannot
render a panel. Open() prints a friendly warning.
]]

-- MINOR history (selected):
--   3  prior: settings instance / OpenStandalone wired to Cairn-SettingsPanel-1.0 only
--   4  OpenStandalone now prefers Cairn-SettingsPanel-2.0 (Cairn-Gui-2.0 panel)
--      with a v1 fallback. Same public API. Spotted while building Cairn-Demo's
--      Settings tab on 2026-05-07: opening the panel from a v2 demo window
--      pulled the user into a visually-mismatched v1 panel.
--   5  color validator accepts BOTH named ({r=, g=, b=[, a=]}) and positional
--      ({[1]=r, [2]=g, [3]=b}) shapes, normalizing positional to named.
--      Lib header documented named; validator only accepted positional. Caught
--      while wiring Cairn-Demo's Settings tab schema on 2026-05-07.
local MAJOR, MINOR = "Cairn-Settings-1.0", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Weak-keyed instances table so Forge_Registry / debug tools can enumerate
-- live settings panels. Same pattern as Cairn-Callback.instances.
lib.instances = lib.instances or setmetatable({}, { __mode = "k" })

local Log = LibStub("Cairn-Log-1.0", true)
local function logger()
	if not lib._log and Log then lib._log = Log("Cairn.Settings") end
	return lib._log
end

local SUPPORTED_TYPES = {
	toggle   = true,
	range    = true,
	dropdown = true,
	header   = true,
	anchor   = true,  -- v0.2; requires Cairn.EditMode + LibEditMode for full effect
	text     = true,  -- v0.2; popup EditBox launched from a row button
	color    = true,  -- v0.2; ColorPickerFrame launched from a row button
	keybind  = true,  -- v0.2; modifier+key capture launched from a row button
}


-- ----- Helpers -----------------------------------------------------------

local function validateSchema(schema)
	if type(schema) ~= "table" then
		error("Cairn.Settings.New: schema must be a table (array of entries)", 3)
	end
	local seen = {}
	for i, entry in ipairs(schema) do
		if type(entry) ~= "table" then
			error("Cairn.Settings.New: schema entry #" .. i .. " must be a table", 3)
		end
		if type(entry.key) ~= "string" or entry.key == "" then
			error("Cairn.Settings.New: schema entry #" .. i .. " missing 'key' (string)", 3)
		end
		if not SUPPORTED_TYPES[entry.type] then
			error("Cairn.Settings.New: schema entry #" .. i .. " ('" .. entry.key
				.. "') has unsupported type: " .. tostring(entry.type), 3)
		end
		if seen[entry.key] then
			error("Cairn.Settings.New: duplicate schema key: " .. entry.key, 3)
		end
		seen[entry.key] = true
		if entry.type ~= "header" and entry.type ~= "anchor" and entry.default == nil then
			error("Cairn.Settings.New: schema entry '" .. entry.key
				.. "' requires a 'default' value", 3)
		end
		if entry.type == "dropdown" and type(entry.choices) ~= "table" then
			error("Cairn.Settings.New: dropdown entry '" .. entry.key
				.. "' requires a 'choices' table", 3)
		end
		if entry.type == "text" and type(entry.default) ~= "string" then
			error("Cairn.Settings.New: text entry '" .. entry.key
				.. "' requires a string 'default'", 3)
		end
		if entry.type == "color" then
			-- Canonical shape is named: { r =, g =, b =[, a =] }, each 0..1.
			-- Positional { [1]=r, [2]=g, [3]=b[, [4]=a] } is also accepted
			-- for backwards-compat and normalized in-place to named.
			-- (MINOR 5: prior validator only accepted positional, which
			-- contradicted the lib header that documented named. Caught
			-- 2026-05-07 while wiring Cairn-Demo's Settings tab.)
			local d = entry.default
			if type(d) ~= "table" then
				error("Cairn.Settings.New: color entry '" .. entry.key
					.. "' requires a default table {r=, g=, b=[, a=]} (each 0..1)", 3)
			end
			local hasNamed = (type(d.r) == "number" and type(d.g) == "number" and type(d.b) == "number")
			local hasPos   = (type(d[1]) == "number" and type(d[2]) == "number" and type(d[3]) == "number")
			if not hasNamed and not hasPos then
				error("Cairn.Settings.New: color entry '" .. entry.key
					.. "' requires a default = {r=, g=, b=[, a=]} OR {r, g, b[, a]} (each 0..1)", 3)
			end
			if hasPos and not hasNamed then
				-- Normalize positional -> named in-place.
				entry.default = { r = d[1], g = d[2], b = d[3], a = d[4] }
			end
		end
		if entry.type == "keybind" and type(entry.default) ~= "string" then
			error("Cairn.Settings.New: keybind entry '" .. entry.key
				.. "' requires a string 'default' (e.g. \"CTRL-SHIFT-X\" or \"\")", 3)
		end
		if entry.type == "anchor" then
			if type(entry.frame) ~= "table" or type(entry.frame.GetName) ~= "function" then
				error("Cairn.Settings.New: anchor entry '" .. entry.key
					.. "' requires a 'frame' (a Frame with :GetName)", 3)
			end
			local fname = entry.frame:GetName()
			if not fname or fname == "" then
				error("Cairn.Settings.New: anchor entry '" .. entry.key
					.. "' requires frame to have a name (CreateFrame with a name string)", 3)
			end
		end
	end
end

local function seedDefaults(db, schema)
	-- For each non-header / non-anchor entry, ensure db.profile[key] has a
	-- value. Only write the default if currently nil so user data survives
	-- across upgrades. (Anchor positions are NOT stored in db.profile;
	-- LibEditMode persists them in EditMode's own SavedVariables.)
	for _, entry in ipairs(schema) do
		if entry.type ~= "header" and entry.type ~= "anchor"
			and db.profile[entry.key] == nil then
			db.profile[entry.key] = entry.default
		end
	end
end

local function fireSubscribers(self, key, newValue, oldValue)
	local list = self._subs[key]
	if not list then return end
	for i = 1, #list do
		local sub = list[i]
		if sub and not sub.removed then
			local ok, err = pcall(sub.fn, newValue, oldValue)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
	end
end

local function setValue(self, key, value, fireCallbacks)
	local oldValue = self._db.profile[key]
	if oldValue == value then return end
	self._db.profile[key] = value
	if fireCallbacks then
		local entry = self._byKey[key]
		if entry and entry.onChange then
			local ok, err = pcall(entry.onChange, value, oldValue)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
		fireSubscribers(self, key, value, oldValue)
	end
end

-- ----- Stub instance (no Blizzard Settings global) -----------------------

local stubProto = {}
stubProto.__index = stubProto

function stubProto:Open()
	if logger() then
		logger():Warn("Settings.Open called but Blizzard Settings API is not available on this client.")
	else
		print("|cFF7FBFFF[Cairn]|r Settings panel not available on this client.")
	end
end

function stubProto:Get(key) return self._db.profile[key] end
function stubProto:Set(key, value) setValue(self, key, value, true) end
function stubProto:GetCategoryID() return nil end

-- Reuse OnChange impl below.

-- ----- Real instance ----------------------------------------------------

local proto = {}
proto.__index = proto

function proto:Open()
	if not self._categoryID then
		if logger() then
			logger():Warn("Settings:Open called but no category was registered.")
		end
		return
	end
	if Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self._categoryID)
	end
end

function proto:Get(key) return self._db.profile[key] end
function proto:Set(key, value) setValue(self, key, value, true) end
function proto:GetCategoryID() return self._categoryID end
function proto:GetCategory() return self._category end

-- Open a standalone Cairn.Gui-rendered panel for this schema. Independent
-- of Blizzard's Settings UI - works for every schema type including those
-- the Blizzard panel can't render on this client (text/color/keybind).
--
-- Prefers Cairn-SettingsPanel-2.0 (built on Cairn-Gui-2.0) when present;
-- falls back to Cairn-SettingsPanel-1.0 (Cairn-Gui-1.0) otherwise. Both
-- libs expose the same .OpenFor(settings) entrypoint so the call site is
-- identical.
function proto:OpenStandalone()
    local PanelV2 = LibStub("Cairn-SettingsPanel-2.0", true)
    if PanelV2 then return PanelV2.OpenFor(self) end
    local PanelV1 = LibStub("Cairn-SettingsPanel-1.0", true)
    if PanelV1 then return PanelV1.OpenFor(self) end
    if logger() then logger():Warn(":OpenStandalone called but no Cairn-SettingsPanel lib is loaded.") end
    return nil
end
stubProto.OpenStandalone = proto.OpenStandalone

local function onChange(self, key, fn, owner)
	if type(key) ~= "string" then error("Cairn.Settings:OnChange: 'key' must be a string", 2) end
	if type(fn) ~= "function" then error("Cairn.Settings:OnChange: 'fn' must be a function", 2) end
	self._subs[key] = self._subs[key] or {}
	local sub = { fn = fn, owner = owner }
	local list = self._subs[key]
	list[#list + 1] = sub
	return function() sub.removed = true end
end
proto.OnChange     = onChange
stubProto.OnChange = onChange

-- ----- Schema → Blizzard panel ------------------------------------------

local function registerEntry(self, entry)
	local key = entry.key

	if entry.type == "header" then
		if CreateSettingsListSectionHeaderInitializer and self._layout then
			local init = CreateSettingsListSectionHeaderInitializer(entry.label or key)
			self._layout:AddInitializer(init)
		end
		return
	end

	if entry.type == "anchor" then
		-- Render a section header with the label (and a hint in the tooltip).
		if CreateSettingsListSectionHeaderInitializer and self._layout then
			local headerLabel = (entry.label or key) .. "  (Edit Mode)"
			local init = CreateSettingsListSectionHeaderInitializer(headerLabel)
			self._layout:AddInitializer(init)
		end

		-- Hand off to Cairn.EditMode (no-ops if LibEditMode isn't loaded).
		local EditMode = LibStub("Cairn-EditMode-1.0", true)
		if EditMode then
			local cb = entry.onChange and function() entry.onChange() end or nil
			EditMode:Register(entry.frame, entry.default, cb, entry.label or key)
		elseif logger() then
			logger():Warn("anchor entry '%s' present but Cairn.EditMode module not loaded.", key)
		end
		return
	end

	-- All other (real) settings are backed by db.profile.
	local variableName = "Cairn_" .. self._addonName .. "_" .. key

	local varType
	if entry.type == "toggle" then
		varType = Settings.VarType.Boolean
	elseif entry.type == "range" then
		varType = Settings.VarType.Number
	elseif entry.type == "dropdown" then
		varType = (type(entry.default) == "number") and Settings.VarType.Number or Settings.VarType.String
	end

	local setting = Settings.RegisterProxySetting(
		self._category, variableName, varType, entry.label or key, entry.default,
		function() return self._db.profile[key] end,
		function(_, value) setValue(self, key, value, true) end
	)

	-- text / color / keybind are STORAGE-ONLY schema types. The schema
	-- validates them, defaults seed them, Get/Set/OnChange work normally,
	-- but no Blizzard panel widget is rendered. Addon authors render the
	-- visual themselves (their own panel, slash command, EditBox popup,
	-- ColorPickerFrame, key-capture modal - whatever fits the addon).
	-- This was a deliberate v0.2 decision after Midnight's Settings API
	-- changes broke the panel-button paths we tried.
	if entry.type == "text" or entry.type == "color" or entry.type == "keybind" then
		return
	end

	if entry.type == "toggle" then
		Settings.CreateCheckbox(self._category, setting, entry.tooltip)
	elseif entry.type == "range" then
		local opts = Settings.CreateSliderOptions(entry.min or 0, entry.max or 1, entry.step or 0.1)
		if MinimalSliderWithSteppersMixin and opts.SetLabelFormatter then
			opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(self._category, setting, opts, entry.tooltip)
	elseif entry.type == "dropdown" then
		Settings.CreateDropdown(self._category, setting, function()
			local container = Settings.CreateControlTextContainer()
			local pairs_list = {}
			for value, label in pairs(entry.choices) do
				pairs_list[#pairs_list + 1] = { value = value, label = label }
			end
			table.sort(pairs_list, function(a, b) return tostring(a.label) < tostring(b.label) end)
			for _, p in ipairs(pairs_list) do container:Add(p.value, p.label) end
			return container:GetData()
		end, entry.tooltip)
	end
end

-- ----- Constructor -------------------------------------------------------

function lib.New(addonName, db, schema)
	if type(addonName) ~= "string" or addonName == "" then
		error("Cairn.Settings.New: addonName must be a non-empty string", 2)
	end
	if type(db) ~= "table" or type(db.profile) ~= "table" then
		error("Cairn.Settings.New: db must be a Cairn.DB instance with .profile (call after ADDON_LOADED)", 2)
	end
	validateSchema(schema)
	seedDefaults(db, schema)

	local byKey = {}
	for _, entry in ipairs(schema) do byKey[entry.key] = entry end

	local self = {
		_addonName = addonName,
		_db        = db,
		_schema    = schema,
		_byKey     = byKey,
		_subs      = {},
	}
	-- Track this instance for debug enumeration (Forge_Registry).
	lib.instances[self] = addonName

	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
		if logger() then
			logger():Warn("Blizzard Settings API not available; returning Get/Set-only stub for %s.", addonName)
		end
		setmetatable(self, stubProto)
		-- Even in stub mode, anchor entries should still try to register
		-- with Cairn.EditMode so EditMode-movable frames work.
		local EditMode = LibStub("Cairn-EditMode-1.0", true)
		if EditMode then
			for _, entry in ipairs(schema) do
				if entry.type == "anchor" then
					local cb = entry.onChange and function() entry.onChange() end or nil
					EditMode:Register(entry.frame, entry.default, cb, entry.label or entry.key)
				end
			end
		end
		return self
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)
	self._category   = category
	self._layout     = layout
	self._categoryID = category and category:GetID() or nil

	setmetatable(self, proto)

	for _, entry in ipairs(schema) do
		local ok, err = pcall(registerEntry, self, entry)
		if not ok then
			if logger() then
				logger():Error("Failed to register schema entry '%s': %s", entry.key, tostring(err))
			elseif geterrorhandler then
				geterrorhandler()(err)
			end
		end
	end

	Settings.RegisterAddOnCategory(category)
	if logger() then
		logger():Info("Registered settings category for %s (%d entries)", addonName, #schema)
	end

	return self
end

setmetatable(lib, { __call = function(self, name, db, schema) return self.New(name, db, schema) end })
