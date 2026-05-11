# Cairn

A modern alternative to Ace3 for World of Warcraft addon authors.

Composable libraries — Addon, DB, Slash, Events, Locale, Log, Util, Hooks, Timer, Settings, Callback, Media — plus a feature-complete v2 GUI family (Core, Standard widgets, Secure widgets, Layouts-Extra, Theme-Default) and GUI consumers (SettingsPanel, LogWindow). The flagship is the Settings library, which bridges to Blizzard's native Settings panel.

## Design principle

Keep things simple wherever possible. When complexity is unavoidable, be intentional about it, and wrap it behind an interface that lets consumers stay simple.

That's the one-sentence test for every design decision in Cairn. The principle applies to **the consumer**: a 250-line lib that lets the consumer write a one-liner is a better outcome than a 50-line lib that forces every consumer to roll their own dispatch + help. Internal complexity is fine when it shrinks the consumer surface.

## What's inside

| Lib | Purpose | LibStub MAJOR |
| --- | --- | --- |
| `Cairn-Addon` | Addon lifecycle (OnInit / OnLogin / OnDisable) with retro-fire | `Cairn-Addon` |
| `Cairn-DB` | SavedVariables wrapper with default merging and named profiles | `Cairn-DB` |
| `Cairn-Slash` | Slash command registry with nested subcommand routing | `Cairn-Slash` |
| `Cairn-Events` | WoW event router + internal addon-to-addon event channel | `Cairn-Events` |
| `Cairn-Locale` | i18n table with locale fallback + runtime change notifications | `Cairn-Locale` |
| `Cairn-Log` | Categorized ring-buffer log shared across consumers | `Cairn-Log` |
| `Cairn-Hooks` | Pre/Post/Wrap hook helpers with batch-cancel | `Cairn-Hooks` |
| `Cairn-Timer` | After / Every / Debounce / Stopwatch with ownership tracking | `Cairn-Timer` |
| `Cairn-Settings` | Declarative settings schema → Blizzard's native Settings panel | `Cairn-Settings` |
| `Cairn-Callback` | CallbackHandler-1.0 compatibility shim | `Cairn-Callback` |
| `Cairn-Util` | Small utilities organized into sub-namespaces (Hash, …) | `Cairn-Util` |
| `Cairn-Media` | Two-mode asset registry (private + public via LSM) + icon glyphs | `Cairn-Media` |
| `Cairn-Gui-2.0` | Widget framework — Container / Button / Label / Window / Checkbox / ScrollFrame / EditBox / Slider / Dropdown / TabGroup, plus Secure variants | `Cairn-Gui-2.0` |

## Quick start

```lua
local CA = LibStub("Cairn-Addon")
local CDB = LibStub("Cairn-DB")
local CS = LibStub("Cairn-Settings")
local CSlash = LibStub("Cairn-Slash")

local addon = CA:New("MyAddon")

local db = CDB:New("MyAddonDB", {
    profile = { scale = 1.0, theme = "dark" },
})

local settings = CS:New("MyAddon", db, {
    { key = "scale", type = "range",    label = "Scale",
      min = 0.5, max = 2.0, step = 0.1, default = 1.0 },
    { key = "theme", type = "dropdown", label = "Theme",
      default = "dark",
      choices = { dark = "Dark", light = "Light" } },
})

local slash = CSlash:Register("MyAddon", "/myaddon", { aliases = { "/ma" } })
slash:Sub("config", function() settings:Open() end, "open settings")

function addon:OnInit() print("MyAddon loaded") end
function addon:OnLogin() print("MyAddon ready") end
```

## Naming

LibStub MAJORs have no version suffix. Use `LibStub("Cairn-Addon")`, not `LibStub("Cairn-Addon-1.0")`. The Cairn-Gui-2.0 family is the one exception — those MAJORs keep their `-2.0` suffix since they were not rewritten.

## License

MIT. See `LICENSE`.

## Distribution

- CurseForge: project 1532175
- Wago: project `b6XemBKp`
- WoWInterface: project 27134
