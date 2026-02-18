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

-- UI theme colours
Config.colours = {
    bg         = { r = 0.039, g = 0.047, b = 0.063 }, -- #0a0c10
    panelBg    = { r = 0.059, g = 0.071, b = 0.098 }, -- #0f1219
    cardBg     = { r = 0.078, g = 0.094, b = 0.125 }, -- #141820
    hover      = { r = 0.102, g = 0.125, b = 0.188 }, -- #1a2030
    borderSub  = { r = 0.118, g = 0.145, b = 0.208 }, -- #1e2535
    borderVis  = { r = 0.145, g = 0.176, b = 0.251 }, -- #252d40
    gold       = { r = 0.910, g = 0.659, b = 0.125 }, -- #e8a820
    red        = { r = 0.910, g = 0.251, b = 0.251 }, -- #e84040
    blue       = { r = 0.251, g = 0.722, b = 0.910 }, -- #40b8e8
    purple     = { r = 0.690, g = 0.251, b = 0.910 }, -- #b040e8
    green      = { r = 0.251, g = 0.910, b = 0.478 }, -- #40e87a
}
