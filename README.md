# Cairn

> Modern composable libraries for World of Warcraft addons.

Cairn is a small collection of independent, modern Lua libraries for WoW
addon authors. Pick the pieces you need, leave the rest.

It targets every shipping WoW client via per-flavor TOCs:

- **Retail / Mainline** — Interface `120005`
- **MoP Classic** — Interface `50503`
- **TBC Anniversary** — Interface `20505`
- **Classic Era / Hardcore** — Interface `11508`
- **Experimental PTR (XPTR)** — Interface `120007`

Cairn is positioned as a fresh alternative to Ace3 — not a successor, not
a fork. The libraries are designed to be useful on their own, including
alongside Ace3 if you're already invested.

**Status:** v0.2.0-dev. v0.1.0 shipped: `Cairn.Events`, `Cairn.Log`,
`Cairn.LogWindow`, `Cairn.DB`, `Cairn.Settings`, `Cairn.Addon`,
`Cairn.Slash`. v0.2 adds: `Cairn.EditMode` (LibEditMode wrapper),
the `anchor` schema type in `Cairn.Settings`, `Cairn.Locale`
(i18n with locale fallback), `Cairn.Sequencer` (composable
step runner), `Cairn.Hooks` (multi-callback hook helper),
`Cairn.Timer` (owner-grouped timers), `Cairn.Comm` (addon-to-addon
messaging), `Cairn.Callback` (registry-style callback dispatcher,
exposed at `LibStub("Cairn-Callback-1.0")` for direct internal use),
and
the `Cairn-Gui-*` widget family (Tools, Style, Core with 12 widgets,
Menu — derived from the BSD-licensed Diesal libraries and modernized
for Interface 120005). The v0.1-era `Cairn.Dashboard` was retired and
replaced by the standalone Forge_Logs addon. See [Roadmap](#roadmap).

---

## Why Cairn?

Most popular WoW addons today don't actually use Ace3 wholesale.
WeakAuras, Details!, BigWigs, DBM, Plater, MRT all rolled their own
architecture. ElvUI uses three Ace3 libraries and ignores the rest.

Cairn is what that "rest from scratch" could look like if you started
today, with these decisions baked in:

- **Composable, not monolithic.** No required core, no mixin chain.
  Each module is independently usable; the umbrella `Cairn` table just
  resolves them on first access.
- **Modern Lua patterns.** Closure handlers instead of mixin methods.
  Subscribe calls return an unsubscribe function.
- **Plays well with Blizzard's modern UI.** `Cairn.Settings` writes
  directly into the native Settings panel. The `anchor` schema type
  registers your frame with Edit Mode (via LibEditMode) so users can
  drag it visually.
- **Built-in dev tooling lives in [Forge](../Forge/).** Cairn focuses on
  the libraries; Forge ships the developer UI (per-source log viewer,
  Lua REPL, addon manager, etc.). Authors who want bug reporting and a
  log dashboard install Forge alongside Cairn.
- **Widget toolkit available.** The `Cairn-Gui-*` family (Tools, Style,
  Core, Menu) is a 14-widget kit derived from the BSD-licensed Diesal
  libraries and modernized for Interface 120005. Optional — if you'd
  rather roll your own UI, leave it out.

---

## Installation

Cairn supports two distribution modes. Both expose the same `Cairn.X` API.

### Mode 1: Standalone (recommended for end users)

1. Copy the `Cairn/` folder into the `Interface\AddOns\` directory of
   whichever flavor(s) you play:
   - Retail: `World of Warcraft\_retail_\Interface\AddOns\Cairn\`
   - MoP Classic: `World of Warcraft\_classic_\Interface\AddOns\Cairn\`
   - TBC Anniversary: `World of Warcraft\_anniversary_\Interface\AddOns\Cairn\`
   - Classic Era / Hardcore: `World of Warcraft\_classic_era_\Interface\AddOns\Cairn\`
   - Experimental PTR: `World of Warcraft\_xptr_\Interface\AddOns\Cairn\`

   The published zip ships separate per-flavor builds (CurseForge picks
   the right one automatically). The folder content is identical; the
   client picks the matching `Cairn_<flavor>.toc` for its Interface
   number, falling back to `Cairn.toc`.
2. Make sure Cairn is enabled in your in-game AddOns list.
3. Optionally install [LibEditMode](https://www.curseforge.com/wow/addons/libeditmode)
   from CurseForge if you want EditMode integration to work
   (Retail-only — no-ops on Classic flavors).
4. Any addon that depends on Cairn loads after it automatically.

After login, type `/cairn` to see the available subcommands.

**Compatibility notes for Classic flavors:** `Cairn.EditMode` no-ops on
non-Retail. `Cairn.Settings` / `Cairn.SettingsPanel` use the modern
Settings API which is partially supported on Vanilla 1.15.x and TBC
Anniversary 2.5.5; consumer addons should treat Settings registration as
best-effort there.

### Mode 2: Embedded (recommended for addon authors shipping a single zip)

Drop the Cairn module files into your addon's `Libs/` directory and
include them in your `.toc` BEFORE your own files. LibStub's
version-deduplication means only the highest-version copy stays loaded
even if multiple addons embed the same module.

```
MyAddon/
  MyAddon.toc
  Libs/
    LibStub/LibStub.lua
    Cairn/
      Cairn.lua
      CairnEvents/Cairn-Events-1.0.lua
      CairnLog/Cairn-Log-1.0.lua
      CairnDB/Cairn-DB-1.0.lua
      CairnSettings/Cairn-Settings-1.0.lua
      CairnAddon/Cairn-Addon-1.0.lua
      CairnSlash/Cairn-Slash-1.0.lua
      CairnEditMode/Cairn-EditMode-1.0.lua    -- optional; needs LibEditMode
  Core.lua
```

Do NOT embed `CairnStandalone/Cairn-Standalone-1.0.lua` — it's only
meant for the standalone Cairn addon (it wires SavedVariables and the
`/cairn` slash router).

---

## Quick start

```lua
-- MyAddon/Core.lua
local addonName = ...
local addon     = Cairn.Addon.New(addonName)
local log       = addon:Log()

local db        = Cairn.DB.New("MyAddonDB", {
    defaults = { profile = { scale = 1.0, enabled = true } },
})

local settings  = Cairn.Settings.New(addonName, db, {
    { key = "enabled", type = "toggle", default = true,  label = "Enabled" },
    { key = "scale",   type = "range",  default = 1.0,
      min = 0.5, max = 2.0, step = 0.1, label = "Scale" },
})

local slash     = Cairn.Slash.Register(addonName, "/myaddon")
slash:Subcommand("config", function() settings:Open() end, "open settings")
slash:Subcommand("reset",  function() db:ResetProfile() end, "reset profile")

function addon:OnInit()  log:Info("init: SVs ready") end
function addon:OnLogin() log:Info("welcome back, scale=%s", tostring(db.profile.scale)) end
```

A complete addon: lifecycle hooks, persistent settings, a real Blizzard
Settings panel entry, slash commands, and printf-style logging — under
25 lines of code.

---

## Modules

### `Cairn` (umbrella facade)

Tiny lazy loader. Indexing `Cairn.Foo` calls `LibStub("Cairn-Foo-1.0", true)`
and caches the result. If the module isn't loaded, returns `nil`.

```lua
Cairn._VERSION                                      -- "0.1.0"
Cairn:RegisterSlashSub(name, fn, helpText)          -- add a /cairn <name> subcommand
```

---

### `Cairn.Events` — event subscription

```lua
local unsub = Cairn.Events:Subscribe(event, handler, owner)
unsub()
Cairn.Events:UnsubscribeAll(owner)
Cairn.Events:Has(event)
```

Handler receives the event payload args. Errors caught with `pcall` and
routed to `geterrorhandler()`.

---

### `Cairn.Callback` — registry-style callback dispatcher (v0.2)

A general-purpose callback registry. Different from `Cairn.Events` (which
wraps Blizzard's WoW-event system); `Cairn.Callback` is for **library-
to-consumer messaging** — your library declares events its consumers can
subscribe to.

```lua
local Callback = LibStub("Cairn-Callback-1.0")
local reg = Callback.New()

reg:Subscribe(eventname, key, fn)  -- key acts as "self": one fn per (event, key)
reg:Unsubscribe(eventname, key)
reg:UnsubscribeAll(key)
reg:Fire(eventname, ...)           -- subscribers get (eventname, ...trailing)

reg:SetOnUsed(fn)    -- fn(reg, eventname) on first subscriber for an event
reg:SetOnUnused(fn)  -- fn(reg, eventname) on last subscriber removed
```

Subscribers receive `(eventname, ...trailingArgs)`, matching the
upstream WoWAce CallbackHandler-1.0 dispatch convention. Subscribes
during `Fire` are queued and applied after dispatch returns. Errors in
subscribers are pcall-trapped and routed through `geterrorhandler()`.

**Why both Events and Callback?** Events is for "WoW fired SPELL_CAST"
(one subscriber list per event name, owned globally). Callback is for
"my library has a custom event" (each library/object instantiates its
own registry).

#### CallbackHandler-1.0 shim

`Cairn/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` registers
under the upstream LibStub name `CallbackHandler-1.0` so that
LibSharedMedia-3.0, the Cairn-Gui-* widget family, and any other
Ace3-style consumer that calls `LibStub("CallbackHandler-1.0")` finds
a working implementation when no other addon supplies one. The body is
a port of ElvUI's bundled MINOR=8 variant of upstream WoWAce
CallbackHandler-1.0 (uses `securecallfunction` for dispatch — the
modern Blizzard-blessed style). Cairn does NOT vendor the 2010-era
WoWAce reference.

Cairn-Callback-1.0 is a separate library, NOT the backing for this
shim. The two are independent. The shim has its own `:New` /
`:Fire` / RegisterCallback surface; Cairn-Callback is exposed at
`LibStub("Cairn-Callback-1.0")` for code that wants the simple
`:Subscribe / :Fire` API directly.

##### MINOR strategy and the ElvUI caveat

The shim registers at `MINOR=7`. That beats upstream WoWAce
(`MINOR=6`) so we win LibStub when no other CallbackHandler-1.0 is
loaded — the typical case for an addon that depends on Cairn alone.
But it loses to ElvUI's bundled `MINOR=8`, so when ElvUI is in the
user's environment ElvUI's CallbackHandler owns the dispatch chain
and our shim body never executes.

This is intentional. Empirically, having Cairn's `:New` win LibStub
when ElvUI is present causes ElvUI's unitframe init to race
catastrophically — Range.lua throws "self.unitframe is nil" repeatedly
and ElvUI half-loads. The race reproduces even with our `:New` body
byte-identical to ElvUI's, even with no Cairn extension code running
inside `:New`. Root cause was never fully diagnosed; the safe ground
rule is "when ElvUI is present, ElvUI's CallbackHandler must win."

The MINOR=7 choice gives us:

- **No ElvUI present**: our shim wins, dispatches every consumer's
  callbacks, and Forge_Registry's "Callbacks" source enumerates
  registries via the Cairn-Callback `instances` table (populated by a
  hook at the end of our `:New`).
- **ElvUI present**: ElvUI's MINOR=8 wins, our `:New` is never called,
  Cairn-Callback's `instances` stays empty for shim-created registries.
  Forge_Registry falls back to a lazy LibStub.libs scan that
  duck-types each lib's fields for callback-registry shape
  (`recurse` number + `events` table + `Fire` function) and surfaces
  them.

If you ever need to change the shim, test with ElvUI enabled before
and after. Even a single weak-table write inside `:New` was enough to
trigger the race in past attempts.

---

### `Cairn.Log` — leveled logging

```lua
local log = Cairn.Log("MyAddon")
log:Info("loaded v%s", "1.0")
log:Warn("config key %q deprecated", k)
log:Error("parse failed: %s", err)
log:SetLevel("DEBUG")

Cairn.Log:SetGlobalLevel("WARN")
Cairn.Log:SetChatEchoLevel("WARN")
Cairn.Log:SetPersistence(1000)
Cairn.Log:GetEntries(filterFn)
Cairn.Log:OnNewEntry(fn, owner)
```

Levels: `ERROR (1)`, `WARN (2)`, `INFO (3)`, `DEBUG (4)`, `TRACE (5)`.
Default visibility `INFO+`.

---

### `Cairn.LogWindow` — log viewer

Open with `/cairn log`.

```lua
Cairn.LogWindow:Toggle()
Cairn.LogWindow:SetSourceFilter("MyAddon")
Cairn.LogWindow:SetMinLevel("DEBUG")
Cairn.LogWindow:SetSearch("config")
```

Requires `Cairn.Log`.

---

### `Cairn.DB` — SavedVariables with profiles

```lua
-- .toc:  ## SavedVariables: MyAddonDB

local db = Cairn.DB.New("MyAddonDB", {
    defaults = {
        profile = { scale = 1.0, enabled = true },
        global  = { dataVersion = 1 },
    },
    profileType = "char",  -- "char" (default) | "default"
})

print(db.profile.scale)
db.profile.scale = 1.5

db:GetCurrentProfile()
db:GetProfiles()
db:SetProfile("PvP")
db:ResetProfile()
db:DeleteProfile("OldOne")
db:CopyProfile("From", "To")

local unsub = db:OnProfileChanged(function(newName, oldName) ... end, addonName)
```

Defaults are deep-copied on profile creation. Use `ResetProfile()` to
push new defaults into existing data.

**Init timing — do not touch `.profile` / `.global` at file scope.**
WoW loads SavedVariables *after* your addon's `.lua` files execute, but
*before* `ADDON_LOADED` fires. Reading `db.profile` at file scope causes
the lib to lazy-init while `_G[svName]` is still nil; it builds an empty
table, pins the wrapper to it, and WoW then overwrites `_G[svName]` with
the on-disk data — leaving your wrapper orphaned. Symptom: settings
appear to save but vanish after `/reload`. Defer the first access
to `ADDON_LOADED` (or `Cairn.Addon`'s `OnInit`):

```lua
local db = Cairn.DB.New("MyAddonDB", { defaults = {...} })
ns.db = db
-- Do NOT read db.profile here.

local addon = Cairn.Addon.New("MyAddon")
function addon:OnInit()
    local _ = db.profile          -- safe: SVs are loaded
    if db.profile.foo == nil then db.profile.foo = {} end
end
```

---

### `Cairn.Settings` — declarative config + Blizzard panel bridge

```lua
local settings = Cairn.Settings.New(addonName, db, {
    { key = "h_general", type = "header", label = "General" },
    { key = "enabled",   type = "toggle", default = true, label = "Enabled" },
    { key = "scale",     type = "range",  default = 1.0,
      min = 0.5, max = 2.0, step = 0.1, label = "Scale",
      onChange = function(value, oldValue) MyAddon:Rescale(value) end },
    { key = "anchor",    type = "dropdown", default = "TOPLEFT", label = "Anchor",
      choices = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right" } },
    -- v0.2: anchor type integrates with EditMode (requires LibEditMode)
    { key = "framePos",  type = "anchor", label = "Frame position",
      frame = MyAddonFrame,
      default = { point = "CENTER", x = 0, y = 0 },
      onChange = function() MyAddon:Reanchor() end },
})

settings:Open()
settings:Get("scale")
settings:Set("scale", 1.5)
settings:OnChange("scale", fn, owner)
```

| Type       | Required fields                    | Notes |
|------------|------------------------------------|-------|
| `header`   | `label`                            | Section header, not a setting |
| `toggle`   | `default`, `label`                 | Boolean checkbox |
| `range`    | `default`, `label`, `min`, `max`   | Numeric slider; `step` defaults to 0.1 |
| `dropdown` | `default`, `label`, `choices`      | `choices` is `{value = label, ...}` |
| `anchor`   | `frame` (named), `label`           | EditMode-movable; needs LibEditMode |
| `text`     | `default` (string), `label`        | **Storage-only.** Schema validates and seeds defaults; `Get`/`Set`/`OnChange` work. No Blizzard panel widget — addon owns the UI (popup EditBox, slash, custom panel). |
| `color`    | `default = {r,g,b[,a]}`, `label`   | **Storage-only.** Same contract as `text`. Addon launches `ColorPickerFrame` (or whatever) and writes via `Set`. |
| `keybind`  | `default` (string), `label`        | **Storage-only.** Same contract as `text`. Stores whatever string the addon writes — `"CTRL-SHIFT-X"`, key codes, etc. |

**Why three schema types are storage-only:** Cairn.Settings's job for these is to validate the schema, seed defaults into `db.profile`, and route `Set` through the `onChange` / subscriber pipeline. Rendering a button row in the Blizzard Settings panel turned out to require APIs that aren't available across all client patches; rather than ship a brittle integration, Cairn keeps a clean contract — the schema is the data layer, the addon wires whatever UI fits.

The `anchor` type does NOT seed `db.profile` — LibEditMode persists
position via Blizzard's EditMode SavedVariables. Defaults seed
`db.profile` only for keys currently `nil`. Schema order is preserved
in the panel. If Blizzard's modern Settings global isn't available, `New`
returns a Get/Set/OnChange-only stub.

---

### `Cairn.EditMode` — optional LibEditMode wrapper (v0.2)

```lua
Cairn.EditMode:IsAvailable()                          -- true if LibEditMode loaded
Cairn.EditMode:Register(frame, defaults, callback, name)
Cairn.EditMode:Open()                                 -- toggle Edit Mode panel
```

Frames must have a non-nil `:GetName()`. `defaults` is
`{ point = "CENTER", x = 0, y = 0 }` (any subset). If LibEditMode isn't
loaded, `Register` returns false; nothing else breaks.

LibEditMode (https://github.com/p3lim-wow/LibEditMode) is the de-facto
community wrapper. Cairn does not vendor it — install separately.

---

### `Cairn.Dashboard` — retired (replaced by Forge_Logs)

The v0.1-era `Cairn.Dashboard` was retired during v0.2 development. The
log-viewer + copyable log dump features moved into the standalone
**Forge_Logs** sub-addon (part of the Forge developer toolset). The
`/cairn dash` slash now redirects to `/forge logs` if Forge is loaded.

Authors who want the old dashboard's behavior should install Forge
alongside Cairn. The split keeps Cairn focused on libraries and Forge
focused on developer UI.

---

### `Cairn.Addon` — lifecycle helpers

```lua
local addon = Cairn.Addon.New("MyAddon")

function addon:OnInit()    end  -- ADDON_LOADED for your addon (SVs ready)
function addon:OnLogin()   end  -- PLAYER_LOGIN
function addon:OnEnter(isLogin, isReload) end  -- PLAYER_ENTERING_WORLD
function addon:OnLogout()  end  -- PLAYER_LOGOUT

addon:Log()                     -- lazy Cairn.Log("MyAddon"), cached
Cairn.Addon.Get("MyAddon")      -- registry lookup

-- v0.2 timestamp tracking (read by Cairn.Dashboard's Info tab):
addon.initFiredAt                  -- epoch seconds, or nil if not yet fired
addon.loginFiredAt
addon.enterFiredAt
addon.logoutFiredAt
```

Hooks that aren't defined are skipped. ADDON_LOADED is filtered to your
addon name automatically. Errors caught with `pcall`. Requires `Cairn.Events`.

---

### `Cairn.Slash` — generic slash router

```lua
local s = Cairn.Slash.Register("MyAddon", "/myaddon", { aliases = { "/ma" } })

s:Subcommand("config", function(rest) MyAddon:OpenConfig() end, "open config")
s:Subcommand("reset",  function() MyAddon:Reset() end, "reset everything")
s:Default(function(input) MyAddon:DefaultAction(input) end)

s:Run("config")
s:Aliases({ "/m", "/ma" })
s:PrintHelp()
local args = s:Args('hello "two words"')   -- {"hello","two words"}
Cairn.Slash.Get("MyAddon")
```

`/myaddon help` and `/myaddon ?` always print auto-help.

---

### `Cairn.Locale` — i18n (v0.2)

Per-addon localization with locale fallback. Author registers per-locale
string tables; Cairn picks the active locale from `GetLocale()` and
falls back to a default locale (then to the key itself) for missing
translations.

```lua
local L = Cairn.Locale.New("MyAddon", {
    enUS = { hello = "Hello", welcome = "Welcome back, %s!" },
    deDE = { hello = "Hallo", welcome = "Willkommen zurück, %s!" },
    frFR = { hello = "Bonjour" },  -- partial; missing keys fall back to enUS
}, { default = "enUS" })

-- Three ways to read a string:
print(L.hello)                   -- direct table access (recommended)
print(L["hello"])
print(L:Get("hello"))            -- explicit method form

-- Format strings (printf on top of Get):
print(L("welcome", playerName))  -- callable sugar
print(L:Format("welcome", playerName))

-- Introspection:
L:GetLocale()                    -- active locale code
L:GetDefault()                   -- fallback locale code
L:Has("hello")                   -- true if active or default has it
L:GetMissing()                   -- keys present in default but missing in
                                  -- active (handy debug aid for translators)

Cairn.Locale.Get("MyAddon")      -- registry lookup, nil if unregistered
```

Behavior on missing keys: active locale → default locale → key itself,
plus a one-time warning per missing key via `Cairn.Log` (suppress with
`opts.silent = true`). If the user's locale has no table at all, Cairn
quietly switches the active locale to the default rather than warning
on every key.

`Cairn.Locale(name, locales, opts)` is sugar for `Cairn.Locale.New(...)`.

---

### `Cairn.Sequencer` — composable step runner (v0.2)

A small, generic step-runner. Each step is a function that returns
truthy to advance and falsy to retry on the next tick. Sequencers carry
optional reset and abort conditions and fire lifecycle callbacks. Useful
for guide/quest steps, multi-stage tutorials, deploy-style preflight
checks — anything ordered that you want to drive from a ticker.

```lua
local seq = Cairn.Sequencer.New({
    function(s) return playerInZone("Westfall")  end,  -- truthy => advance
    function(s) return questAccepted(123)        end,
    function(s) return mobsKilled(8)             end,
    function(s) return questTurnedIn(123)        end,
}, {
    resetWhen  = function() return playerLeftZone() end,
    abortWhen  = function() return questAbandoned() end,
    onStep     = function(seq, idx, fn) print("done step", idx) end,
    onComplete = function(seq) print("guide done!") end,
})

-- Drive from any ticker (Cairn.Events, C_Timer.NewTicker, OnUpdate, etc).
C_Timer.NewTicker(0.25, function() seq:Execute() end)
```

`:Execute()` checks `abortWhen` and `resetWhen` first, then runs the
current step. `:Next()` is the raw advance with no condition checks.
Step errors are pcall-trapped and logged via `Cairn.Log("Cairn.Sequencer")`
so a single bad step doesn't kill the run.

| Method                        | What it does                                    |
| ----------------------------- | ----------------------------------------------- |
| `Execute()`                   | Auto-checks abort/reset, then runs `Next`.      |
| `Next()`                      | Run current step; advance on truthy. Returns advanced?. |
| `Reset()`                     | Index back to 1; fires `onReset`.               |
| `Abort()`                     | Jump past last step; fires `onAbort`.           |
| `Finished()`                  | True once index passes the action list.         |
| `Index()` / `Total()`         | Inspector helpers (1-based).                    |
| `Current()`                   | The current step function (nil when finished).  |
| `Progress()`                  | `(index - 1) / total`, 0..1.                    |
| `Status()`                    | `"pending"`, `"running"`, `"complete"`, `"aborted"`. |
| `SetActions(t)` / `Append(fn)`| Replace or extend the step list.                |
| `OnStep`/`OnComplete`/`OnAbort`/`OnReset` | Subscribe; returns unsubscribe. |

Aborted sequencers stay aborted until `:Reset()`. Subscribers compose
with the inline option callbacks (both fire). `Cairn.Sequencer(actions, opts)`
is sugar for `Cairn.Sequencer.New(...)`.

---

### `Cairn.Hooks` — multi-callback hook helper (v0.2)

A small wrapper around `hooksecurefunc` that lets multiple addons hook the
same function without stomping each other. Cairn installs one underlying
secure hook per `(target, name)` and dispatches to all active callbacks.
Returns an unhook closure that flips the callback inactive (the underlying
secure hook stays for the session, since `hooksecurefunc` cannot be undone).

```lua
local Hooks = Cairn.Hooks

-- Post-hook a global function (two-arg form).
local unhook = Hooks.Post("seterrorhandler", function(newHandler)
    -- runs after seterrorhandler(newHandler), with the same args
end)

-- Post-hook a method on a frame or table (three-arg form).
Hooks.Post(SomeFrame, "Show", function(self) print("shown") end)

-- Sugar alias of the three-arg form.
Hooks.Method(SomeFrame, "Show", function(self) ... end)

-- Inspect.
Hooks.Has(_G, "seterrorhandler")    -- true once we have a hook on it
Hooks.Count(SomeFrame, "Show")      -- active callbacks (excluding unhooked)

unhook()                            -- mark our callback inactive
```

| Method                  | What it does                                          |
| ----------------------- | ----------------------------------------------------- |
| `Post(name, fn)`        | Post-hook a global. Returns unhook closure.           |
| `Post(target, name, fn)`| Post-hook a method on `target`. Returns unhook closure.|
| `Method(target, name, fn)` | Sugar for the three-arg `Post`.                    |
| `Has(target, name)`     | True if at least one active callback exists.         |
| `Count(target, name)`   | Number of active callbacks.                          |

Pre-hooks are intentionally not included in v0.2; secure pre-hooking is
risky and unsecure pre-hooks will land in v0.3 as `Cairn.Hooks.Pre` if
demand is there. Step-error guard: each callback runs in `pcall`, so a
single broken hook won't kill the dispatch chain.

`Cairn.Hooks(...)` is sugar for `Cairn.Hooks.Post(...)`.

---

### `Cairn.Timer` — owner-grouped timers + named replacement

A thin layer over WoW's `C_Timer` that adds two things addons typically
need but have to roll themselves: **cancel-all-by-owner** and **named
timers** (replace-if-exists, useful for debounce).

```lua
local T = Cairn.Timer

-- One-shot.
local h = T:After(2.0, function() print("two seconds later") end, "MyAddon")

-- Repeating. iterations nil = forever.
T:NewTicker(0.5, function() poll() end, "MyAddon", 10)

-- Debounce: every call replaces the previous "save" timer, so doSave()
-- only fires once 1s after the LAST event.
local function onConfigChanged()
    T:Schedule("save", 1.0, function() doSave() end, "MyAddon")
end

-- Cancel.
T:Cancel(h)
T:CancelByName("save")
T:CancelAll("MyAddon")    -- nuke every timer this owner started

-- Inspect.
T:CountByOwner("MyAddon")
T:GetByName("save")

-- Sugar: Cairn.Timer(seconds, fn, owner) is :After(...).
```

| Method                              | What it does                                       |
| ----------------------------------- | -------------------------------------------------- |
| `After(seconds, fn, owner)`         | One-shot. Returns a handle.                        |
| `NewTicker(seconds, fn, owner, n)`  | Repeating. `n` iterations (nil = forever).         |
| `Schedule(name, seconds, fn, owner)`| One-shot, replaces any existing timer with `name`. |
| `Cancel(handle)`                    | Cancel a single handle.                            |
| `CancelByName(name)`                | Cancel a named timer.                              |
| `CancelAll(owner)`                  | Cancel every live handle for an owner.             |
| `CountByOwner(owner)`               | Number of live handles for an owner.               |
| `GetByName(name)`                   | Look up a named handle.                            |
| `HandlesFor(owner)`                 | Snapshot array of an owner's live handles.         |

Callback errors are pcall-trapped and routed through `geterrorhandler()`
so a single bad timer doesn't kill its peers.

---

### `Cairn.Gui` — small widget kit (v0.2)

A focused widget kit Cairn ships so addons aren't held hostage to Blizzard's
Settings/AddOn UI APIs (which churn between patches). Built on raw `CreateFrame`
+ a handful of base-game templates (`BackdropTemplate`, `UIPanelButtonTemplate`,
`OptionsSliderTemplate`, `UIDropDownMenuTemplate`, `BasicFrameTemplateWithInset`).
No third-party UI library dependency.

```lua
local Gui = Cairn.Gui

local panel = Gui:Panel(UIParent, { title = "MyAddon" })
panel:SetSize(400, 300); panel:SetPoint("CENTER")

local box = Gui:VBox(panel, { padding = 8, gap = 4 })
box:SetPoint("TOPLEFT", 8, -28); box:SetPoint("BOTTOMRIGHT", -8, 8)

box:Add(Gui:Header(panel, "Display"))
box:Add(Gui:Checkbox(panel, { label = "Enabled", value = true }))
                :OnChange(function(v) print("enabled =", v) end)
box:Add(Gui:Slider(panel, { label = "Scale", min = 0.5, max = 2, step = 0.05, value = 1 }))
box:Add(Gui:ColorSwatch(panel, { label = "Accent", value = { 1, 0.5, 0, 1 } }))
box:Layout()
```

Every value-bearing widget exposes a uniform `:Get() / :Set(v) / :OnChange(fn)`.
Errors inside `OnChange` callbacks are pcall-trapped and routed through
`geterrorhandler()`.

| Widget                   | Purpose                                          |
| ------------------------ | ------------------------------------------------ |
| `Panel(parent, opts)`    | Styled container; optional `opts.title`.         |
| `VBox / HBox`            | Auto-arrange children; `:Add(child, opts)`.      |
| `Header(parent, text)`   | Section heading, accent-colored.                 |
| `Label(parent, text)`    | Wrappable text.                                  |
| `Button`, `Checkbox`     | Standard controls.                               |
| `EditBox`, `Slider`      | Text + number inputs.                            |
| `Dropdown`               | `{value = label}` choice picker.                 |
| `ColorSwatch`            | Click → `ColorPickerFrame`. RGBA.                |
| `KeybindButton`          | Click → next-key capture; `"CTRL-SHIFT-X"` form. |

v0.1 ships with the widgets above. The next major widget effort is
not v0.2/v0.3 of the hand-rolled kit but the **Cairn-Gui-* family**
(see below), a richer 14-widget set ported from the BSD-licensed Diesal
libraries.

---

### `Cairn-Gui-*` — Diesal-derived widget family (v0.2)

A more substantial widget kit than the v0.1 hand-rolled `Cairn.Gui`,
forked from the [Diesal](https://code.google.com/p/diesallibs/) library
collection (BSD 3-clause, original author: diesal2010, last upstream
2014) and modernized for Interface 120005. Four LibStub libraries:

| Library                     | Purpose                                            |
| --------------------------- | -------------------------------------------------- |
| `Cairn-Gui-Tools-1.0`       | Color/coords/table helpers, embed framework.       |
| `Cairn-Gui-Style-1.0`       | Texture / outline / FontString styling + Media.    |
| `Cairn-Gui-Core-1.0`        | Widget framework + 12 widgets via XML manifest.    |
| `Cairn-Gui-Menu-1.0`        | Context-menu lib (Menu, MenuItem) on top of Core.  |

The 12 Core widgets: `Window`, `Button`, `CheckBox`, `Input`, `Spinner`,
`ScrollFrame`, `ScrollingEditBox`, `ScrollingMessageFrame`, `DropDown`
(registers as `"Dropdown"`), `DropDownItem`, `ComboBox`, `ComboBoxItem`.

```lua
local Gui = LibStub("Cairn-Gui-Core-1.0")

local w = Gui:Create("Window")
w:SetPoint("CENTER")
w:SetWidth(400); w:SetHeight(300)
w:Show()
```

Provenance and modification details are documented in
[`Diesal/ATTRIBUTION.md`](../Diesal/ATTRIBUTION.md). All Diesal-derived
files retain the original copyright + BSD license text alongside a
"Modified for Cairn by ChronicTinkerer (2026)" header. Bundled assets:
two `.tga` texture sheets (Diesal originals, BSD), and two free-license
fonts (`Standard0755.ttf`, `FFF Intelligent Thin Condensed.ttf`). The
proprietary Calibri Bold font that shipped upstream was dropped.

The `CallbackHandler-1.0` and `LibSharedMedia-3.0` deps that the
Diesal libraries reference are handled in `Cairn/Libs/`: a Cairn-shipped
CallbackHandler-1.0 ported from ElvUI's MINOR=8 variant (registered at
MINOR=7 so it loses to ElvUI's bundled copy when ElvUI is present — see
the CallbackHandler-1.0 shim section above for why), and an unmodified
vendored copy of LibSharedMedia-3.0 (LGPL v2.1).

---

### `Cairn.SettingsPanel` — Cairn-Gui renderer for Cairn.Settings (v0.2)

Standalone panel that renders any `Cairn.Settings` schema using `Cairn.Gui`.
Independent of Blizzard's Settings UI — works for every schema type including
`text`, `color`, and `keybind` which the Blizzard panel can't render uniformly.

```lua
local settings = Cairn.Settings.New(addonName, db, schema)

settings:Open()             -- Blizzard panel (existing types only)
settings:OpenStandalone()   -- Cairn.Gui panel (every schema type)
```

Both paths coexist — the addon picks per-call. Existing addons need no change;
new addons can pick either based on whether they want native-UI integration or
a fully owned panel.

---

### `Cairn.Comm` — addon-to-addon messaging

Thin wrapper over `CHAT_MSG_ADDON` / `C_ChatInfo.SendAddonMessage`. Each
addon picks a prefix (max 16 chars) and subscribes to incoming messages on
that prefix. Supports `PARTY` / `RAID` / `INSTANCE_CHAT` / `GUILD` /
`WHISPER` channels plus a `SendBroadcast` that auto-picks the best one.

```lua
local C = Cairn.Comm

-- Subscribe. Returns an unsubscribe closure.
local unsub = C:Subscribe("MYADDON", function(msg, channel, sender)
    print(sender, "via", channel, ":", msg)
end, "MyAddon")

-- Send.
C:Send("MYADDON", "hello", "PARTY")
C:Send("MYADDON", "ping", "WHISPER", "Steven-Area52")

-- Broadcast: in raid -> RAID, in party -> PARTY, else guild, else nil.
C:SendBroadcast("MYADDON", "hello world")

-- Cleanup.
unsub()
C:UnsubscribeAll("MyAddon")
```

| Method                                          | What it does                                  |
| ----------------------------------------------- | --------------------------------------------- |
| `Subscribe(prefix, fn, owner)`                  | Listen on `prefix`. Returns unsub closure.    |
| `UnsubscribeAll(owner)`                         | Cancel every subscription owned by `owner`.   |
| `Send(prefix, message, channel, target)`        | Send. `target` only used for `WHISPER`.       |
| `SendBroadcast(prefix, message)`                | Auto-pick channel and send.                   |
| `GetBroadcastChannel()`                         | What `SendBroadcast` would use right now.     |
| `IsRegistered(prefix)` / `CountSubscribers(p)`  | Inspect.                                      |

WoW caps each message at 255 chars — payload chunking is the caller's
problem in v0.2. Handler errors run under `pcall`.

---

## Composing with other libraries

Cairn is plumbing, not a one-stop framework. It deliberately doesn't
ship game data (quest databases, NPC tables, item info, etc.). For
domain-specific work, depend on a specialized library alongside Cairn
and let your addon compose them.

The pattern: Cairn handles user-facing concerns (settings panel, slash
commands, logging, persistence, lifecycle). The domain library handles
its specialty (quest data, nameplate logic, raid encounters, whatever).
Your addon's `Core.lua` wires them together.

Example: a guide addon using `LibCodex` (quest database) with Cairn:

```
MyGuideAddon/
  MyGuideAddon.toc
  ## Dependencies: Cairn, LibCodex
  Core.lua
```

```lua
-- MyGuideAddon/Core.lua
local addonName = ...
local addon     = Cairn.Addon.New(addonName)
local log       = addon:Log()
local Codex     = LibStub("LibCodex-Quests-1.0")  -- domain lib

local db        = Cairn.DB.New("MyGuideAddonDB", {
    defaults = { profile = { autoAdvance = true, currentQuest = nil } },
})

local settings  = Cairn.Settings.New(addonName, db, {
    { key = "autoAdvance", type = "toggle", default = true,
      label = "Auto-advance to next quest" },
})

function addon:OnLogin()
    local quest = Codex:GetQuest(db.profile.currentQuest)
    if quest then log:Info("resumed at quest %s", quest.name) end
end

local slash = Cairn.Slash.Register(addonName, "/guide")
slash:Subcommand("next", function()
    local q = Codex:GetNextQuest(db.profile.currentQuest)
    if q then db.profile.currentQuest = q.id; log:Info("now on %s", q.name) end
end, "advance to next quest")
slash:Default(function() settings:Open() end)
```

Cairn never knows or cares that LibCodex exists. LibCodex never knows
or cares that Cairn exists. Your addon depends on both, calls into
both, and they coexist without coupling. The Dashboard (`/cairn dash`)
will pick up your addon's source automatically because it logged at
load time.

This pattern works the same for any domain library — `LibCodex` for
quest data, `LibSharedMedia-3.0` for fonts/textures, your own internal
data layer, third-party APIs you wrap. Cairn stays small and stable;
the domain libs evolve independently.

---

## Slash commands (Cairn itself)

```
/cairn                          show available subcommands
/cairn log                      toggle log window
/cairn log clear                empty log buffer
/cairn log level <name>         set window min level + global level
/cairn log source <name|all>    filter window to one source
/cairn log search <query>       substring search
/cairn log echo <name>          set chat-echo level
/cairn log stats                show buffer/level summary
/cairn dash                     open developer dashboard
/cairn dashboard                alias for /cairn dash
/cairn dev                      alias for /cairn dash
```

Modules can add subcommands via `Cairn:RegisterSlashSub("name", fn, "help")`.

---

## Demo & test addons

`CairnTest` — exercises Events, Log, DB. Tracks `totalLogins` /
`totalEnters` across sessions.

```
/cairntest                      received counts + persistent totals
/cairntest spam                 emit one log line at every level
/cairntest db                   show DB profile state
/cairntest profile <name>       switch DB profile
/cairntest reset                reset profile to defaults
```

`CairnSettingsDemo` — a movable on-screen frame whose appearance is
driven by `Cairn.Settings`. EditMode-movable if LibEditMode is installed.

```
/csdemo                         open the settings panel
/csdemo show / hide             toggle the demo frame
/csdemo edit                    open Edit Mode panel
/csdemo reset                   reset profile to defaults
```

---

## Roadmap

**v0.1** (shipped):

- [x] `Cairn` umbrella facade + slash router
- [x] `Cairn.Events`
- [x] `Cairn.Log`
- [x] `Cairn.LogWindow`
- [x] `Cairn.DB`
- [x] `Cairn.Settings`
- [x] `Cairn.Addon`
- [x] `Cairn.Slash`

**v0.2** (in progress):

- [x] `Cairn.EditMode` (LibEditMode wrapper)
- [x] `anchor` schema type in `Cairn.Settings`
- [x] `text`, `color`, `keybind` schema types in `Cairn.Settings`
- [x] `Cairn.Comm` — addon-to-addon messaging
- [x] `Cairn.Locale` — i18n with locale fallback
- [x] `Cairn.Sequencer` — composable step runner
- [x] `Cairn.Hooks` — multi-callback hook helper
- [x] `Cairn.Timer` — owner-grouped timers + named replacement

**v0.3 stretch:**

- (none currently planned)

**Explicitly NOT planned:** widget toolkit, shared media library
(LibSharedMedia exists), threading beyond a basic timer (Lua coroutines
are fine).

---

## File layout

```
Cairn/
  Cairn.toc                       Mainline / Retail manifest (Interface 120005).
  Cairn_Mists.toc                 MoP Classic manifest (Interface 50503).
  Cairn_TBC.toc                   TBC Anniversary manifest (Interface 20505).
  Cairn_Vanilla.toc               Classic Era / Hardcore manifest (Interface 11508).
  Cairn_XPTR.toc                  Experimental PTR manifest (Interface 120007).
                                  All five share the same load order.
  CHANGELOG.md                    Release notes (Keep a Changelog format).
  Libs/LibStub/LibStub.lua        Vendored standard LibStub. Public domain.
  Cairn.lua                                  Umbrella facade + /cairn slash router.
  CairnEvents/Cairn-Events-1.0.lua           Event subscription.
  CairnLog/Cairn-Log-1.0.lua                 Leveled logger.
  CairnLogWindow/Cairn-LogWindow-1.0.lua     UI viewer for the log buffer.
  CairnDB/Cairn-DB-1.0.lua                   SavedVariables wrapper with profiles.
  CairnSettings/Cairn-Settings-1.0.lua       Declarative schema + Blizzard panel bridge.
  CairnAddon/Cairn-Addon-1.0.lua             Addon lifecycle helpers.
  CairnSlash/Cairn-Slash-1.0.lua             Generic slash router for any addon.
  CairnEditMode/Cairn-EditMode-1.0.lua       Optional LibEditMode wrapper (v0.2).
  CairnLocale/Cairn-Locale-1.0.lua           Per-addon i18n with fallback (v0.2).
  CairnSequencer/Cairn-Sequencer-1.0.lua     Composable step runner (v0.2).
  CairnHooks/Cairn-Hooks-1.0.lua             Multi-callback hook helper (v0.2).
  CairnTimer/Cairn-Timer-1.0.lua             Owner-grouped timers + named replacement (v0.2).
  CairnComm/Cairn-Comm-1.0.lua               Addon-to-addon messaging via CHAT_MSG_ADDON (v0.2).
  Cairn-Gui-1.0/                             Diesal-derived widget family (v1).
    Cairn-Gui-1.0.lua                          Widget kit base.
    Cairn-Gui-Tools-1.0/...                    Foundation utilities.
    Cairn-Gui-Style-1.0/...                    Textures, outlines, fonts, media registration.
    Cairn-Gui-Core-1.0/...                     12 widgets (Window, Button, CheckBox, ...).
    Cairn-Gui-Menu-1.0/...                     Context-menu widgets on top of Core.
  Cairn-Gui-2.0/                             v2 widget library + bundles.
    Cairn-Gui-2.0.lua, Core/, Mixins/          Engine, primitives, layout, animation, theme.
    Cairn-Gui-Widgets-Standard-2.0/...         Standard widget bundle (Button, Label, ...).
    Cairn-Gui-Theme-Default-2.0/...            Default visual theme.
  CairnSettingsPanel/Cairn-SettingsPanel-1.0.lua  Cairn.Gui renderer for Cairn.Settings schemas (v0.2).
  CairnStandalone/Cairn-Standalone-1.0.lua   SavedVariables wiring + /cairn log subcommands.
                                             Standalone-only; do NOT embed.
  README.md                       This file.
  LICENSE                         MIT.
```

---

## License

MIT. See [LICENSE](LICENSE).

LibStub is vendored under its public-domain dedication.

---

## Author

ChronicTinkerer — <https://github.com/ChronicTinkerer/cairn>

Issues, ideas, and pull requests welcome.
