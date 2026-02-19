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

    -- Confirmation popup shown by the "Reload Data" button and /cl refresh.
    -- ReloadUI() is a standard Blizzard API call used by many addons.
    StaticPopupDialogs["COMBATLEDGER_RELOAD_CONFIRM"] = {
        text = "Reload the UI to fetch the latest data from CombatLedger Companion?\n\n|cff7888a0This is equivalent to typing /reload.|r",
        button1 = "Reload",
        button2 = "Cancel",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
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
        self:Print("CombatLedger v1.1.1a")
    elseif cmd == "refresh" then
        StaticPopup_Show("COMBATLEDGER_RELOAD_CONFIRM")
    elseif cmd == "" or cmd == "open" then
        CL.Frame:Toggle()
    else
        self:Print("Unknown command. Usage: /cl [open|reset|version|refresh]")
    end
end
