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
    return C.textPrimary.r, C.textPrimary.g, C.textPrimary.b
end

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------------
-- Build a single death card
--
-- prevCard : frame above this one, or nil for the first card.
--            Each card anchors TOPLEFT → prevCard BOTTOMLEFT so WoW moves
--            subsequent cards automatically when a card expands/collapses.
-- onToggle : callback fired after every height change so the caller can
--            recompute scroll-content height.
--
-- Returns  : the card Frame.
-- ---------------------------------------------------------------------------

local function buildDeathCard(parent, death, prevCard, onToggle)
    local CARD_HEADER_H = 32
    local ROW_H         = 18
    local CARD_W        = parent:GetWidth() - 32

    -- Card outer frame — anchor to bottom of the previous card (or parent top)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(CARD_W)
    card:SetHeight(CARD_HEADER_H)
    if prevCard then
        card:SetPoint("TOPLEFT", prevCard, "BOTTOMLEFT", 0, -8)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -44)
    end
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    -- Header
    local header = CreateFrame("Button", nil, card)
    header:SetHeight(CARD_HEADER_H)
    header:SetPoint("TOPLEFT",  card, "TOPLEFT")
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT")
    local cr, cg, cb = classColour(death.playerClass)
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(header)
    headerBg:SetColorTexture(cr * 0.3, cg * 0.3, cb * 0.3, 1)

    -- Class colour strip on left edge
    local strip = header:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(4)
    strip:SetPoint("TOPLEFT",    header, "TOPLEFT")
    strip:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
    strip:SetColorTexture(cr, cg, cb, 1)

    -- Header text: [SPEC] Name — Pull #N — Xm Ys in
    local spec = (death.playerSpec and #death.playerSpec > 0) and death.playerSpec or "???"
    local specAbbr = spec:sub(1, 3)
    local headerLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerLabel:SetPoint("LEFT", header, "LEFT", 12, 0)
    headerLabel:SetFormattedText(
        "|cff%02x%02x%02x[%s] %s|r  |cff6b7a9aPull #%d — %s in|r",
        cr * 255, cg * 255, cb * 255,
        specAbbr, death.playerName,
        death.pullNumber,
        CL.Data:FormatDuration(death.timeIntoPull)
    )

    -- Fatal spell badge on right
    local fatalLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fatalLabel:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    fatalLabel:SetFormattedText(
        "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:12:12|t |cffe84040%s (+%d overkill)|r",
        death.fatalSpellName, death.overkill)

    -- Content (timeline), shown/hidden on click
    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT",  header, "BOTTOMLEFT")
    content:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    content:Hide()

    -- HP bar (3 px colour bar at top of content)
    local hpBar = CreateFrame("Frame", nil, content)
    hpBar:SetHeight(3)
    hpBar:SetPoint("TOPLEFT",  content, "TOPLEFT")
    hpBar:SetPoint("TOPRIGHT", content, "TOPRIGHT")
    setBg(hpBar, 0.2, 0.2, 0.2)

    -- Build timeline rows
    local events  = death.events or {}
    local contentH = 6  -- top padding
    for i, ev in ipairs(events) do
        local row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(contentH + 3))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT")

        if ev.isFatal then
            setBg(row, 0.35, 0.1, 0.1, 1)
        elseif i % 2 == 0 then
            setBg(row, 0.06, 0.07, 0.09, 1)
        end

        -- Icon (D / H / skull)
        local icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        icon:SetWidth(20)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        if ev.isFatal then
            icon:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:12:12|t")
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
        hp:SetFormattedText("|cff6b7a9a%d%%|r", ev.estimatedHpAfter)

        contentH = contentH + ROW_H
    end

    -- Defensive note (available self-defensive was not used at time of death)
    local defNotes = {}
    for _, def in ipairs(death.availableDefensives or {}) do
        if def.available and not def.wasUsed then
            table.insert(defNotes, def.spellName .. " was available but not used")
        end
    end
    if #defNotes > 0 then
        contentH = contentH + 4
        local defNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        defNote:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -contentH)
        defNote:SetText("|cffffff00!! " .. table.concat(defNotes, "  |  ") .. "|r")
        contentH = contentH + 16
    end

    contentH = contentH + 6  -- bottom padding
    content:SetHeight(contentH)

    -- Toggle expand / collapse
    local expanded = false
    header:SetScript("OnClick", function()
        expanded = not expanded
        if expanded then
            content:Show()
            card:SetHeight(CARD_HEADER_H + contentH)
        else
            content:Hide()
            card:SetHeight(CARD_HEADER_H)
        end
        if onToggle then onToggle() end
    end)

    return card
end

-- ---------------------------------------------------------------------------
-- Scroll-content height recalculation
-- Called once at render time and again each time any card is toggled.
-- ---------------------------------------------------------------------------

local function recalcHeight(content, cards)
    local h = 44  -- space occupied by the encounter header above the first card
    for _, c in ipairs(cards) do
        h = h + c:GetHeight() + 8  -- 8 px gap between cards
    end
    content:SetHeight(h + 16)      -- 16 px bottom padding
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

    local session = CL.Data:GetActiveSession()
    local deaths  = CL.Data:GetDeaths(session)

    if #deaths == 0 then
        CL.Frame:ShowEmptyState("No deaths in this session.", "Well played.")
        return
    end

    -- Scrollable container
    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    -- Encounter header (fixed 44 px above the first card)
    local hdr = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -8)
    hdr:SetFormattedText("|cffe8a820%s|r  |cff6b7a9aPull #%d — %s — %d death(s)|r",
        session.encounterName,
        session.pullNumber,
        session.success and "Success" or "Wipe",
        #deaths)

    -- Build cards in an anchor chain
    local cards    = {}
    local prevCard = nil
    for _, death in ipairs(deaths) do
        local card = buildDeathCard(content, death, prevCard, function()
            recalcHeight(content, cards)
        end)
        table.insert(cards, card)
        prevCard = card
    end

    -- Initial scroll-content height (all cards collapsed)
    recalcHeight(content, cards)
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
