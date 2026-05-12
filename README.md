# Cairn

A modern alternative to Ace3 for World of Warcraft addon authors.

Composable libraries — Addon, DB, Slash, Events, Locale, Log, Util, Hooks, Timer, Settings, Callback, Media — plus a feature-complete v2 GUI family (Core, Standard widgets, Secure widgets, Layouts-Extra, Theme-Default) and GUI consumers (SettingsPanel, LogWindow). The flagship is the Settings library, which bridges to Blizzard's native Settings panel.

## Design principle

Keep things simple wherever possible. When complexity is unavoidable, be intentional about it, and wrap it behind an interface that lets consumers stay simple.

That's the one-sentence test for every design decision in Cairn. The principle applies to **the consumer**: a 250-line lib that lets the consumer write a one-liner is a better outcome than a 50-line lib that forces every consumer to roll their own dispatch + help. Internal complexity is fine when it shrinks the consumer surface.

## What's inside

| Lib | Purpose | LibStub MAJOR |
| --- | --- | --- |
| `Cairn-Core` | Bootstraps the `_G.Cairn` namespace. Foundation lib, loads first. | `Cairn-Core-1.0` |
| `Cairn-Addon` | Addon lifecycle (OnInit / OnLogin / OnDisable) with retro-fire | `Cairn-Addon-1.0` |
| `Cairn-DB` | SavedVariables wrapper with default merging and named profiles | `Cairn-DB-1.0` |
| `Cairn-Slash` | Slash command registry with nested subcommand routing | `Cairn-Slash-1.0` |
| `Cairn-Events` | WoW event router + internal addon-to-addon event channel | `Cairn-Events-1.0` |
| `Cairn-Locale` | i18n table with locale fallback + runtime change notifications | `Cairn-Locale-1.0` |
| `Cairn-Log` | Categorized ring-buffer log shared across consumers | `Cairn-Log-1.0` |
| `Cairn-Hooks` | Pre/Post/Wrap hook helpers with batch-cancel | `Cairn-Hooks-1.0` |
| `Cairn-Timer` | After / Every / Debounce / Stopwatch with ownership tracking | `Cairn-Timer-1.0` |
| `Cairn-Settings` | Declarative settings schema → Blizzard's native Settings panel | `Cairn-Settings-1.0` |
| `Cairn-Callback` | CallbackHandler-1.0 compatibility shim | `Cairn-Callback-1.0` |
| `Cairn-Util` | Small utilities organized into sub-namespaces (Pcall / Table / String / Path / Numbers / Queue / ObjectPool / Bitfield / Array / Frame / Texture / Hash) plus top-level `Memoize`. Single-file lib; vendored `AF_MD5.lua` separate for license attribution. | `Cairn-Util-1.0` |
| `Cairn-Media` | Two-mode asset registry (private + public via LSM) + icon glyphs | `Cairn-Media-1.0` |
| `Cairn-Flow` | Control-flow primitives — Sequencer / Decision tree / FSM / Behavior tree, four sub-namespaces under one MAJOR | `Cairn-Flow-1.0` |
| `Cairn-Gui-2.0` | Widget framework — Container / Button / Label / Window / Checkbox / ScrollFrame / EditBox / Slider / Dropdown / TabGroup, plus Secure variants | `Cairn-Gui-2.0` |

## Quick start

The preferred consumer surface is the `_G.Cairn` namespace, which resolves `Cairn.<Name>` lazily to `LibStub("Cairn-<Name>-1.0")`:

```lua
local addon = Cairn.Addon:New("MyAddon")

local db = Cairn.DB:New("MyAddonDB", {
    profile = { scale = 1.0, theme = "dark" },
})

local settings = Cairn.Settings:New("MyAddon", db, {
    { key = "scale", type = "range",    label = "Scale",
      min = 0.5, max = 2.0, step = 0.1, default = 1.0 },
    { key = "theme", type = "dropdown", label = "Theme",
      default = "dark",
      choices = { dark = "Dark", light = "Light" } },
})

local slash = Cairn.Slash:Register("MyAddon", "/myaddon", { aliases = { "/ma" } })
slash:Sub("config", function() settings:Open() end, "open settings")

function addon:OnInit() print("MyAddon loaded") end
function addon:OnLogin() print("MyAddon ready") end
```

The direct `LibStub("Cairn-Addon-1.0"):New(...)` form works equivalently — the namespace is just terser, and a missing lib gives a clear `attempt to index 'Cairn' (a nil value)` error.

GUI access does NOT go through the namespace — those libs are at MAJOR 2.0, not 1.0. Use `LibStub("Cairn-Gui-2.0")` directly.

## Standalone embeds

Every Cairn lib assumes two things at load time:

1. The `_G.Cairn` namespace exists with its resolving metatable installed. That bootstrap lives in `Core.lua` (registered as `Cairn-Core-1.0`).
2. Shared helpers (`Pcall.Call`, `Table.Snapshot`, `Table.MergeDefaults`, etc.) are reachable via `LibStub("Cairn-Util-1.0")`.

**If you embed a single Cairn lib (e.g. Cairn-Settings) inside your own addon without the full Cairn collection, you MUST also embed `Core.lua` and `Cairn-Util`.** Embedding any Cairn lib alone will fail at load.

Minimal embed list for a single-lib consumer:

```
embeds\LibStub\LibStub.lua          (or whatever LibStub you already ship)
Core.lua                            (Cairn-Core)
CairnUtil\Cairn-Util.lua            (Cairn-Util — single file, all sub-namespaces)
CairnUtil\AF_MD5.lua                (only if your lib calls Hash.MD5)
... then the lib you actually want
```

Inside a consumer that's loading Cairn alongside other addons, the regular `## OptionalDeps: Cairn` TOC entry handles this for you automatically; this list only matters for true single-lib vendoring.

## Try it / smoke test

A working consumer of every lib ships at `Cairn\SubAddons\CairnDemo\`. Enable it like any addon, then:

- `/cairndemo run` — runs a 20-line PASS/FAIL smoke covering every lib through the namespace; useful for confirming a working install.
- `/cairndemo gui` — pops a visible window with a clicky button, confirming Cairn-Gui-2.0 + Theme-Default loaded correctly.

CairnDemo also doubles as a reference implementation for new consumers.

## Naming

LibStub MAJORs carry a version suffix. Use `LibStub("Cairn-Addon-1.0")`, `LibStub("Cairn-DB-1.0")`, etc. The Cairn-Gui family is at MAJOR 2.0 — those MAJORs keep their `-2.0` suffix (`Cairn-Gui-2.0`, `Cairn-Gui-Widgets-Standard-2.0`, etc.) since the v2 family was ported rather than rewritten. `Cairn-Callback-1.0` also registers itself under the upstream-compatible `CallbackHandler-1.0` slot.

## License

MIT. See `LICENSE`.

## Distribution

- CurseForge: project 1532175
- Wago: project `b6XemBKp`
- WoWInterface: project 27134
