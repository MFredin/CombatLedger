-- tabs/Deaths.lua — Death recap tab (Task 1.10)
--
-- Renders one expandable card per death event with:
--   • Class-coloured header (player name, spec, pull #, time-into-pull)
--   • Timeline of last 10s damage/heal events
--   • Running HP bar
--   • Fatal event highlighted with red tint
--   • Defensive availability note

local addonName, CL = ...
local Deaths = {}
CL.Deaths = Deaths

CL.Frame:RegisterTab("deaths", "Deaths", Deaths)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function classColour(cls)
    local cc = CL.Config.classColours[cls]
    if cc then return cc.r, cc.g, cc.b end
    return 0.8, 0.8, 0.8
end

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Build a single death card
-- ---------------------------------------------------------------------------

local function buildDeathCard(parent, death, yOffset)
    local CARD_HEADER_H = 32
    local ROW_H = 18
    local CARD_W = parent:GetWidth() - 32

    -- Card outer frame
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(CARD_W)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    -- Header
    local header = CreateFrame("Button", nil, card)
    header:SetHeight(CARD_HEADER_H)
    header:SetPoint("TOPLEFT", card, "TOPLEFT")
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT")
    local cr, cg, cb = classColour(death.playerClass)
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(cr * 0.3, cg * 0.3, cb * 0.3, 1)

    -- Class colour strip on left edge
    local strip = header:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(4)
    strip:SetPoint("TOPLEFT", header, "TOPLEFT")
    strip:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    strip:SetColorTexture(cr, cg, cb, 1)

    -- Header text: [SPEC] Name — Pull #N — Xm Ys in
    local specAbbr = (death.playerSpec or "???"):sub(1, 3)
    local headerLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerLabel:SetPoint("LEFT", header, "LEFT", 12, 0)
    headerLabel:SetFormattedText(
        "|cff%02x%02x%02x[%s] %s|r  |cff888888Pull #%d — %s in|r",
        cr * 255, cg * 255, cb * 255,
        specAbbr, death.playerName,
        death.pullNumber,
        CL.Data:FormatDuration(death.timeIntoPull)
    )

    -- Fatal spell badge on right
    local fatalLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fatalLabel:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    fatalLabel:SetFormattedText("|cffe84040☠ %s (+%d overkill)|r",
        death.fatalSpellName, death.overkill)

    -- Content (timeline), shown/hidden on click
    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    content:Hide()

    -- HP bar (3px colour bar at top of content)
    local hpBar = CreateFrame("Frame", nil, content)
    hpBar:SetHeight(3)
    hpBar:SetPoint("TOPLEFT", content, "TOPLEFT")
    hpBar:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    setBg(hpBar, 0.2, 0.2, 0.2)

    -- Build timeline rows
    local events = death.events or {}
    local totalH = 6 -- top padding
    local rows = {}
    for i, ev in ipairs(events) do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(totalH + 3))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT")

        if ev.isFatal then
            setBg(row, 0.35, 0.1, 0.1, 1)
        elseif i % 2 == 0 then
            setBg(row, 0.06, 0.07, 0.09, 1)
        end

        -- Icon (D/H/☠)
        local icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        icon:SetWidth(20)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        if ev.isFatal then
            icon:SetText("|cffe84040☠|r")
        elseif ev.type == "damage" then
            icon:SetText("|cffe84040D|r")
        else
            icon:SetText("|cff40e87aH|r")
        end

        -- Source
        local src = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        src:SetWidth(120)
        src:SetPoint("LEFT", row, "LEFT", 28, 0)
        src:SetText(ev.sourceName or "")

        -- Spell
        local spell = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        spell:SetWidth(150)
        spell:SetPoint("LEFT", row, "LEFT", 152, 0)
        spell:SetText(ev.spellName or "")

        -- Amount
        local amt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        amt:SetWidth(80)
        amt:SetPoint("LEFT", row, "LEFT", 306, 0)
        if ev.type == "damage" then
            amt:SetText(string.format("|cffe84040-%d|r", ev.amount))
        else
            amt:SetText(string.format("|cff40e87a+%d|r", ev.amount))
        end

        -- HP after
        local hp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hp:SetWidth(60)
        hp:SetPoint("LEFT", row, "LEFT", 390, 0)
        hp:SetFormattedText("|cff888888%d%%|r", ev.estimatedHpAfter)

        totalH = totalH + ROW_H
        table.insert(rows, row)
    end

    -- Defensive note (if any available defensive was unused)
    local defNotes = {}
    for _, def in ipairs(death.availableDefensives or {}) do
        if def.available and not def.wasUsed then
            table.insert(defNotes, def.spellName .. " was available but not used")
        end
    end
    if #defNotes > 0 then
        totalH = totalH + 4
        local defNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        defNote:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -(totalH))
        defNote:SetText("|cffffff00⚠ " .. table.concat(defNotes, "  |  ") .. "|r")
        totalH = totalH + 16
    end

    totalH = totalH + 6
    content:SetHeight(totalH)
    card:SetHeight(CARD_HEADER_H + (content:IsShown() and totalH or 0))

    -- Toggle expand/collapse on header click
    local expanded = false
    header:SetScript("OnClick", function()
        expanded = not expanded
        if expanded then
            content:Show()
            card:SetHeight(CARD_HEADER_H + totalH)
        else
            content:Hide()
            card:SetHeight(CARD_HEADER_H)
        end
    end)

    -- Return total height consumed
    return CARD_HEADER_H + 4
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Deaths:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        CL.Frame:ShowEmptyState(
            "No data available.",
            CombatLedgerDB and "No sessions recorded yet." or "Companion app not detected."
        )
        return
    end
    CL.Frame:HideEmptyState()

    local session = CL.Data:GetLatestSession()
    local deaths = CL.Data:GetDeaths(session)

    if #deaths == 0 then
        CL.Frame:ShowEmptyState("No deaths in this session.", "Well played.")
        return
    end

    -- Scrollable container
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetAllPoints(parent)
    self.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(parent:GetWidth() - 28)
    scrollFrame:SetScrollChild(content)

    -- Encounter header
    local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -8)
    hdr:SetFormattedText("|cffe8a820%s|r  |cff888888Pull #%d — %s — %d death(s)|r",
        session.encounterName,
        session.pullNumber,
        session.success and "Success" or "Wipe",
        #deaths)

    local yOffset = -44
    for _, death in ipairs(deaths) do
        local cardH = buildDeathCard(content, death, yOffset)
        yOffset = yOffset - cardH - 8
    end

    content:SetHeight(math.abs(yOffset) + 16)
end

function Deaths:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Deaths:Clear(parent)
    self:Hide(parent)
end
