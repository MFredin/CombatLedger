-- tabs/Performance.lua — Performance tab (Phase 2 placeholder)

local addonName, CL = ...
local Performance = {}
CL.Performance = Performance

CL.Frame:RegisterTab("performance", "Performance", Performance)

function Performance:Render(parent)
    self:Clear(parent)
    CL.Frame:ShowEmptyState("Performance", "Coming in Phase 2.")
end

function Performance:Hide(parent)
    if self.frame then self.frame:Hide(); self.frame = nil end
end

function Performance:Clear(parent)
    self:Hide(parent)
end
