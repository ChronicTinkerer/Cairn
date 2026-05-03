# Cairn

> Modern composable libraries for World of Warcraft addons.

Cairn is a small collection of independent, modern Lua libraries for WoW
addon authors. Pick the pieces you need, leave the rest.

It targets **WoW Retail (Midnight, Interface 120005)** and is positioned as
a fresh alternative to Ace3 — not a successor, not a fork. The libraries
are designed to be useful on their own, including alongside Ace3 if you're
already invested.

**Status:** v0.1.0, early development. Shipping today: `Cairn.Events`,
`Cairn.Log`, `Cairn.LogWindow`. Planned for v0.1: `Cairn.Addon`,
`Cairn.DB`, `Cairn.Slash`, `Cairn.Settings`. See [Roadmap](#roadmap).

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
- **Plays well with Blizzard's modern UI.** The flagship `Cairn.Settings`
  module (planned, see roadmap) will bridge to the native Settings panel
  and register frames with Edit Mode automatically.
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
  Core.lua
```

In `MyAddon.toc`:

```
## Interface: 120005
## Title: MyAddon

Libs\LibStub\LibStub.lua
Libs\Cairn\Cairn.lua
Libs\Cairn\Cairn-Events-1.0.lua
Libs\Cairn\Cairn-Log-1.0.lua

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
log:Info("loaded version %s", "1.0.0")

Cairn.Events:Subscribe("PLAYER_LOGIN", function()
    log:Info("welcome back")
end, addonName)

Cairn.Events:Subscribe("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    log:Debug("entering world  isLogin=%s  isReload=%s",
        tostring(isLogin), tostring(isReload))
end, addonName)
```

That's a complete addon. Subscribe to events with closures, log with
printf-style formatting, see your messages in chat AND in the
`/cairn log` window.

---

## Modules

### `Cairn` (umbrella facade)

The umbrella is a tiny lazy loader. Indexing `Cairn.Foo` calls
`LibStub("Cairn-Foo-1.0", true)` under the hood and caches the result.
If the module isn't loaded, indexing returns `nil` so you get a clean
"attempt to call a nil value" at the call site rather than confusing
errors deep inside Cairn.

Public methods on the umbrella:

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
allowed (CallbackHandler-1.0 disallows that, which is one reason we
don't use it directly).

```lua
-- Subscribe. Returns an unsubscribe closure.
local unsub = Cairn.Events:Subscribe(event, handler, owner)

-- Owner is optional but recommended; pass your addon name. Used for
-- mass unsubscribe and as a debugging label.

-- Unsubscribe just this handler:
unsub()

-- Unsubscribe everything for an owner (use in addon teardown):
Cairn.Events:UnsubscribeAll(owner)

-- Check if any handler is registered:
Cairn.Events:Has(event)   -- true | false
```

Handler signature: receives the event payload args (NOT the event name —
matches the modern WoW pattern where you typically know which event
you subscribed to).

Errors in one handler are caught with `pcall` and routed to
`geterrorhandler()`; they don't abort the rest of the dispatch.

---

### `Cairn.Log` — leveled logging

Per-source loggers, ring-buffer storage, optional chat echo, configurable
persistence to SavedVariables.

**Levels** (severity descending):

| Level   | Number | Default visibility |
|---------|--------|--------------------|
| `ERROR` | 1      | shown, chat echo   |
| `WARN`  | 2      | shown, chat echo   |
| `INFO`  | 3      | shown, chat echo   |
| `DEBUG` | 4      | hidden             |
| `TRACE` | 5      | hidden             |

**Per-source logger:**

```lua
local log = Cairn.Log("MyAddon")    -- get or create logger for "MyAddon"

log:Trace("very verbose: %d", n)
log:Debug("subscribed to %d events", n)
log:Info("loaded version %s", v)
log:Warn("config key %q is deprecated", k)
log:Error("parse failed: %s", err)

log:SetLevel("DEBUG")               -- raise verbosity for THIS source only
log:GetLevel()                      -- current effective level (number)
log:ClearLevel()                    -- revert to global level
```

All level methods accept printf-style format args and use `string.format`
under the hood. A malformed format string is caught — the message goes
to the buffer with a `[LOG FORMAT ERROR]` suffix instead of crashing
the logger.

**Module-level controls:**

```lua
Cairn.Log:SetGlobalLevel("WARN")    -- default level for all sources
Cairn.Log:SetChatEchoLevel("WARN")  -- only echo WARN+ to chat
Cairn.Log:SetPersistence(1000)      -- save last N entries to SV (0 = off)

Cairn.Log:Count()                   -- live entries in buffer
Cairn.Log:Clear()                   -- empty buffer
Cairn.Log:GetEntries(filterFn)      -- snapshot, oldest first

-- Subscribe to new entries (LogWindow uses this):
local unsub = Cairn.Log:OnNewEntry(function(entry) ... end, owner)

-- SavedVariables hooks (the standalone Cairn addon wires these):
local sv = Cairn.Log:DumpToSV()
Cairn.Log:LoadFromSV(sv)
```

Each entry is a table:

```lua
{ ts = 1730000000, level = 3, source = "MyAddon", message = "loaded version 1.0" }
```

---

### `Cairn.LogWindow` — UI viewer

Movable, resizable window that subscribes to `Cairn.Log` and shows
recent entries with filters. Open with `/cairn log`.

```lua
Cairn.LogWindow:Toggle()
Cairn.LogWindow:Show()
Cairn.LogWindow:Hide()
Cairn.LogWindow:IsShown()

Cairn.LogWindow:SetSourceFilter("MyAddon")   -- nil or "all" = no filter
Cairn.LogWindow:SetMinLevel("DEBUG")         -- show DEBUG and more severe
Cairn.LogWindow:SetSearch("config")          -- substring; nil to clear
Cairn.LogWindow:Refresh()                    -- usually automatic
```

`Cairn.LogWindow` requires `Cairn.Log` to be loaded. If you embed Cairn
into your addon and only want logging without the window, skip
`Cairn-LogWindow-1.0.lua` from your `.toc`.

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

## CairnTest

`CairnTest` is a deliberately-tiny addon that proves Cairn loads and
dispatches in real WoW. It depends on the standalone Cairn addon and
demonstrates `Cairn.Events` and `Cairn.Log` in ~50 lines.

After login you should see two `[Cairn] [CairnTest INFO]` lines in
chat — one for `PLAYER_LOGIN`, one for `PLAYER_ENTERING_WORLD`.

```
/cairntest         -- show received event counts
/cairntest has     -- check Has() for a few events
/cairntest spam    -- emit one log line at every level
/cairntest unsub   -- unsubscribe all handlers (for testing teardown)
```

---

## Roadmap

**v0.1 in progress** (this release focuses on getting the loader
pattern, slash router, and diagnostics right):

- [x] `Cairn` umbrella facade + slash router
- [x] `Cairn.Events`
- [x] `Cairn.Log`
- [x] `Cairn.LogWindow`
- [ ] `Cairn.Addon` — addon bootstrapping (lifecycle hooks, registry)
- [ ] `Cairn.DB` — SavedVariables with profiles, defaults, migrations
- [ ] `Cairn.Slash` — slash router for any addon, not just /cairn
- [ ] `Cairn.Settings` — declarative config schema, bridges to Blizzard
      Settings panel, registers Edit Mode anchors

**v0.2 stretch:**

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
  Cairn-Standalone-1.0.lua        SavedVariables wiring + /cairn log subs.
                                  Standalone-only; do NOT embed.
  README.md                       This file.
```

---

## License

MIT. See [LICENSE](LICENSE).

LibStub is vendored under its public-domain dedication.

---

## Author

ChronicTinkerer — <https://github.com/ChronicTinkerer/cairn>

Issues, ideas, and pull requests welcome.
