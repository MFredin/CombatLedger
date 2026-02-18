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

local COLS = {
    { x =   8, w =  28, text = "#"          },
    { x =  40, w = 200, text = "Boss"       },
    { x = 244, w =  80, text = "Difficulty" },
    { x = 328, w =  80, text = "Duration"   },
    { x = 412, w =  60, text = "Deaths"     },
    { x = 476, w =  60, text = "Int %"      },
    { x = 540, w =  80, text = "Result"     },
    { x = 624, w = 120, text = "Date"       },
}

local function buildHeader(parent, yOffset)
    local hdrRow = CreateFrame("Frame", nil, parent)
    hdrRow:SetHeight(ROW_H)
    hdrRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    hdrRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    setBg(hdrRow, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    for _, col in ipairs(COLS) do
        local fs = hdrRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(col.w)
        fs:SetPoint("LEFT", hdrRow, "LEFT", col.x, 0)
        fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
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

    -- Interrupt rate
    local intRate = (session.interrupts and session.interrupts.summary
        and session.interrupts.summary.ratePercent) or 0
    local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intFs:SetWidth(60)
    intFs:SetPoint("LEFT", row, "LEFT", 476, 0)
    local ir, ig, ib = intRate >= 80 and 0.25 or 0.91, intRate >= 80 and 0.72 or 0.45, 0.25
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

    local sessions = CL.Data:GetSessions()
    if #sessions == 0 then
        CL.Frame:ShowEmptyState("No sessions recorded yet.", "Run a dungeon then /reload.")
        return
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetAllPoints(parent)
    self.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(parent:GetWidth() - 28)
    scrollFrame:SetScrollChild(content)

    -- Session count banner
    local banner = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    banner:SetFormattedText(
        "|cffe8a820%d sessions|r  |cff6b7a9astored in SavedVariables|r  " ..
        "  |cff6b7a9aActive: Pull #%d (%s)|r",
        #sessions,
        CL.Data.activeSessionIndex,
        (sessions[CL.Data.activeSessionIndex] or {}).encounterName or "?"
    )

    local yOffset = -32
    buildHeader(content, yOffset)
    yOffset = yOffset - ROW_H - 2

    -- Row buttons list for highlight management
    local rowButtons = {}

    local function onSelect(idx, border)
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
        CL.Data:SetActiveSession(idx)
        -- Refresh banner
        banner:SetFormattedText(
            "|cffe8a820%d sessions|r  |cff6b7a9astored in SavedVariables|r" ..
            "  |cff6b7a9aActive: Pull #%d (%s)|r",
            #sessions,
            idx,
            (sessions[idx] or {}).encounterName or "?"
        )
    end

    for i, session in ipairs(sessions) do
        buildSessionRow(content, session, i, yOffset, onSelect, rowButtons)
        yOffset = yOffset - ROW_H
    end

    -- Highlight currently active session
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
