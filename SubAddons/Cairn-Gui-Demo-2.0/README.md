# Cairn-Gui-Demo-2.0

Live, browseable showcase of every Cairn-Gui-2.0 feature. Author-facing
reference: each tab renders a single capability on the left and quotes
the exact Lua you'd write to reproduce it on the right.

This is a separate WoW addon, not a piece of the Cairn library. It depends
on Cairn but no other addon depends on it. Disable it whenever you want;
the library still works.

## Open it

In WoW: `/cgdemo`

(or the long form `/cairn-gui-demo`)

## What's in each tab

- **Welcome** — version info, list of loaded bundles, tab guide.
- **Buttons** — four variants, disabled state, click counter, intrinsic sizing.
- **Inputs** — EditBox, Slider, Checkbox, Dropdown, Label variants.
- **Containers** — secondary Window pop-up, ScrollFrame, nested TabGroup.
- **Layouts** — Manual, Fill, Stack, Grid, Form, Flex side-by-side.
- **Layouts Extra** — Hex + Polar (optional `Cairn-Gui-Layouts-Extra-2.0` bundle).
- **Themes** — live theme picker, subtree theme, per-instance overrides.
- **Primitives** — Rect, Border, Icon, Divider, Glow, Mask + state variants.
- **Animations** — Animate, Sequence, Parallel, Stagger, Spring + ReduceMotion.
- **Events** — multi-subscriber, tags, Once, Forward.
- **L10n** — `@namespace:key` resolution + live locale switcher.
- **Inspector** — Stats snapshot, EventLog tail, tree walk over this tab.
- **Secure** — ActionButton, MacroButton, UnitButton + fake-combat toggle.
- **Contracts** — `RunContracts()` one-shot validator pass.

## Tab files

Tabs are independent. Adding a new tab is one new file under `Tabs/` plus
one entry in `Cairn-Gui-Demo-2.0.toc`. The tab calls `CairnGuiDemo:RegisterTab(id, def)`
at file-scope load; `Core.lua` builds the TabGroup from whatever was
registered, in `def.order` order.

```lua
Demo:RegisterTab("buttons", {
    label = "Buttons",
    order = 10,
    build = function(pane, demo)
        local _, live = demo:BuildTabShell(pane, headingText, snippetText)
        -- populate `live` (a Cairn Container) freely
    end,
})
```

`Demo:BuildTabShell(pane, heading, code)` lays down the standard heading
+ live panel + scrollable code panel and returns `heading, live, codeLabel`.
Most tabs only need `live`.

## Dependencies

- **Cairn** (required) — provides `Cairn-Gui-2.0` Core, the Standard widget
  bundle, the default theme, and Cairn-Locale-1.0.
- `Cairn-Gui-Widgets-Secure-2.0` — optional; the Secure tab degrades to a
  notice if absent.
- `Cairn-Gui-Layouts-Extra-2.0` — optional; the Layouts Extra tab degrades
  to a notice if absent.

## License

MIT. Same as the Cairn library it demonstrates.
