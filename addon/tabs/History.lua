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

-- Raid columns: pull-number and boss-centric language.
local COLS_RAID = {
    { x =   8, w =  28, text = "#"          },
    { x =  40, w = 200, text = "Boss"       },
    { x = 244, w =  80, text = "Difficulty" },
    { x = 328, w =  80, text = "Duration"   },
    { x = 412, w =  60, text = "Deaths"     },
    { x = 476, w =  60, text = "Int %"      },
    { x = 540, w =  80, text = "Result"     },
    { x = 624, w = 120, text = "Date"       },
}

-- Dungeon columns: run-number and dungeon-centric language.
-- "Int %" is labeled "Interrupt" and displayed with a blue tint to signal its importance.
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

local function buildHeader(parent, yOffset, isDungeon)
    local hdrRow = CreateFrame("Frame", nil, parent)
    hdrRow:SetHeight(ROW_H)
    hdrRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    hdrRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    setBg(hdrRow, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    local cols = isDungeon and COLS_DUNGEON or COLS_RAID
    for _, col in ipairs(cols) do
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

local function buildSessionRow(parent, session, index, yOffset, onSelect, rowButtons, isDungeon)
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

    -- Interrupt rate — blue tint in dungeon mode (most critical M+ metric)
    local intRate = (session.interrupts and session.interrupts.summary
        and session.interrupts.summary.ratePercent) or 0
    local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intFs:SetWidth(60)
    intFs:SetPoint("LEFT", row, "LEFT", 476, 0)
    if isDungeon then
        local ir, ig, ib = intRate >= 80 and C.blue.r or C.red.r,
                           intRate >= 80 and C.blue.g or C.red.g,
                           intRate >= 80 and C.blue.b or C.red.b
        intFs:SetTextColor(ir, ig, ib)
    else
        local ir, ig, ib = intRate >= 80 and 0.25 or 0.91, intRate >= 80 and 0.72 or 0.45, 0.25
        intFs:SetTextColor(ir, ig, ib)
    end
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

    -- Filter to sessions matching the current view mode.
    local isDungeon = CL.Config:GetViewMode() == "dungeon"
    local sessions, filteredIndices = {}, {}
    for i, s in ipairs(allSessions) do
        if CL.Config:SessionMatchesMode(s) then
            table.insert(sessions, s)
            table.insert(filteredIndices, i)
        end
    end

    local modeLabel = isDungeon and "dungeon runs" or "raid sessions"
    if #sessions == 0 then
        CL.Frame:ShowEmptyState(
            string.format("No %s recorded yet.", modeLabel),
            isDungeon and "Run a Mythic+ or dungeon then /reload."
                       or "Complete a raid encounter then /reload."
        )
        return
    end

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Session count banner
    local runWord = isDungeon and "runs" or "sessions"
    local pullWord = isDungeon and "Run" or "Pull"
    local activeName = (allSessions[CL.Data.activeSessionIndex] or {}).encounterName or "?"
    local banner = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    banner:SetFormattedText(
        "|cffe8a820%d %s|r  |cff6b7a9astored in SavedVariables|r" ..
        "  |cff6b7a9aActive: %s #%d (%s)|r",
        #sessions, runWord, pullWord, CL.Data.activeSessionIndex, activeName
    )

    local yOffset = -32
    buildHeader(content, yOffset, isDungeon)
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
            "|cffe8a820%d %s|r  |cff6b7a9astored in SavedVariables|r" ..
            "  |cff6b7a9aActive: %s #%d (%s)|r",
            #sessions, runWord, pullWord, realIdx,
            (allSessions[realIdx] or {}).encounterName or "?"
        )
    end

    for listIdx, session in ipairs(sessions) do
        local realIdx = filteredIndices[listIdx]
        buildSessionRow(content, session, listIdx, yOffset,
            function(_, border) onSelect(realIdx, border) end,
            rowButtons, isDungeon)
        yOffset = yOffset - ROW_H
    end

    -- Highlight currently active session (rb.idx is the display/list position;
    -- filteredIndices maps it back to the real session index).
    for _, rb in ipairs(rowButtons) do
        if filteredIndices[rb.idx] == CL.Data.activeSessionIndex then
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
