-- tabs/History.lua — Session History browser (Phase 3 Task 3.3)
--
-- Renders a scrollable table of all sessions stored in SavedVariables.
-- Clicking a row makes that session active for all other tabs.
--
-- Columns: # | Boss | Difficulty | Duration | Deaths | Int% | Result

local addonName, CL = ...
local History = {}
CL.History = History

CL.Frame:RegisterTab("history", "History", History)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local ROW_H      = 24
local ACTIVE_CLR = { r = 0.91, g = 0.72, b = 0.10 }  -- gold highlight

local DIFFICULTY_NAMES = {
    [1]  = "Normal",
    [2]  = "Heroic",
    [3]  = "Mythic",
    [8]  = "Mythic+",
    [23] = "Mythic+",
}

local function difficultyLabel(d)
    return DIFFICULTY_NAMES[d] or ("Diff " .. tostring(d))
end

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Column header row
-- ---------------------------------------------------------------------------

local COLS_DUNGEON = {
    { x =   8, w =  28, text = "#"           },
    { x =  40, w = 200, text = "Encounter"   },
    { x = 244, w =  80, text = "Type"        },
    { x = 328, w =  80, text = "Duration"    },
    { x = 412, w =  60, text = "Deaths"      },
    { x = 476, w =  60, text = "Interrupt",  blue = true },
    { x = 540, w =  80, text = "Result"      },
    { x = 624, w = 120, text = "Date"        },
}

local function buildHeader(parent, yOffset)
    local hdrRow = CreateFrame("Frame", nil, parent)
    hdrRow:SetHeight(ROW_H)
    hdrRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    hdrRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    setBg(hdrRow, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    for _, col in ipairs(COLS_DUNGEON) do
        local fs = hdrRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(col.w)
        fs:SetPoint("LEFT", hdrRow, "LEFT", col.x, 0)
        if col.blue then
            fs:SetTextColor(C.blue.r, C.blue.g, C.blue.b)
        else
            fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        end
        fs:SetText(col.text)
    end
    return hdrRow
end

-- ---------------------------------------------------------------------------
-- Session row builder
-- ---------------------------------------------------------------------------

local function buildSessionRow(parent, session, index, yOffset, onSelect, rowButtons)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT")

    -- Background (will be overridden by active highlight)
    local rowBg = setBg(row, 0, 0, 0, 0)
    if index % 2 == 0 then
        rowBg:SetColorTexture(0.06, 0.07, 0.09, 1)
    end

    -- Wipe/kill colour tint
    local resultTint = row:CreateTexture(nil, "BACKGROUND")
    resultTint:SetAllPoints(row)
    if session.success then
        resultTint:SetColorTexture(0.0, 0.15, 0.05, 1)
    else
        resultTint:SetColorTexture(0.15, 0.02, 0.02, 1)
    end

    -- Active highlight border (hidden by default)
    local activeBorder = row:CreateTexture(nil, "OVERLAY")
    activeBorder:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    activeBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    activeBorder:SetWidth(3)
    activeBorder:SetColorTexture(ACTIVE_CLR.r, ACTIVE_CLR.g, ACTIVE_CLR.b, 1)
    activeBorder:Hide()

    -- # (index)
    local idxFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idxFs:SetWidth(28)
    idxFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    idxFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    idxFs:SetText(tostring(index))

    -- Boss name
    local bossFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossFs:SetWidth(200)
    bossFs:SetPoint("LEFT", row, "LEFT", 40, 0)
    bossFs:SetText(session.encounterName or "Unknown")

    -- Difficulty
    local diffFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffFs:SetWidth(80)
    diffFs:SetPoint("LEFT", row, "LEFT", 244, 0)
    diffFs:SetText("|cff6b7a9a" .. difficultyLabel(session.difficulty) .. "|r")

    -- Duration
    local durFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durFs:SetWidth(80)
    durFs:SetPoint("LEFT", row, "LEFT", 328, 0)
    durFs:SetText(CL.Data:FormatDuration(session.durationSec or 0))

    -- Deaths
    local deathCount = #(session.deaths or {})
    local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathFs:SetWidth(60)
    deathFs:SetPoint("LEFT", row, "LEFT", 412, 0)
    if deathCount > 0 then
        deathFs:SetTextColor(0.91, 0.25, 0.25)
        deathFs:SetText(tostring(deathCount))
    else
        deathFs:SetText("|cff40b870✓|r")
    end

    -- Interrupt rate — blue tint, primary M+ metric
    local intRate = (session.interrupts and session.interrupts.summary
        and session.interrupts.summary.ratePercent) or 0
    local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intFs:SetWidth(60)
    intFs:SetPoint("LEFT", row, "LEFT", 476, 0)
    local ir, ig, ib = intRate >= 80 and C.blue.r or C.red.r,
                       intRate >= 80 and C.blue.g or C.red.g,
                       intRate >= 80 and C.blue.b or C.red.b
    intFs:SetTextColor(ir, ig, ib)
    intFs:SetText(string.format("%.0f%%", intRate))

    -- Result badge
    local resultFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultFs:SetWidth(80)
    resultFs:SetPoint("LEFT", row, "LEFT", 540, 0)
    if session.success then
        resultFs:SetText("|cff40e87aSuccess|r")
    else
        resultFs:SetText("|cffe84040Wipe|r")
    end

    -- Date/time
    local dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateFs:SetWidth(120)
    dateFs:SetPoint("LEFT", row, "LEFT", 624, 0)
    dateFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    if session.startTime and session.startTime > 0 then
        dateFs:SetText(date("%m/%d %H:%M", session.startTime))
    end

    -- Click handler: set this as the active session
    row:SetScript("OnClick", function()
        onSelect(index, activeBorder)
    end)

    row:SetScript("OnEnter", function()
        if CL.Data.activeSessionIndex ~= index then
            rowBg:SetColorTexture(0.12, 0.13, 0.18, 1)
        end
    end)
    row:SetScript("OnLeave", function()
        if CL.Data.activeSessionIndex ~= index then
            if index % 2 == 0 then
                rowBg:SetColorTexture(0.06, 0.07, 0.09, 1)
            else
                rowBg:SetColorTexture(0, 0, 0, 0)
            end
        end
    end)

    table.insert(rowButtons, { border = activeBorder, bg = rowBg, idx = index })
    return row
end

-- ---------------------------------------------------------------------------
-- Dungeon run grouping (accordion)
-- ---------------------------------------------------------------------------

-- Which runId is currently expanded (nil = all collapsed).
local expandedRunId = nil

--- Group dungeon sessions by their runId (falls back to one-per-session for
--- old data that pre-dates the runId field).
local function groupByRun(sessions, filteredIndices)
    local runs   = {}
    local runMap = {}
    for listIdx, session in ipairs(sessions) do
        local realIdx = filteredIndices[listIdx]
        local rid = session.runId or ("__solo_" .. realIdx)
        if not runMap[rid] then
            local run = { runId = rid, pulls = {} }
            table.insert(runs, run)
            runMap[rid] = run
        end
        table.insert(runMap[rid].pulls, { session = session, realIdx = realIdx })
    end
    for _, run in ipairs(runs) do
        if #run.pulls > 1 then
            table.sort(run.pulls, function(a, b)
                return (a.session.pullNumber or 0) < (b.session.pullNumber or 0)
            end)
        end
    end
    return runs
end

--- Collapsible header row for a dungeon run (multiple pulls).
local function buildRunHeader(parent, run, yOffset, onToggle)
    local isExpanded = (expandedRunId == run.runId)

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT")

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(0.08, 0.09, 0.13)

    -- Gold left accent
    local strip = row:CreateTexture(nil, "BACKGROUND")
    strip:SetSize(3, ROW_H)
    strip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    strip:SetColorTexture(C.gold.r, C.gold.g, C.gold.b)

    -- Expand arrow (ASCII, font-safe)
    local arrowFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowFs:SetPoint("LEFT", row, "LEFT", 6, 0)
    arrowFs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    arrowFs:SetText(isExpanded and "v" or ">")

    -- Pull count
    local countFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countFs:SetWidth(50)
    countFs:SetPoint("LEFT", row, "LEFT", 20, 0)
    countFs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    countFs:SetFormattedText("%dp", #run.pulls)

    -- Encounter name summary
    local names = {}
    local totalDeaths = 0
    local killCount   = 0
    for _, pull in ipairs(run.pulls) do
        local short = (pull.session.encounterName or "?"):sub(1, 20)
        table.insert(names, short)
        totalDeaths = totalDeaths + #(pull.session.deaths or {})
        if pull.session.success then killCount = killCount + 1 end
    end
    local nameStr = table.concat(names, "  |  ")
    if #nameStr > 55 then nameStr = nameStr:sub(1, 52) .. "..." end

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFs:SetWidth(330)
    nameFs:SetPoint("LEFT", row, "LEFT", 74, 0)
    nameFs:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
    nameFs:SetText(nameStr)

    -- Total deaths
    local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathFs:SetWidth(60)
    deathFs:SetPoint("LEFT", row, "LEFT", 412, 0)
    if totalDeaths > 0 then
        deathFs:SetTextColor(0.91, 0.25, 0.25)
        deathFs:SetFormattedText("%d deaths", totalDeaths)
    else
        deathFs:SetTextColor(0.25, 0.72, 0.47)
        deathFs:SetText("clean")
    end

    -- Kill/total
    local resultFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultFs:SetWidth(80)
    resultFs:SetPoint("LEFT", row, "LEFT", 540, 0)
    if killCount == #run.pulls then
        resultFs:SetFormattedText("|cff40e87a%d/%d killed|r", killCount, #run.pulls)
    else
        resultFs:SetFormattedText("|cffe84040%d/%d killed|r", killCount, #run.pulls)
    end

    -- Date (from first — chronologically earliest — pull in the run)
    local firstPull = run.pulls[1]
    if firstPull and (firstPull.session.startTime or 0) > 0 then
        local dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateFs:SetWidth(120)
        dateFs:SetPoint("LEFT", row, "LEFT", 624, 0)
        dateFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        dateFs:SetText(date("%m/%d %H:%M", firstPull.session.startTime))
    end

    row:SetScript("OnClick",  function() onToggle(run.runId) end)
    row:SetScript("OnEnter",  function() bg:SetColorTexture(0.12, 0.14, 0.20) end)
    row:SetScript("OnLeave",  function() bg:SetColorTexture(0.08, 0.09, 0.13) end)

    return row
end

--- Indented pull sub-row rendered inside an expanded run.
local function buildPullSubRow(parent, pull, yOffset, onSelect, rowButtons)
    local session = pull.session
    local realIdx = pull.realIdx

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT")

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    rowBg:SetColorTexture(0.03, 0.04, 0.06)

    -- Indent gutter (visual indent)
    local gutter = row:CreateTexture(nil, "BACKGROUND")
    gutter:SetSize(12, ROW_H)
    gutter:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    gutter:SetColorTexture(0.06, 0.07, 0.10)

    -- Active border
    local activeBorder = row:CreateTexture(nil, "OVERLAY")
    activeBorder:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
    activeBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    activeBorder:SetWidth(3)
    activeBorder:SetColorTexture(ACTIVE_CLR.r, ACTIVE_CLR.g, ACTIVE_CLR.b)
    activeBorder:Hide()

    -- Pull number
    local idxFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idxFs:SetWidth(26)
    idxFs:SetPoint("LEFT", row, "LEFT", 14, 0)
    idxFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    idxFs:SetText("#" .. (session.pullNumber or "?"))

    -- Encounter name
    local bossFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossFs:SetWidth(200)
    bossFs:SetPoint("LEFT", row, "LEFT", 40, 0)
    bossFs:SetText(session.encounterName or "Unknown")

    -- Type (Boss / Trash)
    local typeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeFs:SetWidth(80)
    typeFs:SetPoint("LEFT", row, "LEFT", 244, 0)
    local pullTypeLabel = (session.pullType == "trash") and "Trash" or "Boss"
    typeFs:SetText("|cff6b7a9a" .. pullTypeLabel .. "|r")

    -- Duration
    local durFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durFs:SetWidth(80)
    durFs:SetPoint("LEFT", row, "LEFT", 328, 0)
    durFs:SetText(CL.Data:FormatDuration(session.durationSec or 0))

    -- Deaths
    local deathCount = #(session.deaths or {})
    local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathFs:SetWidth(60)
    deathFs:SetPoint("LEFT", row, "LEFT", 412, 0)
    if deathCount > 0 then
        deathFs:SetTextColor(0.91, 0.25, 0.25)
        deathFs:SetText(tostring(deathCount))
    else
        deathFs:SetText("|cff40b870--  |r")
    end

    -- Interrupt rate
    local intRate = (session.interrupts and session.interrupts.summary
        and session.interrupts.summary.ratePercent) or 0
    local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intFs:SetWidth(60)
    intFs:SetPoint("LEFT", row, "LEFT", 476, 0)
    local ir, ig, ib = intRate >= 80 and C.blue.r or C.red.r,
                       intRate >= 80 and C.blue.g or C.red.g,
                       intRate >= 80 and C.blue.b or C.red.b
    intFs:SetTextColor(ir, ig, ib)
    intFs:SetText(string.format("%.0f%%", intRate))

    -- Result
    local resultFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resultFs:SetWidth(80)
    resultFs:SetPoint("LEFT", row, "LEFT", 540, 0)
    if session.success then
        resultFs:SetText("|cff40e87aKill|r")
    else
        resultFs:SetText("|cffe84040Wipe|r")
    end

    row:SetScript("OnClick",  function() onSelect(realIdx, activeBorder) end)
    row:SetScript("OnEnter",  function()
        if CL.Data.activeSessionIndex ~= realIdx then
            rowBg:SetColorTexture(0.10, 0.12, 0.17)
        end
    end)
    row:SetScript("OnLeave",  function()
        if CL.Data.activeSessionIndex ~= realIdx then
            rowBg:SetColorTexture(0.03, 0.04, 0.06)
        end
    end)

    table.insert(rowButtons, { border = activeBorder, bg = rowBg, idx = realIdx })
    return row
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function History:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        CL.Frame:ShowEmptyState(
            "No data available.",
            CombatLedgerDB and "No sessions recorded yet." or "Companion app not detected."
        )
        return
    end
    CL.Frame:HideEmptyState()

    local allSessions = CL.Data:GetSessions()
    if #allSessions == 0 then
        CL.Frame:ShowEmptyState("No sessions recorded yet.", "Run a dungeon or raid then /reload.")
        return
    end

    local sessions, filteredIndices = {}, {}
    for i, s in ipairs(allSessions) do
        table.insert(sessions, s)
        table.insert(filteredIndices, i)
    end

    if #sessions == 0 then
        CL.Frame:ShowEmptyState(
            "No M+ sessions recorded yet.",
            "Run a Mythic+ dungeon then /reload."
        )
        return
    end

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Session count banner
    local activeName = (allSessions[CL.Data.activeSessionIndex] or {}).encounterName or "?"
    local banner = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    banner:SetFormattedText(
        "|cffe8a820%d runs|r  |cff6b7a9astored in SavedVariables|r" ..
        "  |cff6b7a9aActive: Pull #%d (%s)|r",
        #sessions, CL.Data.activeSessionIndex, activeName
    )

    local yOffset = -32
    buildHeader(content, yOffset)
    yOffset = yOffset - ROW_H - 2

    -- Row buttons list for highlight management
    local rowButtons = {}

    local function onSelect(realIdx, border)
        -- Remove old highlight
        for _, rb in ipairs(rowButtons) do
            rb.border:Hide()
            if rb.idx % 2 == 0 then
                rb.bg:SetColorTexture(0.06, 0.07, 0.09, 1)
            else
                rb.bg:SetColorTexture(0, 0, 0, 0)
            end
        end
        -- Apply new highlight
        border:Show()
        CL.Data:SetActiveSession(realIdx)
        -- Refresh banner
        banner:SetFormattedText(
            "|cffe8a820%d runs|r  |cff6b7a9astored in SavedVariables|r" ..
            "  |cff6b7a9aActive: Pull #%d (%s)|r",
            #sessions, realIdx,
            (allSessions[realIdx] or {}).encounterName or "?"
        )
    end

    -- Group sessions into runs and show collapsible accordion
    local runs = groupByRun(sessions, filteredIndices)
    for _, run in ipairs(runs) do
        if #run.pulls == 1 then
            -- Single pull — render as a plain session row.
            local pull = run.pulls[1]
            buildSessionRow(content, pull.session, pull.realIdx, yOffset,
                function(_, border) onSelect(pull.realIdx, border) end,
                rowButtons)
            yOffset = yOffset - ROW_H
        else
            -- Multi-pull run: collapsible header.
            buildRunHeader(content, run, yOffset, function(rid)
                expandedRunId = (expandedRunId == rid) and nil or rid
                History:Render(parent)
            end)
            yOffset = yOffset - ROW_H
            if expandedRunId == run.runId then
                for _, pull in ipairs(run.pulls) do
                    buildPullSubRow(content, pull, yOffset,
                        function(rid, border) onSelect(rid, border) end,
                        rowButtons)
                    yOffset = yOffset - ROW_H
                end
            end
        end
    end
    -- Highlight: rb.idx is the absolute session index.
    for _, rb in ipairs(rowButtons) do
        if rb.idx == CL.Data.activeSessionIndex then
            rb.border:Show()
        end
    end

    content:SetHeight(math.abs(yOffset) + 16)
end

function History:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function History:Clear(parent)
    self:Hide(parent)
end
