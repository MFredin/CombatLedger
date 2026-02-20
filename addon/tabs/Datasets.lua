-- tabs/Datasets.lua — Datasets tab
--
-- Shows an aggregate view of all recorded encounters, grouped by boss and
-- difficulty.  Each encounter card is expandable to reveal the pull-by-pull
-- history with duration, deaths, interrupt rate, and result.

local addonName, CL = ...
local Datasets = {}
CL.Datasets = Datasets

CL.Frame:RegisterTab("datasets", "Datasets", Datasets)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CARD_W_PAD  = 32   -- total horizontal padding inside scroll content
local HEADER_H    = 36
local ROW_H       = 22

local DIFFICULTY_NAMES = {
    [1]  = "Normal",
    [2]  = "Heroic",
    [3]  = "Mythic",
    [8]  = "M+",
    [23] = "M+",
}

local function diffLabel(d)
    return DIFFICULTY_NAMES[d] or ("D" .. tostring(d))
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Group sessions by (encounterName, difficulty)
-- Returns an ordered list of group keys and a table keyed by group key.
-- ---------------------------------------------------------------------------

local function groupSessions(sessions)
    local order = {}
    local groups = {}

    for _, s in ipairs(sessions) do
        local name = (s.encounterName and #s.encounterName > 0) and s.encounterName or "Unknown"
        local diff = s.difficulty or 0
        local key  = name .. "|" .. diff

        if not groups[key] then
            table.insert(order, key)
            groups[key] = {
                encounterName = name,
                difficulty    = diff,
                pulls         = {},
                kills         = 0,
                wipes         = 0,
                bestTime      = math.huge,
                totalDeaths   = 0,
            }
        end

        local g = groups[key]
        table.insert(g.pulls, s)

        if s.success then
            g.kills    = g.kills + 1
            local dur  = s.durationSec or 0
            if dur > 0 and dur < g.bestTime then g.bestTime = dur end
        else
            g.wipes    = g.wipes + 1
        end
        g.totalDeaths = g.totalDeaths + (#(s.deaths or {}))
    end

    -- Sort pulls inside each group newest first
    for _, g in pairs(groups) do
        table.sort(g.pulls, function(a, b)
            return (a.startTime or 0) > (b.startTime or 0)
        end)
    end

    return order, groups
end

-- ---------------------------------------------------------------------------
-- Build an expandable encounter card
-- ---------------------------------------------------------------------------

local function buildEncounterCard(parent, group, prevCard, onToggle)
    local CARD_W = parent:GetWidth() - CARD_W_PAD

    -- Outer card frame
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(CARD_W)
    card:SetHeight(HEADER_H)
    if prevCard then
        card:SetPoint("TOPLEFT", prevCard, "BOTTOMLEFT", 0, -8)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -44)
    end
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    -- Header button
    local header = CreateFrame("Button", nil, card)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT",  card, "TOPLEFT")
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT")
    setBg(header, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    -- Gold accent left strip
    local strip = header:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(3)
    strip:SetPoint("TOPLEFT",    header, "TOPLEFT")
    strip:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    strip:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 1)

    -- Encounter name
    local nameFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFs:SetPoint("LEFT", header, "LEFT", 14, 0)
    nameFs:SetWidth(200)
    nameFs:SetText(group.encounterName)

    -- Difficulty badge
    local diffFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diffFs:SetPoint("LEFT", header, "LEFT", 222, 0)
    diffFs:SetWidth(40)
    diffFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    diffFs:SetText(diffLabel(group.difficulty))

    -- Pull count
    local pullsTotal = group.kills + group.wipes
    local pullsFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pullsFs:SetPoint("LEFT", header, "LEFT", 270, 0)
    pullsFs:SetWidth(80)
    pullsFs:SetFormattedText("|cff6b7a9a%d pull%s|r", pullsTotal, pullsTotal == 1 and "" or "s")

    -- Kill / wipe ratio
    local ratioFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ratioFs:SetPoint("LEFT", header, "LEFT", 358, 0)
    ratioFs:SetWidth(120)
    ratioFs:SetFormattedText(
        "|cff40e87a%d kill%s|r  |cffe84040%d wipe%s|r",
        group.kills, group.kills == 1 and "" or "s",
        group.wipes, group.wipes == 1 and "" or "s")

    -- Best kill time (only if there were kills)
    if group.kills > 0 and group.bestTime < math.huge then
        local bestFs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bestFs:SetPoint("LEFT", header, "LEFT", 488, 0)
        bestFs:SetWidth(100)
        bestFs:SetFormattedText("|cff6b7a9aBest:|r |cffe0e8f0%s|r",
            CL.Data:FormatDuration(group.bestTime))
    end

    -- Expand chevron on right
    local chevron = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chevron:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    chevron:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    chevron:SetText("▶")

    -- ── Content (pull list) ────────────────────────────────────────────────

    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT",  header, "BOTTOMLEFT")
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    content:Hide()

    -- Column header row
    local colHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -6)
    colHdr:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    colHdr:SetText("Pull   Date          Duration   Deaths   Int%   Result")

    local contentH = 6 + 16 + 4  -- top pad + col header + gap

    for i, pull in ipairs(group.pulls) do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -contentH)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT")
        if i % 2 == 0 then
            setBg(row, 0.06, 0.07, 0.09, 1)
        end

        -- Pull number
        local pullNumFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pullNumFs:SetWidth(36)
        pullNumFs:SetPoint("LEFT", row, "LEFT", 10, 0)
        pullNumFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        pullNumFs:SetText(tostring(pull.pullNumber or i))

        -- Date
        local dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateFs:SetWidth(88)
        dateFs:SetPoint("LEFT", row, "LEFT", 50, 0)
        dateFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        if pull.startTime and pull.startTime > 0 then
            dateFs:SetText(date("%m/%d %H:%M", pull.startTime))
        else
            dateFs:SetText("|cff3d4a62—|r")
        end

        -- Duration
        local durFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durFs:SetWidth(80)
        durFs:SetPoint("LEFT", row, "LEFT", 142, 0)
        durFs:SetText(CL.Data:FormatDuration(pull.durationSec or 0))

        -- Deaths
        local dCount = #(pull.deaths or {})
        local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deathFs:SetWidth(60)
        deathFs:SetPoint("LEFT", row, "LEFT", 226, 0)
        if dCount > 0 then
            deathFs:SetTextColor(C.red.r, C.red.g, C.red.b)
            deathFs:SetText(tostring(dCount))
        else
            deathFs:SetText("|cff40b870✓|r")
        end

        -- Interrupt rate
        local intRate = (pull.interrupts and pull.interrupts.summary
            and pull.interrupts.summary.ratePercent) or 0
        local intFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        intFs:SetWidth(50)
        intFs:SetPoint("LEFT", row, "LEFT", 290, 0)
        local ir = intRate >= 80 and C.green.r or C.textSecondary.r
        local ig = intRate >= 80 and C.green.g or C.textSecondary.g
        local ib = intRate >= 80 and C.green.b or C.textSecondary.b
        intFs:SetTextColor(ir, ig, ib)
        intFs:SetFormattedText("%.0f%%", intRate)

        -- Result
        local resultFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        resultFs:SetWidth(70)
        resultFs:SetPoint("LEFT", row, "LEFT", 346, 0)
        if pull.success then
            resultFs:SetText("|cff40e87aSuccess|r")
        else
            resultFs:SetText("|cffe84040Wipe|r")
        end

        contentH = contentH + ROW_H
    end

    contentH = contentH + 8  -- bottom padding
    content:SetHeight(contentH)

    -- ── Toggle expand / collapse ───────────────────────────────────────────

    local expanded = false
    header:SetScript("OnClick", function()
        expanded = not expanded
        if expanded then
            chevron:SetText("▼")
            content:Show()
            card:SetHeight(HEADER_H + contentH)
        else
            chevron:SetText("▶")
            content:Hide()
            card:SetHeight(HEADER_H)
        end
        if onToggle then onToggle() end
    end)

    return card
end

-- ---------------------------------------------------------------------------
-- Scroll-content height recalculation
-- ---------------------------------------------------------------------------

local function recalcHeight(content, cards)
    local h = 44
    for _, c in ipairs(cards) do
        h = h + c:GetHeight() + 8
    end
    content:SetHeight(h + 16)
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Datasets:Render(parent)
    self:Clear(parent)

    local allSessions = CL.Data:GetAllSessions()

    if #allSessions == 0 then
        if not (CombatLedgerDB) then
            CL.Frame:ShowEmptyState("No data available.", "Companion app not detected.")
        else
            CL.Frame:ShowEmptyState("No sessions recorded yet.", "Run a dungeon then /reload.")
        end
        return
    end
    CL.Frame:HideEmptyState()

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    local order, groups = groupSessions(allSessions)

    -- Page header
    local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -8)
    hdr:SetFormattedText(
        "|cffe8a820Datasets|r  |cff6b7a9a%d encounter%s  •  %d total pull%s|r",
        #order, #order == 1 and "" or "s",
        #allSessions, #allSessions == 1 and "" or "s")

    -- Build one card per encounter group
    local cards    = {}
    local prevCard = nil

    for _, key in ipairs(order) do
        local group = groups[key]
        local card  = buildEncounterCard(content, group, prevCard, function()
            recalcHeight(content, cards)
        end)
        table.insert(cards, card)
        prevCard = card
    end

    recalcHeight(content, cards)
end

function Datasets:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Datasets:Clear(parent)
    self:Hide(parent)
end
