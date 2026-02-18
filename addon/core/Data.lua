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

-- ---------------------------------------------------------------------------
-- Phase 3 — Session selector (History tab sets activeSessionIndex)
-- ---------------------------------------------------------------------------

Data.activeSessionIndex = 1

--- Set the active session by index (1 = most recent).
function Data:SetActiveSession(index)
    self.activeSessionIndex = index or 1
end

--- Returns the currently selected session (default: most recent).
function Data:GetActiveSession()
    return self:GetSession(self.activeSessionIndex or 1)
end

--- Returns total number of sessions in SavedVariables.
function Data:GetSessionCount()
    return #self:GetSessions()
end

-- ---------------------------------------------------------------------------
-- Phase 3 — Trend accessors
-- ---------------------------------------------------------------------------

--- Returns the trend report table (populated after multiple pulls on same boss).
function Data:GetTrend()
    if not self.db then return {} end
    return self.db.trends or {}
end

--- Returns the trend points array (chronological pull history).
function Data:GetTrendPoints()
    return self:GetTrend().points or {}
end

--- Returns the trend summary (totalPulls, kills, deathTrend, etc.).
function Data:GetTrendSummary()
    return self:GetTrend().summary or {}
end

-- ---------------------------------------------------------------------------
-- Phase 3 — Distribution accessors
-- ---------------------------------------------------------------------------

--- Returns the distribution report table (percentile data for current session).
function Data:GetDistribution()
    if not self.db then return {} end
    return self.db.distribution or {}
end

--- Returns the distribution players array.
function Data:GetDistributionPlayers()
    return self:GetDistribution().players or {}
end

--- Returns the percentile entry for a player+metric, or nil.
function Data:GetPlayerPercentile(playerGUID, metric)
    for _, dp in ipairs(self:GetDistributionPlayers()) do
        if dp.playerGUID == playerGUID and dp.metric == metric then
            return dp
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Phase 3 — Formatting utilities
-- ---------------------------------------------------------------------------

--- Format a trend slope as a coloured arrow string.
--- invertedBetter = true means a negative slope is an improvement (e.g. deaths).
function Data:FormatTrend(val, invertedBetter)
    if not val or val == 0 then
        return "|cff888888→ stable|r"
    end
    local improving = invertedBetter and (val < 0) or (val > 0)
    local arrow = improving and "↑" or "↓"
    local color = improving and "40e87a" or "e84040"
    return string.format("|cff%s%s %.1f|r", color, arrow, math.abs(val))
end

--- Format a percentile as a coloured "P80" badge.
function Data:FormatPercentile(pct)
    local color
    if pct >= 90 then color = "e8a820"       -- gold  (exceptional)
    elseif pct >= 75 then color = "40e87a"   -- green (good)
    elseif pct >= 50 then color = "40b8e8"   -- blue  (average)
    elseif pct >= 25 then color = "fe8040"   -- orange (below avg)
    else color = "e84040"                     -- red   (poor)
    end
    return string.format("|cff%sP%d|r", color, math.floor(pct or 0))
end
