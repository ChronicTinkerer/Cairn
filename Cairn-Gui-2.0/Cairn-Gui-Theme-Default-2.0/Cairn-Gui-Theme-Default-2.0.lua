--[[
Cairn-Gui-Theme-Default-2.0

The default theme for Cairn-Gui-2.0. Modern dark surfaces with a blue
accent, designed to look at home in 2026 rather than 2010. The whole
palette is registered as theme name "Cairn.Default" and set as the
active theme on load. Consumers can switch via:

	LibStub("Cairn-Gui-2.0"):SetActiveTheme(otherName)

The bundle's MAJOR matches the Core MAJOR it targets (2.0). Earlier the
bundle was named Cairn-Gui-Theme-Default-1.0, which created confusion
because it suggested the v1 family even though the LibStub call inside
asked for v2 Core.

Per Decision 11, this bundle is its own LibStub MAJOR. Consumers who
want a different visual language can replace this bundle with one of
their own (e.g., Cairn.Light, MyAddon.Cyberpunk) without modifying Core
or any Standard widgets. The widgets resolve tokens through the cascade
and pick up whatever theme the consumer activated.

Token namespace coverage (per architecture Decision 5: category.scope.role):

	color.bg.{panel, surface}
	color.bg.button[.{primary, danger, ghost}][.{hover, pressed, disabled}]
	color.fg.text[.{muted, disabled, on_accent, danger}]
	color.border.{default, subtle, focus, accent, danger}
	color.accent.{primary[.hover], danger, success, warning, info}
	length.padding.{xs, sm, md, lg, xl}
	length.gap.{xs, sm, md, lg}
	font.{body, heading, small}
	duration.{fast, normal, slow}

Tokens not registered here fall through to the library hardcoded
defaults in Cairn-Gui-2.0/Core/Theme.lua DEFAULTS table.
]]

-- History under previous MAJOR (Cairn-Gui-Theme-Default-1.0):
--   1: initial dark theme (Days 1-13).
--   2: Day 14: texture.icon.check token registered for Checkbox.
--
-- Cairn-Gui-Theme-Default-2.0 MINOR bumps:
--   1: MAJOR rename only. No token / API changes from 1.0/MINOR=2.
local MAJOR, MINOR = "Cairn-Gui-Theme-Default-2.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local Core = LibStub("Cairn-Gui-2.0", true)
if not Core then
	error("Cairn-Gui-Theme-Default-2.0 requires Cairn-Gui-2.0; check Cairn.toc load order")
end

if not Core:RequireCore("Cairn-Gui-2.0", 1) then
	return
end

-- ----- The theme -------------------------------------------------------

Core:RegisterTheme("Cairn.Default", {
	tokens = {
		-- ====== Surfaces (panel, surface, button) =====================

		-- Panel: the canvas color for top-level windows. Slight transparency
		-- to let very subtle environmental tone through without being noisy.
		["color.bg.panel"]                  = {0.06, 0.06, 0.07, 0.97},
		-- Surface: a raised area within a panel (cards, sections).
		["color.bg.surface"]                = {0.10, 0.10, 0.12, 1.00},

		-- Buttons (neutral). Default flat surface, slight lift on hover,
		-- darken on press, faded on disabled.
		["color.bg.button"]                 = {0.13, 0.13, 0.16, 1.00},
		["color.bg.button.hover"]           = {0.18, 0.18, 0.22, 1.00},
		["color.bg.button.pressed"]         = {0.08, 0.08, 0.10, 1.00},
		["color.bg.button.disabled"]        = {0.10, 0.10, 0.12, 0.50},

		-- Buttons (primary). The accent color, signaling the recommended action.
		["color.bg.button.primary"]          = {0.30, 0.55, 0.95, 1.00},
		["color.bg.button.primary.hover"]    = {0.35, 0.62, 1.00, 1.00},
		["color.bg.button.primary.pressed"]  = {0.22, 0.45, 0.80, 1.00},
		["color.bg.button.primary.disabled"] = {0.30, 0.40, 0.55, 0.50},

		-- Buttons (danger). For destructive actions.
		["color.bg.button.danger"]           = {0.82, 0.30, 0.30, 1.00},
		["color.bg.button.danger.hover"]     = {0.92, 0.36, 0.36, 1.00},
		["color.bg.button.danger.pressed"]   = {0.65, 0.22, 0.22, 1.00},
		["color.bg.button.danger.disabled"]  = {0.55, 0.30, 0.30, 0.50},

		-- Buttons (ghost). Transparent until interacted with; a low-emphasis
		-- variant for secondary actions or icon buttons.
		["color.bg.button.ghost"]            = {0.00, 0.00, 0.00, 0.00},
		["color.bg.button.ghost.hover"]      = {1.00, 1.00, 1.00, 0.06},
		["color.bg.button.ghost.pressed"]    = {1.00, 1.00, 1.00, 0.12},
		["color.bg.button.ghost.disabled"]   = {0.00, 0.00, 0.00, 0.00},

		-- ====== Foregrounds (text colors) =============================

		["color.fg.text"]                    = {0.94, 0.94, 0.96, 1.00},
		["color.fg.text.muted"]              = {0.60, 0.60, 0.65, 1.00},
		["color.fg.text.disabled"]           = {0.40, 0.40, 0.45, 1.00},
		["color.fg.text.on_accent"]          = {1.00, 1.00, 1.00, 1.00},
		["color.fg.text.danger"]             = {0.95, 0.42, 0.42, 1.00},
		["color.fg.text.success"]            = {0.40, 0.85, 0.55, 1.00},
		["color.fg.text.warning"]            = {0.95, 0.75, 0.30, 1.00},

		-- ====== Borders ===============================================

		["color.border.default"]             = {0.20, 0.20, 0.25, 1.00},
		["color.border.subtle"]              = {0.14, 0.14, 0.17, 1.00},
		["color.border.focus"]               = {0.30, 0.55, 0.95, 1.00},
		["color.border.accent"]              = {0.30, 0.55, 0.95, 0.60},
		["color.border.danger"]              = {0.82, 0.30, 0.30, 0.60},

		-- ====== Accent palette (semantic) =============================
		-- Use these directly for icons, glyphs, focus rings, status pips.
		-- Buttons in the .primary / .danger variants resolve through their
		-- own bg tokens, not these directly.

		["color.accent.primary"]             = {0.30, 0.55, 0.95, 1.00},
		["color.accent.primary.hover"]       = {0.35, 0.62, 1.00, 1.00},
		["color.accent.danger"]              = {0.82, 0.30, 0.30, 1.00},
		["color.accent.success"]             = {0.30, 0.78, 0.52, 1.00},
		["color.accent.warning"]             = {0.95, 0.70, 0.22, 1.00},
		["color.accent.info"]                = {0.40, 0.70, 0.95, 1.00},

		-- ====== Spacing scale =========================================
		-- Padding and gap are independent: padding is a container's inset,
		-- gap is between siblings inside a layout strategy.

		["length.padding.xs"]                = 2,
		["length.padding.sm"]                = 4,
		["length.padding.md"]                = 8,
		["length.padding.lg"]                = 12,
		["length.padding.xl"]                = 16,

		["length.gap.xs"]                    = 2,
		["length.gap.sm"]                    = 4,
		["length.gap.md"]                    = 8,
		["length.gap.lg"]                    = 12,

		-- ====== Fonts =================================================

		["font.body"]                        = { face = STANDARD_TEXT_FONT, size = 12, flags = "" },
		["font.heading"]                     = { face = STANDARD_TEXT_FONT, size = 16, flags = "" },
		["font.small"]                       = { face = STANDARD_TEXT_FONT, size = 10, flags = "" },

		-- ====== Animation durations ===================================
		-- Slightly snappier than Core defaults so transitions feel modern
		-- rather than slow.

		["duration.fast"]                    = 0.12,
		["duration.normal"]                  = 0.20,
		["duration.slow"]                    = 0.35,

		-- ====== Textures ==============================================
		-- Atlas keys preferred. DrawIcon tries C_Texture.GetAtlasInfo
		-- first, falls back to SetTexture for file paths. The check atlas
		-- is a clean white glyph on transparent, suitable for tinting via
		-- color.accent.primary or a state-variant color spec.

		["texture.icon.check"]               = "common-icon-checkmark",
	},
})

-- Make Cairn.Default the active theme on load. Consumers can switch via
-- Core:SetActiveTheme(name) at any time; that call triggers no walk yet
-- (lazy repaint queue is a Decision-5 follow-up), so consumers who switch
-- after widgets are already drawn must call Repaint on the affected
-- widgets themselves.
Core:SetActiveTheme("Cairn.Default")

lib._registered = true
