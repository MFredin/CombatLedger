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

--- Themed button: solid bg + centred text, swap colours on hover.
local function makeBtn(parent, text, bgR, bgG, bgB, txtR, txtG, txtB, hvR, hvG, hvB, hvTxtR, hvTxtG, hvTxtB)
    local btn = CreateFrame("Button", nil, parent)
    local bg  = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetColorTexture(bgR, bgG, bgB)
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints(btn)
    lbl:SetJustifyH("CENTER")
    lbl:SetText(text)
    lbl:SetTextColor(txtR, txtG, txtB)
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(hvR, hvG, hvB)
        lbl:SetTextColor(hvTxtR, hvTxtG, hvTxtB)
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(bgR, bgG, bgB)
        lbl:SetTextColor(txtR, txtG, txtB)
    end)
    return btn
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
-- Preset Builder section
-- ---------------------------------------------------------------------------

local TAB_OPTIONS = {
    { id = "overview",    label = "Overview"    },
    { id = "performance", label = "Performance" },
    { id = "deaths",      label = "Deaths"      },
    { id = "interrupts",  label = "Interrupts"  },
    { id = "cc",          label = "CC Coverage" },
    { id = "history",     label = "History"     },
    { id = "trends",      label = "Trends"      },
    { id = "timeline",    label = "Timeline"    },
}

local ROLE_OPTIONS = {
    { key = nil,      label = "All Roles" },
    { key = "TANK",   label = "Tank"      },
    { key = "HEALER", label = "Healer"    },
    { key = "DPS",    label = "DPS"       },
}

local function buildPresetBuilderCard(parent, yOff, onSaved)
    local CARD_H = 218
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, yOff)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)
    card:SetHeight(CARD_H)
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    local hdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    hdr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    hdr:SetText("PRESET BUILDER")

    -- Name input
    local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -28)
    nameLabel:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    nameLabel:SetText("Name:")

    local nameBox = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    nameBox:SetSize(220, 20)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetText("")

    -- Tab selector
    local tabRowLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tabRowLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -54)
    tabRowLabel:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    tabRowLabel:SetText("Opens tab:")

    local selectedTab = "overview"
    local tabBtns     = {}
    local tbX, tbY    = 10, -70

    for _, td in ipairs(TAB_OPTIONS) do
        local tb = CreateFrame("Button", nil, card)
        tb:SetSize(90, 18)
        tb:SetPoint("TOPLEFT", card, "TOPLEFT", tbX, tbY)
        tbX = tbX + 96
        if tbX > 700 then tbX = 10; tbY = tbY - 22 end

        local tbBg  = tb:CreateTexture(nil, "BACKGROUND"); tbBg:SetAllPoints(tb)
        local tbTxt = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tbTxt:SetAllPoints(tb); tbTxt:SetJustifyH("CENTER"); tbTxt:SetText(td.label)

        local tdId = td.id
        local function refreshTab()
            local a = (selectedTab == tdId)
            tbBg:SetColorTexture(a and C.gold.r*0.2 or C.panelBg.r, a and C.gold.g*0.2 or C.panelBg.g, a and C.gold.b*0.2 or C.panelBg.b)
            tbTxt:SetTextColor(a and C.gold.r or C.textSecondary.r, a and C.gold.g or C.textSecondary.g, a and C.gold.b or C.textSecondary.b)
        end
        refreshTab()
        table.insert(tabBtns, { refresh = refreshTab, id = tdId })
        tb:SetScript("OnClick", function()
            selectedTab = tdId
            for _, t in ipairs(tabBtns) do t.refresh() end
        end)
    end

    -- Role selector
    local roleRowLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleRowLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -118)
    roleRowLabel:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    roleRowLabel:SetText("Role filter:")

    local selectedRole = nil
    local roleBtns     = {}
    local rbX          = 10

    for _, rd in ipairs(ROLE_OPTIONS) do
        local rb = CreateFrame("Button", nil, card)
        rb:SetSize(80, 18)
        rb:SetPoint("TOPLEFT", card, "TOPLEFT", rbX, -136)
        rbX = rbX + 86

        local rbBg  = rb:CreateTexture(nil, "BACKGROUND"); rbBg:SetAllPoints(rb)
        local rbTxt = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rbTxt:SetAllPoints(rb); rbTxt:SetJustifyH("CENTER"); rbTxt:SetText(rd.label)

        local rdKey = rd.key
        local function refreshRole()
            local a = (selectedRole == rdKey)
            rbBg:SetColorTexture(a and C.blue.r*0.2 or C.panelBg.r, a and C.blue.g*0.2 or C.panelBg.g, a and C.blue.b*0.2 or C.panelBg.b)
            rbTxt:SetTextColor(a and C.blue.r or C.textSecondary.r, a and C.blue.g or C.textSecondary.g, a and C.blue.b or C.textSecondary.b)
        end
        refreshRole()
        table.insert(roleBtns, { refresh = refreshRole, key = rdKey })
        rb:SetScript("OnClick", function()
            selectedRole = rdKey
            for _, r in ipairs(roleBtns) do r.refresh() end
        end)
    end

    -- Status line
    local statusFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusFs:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -162)
    statusFs:SetText("")

    -- Save button
    local saveBtn = makeBtn(card, "Save Preset",
        C.goldDim.r * 0.3, C.goldDim.g * 0.3, C.goldDim.b * 0.3,
        C.gold.r, C.gold.g, C.gold.b,
        C.gold.r * 0.3, C.gold.g * 0.3, C.gold.b * 0.3,
        1, 1, 1)
    saveBtn:SetSize(120, 22)
    saveBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -180)
    saveBtn:SetScript("OnClick", function()
        local name = strtrim(nameBox:GetText())
        if name == "" then
            statusFs:SetTextColor(C.red.r, C.red.g, C.red.b)
            statusFs:SetText("Enter a preset name first.")
            return
        end
        for _, bp in ipairs(CL.Config.builtinPresets) do
            if bp.name == name then
                statusFs:SetTextColor(C.red.r, C.red.g, C.red.b)
                statusFs:SetText("Cannot overwrite a built-in preset.")
                return
            end
        end
        CL.Config:SaveCustomPreset(name, selectedTab, selectedRole)
        nameBox:SetText("")
        statusFs:SetTextColor(C.green.r, C.green.g, C.green.b)
        statusFs:SetFormattedText("|cff40e87aPreset \"%s\" saved.|r  Reopen /cl to see it in the filter bar.", name)
        if onSaved then onSaved() end
    end)

    return card, CARD_H
end

local function buildCustomPresetList(parent, yOff, onDelete)
    local custom = {}
    local profile = (CL.addon and CL.addon.db and CL.addon.db.profile) or {}
    for name, p in pairs(profile.customPresets or {}) do
        table.insert(custom, { name = name, preset = p })
    end
    table.sort(custom, function(a, b) return a.name < b.name end)
    if #custom == 0 then return nil, 0 end

    local ROW_H  = 26
    local CARD_H = 30 + #custom * ROW_H

    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  16, yOff)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)
    card:SetHeight(CARD_H)
    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    local hdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    hdr:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    hdr:SetText("CUSTOM PRESETS")

    local iy = -26
    for _, entry in ipairs(custom) do
        local nameFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFs:SetPoint("TOPLEFT", card, "TOPLEFT", 10, iy)
        nameFs:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
        nameFs:SetText(entry.name)

        local detFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        detFs:SetPoint("TOPLEFT", card, "TOPLEFT", 200, iy)
        detFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        local roleKey = (entry.preset.filters and entry.preset.filters.players and entry.preset.filters.players.role) or nil
        detFs:SetFormattedText("%s  /  %s", entry.preset.activeTab or "?", roleKey or "All Roles")

        local entryName = entry.name
        local delBtn = makeBtn(card, "Delete",
            C.borderSub.r, C.borderSub.g, C.borderSub.b,
            C.red.r, C.red.g, C.red.b,
            C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3,
            1, 1, 1)
        delBtn:SetSize(60, 18)
        delBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, iy + 2)
        delBtn:SetScript("OnClick", function()
            CL.Config:DeleteCustomPreset(entryName)
            if onDelete then onDelete() end
        end)

        iy = iy - ROW_H
    end

    return card, CARD_H
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

    local clearBtn = makeBtn(card, "Clear Local Data",
        C.red.r * 0.2, C.red.g * 0.2, C.red.b * 0.2,
        C.red.r, C.red.g, C.red.b,
        C.red.r * 0.35, C.red.g * 0.35, C.red.b * 0.35,
        1, 1, 1)
    clearBtn:SetSize(140, 22)
    clearBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
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
    _ = infoCard
    yOff = yOff - 88

    -- Preset Builder card
    local function reRender() Settings:Render(parent) end
    local builderCard, builderH = buildPresetBuilderCard(content, yOff, reRender)
    _ = builderCard
    yOff = yOff - builderH - 12

    -- Custom Presets list (only shown when at least one exists)
    local listCard, listH = buildCustomPresetList(content, yOff, reRender)
    _ = listCard
    if listH > 0 then yOff = yOff - listH - 12 end

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
            advToggleText:SetText("|cffe8a820[X]|r |cffe0e8f0Enable advanced features|r")
        else
            advToggleText:SetText("|cff6b7a9a[ ]|r |cff6b7a9aEnable advanced features|r")
        end
    end

    updateToggleText()

    local advYOff = yOff  -- capture before incrementing

    advToggle:SetScript("OnClick", function()
        advEnabled = not advEnabled
        if CL.addon and CL.addon.db then
            CL.addon.db.profile.advancedMode = advEnabled
        end
        updateToggleText()
        if advEnabled and not advCard then
            advCard = buildAdvancedSection(content, advYOff - 30, function()
                doClearLocalData()
            end)
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
