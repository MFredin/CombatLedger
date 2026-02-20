-- tabs/Settings.lua — Settings tab
--
-- Shows companion status info and provides advanced data management.
-- The "advanced features" section is hidden behind a toggle and stored
-- in the AceDB profile so the choice persists across sessions.

local addonName, CL = ...
local Settings = {}
CL.Settings = Settings

CL.Frame:RegisterTab("settings", "Settings", Settings)

local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function setBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function makeLabel(parent, text, x, y, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if r then fs:SetTextColor(r, g, b) end
    fs:SetText(text)
    return fs
end

-- ---------------------------------------------------------------------------
-- Build the status info card
-- ---------------------------------------------------------------------------

local function buildInfoCard(parent, yOff)
    local compVer    = CL.Data:GetCompanionVersion() or nil
    local sessCount  = CL.Data:GetSessionCount()
    local allCount   = #CL.Data:GetAllSessions()

    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, yOff)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)
    card:SetHeight(80)
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    local sectionHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sectionHdr:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    sectionHdr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    sectionHdr:SetText("COMPANION STATUS")

    if compVer then
        local verLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        verLine:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -24)
        verLine:SetFormattedText(
            "Version |cffe0e8f0%s|r     |cff6b7a9aSessions recorded:|r |cffe0e8f0%d|r",
            compVer, allCount)
    else
        local noComp = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noComp:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -24)
        noComp:SetText("|cffe84040Companion app not detected.|r  Run a fight after launching the app, then /reload.")
    end

    local noteLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLine:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -42)
    noteLine:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    noteLine:SetText("To configure the companion (WoW path, startup options), open the CombatLedger app.")

    -- Active sessions note
    if sessCount > 0 then
        local sesLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sesLine:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -58)
        sesLine:SetFormattedText("|cff6b7a9a%d session(s) available in current SavedVariables|r", sessCount)
    end

    return card
end

-- ---------------------------------------------------------------------------
-- Build the advanced section
-- ---------------------------------------------------------------------------

local function buildAdvancedSection(parent, yOff, onClear)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, yOff)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)
    card:SetHeight(96)
    setBg(card, 0.15, 0.04, 0.04)

    local dangerHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dangerHdr:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    dangerHdr:SetTextColor(C.red.r, C.red.g, C.red.b)
    dangerHdr:SetText("DANGER ZONE")

    local desc = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -24)
    desc:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, 0)
    desc:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    desc:SetText("Clear Local Data wipes session data from addon memory for this session.\nTo permanently purge all history use the companion app Settings tab.")

    local clearBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    clearBtn:SetSize(140, 22)
    clearBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
    clearBtn:SetText("Clear Local Data")
    clearBtn:SetScript("OnClick", function()
        onClear()
    end)

    return card
end

-- ---------------------------------------------------------------------------
-- Clear local data helper
-- ---------------------------------------------------------------------------

local function doClearLocalData(advToggleBtn, advCard)
    -- Wipe the in-memory DB and reinitialise the data layer.
    if CombatLedgerDB then
        CombatLedgerDB.sessions           = {}
        CombatLedgerDB.historicalSnapshots = {}
        CombatLedgerDB.trends             = nil
        CombatLedgerDB.distribution       = nil
    end
    CL.Data:Init()
    -- Refresh the current tab so all views show empty state.
    local tab = (CL.addon and CL.addon.db and CL.addon.db.profile.lastActiveTab) or "overview"
    CL.Frame:SwitchTab(tab)
end

-- ---------------------------------------------------------------------------
-- Tab render / hide
-- ---------------------------------------------------------------------------

function Settings:Render(parent)
    self:Clear(parent)

    local scrollFrame, content = CL.Frame:MakeScrollable(parent)
    self.scrollFrame = scrollFrame

    local yOff = -16

    -- Page title
    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText("Settings")
    yOff = yOff - 28

    -- Status card
    local infoCard = buildInfoCard(content, yOff)
    yOff = yOff - 88

    -- Advanced toggle
    local advProfile = (CL.addon and CL.addon.db and CL.addon.db.profile) or {}
    local advEnabled = advProfile.advancedMode or false

    local advToggle = CreateFrame("Button", nil, content)
    advToggle:SetSize(200, 22)
    advToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOff)

    local advToggleBg = advToggle:CreateTexture(nil, "BACKGROUND")
    advToggleBg:SetAllPoints(advToggle)
    advToggleBg:SetColorTexture(0, 0, 0, 0)

    local advToggleText = advToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    advToggleText:SetAllPoints(advToggle)
    advToggleText:SetJustifyH("LEFT")

    local advCard = nil  -- lazily created

    local function updateToggleText()
        advEnabled = (CL.addon and CL.addon.db and CL.addon.db.profile.advancedMode) or false
        if advEnabled then
            advToggleText:SetText("|cffe8a820[✓]|r |cffe0e8f0Enable advanced features|r")
        else
            advToggleText:SetText("|cff6b7a9a[  ]|r |cff6b7a9aEnable advanced features|r")
        end
    end

    updateToggleText()

    advToggle:SetScript("OnClick", function()
        advEnabled = not advEnabled
        if CL.addon and CL.addon.db then
            CL.addon.db.profile.advancedMode = advEnabled
        end
        updateToggleText()
        -- Show/hide the advanced card
        if advEnabled and not advCard then
            advCard = buildAdvancedSection(content, yOff - 30, function()
                doClearLocalData()
            end)
            content:SetHeight(math.abs(yOff - 30) + 96 + 24)
        end
        if advCard then
            if advEnabled then advCard:Show() else advCard:Hide() end
        end
    end)

    yOff = yOff - 30

    -- Pre-build advanced section (hidden if not enabled)
    advCard = buildAdvancedSection(content, yOff, function()
        doClearLocalData()
    end)
    if not advEnabled then
        advCard:Hide()
    end
    yOff = yOff - 104

    content:SetHeight(math.abs(yOff) + 24)
end

function Settings:Hide(parent)
    if self.scrollFrame then
        self.scrollFrame:Hide()
        self.scrollFrame = nil
    end
end

function Settings:Clear(parent)
    self:Hide(parent)
end
