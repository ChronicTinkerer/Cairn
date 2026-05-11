--[[
Cairn-Gui-2.0 / Core / L10n

Localization glue per Decision 10A. Widget text setters call into this
module to resolve the "@namespace:key" prefix to a localized string via
Cairn-Locale-1.0. Plain strings (no @ prefix) pass through untouched.

The resolver is intentionally LAZY: it looks up the locale instance on
every call rather than caching, so a runtime locale switch (or a fresh
RegisterLocaleOverlay) takes effect without consumer code refresh.

Public API on lib:

	Cairn.Gui:ResolveText(text, widgetCairn?)
		If text starts with "@namespace:key", returns the resolved
		localized string from Cairn.Locale.Get(namespace):Lookup(key).
		Falls back to the literal "@namespace:key" string if the
		namespace isn't registered, the key isn't translated, or
		Cairn-Locale-1.0 isn't loaded. Returns text unchanged for any
		other input shape.

		`widgetCairn` is optional; passed for future use (e.g.,
		per-widget locale overrides). v1 doesn't consult it.

Public API on widget.Cairn (added to Mixins.Base by this file):

	widget.Cairn:_resolveText(text)
		Convenience wrapper around lib:ResolveText so widget mixins can
		call self:_resolveText(text) without reaching into lib.

Cairn-Gui-2.0/Core/L10n (c) 2026 ChronicTinkerer. MIT license.
]]

local MAJOR, MINOR = "Cairn-Gui-2.0", 1
local lib = LibStub:GetLibrary(MAJOR, true)
if not lib then return end

local Base = lib.Mixins and lib.Mixins.Base
if not Base then
	error("Cairn-Gui-2.0/Core/L10n requires Mixins/Base to load first; check Cairn.toc order")
end

-- ----- Resolver --------------------------------------------------------

function lib:ResolveText(text, _widgetCairn)
	if type(text) ~= "string" or text == "" then return text end
	-- Cheap prefix check: if it doesn't start with @, no resolution.
	if text:sub(1, 1) ~= "@" then return text end

	-- "@namespace:key" pattern. The key part can contain colons and
	-- dots; we only split on the FIRST colon after the @ prefix.
	local ns, key = text:sub(2):match("^([^:]+):(.+)$")
	if not ns or not key then
		-- Malformed prefix (e.g., "@foo" with no colon). Pass through;
		-- the consumer probably meant a literal.
		return text
	end

	-- Locate Cairn-Locale-1.0 lazily so consumers who don't ship Locale
	-- still get the literal-pass-through path without an error.
	local Locale = LibStub("Cairn-Locale-1.0", true)
	if not Locale or not Locale.Get then return text end

	local instance = Locale.Get(ns)
	if not instance then return text end

	-- Resolve through the instance's prototype, NOT through attribute
	-- access on the instance. Cairn-Locale's instance metatable treats
	-- unknown attribute reads as translation lookups (so `instance.Foo`
	-- emits a missing-key warning for Foo). Probing `instance.Lookup`
	-- on every call would generate noise for the entire user base.
	-- Three cases to handle:
	--   * mt.__index is a TABLE (prototype): rawget the method.
	--   * mt.__index is a FUNCTION (Cairn-Locale's pattern): we can't
	--     introspect, but the function is known to route via proto.Get,
	--     so call instance.Get directly. The function will see "Get" as
	--     a known proto key and return the function without warning.
	--   * No metatable: nothing we can do; bail to literal pass-through.
	local resolved
	local mt    = getmetatable(instance)
	local idx   = mt and mt.__index
	if type(idx) == "table" then
		local lookup = rawget(idx, "Lookup")
		local getter = rawget(idx, "Get")
		if type(lookup) == "function" then
			resolved = lookup(instance, key)
		elseif type(getter) == "function" then
			resolved = getter(instance, key)
		end
	elseif type(idx) == "function" then
		-- Function-style __index. Touching `instance.Get` returns
		-- proto.Get (a known key on the proto) without tripping the
		-- missing-key path. We rely on the convention that any locale
		-- lib using function-style __index exposes Get.
		local getter = instance.Get
		if type(getter) == "function" then
			resolved = getter(instance, key)
		end
	end
	return resolved or text
end

-- ----- Mixin convenience -----------------------------------------------

function Base:_resolveText(text)
	return lib:ResolveText(text, self)
end
