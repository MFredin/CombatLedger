-- tabs/Overview.lua — Overview tab

local addonName, CL = ...
local Overview = {}
CL.Overview = Overview

-- Register with the frame system
CL.Frame:RegisterTab("overview", "Overview", Overview)

local C = CL.Config.colours

function Overview:Render(parent)
    self:Clear(parent)

    if not CL.Data:IsAvailable() then
        if not CombatLedgerDB then
            CL.Frame:ShowEmptyState(
                "Companion app not detected.",
                "Install CombatLedger Companion to enable post-combat analysis."
            )
        else
            CL.Frame:ShowEmptyState(
                "No sessions recorded yet.",
                "Run a dungeon or raid, then type /reload."
            )
        end
        return
    end
    CL.Frame:HideEmptyState()

    local session = CL.Data:GetLatestSession()
    if not session then return end

    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)

    local function addLine(text, y)
        local fs = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, y)
        fs:SetText(text)
        return fs
    end

    local y = -16
    addLine(string.format("|cffe8a820%s|r  —  %s  |cff888888Pull #%d|r",
        session.encounterName,
        session.success and "|cff40e87aSuccess|r" or "|cffe84040Wipe|r",
        session.pullNumber), y)
    y = y - 22

    addLine(string.format("Duration: %s   Deaths: %d   Interrupts: %d/%d  (%.0f%%)",
        CL.Data:FormatDuration(session.durationSec),
        #(session.deaths or {}),
        (session.interrupts and session.interrupts.summary and session.interrupts.summary.intercepted) or 0,
        (session.interrupts and session.interrupts.summary and session.interrupts.summary.total) or 0,
        (session.interrupts and session.interrupts.summary and session.interrupts.summary.ratePercent) or 0
    ), y)
    y = y - 22

    addLine("|cff888888Use the Deaths and Interrupts tabs for detailed analysis.|r", y)
end

function Overview:Hide(parent)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
end

function Overview:Clear(parent)
    self:Hide(parent)
end
