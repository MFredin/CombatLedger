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
    titleText:SetPoint("LEFT", logoMark, "RIGHT", 8, 2)
    titleText:SetText("COMBAT|cffe8a820LEDGER|r")

    -- Sub-label: "POST-COMBAT ANALYSIS ENGINE"
    local subLabel = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subLabel:SetPoint("LEFT", logoMark, "RIGHT", 9, -9)
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
    closeX:SetText("✕")
    closeX:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBg:SetColorTexture(C.red.r, C.red.g, C.red.b, 0.6) closeX:SetTextColor(1, 1, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBg:SetColorTexture(C.borderVis.r, C.borderVis.g, C.borderVis.b) closeX:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b) end)

    -- Session badge (right of close)
    local sessionBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionBadge:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    sessionBadge:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
    sessionBadge:SetText("SESSION #— · NO DATA")
    self.sessionBadge = sessionBadge

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
    verLabel:SetText("CombatLedger v0.4.0  ·  Requires Companion ≥ 0.4.0")

    self.companionStatus = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.companionStatus:SetPoint("RIGHT", bottomBar, "RIGHT", -12, 0)
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
        local idx = CL.Data.activeSessionIndex or 1
        local count = CL.Data:GetSessionCount()
        local diff = session.difficulty and string.format(" · %s", session.difficulty) or ""
        self.sessionBadge:SetText(string.format("SESSION %d/%d%s", idx, count, diff))
        self.sessionBadge:SetTextColor(C.textSecondary.r, C.textSecondary.g, C.textSecondary.b)
        if self.companionStatus then
            local ver = session.companionVersion and ("v" .. session.companionVersion) or "CONNECTED"
            self.companionStatus:SetText(string.format("|cff40e87a● |r%s", ver))
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
