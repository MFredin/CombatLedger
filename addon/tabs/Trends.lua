-- tabs/Trends.lua — Pull-over-pull Trend Analysis (Phase 3 Task 3.3)
--
-- Per-player-per-metric spark-line charts showing last 5–30 pulls:
--   • One row per player per metric (deaths, interrupt rate, DPS/HPS, CC)
--   • Spark-line: series of dots + connecting lines via WoW texture frames
--   • Trend arrow: ↑ green (improving), ↓ red (declining), → grey (stable)
--   • Summary banner: boss, total pulls, kills, best time, group trend arrows
--
-- Data comes from CombatLedgerDB.trends and CombatLedgerDB.distribution

local addonName, CL = ...
local Trends = {}
CL.Trends = Trends

CL.Frame:RegisterTab("trends", "Trends", Trends)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CHART_W   = 540   -- spark-line chart width in pixels
local CHART_H   = 20    -- height of each spark-line row
local DOT_SIZE  = 6     -- diameter of each data point dot
local ROW_H     = 40    -- total height per metric row (label + spark-line)
local ROW_GAP   = 6     -- vertical gap between rows

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Spark-line renderer
-- ---------------------------------------------------------------------------
-- Draws a mini chart as a series of coloured dots connected by thin lines.
-- Each dot is a small Frame with a texture; connecting lines are 2px frames.

local function buildSparkLine(parent, values, successes, xOffset, yOffset, chartW, chartH)
    if not values or #values == 0 then return end

    local n = #values
    if n < 1 then return end

    -- Normalise values to [0, chartH] range
    local minV, maxV = values[1], values[1]
    for _, v in ipairs(values) do
        if v < minV then minV = v end
        if v > maxV then maxV = v end
    end
    local range = maxV - minV
    if range < 1 then range = 1 end  -- avoid div-by-zero for flat lines

    local function normY(v)
        -- Invert so higher = up on screen; add 3px padding
        return -chartH + math.floor(((v - minV) / range) * (chartH - DOT_SIZE)) + 3
    end

    local stepX = chartW / math.max(n - 1, 1)

    local prevX, prevY = nil, nil
    for i, v in ipairs(values) do
        local dotX = xOffset + math.floor((i - 1) * stepX)
        local dotY = yOffset + normY(v)
        local isKill = successes and successes[i]

        -- Connecting line from previous dot
        if prevX then
            local dx = dotX - prevX
            local dy = dotY - prevY
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                local line = CreateFrame("Frame", nil, parent)
                line:SetSize(math.max(math.abs(dx), 1), 2)
                line:SetPoint("TOPLEFT", parent, "TOPLEFT", prevX, prevY - 1)
                local lineTex = line:CreateTexture(nil, "ARTWORK")
                lineTex:SetAllPoints(line)
                lineTex:SetColorTexture(0.3, 0.3, 0.4, 0.7)
            end
        end

        -- Dot
        local dot = CreateFrame("Frame", nil, parent)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetPoint("TOPLEFT", parent, "TOPLEFT", dotX - DOT_SIZE / 2, dotY)
        local dotTex = dot:CreateTexture(nil, "OVERLAY")
        dotTex:SetAllPoints(dot)
        if isKill then
            dotTex:SetColorTexture(0.25, 0.91, 0.47, 1)  -- green = kill
        else
            dotTex:SetColorTexture(0.91, 0.35, 0.35, 1)  -- red = wipe
        end

        prevX = dotX
        prevY = dotY
    end
end

-- ---------------------------------------------------------------------------
-- Group trend summary banner
-- ---------------------------------------------------------------------------

local function buildSummaryBanner(parent, trend, yStart)
    local summary = trend.summary or {}
    local y = yStart

    -- Boss name + pull counts
    local titleFs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    titleFs:SetFormattedText(
        "|cffe8a820%s|r  |cff6b7a9a%d pulls  ·  %d kills  ·  best %s|r",
        trend.encounterName or "Unknown Boss",
        summary.totalPulls or 0,
        summary.kills or 0,
        CL.Data:FormatDuration(summary.bestTimeSec or 0)
    )
    y = y - 24

    -- Group trend arrows row
    local arrowLine = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrowLine:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    arrowLine:SetFormattedText(
        "Deaths %s   Interrupts %s   DPS %s   " ..
        "|cff6b7a9aAvg deaths: %.1f  ·  Avg int: %.0f%%|r",
        CL.Data:FormatTrend(summary.deathTrend, true),   -- inverted: fewer = better
        CL.Data:FormatTrend(summary.interruptTrend, false),
        CL.Data:FormatTrend(summary.dpsTrend, false),
        summary.avgDeaths or 0,
        summary.avgInterruptRate or 0
    )
    y = y - 28

    -- Divider
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    divider:SetHeight(1)
    divider:SetColorTexture(0.2, 0.2, 0.25, 1)
    y = y - 12

    return y
end

-- ---------------------------------------------------------------------------
-- Build one metric section (e.g. "Deaths" spark-lines per player)
-- ---------------------------------------------------------------------------

local METRIC_DEFS = {
    {
        label      = "Deaths",
        pointKey   = "totalDeaths",
        invertBetter = true,   -- fewer deaths = improvement
    },
    {
        label      = "Interrupt Rate %",
        pointKey   = "interruptRatePct",
        invertBetter = false,
    },
    {
        label      = "Group DPS (k/s)",
        pointKey   = "totalDamageDone",
        scale      = function(pt)
            return pt.durationSec > 0 and math.floor(pt.totalDamageDone / pt.durationSec / 1000) or 0
        end,
        invertBetter = false,
    },
    {
        label      = "CC Coverage %",
        pointKey   = "ccAvgCoveragePct",
        invertBetter = false,
    },
}

local function buildMetricSection(parent, metricDef, points, yOffset)
    if not points or #points == 0 then return yOffset end

    -- Section label
    local secLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    secLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    secLabel:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    secLabel:SetText(metricDef.label)
    yOffset = yOffset - 18

    -- Extract values
    local values = {}
    local successes = {}
    for _, pt in ipairs(points) do
        local v
        if metricDef.scale then
            v = metricDef.scale(pt)
        else
            v = pt[metricDef.pointKey] or 0
        end
        table.insert(values, v)
        table.insert(successes, pt.success)
    end

    -- Build spark-line chart
    local chartFrame = CreateFrame("Frame", nil, parent)
    chartFrame:SetSize(CHART_W + 120, CHART_H + 8)
    chartFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    setBg(chartFrame, 0.05, 0.05, 0.08, 1)

    -- X-axis labels (pull numbers, every 5th)
    for i, pt in ipairs(points) do
        if i == 1 or i == #points or (i % 5 == 0) then
            local stepX = CHART_W / math.max(#points - 1, 1)
            local lx = 8 + math.floor((i - 1) * stepX)
            local labelFs = chartFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelFs:SetPoint("TOPLEFT", chartFrame, "TOPLEFT", lx - 8, -(CHART_H + 4))
            labelFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
            labelFs:SetText(tostring(pt.pullNumber))
        end
    end

    buildSparkLine(chartFrame, values, successes, 8, -4, CHART_W, CHART_H)

    -- Min / max / current labels on right
    local curVal = values[#values] or 0
    local minVal = math.huge
    local maxVal = -math.huge
    for _, v in ipairs(values) do
        if v < minVal then minVal = v end
        if v > maxVal then maxVal = v end
    end
    if minVal == math.huge then minVal = 0 end
    if maxVal == -math.huge then maxVal = 0 end

    -- Compute trend over all points
    local slope = 0
    if #values >= 2 then
        local n = #values
        local xm = (n - 1) / 2
        local ym = 0
        for _, v in ipairs(values) do ym = ym + v end
        ym = ym / n
        local num, den = 0, 0
        for i, v in ipairs(values) do
            local xi = i - 1
            num = num + (xi - xm) * (v - ym)
            den = den + (xi - xm) * (xi - xm)
        end
        if den ~= 0 then slope = num / den end
    end

    local statLabel = chartFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statLabel:SetPoint("LEFT", chartFrame, "LEFT", CHART_W + 16, 0)
    statLabel:SetText(string.format(
        "cur: |cffffffff%.1f|r  %s",
        curVal,
        CL.Data:FormatTrend(slope, metricDef.invertBetter)
    ))

    yOffset = yOffset - CHART_H - 28  -- chart + x-axis labels + gap
    return yOffset
end

-- ---------------------------------------------------------------------------
-- Distribution section (from last session's percentile data)
-- ---------------------------------------------------------------------------

local function buildDistributionSection(content, yOffset)
    local distPlayers = CL.Data:GetDistributionPlayers()
    if #distPlayers == 0 then return yOffset end

    -- Section header
    local sectionHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
    sectionHdr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    sectionHdr:SetText("Personal Percentiles (vs your pull history)")
    yOffset = yOffset - 20

    local subHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
    subHdr:SetText("|cff6b7a9aGold = exceptional  Green = good  Blue = average  Red = poor|r")
    yOffset = yOffset - 20

    -- Group by player, show dps/hps/interrupts in one line
    local playerMap = {}
    local playerOrder = {}
    for _, dp in ipairs(distPlayers) do
        if not playerMap[dp.playerName] then
            playerMap[dp.playerName] = {}
            table.insert(playerOrder, dp.playerName)
        end
        playerMap[dp.playerName][dp.metric] = dp
    end

    for _, name in ipairs(playerOrder) do
        local metrics = playerMap[name]
        local dpsEntry = metrics["dps"]
        local hpsEntry = metrics["hps"]
        local intEntry = metrics["interrupts"]
        local classColor = "6b7a9a"
        if dpsEntry then
            local cc = CL.Config.classColours[dpsEntry.playerClass]
            if cc then
                classColor = string.format("%02x%02x%02x",
                    math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255))
            end
        end

        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, yOffset)

        -- Name
        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetWidth(120)
        nameFs:SetPoint("LEFT", row, "LEFT", 0, 0)
        nameFs:SetText(string.format("|cff%s%s|r", classColor, name))

        -- DPS percentile
        if dpsEntry then
            local dpsFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dpsFs:SetWidth(80)
            dpsFs:SetPoint("LEFT", row, "LEFT", 124, 0)
            dpsFs:SetText("DPS " .. CL.Data:FormatPercentile(dpsEntry.percentile)
                .. string.format("|cff6b7a9a (%d pulls)|r", dpsEntry.totalSamples))
        end

        -- HPS percentile
        if hpsEntry and hpsEntry.currentValue > 0 then
            local hpsFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hpsFs:SetWidth(80)
            hpsFs:SetPoint("LEFT", row, "LEFT", 240, 0)
            hpsFs:SetText("HPS " .. CL.Data:FormatPercentile(hpsEntry.percentile))
        end

        -- Interrupts percentile
        if intEntry then
            local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            intFs:SetWidth(100)
            intFs:SetPoint("LEFT", row, "LEFT", 340, 0)
            intFs:SetText("Interrupts " .. CL.Data:FormatPercentile(intEntry.percentile))
        end

        yOffset = yOffset - 22
    end

    return yOffset
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Trends:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        CL.Frame:ShowEmptyState(
            "No data available.",
            CombatLedgerDB and "No sessions recorded yet." or "Companion app not detected."
        )
        return
    end
    CL.Frame:HideEmptyState()

    local trend = CL.Data:GetTrend()
    local points = CL.Data:GetTrendPoints()

    if #points == 0 then
        CL.Frame:ShowEmptyState(
            "Not enough data for trend analysis.",
            "Complete multiple pulls on the same boss to see trends."
        )
        return
    end

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Summary banner
    local yOffset = -8
    yOffset = buildSummaryBanner(content, trend, yOffset)

    -- One spark-line per metric
    for _, metricDef in ipairs(METRIC_DEFS) do
        yOffset = buildMetricSection(content, metricDef, points, yOffset)
    end

    -- Distribution section
    yOffset = yOffset - 12
    yOffset = buildDistributionSection(content, yOffset)

    content:SetHeight(math.abs(yOffset) + 24)
end

function Trends:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Trends:Clear(parent)
    self:Hide(parent)
end
