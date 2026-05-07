--[[
Cairn-Gui-Demo-2.0 / Snippets

Code-snippet strings every tab can quote in its right-hand "code" panel.
Pulled out of the tab files so the tab logic stays focused on rendering
and the snippet text is easy to keep aligned with the visible result.

Each entry is the EXACT Lua a consumer would write to reproduce what the
tab demonstrates on the left. Indentation is tabs (matching the rest of
Cairn). Strings are kept verbatim, no leading/trailing newlines.

Cairn-Gui-Demo-2.0/Snippets (c) 2026 ChronicTinkerer. MIT license.
]]

local CairnGuiDemo = _G.CairnGuiDemo
if not CairnGuiDemo then return end

CairnGuiDemo.Snippets = {

-- ===== Welcome =========================================================

welcome = [[
-- Cairn-Gui-2.0 is a widget library; this addon is the demo.
-- Each tab in this window demonstrates a single capability.
--
-- The whole library is one LibStub MAJOR per architecture Decision 11:
--
local Gui = LibStub("Cairn-Gui-2.0")
local Std = LibStub("Cairn-Gui-Widgets-Standard-2.0")
--
-- Open this window any time with: /cgdemo
]],

-- ===== Buttons =========================================================

buttons = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Four built-in variants. Acquire takes (typeName, parent, opts).
local primary = Gui:Acquire("Button", parent, {
    text    = "Save",
    variant = "primary",
})
local danger  = Gui:Acquire("Button", parent, {
    text    = "Delete",
    variant = "danger",
})

-- Multi-subscriber click. Each handler runs; xpcall isolates errors.
primary.Cairn:On("Click", function(w, mouseButton)
    print("primary clicked:", mouseButton)
end)

-- Disabled is a state, not a separate variant. The state machine
-- repaints automatically.
danger.Cairn:SetEnabled(false)
]],

-- ===== Inputs ==========================================================

inputs = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Text input with placeholder + focus ring + multi-subscriber events.
local eb = Gui:Acquire("EditBox", parent, {
    placeholder = "Type something...",
    width       = 200,
})
eb.Cairn:On("TextChanged", function(w, text)  -- multi-subscriber
    valueLabel.Cairn:SetText("Text: " .. text)
end)

-- Numeric range with optional readout.
local sl = Gui:Acquire("Slider", parent, {
    min = 0, max = 100, value = 25, step = 1,
    showValue = true,
})
sl.Cairn:On("Changed", function(w, v) ... end)

-- Boolean toggle. Both Click and Toggled events fire.
local cb = Gui:Acquire("Checkbox", parent, {
    text    = "Enable feature",
    checked = false,
})

-- Single-select dropdown with scrollable popup.
local dd = Gui:Acquire("Dropdown", parent, {
    options = {
        { value = "small",  label = "Small"  },
        { value = "medium", label = "Medium" },
        { value = "large",  label = "Large"  },
    },
    selected = "medium",
})
]],

-- ===== Containers ======================================================

containers = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Window: top-level draggable container with a title bar.
local win = Gui:Acquire("Window", UIParent, {
    title    = "Hello",
    width    = 320,
    height   = 200,
    closable = true,
})
local body = win.Cairn:GetContent()
body.Cairn:SetLayout("Stack", { direction = "vertical", gap = 4, padding = 8 })

-- ScrollFrame: viewport + scroll child. SetLayout on .GetContent(), not
-- on the scroll frame itself.
local sf = Gui:Acquire("ScrollFrame", body, {
    width = 280, height = 100, contentHeight = 600,
})
sf.Cairn:GetContent().Cairn:SetLayout("Stack",
    { direction = "vertical", gap = 4, padding = 4 })
for i = 1, 30 do
    Gui:Acquire("Label", sf.Cairn:GetContent(), { text = "Row " .. i })
end

-- TabGroup: tab buttons + per-tab content panes. GetTabContent(id)
-- returns the pane Container you can populate.
local tg = Gui:Acquire("TabGroup", body, {
    tabs = { { id = "a", label = "A" }, { id = "b", label = "B" } },
})
]],

-- ===== Layouts =========================================================

layouts = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Layouts are STRATEGIES registered against a string name. Six built-ins
-- ship in Core: Manual, Fill, Stack, Grid, Form, Flex.

container.Cairn:SetLayout("Stack", {
    direction = "vertical",   -- or "horizontal"
    gap       = 4,
    padding   = 8,
})

container.Cairn:SetLayout("Grid", {
    columns = 3,
    rowGap  = 4,
    colGap  = 4,
    padding = 8,
})

container.Cairn:SetLayout("Form", {
    -- Children come in (label, field) pairs.
    rowGap = 6, colGap = 8, padding = 8,
})

container.Cairn:SetLayout("Flex", {
    direction = "row",        -- or "column"
    justify   = "between",    -- start | end | center | between | around | evenly
    align     = "stretch",
    gap       = 4,
    padding   = 8,
})

-- Per-child opts read off the cairn:
child.Cairn._flexGrow  = 1     -- distribute leftover main-axis space
child.Cairn._flexBasis = 80    -- override initial main-axis size

-- Custom strategies register through the SAME public API:
Gui:RegisterLayout("Hex", function(container, opts) ... end)
]],

-- ===== Layouts Extra ===================================================

layoutsextra = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- The Cairn-Gui-Layouts-Extra-2.0 bundle registers layouts the same way
-- the Core ones do; you just have to load the bundle.
LibStub("Cairn-Gui-Layouts-Extra-2.0")

container.Cairn:SetLayout("Hex", {
    columns     = 4,
    cellSize    = 28,
    orientation = "pointy",   -- or "flat"
    gap         = 2,
    padding     = 4,
})

container.Cairn:SetLayout("Polar", {
    radius     = 70,
    startAngle = 90,           -- 0=right, 90=top, 180=left, 270=bottom
    direction  = "ccw",        -- or "cw"
    cellSize   = 24,
})
]],

-- ===== Themes ==========================================================

themes = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Register a theme. `extends` chains to a parent theme; tokens override
-- only what the child specifies.
Gui:RegisterTheme("Demo.Vivid", {
    extends = "Cairn.Default",
    tokens  = {
        ["color.accent.primary"]    = {0.95, 0.45, 0.20, 1.00},
        ["color.bg.button.primary"] = {0.92, 0.40, 0.15, 1.00},
        ["color.bg.panel"]          = {0.04, 0.04, 0.06, 0.98},
    },
})

-- Active theme. Cascade walks: instance override -> nearest ancestor
-- SetTheme -> active global -> extends chain -> library defaults.
Gui:SetActiveTheme("Demo.Vivid")

-- Per-instance override. Wins over everything.
btn.Cairn:SetTokenOverride("color.accent.primary", {0.20, 0.80, 0.40, 1})

-- Per-subtree theme bound to a container.
window.Cairn:SetTheme("Demo.Vivid")

-- Repaint isn't automatic in v1; call Repaint() to re-resolve and apply.
btn.Cairn:Repaint()
]],

-- ===== Primitives ======================================================

primitives = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Six drawing primitives. Each one accepts a token name, a literal
-- value, or a state-variant table.

widget.Cairn:DrawRect("bg",     "color.bg.panel")
widget.Cairn:DrawBorder("frame", "color.border.default", { width = 1 })
widget.Cairn:DrawIcon("leading", "icon.check", {
    size   = 16,
    anchor = "LEFT",
    offsetX = 4,
    color  = "color.accent.primary",
})
widget.Cairn:DrawDivider("hr", "color.border.subtle", {
    orientation = "horizontal", thickness = 1,
})
widget.Cairn:DrawGlow("halo", "color.accent.primary", { spread = 6 })
widget.Cairn:DrawMask("clip", { shape = "rounded", radius = 8 })

-- State variants drive automatic transitions when paired with a
-- `transition` token (the Animation engine reads it):
widget.Cairn:DrawRect("bg", {
    default    = "color.bg.button",
    hover      = "color.bg.button.hover",
    pressed    = "color.bg.button.pressed",
    disabled   = "color.bg.button.disabled",
    transition = "duration.fast",
})
]],

-- ===== Animations ======================================================

animations = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Declarative single call: tween multiple properties together.
btn.Cairn:Animate({
    alpha = { to = 0.5,  dur = 0.25, ease = "easeOut" },
    scale = { to = 1.10, dur = 0.25 },
})

-- Spring physics: opt in via the spring sub-table.
btn.Cairn:Animate({
    scale = {
        to     = 1.20,
        spring = { stiffness = 220, damping = 18, mass = 1 },
    },
})

-- Compositions
btn.Cairn:Sequence({
    { alpha = { to = 0.0, dur = 0.15 } },
    { alpha = { to = 1.0, dur = 0.30 } },
})
btn.Cairn:Parallel({
    { alpha = { to = 0.4, dur = 0.20 } },
    { scale = { to = 1.05, dur = 0.20 } },
})
btn.Cairn:Stagger(steps, 0.08)

-- Imperative shortcut for the single-property case.
btn.Cairn:Tween("alpha", 1.0, { dur = 0.2 })

-- Custom easing.
Gui:RegisterEasing("easeOutQuint", function(t)
    local f = 1 - t
    return 1 - f * f * f * f * f
end)

-- Accessibility: ReduceMotion clamps every duration to zero.
Gui.ReduceMotion = true
]],

-- ===== Events ==========================================================

events = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Multi-subscriber by default. Each handler runs.
btn.Cairn:On("Click", handlerA)
btn.Cairn:On("Click", handlerB, "myplugin")    -- tagged for bulk detach
btn.Cairn:Once("Click", handlerC)              -- auto-detach after first

-- Detach by reference, by event, by tag, or all-at-once:
btn.Cairn:Off("Click", handlerA)
btn.Cairn:Off("Click")
btn.Cairn:OffByTag("myplugin")
btn.Cairn:Off()                                 -- nuke everything

-- Native Blizzard frame events stay accessible via SetScript /
-- HookScript on the underlying frame; no Cairn wrapping.
btn:HookScript("OnUpdate", function(self_, dt) ... end)

-- Re-fire an event from one widget on another.
btn.Cairn:Forward("Click", otherWidget)
]],

-- ===== L10n ============================================================

l10n = [[
local Locale = LibStub("Cairn-Locale-1.0")
local Gui    = LibStub("Cairn-Gui-2.0")

-- Register a locale namespace.
Locale.New("MyAddon", {
    enUS = { greeting = "Hello!", save = "Save" },
    deDE = { greeting = "Hallo!", save = "Speichern" },
}, { default = "enUS" })

-- Widget text setters resolve "@namespace:key" via Cairn-Locale lazily,
-- so a locale switch reflects on next read.
btn.Cairn:SetText("@MyAddon:save")
lbl.Cairn:SetText("@MyAddon:greeting")

-- Unknown namespace, malformed prefix, or missing key all fall through
-- to the literal string.
btn.Cairn:SetText("@MyAddon:nonexistent")  -- displays the literal

-- Library's own dev-mode strings live under @Cairn-Gui:; community
-- translators add overlays via:
Gui:RegisterLocaleOverlay("deDE", {
    ["error.combat"] = "Im Kampf nicht moeglich",
})
]],

-- ===== Inspector =======================================================

inspector = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- Per-widget dump (state snapshot, no children, no frame ref).
local snap = btn.Cairn:Dump()
-- snap = { type, parentType, childCount, shown, strata, level, rect,
--          intrinsic, hasCallbacks, hasLayout, manualLayout }

-- Walk a tree depth-first. Return false from fn to stop early.
Gui.Inspector:Walk(window.Cairn, function(c, depth)
    print(string.rep("  ", depth), c._type)
end)

-- Hit-test by screen coords.
local hit = Gui.Inspector:Find(GetCursorPosition())

-- First widget by registered type name.
local firstButton = Gui.Inspector:SelectByName("Button")

-- Library-wide stats: anim count, layout recomputes, primitive draws,
-- event dispatches, pool occupancy, event log capacity.
local s = Gui.Stats:Snapshot()

-- Event log (off by default; flip Cairn.Dev or call Enable() to start).
Gui.EventLog:Enable()
local recent = Gui.EventLog:Tail(20)
]],

-- ===== Secure ==========================================================

secure = [[
local Gui = LibStub("Cairn-Gui-2.0")
LibStub("Cairn-Gui-Widgets-Secure-2.0")

-- ActionButton: spell / item / macro / macrotext.
local btn = Gui:Acquire("ActionButton", parent, {
    type  = "spell",
    spell = "Fireball",
    unit  = "target",
    width = 36, height = 36,
})

-- Typed wrappers route through the combat queue so you CAN call them
-- mid-combat. The change applies on PLAYER_REGEN_ENABLED drain.
btn.Cairn:SetSpell("Frostbolt")
btn.Cairn:SetMacroText("/cast [@target] Heal")

-- MacroButton: focused subset.
local mb = Gui:Acquire("MacroButton", parent, {
    macrotext = "/cast Mount Up",
    text      = "Mount",
})

-- UnitButton: target / focus / menu click bindings.
local ub = Gui:Acquire("UnitButton", parent, { unit = "player" })
ub.Cairn:SetClickAction("LeftButton",  "target")
ub.Cairn:SetClickAction("RightButton", "menu")

-- Combat status / fake combat for testing without an actual fight:
Gui.Combat:InCombat()                -- bool
Gui.Combat:SetFakeCombat(true)        -- forces InCombat() true
local stats = Gui.Combat:Stats()      -- {queued, drained, lockdownFailures, depth}
]],

-- ===== Contracts =======================================================

contracts = [[
local Gui = LibStub("Cairn-Gui-2.0")

-- One-shot health check across every registered piece. Returns:
-- { widgets={ok,warn={...}}, layouts={...}, themes={...}, easings={...} }
local result = Gui:RunContracts()

-- Validate a single registration before passing it in:
local ok, err = Gui:ValidateWidget("MyButton", {
    frameType = "Button",
    mixin     = { OnAcquire = function() end },
    pool      = true,
    reset     = function(c) end,
})
local ok, err = Gui:ValidateLayout("MyLayout", function(container, opts) end)
local ok, err = Gui:ValidateTheme("MyTheme", { tokens = { ... } })

-- Validators are GENTLE: warnings flow through Cairn-Log when present;
-- failures don't unregister. Run from a Forge tab or a release CI step.
]],

}
