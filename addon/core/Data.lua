-- core/Data.lua — SavedVariables reader + data access layer
-- Reads CombatLedgerDB (written by companion), never writes to it.

local addonName, CL = ...
CL.Data = {}

local Data = CL.Data

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

function Data:Init()
    -- CombatLedgerDB is a raw global written by the companion.
    -- It is not registered in ## SavedVariables, so WoW does not manage it.
    if not CombatLedgerDB then
        self.available = false
        return
    end
    self.available = true
    self.db = CombatLedgerDB
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

--- Returns true if companion data is present and non-empty.
function Data:IsAvailable()
    return self.available and self.db and #(self.db.sessions or {}) > 0
end

--- Returns the companion version string, or nil.
function Data:GetCompanionVersion()
    return self.db and self.db.companionVersion
end

--- Returns the array of sessions (newest first), or an empty table.
function Data:GetSessions()
    if not self.db then return {} end
    return self.db.sessions or {}
end

--- Returns session at index i (1 = newest).
function Data:GetSession(i)
    return self:GetSessions()[i]
end

--- Returns the first (most recent) session, or nil.
function Data:GetLatestSession()
    return self:GetSession(1)
end

--- Returns the deaths array for a session table.
function Data:GetDeaths(session)
    if not session then return {} end
    return session.deaths or {}
end

--- Returns the interrupt report table for a session.
function Data:GetInterrupts(session)
    if not session then return {} end
    return session.interrupts or {}
end

--- Returns the CC coverage array for a session.
function Data:GetCCCoverage(session)
    if not session then return {} end
    return session.ccCoverage or {}
end

--- Returns the performance report for a session.
function Data:GetPerformance(session)
    if not session then return {} end
    return session.performance or {}
end

--- Returns the defensive audit report for a session.
function Data:GetDefensiveAudit(session)
    if not session then return {} end
    return session.defensiveAudit or {}
end

--- Format a duration in seconds as "Xm Ys" or "Xs".
function Data:FormatDuration(sec)
    sec = math.floor(sec or 0)
    if sec >= 60 then
        return string.format("%dm %ds", math.floor(sec / 60), sec % 60)
    end
    return string.format("%ds", sec)
end

--- Format a Unix timestamp as "HH:MM".
function Data:FormatTime(unixTs)
    return date("%H:%M", unixTs)
end
