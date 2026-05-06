--[[
Cairn-Comm-1.0

Addon-to-addon messaging built on CHAT_MSG_ADDON. Each addon picks a
prefix (max 16 chars), subscribes to incoming messages on that prefix,
and sends strings on PARTY / RAID / INSTANCE_CHAT / GUILD / WHISPER.

Public API:

    -- Subscribe. Returns an unsubscribe closure.
    local unsub = Cairn.Comm:Subscribe("MYADDON", function(msg, channel, sender)
        -- handle incoming
    end, "MyAddon")    -- last arg = owner (anything; used by UnsubscribeAll)

    unsub()                                           -- single subscriber off
    Cairn.Comm:UnsubscribeAll("MyAddon")              -- everything from owner

    -- Send. channel is one of PARTY / RAID / INSTANCE_CHAT / GUILD / WHISPER.
    -- target is required for WHISPER, ignored otherwise.
    Cairn.Comm:Send("MYADDON", "hello", "PARTY")
    Cairn.Comm:Send("MYADDON", "hi steve", "WHISPER", "Steven-Area52")

    -- Broadcast: picks the best group channel automatically.
    --   in raid -> RAID; in party -> PARTY; else GUILD if guilded; else nil.
    Cairn.Comm:SendBroadcast("MYADDON", "hello")

    -- Inspect.
    Cairn.Comm:IsRegistered("MYADDON")    -- whether we've told WoW to listen
    Cairn.Comm:CountSubscribers("MYADDON")

Notes:
* Each prefix is registered with WoW (via C_ChatInfo.RegisterAddonMessagePrefix)
  on first :Subscribe. Other addons that share the same prefix will see your
  messages and vice versa - chooseunique prefixes (typically your addon name).
* WoW caps each message at 255 chars. Payload chunking is the caller's
  problem in v0.2; later versions may add automatic split/reassembly.
* Handler errors are pcall-trapped and routed to geterrorhandler() so a
  single broken handler doesn't kill its peers.
]]

local MAJOR, MINOR = "Cairn-Comm-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- Preserve state across LibStub upgrades within a session.
lib.subscribers = lib.subscribers or {}    -- prefix -> array of { fn, owner }
lib.registered  = lib.registered  or {}    -- prefix -> true
lib._frame      = lib._frame      or nil   -- single CHAT_MSG_ADDON listener

local VALID_CHANNELS = {
    PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, WHISPER = true,
}

-- ----- Internal helpers -------------------------------------------------

local function ensureFrame()
    if lib._frame then return lib._frame end
    if not CreateFrame then return nil end
    local f = CreateFrame("Frame")  -- anonymous; named frames are noisier with ADDON_ACTION_FORBIDDEN
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
        local subs = lib.subscribers[prefix]
        if not subs then return end
        for _, sub in ipairs(subs) do
            if sub and not sub._removed and type(sub.fn) == "function" then
                local ok, err = pcall(sub.fn, message, channel, sender)
                if not ok and geterrorhandler then geterrorhandler()(err) end
            end
        end
    end)
    lib._frame = f
    return f
end

local function registerPrefix(prefix)
    if lib.registered[prefix] then return true end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        lib.registered[prefix] = ok and true or false
        return lib.registered[prefix]
    end
    if RegisterAddonMessagePrefix then
        local ok = RegisterAddonMessagePrefix(prefix)
        lib.registered[prefix] = ok and true or false
        return lib.registered[prefix]
    end
    return false
end

-- ----- Subscription -----------------------------------------------------

function lib:Subscribe(prefix, fn, owner)
    if type(prefix) ~= "string" or prefix == "" then
        error("Cairn.Comm:Subscribe: prefix must be a non-empty string", 2)
    end
    if #prefix > 16 then
        error("Cairn.Comm:Subscribe: prefix max 16 chars (got " .. #prefix .. ")", 2)
    end
    if type(fn) ~= "function" then
        error("Cairn.Comm:Subscribe: fn must be a function", 2)
    end

    ensureFrame()
    registerPrefix(prefix)

    self.subscribers[prefix] = self.subscribers[prefix] or {}
    local sub = { fn = fn, owner = owner, _removed = false }
    table.insert(self.subscribers[prefix], sub)

    return function()
        sub._removed = true
        local list = self.subscribers[prefix]
        if list then
            for i, s in ipairs(list) do
                if s == sub then table.remove(list, i); break end
            end
            if #list == 0 then self.subscribers[prefix] = nil end
        end
    end
end

function lib:UnsubscribeAll(owner)
    if owner == nil then return end
    for prefix, list in pairs(self.subscribers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                list[i]._removed = true
                table.remove(list, i)
            end
        end
        if #list == 0 then self.subscribers[prefix] = nil end
    end
end

function lib:CountSubscribers(prefix)
    local list = self.subscribers[prefix]
    return list and #list or 0
end

function lib:IsRegistered(prefix)
    return self.registered[prefix] and true or false
end

-- ----- Send -------------------------------------------------------------

function lib:Send(prefix, message, channel, target)
    if type(prefix) ~= "string" or prefix == "" then
        error("Cairn.Comm:Send: prefix must be a non-empty string", 2)
    end
    if type(message) ~= "string" then
        error("Cairn.Comm:Send: message must be a string", 2)
    end
    if not VALID_CHANNELS[channel] then
        error("Cairn.Comm:Send: channel must be one of PARTY/RAID/INSTANCE_CHAT/GUILD/WHISPER (got "
            .. tostring(channel) .. ")", 2)
    end
    if channel == "WHISPER" and (type(target) ~= "string" or target == "") then
        error("Cairn.Comm:Send: WHISPER requires a non-empty target", 2)
    end

    -- Make sure WoW knows about this prefix; senders register too because
    -- some clients require it before SendAddonMessage works.
    registerPrefix(prefix)

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return C_ChatInfo.SendAddonMessage(prefix, message, channel, target)
    end
    if SendAddonMessage then
        return SendAddonMessage(prefix, message, channel, target)
    end
end

-- Pick the best group channel for a broadcast. Falls back to GUILD if not
-- in a group, returns nil if no channel is available (solo + no guild).
function lib:GetBroadcastChannel()
    if IsInRaid and IsInRaid() then
        if IsInGroup and IsInGroup(2) then  -- LE_PARTY_CATEGORY_INSTANCE = 2
            return "INSTANCE_CHAT"
        end
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        if IsInGroup(2) then return "INSTANCE_CHAT" end
        return "PARTY"
    end
    if IsInGuild and IsInGuild() then return "GUILD" end
    return nil
end

function lib:SendBroadcast(prefix, message)
    local channel = self:GetBroadcastChannel()
    if not channel then return false, "no group / guild to broadcast on" end
    return self:Send(prefix, message, channel)
end
