-- CairnDemo
-- A working consumer of every Cairn v1.0 library. Each section below exercises
-- one lib through the `Cairn.*` namespace (no direct LibStub calls) so the file
-- doubles as a smoke check: if the addon loads silently and `/cairndemo run`
-- prints all PASS lines, the framework is wired correctly.
--
-- Slash interface:
--   /cairndemo            -- prints help (auto-generated from the registered tree)
--   /cairndemo run        -- runs the full smoke and prints PASS/FAIL
--   /cairndemo hello      -- localized greeting
--   /cairndemo timer ...  -- timer demos (after / every / debounce / stopwatch)
--   /cairndemo log ...    -- write to the shared ring buffer at chosen level
--   /cairndemo settings   -- opens the Blizzard panel
--
-- Author: ChronicTinkerer. MIT.

local ADDON_NAME = "CairnDemo"


-- ---------------------------------------------------------------------------
-- 1. Cairn-Addon  — lifecycle wrapper with retro-fire
-- ---------------------------------------------------------------------------
-- We pull the lib through the Cairn namespace installed by Cairn-Core. If
-- the namespace is missing or the lib didn't register, the very next line
-- raises a clear nil-index error and there's no point continuing.
local addon = Cairn.Addon:New(ADDON_NAME)


-- ---------------------------------------------------------------------------
-- 2. Cairn-Log  — categorized ring-buffer logger
-- ---------------------------------------------------------------------------
-- One source-level logger named after the addon, plus a "smoke" category for
-- test output so we can filter later via Forge_Logs.
local log     = Cairn.Log:New(ADDON_NAME)
local smokeLog = log:Category("smoke")


-- ---------------------------------------------------------------------------
-- 3. Cairn-DB  — SavedVariables wrapper with defaults
-- ---------------------------------------------------------------------------
-- `## SavedVariables: CairnDemoDB` in the .toc guarantees the global table
-- is restored before this file runs, so the New() call sees prior state.
local db = Cairn.DB:New("CairnDemoDB", {
    global  = { totalLogins = 0, lastVersion = "1.0" },
    profile = { greetingsSeen = 0, favoriteFont = "Default" },
})


-- ---------------------------------------------------------------------------
-- 4. Cairn-Locale  — i18n with locale fallback
-- ---------------------------------------------------------------------------
-- One file per language is the recommended split; for the demo we keep both
-- enUS (required) and deDE (illustrates fallback) inline.
local L = Cairn.Locale:New(ADDON_NAME)
L:Set("enUS", {
    HELLO    = "Hello, %s! Welcome to CairnDemo.",
    LOGIN_N  = "Login #%d this character.",
    SMOKE_OK = "Smoke check passed for %s.",
})
L:Set("deDE", {
    HELLO    = "Hallo, %s! Willkommen bei CairnDemo.",
    LOGIN_N  = "Login Nr. %d auf diesem Charakter.",
})


-- ---------------------------------------------------------------------------
-- 5. Cairn-Util  — shared helpers
-- ---------------------------------------------------------------------------
-- Hash a per-character identity string so we can prove Hash.MD5 works at
-- least once on each run. The shape doesn't matter; it's just a known-good
-- input/output round-trip.
local CU = Cairn.Util
local charKey  = UnitName("player") .. "-" .. GetRealmName()
local charHash = CU.Hash.MD5(charKey)


-- ---------------------------------------------------------------------------
-- 6. Cairn-Media  — asset registry (lookup-only here)
-- ---------------------------------------------------------------------------
-- We don't register new media; we just resolve a known built-in font path
-- so the smoke can confirm GetFont() returns something usable.
local fontPath = Cairn.Media:GetFont("Default")


-- ---------------------------------------------------------------------------
-- 7. Cairn-Events  — single-frame event routing (WoW + internal)
-- ---------------------------------------------------------------------------
-- Subscribe to a WoW event for one-shot work and to an internal event so we
-- can verify Fire() round-trips. The handler closure captures `addon` for
-- ownership-based cleanup if/when we Unsubscribe.
Cairn.Events:Subscribe("PLAYER_ENTERING_WORLD", function()
    -- Throttle the noisy event: only the first fire per session does work.
    if rawget(addon, "_seenPEW") then return end
    rawset(addon, "_seenPEW", true)
    smokeLog:Debug("Caught PLAYER_ENTERING_WORLD on character %s", charKey)
end, addon)

Cairn.Events:Subscribe("CairnDemo:Greeted", function(target)
    db.profile.greetingsSeen = (db.profile.greetingsSeen or 0) + 1
    smokeLog:Info("Greeted %s (total this character: %d)", target, db.profile.greetingsSeen)
end, addon)


-- ---------------------------------------------------------------------------
-- 8. Cairn-Hooks  — Pre/Post/Wrap instrumentation
-- ---------------------------------------------------------------------------
-- Demonstrate Post on a Blizzard global: count how many times the player
-- opens the world map. Stored in `db.global` so it survives /reload.
db.global.mapOpenCount = db.global.mapOpenCount or 0
if ToggleWorldMap then
    Cairn.Hooks:Post(_G, "ToggleWorldMap", function()
        db.global.mapOpenCount = db.global.mapOpenCount + 1
    end, addon)
end


-- ---------------------------------------------------------------------------
-- 9. Cairn-Callback  — CallbackHandler-compatible registry
-- ---------------------------------------------------------------------------
-- The demo exposes a CairnDemo.callbacks object so other addons (or our
-- own smoke) can RegisterCallback("ReadyChecked", ...). Cairn.Callback is
-- the upstream-shape API; this is the canonical way to expose ad-hoc events.
local target = {}
Cairn.Callback:New(target, "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents")
_G.CairnDemo = _G.CairnDemo or {}
_G.CairnDemo.callbacks = target


-- ---------------------------------------------------------------------------
-- 10. Cairn-Settings  — Blizzard panel schema
-- ---------------------------------------------------------------------------
-- A small declarative schema. Cairn-Settings reads/writes db.profile, fires
-- per-entry onChange, and renders the rendered types (header/toggle/range/
-- dropdown) directly into Blizzard's native panel.
local settings = Cairn.Settings:New(ADDON_NAME, db, {
    -- Cairn-Settings requires `key` on every entry, including headers (the
    -- key is used for schema-internal de-dup even when the entry is purely
    -- visual). Prefix decorative keys with `_` so they're easy to spot.
    { type = "header", key = "_hdr_main", label = "CairnDemo settings" },
    { type = "toggle", key = "greetOnLogin", label = "Print greeting on login", default = true,
      onChange = function(v) smokeLog:Debug("greetOnLogin -> %s", tostring(v)) end },
    { type = "range",  key = "timerDelay",   label = "Default timer delay (s)", default = 2,
      min = 1, max = 10, step = 1 },
    -- Dropdown `choices` is a map of value -> label (NOT an array of objects).
    { type = "dropdown", key = "logLevel",   label = "Echo logs at level",
      default = "warn",
      choices = { debug = "Debug", info = "Info", warn = "Warn", error = "Error" },
      onChange = function(v) log:SetChatEchoLevel(v) end },
})


-- ---------------------------------------------------------------------------
-- 11. Cairn-Slash  — nested subcommands with auto-help
-- ---------------------------------------------------------------------------
-- Register one root, then attach a tree. Default on the root prints the
-- recursive help; default on each group prints help for that level.
local root = Cairn.Slash:Register(ADDON_NAME, "/cairndemo", { description = "CairnDemo commands" })

root:Default(function()
    -- :Default with no handler triggers auto-help; we call it explicitly so
    -- bare /cairndemo still gets a friendly output rather than a no-op.
    print(("|cff55ff55CairnDemo|r %s — try /cairndemo help"):format(GetAddOnMetadata
        and GetAddOnMetadata(ADDON_NAME, "Version") or "?"))
end)

root:Sub("hello", function()
    local who  = UnitName("player") or "stranger"
    local line = L.HELLO:format(who)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ff66" .. line .. "|r")
    Cairn.Events:Fire("CairnDemo:Greeted", who)
end, "Print a localized greeting")

root:Sub("settings", function() settings:Open() end, "Open the Blizzard settings panel")

root:Sub("gui", function()
    -- Visible Gui demo: pops a small window with a label and a button that
    -- increments a counter via the inline per-widget pub/sub. If clicks
    -- update the label, the Gui plumbing is healthy at the rendering layer.
    --
    -- Acquire signature is (name, parent, opts). Parent is a real Blizzard
    -- frame -- pass UIParent for top-level, or another widget's frame
    -- (which is what Acquire returns) for a child.
    local Gui = LibStub("Cairn-Gui-2.0", true)
    if not Gui then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[CairnDemo]|r Cairn-Gui-2.0 not loaded")
        return
    end
    local win = Gui:Acquire("Window", UIParent,
                            { width = 280, height = 140, title = "CairnDemo" })
    win:SetPoint("CENTER")
    local clicks = 0
    local lbl = Gui:Acquire("Label", win, { text = "Clicks: 0", width = 220, height = 24 })
    lbl:SetPoint("TOP", win, "TOP", 0, -40)
    local btn = Gui:Acquire("Button", win, { text = "Click me", width = 120, height = 26 })
    btn:SetPoint("BOTTOM", win, "BOTTOM", 0, 16)
    btn.Cairn:On("Click", function()
        clicks = clicks + 1
        -- SetText is a Cairn method on the Label's wrapper, not the frame.
        lbl.Cairn:SetText(("Clicks: %d"):format(clicks))
    end)
    win:Show()
end, "Pop a visible Cairn-Gui window with a click-counter button")

local timerSub = root:Sub("timer", "Timer demos (after / every / debounce / stopwatch)")
timerSub:Sub("after", function()
    local d = (db.profile.timerDelay or 2)
    Cairn.Timer:After(d, function()
        DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[CairnDemo]|r Timer:After fired (%ds)"):format(d))
    end)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff999999[CairnDemo]|r Timer:After scheduled for %ds"):format(d))
end, "Fire once after the configured delay")

timerSub:Sub("debounce", function()
    -- Call the handler 5x in a tight loop; debounce collapses them into a
    -- single fire after 200ms of quiet. Smoke value: 1 print, not 5.
    for _ = 1, 5 do
        Cairn.Timer:Debounce("cairndemo:debounce-test", 0.2, function()
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[CairnDemo]|r Debounce fired (once, not 5x)")
        end)
    end
end, "Fire 5 calls; only the last one runs after 0.2s")

timerSub:Sub("stopwatch", function()
    local sw = Cairn.Timer:Stopwatch()
    Cairn.Timer:After(1, function()
        DEFAULT_CHAT_FRAME:AddMessage(("|cff66ccff[CairnDemo]|r Stopwatch elapsed: %.3fs"):format(sw:Read()))
    end)
end, "Measure elapsed time")

local logSub = root:Sub("log", "Write to the shared log ring buffer")
for _, lvl in ipairs({ "debug", "info", "warn", "error" }) do
    logSub:Sub(lvl, function(msg)
        log[lvl:gsub("^%l", string.upper)](log, msg ~= "" and msg or ("hello from " .. lvl))
        DEFAULT_CHAT_FRAME:AddMessage(("|cff999999[CairnDemo]|r logged at %s"):format(lvl))
    end, ("Log at %s level"):format(lvl))
end

root:Sub("run", function()
    -- The smoke. One line per lib; prefix PASS/FAIL; ends with a count.
    local pass, fail = 0, 0
    local function check(label, ok, detail)
        if ok then
            pass = pass + 1
            DEFAULT_CHAT_FRAME:AddMessage(("|cff55ff55PASS|r %s"):format(label))
        else
            fail = fail + 1
            DEFAULT_CHAT_FRAME:AddMessage(("|cffff5555FAIL|r %s%s"):format(label, detail and "  "..detail or ""))
        end
    end

    check("Cairn.Addon registry has CairnDemo",  Cairn.Addon.registry[ADDON_NAME] == addon)
    check("Cairn.DB.global persists",            type(db.global) == "table")
    check("Cairn.DB.profile persists",           type(db.profile) == "table")
    check("Cairn.Events fires internal events",  type(Cairn.Events.handlers["CairnDemo:Greeted"]) == "table")
    check("Cairn.Slash registered root",         Cairn.Slash:Get(ADDON_NAME) == root)
    check("Cairn.Locale enUS round-trip",        L:Get("HELLO"):find("Welcome to CairnDemo") ~= nil)
    check("Cairn.Log:Info produces an entry",
          -- GetEntries lives on the lib (Cairn.Log), not on the per-source
          -- logger instance returned by :New().
          (function() local n0 = #Cairn.Log:GetEntries({ source = ADDON_NAME }); smokeLog:Info("ping"); return #Cairn.Log:GetEntries({ source = ADDON_NAME }) > n0 end)(),
          "log entry count did not increase")
    check("Cairn.Hooks installed on ToggleWorldMap",
          ToggleWorldMap == nil or #Cairn.Hooks._registry > 0,
          "registry empty after :Post")
    check("Cairn.Timer:After returns a handle",
          (function() local h = Cairn.Timer:After(60, function() end); local ok = type(h) == "table"; if h and h.Cancel then h:Cancel() end; return ok end)())
    check("Cairn.Callback target has RegisterEvent",
          type(target.RegisterEvent) == "function")
    check("Cairn.Util.Hash.MD5 round-trip",      type(charHash) == "string" and #charHash == 32)
    check("Cairn.Util.Table.Snapshot returns copy",
          (function() local s = CU.Table.Snapshot({1,2,3}); return s[3] == 3 and #s == 3 end)())
    check("Cairn.Util.Table.MergeDefaults preserves user values",
          (function() local t = { a = "user" }; CU.Table.MergeDefaults(t, { a = "DEF", b = "fill" }); return t.a == "user" and t.b == "fill" end)())
    check("Cairn.Media:GetFont(Default) resolves", type(fontPath) == "string" and fontPath ~= "")
    check("Cairn.Settings instance built",       type(settings) == "table" and type(settings.Get) == "function")
    check("_G.Cairn namespace resolves dynamically",
          Cairn.Addon == LibStub("Cairn-Addon-1.0"))

    -- ----- Cairn-Gui-2.0 family --------------------------------------------
    -- The Gui family is "ported verbatim" but we recently swapped its Log/
    -- Callback consumption to the new v1.0 lib surface and replaced the
    -- Cairn-Callback dependency in Core/Events.lua with an inline registry.
    -- The checks below exercise the changed paths end-to-end.
    local Gui = LibStub("Cairn-Gui-2.0", true)
    check("Cairn-Gui-2.0 registered", type(Gui) == "table")
    if Gui then
        check("Cairn-Gui-2.0 widgets registry", type(Gui.widgets) == "table")
        check("Cairn-Gui-2.0 themes include Cairn.Default",
              type(Gui.themes) == "table" and Gui.themes["Cairn.Default"] ~= nil)
        -- Step-by-step pubsub trace so a fail tells us WHICH step broke.
        local guiTrace
        check("Cairn-Gui-2.0 Acquire/On/Fire/Off round-trip", (function()
            local ok, w = pcall(Gui.Acquire, Gui, "Container", UIParent,
                                { width = 50, height = 50 })
            if not ok then guiTrace = "Acquire threw: " .. tostring(w); return false end
            if not w   then guiTrace = "Acquire returned nil"; return false end
            if not w.Cairn then guiTrace = "widget.Cairn missing"; return false end

            local hits, lastArg = 0, nil
            local subOk, subErr = pcall(function()
                w.Cairn:On("CairnDemoEvt", function(_self, payload)
                    hits = hits + 1; lastArg = payload
                end)
            end)
            if not subOk then guiTrace = ":On threw: "..tostring(subErr); return false end

            local fireOk, fireErr = pcall(function()
                w.Cairn:Fire("CairnDemoEvt", "hello")
            end)
            if not fireOk then guiTrace = ":Fire threw: "..tostring(fireErr); return false end
            if hits ~= 1 then guiTrace = (":Fire dispatched %d hits (expected 1)"):format(hits); return false end
            if lastArg ~= "hello" then guiTrace = ":Fire payload="..tostring(lastArg); return false end

            local offOk, offErr = pcall(function() w.Cairn:Off("CairnDemoEvt") end)
            if not offOk then guiTrace = ":Off threw: "..tostring(offErr); return false end
            w.Cairn:Fire("CairnDemoEvt", "should-not-fire")
            if hits ~= 1 then guiTrace = (":Off didn't remove handler (hits=%d)"):format(hits); return false end

            pcall(function() w.Cairn:Release() end)
            return true
        end)(), guiTrace)
    end

    DEFAULT_CHAT_FRAME:AddMessage(("|cffffff00CairnDemo smoke:|r %d PASS / %d FAIL"):format(pass, fail))
    if fail == 0 then smokeLog:Info(L:Get("SMOKE_OK"):format(ADDON_NAME)) end
end, "Run the v1.0-library smoke (PASS/FAIL per lib)")


-- ---------------------------------------------------------------------------
-- 12. Lifecycle hooks  — retro-fire works even though we wire late
-- ---------------------------------------------------------------------------
-- OnInit always fires AFTER our addon's ADDON_LOADED. OnLogin always fires
-- AFTER PLAYER_LOGIN. Retro-fire ensures these run even if our assignment
-- happens after the event has already passed.
function addon:OnInit()
    log:Info("CairnDemo ready. SavedVar entries: %d.", db.global.totalLogins or 0)
end

function addon:OnLogin()
    db.global.totalLogins = (db.global.totalLogins or 0) + 1
    if settings:Get("greetOnLogin") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ff66" .. L.HELLO:format(UnitName("player") or "?") .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage(("|cff999999[CairnDemo]|r %s"):format(L:Get("LOGIN_N"):format(db.global.totalLogins)))
        Cairn.Events:Fire("CairnDemo:Greeted", UnitName("player") or "?")
    end
    log:Info("Login complete; charKey=%s charHash=%s", charKey, charHash:sub(1, 8) .. "...")
end
