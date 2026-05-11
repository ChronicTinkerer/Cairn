--[[
Cairn-Gui-2.0 / Core / Contracts

Registration-shape validators per Decision 11. Catches def errors at
the registration time of widgets / layouts / themes / easings, plus
provides an explicit `lib:RunContracts()` entry point Forge can call
to revalidate every registered piece in one pass.

Validators are GENTLE: they emit a warning via Cairn-Log (or print to
chat as fallback) but DO NOT error or unregister. Production runs
shouldn't break on a contract violation; they should surface it for
the author to fix on their next build.

Public API on lib:

	Cairn.Gui:RunContracts()
		Walk every registered widget def, layout strategy, theme, and
		easing. Return a table summary:
			{
				widgets = { ok = N, warn = { {name, msg}, ... } },
				layouts = { ok = N, warn = { {name, msg}, ... } },
				themes  = { ok = N, warn = { {name, msg}, ... } },
				easings = { ok = N, warn = { {name, msg}, ... } },
			}
		Useful as a one-shot health check from a Forge tab or test snippet.

	Cairn.Gui:ValidateWidget(name, def)
	Cairn.Gui:ValidateLayout(name, fn)
	Cairn.Gui:ValidateTheme(name, theme)
		Validate a single registration. Returns (ok, errMsg). Used
		internally by RegisterX hooks; exposed for ad-hoc validation
		of pre-registration data.

Validation rules per registration kind:

	WIDGET:
		- def.frameType is a string
		- def.mixin is a table
		- if def.secure: def.template should match Secure*Template pattern
		- if def.pool: def.reset must be a function (or nil = warn-only)
		- def.prewarm, if set, must be a non-negative number

	LAYOUT:
		- fn is a function

	THEME:
		- theme.tokens is a table
		- token values fall into known shapes (color / length / font /
		  texture / flag / duration); unknown shapes warn but pass.

	EASING:
		- fn is a function

Cairn-Gui-2.0/Core/Contracts (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

-- ----- Validators ------------------------------------------------------

function lib:ValidateWidget(name, def)
	if type(def) ~= "table" then return false, "def is not a table" end
	if type(def.frameType) ~= "string" or def.frameType == "" then
		return false, "frameType must be a non-empty string"
	end
	if type(def.mixin) ~= "table" then
		return false, "mixin must be a table"
	end
	if def.secure then
		-- Secure widgets MUST use a Blizzard secure template.
		local t = def.template or ""
		if not (t:find("Secure", 1, true)) then
			return false, "secure widget should use a Blizzard Secure*Template (template = " .. tostring(def.template) .. ")"
		end
	end
	if def.pool and def.reset and type(def.reset) ~= "function" then
		return false, "pool=true with non-function reset (got " .. type(def.reset) .. ")"
	end
	if def.prewarm ~= nil and (type(def.prewarm) ~= "number" or def.prewarm < 0) then
		return false, "prewarm must be a non-negative number (got " .. tostring(def.prewarm) .. ")"
	end
	return true
end

function lib:ValidateLayout(name, fn)
	if type(fn) ~= "function" then
		return false, "layout strategy must be a function"
	end
	return true
end

local KNOWN_TOKEN_KIND_PREFIXES = {
	color    = true,
	length   = true,
	font     = true,
	texture  = true,
	flag     = true,
	duration = true,
}

function lib:ValidateTheme(name, theme)
	if type(theme) ~= "table" then
		return false, "theme must be a table"
	end
	if theme.tokens and type(theme.tokens) ~= "table" then
		return false, "theme.tokens must be a table when present"
	end
	if theme.tokens then
		for k, v in pairs(theme.tokens) do
			if type(k) == "string" then
				local prefix = k:match("^([^.]+)%.")
				if prefix and not KNOWN_TOKEN_KIND_PREFIXES[prefix] then
					-- Soft warning: unknown token-kind prefix. Doesn't
					-- fail validation; just notes.
					return true, "unknown token kind prefix: " .. prefix .. " (token " .. k .. ")"
				end
			end
		end
	end
	return true
end

function lib:ValidateEasing(name, fn)
	if type(fn) ~= "function" then
		return false, "easing must be a function"
	end
	return true
end

-- ----- RunContracts ----------------------------------------------------

local function logWarn(kind, name, msg)
	-- Try Cairn-Log first; fall back to chat print.
	local Log = LibStub("Cairn-Log-1.0", true)
	if Log then
		local logger = Log("Cairn.Gui.Contracts")
		if logger and logger.Warn then
			logger:Warn("%s %q: %s", kind, tostring(name), tostring(msg))
			return
		end
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(string.format(
			"|cffd87f3aCairn-Gui contracts:|r %s %q -- %s",
			kind, tostring(name), tostring(msg)))
	end
end

function lib:RunContracts()
	local result = {
		widgets = { ok = 0, warn = {} },
		layouts = { ok = 0, warn = {} },
		themes  = { ok = 0, warn = {} },
		easings = { ok = 0, warn = {} },
	}

	if self.widgets then
		for name, def in pairs(self.widgets) do
			local ok, msg = self:ValidateWidget(name, def)
			if ok and not msg then
				result.widgets.ok = result.widgets.ok + 1
			else
				table.insert(result.widgets.warn, { name = name, msg = msg })
				logWarn("widget", name, msg)
			end
		end
	end

	if self.layouts then
		for name, fn in pairs(self.layouts) do
			local ok, msg = self:ValidateLayout(name, fn)
			if ok and not msg then
				result.layouts.ok = result.layouts.ok + 1
			else
				table.insert(result.layouts.warn, { name = name, msg = msg })
				logWarn("layout", name, msg)
			end
		end
	end

	if self.themes then
		for name, theme in pairs(self.themes) do
			local ok, msg = self:ValidateTheme(name, theme)
			if ok and not msg then
				result.themes.ok = result.themes.ok + 1
			else
				table.insert(result.themes.warn, { name = name, msg = msg })
				logWarn("theme", name, msg)
			end
		end
	end

	if self.easings then
		for name, fn in pairs(self.easings) do
			local ok, msg = self:ValidateEasing(name, fn)
			if ok and not msg then
				result.easings.ok = result.easings.ok + 1
			else
				table.insert(result.easings.warn, { name = name, msg = msg })
				logWarn("easing", name, msg)
			end
		end
	end

	return result
end
