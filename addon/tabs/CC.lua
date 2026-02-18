-- tabs/CC.lua — CC coverage tab (Phase 2 placeholder)

local addonName, CL = ...
local CC = {}
CL.CC = CC

CL.Frame:RegisterTab("cc", "CC", CC)

function CC:Render(parent)
    self:Clear(parent)
    CL.Frame:ShowEmptyState("CC Coverage", "Coming in Phase 2.")
end

function CC:Hide(parent)
    if self.frame then self.frame:Hide(); self.frame = nil end
end

function CC:Clear(parent)
    self:Hide(parent)
end
