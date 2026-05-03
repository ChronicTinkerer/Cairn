# Cairn

> Modern composable libraries for World of Warcraft addons.

Cairn is a small collection of independent, modern Lua libraries for WoW
addon authors. Pick the pieces you need, leave the rest.

It targets **WoW Retail (Midnight, Interface 120005)** and is positioned as
a fresh alternative to Ace3 — not a successor, not a fork. The libraries
are designed to be useful on their own, including alongside Ace3 if you're
already invested.

**Status:** v0.2.0-dev. v0.1.0 shipped: `Cairn.Events`, `Cairn.Log`,
`Cairn.LogWindow`, `Cairn.DB`, `Cairn.Settings`, `Cairn.Addon`,
`Cairn.Slash`. v0.2 adds: `Cairn.EditMode` (LibEditMode wrapper),
the `anchor` schema type in `Cairn.Settings`, `Cairn.Dashboard`
(developer dashboard with copyable per-addon logs), and `Cairn.Locale`
(i18n with locale fallback). See [Roadmap](#roadmap).

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
- **Built-in dev tooling.** `Cairn.Dashboard` (`/cairn dash`) lists
  every addon Cairn knows about with per-source log filtering and
  copyable log dumps for bug reports.
- **No widget toolkit.** Survey said most authors roll their own UI;
  Cairn doesn't fight that.

---

## Installation

Cairn supports two distribution modes. Both expose the same `Cairn.X` API.

### Mode 1: Standalone (recommended for end users)

1. Copy the `Cairn/` folder into:
   `World of Warcraft\_retail_\Interface\AddOns\Cairn\`
2. Make sure Cairn is enabled in your in-game AddOns list.
3. Optionally install [LibEditMode](https://www.curseforge.com/wow/addons/libeditmode)
   from CurseForge if you want EditMode integration to work.
4. Any addon that depends on Cairn loads after it automatically.

After login, type `/cairn` to see the available subcommands.

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
      Cairn-Events-1.0.lua
      Cairn-Log-1.0.lua
      Cairn-DB-1.0.lua
      Cairn-Settings-1.0.lua
      Cairn-Addon-1.0.lua
      Cairn-Slash-1.0.lua
      Cairn-EditMode-1.0.lua    -- optional; needs LibEditMode installed
      Cairn-Dashboard-1.0.lua   -- optional; only useful in standalone mode
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

### `Cairn.Dashboard` — developer dashboard (v0.2)

Per-addon log viewer with copy-to-clipboard support, plus an Info tab
showing memory usage, lifecycle state, event subscription counts, slash
commands, and log entry counts by level. Open with `/cairn dash`.

```lua
Cairn.Dashboard:Show()
Cairn.Dashboard:Hide()
Cairn.Dashboard:Toggle()
Cairn.Dashboard:IsShown()
Cairn.Dashboard:SelectSource(name)   -- "All" or any registered source
Cairn.Dashboard:GetSources()         -- discovered sources, sorted, "All" first
Cairn.Dashboard:Refresh()            -- usually automatic
```

Sources are auto-discovered: any addon that has called `Cairn.Log("X")`,
`Cairn.Addon.New("X")`, or `Cairn.Slash.Register("X", ...)` shows up in
the left pane. Selecting a source filters the Logs tab and populates
the Info tab.

The Logs tab has a level-cycling button, search box, Clear (clears the
shared log buffer), and Copy (opens an EditBox popup with the current
view's entries pre-selected and ready for Ctrl+C — the standard WoW
pattern for clipboard copy).

The Info tab shows, for the selected source: memory usage (via
`GetAddOnMemoryUsage`, only meaningful for real addon names), lifecycle
state if registered with `Cairn.Addon` (timestamps for OnInit / OnLogin /
OnEnter / OnLogout), count of active event subscriptions for the owner,
slash commands registered, current logger level, and entry counts by
level for that source.

Module-level helper, exposed for testing:

```lua
Cairn.Dashboard.FormatLogsForCopy(sourceName, entries)   -- plain-text dump
```

Requires `Cairn.Log`. Optionally uses `Cairn.Events`, `Cairn.Addon`,
`Cairn.Slash` for richer Info-tab data; missing modules just hide their
sections.

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
- [x] `Cairn.Dashboard` (developer dashboard with copyable per-addon logs)
- [ ] `text`, `color`, `keybind` schema types in `Cairn.Settings`
- [ ] `Cairn.Comm` — addon-to-addon messaging
- [x] `Cairn.Locale` — i18n with locale fallback

**v0.3 stretch:**

- `Cairn.Hooks` — secure hooks helper
- `Cairn.Timer` — scheduling

**Explicitly NOT planned:** widget toolkit, shared media library
(LibSharedMedia exists), threading beyond a basic timer (Lua coroutines
are fine).

---

## File layout

```
Cairn/
  Cairn.toc                       Manifest. Lists module files in load order.
  Libs/LibStub/LibStub.lua        Vendored standard LibStub. Public domain.
  Cairn.lua                       Umbrella facade + /cairn slash router.
  Cairn-Events-1.0.lua            Event subscription.
  Cairn-Log-1.0.lua               Leveled logger.
  Cairn-LogWindow-1.0.lua         UI viewer for the log buffer.
  Cairn-DB-1.0.lua                SavedVariables wrapper with profiles.
  Cairn-Settings-1.0.lua          Declarative schema + Blizzard panel bridge.
  Cairn-Addon-1.0.lua             Addon lifecycle helpers.
  Cairn-Slash-1.0.lua             Generic slash router for any addon.
  Cairn-EditMode-1.0.lua          Optional LibEditMode wrapper (v0.2).
  Cairn-Dashboard-1.0.lua         Developer dashboard with copyable logs (v0.2).
  Cairn-Standalone-1.0.lua        SavedVariables wiring + /cairn log + /cairn dash.
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
