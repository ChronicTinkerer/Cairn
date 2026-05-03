--[[
Cairn umbrella facade.

Idempotent and safe to load multiple times. Each Cairn module ships a copy
in its embedded form so authors only need to include the modules they
care about; the facade resolves itself lazily from LibStub.

Usage from any addon (after Cairn or any Cairn module has loaded):

    Cairn.Events:Subscribe("PLAYER_LOGIN", function() ... end, addonName)
    local log = Cairn.Log("MyAddon"); log:Info("loaded v%s", v)
    Cairn.Settings.New("MyAddon", schema)

The first time you index `Cairn.Foo`, the facade asks LibStub for
`Cairn-Foo-1.0` and caches it on the table. If the module isn't loaded
the index returns nil and the caller gets a clean error at their site.

Slash router: any module can register a /cairn subcommand via
`Cairn:RegisterSlashSub(name, fn, helpText)`. The umbrella owns the
single SLASH_CAIRN1 registration so subcommands compose without
collision.
]]

if not Cairn then
	local LibStub = _G.LibStub
	assert(LibStub, "Cairn requires LibStub to be loaded first.")

	Cairn = setmetatable({
		_VERSION    = "0.1.0",
		_NAME       = "Cairn",
		_slashSubs  = {},
	}, {
		__index = function(t, key)
			local libName = "Cairn-" .. tostring(key) .. "-1.0"
			local lib = LibStub(libName, true)
			if lib then
				rawset(t, key, lib)
				return lib
			end
			return nil
		end,
	})

	function Cairn:RegisterSlashSub(name, fn, helpText)
		if type(name) ~= "string" or name == "" then
			error("Cairn:RegisterSlashSub: name must be a non-empty string", 2)
		end
		if type(fn) ~= "function" then
			error("Cairn:RegisterSlashSub: fn must be a function", 2)
		end
		self._slashSubs[name:lower()] = { fn = fn, help = helpText }
	end

	-- Single /cairn registration. Dispatches to subcommands.
	if SlashCmdList then
		SLASH_CAIRN1 = "/cairn"
		SlashCmdList["CAIRN"] = function(msg)
			local sub, rest = (msg or ""):match("^%s*(%S*)%s*(.*)$")
			sub = (sub or ""):lower()

			if sub == "" or sub == "help" or sub == "?" then
				print("|cFF7FBFFF[Cairn]|r v" .. (Cairn._VERSION or "?") .. " commands:")
				local names = {}
				for n in pairs(Cairn._slashSubs) do names[#names + 1] = n end
				table.sort(names)
				if #names == 0 then
					print("  (no subcommands registered)")
				else
					for _, n in ipairs(names) do
						local entry = Cairn._slashSubs[n]
						local help = entry.help and (" - " .. entry.help) or ""
						print(string.format("  /cairn %s%s", n, help))
					end
				end
				return
			end

			local entry = Cairn._slashSubs[sub]
			if entry then return entry.fn(rest) end
			print("|cFF7FBFFF[Cairn]|r unknown subcommand: " .. sub .. "   (try /cairn help)")
		end
	end
end
