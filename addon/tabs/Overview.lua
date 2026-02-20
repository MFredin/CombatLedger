-- tabs/Overview.lua — Overview tab
--
-- Layout (matches mockup):
--   • Encounter header card — gold left stripe, encounter name, pull stats
--   • 2-column body:
--       Left  (45%) — Death summary: player rows with class color + fatal spell
--       Right (55%) — Interrupt summary: per-player progress bars

local addonName, CL = ...
local Overview = {}
CL.Overview = Overview

CL.Frame:RegisterTab("overview", "Overview", Overview)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function setBg(f, r, g, b, a)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

local function addBorder(f, r, g, b)
    r, g, b = r or C.borderSub.r, g or C.borderSub.g, b or C.borderSub.b
    local bt = f:CreateTexture(nil, "BORDER"); bt:SetHeight(1); bt:SetColorTexture(r, g, b); bt:SetPoint("TOPLEFT", f, "TOPLEFT"); bt:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    local bb = f:CreateTexture(nil, "BORDER"); bb:SetHeight(1); bb:SetColorTexture(r, g, b); bb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    local bl = f:CreateTexture(nil, "BORDER"); bl:SetWidth(1);  bl:SetColorTexture(r, g, b); bl:SetPoint("TOPLEFT", f, "TOPLEFT"); bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    local br = f:CreateTexture(nil, "BORDER"); br:SetWidth(1);  br:SetColorTexture(r, g, b); br:SetPoint("TOPRIGHT", f, "TOPRIGHT"); br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
end

local function classColor(cls)
    local cc = CL.Config.classColours[cls and cls:upper()]
    if cc then return cc.r, cc.g, cc.b end
    return C.textSecondary.r, C.textSecondary.g, C.textSecondary.b
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function Overview:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        if not CombatLedgerDB then
            CL.Frame:ShowEmptyState(
                "Companion app not detected.",
                "Install CombatLedger Companion to enable post-combat analysis."
            )
        else
            CL.Frame:ShowEmptyState(
                "No sessions recorded yet.",
                "Run a dungeon or raid encounter and /reload."
            )
        end
        return
    end
    CL.Frame:HideEmptyState()

    local session = CL.Data:GetActiveSession()
    if not session then return end

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    self.frame = f

    local CONTENT_W = parent:GetWidth() or 936  -- ~960 - 12*2 margins
    local PAD = 12

    -- ── Encounter header card ─────────────────────────────────────────────
    -- Gold left stripe, gradient-tinted bg
    local hCard = CreateFrame("Frame", nil, f)
    hCard:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD, -PAD)
    hCard:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
    hCard:SetHeight(56)
    setBg(hCard, C.cardBg.r, C.cardBg.g, C.cardBg.b)
    addBorder(hCard, C.borderSub.r, C.borderSub.g, C.borderSub.b)

    -- Gold left stripe (encounter header accent)
    local stripe = hCard:CreateTexture(nil, "OVERLAY")
    stripe:SetWidth(3)
    stripe:SetPoint("TOPLEFT",    hCard, "TOPLEFT",    0, 0)
    stripe:SetPoint("BOTTOMLEFT", hCard, "BOTTOMLEFT", 0, 0)
    stripe:SetColorTexture(C.gold.r, C.gold.g, C.gold.b)

    -- Encounter name
    local encName = hCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    encName:SetPoint("TOPLEFT", hCard, "TOPLEFT", 14, -10)
    encName:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
    encName:SetText(session.encounterName or "Unknown Encounter")

    -- Pull / run label, result, duration
    local resultColor = session.success and "|cff40e87a" or "|cffe84040"
    local resultText  = session.success and "KILL" or "WIPE"
    local isDungeon   = not CL.Config:IsRaidSession(session)
    local runLabel    = isDungeon and "Run" or "Pull"
    local pullLabel = hCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pullLabel:SetPoint("BOTTOMLEFT", hCard, "BOTTOMLEFT", 14, 10)
    pullLabel:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    pullLabel:SetText(string.format(
        "%s #%d  ·  %s%s|r  ·  %s",
        runLabel,
        session.pullNumber or 1,
        resultColor, resultText,
        CL.Data:FormatDuration(session.durationSec or 0)
    ))

    -- Stat counters (right side): Deaths | Int% | CC%
    local deaths    = #(session.deaths or {})
    local intTotal  = (session.interrupts and session.interrupts.summary and session.interrupts.summary.total) or 0
    local intHit    = (session.interrupts and session.interrupts.summary and session.interrupts.summary.intercepted) or 0
    local intPct    = intTotal > 0 and (intHit / intTotal * 100) or 0
    local ccPct     = (session.ccCoverage and session.ccCoverage.avgCoveragePct) or 0

    local function statCounter(label, val, valColor, xOffset)
        local valFs = hCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        valFs:SetPoint("RIGHT", hCard, "RIGHT", xOffset, 4)
        valFs:SetTextColor(valColor.r, valColor.g, valColor.b)
        valFs:SetText(val)

        local lblFs = hCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lblFs:SetPoint("RIGHT", hCard, "RIGHT", xOffset, -12)
        lblFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        lblFs:SetText(label)
    end

    local deathColor = deaths == 0 and C.green or C.red
    statCounter("DEATHS",   tostring(deaths), deathColor, -16)

    -- In dungeon mode interrupts are critical — always show in blue with a
    -- brighter shade for emphasis regardless of the actual rate.
    local intColor
    if isDungeon then
        intColor = intPct >= 80 and C.blue
                or intPct >= 50 and { r = C.blue.r * 0.75, g = C.blue.g * 0.75, b = 1.0 }
                or C.red
    else
        intColor = intPct >= 80 and C.green
                or intPct >= 50 and { r = C.gold.r, g = C.gold.g, b = C.gold.b }
                or C.red
    end
    statCounter(isDungeon and "INTERRUPT" or "INT%",
                string.format("%.0f%%", intPct), intColor, -96)
    statCounter("CC%",      string.format("%.0f%%", ccPct),
                ccPct >= 80 and C.green or ccPct >= 50 and { r = C.gold.r, g = C.gold.g, b = C.gold.b } or C.red,
                -180)

    -- Dividers between stats
    local function statDiv(xOffset)
        local d = hCard:CreateTexture(nil, "OVERLAY")
        d:SetWidth(1); d:SetHeight(30)
        d:SetPoint("RIGHT", hCard, "RIGHT", xOffset, 0)
        d:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)
    end
    statDiv(-76)
    statDiv(-160)

    -- ── 2-column section ──────────────────────────────────────────────────
    local COL_GAP  = 8
    local COL_Y    = -PAD - 56 - 8  -- below encounter header
    local COL_L_W  = math.floor((CONTENT_W - PAD * 2 - COL_GAP) * 0.45)
    local COL_R_W  = (CONTENT_W - PAD * 2 - COL_GAP) - COL_L_W
    local COL_H    = 340

    -- LEFT: Death Summary
    local leftCol = CreateFrame("Frame", nil, f)
    leftCol:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, COL_Y)
    leftCol:SetWidth(COL_L_W)
    leftCol:SetHeight(COL_H)

    -- Section header row
    local lHeader = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lHeader:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, 0)
    lHeader:SetText("DEATHS")
    lHeader:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    local lLine = leftCol:CreateTexture(nil, "OVERLAY")
    lLine:SetHeight(1)
    lLine:SetPoint("LEFT",  lHeader, "RIGHT", 6, 0)
    lLine:SetPoint("RIGHT", leftCol, "RIGHT", 0, 0)
    lLine:SetPoint("TOP",   lHeader, "TOP",   0, -7)
    lLine:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)

    -- Death player rows
    local deathList = session.deaths or {}
    local rowY = -22
    if #deathList == 0 then
        local noneFs = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noneFs:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, rowY)
        noneFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        noneFs:SetText("No deaths this pull  |TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t")
        noneFs:SetTextColor(C.green.r, C.green.g, C.green.b)
    else
        for i, death in ipairs(deathList) do
            if rowY < -(COL_H - 10) then break end

            -- Row background (red tint for death)
            local row = CreateFrame("Frame", nil, leftCol)
            row:SetPoint("TOPLEFT",  leftCol, "TOPLEFT",  0, rowY)
            row:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", 0, rowY)
            row:SetHeight(38)
            setBg(row, C.cardBg.r, C.cardBg.g, C.cardBg.b)
            addBorder(row, C.borderSub.r, C.borderSub.g, C.borderSub.b)

            -- Red left stripe
            local dStripe = row:CreateTexture(nil, "OVERLAY")
            dStripe:SetWidth(3)
            dStripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
            dStripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            dStripe:SetColorTexture(C.red.r, C.red.g, C.red.b)

            -- Class-colored avatar badge (spec abbreviation)
            local cr, cg, cb = classColor(death.playerClass)
            local avatar = CreateFrame("Frame", nil, row)
            avatar:SetSize(26, 26)
            avatar:SetPoint("LEFT", row, "LEFT", 8, 0)
            setBg(avatar, cr * 0.12, cg * 0.12, cb * 0.12)
            local avBorder = avatar:CreateTexture(nil, "OVERLAY")
            avBorder:SetAllPoints(avatar)
            avBorder:SetColorTexture(cr * 0.25, cg * 0.25, cb * 0.25)
            local specText = avatar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            specText:SetAllPoints(avatar)
            specText:SetJustifyH("CENTER")
            specText:SetTextColor(cr, cg, cb)
            local spec = (death.playerSpec or "?"):sub(1, 3):upper()
            specText:SetText(spec)

            -- Player name
            local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameFs:SetPoint("TOPLEFT",    row, "TOPLEFT",    40, -5)
            nameFs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 40, 14)
            nameFs:SetTextColor(cr, cg, cb)
            nameFs:SetJustifyV("TOP")
            nameFs:SetText(death.playerName or "Unknown")

            -- Fatal spell (right-aligned, red)
            local fatalSpell = death.killingBlow and death.killingBlow.spellName or "—"
            local fatalFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fatalFs:SetPoint("RIGHT", row, "RIGHT", -8, 3)
            fatalFs:SetTextColor(C.red.r, C.red.g, C.red.b)
            fatalFs:SetText(fatalSpell)

            -- Death time
            local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeFs:SetPoint("RIGHT", row, "RIGHT", -8, -12)
            timeFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
            if death.timeIntoPull then
                timeFs:SetText(string.format("@%ds", math.floor(death.timeIntoPull)))
            end

            rowY = rowY - 42
        end
    end

    -- RIGHT: Interrupt Summary
    local rightCol = CreateFrame("Frame", nil, f)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", COL_GAP, 0)
    rightCol:SetWidth(COL_R_W)
    rightCol:SetHeight(COL_H)

    local rHeader = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rHeader:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    rHeader:SetText(string.format("INTERRUPTS  %d/%d", intHit, intTotal))
    rHeader:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    local rLine = rightCol:CreateTexture(nil, "OVERLAY")
    rLine:SetHeight(1)
    rLine:SetPoint("LEFT",  rHeader, "RIGHT", 6, 0)
    rLine:SetPoint("RIGHT", rightCol, "RIGHT", 0, 0)
    rLine:SetPoint("TOP",   rHeader, "TOP",   0, -7)
    rLine:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)

    -- Per-player interrupt bars
    local players = {}
    if session.interrupts and session.interrupts.players then
        for _, p in ipairs(session.interrupts.players) do
            table.insert(players, p)
        end
        table.sort(players, function(a, b)
            return (a.intercepted or 0) > (b.intercepted or 0)
        end)
    end

    local irY = -22
    if #players == 0 then
        local noneFs = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noneFs:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, irY)
        noneFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        noneFs:SetText("No interrupt data")
    else
        local maxInt = 1
        for _, p in ipairs(players) do
            maxInt = math.max(maxInt, p.intercepted or 0)
        end

        for _, p in ipairs(players) do
            if irY < -(COL_H - 10) then break end

            local pr, pg, pb = classColor(p.playerClass)

            -- Player name
            local pNameFs = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pNameFs:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, irY)
            pNameFs:SetTextColor(pr, pg, pb)
            pNameFs:SetText(p.playerName or "Unknown")

            -- Count (right-aligned)
            local countFs = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            countFs:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, irY)
            countFs:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
            countFs:SetText(string.format("%d/%d", p.intercepted or 0, p.total or 0))
            irY = irY - 16

            -- Progress bar
            local barBg = CreateFrame("Frame", nil, rightCol)
            barBg:SetPoint("TOPLEFT",  rightCol, "TOPLEFT",  0, irY)
            barBg:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, irY)
            barBg:SetHeight(8)
            setBg(barBg, C.bg.r, C.bg.g, C.bg.b)

            local fillW = maxInt > 0 and ((p.intercepted or 0) / maxInt) or 0
            if fillW > 0 then
                local fill = barBg:CreateTexture(nil, "OVERLAY")
                fill:SetPoint("TOPLEFT",    barBg, "TOPLEFT",    0, 0)
                fill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
                fill:SetRelativeWidth(fillW)
                fill:SetColorTexture(pr * 0.7, pg * 0.7, pb * 0.7)
            end

            -- Missed indicator (red portion at 100%)
            local missed = (p.total or 0) - (p.intercepted or 0)
            if missed > 0 then
                local missedPct = p.total and (missed / p.total) or 0
                local missFill = barBg:CreateTexture(nil, "OVERLAY")
                missFill:SetPoint("TOPRIGHT",    barBg, "TOPRIGHT",    0, 0)
                missFill:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", 0, 0)
                missFill:SetRelativeWidth(missedPct)
                missFill:SetColorTexture(C.red.r * 0.4, 0, 0)
            end

            irY = irY - 12
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hide / Clear
-- ---------------------------------------------------------------------------

function Overview:Hide(parent)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
end

function Overview:Clear(parent)
    self:Hide(parent)
end
