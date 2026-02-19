-- tabs/Interrupts.lua — Interrupt report tab (Task 1.11)
--
-- Renders:
--   • Header: total intercepted / total / rate %
--   • Table: Target·Cast | Interrupted By | Spell Used | Cast Progress | Status
--   • Per-player summary bar at bottom

local addonName, CL = ...
local Interrupts = {}
CL.Interrupts = Interrupts

CL.Frame:RegisterTab("interrupts", "Interrupts", Interrupts)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Status badge colours
-- ---------------------------------------------------------------------------

local STATUS_KICKED  = { r = 0.25, g = 0.72, b = 0.91 } -- blue
local STATUS_MISSED  = { r = 0.91, g = 0.25, b = 0.25 } -- red
local STATUS_PARTIAL = { r = 0.91, g = 0.70, b = 0.25 } -- amber

local ROW_H = 22

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Cast progress mini-bar
-- ---------------------------------------------------------------------------

local function buildProgressBar(parent, pct, wasInterrupted)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(80, 12)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.1, 0.1, 0.1, 1)

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", bar, "LEFT")
    fill:SetHeight(12)
    fill:SetWidth(math.max(2, 80 * (pct / 100)))
    if wasInterrupted then
        fill:SetColorTexture(0.25, 0.72, 0.91, 1) -- blue = kicked
    else
        fill:SetColorTexture(0.91, 0.25, 0.25, 1) -- red = full bar (missed)
    end

    return bar
end

-- ---------------------------------------------------------------------------
-- Build interrupt event row
-- ---------------------------------------------------------------------------

local function buildRow(parent, ev, yOffset, rowIndex)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT")

    if not ev.wasInterrupted then
        setBg(row, 0.20, 0.05, 0.05, 1) -- subtle red tint for missed
    elseif rowIndex % 2 == 0 then
        setBg(row, 0.06, 0.07, 0.09, 1)
    end

    local x = 8

    -- Target · Cast (col 1, 200px)
    local targetCast = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetCast:SetWidth(200)
    targetCast:SetPoint("LEFT", row, "LEFT", x, 0)
    targetCast:SetText(string.format("%s · %s", ev.targetName, ev.spellName))
    x = x + 204

    -- Interrupted By (col 2, 120px)
    local interBy = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interBy:SetWidth(120)
    interBy:SetPoint("LEFT", row, "LEFT", x, 0)
    interBy:SetText(ev.interruptedBy or "|cff555555—|r")
    x = x + 124

    -- Interrupt Spell (col 3, 120px)  — only relevant if kicked
    local intSpell = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intSpell:SetWidth(120)
    intSpell:SetPoint("LEFT", row, "LEFT", x, 0)
    intSpell:SetText(ev.interruptSpellId and tostring(ev.interruptSpellId) or "|cff555555—|r")
    x = x + 124

    -- Cast Progress bar (col 4, 84px)
    local pct = ev.wasInterrupted and (ev.castPercentAtInterrupt or 0) or 100
    local progressBar = buildProgressBar(row, pct, ev.wasInterrupted)
    progressBar:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + 88

    -- Status badge (col 5)
    local status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("LEFT", row, "LEFT", x, 0)
    if ev.wasInterrupted then
        local sc = STATUS_KICKED
        status:SetTextColor(sc.r, sc.g, sc.b)
        status:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t Kicked")
    else
        local sc = STATUS_MISSED
        status:SetTextColor(sc.r, sc.g, sc.b)
        status:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t Missed")
    end
end

-- ---------------------------------------------------------------------------
-- Column headers
-- ---------------------------------------------------------------------------

local function buildHeader(parent, yOffset)
    local hdrRow = CreateFrame("Frame", nil, parent)
    hdrRow:SetHeight(ROW_H)
    hdrRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    hdrRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT")
    setBg(hdrRow, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    local cols = {
        { x =   8, w = 200, text = "Target · Cast" },
        { x = 212, w = 120, text = "Interrupted By" },
        { x = 336, w = 120, text = "Spell Used" },
        { x = 460, w =  84, text = "Progress" },
        { x = 548, w = 100, text = "Status" },
    }
    for _, c in ipairs(cols) do
        local fs = hdrRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(c.w)
        fs:SetPoint("LEFT", hdrRow, "LEFT", c.x, 0)
        fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        fs:SetText(c.text)
    end
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Interrupts:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        CL.Frame:ShowEmptyState(
            "No data available.",
            CombatLedgerDB and "No sessions recorded yet." or "Companion app not detected."
        )
        return
    end
    CL.Frame:HideEmptyState()

    local session = CL.Data:GetActiveSession()
    local report  = CL.Data:GetInterrupts(session)
    local events  = report and report.interrupts or {}

    if #events == 0 then
        CL.Frame:ShowEmptyState("No interruptible casts detected in this session.", "")
        return
    end

    local summary = report.summary or {}

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Summary line
    local sumLine = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sumLine:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    sumLine:SetFormattedText(
        "Interrupted: |cff40b8e8%d|r / |cff6b7a9a%d|r  (|cff%02x%02x%02x%d%%|r)",
        summary.intercepted or 0,
        summary.total or 0,
        summary.ratePercent >= 80 and 64 or 232,
        summary.ratePercent >= 80 and 232 or 64,
        64,
        summary.ratePercent or 0
    )

    local yOffset = -34
    buildHeader(content, yOffset)
    yOffset = yOffset - ROW_H - 2

    -- Sort by pull then timestamp
    table.sort(events, function(a, b)
        if a.pullNumber ~= b.pullNumber then return a.pullNumber < b.pullNumber end
        return a.timestamp < b.timestamp
    end)

    for i, ev in ipairs(events) do
        buildRow(content, ev, yOffset, i)
        yOffset = yOffset - ROW_H
    end

    -- Per-player summary bar
    local byPlayer = report.byPlayer or {}
    yOffset = yOffset - 16
    local bar = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
    bar:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    bar:SetText("Per-player kicks:")
    yOffset = yOffset - 20

    for name, pdata in pairs(byPlayer) do
        local pLine = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pLine:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOffset)
        pLine:SetFormattedText("  %s  |cff40b8e8%d|r kicks", name, pdata.intercepted)
        yOffset = yOffset - 18
    end

    content:SetHeight(math.abs(yOffset) + 16)
end

function Interrupts:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Interrupts:Clear(parent)
    self:Hide(parent)
end
