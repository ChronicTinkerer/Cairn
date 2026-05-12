-- Cairn-Slash
-- Slash command registry with nested subcommand routing and recursive
-- auto-help.
--
-- Leaf commands:
--   local slash = LibStub("Cairn-Slash-1.0"):Register("Forge", "/forge", {
--       aliases = { "/fg" },
--   })
--   slash:Sub("logs", openLogs, "open Forge_Logs")
--
-- Nested subcommands:
--   local dev = slash:Sub("dev", "developer tools")    -- group, no handler
--   dev:Sub("locale", setLocale, "set locale override")
--   dev:Sub("logs",   devLogs,   "open dev logs viewer")
--
-- Root-level fallback (and any node-level fallback):
--   slash:Default(function(msg) print("unknown: " .. msg) end)
--
-- A node can have BOTH a handler and nested subs:
--   local db = slash:Sub("db", showDb, "show DB state")
--   db:Sub("reset", resetDb, "reset to defaults")
--   -- /forge db          -> showDb("")
--   -- /forge db reset    -> resetDb("")
--   -- /forge db zzz      -> showDb("zzz")
--
-- Public API:
--   local CS = LibStub("Cairn-Slash-1.0")
--   CS:Register(name, slash, opts)  -> root instance
--   CS:Get(name)                    -- registered lookup
--   CS.registry                     -- { [name] = root instance }
--   CS:GetArgs(str, numargs)        -- parse N args + remaining tail;
--                                      hyperlink / texture / quote-aware.
--                                      Decision 2 from the 2026-05-12 walk.
--   CS:RegisterChatCommand(target, cmd, fn, persist)  -- flat slash registration
--                                                     -- with per-embed tracking.
--                                                     -- MINOR 17, Decision 1.
--   CS:UnregisterChatCommand(target, cmd)
--   CS:OnEmbedDisable(target)       -- auto-cleanup non-persist slashes
--   CS:GetChatCommands(target)      -- list of {command, key, persist, fn}
--
-- Instance methods (chainable; available on every node — root and subs):
--   instance:Sub(name, handler, description)   -- leaf:  handler is a function
--   instance:Sub(name, description)            -- group: description is a string
--   instance:Sub(name)                         -- group with no description
--   instance:Default(handler)                  -- set this node's handler
--   instance:GetSubs()                         -- { [name] = sub node }
--   instance:RegisterSubcommand(localeKey, handler, opts)  -- MINOR 16, D3:
--                                              -- locale-fallback sub
--                                              -- matching (registers both
--                                              -- current-locale form and
--                                              -- English form via Cairn-
--                                              -- Locale). Case-insensitive
--                                              -- match on user-typed token.
--
-- Dispatch rules:
--   - Walk the tree as far as msg's leading tokens match nested sub names.
--   - At the deepest matched node, call that node's `_handler` (set via
--     :Sub's handler arg, or :Default on the node itself) with the unmatched
--     remainder of msg as `rest`.
--   - If the matched node has no `_handler`, the auto-help fallback prints
--     every reachable sub from that node as a full slash path.
--
-- Auto-help is recursive: from the matched node, we enumerate ALL descendant
-- subs and print their full slash paths. No way to end up with an incomplete
-- help view because of nested commands hiding behind a group.
--
-- License: MIT. Author: ChronicTinkerer.

local LIB_MAJOR = "Cairn-Slash-1.0"
local LIB_MINOR = 17

local Cairn_Slash = LibStub:NewLibrary(LIB_MAJOR, LIB_MINOR)
if not Cairn_Slash then return end

local CU = LibStub("Cairn-Util-1.0")
local Pcall = CU.Pcall


Cairn_Slash.registry = Cairn_Slash.registry or {}


-- ---------------------------------------------------------------------------
-- Node methods (mounted via metatable __index on every node — root + subs)
-- ---------------------------------------------------------------------------

local SlashMethods = {}
local SlashMeta = { __index = SlashMethods }


-- _fullSlash is computed once at construction time so auto-help can emit
-- the full slash path of any node without walking up _parent each time.
-- Worth the duplication: help generation runs on every fallback dispatch.
local function newNode(parent, name, handler, description)
    return setmetatable({
        _name        = name,
        _fullSlash   = parent._fullSlash .. " " .. name,
        _handler     = handler,
        _description = description,
        _subs        = {},
        _parent      = parent,
    }, SlashMeta)
end


-- Overloaded by type of the second arg. The point is that the consumer
-- never has to pick a different method for "leaf" vs "group" — both look
-- the same at the call site, the lib disambiguates internally:
--
--   :Sub("foo", fn, "desc")  -- leaf with handler
--   :Sub("foo", "desc")      -- group, description only
--   :Sub("foo")              -- bare group
--
-- Re-registering an existing name is idempotent and acts as a setter for
-- handler / description if a newer value is supplied. This lets a consumer
-- declare a group first then later attach a handler without API ceremony.
function SlashMethods:Sub(name, handlerOrDescription, description)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Slash :Sub: name must be a non-empty string", 2)
    end

    local handler
    if type(handlerOrDescription) == "function" then
        handler = handlerOrDescription
        -- third arg is description (or nil)
    elseif type(handlerOrDescription) == "string" then
        if description ~= nil then
            error("Cairn-Slash :Sub: cannot pass description twice", 2)
        end
        description = handlerOrDescription
    elseif handlerOrDescription ~= nil then
        error("Cairn-Slash :Sub: second arg must be a function, string, or nil", 2)
    end

    if description ~= nil and type(description) ~= "string" then
        error("Cairn-Slash :Sub: description must be a string", 2)
    end

    local existing = self._subs[name]
    if existing then
        if handler ~= nil then existing._handler = handler end
        if description ~= nil then existing._description = description end
        return existing
    end

    local sub = newNode(self, name, handler, description)
    self._subs[name] = sub
    return sub
end


-- :Default exists so consumers can attach a handler AFTER a group node was
-- already created (e.g. group declared first for sub-tree definition, then
-- behavior added later). It's the same _handler slot that :Sub's function
-- form sets — there's only one handler per node — so this is also the way
-- to "reassign" a handler after the fact.
function SlashMethods:Default(handler)
    if type(handler) ~= "function" then
        error("Cairn-Slash :Default: handler must be a function", 2)
    end
    self._handler = handler
    return self
end


-- Returned table is the LIVE _subs map, not a copy. Consumers walking it
-- mid-modification should snapshot first. Used by Forge_Registry for
-- introspection; mutate at your own risk.
function SlashMethods:GetSubs()
    return self._subs
end


-- :RegisterSubcommand(localeKey, handler, opts) — Decision 3, MINOR 16
--
-- Registers a sub-command that matches BOTH the current-locale form AND
-- the English fallback form via Cairn-Locale. Non-English-client users
-- can follow guides / Discord posts using English command names verbatim
-- while still typing the localized form natively.
--
--   slash:RegisterSubcommand("reset", resetFn, "reset the addon")
--   -- On enUS client: matches "/forge reset"
--   -- On deDE client (if L["reset"] = "zuruecksetzen"):
--   --   matches BOTH "/forge zuruecksetzen" AND "/forge reset"
--
-- opts.description (string)        — auto-help text (forwarded to :Sub)
-- opts.strictLocale (bool)         — when true, register ONLY the current-
--                                    locale form; English fallback skipped.
--                                    For consumers that explicitly don't
--                                    want English aliases.
--
-- The locale-key arg is treated as the phrase ID looked up in the root
-- node's `_addonName` (set at `:Register` time). When Cairn-Locale isn't
-- loaded OR the phrase ID isn't registered, the lib falls back to using
-- the locale-key string itself as the sub name (matching existing :Sub
-- semantics — predictable degradation).
--
-- Case-insensitive matching is enabled for every sub registered via this
-- path: the user-typed token is lowercased for lookup against the
-- registered names' lowercase forms. Locale strings stay in their
-- consumer-declared case (e.g. German nouns stay capitalized). The
-- existing `:Sub` continues to do case-sensitive matching for backward-
-- compat.
function SlashMethods:RegisterSubcommand(localeKey, handler, opts)
    if type(localeKey) ~= "string" or localeKey == "" then
        error("Cairn-Slash :RegisterSubcommand: localeKey must be a non-empty string", 2)
    end
    if type(handler) ~= "function" then
        error("Cairn-Slash :RegisterSubcommand: handler must be a function", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("Cairn-Slash :RegisterSubcommand: opts must be a table or nil", 2)
    end
    opts = opts or {}

    -- Walk up to the root node to read the addonName. The root sets
    -- _addonName via :Register; child nodes inherit by walking _parent.
    local root = self
    while root._parent do root = root._parent end
    local addonName = rawget(root, "_addonName") or rawget(root, "_name")

    -- Resolve current-locale and English-fallback names through Cairn-
    -- Locale's phrase API. Both methods return nil on total miss; the
    -- key string itself is the safe fallback so the consumer still gets
    -- a working sub even without locale wiring.
    local Locale = LibStub and LibStub("Cairn-Locale-1.0", true)
    local currentName, englishName = localeKey, nil
    if Locale and addonName then
        local phrase = Locale.GetPhrase and Locale:GetPhrase(addonName, localeKey)
        if type(phrase) == "string" and phrase ~= "" then
            currentName = phrase
        end
        if not opts.strictLocale then
            local enUS = Locale.GetEnglishFallback
                     and Locale:GetEnglishFallback(addonName, localeKey)
            if type(enUS) == "string" and enUS ~= "" and enUS ~= currentName then
                englishName = enUS
            end
        end
    end

    -- Register the current-locale form via :Sub.
    local sub = self:Sub(currentName, handler, opts.description)

    -- Mirror into case-insensitive lookup map so user-typed lowercase
    -- tokens match the capitalized locale form on dispatch.
    self._subsLower = self._subsLower or {}
    self._subsLower[currentName:lower()] = sub

    -- Register English form as an additional route to the same sub, but
    -- ONLY when different from the current form (avoids duplicate
    -- registration on enUS clients).
    if englishName then
        -- Don't call :Sub a second time — that creates a new node. Instead
        -- alias the existing sub node into the parent's `_subs` map under
        -- the English name + lowercase variant.
        self._subs[englishName] = sub
        self._subsLower[englishName:lower()] = sub
    end

    return sub
end


-- ---------------------------------------------------------------------------
-- Dispatch + auto-help
-- ---------------------------------------------------------------------------

-- Recursive walk. The auto-help requirement is "show EVERY reachable sub,
-- not just the immediate level" so consumers don't get a misleading partial
-- view when a sub-tree exists.
local function collectPaths(node, lines)
    for _, sub in pairs(node._subs) do
        lines[#lines + 1] = { path = sub._fullSlash, description = sub._description }
        collectPaths(sub, lines)
    end
end


-- pairs() iteration order is undefined; sort the collected paths so a user
-- running /forge twice gets the same help layout both times. Alignment via
-- maxLen pad keeps descriptions visually columned regardless of path length.
local function printHelp(node)
    local lines = {}
    collectPaths(node, lines)
    table.sort(lines, function(a, b) return a.path < b.path end)

    print(("|cffffaa00%s|r commands:"):format(node._fullSlash))
    if #lines == 0 then
        print("  (no subcommands registered)")
        return
    end

    -- Align descriptions on the longest path
    local maxLen = 0
    for _, line in ipairs(lines) do
        if #line.path > maxLen then maxLen = #line.path end
    end
    local fmt = "  %-" .. maxLen .. "s  %s"
    for _, line in ipairs(lines) do
        if line.description then
            print(fmt:format(line.path, line.description))
        else
            print("  " .. line.path)
        end
    end
end


-- dispatch(node, msg)
-- Walks as deep as tokens match, calls deepest matched node's handler with
-- the unmatched remainder. Three notable behaviors:
--
--   1. /forge dev locale enUS   → matches "dev" then "locale"; locale's
--      handler gets "enUS" as msg
--   2. /forge dev zzz            → matches "dev"; "zzz" doesn't match any
--      of dev's subs, so dev's handler gets "zzz" as msg
--   3. /forge dev (no rest)      → matches "dev"; if dev has a handler it
--      gets "" as msg, else auto-help fires for dev's subtree
--
-- The pcall around the handler call is the standard "one bad consumer
-- shouldn't break the slash UI" pattern.
local function dispatch(node, msg)
    msg = msg or ""

    local subName, rest = msg:match("^(%S+)%s*(.*)$")
    if subName then
        -- Case-sensitive first (preserves existing :Sub semantics).
        local target = node._subs[subName]
        -- MINOR 16 (D3): case-insensitive fallback for subs registered
        -- via :RegisterSubcommand. The user-typed token is lowercased
        -- and matched against `_subsLower`; locale strings keep their
        -- consumer-declared case.
        if not target and node._subsLower then
            target = node._subsLower[subName:lower()]
        end
        if target then
            return dispatch(target, rest or "")
        end
    end

    if node._handler then
        Pcall.Call(("Cairn-Slash: %s handler"):format(node._fullSlash),
            node._handler, msg)
        return
    end

    printHelp(node)
end


-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Register is the only entry-point onto the lib; everything else hangs off
-- the returned root node via chained :Sub/:Default calls. Aliases route
-- to the same dispatcher, so /forge and /fg are indistinguishable from the
-- user's perspective. The CAIRN_SLASH_ prefix on the SLASH_/SlashCmdList
-- keys is what keeps multiple consumers' slash commands from colliding in
-- WoW's global slash registry.
function Cairn_Slash:Register(name, slashStr, opts)
    if type(name) ~= "string" or name == "" then
        error("Cairn-Slash:Register: name must be a non-empty string", 2)
    end
    if type(slashStr) ~= "string" or not slashStr:match("^/") then
        error("Cairn-Slash:Register: slash must be a string starting with '/'", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("Cairn-Slash:Register: opts must be a table or nil", 2)
    end

    local existing = self.registry[name]
    if existing then return existing end

    local aliases = opts and opts.aliases or {}
    if type(aliases) ~= "table" then
        error("Cairn-Slash:Register: opts.aliases must be a list of strings", 2)
    end
    for i, alias in ipairs(aliases) do
        if type(alias) ~= "string" or not alias:match("^/") then
            error(("Cairn-Slash:Register: alias #%d must be a string starting with '/'"):format(i), 2)
        end
    end

    local root = setmetatable({
        _name      = name,
        -- MINOR 16: addonName for Cairn-Locale routing in :RegisterSubcommand
        -- (D3 locale-fallback). Defaults to the consumer's `name` arg
        -- which matches the typical Cairn-Locale instance name. The
        -- `opts.addonName` override exists for consumers whose slash-
        -- registration name differs from their Cairn-Locale instance.
        _addonName = (opts and opts.addonName) or name,
        _fullSlash = slashStr,
        _aliases   = aliases,
        _handler   = nil,
        _subs      = {},
        _parent    = nil,
    }, SlashMeta)

    local key = "CAIRN_SLASH_" .. name:upper()
    _G["SLASH_" .. key .. "1"] = slashStr
    for i, alias in ipairs(aliases) do
        _G["SLASH_" .. key .. (i + 1)] = alias
    end
    _G.SlashCmdList[key] = function(msg) dispatch(root, msg) end

    self.registry[name] = root
    return root
end


-- Cairn_Slash:Get(name)
function Cairn_Slash:Get(name)
    return self.registry[name]
end


-- ---------------------------------------------------------------------------
-- :GetArgs(str, numargs) — hyperlink / texture / quote-aware arg parser
-- ---------------------------------------------------------------------------
-- Cairn-Slash Decision 2 (locked 2026-05-12).
--
-- Splits `str` into `numargs` args plus a remaining tail. Handles three
-- non-trivial cases that naive `strsplit(" ", ...)` corrupts:
--
--   1. "quoted strings"
--   2. Blizzard hyperlinks  |H...|h[Display Text]|h
--      (item, quest, achievement, spell, encounter, glyph, faction,
--       talent, currency, etc. — they all share the |H...|h[...]|h
--       envelope)
--   3. Texture escapes  |T...|t
--
-- Returns `(arg1, arg2, ..., argN, remaining)`. `remaining` is the
-- unparsed tail with leading whitespace stripped. Args beyond what `str`
-- contains are returned as nil.
--
-- Examples:
--
--   :GetArgs("foo bar baz", 2)
--     -> "foo", "bar", "baz"
--
--   :GetArgs('waypoint "Cathedral Square"', 2)
--     -> "waypoint", "Cathedral Square", ""
--
--   :GetArgs('show |Hitem:9351|h[Twill Belt]|h details', 2)
--     -> "show", "|Hitem:9351|h[Twill Belt]|h", "details"
--
-- Snippet "Hyperlink + texture-aware string arg parser" captured in
-- WOW_SNIPPETS.md (this implementation is the canonical Cairn version).
function Cairn_Slash:GetArgs(str, numargs)
    if type(str) ~= "string" then
        error("Cairn-Slash:GetArgs: str must be a string", 2)
    end
    numargs = numargs or 1
    if type(numargs) ~= "number" or numargs < 1 then
        error("Cairn-Slash:GetArgs: numargs must be a positive integer", 2)
    end

    local results = {}
    local pos = 1
    local len = #str

    for i = 1, numargs do
        -- Skip leading whitespace.
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end

        if pos > len then
            results[i] = nil
        else
            local startChar    = str:sub(pos, pos)
            local startTwoChar = str:sub(pos, pos + 1)
            local token

            if startChar == '"' then
                -- Quoted: extract until the next unescaped quote. No quote
                -- escape syntax is supported; "\\\"" inside a quoted string
                -- would terminate it. Documented limitation.
                local closingPos = str:find('"', pos + 1, true)
                if closingPos then
                    token = str:sub(pos + 1, closingPos - 1)
                    pos = closingPos + 1
                else
                    -- Unmatched quote — consume rest of string as the token.
                    token = str:sub(pos + 1)
                    pos = len + 1
                end
            elseif startTwoChar == "|H" then
                -- Hyperlink. Structure: |H<metadata>|h[<display>]|h
                -- Two `|h` occurrences inside the link. Find both; the
                -- token ends at the second one's end.
                local firstH = str:find("|h", pos + 2, true)
                if firstH then
                    local secondH = str:find("|h", firstH + 2, true)
                    if secondH then
                        token = str:sub(pos, secondH + 1)
                        pos = secondH + 2
                    end
                end
                if not token then
                    -- Malformed hyperlink — fall back to whitespace-split.
                    local nextWs = str:find("%s", pos)
                    token = str:sub(pos, (nextWs or len + 1) - 1)
                    pos = (nextWs or len + 1)
                end
            elseif startTwoChar == "|T" then
                -- Texture escape: |T<path>|t
                local closeT = str:find("|t", pos + 2, true)
                if closeT then
                    token = str:sub(pos, closeT + 1)
                    pos = closeT + 2
                else
                    -- Malformed texture — whitespace-split fallback.
                    local nextWs = str:find("%s", pos)
                    token = str:sub(pos, (nextWs or len + 1) - 1)
                    pos = (nextWs or len + 1)
                end
            else
                -- Plain token: until next whitespace.
                local nextWs = str:find("%s", pos)
                token = str:sub(pos, (nextWs or len + 1) - 1)
                pos = (nextWs or len + 1)
            end

            results[i] = token
        end
    end

    -- Trim leading whitespace from the remaining tail so consumers
    -- don't have to.
    while pos <= len and str:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    results[numargs + 1] = str:sub(pos)

    return unpack(results, 1, numargs + 1)
end


-- ---------------------------------------------------------------------------
-- :RegisterChatCommand + per-embed registry (MINOR 17, Decision 1)
-- ---------------------------------------------------------------------------
-- Parallel API to :Register/:Sub for FLAT slash registration. A consumer
-- (or "embed" — typically a module within a larger addon) registers a
-- single slash → handler with a `target` token, and Cairn-Slash tracks
-- it in a per-target registry. The consumer's `OnEmbedDisable` lifecycle
-- (or any time they want to clean up) calls `:OnEmbedDisable(target)`
-- and every non-persist slash for that target unregisters automatically.
--
--   Cairn.Slash:RegisterChatCommand(myModule, "myaction",
--       function(msg) myModule:Action(msg) end)
--
--   -- /myaction <msg>  routes to the handler
--
--   -- Later, when myModule's parent addon shuts down a sub-module:
--   Cairn.Slash:OnEmbedDisable(myModule)
--   -- /myaction now does nothing — the slash is unregistered
--
-- `persist = true` keeps the slash alive across `:OnEmbedDisable` calls.
-- Use for top-level addon commands that should survive Disable/Enable
-- cycles. Default `persist = false` is the right default for the common
-- case (module-scoped slashes).
--
-- The lib generates a unique `CAIRN_CHATCMD_<counter>` SLASH key per
-- registration so multiple consumers can never collide on WoW's global
-- slash registry — no matter what string commands they pick.
--
-- Pattern reference: AceConsole-3.0's `:RegisterChatCommand` shape.
-- Cairn-Slash re-implements the per-embed registry pattern natively.

-- Per-target registry. `_chatCommands[target] = { {command, key, persist, fn}, ... }`
Cairn_Slash._chatCommands = Cairn_Slash._chatCommands or {}

-- Monotonic counter for unique SLASH_<key>N keys. Survives lib upgrades
-- via the `or 0` initialization so post-upgrade registrations don't
-- collide with pre-upgrade ones.
Cairn_Slash._chatCmdCounter = Cairn_Slash._chatCmdCounter or 0


-- Internal: install a SlashCmdList entry for one command. Returns the
-- SLASH key used so :UnregisterChatCommand can find + remove it.
local function installChatCommand(command, fn)
    Cairn_Slash._chatCmdCounter = Cairn_Slash._chatCmdCounter + 1
    local key = "CAIRN_CHATCMD_" .. Cairn_Slash._chatCmdCounter
    -- Normalize: accept "foo" or "/foo" as the input, register "/foo".
    local normalized = command:sub(1, 1) == "/" and command or ("/" .. command)
    _G["SLASH_" .. key .. "1"] = normalized
    if _G.SlashCmdList then
        _G.SlashCmdList[key] = function(msg)
            Pcall.Call(("Cairn-Slash: chat command %s"):format(normalized), fn, msg)
        end
    end
    return key, normalized
end


-- Internal: remove a SlashCmdList entry.
local function uninstallChatCommand(key)
    if _G.SlashCmdList then
        _G.SlashCmdList[key] = nil
    end
    _G["SLASH_" .. key .. "1"] = nil
end


-- :RegisterChatCommand(target, command, fn, persist) — flat slash registration
--
-- target  any            — opaque key. Typically the consumer module
--                          table. Cairn-Slash never inspects it; just
--                          uses it for registry partitioning.
-- command string         — slash command name. Leading "/" optional —
--                          "foo" and "/foo" both register "/foo".
-- fn      function       — handler called with the chat message after
--                          the slash (`""` if no args).
-- persist bool, optional — when true, this slash survives
--                          `:OnEmbedDisable(target)`. Default false.
--
-- Returns the generated SLASH key on success. Errors loudly on bad input.
function Cairn_Slash:RegisterChatCommand(target, command, fn, persist)
    if target == nil then
        error("Cairn-Slash:RegisterChatCommand: target must not be nil", 2)
    end
    if type(command) ~= "string" or command == "" then
        error("Cairn-Slash:RegisterChatCommand: command must be a non-empty string", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn-Slash:RegisterChatCommand: fn must be a function", 2)
    end
    if persist ~= nil and type(persist) ~= "boolean" then
        error("Cairn-Slash:RegisterChatCommand: persist must be a boolean or nil", 2)
    end

    local key, normalized = installChatCommand(command, fn)

    local bucket = self._chatCommands[target]
    if not bucket then
        bucket = {}
        self._chatCommands[target] = bucket
    end
    bucket[#bucket + 1] = {
        command  = normalized,
        key      = key,
        persist  = persist == true,
        fn       = fn,
    }
    return key
end


-- :UnregisterChatCommand(target, command) — remove one specific command
-- registered for `target`. Walks the target's bucket and removes the
-- first match by normalized command string. Returns true on success.
function Cairn_Slash:UnregisterChatCommand(target, command)
    if target == nil then
        error("Cairn-Slash:UnregisterChatCommand: target must not be nil", 2)
    end
    if type(command) ~= "string" or command == "" then
        error("Cairn-Slash:UnregisterChatCommand: command must be a non-empty string", 2)
    end
    local bucket = self._chatCommands[target]
    if not bucket then return false end

    local normalized = command:sub(1, 1) == "/" and command or ("/" .. command)
    for i, entry in ipairs(bucket) do
        if entry.command == normalized then
            uninstallChatCommand(entry.key)
            table.remove(bucket, i)
            if #bucket == 0 then
                self._chatCommands[target] = nil
            end
            return true
        end
    end
    return false
end


-- :OnEmbedDisable(target) — walk target's chat commands, unregister non-
-- persist ones. Persist commands stay registered. Returns count of
-- commands that were unregistered.
function Cairn_Slash:OnEmbedDisable(target)
    if target == nil then
        error("Cairn-Slash:OnEmbedDisable: target must not be nil", 2)
    end
    local bucket = self._chatCommands[target]
    if not bucket then return 0 end

    local removed = 0
    -- Walk backward so table.remove doesn't shift the iteration index.
    for i = #bucket, 1, -1 do
        local entry = bucket[i]
        if not entry.persist then
            uninstallChatCommand(entry.key)
            table.remove(bucket, i)
            removed = removed + 1
        end
    end
    if #bucket == 0 then
        self._chatCommands[target] = nil
    end
    return removed
end


-- :GetChatCommands(target) — read-only access to a target's registered
-- chat commands. Returns the live array (consumers walking it mid-
-- modification should snapshot). Returns nil if the target has no
-- registered commands. Used by Forge_Registry for introspection.
function Cairn_Slash:GetChatCommands(target)
    return self._chatCommands[target]
end


return Cairn_Slash
