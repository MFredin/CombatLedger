-- tabs/CC.lua — CC Coverage tab (Task 2.2)
--
-- Renders per-target crowd-control coverage timelines with DR tracking.
--
-- Layout per target row:
--   [Target Name] [Coverage %]  [Wasted Immune Count]
--   [-------- Horizontal timeline bar with DR-opacity segments --------]
--
-- DR opacity legend at top:
--   ████ Full  ████ 50%  ████ 25%  ░░░░ Immune
--
-- Filter toggle: show only "problem targets" with <50% coverage.

local addonName, CL = ...
local CC = {}
CL.CC = CC

CL.Frame:RegisterTab("cc", "CC Coverage", CC)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local TIMELINE_W    = 720   -- px width of the timeline bar area
local ROW_H         = 48    -- height per target row (name + timeline)
local SEGMENT_H     = 20    -- height of the timeline bar itself
local ROW_PAD       = 8     -- vertical gap between rows

-- DR multiplier → alpha for timeline segment fill
-- Colours from Config: teal base tinted by alpha
local DR_ALPHAS = {
    [1.0]  = 1.00,  -- full CC
    [0.5]  = 0.60,  -- half DR
    [0.25] = 0.35,  -- quarter DR
    [0.0]  = 0.15,  -- immune (wasted cast)
}

-- Coverage % → r,g,b badge colour
local function coverageColour(pct)
    if pct >= 80 then return 0.25, 0.90, 0.40  -- green
    elseif pct >= 50 then return 0.91, 0.80, 0.25  -- gold
    else return 0.91, 0.25, 0.25  -- red
    end
end

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- DR legend bar
-- ---------------------------------------------------------------------------

local function buildLegend(parent, yOffset)
    local legendFrame = CreateFrame("Frame", nil, parent)
    legendFrame:SetHeight(20)
    legendFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    legendFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)

    local x = 0
    local entries = {
        { label = "Full CC",  alpha = 1.00 },
        { label = "50% DR",   alpha = 0.60 },
        { label = "25% DR",   alpha = 0.35 },
        { label = "Immune",   alpha = 0.15 },
    }
    for _, e in ipairs(entries) do
        local swatch = legendFrame:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(14, 14)
        swatch:SetPoint("LEFT", legendFrame, "LEFT", x, 0)
        swatch:SetColorTexture(0.25, 0.72, 0.91, e.alpha)
        x = x + 18

        local lbl = legendFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", legendFrame, "LEFT", x, 0)
        lbl:SetText("|cff6b7a9a" .. e.label .. "|r")
        lbl:SetWidth(64)
        x = x + 68
    end

    return legendFrame
end

-- ---------------------------------------------------------------------------
-- Filter toggle button
-- ---------------------------------------------------------------------------

local filterProblems = false  -- module-level state

local function buildFilterToggle(parent, yOffset, onToggle)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(180, 22)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)

    local bgTex = btn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(btn)
    bgTex:SetColorTexture(0.15, 0.15, 0.18, 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints(btn)

    local function refresh()
        if filterProblems then
            lbl:SetText("|cfffe8040!! Problem targets only|r")
        else
            lbl:SetText("|cff6b7a9aShow: All targets|r")
        end
    end
    refresh()

    btn:SetScript("OnClick", function()
        filterProblems = not filterProblems
        refresh()
        onToggle()
    end)

    return btn
end

-- ---------------------------------------------------------------------------
-- Build a single target's coverage row
-- ---------------------------------------------------------------------------

-- sessionStartTime: unix timestamp (seconds) of the encounter start
local function buildTargetRow(parent, cc, yOffset, sessionStartTime)
    local rowFrame = CreateFrame("Frame", nil, parent)
    rowFrame:SetHeight(ROW_H)
    rowFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    rowFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)

    -- Alternating subtle row background
    setBg(rowFrame, 0.07, 0.08, 0.10, 1)

    -- Target name (left, 150px)
    local nameLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetWidth(148)
    nameLabel:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 4, -4)
    nameLabel:SetText(cc.targetName or "Unknown")

    -- Coverage % badge (from totalCombatDuration / coveredDuration fields)
    local pct = cc.coveragePercent or 0
    local br, bg, bb = coverageColour(pct)
    local pctLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pctLabel:SetWidth(56)
    pctLabel:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 154, -4)
    pctLabel:SetTextColor(br, bg, bb)
    pctLabel:SetFormattedText("%.0f%%", pct)

    -- Wasted (immune) count
    if (cc.wastedCasts or 0) > 0 then
        local wastedLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wastedLabel:SetWidth(100)
        wastedLabel:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 212, -4)
        wastedLabel:SetTextColor(0.91, 0.25, 0.25)
        wastedLabel:SetFormattedText("!! %d immune", cc.wastedCasts)
    end

    -- Timeline bar background
    local timelineFrame = CreateFrame("Frame", nil, rowFrame)
    timelineFrame:SetSize(TIMELINE_W, SEGMENT_H)
    timelineFrame:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 4, 8)

    local bgBar = timelineFrame:CreateTexture(nil, "BACKGROUND")
    bgBar:SetAllPoints(timelineFrame)
    bgBar:SetColorTexture(0.05, 0.05, 0.07, 1)

    -- Use per-target totalCombatDuration (seconds) as the timeline axis
    local dur = cc.totalCombatDuration or 0
    if dur <= 0 then dur = 1 end

    -- Draw each segment
    -- seg.startTime / seg.endTime are unix timestamps (seconds).
    -- seg.actualDuration is the CC duration in seconds.
    local segments = cc.segments or {}
    for _, seg in ipairs(segments) do
        -- Compute relative start within the target's combat window
        local relStart = (seg.startTime or sessionStartTime) - sessionStartTime
        local segDur   = seg.actualDuration or 0
        if segDur > 0 then
            local xPct = math.max(0, relStart / dur)
            local wPct = segDur / dur
            local xPx  = math.floor(xPct * TIMELINE_W)
            local wPx  = math.max(3, math.floor(wPct * TIMELINE_W))

            local mult = seg.drMultiplier
            if mult == nil then mult = 1.0 end
            local alpha = DR_ALPHAS[mult] or 0.15

            local segTex = timelineFrame:CreateTexture(nil, "ARTWORK")
            segTex:SetSize(wPx, SEGMENT_H - 2)
            segTex:SetPoint("LEFT", timelineFrame, "LEFT", xPx, 0)
            segTex:SetColorTexture(0.25, 0.72, 0.91, alpha)
        end
    end

    return ROW_H + ROW_PAD
end

-- ---------------------------------------------------------------------------
-- Column headers
-- ---------------------------------------------------------------------------

local function buildColHeaders(parent, yOffset)
    local hdrRow = CreateFrame("Frame", nil, parent)
    hdrRow:SetHeight(22)
    hdrRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    hdrRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)
    setBg(hdrRow, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    local cols = {
        { x =   4, w = 148, text = "Target" },
        { x = 154, w =  56, text = "Coverage" },
        { x = 212, w = 100, text = "Wasted" },
        { x = 316, w = TIMELINE_W, text = "Timeline  ← 0s" },
    }
    for _, col in ipairs(cols) do
        local fs = hdrRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(col.w)
        fs:SetPoint("LEFT", hdrRow, "LEFT", col.x, 0)
        fs:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        fs:SetText(col.text)
    end
end

-- ---------------------------------------------------------------------------
-- Main render  (called by Frame on tab switch)
-- ---------------------------------------------------------------------------

function CC:Render(parent)
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
    local coverage = CL.Data:GetCCCoverage(session)

    if not coverage or #coverage == 0 then
        CL.Frame:ShowEmptyState("No CC data in this session.", "No crowd-control events were recorded.")
        return
    end

    -- Session start unix timestamp (seconds) — used for relative segment positioning
    local sessionStartTime = session.startTime or 0

    -- Scroll container
    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Encounter header
    local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    hdr:SetFormattedText("|cffe8a820%s|r  |cff6b7a9aPull #%d — %s — %d target(s)|r",
        session.encounterName or "Unknown",
        session.pullNumber or 0,
        session.success and "Success" or "Wipe",
        #coverage)

    -- Filter toggle
    local yOffset = -36
    local function reRender()
        CC:Render(parent)
    end
    buildFilterToggle(content, yOffset, reRender)

    -- DR legend
    buildLegend(content, yOffset)
    yOffset = yOffset - 26

    -- Column headers
    buildColHeaders(content, yOffset)
    yOffset = yOffset - 26

    -- Sort: worst coverage first (most problematic at top)
    table.sort(coverage, function(a, b)
        return (a.coveragePercent or 0) < (b.coveragePercent or 0)
    end)

    -- Render rows
    local rowsDrawn = 0
    for _, cc in ipairs(coverage) do
        local pct = cc.coveragePercent or 0
        if not filterProblems or pct < 50 then
            local h = buildTargetRow(content, cc, yOffset, sessionStartTime)
            yOffset = yOffset - h
            rowsDrawn = rowsDrawn + 1
        end
    end

    if rowsDrawn == 0 then
        CL.Frame:ShowEmptyState("No problem targets.", "All targets have ≥50% CC coverage.")
    end

    content:SetHeight(math.abs(yOffset) + 16)
end

function CC:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function CC:Clear(parent)
    self:Hide(parent)
end
