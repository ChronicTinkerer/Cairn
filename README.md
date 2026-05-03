# Cairn

> Modern composable libraries for World of Warcraft addons.

Cairn is a small collection of independent, modern Lua libraries for WoW
addon authors. Pick the pieces you need, leave the rest.

It targets **WoW Retail (Midnight, Interface 120005)** and is positioned as
a fresh alternative to Ace3 — not a successor, not a fork. The libraries
are designed to be useful on their own, including alongside Ace3 if you're
already invested.

**Status:** v0.1.0, early development. Shipping today: `Cairn.Events`,
`Cairn.Log`, `Cairn.LogWindow`, `Cairn.DB`, `Cairn.Settings`. Planned
for v0.1: `Cairn.Addon`, `Cairn.Slash`. v0.2 will add EditMode anchor
support to Settings. See [Roadmap](#roadmap).

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
local log = Cairn.Log(addonName)

local db = Cairn.DB.New("MyAddonDB", {
    defaults = { profile = { scale = 1.0, enabled = true } },
})

local settings = Cairn.Settings.New(addonName, db, {
    { key = "enabled", type = "toggle", default = true,  label = "Enabled" },
    { key = "scale",   type = "range",  default = 1.0,
      min = 0.5, max = 2.0, step = 0.1, label = "Scale" },
})

log:Info("loaded version %s", "1.0.0")

Cairn.Events:Subscribe("PLAYER_LOGIN", function()
    log:Info("welcome back, scale=%s", tostring(db.profile.scale))
end, addonName)
```

That's a complete addon: persistent settings, a real Blizzard Settings
panel entry, event subscription, and printf-style logging — under 20
lines of code.

---

## Modules

### `Cairn` (umbrella facade)

The umbrella is a tiny lazy loader. Indexing `Cairn.Foo` calls
`LibStub("Cairn-Foo-1.0", true)` under the hood and caches the result.
If the module isn't loaded, indexing returns `nil` so you get a clean
"attempt to call a nil value" at the call site rather than confusing
errors deep inside Cairn.

```lua
Cairn._VERSION                                      -- "0.1.0"
Cairn._NAME                                         -- "Cairn"
Cairn:RegisterSlashSub(name, fn, helpText)          -- add a /cairn <name> subcommand
```

The slash router owns the single `SLASH_CAIRN1 = "/cairn"` registration.
Modules call `Cairn:RegisterSlashSub(...)` to add subcommands without
fighting each other for the slash slot.

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
Cairn.LogWindow:SetSourceFilter("MyAddon")  -- nil or "all" = no filter
Cairn.LogWindow:SetMinLevel("DEBUG")
Cairn.LogWindow:SetSearch("config")
```

Requires `Cairn.Log` to be loaded.

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

-- Read/write through .profile and .global AFTER ADDON_LOADED.
print(db.profile.scale)
db.profile.scale = 1.5

-- Profile management
db:GetCurrentProfile()           -- "MyChar - MyRealm" or "Default"
db:GetProfiles()                 -- sorted list of all profile names
db:SetProfile("PvP")             -- switch (creates if missing)
db:ResetProfile()                -- wipe current profile, reapply defaults
db:DeleteProfile("OldOne")       -- can't delete current
db:CopyProfile("From", "To")     -- deep copy

local unsub = db:OnProfileChanged(function(newName, oldName)
    -- refresh your UI here
end, addonName)
```

Defaults are deep-copied into a profile when that profile is FIRST
CREATED. Adding new keys to your defaults later does NOT retroactively
appear in existing profiles. Use `ResetProfile()` or a migration to push
new defaults into existing data.

`Cairn.DB(svName, opts)` is sugar for `Cairn.DB.New(svName, opts)`.

---

### `Cairn.Settings` — declarative config + Blizzard panel bridge

Take a flat schema, get a real entry in Blizzard's native Settings panel.
Values persist through a `Cairn.DB` instance you provide, so settings,
profiles, and SavedVariables share the same storage.

```lua
local settings = Cairn.Settings.New(addonName, db, {
    { key = "h_general",  type = "header",  label = "General" },
    { key = "enabled",    type = "toggle",  default = true,  label = "Enabled" },

    { key = "h_display",  type = "header",  label = "Display" },
    { key = "scale",      type = "range",   default = 1.0,
      min = 0.5, max = 2.0, step = 0.1,
      label = "Scale", tooltip = "How big the frame is",
      onChange = function(value, oldValue) MyAddon:Rescale(value) end },
    { key = "anchor",     type = "dropdown", default = "TOPLEFT",
      label = "Anchor",
      choices = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right",
                  BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right" } },
})

settings:Open()                  -- opens Blizzard Settings to your addon
settings:Get("scale")            -- 1.0
settings:Set("scale", 1.5)       -- writes to db.profile.scale, fires onChange
local unsub = settings:OnChange("scale", function(value, oldValue)
    -- subscribe to a specific key (returns an unsubscribe closure)
end, addonName)
```

**Schema entry types (v0.1):**

| Type       | Required fields                    | Notes |
|------------|------------------------------------|-------|
| `header`   | `label`                            | Section header, not a setting |
| `toggle`   | `default`, `label`                 | Boolean checkbox |
| `range`    | `default`, `label`, `min`, `max`   | Numeric slider; `step` defaults to 0.1 |
| `dropdown` | `default`, `label`, `choices`      | `choices` is `{value = label, ...}` |

**Common fields:** `key` (required, unique within the schema),
`tooltip` (optional hover text), `onChange` (optional `function(value, oldValue)`).

**Defaults are seeded into `db.profile` on `Settings.New`.** Only keys
that are currently `nil` get the default written, so existing user values
survive addon upgrades. To force-update an existing profile, call
`db:ResetProfile()`.

**Schema order is preserved.** Define entries in the order you want them
to appear in the panel.

**Classic / no-Settings fallback:** if the modern Blizzard Settings global
isn't available, `Cairn.Settings.New` returns a stub that supports
`Get`, `Set`, and `OnChange` but cannot render a panel; `Open()` warns
without erroring. Your addon keeps working; users just don't get the
panel.

**Planned for v0.2:** `text`, `color`, `keybind`, and `anchor` (the
EditMode integration). Anchor-typed entries will auto-register the
named frame with Edit Mode so users can drag it visually.

---

## Slash commands

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

`CairnTest` is a tiny smoke addon that exercises `Cairn.Events`,
`Cairn.Log`, and `Cairn.DB`. It tracks `totalLogins` / `totalEnters`
across sessions so you can verify persistence.

```
/cairntest                      received counts + persistent totals
/cairntest has                  Has() check for a few events
/cairntest spam                 emit one log line at every level
/cairntest unsub                unsubscribe all handlers (test teardown)
/cairntest db                   show DB profile state
/cairntest profile <name>       switch to a different DB profile
/cairntest reset                reset current profile to defaults
```

`CairnSettingsDemo` adds a movable on-screen frame whose appearance
(visibility, scale, color theme) is driven by `Cairn.Settings`. Open
the panel via Game Menu -> Options -> AddOns -> Cairn Settings Demo,
or with `/csdemo`.

```
/csdemo                         open the settings panel
/csdemo show                    show the demo frame
/csdemo hide                    hide the demo frame
/csdemo reset                   reset profile to defaults
```

---

## Roadmap

**v0.1** (this release):

- [x] `Cairn` umbrella facade + slash router
- [x] `Cairn.Events`
- [x] `Cairn.Log`
- [x] `Cairn.LogWindow`
- [x] `Cairn.DB` — SavedVariables with profiles, defaults
- [x] `Cairn.Settings` — declarative schema, Blizzard panel bridge
- [ ] `Cairn.Addon` — addon bootstrapping (lifecycle hooks, registry)
- [ ] `Cairn.Slash` — slash router for any addon, not just /cairn

**v0.2 stretch:**

- `Cairn.Settings` — `text`, `color`, `keybind`, `anchor` (EditMode) types
- `Cairn.Comm` — addon-to-addon messaging (AceComm replacement)
- `Cairn.Locale` — i18n helper
- `Cairn.Hooks` — secure hooks helper
- `Cairn.Timer` — scheduling

**Explicitly NOT planned:** widget toolkit (use Blizzard's frame APIs or
roll your own — that's what every popular addon does), shared media
library (LibSharedMedia exists and works), threading/scheduling library
beyond a basic timer (Lua coroutines are fine).

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
