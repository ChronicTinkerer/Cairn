--[[
Cairn-Demo / Snippets

Code-snippet strings every tab quotes in its right-hand "code" panel.
Each entry is the EXACT Lua a consumer would write to reproduce what the
tab demonstrates on the left. Indentation is tabs (matching Cairn).
Strings are kept verbatim, no leading/trailing newlines.

Cairn-Demo/Snippets (c) 2026 ChronicTinkerer. MIT license.
]]

local CairnDemo = _G.CairnDemo
if not CairnDemo then return end

CairnDemo.Snippets = {

-- ===== Welcome =========================================================

welcome = [[
-- Cairn is a collection of composable WoW libraries; this addon is the
-- "everything except the GUI" demo. Cairn-Gui-Demo-2.0 covers the GUI
-- side. Each tab in this window exercises one library:
--
--   Cairn.Callback   /  Cairn.Hooks
--   Cairn.Events     /  Cairn.Sequencer
--   Cairn.Log        /  Cairn.Timer
--   Cairn.DB         /  Cairn.FSM
--   Cairn.Settings   /  Cairn.Comm
--   Cairn.Addon      /  Cairn.EditMode (optional)
--   Cairn.Slash      /  Cairn.Locale
--
-- Open this window any time with: /cdemo
-- Run the smoke test directly with: /cdemo smoke
]],

-- ===== Callback ========================================================

callback = [[
local Callback = LibStub("Cairn-Callback-1.0")
local reg = Callback.New("MyAddon")

-- Subscribers are keyed by (event, key). Same key replaces.
reg:Subscribe("Saved", self, function(eventname, payload)
    print("a:", eventname, payload)
end)
reg:Subscribe("Saved", otherSelf, function(eventname, payload)
    print("b:", eventname, payload)
end)

-- Lifecycle hooks: fire when an event gets its first / last subscriber.
reg:SetOnUsed(function(r, evt)   print("first sub for", evt) end)
reg:SetOnUnused(function(r, evt) print("no more subs for", evt) end)

reg:Fire("Saved", { id = 7 })       -- both subscribers run
reg:Unsubscribe("Saved", self)
reg:UnsubscribeAll(otherSelf)
]],

-- ===== Events ==========================================================

events = [[
local Events = Cairn.Events  -- or LibStub("Cairn-Events-1.0")

-- Subscribe is OWNER-keyed (not (event,key) like Callback). The same
-- owner can subscribe twice to the same event without ceremony.
local off1 = Events:Subscribe("PLAYER_REGEN_DISABLED", function()
    print("entering combat (handler 1)")
end, "MyAddon")

local off2 = Events:Subscribe("PLAYER_REGEN_DISABLED", function()
    print("entering combat (handler 2)")
end, "MyAddon")

off1()                              -- remove just handler 1

Events:UnsubscribeAll("MyAddon")    -- remove every "MyAddon" subscription

-- Has() returns true while at least one handler is registered.
print(Events:Has("PLAYER_REGEN_DISABLED"))
]],

-- ===== Log =============================================================

log = [[
local Log = Cairn.Log  -- or LibStub("Cairn-Log-1.0")

-- Loggers are per-source. Repeat calls return the same object.
local log = Log("MyAddon")
log:Info("loaded v%s", "1.0")
log:Warn("config key %q deprecated", "oldkey")
log:Debug("subscribed to %d events", 7)

-- Per-source level (default INFO).
log:SetLevel("DEBUG")

-- Library-wide settings.
Log:SetGlobalLevel("INFO")
Log:SetChatEchoLevel("WARN")
Log:SetPersistence(1000)            -- last N entries saved to SV

-- Buffer access (LogWindow uses the same APIs).
local entries = Log:GetEntries()    -- snapshot, oldest first
Log:Clear()

-- Cairn-LogWindow shows the buffer in a movable window:
Cairn.LogWindow:Toggle()
Cairn.LogWindow:SetMinLevel("DEBUG")
Cairn.LogWindow:SetSourceFilter("MyAddon")
Cairn.LogWindow:SetSearch("subscribed")
]],

-- ===== DB ==============================================================

db = [[
local db = Cairn.DB.New("MyAddonDB", {
    defaults = {
        profile = { scale = 1.0, enabled = true },
        global  = { dataVersion = 1 },
    },
    profileType = "char",            -- "char" (default) | "default"
})

-- IMPORTANT: do NOT touch db.profile at FILE SCOPE. SVs aren't loaded
-- yet. Defer to ADDON_LOADED / Cairn.Addon:OnInit.
local addon = Cairn.Addon.New("MyAddon")
function addon:OnInit()
    print(db.profile.scale)          -- 1.0 (from defaults on first run)
    db.profile.scale = 1.5
    db.global.dataVersion = 2
end

-- Profile management.
db:GetCurrentProfile()               -- "MyChar - MyRealm" or "Default"
db:GetProfiles()                     -- { "Default", ... }
db:SetProfile("PvP")                 -- switch (creates if missing)
db:CopyProfile("Default", "PvP")     -- deep-copy values
db:OnProfileChanged(function(new, old)
    print("profile changed:", old, "->", new)
end, "MyAddon")
]],

-- ===== Settings ========================================================

settings = [[
local db = Cairn.DB.New("MyAddonDB", { defaults = { profile = {
    scale = 1.0, enabled = true, anchor = "TOPLEFT",
}}})

local settings = Cairn.Settings.New("MyAddon", db, {
    { key = "h",       type = "header", label = "Display" },
    { key = "scale",   type = "range",  label = "Scale",
      min = 0.5, max = 2.0, step = 0.1, default = 1.0,
      onChange = function(v) MyAddon:Rescale(v) end },
    { key = "enabled", type = "toggle", label = "Enable", default = true },
    { key = "anchor",  type = "dropdown", label = "Anchor",
      default = "TOPLEFT",
      choices = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right" } },
})

-- Open in Blizzard's modern Settings panel:
settings:Open()

-- Or open the standalone Cairn-Gui-2.0-rendered panel (prefers v2; falls
-- back to Cairn-SettingsPanel-1.0 if v2 isn't loaded):
settings:OpenStandalone()

settings:Get("scale")                -- 1.0
settings:Set("scale", 1.5)           -- fires onChange
settings:OnChange("scale", function(v, old)
    print("scale:", old, "->", v)
end, "MyAddon")
]],

-- ===== Addon ===========================================================

addon = [[
local addon = Cairn.Addon.New("MyAddon")

function addon:OnInit()    -- ADDON_LOADED for your addon (SVs ready)
    print("OnInit at", self.initFiredAt)
end

function addon:OnLogin()   -- PLAYER_LOGIN
    print("OnLogin at", self.loginFiredAt)
end

function addon:OnEnter()   -- PLAYER_ENTERING_WORLD (every world load)
    print("OnEnter at", self.enterFiredAt)
end

function addon:OnLogout()  -- PLAYER_LOGOUT (last chance to write SVs)
    print("OnLogout at", self.logoutFiredAt)
end

addon:Log()                          -- lazy Cairn.Log("MyAddon"), cached
Cairn.Addon.Get("MyAddon")           -- the same addon object
]],

-- ===== Slash ===========================================================

slash = [[
local s = Cairn.Slash.Register("MyAddon", "/myaddon", {
    aliases = { "/ma" },
})

s:Subcommand("config", function(args) MyAddon:OpenConfig() end,
    "open the config panel")
s:Subcommand("reset",  function() MyAddon:Reset() end,
    "reset everything")
s:Default(function() MyAddon:Open() end)

-- Auto-help: `/myaddon help` (or `?`, or no input with no Default)
-- prints a list of subcommands.

-- Programmatic dispatch.
s:Run("config")
s:Aliases({ "/m", "/ma" })

-- Quote-aware splitter ("hello \"two words\" three"):
local args = s:Args(rest)            -- { "hello", "two words", "three" }

-- Lookup by addon name.
Cairn.Slash.Get("MyAddon")
]],

-- ===== EditMode ========================================================

editmode = [[
local EM = Cairn.EditMode  -- or LibStub("Cairn-EditMode-1.0")

-- Soft dependency on LibEditMode. If absent, Register returns false and
-- nothing crashes; your frame just isn't EditMode-movable.
if EM:IsAvailable() then
    EM:Register(MyFrame, {
        point = "CENTER", x = 0, y = 0,
    }, function()
        -- callback fires when EditMode commits a position change
        MyAddon:SaveAnchor(MyFrame:GetPoint())
    end, "My Frame")
end

-- Always works (just opens the standard EditMode UI):
EM:Open()
]],

-- ===== Locale ==========================================================

locale = [[
local L = Cairn.Locale.New("MyAddon", {
    enUS = { hello = "Hello", welcome = "Welcome back, %s!" },
    deDE = { hello = "Hallo", welcome = "Willkommen zurueck, %s!" },
    frFR = { hello = "Bonjour" },   -- 'welcome' missing -> falls back to enUS
}, { default = "enUS" })

-- Three ways to read.
print(L.hello)
print(L["hello"])
print(L:Get("hello"))

-- Format strings (printf-style on top of Get).
print(L("welcome", playerName))      -- callable form
print(L:Format("welcome", playerName))

-- Introspection.
L:GetLocale()                        -- "enUS" or whatever GetLocale() said
L:GetDefault()                       -- "enUS"
L:Has("hello")                       -- true
L:GetMissing()                       -- keys present in default, not in active

-- Dev override: force a locale at runtime without restarting.
Cairn.Locale.SetOverride("deDE")
Cairn.Locale.SetOverride(nil)        -- clear
]],

-- ===== Hooks ===========================================================

hooks = [[
local Hooks = Cairn.Hooks  -- or LibStub("Cairn-Hooks-1.0")

-- Two-arg form: post-hook a global function.
local unhook = Hooks.Post("seterrorhandler", function(newHandler)
    -- runs AFTER the original; same args as the original received
end)

-- Three-arg form: post-hook a method on a frame or table.
Hooks.Post(SomeFrame, "Show", function(self)
    print(self:GetName(), "shown")
end)

-- Sugar alias for the three-arg form.
Hooks.Method(SomeFrame, "Show", function(self) ... end)

-- Diagnostics.
Hooks.Has(SomeFrame, "Show")         -- true if at least one hook wired
Hooks.Count(SomeFrame, "Show")       -- count of *active* callbacks

-- WoW limitation: hooksecurefunc cannot be undone in-session. Calling
-- the unhook closure marks our callback inactive; the underlying hook
-- stays registered for the rest of the session.
unhook()
]],

-- ===== Sequencer =======================================================

sequencer = [[
local Seq = Cairn.Sequencer  -- or LibStub("Cairn-Sequencer-1.0")

local seq = Seq.New({
    function(s) return goToZone("Westfall") end,
    function(s) return acceptQuest(123) end,
    function(s) return killMobs(8) end,
    function(s) return turnIn(123) end,
}, {
    resetWhen  = function() return playerLeftZone() end,
    abortWhen  = function() return questAbandoned() end,
    onStep     = function(seq, idx, fn) print("step", idx, "done") end,
    onComplete = function(seq) print("done!") end,
})

seq:Execute()                        -- runs Next once (after reset/abort check)
seq:Index()                          -- 1-based current step
seq:Total()                          -- total steps
seq:Progress()                       -- 0..1
seq:Status()                         -- "pending" | "running" | "complete" | "aborted"
seq:Reset()
seq:Abort()
seq:Append(function(s) return cleanup() end)
]],

-- ===== Timer ===========================================================

timer = [[
local Timer = Cairn.Timer  -- or LibStub("Cairn-Timer-1.0")

-- One-shot. Last arg is owner; CancelAll(owner) kills the lot at once.
local h = Timer:After(2.0, function() print("ping") end, "MyAddon")

-- Repeating. iterations nil = infinite.
local t = Timer:NewTicker(0.5, function() count = count + 1 end,
                          "MyAddon", 10)

-- Named one-shot. Cancels any prior timer with the same name first.
-- Useful for "debounce on the latest event" patterns.
Timer:Schedule("save", 2.0, function() doSave() end, "MyAddon")
Timer:Schedule("save", 2.0, function() doSave() end, "MyAddon")
-- ^ second call cancels the first; only one save fires.

-- Cancel.
Timer:Cancel(h)
Timer:CancelByName("save")
Timer:CancelAll("MyAddon")           -- nuke every MyAddon-tagged timer

-- Inspect.
Timer:GetByName("save")
Timer:CountByOwner("MyAddon")

-- Sugar form.
Cairn.Timer(2.0, function() ... end, "MyAddon")
]],

-- ===== FSM =============================================================

fsm = [[
local FSM = Cairn.FSM  -- or LibStub("Cairn-FSM-1.0")

local spec = FSM.New({
    initial = "idle",
    states = {
        idle    = { on = { START = "running",   GO = { target = "ready", delay = 1.0 } } },
        running = { on = { STOP  = "idle",      FAIL = "error" } },
        ready   = { on = { GO    = "running" } },
        error   = { onEnter = function(m, payload) print("error:", payload) end },
    },
    owner = "MyAddon",
})

local m = spec:Instantiate({ context = { retries = 0 } })

-- Subscribe to lifecycle events.
m:On("Transition", function(_, machine, from, to, evt, payload)
    print("transitioned", from, "->", to, "via", evt)
end)
m:On("Enter:running", function(_, machine, payload)
    print("entered running")
end)

m:Send("START")                      -- idle -> running
m:Send("FAIL", "boom")               -- running -> error
m:State()                            -- "error"
m:Can("START")                       -- false (no rule from error)
m:Reset()                            -- back to "idle"
m:Destroy()                          -- unhook, fire "Destroyed"
]],

-- ===== Comm ============================================================

comm = [[
local Comm = Cairn.Comm  -- or LibStub("Cairn-Comm-1.0")

-- Subscribe with a unique 16-char-or-less prefix. Returns unsub closure.
local unsub = Comm:Subscribe("MYADDON", function(msg, channel, sender)
    print(sender, "via", channel, ":", msg)
end, "MyAddon")

-- Send to a specific channel (PARTY / RAID / INSTANCE_CHAT / GUILD / WHISPER).
Comm:Send("MYADDON", "hello", "PARTY")
Comm:Send("MYADDON", "hi", "WHISPER", "Steven-Area52")

-- Auto-pick best group channel (raid > party > guild).
Comm:SendBroadcast("MYADDON", "hello team")

-- Inspect.
Comm:IsRegistered("MYADDON")         -- whether C_ChatInfo accepted the prefix
Comm:CountSubscribers("MYADDON")

unsub()                              -- single subscriber off
Comm:UnsubscribeAll("MyAddon")       -- everything from owner

-- WoW caps each addon message at 255 chars; payload chunking is on you.
]],

-- ===== Smoke Test ======================================================

smoketest = [[
-- The Smoke Test runs PASS/FAIL assertions against every public API in
-- the Cairn library set. Each assertion is a small self-contained test
-- (e.g., "Cairn.Timer:After fires its callback after the requested
-- delay"). Results stream into the console on the left.
--
-- Click the "Run Smoke Test" button to start. Total runtime <= ~3s
-- because of the timer/sequencer assertions; everything else is sync.
--
-- A green "PASS: N / N" footer means every Cairn library is wired
-- correctly. Red entries point at the specific test that failed and
-- the assertion message.
--
-- This same test set lives at Forge/.dev/tests/cairn_demo_smoke.lua
-- for headless validation via Forge_Console (no demo window needed).
]],

}
