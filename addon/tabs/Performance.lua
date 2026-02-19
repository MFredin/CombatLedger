-- tabs/Performance.lua — Performance tab (Task 2.3)
--
-- Renders per-player performance stats for the latest session:
--   • Sortable table: Name | Class | DPS | HPS | Interrupts | Deaths | CC Applied
--   • Encounter summary bar: total damage, total healing, duration
--   • Defensive audit section: who used defensives and missed opportunities

local addonName, CL = ...
local Performance = {}
CL.Performance = Performance

CL.Frame:RegisterTab("performance", "Performance", Performance)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local ROW_H = 22

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function classColour(cls)
    local cc = CL.Config.classColours[cls]
    if cc then return cc.r, cc.g, cc.b end
    return C.textPrimary.r, C.textPrimary.g, C.textPrimary.b
end

local function formatBigNum(n)
    n = n or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n))
end

-- ---------------------------------------------------------------------------
-- Column header row
-- ---------------------------------------------------------------------------

local COLS = {
    { x =   8, w = 120, text = "Player",      key = "playerName"    },
    { x = 132, w =  80, text = "Spec",        key = "playerSpec"    },
    { x = 216, w =  80, text = "DPS",         key = "dps"           },
    { x = 300, w =  80, text = "HPS",         key = "hps"           },
    { x = 384, w =  60, text = "Interrupts",  key = "interruptCount"},
    { x = 448, w =  50, text = "Deaths",      key = "deathCount"    },
    { x = 502, w =  60, text = "CC Applied",  key = "ccApplied"     },
    { x = 566, w =  60, text = "Rank",        key = nil             },  -- Phase 3 percentile
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
end

-- ---------------------------------------------------------------------------
-- Player data row
-- ---------------------------------------------------------------------------

local function buildPlayerRow(parent, p, yOffset, rowIndex)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT")

    if rowIndex % 2 == 0 then
        setBg(row, 0.06, 0.07, 0.09, 1)
    end

    local cr, cg, cb = classColour(p.playerClass or "")

    -- Player name (class coloured)
    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFs:SetWidth(120)
    nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
    nameFs:SetTextColor(cr, cg, cb)
    nameFs:SetText(p.playerName or "Unknown")

    -- Spec abbreviation
    local specFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specFs:SetWidth(80)
    specFs:SetPoint("LEFT", row, "LEFT", 132, 0)
    specFs:SetText("|cff6b7a9a" .. (p.playerSpec or "???"):sub(1, 6) .. "|r")

    -- DPS (red tint = damage dealer)
    local dpsFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpsFs:SetWidth(80)
    dpsFs:SetPoint("LEFT", row, "LEFT", 216, 0)
    if (p.dps or 0) > 0 then
        dpsFs:SetTextColor(0.91, 0.40, 0.40)
        dpsFs:SetText(formatBigNum(p.dps))
    else
        dpsFs:SetText("|cff555555—|r")
    end

    -- HPS (green tint = healer)
    local hpsFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpsFs:SetWidth(80)
    hpsFs:SetPoint("LEFT", row, "LEFT", 300, 0)
    if (p.hps or 0) > 0 then
        hpsFs:SetTextColor(0.40, 0.91, 0.55)
        hpsFs:SetText(formatBigNum(p.hps))
    else
        hpsFs:SetText("|cff555555—|r")
    end

    -- Interrupts (blue = kicks)
    local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intFs:SetWidth(60)
    intFs:SetPoint("LEFT", row, "LEFT", 384, 0)
    local intCount = p.interruptCount or 0
    if intCount > 0 then
        intFs:SetTextColor(0.25, 0.72, 0.91)
        intFs:SetText(tostring(intCount))
    else
        intFs:SetText("|cff5555550|r")
    end

    -- Deaths (red = bad)
    local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathFs:SetWidth(50)
    deathFs:SetPoint("LEFT", row, "LEFT", 448, 0)
    local deathCount = p.deathCount or 0
    if deathCount > 0 then
        deathFs:SetTextColor(0.91, 0.25, 0.25)
        deathFs:SetText(tostring(deathCount))
    else
        deathFs:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t")
    end

    -- CC applied (teal)
    local ccFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ccFs:SetWidth(60)
    ccFs:SetPoint("LEFT", row, "LEFT", 502, 0)
    local ccCount = p.ccApplied or 0
    if ccCount > 0 then
        ccFs:SetTextColor(0.25, 0.72, 0.91)
        ccFs:SetText(tostring(ccCount))
    else
        ccFs:SetText("|cff5555550|r")
    end

    -- Rank — DPS percentile badge from Phase 3 distribution data
    local rankFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankFs:SetWidth(60)
    rankFs:SetPoint("LEFT", row, "LEFT", 566, 0)
    local dpsDist = CL.Data:GetPlayerPercentile(p.playerGUID, "dps")
    local hpsDist = CL.Data:GetPlayerPercentile(p.playerGUID, "hps")
    if dpsDist and dpsDist.totalSamples and dpsDist.totalSamples > 1 then
        rankFs:SetText(CL.Data:FormatPercentile(dpsDist.percentile))
    elseif hpsDist and hpsDist.totalSamples and hpsDist.totalSamples > 1 then
        rankFs:SetText(CL.Data:FormatPercentile(hpsDist.percentile))
    else
        rankFs:SetText("|cff555555—|r")
    end
end

-- ---------------------------------------------------------------------------
-- Defensive audit section
-- ---------------------------------------------------------------------------

local function buildDefensiveSection(content, defensiveAudit, yOffset)
    if not defensiveAudit or not defensiveAudit.players then return yOffset end

    -- Section header
    local sectionHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
    sectionHdr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    sectionHdr:SetText("Defensive Audit")
    yOffset = yOffset - 24

    local subHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
    subHdr:SetText("|cff6b7a9aMissed defensive at time of death|r")
    yOffset = yOffset - 20

    local hasAny = false
    for _, playerAudit in ipairs(defensiveAudit.players or {}) do
        if #(playerAudit.missedAtDeath or {}) > 0 then
            hasAny = true
            local cr, cg, cb = classColour(playerAudit.playerClass or "")

            local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
            nameLabel:SetTextColor(cr, cg, cb)
            nameLabel:SetText(playerAudit.playerName or "Unknown")
            yOffset = yOffset - 16

            for _, missed in ipairs(playerAudit.missedAtDeath) do
                local missedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                missedLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
                local sinceStr = missed.secSinceLastUse
                    and string.format("(last used %.0fs ago)", missed.secSinceLastUse)
                    or "(never used)"
                missedLabel:SetFormattedText("|cfffe8040!! %s %s|r", missed.spellName, sinceStr)
                yOffset = yOffset - 16
            end

            -- Phase 3.5: missed external defensives (e.g. Ironbark available but unused)
            for _, ext in ipairs(playerAudit.missedExternals or {}) do
                local extLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                extLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 20, yOffset)
                local sinceStr = ext.secSinceLastUse
                    and string.format("(last cast %.0fs ago)", ext.secSinceLastUse)
                    or "(never used)"
                extLabel:SetFormattedText(
                    "|cff40b8e8>> %s from %s was available %s|r",
                    ext.spellName, ext.casterName, sinceStr
                )
                yOffset = yOffset - 16
            end
            yOffset = yOffset - 4
        end
    end

    if not hasAny then
        local okLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        okLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 8, yOffset)
        okLabel:SetText("|cff40b870All defensives were used appropriately.|r")
        yOffset = yOffset - 16
    end

    return yOffset
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Performance:Render(parent)
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
    local perf = CL.Data:GetPerformance(session)
    local defensiveAudit = CL.Data:GetDefensiveAudit(session)

    local players = perf.players or {}
    if #players == 0 then
        CL.Frame:ShowEmptyState("No performance data in this session.", "")
        return
    end

    -- Scroll container
    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Encounter summary
    local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    hdr:SetFormattedText(
        "|cffe8a820%s|r  |cff6b7a9aPull #%d — %s — %ds|r",
        session.encounterName or "Unknown",
        session.pullNumber or 0,
        session.success and "Success" or "Wipe",
        perf.encounterDurationSec or 0
    )

    -- Totals line
    local totals = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totals:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -28)
    totals:SetFormattedText(
        "Total Damage: |cffe84040%s|r   Total Healing: |cff40e87a%s|r",
        formatBigNum(perf.totalDamageDone),
        formatBigNum(perf.totalHealingDone)
    )

    local yOffset = -54

    -- Column headers
    buildHeader(content, yOffset)
    yOffset = yOffset - ROW_H - 2

    -- Player rows
    for i, p in ipairs(players) do
        buildPlayerRow(content, p, yOffset, i)
        yOffset = yOffset - ROW_H
    end

    -- Gap + defensive section
    yOffset = yOffset - 20
    yOffset = buildDefensiveSection(content, defensiveAudit, yOffset)

    content:SetHeight(math.abs(yOffset) + 16)
end

function Performance:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Performance:Clear(parent)
    self:Hide(parent)
end
