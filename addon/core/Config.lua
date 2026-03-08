-- core/Config.lua — Settings, presets (AceConfig)
-- Manages CombatLedgerSettings (addon preferences), NOT companion data.

local addonName, CL = ...
CL.Config = {}

local Config = CL.Config

-- ---------------------------------------------------------------------------
-- AceDB defaults
-- ---------------------------------------------------------------------------

Config.defaults = {
    profile = {
        -- UI state
        framePoint = { point = "CENTER", x = 0, y = 0 },
        lastActiveTab = "overview",
        -- Filters
        filters = {
            players = {},    -- empty = all players
            pulls  = "all",  -- "all" | "1" | "2" | etc.
        },
        -- Active preset name
        activePreset = "Default",
        -- User-defined presets (name → preset table)
        customPresets = {},
        -- Advanced features toggle (Settings tab danger zone)
        advancedMode = false,
    },
    char = {
        -- Per-character UI preferences if needed
    },
}

-- ---------------------------------------------------------------------------
-- Built-in presets (read-only)
-- ---------------------------------------------------------------------------

Config.builtinPresets = {
    {
        name = "Default",
        filters = { players = {}, pulls = "all" },
        activeTab = "overview",
        showOnlyAvoidable = false,
    },
    {
        name = "Deaths Only",
        filters = { players = {}, pulls = "all" },
        activeTab = "deaths",
        showOnlyAvoidable = false,
    },
    {
        name = "Tank Focus",
        filters = { players = { role = "TANK" }, pulls = "all" },
        activeTab = "performance",
        showOnlyAvoidable = false,
    },
    {
        name = "Healer Audit",
        filters = { players = { role = "HEALER" }, pulls = "all" },
        activeTab = "performance",
        showOnlyAvoidable = false,
    },
    {
        name = "M+ Push Review",
        filters = { players = {}, pulls = "all" },
        activeTab = "deaths",
        showOnlyAvoidable = false,
    },
}

-- ---------------------------------------------------------------------------
-- Preset management (Task 2.5)
-- ---------------------------------------------------------------------------

--- Returns merged list of built-in + custom presets.
function Config:GetPresets()
    local list = {}
    for _, p in ipairs(self.builtinPresets) do
        table.insert(list, p)
    end
    local custom = (CL.addon and CL.addon.db and CL.addon.db.profile.customPresets) or {}
    for name, p in pairs(custom) do
        table.insert(list, { name = name, filters = p.filters, activeTab = p.activeTab })
    end
    return list
end

--- Find a preset by name (builtin first, then custom).
function Config:FindPreset(name)
    for _, p in ipairs(self.builtinPresets) do
        if p.name == name then return p end
    end
    local custom = (CL.addon and CL.addon.db and CL.addon.db.profile.customPresets) or {}
    return custom[name]
end

--- Apply a preset by name: saves activePreset setting, switches tab.
function Config:ApplyPreset(name)
    local preset = self:FindPreset(name)
    if not preset then return end
    if CL.addon and CL.addon.db then
        CL.addon.db.profile.activePreset = name
    end
    if preset.activeTab and CL.Frame then
        CL.Frame:SwitchTab(preset.activeTab)
    end
end

--- Return the currently active preset name.
function Config:GetActivePreset()
    return (CL.addon and CL.addon.db and CL.addon.db.profile.activePreset) or "Default"
end

--- Save (create or overwrite) a custom preset.
--- @param name      string  Display name of the preset
--- @param activeTab string  Tab ID to switch to when applied (e.g. "overview")
--- @param role      string|nil  "TANK", "HEALER", "DPS", or nil for all roles
--- The new preset appears in the filter bar the next time the frame is opened.
function Config:SaveCustomPreset(name, activeTab, role)
    if not name or name == "" then return end
    local profile = (CL.addon and CL.addon.db and CL.addon.db.profile)
    if not profile then return end
    profile.customPresets = profile.customPresets or {}
    profile.customPresets[name] = {
        filters   = { players = role and { role = role } or {}, pulls = "all" },
        activeTab = activeTab or "overview",
    }
end

--- Delete a custom preset by name.
--- The chip disappears from the filter bar the next time the frame is opened.
function Config:DeleteCustomPreset(name)
    local profile = (CL.addon and CL.addon.db and CL.addon.db.profile)
    if not profile or not profile.customPresets then return end
    profile.customPresets[name] = nil
end

-- ---------------------------------------------------------------------------
-- WoW class colours
-- ---------------------------------------------------------------------------

Config.classColours = {
    DEATHKNIGHT  = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER  = { r = 0.64, g = 0.19, b = 0.79 },
    DRUID        = { r = 1.00, g = 0.49, b = 0.04 },
    EVOKER       = { r = 0.20, g = 0.58, b = 0.50 },
    HUNTER       = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE         = { r = 0.25, g = 0.78, b = 0.92 },
    MONK         = { r = 0.00, g = 1.00, b = 0.59 },
    PALADIN      = { r = 0.96, g = 0.55, b = 0.73 },
    PRIEST       = { r = 1.00, g = 1.00, b = 1.00 },
    ROGUE        = { r = 1.00, g = 0.96, b = 0.41 },
    SHAMAN       = { r = 0.00, g = 0.44, b = 0.87 },
    WARLOCK      = { r = 0.53, g = 0.53, b = 0.93 },
    WARRIOR      = { r = 0.78, g = 0.61, b = 0.43 },
}

-- UI theme colours (matches CombatLedger mockup CSS variables exactly)
Config.colours = {
    -- Backgrounds
    bg         = { r = 0.039, g = 0.047, b = 0.063 }, -- #0a0c10  --bg-base
    panelBg    = { r = 0.059, g = 0.071, b = 0.098 }, -- #0f1219  --bg-panel
    cardBg     = { r = 0.078, g = 0.094, b = 0.125 }, -- #141820  --bg-card
    hover      = { r = 0.102, g = 0.125, b = 0.188 }, -- #1a2030  --bg-hover
    -- Borders
    borderSub  = { r = 0.118, g = 0.145, b = 0.208 }, -- #1e2535  --border
    borderVis  = { r = 0.145, g = 0.176, b = 0.251 }, -- #252d40  --border-light
    -- Text
    textPrimary   = { r = 0.831, g = 0.863, b = 0.918 }, -- #d4dcea --text-primary
    textSecondary = { r = 0.420, g = 0.478, b = 0.604 }, -- #6b7a9a --text-secondary
    textMuted     = { r = 0.239, g = 0.290, b = 0.384 }, -- #3d4a62 --text-muted
    -- Accent (gold)
    gold       = { r = 0.910, g = 0.659, b = 0.125 }, -- #e8a820  --accent
    goldDim    = { r = 0.690, g = 0.478, b = 0.063 }, -- #b07a10  --accent-dim
    -- Semantic
    red        = { r = 0.910, g = 0.251, b = 0.251 }, -- #e84040  --death
    blue       = { r = 0.251, g = 0.722, b = 0.910 }, -- #40b8e8  --interrupt
    purple     = { r = 0.690, g = 0.251, b = 0.910 }, -- #b040e8  --cc
    green      = { r = 0.251, g = 0.910, b = 0.478 }, -- #40e87a  --heal
    damage     = { r = 0.910, g = 0.376, b = 0.251 }, -- #e86040  --damage
}
