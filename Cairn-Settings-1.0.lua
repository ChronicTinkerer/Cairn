--[[
Cairn-Settings-1.0

Declarative settings schema bridging to Blizzard's native Settings panel
(the modern Settings API introduced in Dragonflight, refined through
Midnight). Backed by a Cairn.DB instance the author provides.

v0.1 schema types: toggle | range | dropdown | header
Planned for v0.2: text, color, keybind, anchor (EditMode integration).

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
	})

	settings:Open()                    -- open Blizzard Settings to this addon
	settings:Get("scale")              -- read current value
	settings:Set("scale", 1.5)         -- write (fires onChange + subscribers)
	settings:OnChange("scale", fn, owner)  -- subscribe; returns unsubscribe

Schema entry shape (common fields):
	key      string  required, unique within this category
	type     string  required, one of: toggle, range, dropdown, header
	label    string  required, the user-facing label
	default  any     required EXCEPT for type="header"; deep-copied into db.profile
	tooltip  string  optional, hover text
	onChange function optional, fired after the value updates: fn(newValue, oldValue)

Type-specific fields:
	range:    min, max, step (defaults: 0, 1, 0.1)
	dropdown: choices (table {value = label, ...})

The lib reads/writes values through `db.profile[key]`, so everything
persists via Cairn.DB profile rules (per-character or named profile,
SavedVariables-backed). Defaults are seeded into the profile on
Settings.New (only for keys not already present), so existing user values
are preserved across upgrades.

If Blizzard's Settings global is unavailable (e.g., Classic builds),
Settings.New returns a stub that supports Get/Set/OnChange but cannot
render a panel. Open() prints a friendly warning.
]]

local MAJOR, MINOR = "Cairn-Settings-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

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
		if entry.type ~= "header" and entry.default == nil then
			error("Cairn.Settings.New: schema entry '" .. entry.key
				.. "' requires a 'default' value", 3)
		end
		if entry.type == "dropdown" and type(entry.choices) ~= "table" then
			error("Cairn.Settings.New: dropdown entry '" .. entry.key
				.. "' requires a 'choices' table", 3)
		end
	end
end

local function seedDefaults(db, schema)
	-- For each non-header entry, ensure db.profile[key] has a value. Only
	-- write the default if the key is currently nil so existing user data
	-- is preserved across addon upgrades.
	for _, entry in ipairs(schema) do
		if entry.type ~= "header" and db.profile[entry.key] == nil then
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

-- Shared OnChange (works on both real and stub).
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

	-- All non-header entries are "real" settings backed by db.profile.
	local variableName = "Cairn_" .. self._addonName .. "_" .. key

	-- Determine VarType.
	local varType
	if entry.type == "toggle" then
		varType = Settings.VarType.Boolean
	elseif entry.type == "range" then
		varType = Settings.VarType.Number
	elseif entry.type == "dropdown" then
		-- Dropdown values can be any type; use Number if default is numeric, else String.
		varType = (type(entry.default) == "number") and Settings.VarType.Number or Settings.VarType.String
	end

	local setting = Settings.RegisterProxySetting(
		self._category, variableName, varType, entry.label or key, entry.default,
		function() return self._db.profile[key] end,
		function(_, value)
			-- The proxy setter is called by Blizzard on user change. Route
			-- it through setValue so onChange + subscribers fire too.
			setValue(self, key, value, true)
		end
	)

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
			-- Pull a stable order: alphabetical by label.
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

	-- Index by key for O(1) onChange lookups.
	local byKey = {}
	for _, entry in ipairs(schema) do byKey[entry.key] = entry end

	local self = {
		_addonName = addonName,
		_db        = db,
		_schema    = schema,
		_byKey     = byKey,
		_subs      = {},  -- key -> { {fn,owner}, ... }
	}

	-- If Blizzard's Settings API isn't available, return a stub.
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then
		if logger() then
			logger():Warn("Blizzard Settings API not available; returning Get/Set-only stub for %s.", addonName)
		end
		return setmetatable(self, stubProto)
	end

	-- Register category + initializers.
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
