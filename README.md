# Cairn

> Modern composable libraries for World of Warcraft addons.

Cairn is a small collection of independent, modern Lua libraries for WoW
addon authors. Pick the pieces you need, leave the rest.

It targets **WoW Retail (Midnight, Interface 120005)** and is positioned as
a fresh alternative to Ace3 — not a successor, not a fork. The libraries
are designed to be useful on their own, including alongside Ace3 if you're
already invested.

**Status:** v0.1.0, complete. Shipping today: `Cairn.Events`, `Cairn.Log`,
`Cairn.LogWindow`, `Cairn.DB`, `Cairn.Settings`, `Cairn.Addon`,
`Cairn.Slash`. v0.2 will add EditMode anchor support to Settings plus
`Cairn.Comm`. See [Roadmap](#roadmap).

---

## Why Cairn?

Most popular WoW addons today don't actually use Ace3 wholesale.
WeakAuras, Details!, BigWigs, DBM, Plater, MRT all rolled their own
architecture. ElvUI uses three Ace3 libraries and ignores the rest. The
common pattern is: cherry-pick what works, write the rest from scratch.

Cairn is what that "rest from scratch" could look like if you started
today, with these decisions baked in:

- **Composable, not monolithic.** No required core, no mixin chain. Each
  module is independently usable; the umbrella `Cairn` table just
  resolves them on first access.
- **Modern Lua patterns.** Closure handlers instead of mixin methods.
  Subscribe calls return an unsubscribe function.
- **Plays well with Blizzard's modern UI.** `Cairn.Settings` writes
  directly into the native Settings panel (no custom config window for
  the simple case). EditMode anchor integration lands in v0.2.
- **No widget toolkit.** Survey said most authors roll their own UI;
  Cairn doesn't fight that. (`Cairn.LogWindow` is a focused exception
  for diagnostics.)

---

## Installation

Cairn supports two distribution modes. Both expose the same `Cairn.X` API.

### Mode 1: Standalone (recommended for end users)

Install Cairn as its own addon. Other addons that depend on Cairn list
it as a `## Dependencies` line in their `.toc`.

1. Copy the `Cairn/` folder into:
   `World of Warcraft\_retail_\Interface\AddOns\Cairn\`
2. Make sure Cairn is enabled in your in-game AddOns list.
3. Any addon that depends on Cairn loads after it automatically.

After login, type `/cairn` to see the available subcommands.

### Mode 2: Embedded (recommended for addon authors shipping a single zip)

Drop the Cairn module files into your addon's `Libs/` directory and
include them in your `.toc` BEFORE your own files. LibStub's
version-deduplication means only the highest-version copy stays loaded
even if multiple addons embed the same module.

Example layout:

```
MyAddon/
  MyAddon.toc
  Libs/
    LibStub/
      LibStub.lua
    Cairn/
      Cairn.lua
      Cairn-Events-1.0.lua
      Cairn-Log-1.0.lua
      Cairn-DB-1.0.lua
      Cairn-Settings-1.0.lua
      Cairn-Addon-1.0.lua
      Cairn-Slash-1.0.lua
  Core.lua
```

Do NOT embed `Cairn-Standalone-1.0.lua` — it's only meant for the
standalone Cairn addon (it wires SavedVariables and the `/cairn` slash
router).

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

That's a complete addon: lifecycle hooks, persistent settings, a real
Blizzard Settings panel entry, slash commands, and printf-style
logging — under 25 lines of code.

---

## Modules

### `Cairn` (umbrella facade)

The umbrella is a tiny lazy loader. Indexing `Cairn.Foo` calls
`LibStub("Cairn-Foo-1.0", true)` under the hood and caches the result.
If the module isn't loaded, indexing returns `nil` so you get a clean
"attempt to call a nil value" at the call site.

```lua
Cairn._VERSION                                      -- "0.1.0"
Cairn._NAME                                         -- "Cairn"
Cairn:RegisterSlashSub(name, fn, helpText)          -- add a /cairn <name> subcommand
```

The slash router owns the single `SLASH_CAIRN1 = "/cairn"` registration.
Modules call `Cairn:RegisterSlashSub(...)` so subcommands compose
without fighting each other.

---

### `Cairn.Events` — event subscription

Modern game-event subscription with closure handlers and owner-based
mass unsubscribe. Multiple handlers per `(owner, event)` pair are
allowed.

```lua
local unsub = Cairn.Events:Subscribe(event, handler, owner)
unsub()                                  -- remove just this handler
Cairn.Events:UnsubscribeAll(owner)       -- remove all for an owner
Cairn.Events:Has(event)                  -- true | false
```

Handler signature: receives the event payload args (NOT the event name).
Errors are caught with `pcall` and routed to `geterrorhandler()`.

---

### `Cairn.Log` — leveled logging

Per-source loggers, ring-buffer storage, optional chat echo, configurable
persistence to SavedVariables.

```lua
local log = Cairn.Log("MyAddon")
log:Info("loaded v%s", "1.0")
log:Warn("config key %q deprecated", k)
log:Error("parse failed: %s", err)
log:SetLevel("DEBUG")                    -- this source only

Cairn.Log:SetGlobalLevel("WARN")
Cairn.Log:SetChatEchoLevel("WARN")
Cairn.Log:SetPersistence(1000)
Cairn.Log:GetEntries(filterFn)
Cairn.Log:OnNewEntry(fn, owner)          -- LogWindow uses this
```

Levels (severity descending): `ERROR (1)`, `WARN (2)`, `INFO (3)`,
`DEBUG (4)`, `TRACE (5)`. Default visibility is `INFO+`.

---

### `Cairn.LogWindow` — UI viewer

Movable, resizable window that subscribes to `Cairn.Log` and shows
recent entries with filters. Open with `/cairn log`.

```lua
Cairn.LogWindow:Toggle()
Cairn.LogWindow:SetSourceFilter("MyAddon")
Cairn.LogWindow:SetMinLevel("DEBUG")
Cairn.LogWindow:SetSearch("config")
```

Requires `Cairn.Log`.

---

### `Cairn.DB` — SavedVariables with profiles

Wraps a SavedVariables global with profile support and defaults.

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

db:GetCurrentProfile()           -- "MyChar - MyRealm" or "Default"
db:GetProfiles()                 -- sorted list of all profile names
db:SetProfile("PvP")             -- switch (creates if missing)
db:ResetProfile()
db:DeleteProfile("OldOne")       -- can't delete current
db:CopyProfile("From", "To")     -- deep copy

local unsub = db:OnProfileChanged(function(newName, oldName) ... end, addonName)
```

Defaults are deep-copied into a profile when that profile is FIRST
CREATED. Use `ResetProfile()` to push new defaults into existing data.

---

### `Cairn.Settings` — declarative config + Blizzard panel bridge

Take a flat schema, get a real entry in Blizzard's native Settings
panel. Values persist through a `Cairn.DB` instance you provide.

```lua
local settings = Cairn.Settings.New(addonName, db, {
    { key = "h_general",  type = "header", label = "General" },
    { key = "enabled",    type = "toggle", default = true, label = "Enabled" },
    { key = "scale",      type = "range",  default = 1.0,
      min = 0.5, max = 2.0, step = 0.1,
      label = "Scale", tooltip = "How big the frame is",
      onChange = function(value, oldValue) MyAddon:Rescale(value) end },
    { key = "anchor",     type = "dropdown", default = "TOPLEFT", label = "Anchor",
      choices = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right" } },
})

settings:Open()                  -- opens Blizzard Settings to your addon
settings:Get("scale")            -- 1.0
settings:Set("scale", 1.5)       -- writes to db.profile, fires onChange
settings:OnChange("scale", fn, owner)  -- subscribe; returns unsubscribe
```

| Type       | Required fields                    | Notes |
|------------|------------------------------------|-------|
| `header`   | `label`                            | Section header, not a setting |
| `toggle`   | `default`, `label`                 | Boolean checkbox |
| `range`    | `default`, `label`, `min`, `max`   | Numeric slider; `step` defaults to 0.1 |
| `dropdown` | `default`, `label`, `choices`      | `choices` is `{value = label, ...}` |

Defaults seed `db.profile` only for keys currently `nil`, so existing
user values survive addon upgrades. Schema order is preserved in the
panel. If Blizzard's modern Settings global isn't available (Classic),
`New` returns a Get/Set/OnChange-only stub.

**Planned for v0.2:** `text`, `color`, `keybind`, and `anchor` (the
EditMode integration).

---

### `Cairn.Addon` — lifecycle helpers

Removes the boilerplate of subscribing to ADDON_LOADED, PLAYER_LOGIN,
PLAYER_ENTERING_WORLD, and PLAYER_LOGOUT.

```lua
local addon = Cairn.Addon.New("MyAddon")

function addon:OnInit()    end  -- ADDON_LOADED for your addon (SVs ready)
function addon:OnLogin()   end  -- PLAYER_LOGIN
function addon:OnEnter(isLogin, isReload) end  -- PLAYER_ENTERING_WORLD
function addon:OnLogout()  end  -- PLAYER_LOGOUT

addon:Log()                     -- lazy Cairn.Log("MyAddon"), cached
Cairn.Addon.Get("MyAddon")      -- registry lookup
```

Hooks that aren't defined are simply skipped. ADDON_LOADED is filtered
to your addon name automatically. Errors in hooks are caught with
`pcall` and routed to `geterrorhandler()`.

Requires `Cairn.Events`.

---

### `Cairn.Slash` — generic slash router

Slash commands for any addon, with subcommand routing, aliases,
auto-help, and a quote-aware arg splitter. (The `/cairn` router in
Cairn.lua is for Cairn itself; `Cairn.Slash` is for your addon.)

```lua
local s = Cairn.Slash.Register("MyAddon", "/myaddon", { aliases = { "/ma" } })

s:Subcommand("config", function(rest) MyAddon:OpenConfig() end, "open config")
s:Subcommand("reset",  function() MyAddon:Reset() end, "reset everything")
s:Default(function(input) MyAddon:DefaultAction(input) end)

s:Run("config")                  -- programmatic dispatch
s:Aliases({ "/m", "/ma" })       -- replace alias list
s:PrintHelp()                    -- print the auto-generated help
local args = s:Args('hello "two words" three')   -- {"hello","two words","three"}
Cairn.Slash.Get("MyAddon")       -- registry lookup
```

If the user types `/myaddon` with no subcommand and no `Default` is
set, the auto-help fires. `/myaddon help` and `/myaddon ?` always print
the auto-help.

---

## Slash commands (Cairn itself)

Registered by the standalone Cairn addon (or any addon that loads
`Cairn-Standalone-1.0.lua`, but you should not embed that file).

```
/cairn                          show available subcommands
/cairn help                     same
/cairn log                      toggle log window
/cairn log clear                empty log buffer
/cairn log level <name>         set window min level + global level
                                (TRACE | DEBUG | INFO | WARN | ERROR)
/cairn log source <name|all>    filter window to one source (or all)
/cairn log search <query>       substring search; empty clears
/cairn log echo <name>          set chat-echo level
/cairn log stats                show buffer/level summary
```

Modules can register additional subcommands via
`Cairn:RegisterSlashSub("name", fn, "help text")`.

---

## Demo & test addons

`CairnTest` — exercises `Cairn.Events`, `Cairn.Log`, and `Cairn.DB`.
Tracks `totalLogins` / `totalEnters` across sessions so you can verify
persistence.

```
/cairntest                      received counts + persistent totals
/cairntest spam                 emit one log line at every level
/cairntest db                   show DB profile state
/cairntest profile <name>       switch DB profile
/cairntest reset                reset profile to defaults
```

`CairnSettingsDemo` — a movable on-screen frame whose appearance
(visibility, scale, color theme) is driven by `Cairn.Settings`. Open
the panel via Game Menu > Options > AddOns > Cairn Settings Demo, or
with `/csdemo`.

```
/csdemo                         open the settings panel
/csdemo show                    show the demo frame
/csdemo hide                    hide the demo frame
/csdemo reset                   reset profile to defaults
```

---

## Roadmap

**v0.1** (complete):

- [x] `Cairn` umbrella facade + slash router
- [x] `Cairn.Events`
- [x] `Cairn.Log`
- [x] `Cairn.LogWindow`
- [x] `Cairn.DB`
- [x] `Cairn.Settings`
- [x] `Cairn.Addon`
- [x] `Cairn.Slash`

**v0.2:**

- `Cairn.Settings` — `text`, `color`, `keybind`, `anchor` (EditMode) types
- `Cairn.Comm` — addon-to-addon messaging (AceComm replacement)
- `Cairn.Locale` — i18n helper
- `Cairn.Hooks` — secure hooks helper
- `Cairn.Timer` — scheduling

**Explicitly NOT planned:** widget toolkit (use Blizzard's frame APIs or
roll your own — that's what every popular addon does), shared media
library (LibSharedMedia exists and works), threading/scheduling beyond
a basic timer (Lua coroutines are fine).

---

## File layout

```
Cairn/
  Cairn.toc                       Manifest. Lists module files in load order.
  Libs/
    LibStub/
      LibStub.lua                 Vendored standard LibStub. Public domain.
  Cairn.lua                       Umbrella facade + /cairn slash router.
  Cairn-Events-1.0.lua            Event subscription.
  Cairn-Log-1.0.lua               Leveled logger.
  Cairn-LogWindow-1.0.lua         UI viewer for the log buffer.
  Cairn-DB-1.0.lua                SavedVariables wrapper with profiles.
  Cairn-Settings-1.0.lua          Declarative schema + Blizzard panel bridge.
  Cairn-Addon-1.0.lua             Addon lifecycle helpers.
  Cairn-Slash-1.0.lua             Generic slash router for any addon.
  Cairn-Standalone-1.0.lua        SavedVariables wiring + /cairn log subs.
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
