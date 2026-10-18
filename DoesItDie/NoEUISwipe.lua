-- Hides the cooldown swipe (and its edge) on EllesmereUI's standalone unit frames, e.g. the timer sweep on
-- their aura icons. Every Cooldown widget shares one method table, so this hooks that table and decides per
-- cooldown whether it lives inside a frame named EUIStandaloneUnitFrames_*.
 
local NAME_MATCH = "^EUIStandaloneUnitFrames_"
local MAX_DEPTH = 8
 
-- Verdict per cooldown frame, so the parent walk runs once per cooldown rather than on every update (the hook
-- fires for every cooldown in the UI: action bars, other addons...). Weak keys: frames can be garbage collected.
local verdict = setmetatable({}, { __mode = "k" })
 
local function isEllesmere(cd)
    local known = verdict[cd]
    if known ~= nil then return known end
    -- pcall: a frame in the chain may refuse calls (forbidden or protected), which must never break the caller.
    local ok, found = pcall(function()
        local f = cd:GetParent()
        for _ = 1, MAX_DEPTH do
            if not f then return false end
            local name = f:GetName()
            if type(name) == "string" and name:find(NAME_MATCH) then return true end
            f = f:GetParent()
        end
        return false
    end)
    found = ok and found or false
    -- Only cache a "no" once the cooldown has a parent: frames can be created first and parented later.
    if found or cd:GetParent() then verdict[cd] = found end
    return found
end
 
local busy = false
local function hideSwipe(cd)
    if busy or not isEllesmere(cd) then return end
    busy = true -- SetDrawSwipe below re-enters this hook
    pcall(cd.SetDrawSwipe, cd, false)
    pcall(cd.SetDrawEdge, cd, false)
    busy = false
end
 
local methods = getmetatable(CreateFrame("Cooldown")).__index
if type(methods) == "table" then
    hooksecurefunc(methods, "SetCooldown", hideSwipe)
    hooksecurefunc(methods, "SetDrawSwipe", hideSwipe) -- in case EllesmereUI turns it back on after setting the cooldown
    if methods.SetCooldownFromDurationObject then
        hooksecurefunc(methods, "SetCooldownFromDurationObject", hideSwipe)
    end
end
