-- tabs/Timeline.lua — Boss Ability Timeline tab (Raid only)
--
-- Shows every boss cast in chronological order with an ALL / IMPORTANT / TRIVIAL
-- filter and an expandable per-player impact panel for the selected event.
-- Gated to Raid sessions (groupSize > 5); shows a placeholder for dungeons.

local addonName, CL = ...
local Timeline = {}
CL.Timeline = Timeline

CL.Frame:RegisterTab("timeline", "Timeline", Timeline)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Module-level state
-- ---------------------------------------------------------------------------

-- Filter key: "all" | "high" | "low"
local activeFilter = "all"
-- Phase filter: 0 = show all phases; positive integer = show only that phase index.
local activePhase  = 0
-- Index (1-based) of the currently expanded event row, or nil.
local expandedIdx  = nil

-- Importance tier → stripe colour (RGB fractions)
local IMP_COLOR = {
    high   = { C.red.r,    C.red.g,    C.red.b    },
    medium = { C.gold.r,   C.gold.g,   C.gold.b   },
    low    = { C.textSecondary.r, C.textSecondary.g, C.textSecondary.b },
}
local IMP_LABEL = { high = "HIGH", medium = "MED", low = "LOW" }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Format a large number as "1.23M", "456K", or "123,456".
local function fmtNum(n)
    n = math.floor(n or 0)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(n)
end

-- Format seconds-into-pull as "M:SS".
local function fmtPullTime(sec)
    sec = math.floor(sec or 0)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ---------------------------------------------------------------------------
-- Build detail panel for an expanded event
-- ---------------------------------------------------------------------------

local function buildDetailPanel(parent, ev, yOff)
    local impacts = ev.impacts or {}
    local deaths  = ev.deathsLinked or {}

    -- Panel height: header + (deaths summary) + rows
    local PANEL_H = 32 + (#impacts * 18) + (8)
    if #impacts == 0 then PANEL_H = 56 end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, yOff)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    panel:SetHeight(PANEL_H)
    setBg(panel, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    -- Left accent bar (matching importance colour)
    local imp = ev.importance or "low"
    local ic  = IMP_COLOR[imp] or IMP_COLOR.low
    local accent = panel:CreateTexture(nil, "BACKGROUND")
    accent:SetSize(2, PANEL_H)
    accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    accent:SetColorTexture(ic[1], ic[2], ic[3])

    local iy = -8

    -- Deaths summary line
    if #deaths > 0 then
        local dFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, iy)
        dFs:SetTextColor(C.red.r, C.red.g, C.red.b)
        dFs:SetText("Deaths linked: " .. table.concat(deaths, ", "))
        iy = iy - 18
    end

    -- Column header
    local hdrFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, iy)
    hdrFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    hdrFs:SetText("Player                         Dmg Taken   Died")
    iy = iy - 16

    if #impacts == 0 then
        local noneFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noneFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, iy)
        noneFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        noneFs:SetText("No direct player damage tracked for this cast.")
    else
        for _, impact in ipairs(impacts) do
            local cc = CL.Config.classColours[impact.playerClass] or { r = 0.84, g = 0.85, b = 0.91 }
            local nameStr = (impact.playerName or "Unknown"):sub(1, 28)
            local dmgStr  = fmtNum(impact.damageTaken or 0)
            local diedStr = impact.died and "|cffe84040 ☠|r" or ""

            local pFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pFs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, iy)
            pFs:SetFormattedText(
                "|cff%02x%02x%02x%-30s|r |cffe0e8f0%9s|r%s",
                math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255),
                nameStr,
                dmgStr,
                diedStr
            )
            iy = iy - 18
        end
    end

    return panel, PANEL_H
end

-- ---------------------------------------------------------------------------
-- Build one event row button
-- ---------------------------------------------------------------------------

local ROW_H = 24
local ROW_GAP = 2

local function buildEventRow(parent, ev, evIdx, yOff, isExpanded, onSelect)
    local imp = ev.importance or "low"
    local ic  = IMP_COLOR[imp] or IMP_COLOR.low

    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, yOff)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, 0)
    row:SetHeight(ROW_H)

    -- Background
    local bgTex = setBg(row, isExpanded and C.hover.r or C.cardBg.r,
                             isExpanded and C.hover.g or C.cardBg.g,
                             isExpanded and C.hover.b or C.cardBg.b)

    -- Importance stripe (left 3px)
    local stripe = row:CreateTexture(nil, "ARTWORK")
    stripe:SetSize(3, ROW_H)
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    stripe:SetColorTexture(ic[1], ic[2], ic[3])

    -- Time
    local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeFs:SetPoint("LEFT", row, "LEFT", 10, 0)
    timeFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    timeFs:SetText(fmtPullTime(ev.timeIntoPull))

    -- Importance badge
    local impFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    impFs:SetPoint("LEFT", row, "LEFT", 52, 0)
    impFs:SetTextColor(ic[1], ic[2], ic[3])
    impFs:SetText(IMP_LABEL[imp] or "???")

    -- Spell name
    local spellFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellFs:SetPoint("LEFT", row, "LEFT", 92, 0)
    spellFs:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
    spellFs:SetText((ev.spellName or "Unknown"):sub(1, 30))

    -- Caster name (middle column)
    local casterFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    casterFs:SetPoint("LEFT", row, "LEFT", 290, 0)
    casterFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    casterFs:SetText((ev.casterName or ""):sub(1, 20))

    -- Deaths
    local deaths = ev.deathsLinked or {}
    if #deaths > 0 then
        local deathFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deathFs:SetPoint("LEFT", row, "LEFT", 460, 0)
        deathFs:SetTextColor(C.red.r, C.red.g, C.red.b)
        deathFs:SetText(string.format("☠ %d", #deaths))
    end

    -- Players hit
    local impacts = ev.impacts or {}
    if #impacts > 0 then
        local hitFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hitFs:SetPoint("LEFT", row, "LEFT", 510, 0)
        hitFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        hitFs:SetText(string.format("%d hit", #impacts))
    end

    -- Total damage
    if (ev.totalDamageTaken or 0) > 0 then
        local dmgFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dmgFs:SetPoint("LEFT", row, "LEFT", 560, 0)
        dmgFs:SetTextColor(C.damage.r, C.damage.g, C.damage.b)
        dmgFs:SetText(fmtNum(ev.totalDamageTaken))
    end

    row:SetScript("OnClick", function() onSelect(evIdx) end)
    row:SetScript("OnEnter", function()
        bgTex:SetColorTexture(C.hover.r, C.hover.g, C.hover.b)
    end)
    row:SetScript("OnLeave", function()
        bgTex:SetColorTexture(
            isExpanded and C.hover.r or C.cardBg.r,
            isExpanded and C.hover.g or C.cardBg.g,
            isExpanded and C.hover.b or C.cardBg.b)
    end)

    return row
end

-- ---------------------------------------------------------------------------
-- Main render
-- ---------------------------------------------------------------------------

function Timeline:Render(parent)
    self:Clear(parent)

    local session = CL.Data:GetActiveSession()

    -- Raid-only gate
    if not session or not CL.Config:IsRaidSession(session) then
        local noticeF = CreateFrame("Frame", nil, parent)
        noticeF:SetAllPoints(parent)
        local noticeFs = noticeF:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noticeFs:SetPoint("CENTER", noticeF, "CENTER", 0, 0)
        noticeFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        noticeFs:SetJustifyH("CENTER")
        noticeFs:SetText("Timeline is available for Raid sessions only.\nSelect a Raid session in the History tab.")
        self._noticeFrame = noticeF
        return
    end

    local tl     = CL.Data:GetBossTimeline(session)
    local events = tl.events or {}

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    local yOff = -16

    -- Page title ---------------------------------------------------------------
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText("Boss Timeline")
    yOff = yOff - 28

    -- Pull duration + event count
    local durFs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durFs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff)
    durFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    durFs:SetFormattedText(
        "Pull: %s   ·   %d boss casts recorded",
        CL.Data:FormatDuration(tl.pullDurationSec or 0), #events)
    yOff = yOff - 24

    -- Filter buttons -----------------------------------------------------------
    local filterDefs = {
        { label = "ALL",       key = "all"  },
        { label = "IMPORTANT", key = "high" },
        { label = "TRIVIAL",   key = "low"  },
    }
    local btnFrames = {}
    local btnX = 16
    for _, fd in ipairs(filterDefs) do
        local btn = CreateFrame("Button", nil, content)
        btn:SetSize(94, 22)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", btnX, yOff)
        btnX = btnX + 100

        local btnBg  = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints(btn)
        local btnTxt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnTxt:SetAllPoints(btn)
        btnTxt:SetJustifyH("CENTER")
        btnTxt:SetText(fd.label)

        local function updateBtn()
            local active = (activeFilter == fd.key)
            btnBg:SetColorTexture(
                active and C.gold.r * 0.25 or C.panelBg.r,
                active and C.gold.g * 0.25 or C.panelBg.g,
                active and C.gold.b * 0.25 or C.panelBg.b)
            btnTxt:SetTextColor(
                active and C.gold.r or C.textSecondary.r,
                active and C.gold.g or C.textSecondary.g,
                active and C.gold.b or C.textSecondary.b)
        end
        updateBtn()
        table.insert(btnFrames, { update = updateBtn, key = fd.key })

        local fdKey = fd.key   -- capture for closure
        btn:SetScript("OnClick", function()
            activeFilter = fdKey
            expandedIdx  = nil
            for _, bf in ipairs(btnFrames) do bf.update() end
            Timeline:Render(parent)
        end)
    end
    yOff = yOff - 30

    -- Phase filter chips (only shown when phase data is present) ---------------
    local phases = tl.phases or {}
    if #phases > 0 then
        local phaseLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        phaseLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff + 2)
        phaseLabel:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        phaseLabel:SetText("PHASE:")

        local phaseBtns = {}
        local phX = 72

        local function makePhaseChip(label, phaseIdx)
            local pb = CreateFrame("Button", nil, content)
            pb:SetSize(94, 22)
            pb:SetPoint("TOPLEFT", content, "TOPLEFT", phX, yOff)
            phX = phX + 100

            local pbBg  = pb:CreateTexture(nil, "BACKGROUND")
            pbBg:SetAllPoints(pb)
            local pbTxt = pb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pbTxt:SetAllPoints(pb)
            pbTxt:SetJustifyH("CENTER")
            pbTxt:SetText(label)

            local function updatePb()
                local active = (activePhase == phaseIdx)
                pbBg:SetColorTexture(
                    active and C.blue.r * 0.25 or C.panelBg.r,
                    active and C.blue.g * 0.25 or C.panelBg.g,
                    active and C.blue.b * 0.25 or C.panelBg.b)
                pbTxt:SetTextColor(
                    active and C.blue.r or C.textSecondary.r,
                    active and C.blue.g or C.textSecondary.g,
                    active and C.blue.b or C.textSecondary.b)
            end
            updatePb()
            table.insert(phaseBtns, { update = updatePb, idx = phaseIdx })

            pb:SetScript("OnClick", function()
                activePhase = phaseIdx
                expandedIdx = nil
                for _, pb2 in ipairs(phaseBtns) do pb2.update() end
                Timeline:Render(parent)
            end)
        end

        -- "All Phases" chip (phaseIdx = 0)
        makePhaseChip("ALL PHASES", 0)
        for _, ph in ipairs(phases) do
            local lbl = ph.phaseName:upper()
            makePhaseChip(lbl, ph.index)
        end
        yOff = yOff - 30
    end

    -- Column header ------------------------------------------------------------
    local colHdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHdr:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff)
    colHdr:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    colHdr:SetText("Time   Tier   Spell                            Caster               ☠  Hit  Dmg")
    yOff = yOff - 18

    local divTex = content:CreateTexture(nil, "BACKGROUND")
    divTex:SetPoint("TOPLEFT",  content, "TOPLEFT",  16, yOff)
    divTex:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, 0)
    divTex:SetHeight(1)
    divTex:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    yOff = yOff - 6

    -- Apply filters (phase first, then importance) -----------------------------
    local filtered = {}
    for i, ev in ipairs(events) do
        -- Phase gate: skip if a specific phase is selected and event doesn't match.
        if activePhase > 0 and (ev.phaseIndex or 0) ~= activePhase then
            -- skip
        elseif activeFilter == "all" then
            table.insert(filtered, { ev = ev, origIdx = i })
        elseif activeFilter == "high" and (ev.importance == "high" or ev.importance == "medium") then
            table.insert(filtered, { ev = ev, origIdx = i })
        elseif activeFilter == "low" and ev.importance == "low" then
            table.insert(filtered, { ev = ev, origIdx = i })
        end
    end

    if #filtered == 0 then
        local emptyFs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyFs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff - 20)
        emptyFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        emptyFs:SetText("No events match the current filter.")
        content:SetHeight(math.abs(yOff - 60))
        return
    end

    -- Render event rows + inline detail panels ---------------------------------
    local function onSelectRow(idx)
        expandedIdx = (expandedIdx == idx) and nil or idx
        Timeline:Render(parent)
    end

    for fi, entry in ipairs(filtered) do
        local ev        = entry.ev
        local isExpand  = (expandedIdx == fi)

        -- Event row
        local row = buildEventRow(content, ev, fi, yOff, isExpand, onSelectRow)
        _ = row  -- used for side effects only
        yOff = yOff - ROW_H - ROW_GAP

        -- Inline detail panel when expanded
        if isExpand then
            local panel, panelH = buildDetailPanel(content, ev, yOff)
            _ = panel
            yOff = yOff - panelH - ROW_GAP
        end
    end

    content:SetHeight(math.abs(yOff) + 24)
end

function Timeline:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
    if self._noticeFrame then
        self._noticeFrame:Hide()
        self._noticeFrame = nil
    end
end

function Timeline:Clear(parent)
    self:Hide(parent)
end
