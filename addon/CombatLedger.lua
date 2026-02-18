-- CombatLedger.lua — Entry point, slash commands, minimap button
-- All combat data processing happens in the TypeScript companion app.
-- This addon is purely a reader and renderer of SavedVariables.

local addonName, CL = ...

-- ---------------------------------------------------------------------------
-- Addon registration (AceAddon-3.0)
-- ---------------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):NewAddon("CombatLedger", "AceConsole-3.0")
CL.addon = addon

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

function addon:OnInitialize()
    -- AceDB manages addon settings (NOT companion data).
    -- CombatLedgerDB is written directly by the companion and read as a raw global.
    self.db = LibStub("AceDB-3.0"):New("CombatLedgerSettings", CL.Config.defaults, true)

    self:RegisterChatCommand("cl", "SlashCommand")
    self:RegisterChatCommand("combatledger", "SlashCommand")
end

function addon:OnEnable()
    -- Data module reads CombatLedgerDB on first access.
    CL.Data:Init()
    CL.Frame:Init()
end

function addon:SlashCommand(input)
    local cmd = strtrim(input):lower()
    if cmd == "reset" then
        CombatLedgerDB = nil
        self:Print("CombatLedger data cleared. Run a dungeon and /reload to populate.")
    elseif cmd == "version" then
        self:Print("CombatLedger v0.1.0")
    elseif cmd == "" or cmd == "open" then
        CL.Frame:Toggle()
    else
        self:Print("Unknown command. Usage: /cl [open|reset|version]")
    end
end
