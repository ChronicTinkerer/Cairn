# Cairn-Media-Browser

A live, in-game browser over everything `Cairn-Media-1.0` has registered. Internal companion to `Cairn-Demo` (non-GUI library showcase) and `Cairn-Gui-Demo-2.0` (widget showcase).

This addon is **internal-only**: not in `.pkgmeta`, not published to CurseForge / Wago / WoWInterface. It's a development tool that lives in the repo for the author's use and ships in source form for anyone who clones the repo.

## What it does

Open with `/cmb` (or `/cairn-media`). A tabbed window opens with one tab per media type:

- **Welcome** — per-type counts (public + private + total), Cairn-Media-1.0 MINOR, theme tie-in note, slash command summary
- **Fonts** — every registered font with name, visibility badge, file path, and live preview at 12 / 16 / 24 pt. Material Symbols icon fonts get a row of registered icon glyphs as their preview text instead of a Latin pangram.
- **Statusbars** — every registered statusbar texture rendered at 80 / 200 / 360 px wide, tinted with the accent blue
- **Borders** — every registered border applied to a 220×60 sample frame via `BackdropTemplate`
- **Backgrounds** — every registered background filling a 220×60 sample panel, untinted
- **Sounds** — every registered sound with a Play button (`PlaySoundFile` on the Master channel)
- **Icons** — Material Symbols glyph grid: font-style picker (Outlined / Rounded / Sharp) + every registered icon name rendered at 36pt with name + Unicode codepoint underneath

Each media-type tab has a visibility filter row (All / Public / Private buttons) above the list.

## Architecture

Mirrors `Cairn-Demo` exactly:

- `Core.lua` — addon shell, lifecycle, slash, tab registry, window construction, shared helpers (`BuildTabShell`, `MakeScrollable`, `AppendIntro`, `BuildVisibilityFilter`)
- `Tabs/<Name>.lua` — one file per tab. Each calls `Browser:RegisterTab(id, def)` at file-scope load. Tabs build lazily on first view via the `TabGroup` `Changed` event.

Built on `Cairn-Gui-2.0` widgets (Window, TabGroup, Container, Button, Label, ScrollFrame). Texture and FontString previews are raw WoW frame children of the row Containers — kept outside the layout flow because Stack only positions Frames, not Textures or FontStrings.

## Slash

| Command | Effect |
|---------|--------|
| `/cmb` | Toggle the window |
| `/cmb show` | Open it |
| `/cmb hide` | Close it |
| `/cairn-media` | Long-form alias |

## Adding a new media type

If `Cairn-Media-1.0` ever grows a new type beyond the current six (font / statusbar / border / background / sound + icon-glyph registry):

1. Add `Tabs/<NewType>.lua` mirroring one of the existing simpler tabs (Sounds is the smallest reference).
2. Add the load line to `Cairn-Media-Browser.toc`.
3. Update the Welcome tab's per-type counts section in `Tabs/Welcome.lua`.

## License

MIT. See `LICENSE`.
