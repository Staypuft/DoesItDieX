local NAME_MATCH = "^EUIStandaloneUnitFrames_"

local function isTarget(cd)
    local f = cd:GetParent()
    for _ = 1, 8 do
        if not f then return false end
        local n = f:GetName()
        if n and n:find(NAME_MATCH) then return true end
        f = f:GetParent()
    end
    return false
end

local busy = false
local function kill(cd)
    if busy or not isTarget(cd) then return end
    busy = true
    cd:SetDrawSwipe(false)
    cd:SetDrawEdge(false)
    busy = false
end

local mt = getmetatable(CreateFrame("Cooldown")).__index
hooksecurefunc(mt, "SetCooldown", kill)
hooksecurefunc(mt, "SetDrawSwipe", kill)  -- in case the addon re-enables it after setting the cooldown
if mt.SetCooldownFromDurationObject then
    hooksecurefunc(mt, "SetCooldownFromDurationObject", kill)
end