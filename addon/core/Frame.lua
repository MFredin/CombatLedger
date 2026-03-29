-- core/Frame.lua — Main addon frame, tab system, filter bar
--
-- Visual design mirrors the CombatLedger HTML mockup:
--   • Deep navy/black layered backgrounds (#0a0c10 → #0f1219 → #141820)
--   • Gold accent (#e8a820) corner brackets, active-tab underline, encounter header stripe
--   • Underline-style tabs (2px gold bottom border + glow background when active)
--   • Hex-style "CL" logo mark in the titlebar
--   • Bottom status bar with version and companion sync info
--   • 1px border separators between all structural sections

local addonName, CL = ...
CL.Frame = {}

local Frame = CL.Frame
local C     = CL.Config.colours

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local FRAME_W  = 960
local FRAME_H  = 600
local TITLE_H  = 46   -- titlebar (logo + title + session badge)
local TABBAR_H = 36   -- tab row
local FILTER_H = 36   -- preset filter row
local BOTTOM_H = 30   -- status bar

-- ---------------------------------------------------------------------------
-- Tab registry — each tab module registers itself here before Frame:Init().
-- ---------------------------------------------------------------------------

Frame.tabs       = {}   -- ordered list of tab IDs
Frame.tabDefs    = {}   -- id → { label, module }
Frame.tabButtons = {}   -- id → { btn, bg, label, underline }

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

--- Solid background texture on a frame (BACKGROUND layer).
local function setBg(f, r, g, b, a)
    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(f)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

--- 1-pixel horizontal separator line anchored to the bottom of `parent`.
local function addHSeparator(parent, r, g, b)
    r, g, b = r or C.borderSub.r, g or C.borderSub.g, b or C.borderSub.b
    local sep = parent:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(r, g, b)
    return sep
end

--- 1-pixel horizontal separator at the TOP of a frame.
local function addHSeparatorTop(f, r, g, b)
    r, g, b = r or C.borderSub.r, g or C.borderSub.g, b or C.borderSub.b
    local sep = f:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    sep:SetColorTexture(r, g, b)
    return sep
end

--- Gold L-shaped corner bracket (16 × 16 px, 2px thick lines).
--  @param parent  The frame to anchor to.
--  @param corner  "TL" | "TR" | "BL" | "BR"
local function makeCorner(parent, corner)
    local SIZE = 16
    local THICK = 2
    local r, g, b = C.gold.r, C.gold.g, C.gold.b

    -- Horizontal bar of the L
    local hBar = parent:CreateTexture(nil, "OVERLAY")
    hBar:SetHeight(THICK)
    hBar:SetWidth(SIZE)
    hBar:SetColorTexture(r, g, b)

    -- Vertical bar of the L
    local vBar = parent:CreateTexture(nil, "OVERLAY")
    vBar:SetWidth(THICK)
    vBar:SetHeight(SIZE)
    vBar:SetColorTexture(r, g, b)

    if corner == "TL" then
        hBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        vBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    elseif corner == "TR" then
        hBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        vBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    elseif corner == "BL" then
        hBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        vBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    elseif corner == "BR" then
        hBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        vBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function Frame:Init()
    if self.mainFrame then return end

    -- ── Main frame ────────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "CombatLedgerMainFrame", UIParent)
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        CL.addon.db.profile.framePoint = { point = point, x = x, y = y }
    end)
    f:Hide()
    f:SetFrameStrata("HIGH")

    -- Panel background
    setBg(f, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    -- 1px outer border (border-light #252d40)
    local outerBorder = f:CreateTexture(nil, "OVERLAY")
    outerBorder:SetAllPoints(f)
    outerBorder:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b, 0)
    -- WoW can't do outline-only textures easily; we fake it with 4 edge strips:
    local function edgeStrip(point, w, h)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
        t:SetPoint(point, f, point, 0, 0)
        if w then t:SetWidth(w) t:SetPoint(point == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT", f, point == "TOPRIGHT" and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, 0) end
        if h then t:SetHeight(h) end
    end
    -- Left edge
    local le = f:CreateTexture(nil, "OVERLAY"); le:SetWidth(1); le:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    le:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); le:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    -- Right edge
    local re = f:CreateTexture(nil, "OVERLAY"); re:SetWidth(1); re:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    re:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); re:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    -- Top edge
    local te = f:CreateTexture(nil, "OVERLAY"); te:SetHeight(1); te:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    te:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); te:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    -- Bottom edge
    local be = f:CreateTexture(nil, "OVERLAY"); be:SetHeight(1); be:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    be:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); be:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    -- Gold corner brackets
    makeCorner(f, "TL")
    makeCorner(f, "TR")
    makeCorner(f, "BL")
    makeCorner(f, "BR")

    self.mainFrame = f

    -- Restore saved position
    local fp = CL.addon and CL.addon.db and CL.addon.db.profile.framePoint
    if fp then
        f:ClearAllPoints()
        f:SetPoint(fp.point, UIParent, fp.point, fp.x, fp.y)
    end

    -- ── Titlebar ──────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(TITLE_H)
    -- Gradient background (#0d1018 → #111520)
    setBg(titleBar, 0.051, 0.063, 0.094)
    addHSeparator(titleBar, C.borderVis.r, C.borderVis.g, C.borderVis.b)

    -- Hex logo mark: 28×28 gold square with "CL" text
    local logoMark = CreateFrame("Frame", nil, titleBar)
    logoMark:SetSize(28, 28)
    logoMark:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    local logoBg = logoMark:CreateTexture(nil, "BACKGROUND")
    logoBg:SetAllPoints(logoMark)
    logoBg:SetColorTexture(C.gold.r, C.gold.g, C.gold.b)
    local logoText = logoMark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logoText:SetAllPoints(logoMark)
    logoText:SetText("|cff000000CL|r")
    logoText:SetJustifyH("CENTER")
    logoText:SetJustifyV("MIDDLE")

    -- Addon title: "COMBAT" plain + "LEDGER" in gold
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", logoMark, "RIGHT", 8, 8)
    titleText:SetText("COMBAT|cffe8a820LEDGER|r")

    -- Sub-label: "POST-COMBAT ANALYSIS ENGINE"
    local subLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subLabel:SetPoint("LEFT", logoMark, "RIGHT", 9, -12)
    subLabel:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    subLabel:SetText("POST-COMBAT ANALYSIS ENGINE")

    -- Close button (right side)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -10, 0)
    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints(closeBtn)
    closeBg:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    local closeX = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeX:SetAllPoints(closeBtn)
    closeX:SetText("X")
    closeX:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBg:SetColorTexture(C.red.r, C.red.g, C.red.b, 0.6) closeX:SetTextColor(1, 1, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBg:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b) closeX:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b) end)

    -- ── Encounter selector button (replaces the static session badge) ────────
    -- Clicking it opens a scrollable pull-picker dropdown, similar to Details!
    local selBtn = CreateFrame("Button", nil, titleBar)
    selBtn:SetSize(270, 22)
    selBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)

    local selBg = selBtn:CreateTexture(nil, "BACKGROUND")
    selBg:SetAllPoints(selBtn)
    selBg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b)

    -- 1-px border
    local sbt = selBtn:CreateTexture(nil, "BORDER"); sbt:SetHeight(1); sbt:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); sbt:SetPoint("TOPLEFT", selBtn, "TOPLEFT"); sbt:SetPoint("TOPRIGHT", selBtn, "TOPRIGHT")
    local sbb = selBtn:CreateTexture(nil, "BORDER"); sbb:SetHeight(1); sbb:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); sbb:SetPoint("BOTTOMLEFT", selBtn, "BOTTOMLEFT"); sbb:SetPoint("BOTTOMRIGHT", selBtn, "BOTTOMRIGHT")
    local sbl = selBtn:CreateTexture(nil, "BORDER"); sbl:SetWidth(1);  sbl:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); sbl:SetPoint("TOPLEFT", selBtn, "TOPLEFT"); sbl:SetPoint("BOTTOMLEFT", selBtn, "BOTTOMLEFT")
    local sbr = selBtn:CreateTexture(nil, "BORDER"); sbr:SetWidth(1);  sbr:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); sbr:SetPoint("TOPRIGHT", selBtn, "TOPRIGHT"); sbr:SetPoint("BOTTOMRIGHT", selBtn, "BOTTOMRIGHT")

    local selText = selBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selText:SetPoint("LEFT",  selBtn, "LEFT",  6, 0)
    selText:SetPoint("RIGHT", selBtn, "RIGHT", -14, 0)
    selText:SetJustifyH("LEFT")
    selText:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    selText:SetText("NO DATA")

    local chevron = selBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chevron:SetPoint("RIGHT", selBtn, "RIGHT", -3, 0)
    chevron:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    chevron:SetText("▾")

    -- sessionBadge alias — UpdateSessionBadge writes here
    self.sessionBadge = selText

    selBtn:SetScript("OnEnter", function() selBg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b) end)
    selBtn:SetScript("OnLeave", function() selBg:SetColorTexture(C.cardBg.r, C.cardBg.g, C.cardBg.b) end)
    selBtn:SetScript("OnClick", function() self:ToggleEncounterDropdown() end)

    -- ── Tab bar ───────────────────────────────────────────────────────────
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, -1)
    tabBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -1)
    tabBar:SetHeight(TABBAR_H)
    setBg(tabBar, C.bg.r, C.bg.g, C.bg.b)  -- darkest bg (#0a0c10)
    addHSeparator(tabBar, C.borderSub.r, C.borderSub.g, C.borderSub.b)
    self.tabBar = tabBar

    -- ── Filter / preset bar ───────────────────────────────────────────────
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT",  tabBar, "BOTTOMLEFT",  0, -1)
    filterBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -1)
    filterBar:SetHeight(FILTER_H)
    setBg(filterBar, C.cardBg.r, C.cardBg.g, C.cardBg.b)
    addHSeparator(filterBar, C.borderSub.r, C.borderSub.g, C.borderSub.b)
    self.filterBar = filterBar

    -- ── Bottom status bar ─────────────────────────────────────────────────
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1, 1)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    bottomBar:SetHeight(BOTTOM_H)
    setBg(bottomBar, C.bg.r, C.bg.g, C.bg.b)
    addHSeparatorTop(bottomBar, C.borderSub.r, C.borderSub.g, C.borderSub.b)

    local verLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verLabel:SetPoint("LEFT", bottomBar, "LEFT", 12, 0)
    verLabel:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    verLabel:SetText("CombatLedger v1.3.6  ·  Requires Companion >= 1.3.6")

    -- "Reload Data" button — shows a confirmation popup then calls ReloadUI().
    -- Anchored to the far right; companionStatus sits to its left.
    local reloadBtn = CreateFrame("Button", nil, bottomBar)
    reloadBtn:SetSize(106, 20)
    reloadBtn:SetPoint("RIGHT", bottomBar, "RIGHT", -10, 0)

    local rBg = reloadBtn:CreateTexture(nil, "BACKGROUND")
    rBg:SetAllPoints(reloadBtn)
    rBg:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)

    local rLbl = reloadBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rLbl:SetAllPoints(reloadBtn)
    rLbl:SetJustifyH("CENTER")
    rLbl:SetText("RELOAD DATA")
    rLbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)

    reloadBtn:SetScript("OnClick", function()
        StaticPopup_Show("COMBATLEDGER_RELOAD_CONFIRM")
    end)
    reloadBtn:SetScript("OnEnter", function()
        rBg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b)
        rLbl:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    end)
    reloadBtn:SetScript("OnLeave", function()
        rBg:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)
        rLbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    end)
    self.reloadBtn = reloadBtn

    self.companionStatus = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.companionStatus:SetPoint("RIGHT", reloadBtn, "LEFT", -12, 0)
    self.companionStatus:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    self.companionStatus:SetText("NO COMPANION DATA")

    -- ── Content area ──────────────────────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT",     filterBar,  "BOTTOMLEFT",  0, -1)
    contentArea:SetPoint("BOTTOMRIGHT", bottomBar,  "TOPRIGHT",    0, 1)
    self.contentArea = contentArea

    -- Build tabs and preset bar
    self:BuildTabButtons()
    self:BuildPresetSelector(filterBar)
    self:BuildEmptyState()

    -- Open at last active tab
    local lastTab = (CL.addon and CL.addon.db and CL.addon.db.profile.lastActiveTab) or "overview"
    self:SwitchTab(lastTab)
end

-- ---------------------------------------------------------------------------
-- Tab registration (called by tab modules at load time)
-- ---------------------------------------------------------------------------

function Frame:RegisterTab(id, label, module)
    if not self.tabDefs[id] then
        table.insert(self.tabs, id)
    end
    self.tabDefs[id] = { label = label, module = module }
end

-- ---------------------------------------------------------------------------
-- Build tab buttons (underline style matching mockup)
-- ---------------------------------------------------------------------------

function Frame:BuildTabButtons()
    local x = 8
    for _, id in ipairs(self.tabs) do
        local def = self.tabDefs[id]
        if def then
            local btn = CreateFrame("Button", nil, self.tabBar)
            btn:SetHeight(TABBAR_H)
            -- Auto-size width to text + padding
            local labelW = math.max(80, #def.label * 8 + 24)
            btn:SetWidth(labelW)
            btn:SetPoint("LEFT", self.tabBar, "LEFT", x, 0)
            x = x + labelW + 2

            -- Hover / active glow background (accent-glow: gold at ~8% opacity)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            bg:SetColorTexture(0, 0, 0, 0)  -- transparent by default

            -- Label
            local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetAllPoints(btn)
            lbl:SetText(string.upper(def.label))
            lbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
            lbl:SetJustifyH("CENTER")

            -- Gold underline (2px, hidden by default)
            local underline = btn:CreateTexture(nil, "OVERLAY")
            underline:SetHeight(2)
            underline:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
            underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
            underline:SetColorTexture(0, 0, 0, 0)  -- transparent until active

            btn:SetScript("OnClick", function() self:SwitchTab(id) end)
            btn:SetScript("OnEnter", function()
                if self.activeTab ~= id then
                    bg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b, 0.5)
                    lbl:SetTextColor(C.textPrimary.r, C.textPrimary.g, C.textPrimary.b)
                end
            end)
            btn:SetScript("OnLeave", function()
                if self.activeTab ~= id then
                    bg:SetColorTexture(0, 0, 0, 0)
                    lbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
                end
            end)

            self.tabButtons[id] = { btn = btn, bg = bg, label = lbl, underline = underline }
        end
    end
end

-- ---------------------------------------------------------------------------
-- Preset selector in filter bar
-- ---------------------------------------------------------------------------

function Frame:BuildPresetSelector(filterBar)
    -- ── Preset label + chips (left side) ──────────────────────────────────
    local presetLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetPoint("LEFT", filterBar, "LEFT", 10, 0)
    presetLabel:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    presetLabel:SetText("PRESET:")

    -- Vertical divider after label
    local div = filterBar:CreateTexture(nil, "OVERLAY")
    div:SetWidth(1); div:SetHeight(18)
    div:SetPoint("LEFT", filterBar, "LEFT", 65, 0)
    div:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)

    local x = 74
    self.presetButtons = {}

    local presets = CL.Config:GetPresets()
    for _, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, filterBar)
        btn:SetSize(100, 22)
        btn:SetPoint("LEFT", filterBar, "LEFT", x, 0)
        x = x + 104

        -- Background (filter-chip style: panel bg with border-light border)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetColorTexture(C.panelBg.r, C.panelBg.g, C.panelBg.b)

        -- Border edges
        local function chipEdge(point, isH)
            local e = btn:CreateTexture(nil, "BORDER")
            e:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
            if isH then e:SetHeight(1) else e:SetWidth(1) end
            e:SetPoint(point, btn, point, 0, 0)
            if isH then
                local opp = (point:find("TOP") and "TOP" or "BOTTOM")
                e:SetPoint(point:gsub(opp == "TOP" and "TOP" or "BOTTOM", ""), btn, point, 0, 0)
                -- simpler: just anchor both sides
            end
        end
        -- Simple 1px border approximation using 4 edge textures
        local bt = btn:CreateTexture(nil, "BORDER"); bt:SetHeight(1); bt:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bt:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); bt:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
        local bb = btn:CreateTexture(nil, "BORDER"); bb:SetHeight(1); bb:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bb:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0); bb:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        local bl = btn:CreateTexture(nil, "BORDER"); bl:SetWidth(1);  bl:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bl:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0); bl:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        local br = btn:CreateTexture(nil, "BORDER"); br:SetWidth(1);  br:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); br:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0); br:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints(btn)
        lbl:SetText(preset.name)
        lbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)

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

        self.presetButtons[presetName] = { btn = btn, bg = bg, lbl = lbl, bTop = bt, bBot = bb, bLeft = bl, bRight = br }
    end

    self:RefreshPresetHighlight()
end

function Frame:RefreshPresetHighlight()
    local active = CL.Config:GetActivePreset()
    for name, pbtn in pairs(self.presetButtons or {}) do
        if name == active then
            -- Active chip: gold glow bg + gold-dim border + gold text
            pbtn.bg:SetColorTexture(C.gold.r * 0.15, C.gold.g * 0.15, C.gold.b * 0.15)
            for _, edge in ipairs({ pbtn.bTop, pbtn.bBot, pbtn.bLeft, pbtn.bRight }) do
                edge:SetColorTexture(C.goldDim.r, C.goldDim.g, C.goldDim.b)
            end
            pbtn.lbl:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        else
            pbtn.bg:SetColorTexture(C.panelBg.r, C.panelBg.g, C.panelBg.b)
            for _, edge in ipairs({ pbtn.bTop, pbtn.bBot, pbtn.bLeft, pbtn.bRight }) do
                edge:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
            end
            pbtn.lbl:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tab switching
-- ---------------------------------------------------------------------------

function Frame:SwitchTab(id)
    -- Deactivate all tabs
    for tid, tbtn in pairs(self.tabButtons) do
        tbtn.bg:SetColorTexture(0, 0, 0, 0)
        tbtn.label:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        tbtn.underline:SetColorTexture(0, 0, 0, 0)
        local def = self.tabDefs[tid]
        if def and def.module and def.module.Hide then
            def.module:Hide(self.contentArea)
        end
    end

    -- Activate the selected tab
    local tbtn = self.tabButtons[id]
    if tbtn then
        -- Gold glow background (accent at 15% opacity)
        tbtn.bg:SetColorTexture(C.gold.r * 0.15, C.gold.g * 0.15, C.gold.b * 0.15)
        tbtn.label:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        -- Gold underline
        tbtn.underline:SetColorTexture(C.gold.r, C.gold.g, C.gold.b)
    end

    local def = self.tabDefs[id]
    if def and def.module then
        def.module:Render(self.contentArea)
    end

    -- Update session badge in titlebar
    self:UpdateSessionBadge()

    if CL.addon and CL.addon.db then
        CL.addon.db.profile.lastActiveTab = id
    end
    self.activeTab = id
end

-- ---------------------------------------------------------------------------
-- Session badge update
-- ---------------------------------------------------------------------------

function Frame:UpdateSessionBadge()
    if not self.sessionBadge then return end
    if not CL.Data:IsAvailable() then
        self.sessionBadge:SetText("NO DATA")
        self.sessionBadge:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        if self.companionStatus then
            self.companionStatus:SetText("NO COMPANION DATA")
            self.companionStatus:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
        end
        return
    end
    local session = CL.Data:GetActiveSession()
    if session then
        local idx   = CL.Data.activeSessionIndex or 1
        local count = CL.Data:GetSessionCount()
        local name  = (session.encounterName or "Unknown"):sub(1, 26)
        local pull  = session.pullNumber or idx
        local ok    = session.success and "|cff40e87a✓|r" or "|cffe84040✗|r"
        local perf  = session.performance
        local dur   = perf and perf.encounterDurationSec and math.floor(perf.encounterDurationSec) or 0
        local durStr = dur > 60  and string.format(" %dm%ds", math.floor(dur/60), dur%60)
                    or dur > 0   and string.format(" %ds", dur)
                    or ""
        self.sessionBadge:SetText(string.format(
            "[%d/%d]  #%d %s %s%s", idx, count, pull, name, ok, durStr))
        self.sessionBadge:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        if self.companionStatus then
            local ver = session.companionVersion and ("v" .. session.companionVersion) or "CONNECTED"
            self.companionStatus:SetText(string.format("|TInterface\\RaidFrame\\ReadyCheck-Ready:10:10|t |cff40e87a%s|r", ver))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Encounter selector dropdown
-- ---------------------------------------------------------------------------

--- Toggle the encounter picker dropdown open/closed.
function Frame:ToggleEncounterDropdown()
    if not self.encounterDropdown then
        self:BuildEncounterDropdown()
    end
    if self.encounterDropdown:IsShown() then
        self.encounterDropdown:Hide()
    else
        self:PopulateEncounterDropdown()
        self.encounterDropdown:Show()
    end
end

--- Build the dropdown panel once (called lazily on first open).
function Frame:BuildEncounterDropdown()
    -- Invisible click-catcher covers the whole screen; clicking outside closes the panel.
    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", function()
        self.encounterDropdown:Hide()
    end)
    self.encounterCatcher = catcher

    local dp = CreateFrame("Frame", nil, self.mainFrame)
    dp:SetWidth(290)
    dp:SetFrameStrata("DIALOG")
    -- Anchor top-right of panel to just below the titlebar right edge
    dp:SetPoint("TOPRIGHT", self.mainFrame, "TOPRIGHT", -1, -(TITLE_H + 1))
    dp:Hide()
    setBg(dp, 0.06, 0.07, 0.10)

    -- Border
    local bt = dp:CreateTexture(nil, "BORDER"); bt:SetHeight(1); bt:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bt:SetPoint("TOPLEFT", dp, "TOPLEFT"); bt:SetPoint("TOPRIGHT", dp, "TOPRIGHT")
    local bb = dp:CreateTexture(nil, "BORDER"); bb:SetHeight(1); bb:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bb:SetPoint("BOTTOMLEFT", dp, "BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT", dp, "BOTTOMRIGHT")
    local bl = dp:CreateTexture(nil, "BORDER"); bl:SetWidth(1);  bl:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); bl:SetPoint("TOPLEFT", dp, "TOPLEFT"); bl:SetPoint("BOTTOMLEFT", dp, "BOTTOMLEFT")
    local br = dp:CreateTexture(nil, "BORDER"); br:SetWidth(1);  br:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b); br:SetPoint("TOPRIGHT", dp, "TOPRIGHT"); br:SetPoint("BOTTOMRIGHT", dp, "BOTTOMRIGHT")

    dp:SetScript("OnShow", function() catcher:Show() end)
    dp:SetScript("OnHide", function() catcher:Hide() end)

    self.encounterDropdown = dp
end

--- Re-populate the dropdown with current session data and resize it.
function Frame:PopulateEncounterDropdown()
    local dp = self.encounterDropdown

    -- Remove old scroll frame if present
    if dp._sf then dp._sf:Hide(); dp._sf = nil end

    local sessions = CL.Data:IsAvailable() and CL.Data:GetSessions() or {}
    local ROW_H     = 22
    local MAX_ROWS  = 12   -- max visible rows before scrolling
    local visRows   = math.min(#sessions, MAX_ROWS)

    if visRows == 0 then
        dp:SetHeight(ROW_H)
        local empty = dp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        empty:SetPoint("CENTER", dp, "CENTER")
        empty:SetText("|cff888888No sessions recorded|r")
        return
    end

    dp:SetHeight(visRows * ROW_H + 2)

    local sf = CreateFrame("ScrollFrame", nil, dp)
    sf:SetPoint("TOPLEFT",     dp, "TOPLEFT",     1, -1)
    sf:SetPoint("BOTTOMRIGHT", dp, "BOTTOMRIGHT", -1,  1)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur   = self:GetVerticalScroll()
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * ROW_H)))
    end)
    dp._sf = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(288)
    content:SetHeight(#sessions * ROW_H)
    sf:SetScrollChild(content)

    local activeIdx = CL.Data.activeSessionIndex or 1
    local lastRunId = nil
    local yOff      = 0

    for i, session in ipairs(sessions) do
        -- Thin divider between runs
        if session.runId ~= lastRunId and lastRunId ~= nil then
            local div = content:CreateTexture(nil, "OVERLAY")
            div:SetHeight(1)
            div:SetPoint("TOPLEFT",  content, "TOPLEFT",  8, -yOff)
            div:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -yOff)
            div:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)
        end
        lastRunId = session.runId

        local row = CreateFrame("Button", nil, content)
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -yOff)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOff)
        row:SetHeight(ROW_H)

        local isActive = (i == activeIdx)
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        if isActive then
            rowBg:SetColorTexture(C.gold.r * 0.12, C.gold.g * 0.12, C.gold.b * 0.12)
        else
            rowBg:SetColorTexture(0, 0, 0, 0)
        end

        -- Build row label
        local pullType = (session.pullType == "trash") and "Trash" or (session.encounterName or "Unknown")
        local status   = session.success and "|cff40e87a✓|r" or "|cffe84040✗|r"
        local perf     = session.performance
        local dur      = perf and perf.encounterDurationSec and math.floor(perf.encounterDurationSec) or 0
        local durStr   = dur > 60  and string.format(" %dm%ds", math.floor(dur/60), dur%60)
                      or dur > 0   and string.format(" %ds", dur)
                      or ""
        local label    = string.format("  #%-2d  %s  %s%s", session.pullNumber or i, pullType, status, durStr)
        if isActive then label = "|cffe8a820" .. label .. "|r" end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  row, "LEFT",  4, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label)

        local idx = i  -- upvalue capture
        row:SetScript("OnClick", function()
            CL.Data:SetActiveSession(idx)
            self.encounterDropdown:Hide()
            self:UpdateSessionBadge()
            self:RefreshCurrentTab()
        end)
        row:SetScript("OnEnter", function()
            if not isActive then rowBg:SetColorTexture(C.hover.r, C.hover.g, C.hover.b, 0.5) end
        end)
        row:SetScript("OnLeave", function()
            if not isActive then rowBg:SetColorTexture(0, 0, 0, 0) end
        end)

        yOff = yOff + ROW_H
    end

    content:SetHeight(yOff)
end

--- Re-render the currently active tab (called after changing active session).
function Frame:RefreshCurrentTab()
    if self.activeTab then
        local def = self.tabDefs[self.activeTab]
        if def and def.module then
            def.module:Hide(self.contentArea)
            def.module:Render(self.contentArea)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Empty state
-- ---------------------------------------------------------------------------

function Frame:BuildEmptyState()
    local f = CreateFrame("Frame", nil, self.contentArea)
    f:SetAllPoints(self.contentArea)
    self.emptyState = f
    setBg(f, C.panelBg.r, C.panelBg.g, C.panelBg.b)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    msg:SetPoint("CENTER", f, "CENTER", 0, 24)
    msg:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    self.emptyMsg = msg

    -- Gold divider line under main message
    local divLine = f:CreateTexture(nil, "OVERLAY")
    divLine:SetHeight(1)
    divLine:SetWidth(200)
    divLine:SetPoint("TOP", msg, "BOTTOM", 0, -10)
    divLine:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", divLine, "BOTTOM", 0, -10)
    sub:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
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
-- Toggle (slash command / minimap click)
-- ---------------------------------------------------------------------------

function Frame:Toggle()
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
        -- Refresh the active tab and session badge
        self:UpdateSessionBadge()
        if self.activeTab then
            self:SwitchTab(self.activeTab)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Shared UI helpers exposed to tab modules
-- ---------------------------------------------------------------------------

--- Draw a section-header row: "──── TITLE ────────────────────────── count"
--  Returns the header frame so the caller can position the next element below it.
--  @param parent  Parent frame
--  @param yOffset  Y offset from top of parent (negative number)
--  @param title   Section title string
--  @param count   Optional count string displayed on the right
function Frame:SectionHeader(parent, yOffset, title, count)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    row:SetHeight(18)

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleFs:SetPoint("LEFT", row, "LEFT", 0, 0)
    titleFs:SetText(string.upper(title))
    titleFs:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)

    -- Horizontal rule from title to right edge
    local line = row:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetPoint("LEFT",  titleFs, "RIGHT",  6, 0)
    line:SetPoint("RIGHT", row,     "RIGHT", count and -40 or 0, 0)
    line:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b)

    if count then
        local countFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countFs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        countFs:SetText(tostring(count))
        countFs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
    end

    return row
end

--- Create a card panel: card-bg with border, optional left-stripe color.
--  @param parent     Parent frame
--  @param yOffset    Negative Y offset from top of parent
--  @param h          Card height
--  @param stripeR/G/B  Optional left-border stripe color (nil = no stripe)
function Frame:Card(parent, yOffset, h, stripeR, stripeG, stripeB)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOffset)
    card:SetHeight(h)

    setBg(card, C.cardBg.r, C.cardBg.g, C.cardBg.b)

    -- 1px border
    local bt = card:CreateTexture(nil, "BORDER"); bt:SetHeight(1); bt:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); bt:SetPoint("TOPLEFT", card, "TOPLEFT"); bt:SetPoint("TOPRIGHT", card, "TOPRIGHT")
    local bb = card:CreateTexture(nil, "BORDER"); bb:SetHeight(1); bt:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); bb:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
    local bl = card:CreateTexture(nil, "BORDER"); bl:SetWidth(1);  bl:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); bl:SetPoint("TOPLEFT", card, "TOPLEFT"); bl:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
    local br = card:CreateTexture(nil, "BORDER"); br:SetWidth(1);  br:SetColorTexture(C.borderSub.r, C.borderSub.g, C.borderSub.b); br:SetPoint("TOPRIGHT", card, "TOPRIGHT"); br:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")

    -- Left stripe (e.g. gold for encounter header, red for death card)
    if stripeR then
        local stripe = card:CreateTexture(nil, "OVERLAY")
        stripe:SetWidth(3)
        stripe:SetPoint("TOPLEFT",    card, "TOPLEFT",    0, 0)
        stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        stripe:SetColorTexture(stripeR, stripeG or 0, stripeB or 0)
    end

    return card
end

--- Create a themed scrollable area inside `parent`.
--  Returns scrollFrame, contentChild.
--  The scrollbar is a slim dark track with a thumb that glows gold on hover.
--  All three pieces (scrollFrame, track, thumb) are children of `parent` so
--  they stay inside the CL window border.
function Frame:MakeScrollable(parent)
    local BAR_W   = 6   -- thumb / track width in px
    local BAR_PAD = 3   -- gap from the parent's right edge

    -- ScrollFrame leaves room for the bar on the right
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(BAR_W + BAR_PAD + 2), 0)
    sf:EnableMouseWheel(true)

    -- Scroll content child — width matches the scrollFrame
    local content = CreateFrame("Frame", nil, sf)
    local contentW = parent:GetWidth() - BAR_W - BAR_PAD - 2
    content:SetWidth(contentW > 0 and contentW or 900)
    content:SetHeight(1)   -- grows as rows are added
    sf:SetScrollChild(content)

    -- Dark track strip
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(BAR_W)
    track:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    -BAR_PAD, -2)
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -BAR_PAD,  2)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetAllPoints(track)
    trackTex:SetColorTexture(0.04, 0.05, 0.07)

    -- Thumb
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(BAR_W)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints(thumb)
    thumbTex:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    thumb:Hide()
    thumb:EnableMouse(true)
    thumb:SetScript("OnEnter", function()
        thumbTex:SetColorTexture(C.gold.r, C.gold.g, C.gold.b, 0.8)
    end)
    thumb:SetScript("OnLeave", function()
        thumbTex:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b)
    end)

    local function updateThumb()
        local range = sf:GetVerticalScrollRange()
        if range <= 0 then thumb:Hide(); return end
        thumb:Show()
        local trackH = track:GetHeight()
        local sfH    = sf:GetHeight()
        local thumbH = math.max(20, trackH * sfH / (sfH + range))
        local pos    = (sf:GetVerticalScroll() / range) * (trackH - thumbH)
        thumb:ClearAllPoints()
        thumb:SetHeight(thumbH)
        thumb:SetPoint("TOP", track, "TOP", 0, -pos)
    end

    sf:SetScript("OnVerticalScroll", function(self, val)
        self:SetVerticalScroll(val)
        updateThumb()
    end)
    sf:SetScript("OnScrollRangeChanged", updateThumb)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local cur   = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 40)))
    end)

    return sf, content
end
