-- core/Frame.lua — Main addon frame, tab system, filter bar
-- 960×600 px movable frame with tab bar and filter area.

local addonName, CL = ...
CL.Frame = {}

local Frame = CL.Frame
local C = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Tab registry — each tab registers itself here.
-- ---------------------------------------------------------------------------

Frame.tabs = {}       -- ordered list of tab IDs
Frame.tabDefs = {}    -- id → { label, module }
Frame.tabButtons = {} -- id → button widget

local FRAME_W, FRAME_H = 960, 600
local TITLE_H, TABBAR_H, FILTER_H = 42, 38, 38

-- ---------------------------------------------------------------------------
-- Helper: create a coloured background texture on a frame
-- ---------------------------------------------------------------------------

local function setBg(f, r, g, b, a)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Frame:Init()
    if self.mainFrame then return end

    -- Main frame
    local f = CreateFrame("Frame", "CombatLedgerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        CL.addon.db.profile.framePoint = { point = point, x = x, y = y }
    end)
    f:Hide()
    setBg(f, C.bg.r, C.bg.g, C.bg.b)
    self.mainFrame = f

    -- Restore saved position
    local fp = CL.addon.db.profile.framePoint
    if fp then
        f:ClearAllPoints()
        f:SetPoint(fp.point, UIParent, fp.point, fp.x, fp.y)
    end

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    titleBar:SetHeight(TITLE_H)
    setBg(titleBar, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    titleText:SetText("|cffe8a820CombatLedger|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Version label
    local verLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verLabel:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    verLabel:SetText("|cff888888v0.1.0|r")

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    tabBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
    tabBar:SetHeight(TABBAR_H)
    setBg(tabBar, C.panelBg.r, C.panelBg.g, C.panelBg.b)
    self.tabBar = tabBar

    -- Filter bar
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT")
    filterBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT")
    filterBar:SetHeight(FILTER_H)
    setBg(filterBar, C.cardBg.r, C.cardBg.g, C.cardBg.b)
    self.filterBar = filterBar

    -- Content area
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT")
    contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    self.contentArea = contentArea

    -- Build tab buttons from registered tabs
    self:BuildTabButtons()

    -- Build preset selector in filter bar
    self:BuildPresetSelector(filterBar)

    -- Show companion-not-detected message if needed
    self:BuildEmptyState()

    -- Open at last active tab
    local lastTab = CL.addon.db.profile.lastActiveTab or "overview"
    self:SwitchTab(lastTab)
end

-- ---------------------------------------------------------------------------
-- Tab registration (called by tab modules)
-- ---------------------------------------------------------------------------

function Frame:RegisterTab(id, label, module)
    if not self.tabDefs[id] then
        table.insert(self.tabs, id)
    end
    self.tabDefs[id] = { label = label, module = module }
end

-- ---------------------------------------------------------------------------
-- Build tab buttons
-- ---------------------------------------------------------------------------

function Frame:BuildTabButtons()
    local x = 8
    for _, id in ipairs(self.tabs) do
        local def = self.tabDefs[id]
        if def then
            local btn = CreateFrame("Button", nil, self.tabBar)
            btn:SetHeight(TABBAR_H - 4)
            btn:SetWidth(100)
            btn:SetPoint("LEFT", self.tabBar, "LEFT", x, 0)
            x = x + 104

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            bg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetAllPoints(btn)
            label:SetText(def.label)

            btn:SetScript("OnClick", function()
                self:SwitchTab(id)
            end)
            btn:SetScript("OnEnter", function()
                bg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b)
            end)
            btn:SetScript("OnLeave", function()
                bg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)
            end)

            self.tabButtons[id] = { btn = btn, bg = bg, label = label }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Preset selector in filter bar (Task 2.5)
-- ---------------------------------------------------------------------------

function Frame:BuildPresetSelector(filterBar)
    local presetLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetPoint("LEFT", filterBar, "LEFT", 8, 0)
    presetLabel:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    presetLabel:SetText("Preset:")

    local x = 58
    self.presetButtons = {}

    local presets = CL.Config:GetPresets()
    for _, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, filterBar)
        btn:SetSize(110, 26)
        btn:SetPoint("LEFT", filterBar, "LEFT", x, 0)
        x = x + 114

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints(btn)
        lbl:SetText(preset.name)

        local presetName = preset.name
        btn:SetScript("OnClick", function()
            CL.Config:ApplyPreset(presetName)
            self:RefreshPresetHighlight()
        end)
        btn:SetScript("OnEnter", function()
            bg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b)
        end)
        btn:SetScript("OnLeave", function()
            self:RefreshPresetHighlight()
        end)

        self.presetButtons[presetName] = { btn = btn, bg = bg, lbl = lbl }
    end

    self:RefreshPresetHighlight()
end

function Frame:RefreshPresetHighlight()
    local active = CL.Config:GetActivePreset()
    for name, pbtn in pairs(self.presetButtons or {}) do
        if name == active then
            pbtn.bg:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
            pbtn.lbl:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            pbtn.bg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)
            pbtn.lbl:SetTextColor(0.75, 0.75, 0.75)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tab switching
-- ---------------------------------------------------------------------------

function Frame:SwitchTab(id)
    -- Deactivate all
    for tid, tbtn in pairs(self.tabButtons) do
        tbtn.bg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)
        tbtn.label:SetTextColor(0.8, 0.8, 0.8)
        local def = self.tabDefs[tid]
        if def and def.module and def.module.Hide then
            def.module:Hide(self.contentArea)
        end
    end

    -- Activate selected
    local tbtn = self.tabButtons[id]
    if tbtn then
        tbtn.bg:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
        tbtn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    end

    local def = self.tabDefs[id]
    if def and def.module then
        def.module:Render(self.contentArea)
    end

    CL.addon.db.profile.lastActiveTab = id
    self.activeTab = id
end

-- ---------------------------------------------------------------------------
-- Empty state
-- ---------------------------------------------------------------------------

function Frame:BuildEmptyState()
    local f = CreateFrame("Frame", nil, self.contentArea)
    f:SetAllPoints(self.contentArea)
    self.emptyState = f

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    msg:SetPoint("CENTER", f, "CENTER", 0, 20)
    msg:SetTextColor(0.6, 0.6, 0.6)
    self.emptyMsg = msg

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", msg, "BOTTOM", 0, -8)
    sub:SetTextColor(0.4, 0.4, 0.4)
    self.emptySub = sub
end

function Frame:ShowEmptyState(main, sub)
    if self.emptyState then
        self.emptyMsg:SetText(main)
        self.emptySub:SetText(sub or "")
        self.emptyState:Show()
    end
end

function Frame:HideEmptyState()
    if self.emptyState then
        self.emptyState:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------

function Frame:Toggle()
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
        -- Refresh content
        if self.activeTab then
            self:SwitchTab(self.activeTab)
        end
    end
end
