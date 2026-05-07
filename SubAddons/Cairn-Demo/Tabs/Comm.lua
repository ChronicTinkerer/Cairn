--[[
Cairn-Demo / Tabs / Comm

Live demo of Cairn-Comm-1.0. Subscribes to a demo prefix and lets the user
fire WHISPER messages to themselves -- the easiest way to round-trip an
addon message without needing a second player.

Cairn-Demo/Tabs/Comm (c) 2026 ChronicTinkerer. MIT license.
]]

local Demo = _G.CairnDemo
if not Demo then return end

local Gui  = Demo.lib
local Comm = LibStub("Cairn-Comm-1.0")

local PREFIX = "CAIRNDEMO"
local OWNER  = "CairnDemo.CommTab"

local function build(pane, demo)
	local _, live = demo:BuildTabShell(pane,
		"Cairn-Comm-1.0",
		demo.Snippets.comm)
	if not live then return end

	live.Cairn:SetLayout("Stack",
		{ direction = "vertical", gap = 6, padding = 12 })

	demo:AppendIntro(live,
		"Addon-to-addon CHAT_MSG_ADDON wrapper. Self-WHISPER is the simplest round-trip: register a subscriber, send a WHISPER to yourself, and watch the handler fire.")

	local consoleHolder = Gui:Acquire("Container", live, {
		bg          = "color.bg.surface",
		border      = "color.border.subtle",
		borderWidth = 1,
		height      = 220,
	})
	consoleHolder.Cairn:SetLayout("Fill", { padding = 4 })
	local _, console = demo:Console(consoleHolder, { contentHeight = 800 })

	local statusLbl = Gui:Acquire("Label", live, {
		text = "...", variant = "small", align = "left",
	})
	local function refresh()
		statusLbl.Cairn:SetText(("prefix=%q   IsRegistered=%s   subs=%d"):format(
			PREFIX,
			tostring(Comm:IsRegistered(PREFIX)),
			Comm:CountSubscribers(PREFIX) or 0))
	end
	refresh()

	local off
	local row = Gui:Acquire("Container", live, {})
	row.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 6, padding = 0 })
	row:SetHeight(28)

	Gui:Acquire("Button", row, { text = "Subscribe", variant = "primary" })
		.Cairn:On("Click", function()
			if off then console:Print("already subscribed"); return end
			off = Comm:Subscribe(PREFIX, function(msg, channel, sender)
				console:Print(("[recv] sender=%s  channel=%s  msg=%s"):format(
					tostring(sender), tostring(channel), tostring(msg)))
			end, OWNER)
			console:Print("subscribed under " .. OWNER)
			refresh()
		end)

	Gui:Acquire("Button", row, { text = "Send WHISPER -> self", variant = "default" })
		.Cairn:On("Click", function()
			local me = UnitName("player")
			if not me then console:Print("UnitName('player') -> nil"); return end
			-- Realm needed for cross-realm-safe WHISPER target. Fall back
			-- to bare name if GetRealmName isn't available.
			local realm = GetRealmName and GetRealmName() or nil
			local target = realm and (me .. "-" .. realm:gsub(" ", "")) or me
			Comm:Send(PREFIX, "ping " .. tostring(time()), "WHISPER", target)
			console:Print(("sent WHISPER to %s"):format(target))
		end)

	Gui:Acquire("Button", row, { text = "Send PARTY", variant = "default" })
		.Cairn:On("Click", function()
			Comm:Send(PREFIX, "party-ping", "PARTY")
			console:Print("sent PARTY (no-op if not in a party)")
		end)

	Gui:Acquire("Button", row, { text = "SendBroadcast", variant = "default" })
		.Cairn:On("Click", function()
			Comm:SendBroadcast(PREFIX, "broadcast " .. tostring(time()))
			console:Print("SendBroadcast picked best group channel automatically")
		end)

	Gui:Acquire("Button", row, { text = "Unsubscribe", variant = "danger" })
		.Cairn:On("Click", function()
			if off then off(); off = nil; console:Print("unsubscribed"); refresh() end
		end)

	Gui:Acquire("Button", row, { text = "UnsubscribeAll(owner)", variant = "danger" })
		.Cairn:On("Click", function()
			Comm:UnsubscribeAll(OWNER)
			off = nil
			console:Print("UnsubscribeAll: every " .. OWNER .. " sub removed")
			refresh()
		end)

	Gui:Acquire("Button", row, { text = "Clear log", variant = "default" })
		.Cairn:On("Click", function() console:Clear() end)
end

Demo:RegisterTab("comm", {
	label = "Comm",
	order = 140,
	build = build,
})
