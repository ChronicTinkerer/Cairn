-- CairnDemo_SmokeRunner
-- A Cairn-Gui-2.0 window that runs every smoke registered under
-- `_G.CairnDemo.Smokes` and renders PASS/FAIL results in a scrollable
-- container. One Label per result, colored by outcome (success / danger),
-- with a header label per smoke. The "Run All" button drives execution;
-- the "Clear" button drops result rows back into their pool.
--
-- Smokes register themselves at addon-load time by populating
-- `_G.CairnDemo.Smokes[<name>] = function(report) ... end`. Each smoke
-- calls `report(label, ok, detailOrNil)` per assertion. The runner
-- supplies the report closure and tallies totals.
--
-- Reachable via:
--     /cairndemo smokes
--
-- Cairn-Gui-2.0 is loaded via LibStub because the Gui lib is at -2.0 and
-- therefore not in the -1.0 `_G.Cairn.*` namespace. See memory note
-- `cairn_v1_majors_and_umbrella.md`.

-- Module-scope state lives across reopens so we don't rebuild the window
-- from scratch and so the result Labels stay in the Cairn-Gui widget pool.
-- _rowHeights mirrors _rows so we can size the ScrollFrame's content area
-- without poking at widget internals.
local _win, _scrollFrame, _scrollContent, _summary
local _rows, _rowHeights = {}, {}

-- Row dimensions. Tuned so a typical PASS label fits on one line at the
-- default Cairn body font. Heading rows are slightly taller to set them
-- apart visually.
local ROW_WIDTH      = 560
local ROW_HEIGHT     = 16
local HEADING_HEIGHT = 20
local CONTENT_PAD    = 8

-- Drop every result row back into its pool. Window + header + scrollframe
-- stay alive across runs.
local function clearRows()
    for i = 1, #_rows do
        local w = _rows[i]
        -- Pooled widgets expose Release on the .Cairn side, not the frame.
        if w and w.Cairn and w.Cairn.Release then w.Cairn:Release() end
    end
    _rows, _rowHeights = {}, {}
    if _summary and _summary.Cairn then _summary.Cairn:SetText("no runs yet") end
    if _scrollFrame and _scrollFrame.Cairn then _scrollFrame.Cairn:SetContentHeight(0) end
end

-- Walk every registered smoke in alphabetical order and run it under a
-- `report` callback that materializes one Label per assertion. pcall-
-- wrapped so a smoke that throws doesn't poison the rest of the run.
local function runAll(Gui)
    clearRows()

    local pass, fail, errors = 0, 0, 0

    local names = {}
    for name in pairs(_G.CairnDemo.Smokes or {}) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        -- Per-smoke heading row. Variant=heading uses the heading font;
        -- color stays the default fg.text so the contrast comes from size.
        local h = Gui:Acquire("Label", _scrollContent, {
            text    = "==  " .. name,
            width   = ROW_WIDTH,
            height  = HEADING_HEIGHT,
            variant = "heading",
            align   = "left",
        })
        _rows[#_rows + 1] = h
        _rowHeights[#_rowHeights + 1] = HEADING_HEIGHT

        local function report(label, ok, detail)
            local text
            if ok then
                pass = pass + 1
                text = "    [PASS]  " .. tostring(label)
            else
                fail = fail + 1
                text = "    [FAIL]  " .. tostring(label)
                if detail ~= nil and detail ~= "" then
                    text = text .. "    -- " .. tostring(detail)
                end
            end
            local row = Gui:Acquire("Label", _scrollContent, {
                text    = text,
                width   = ROW_WIDTH,
                height  = ROW_HEIGHT,
                variant = ok and "success" or "danger",
                align   = "left",
            })
            _rows[#_rows + 1] = row
            _rowHeights[#_rowHeights + 1] = ROW_HEIGHT
        end

        local okCall, errCall = pcall(_G.CairnDemo.Smokes[name], report)
        if not okCall then
            -- Smoke threw before completing. Surface the error inline so
            -- it's visible in context with that smoke's other rows.
            errors = errors + 1
            local errRow = Gui:Acquire("Label", _scrollContent, {
                text    = "    [ERROR]  smoke threw: " .. tostring(errCall),
                width   = ROW_WIDTH,
                height  = ROW_HEIGHT,
                variant = "danger",
                align   = "left",
            })
            _rows[#_rows + 1] = errRow
            _rowHeights[#_rowHeights + 1] = ROW_HEIGHT
        end
    end

    -- Update the summary line. We count errors separately from FAILs so
    -- "everything threw" is visually distinct from "asserts failed".
    if _summary and _summary.Cairn then
        if errors == 0 then
            _summary.Cairn:SetText(("%d PASS / %d FAIL across %d smokes"):format(pass, fail, #names))
        else
            _summary.Cairn:SetText(("%d PASS / %d FAIL / %d ERR across %d smokes"):format(pass, fail, errors, #names))
        end
    end

    -- Scrollable content height = padding + sum of row heights. The
    -- Stack layout's gap (0) doesn't add anything between rows, so the
    -- sum is the tight bound the scrollbar uses to size its thumb.
    local h = CONTENT_PAD * 2
    for i = 1, #_rowHeights do h = h + _rowHeights[i] end
    if _scrollFrame and _scrollFrame.Cairn then
        _scrollFrame.Cairn:SetContentHeight(h)
        _scrollFrame.Cairn:ScrollToTop()
    end
end

-- Build the window on first call; subsequent calls just :Show() it.
local function openSmokeRunner()
    local Gui = LibStub and LibStub("Cairn-Gui-2.0", true)
    if not Gui then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[CairnDemo]|r Cairn-Gui-2.0 not loaded; cannot open smoke runner")
        return
    end

    if _win then _win:Show(); return _win end

    _win = Gui:Acquire("Window", UIParent, {
        title    = "Cairn Smoke Runner",
        width    = 620,
        height   = 480,
        closable = true,
        movable  = true,
    })
    _win:SetPoint("CENTER")

    local content = _win.Cairn:GetContent()
    content.Cairn:SetLayout("Stack", { direction = "vertical", gap = 6, padding = 8 })

    -- Header row: action buttons + summary
    local headerRow = Gui:Acquire("Container", content, { width = ROW_WIDTH + 20, height = 28 })
    headerRow.Cairn:SetLayout("Stack", { direction = "horizontal", gap = 8 })

    local runBtn = Gui:Acquire("Button", headerRow, { text = "Run All", width = 100, height = 24 })
    local clearBtn = Gui:Acquire("Button", headerRow, { text = "Clear",   width = 80,  height = 24 })

    _summary = Gui:Acquire("Label", headerRow, {
        text    = "no runs yet",
        width   = 380,
        height  = 24,
        variant = "muted",
        align   = "left",
    })

    -- Result list. The ScrollFrame is a viewport; layout goes on its
    -- content container, not on the ScrollFrame itself.
    _scrollFrame = Gui:Acquire("ScrollFrame", content, {
        width         = ROW_WIDTH + 20,
        height        = 400,
        bg            = "color.bg.surface",
        border        = "color.border.default",
        borderWidth   = 1,
        showScrollbar = true,
    })
    _scrollContent = _scrollFrame.Cairn:GetContent()
    _scrollContent.Cairn:SetLayout("Stack", { direction = "vertical", gap = 0, padding = CONTENT_PAD })

    runBtn.Cairn:On("Click",   function() runAll(Gui) end)
    clearBtn.Cairn:On("Click", clearRows)

    return _win
end

-- Expose for the slash sub-command to call.
_G.CairnDemo                  = _G.CairnDemo or {}
_G.CairnDemo.OpenSmokeRunner  = openSmokeRunner
