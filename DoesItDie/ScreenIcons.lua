-- DoesItDie on-screen icons: a free-standing kill icon and a row of DoT icons you can put anywhere on the
-- screen, instead of (or as well as) the marker and kill icon on the target frame.
--
--   Kill icon: same secret-value trick as the portrait one (see the kill icon notes in DoesItDie.lua). A
--   SKULL_BAR_LENGTH-px StatusBar (max = the unit's current health, secret; value = remaining DoT damage) sits
--   in a small clipping frame; the icon rides the end of the fill and only comes into view when the fill reaches
--   100%, i.e. when your DoTs will kill the unit. Nothing here compares health, so it works in combat.
--   DoT icons: one per DoT of yours on the unit, with the spell icon, a draining swipe for its duration, and the
--   damage it still has to deal. Plain numbers only. Desaturated while a DoT waits for its first tick.
--
-- Both can be dragged (/did screen unlock) or pinned to any named frame, e.g. a TellMeWhen icon
-- (/did screen anchor TellMeWhen_Group1_Icon1), so the kill icon appears right on top of it.
-- Settings live in DoesItDieDB.screen. Unverified in-game.

local ADDON_NAME, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SKULL_BAR_LENGTH = 10000
local UPDATE_INTERVAL = 0.1
local ANCHOR_RETRY_SECONDS = 1
local MAX_DOT_ICONS = 8
local DOT_SPACING = 4

local SCREEN_DEFAULTS = {
    enabled = false,
    unit = "target",
    showKill = true,
    showDots = true,
    killSize = 56,
    dotSize = 32,
    locked = true,
    killPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = -140 },
    dotsPos = { point = "TOP", relPoint = "CENTER", x = 0, y = -180 },
    killAnchor = nil, -- global frame name to center the kill icon on (e.g. a TellMeWhen icon), or nil
    dotsAnchor = nil, -- same for the DoT row (its TOP goes under the frame's BOTTOM)
}

local function print(msg) if ns.print then ns.print(msg) end end
local function trace(msg) if ns.trace then ns.trace(msg) end end

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

local function settings()
    local db = ns.db
    if not db then return nil end
    if type(db.screen) ~= "table" then db.screen = {} end
    local s = db.screen
    for key, value in pairs(SCREEN_DEFAULTS) do
        if s[key] == nil then
            s[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    return s
end

local function killTexturePath()
    local db = ns.db
    local entry = db and ns.findById and ns.lists and ns.findById(ns.lists.icons, db.skullIcon)
    return entry and entry.path or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

-- A draggable holder with a "move me" box that shows only while unlocked.
local function makeHolder(name, label)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:EnableMouse(false)
    holder:RegisterForDrag("LeftButton")
    holder:Hide()

    holder.box = holder:CreateTexture(nil, "BACKGROUND")
    holder.box:SetAllPoints()
    holder.box:SetTexture(WHITE)
    holder.box:SetVertexColor(0.2, 0.6, 1, 0.35)
    holder.box:Hide()

    holder.boxLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.boxLabel:SetPoint("BOTTOM", holder, "TOP", 0, 2)
    holder.boxLabel:SetText(label)
    holder.boxLabel:Hide()
    return holder
end

local killHolder = makeHolder("DoesItDieScreenKill", "DoesItDie kill icon (drag)")

local killWindow = CreateFrame("Frame", nil, killHolder)
killWindow:SetAllPoints()
killWindow:SetClipsChildren(true)

local killBar = CreateFrame("StatusBar", nil, killWindow)
killBar:SetPoint("RIGHT", killWindow, "RIGHT")
killBar:SetStatusBarTexture(WHITE)
killBar:SetStatusBarColor(0, 0, 0, 0)

local killIcon = killBar:CreateTexture(nil, "OVERLAY")
killIcon:SetPoint("RIGHT", killBar:GetStatusBarTexture(), "RIGHT")

local killPulse = killIcon:CreateAnimationGroup()
killPulse:SetLooping("BOUNCE")
local killPulseAlpha = killPulse:CreateAnimation("Alpha")
killPulseAlpha:SetFromAlpha(1)
killPulseAlpha:SetToAlpha(0.5)
killPulseAlpha:SetDuration(0.6)
killPulseAlpha:SetSmoothing("IN_OUT")

local dotsHolder = makeHolder("DoesItDieScreenDots", "DoesItDie DoT icons (drag)")
local dotButtons = {}

local function dotButton(i)
    local button = dotButtons[i]
    if button then return button end
    button = CreateFrame("Frame", nil, dotsHolder)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetTexture(WHITE)
    button.border:SetVertexColor(0, 0, 0, 1)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:SetReverse(true)       -- drains like a debuff
    button.cooldown:SetDrawEdge(false)
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(false) end
    button.damage = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.damage:SetPoint("TOP", button, "BOTTOM", 0, -1)
    dotButtons[i] = button
    return button
end

local function spellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex and not isSecret(tex) then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, spellID)
        if ok and tex and not isSecret(tex) then return tex end
    end
    return 134400 -- question mark
end

local function shortNumber(n)
    if n >= 10000 then return string.format("%.0fk", n / 1000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local anchorMissingSince = {} -- holder -> time we last looked for its anchor frame

-- Frame paths like "TellMeWhen_Group1_Icon1" or "ElvUF_Target.Health".
local function resolveFrame(path)
    if type(path) ~= "string" or path == "" then return nil end
    local frame
    for part in path:gmatch("[^%.]+") do
        if frame == nil then frame = _G[part] else frame = type(frame) == "table" and frame[part] or nil end
        if frame == nil then return nil end
    end
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return nil end
    return frame
end

local function placeHolder(holder, pos, anchorName, attachPoint, anchorPoint)
    holder:ClearAllPoints()
    local anchor = resolveFrame(anchorName)
    if anchor then
        holder:SetPoint(attachPoint, anchor, anchorPoint, 0, 0)
        holder.anchored = anchor
        -- Draw above the anchor (a TellMeWhen icon, say). Level reads can be refused on some frames.
        local ok, level = pcall(anchor.GetFrameLevel, anchor)
        if ok and type(level) == "number" and not isSecret(level) then holder:SetFrameLevel(level + 10) end
        return true
    end
    holder.anchored = nil
    holder:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    return anchorName == nil
end

local function applyLayout()
    local s = settings()
    if not s then return end
    killHolder:SetSize(s.killSize, s.killSize)
    killBar:SetSize(SKULL_BAR_LENGTH, s.killSize)
    killIcon:SetSize(s.killSize, s.killSize)
    killIcon:SetTexture(killTexturePath())
    for _, button in pairs(dotButtons) do button:SetSize(s.dotSize, s.dotSize) end
    dotsHolder:SetSize(4 * (s.dotSize + DOT_SPACING), s.dotSize + 14)

    if not placeHolder(killHolder, s.killPos, s.killAnchor, "CENTER", "CENTER") then
        anchorMissingSince[killHolder] = GetTime()
    else
        anchorMissingSince[killHolder] = nil
    end
    if not placeHolder(dotsHolder, s.dotsPos, s.dotsAnchor, "TOP", "BOTTOM") then
        anchorMissingSince[dotsHolder] = GetTime()
    else
        anchorMissingSince[dotsHolder] = nil
    end

    local unlocked = not s.locked
    for _, holder in ipairs({ killHolder, dotsHolder }) do
        local draggable = unlocked and not holder.anchored
        holder:EnableMouse(draggable)
        holder.box:SetShown(unlocked)
        holder.boxLabel:SetShown(unlocked)
    end
end

local function savePosition(holder, pos)
    local point, _, relPoint, x, y = holder:GetPoint(1)
    pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
end

killHolder:SetScript("OnDragStart", function(self) self:StartMoving() end)
killHolder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local s = settings()
    if s then savePosition(self, s.killPos) end
end)
dotsHolder:SetScript("OnDragStart", function(self) self:StartMoving() end)
dotsHolder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local s = settings()
    if s then savePosition(self, s.dotsPos) end
end)

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function unitUsable(unit)
    if not UnitExists(unit) then return false end
    local ok, dead = pcall(UnitIsDead, unit)
    return not (ok and not isSecret(dead) and dead)
end

local reportedError = false

local function updateKill(s, unit)
    if not s.showKill then return killHolder:Hide() end
    if not s.locked then -- show the icon in full so it can be placed
        killBar:SetMinMaxValues(0, 1)
        killBar:SetValue(1)
        if not killPulse:IsPlaying() then killPulse:Play() end
        return killHolder:Show()
    end
    local damage, count = DoesItDieAPI.GetRemaining(unit)
    if count == 0 or damage <= 0 or not unitUsable(unit) then return killHolder:Hide() end
    local ok, err = pcall(function()
        killBar:SetMinMaxValues(0, UnitHealth(unit)) -- secret: only the StatusBar compares it
        killBar:SetValue(damage)
    end)
    if not ok then
        if not reportedError then
            reportedError = true
            trace("ERROR screen kill icon: " .. tostring(err))
            print("On-screen kill icon failed (logged): " .. tostring(err))
        end
        return killHolder:Hide()
    end
    if not killPulse:IsPlaying() then killPulse:Play() end
    killHolder:Show()
end

local PREVIEW_DOTS = {
    { name = "Preview", spellID = 172, appliedAt = 0, duration = 18, timeLeft = 12, damage = 420, waiting = false },
    { name = "Preview2", spellID = 348, appliedAt = 0, duration = 15, timeLeft = 6, damage = 1350, waiting = true },
}

local function updateDots(s, unit)
    if not s.showDots then return dotsHolder:Hide() end
    local list
    if not s.locked then
        list = PREVIEW_DOTS
    elseif unitUsable(unit) then
        list = DoesItDieAPI.GetDots(unit)
    else
        list = {}
    end

    local shown = math.min(#list, MAX_DOT_ICONS)
    for i = 1, shown do
        local entry, button = list[i], dotButton(i)
        button:SetSize(s.dotSize, s.dotSize)
        button:ClearAllPoints()
        -- Centered row under the holder's top edge.
        local offset = (i - 1 - (shown - 1) / 2) * (s.dotSize + DOT_SPACING)
        button:SetPoint("TOP", dotsHolder, "TOP", offset, 0)
        button.icon:SetTexture(spellTexture(entry.spellID))
        button.icon:SetDesaturated(entry.waiting)
        button.damage:SetText(shortNumber(entry.damage))
        local start = entry.appliedAt
        if not s.locked then start = GetTime() - (entry.duration - entry.timeLeft) end
        if button.start ~= start or button.duration ~= entry.duration then
            button.start, button.duration = start, entry.duration
            button.cooldown:SetCooldown(start, entry.duration)
        end
        button:Show()
    end
    for i = shown + 1, #dotButtons do
        local button = dotButtons[i]
        button:Hide()
        button.start, button.duration = nil, nil
    end
    dotsHolder:SetShown(shown > 0 or not s.locked)
end

local layoutSignature
local function update()
    local s = settings()
    if not s or not DoesItDieAPI then return end
    if not s.enabled then
        killHolder:Hide()
        dotsHolder:Hide()
        return
    end

    -- Re-layout when settings change, the kill icon choice changes, or an anchor frame may have appeared
    -- (TellMeWhen builds its icons after login, and rebuilds them when you change its config).
    local signature = table.concat({ tostring(s.killSize), tostring(s.dotSize), tostring(s.locked),
        tostring(s.killAnchor), tostring(s.dotsAnchor), tostring(ns.db.skullIcon) }, "|")
    local now = GetTime()
    local retry = false
    for _, since in pairs(anchorMissingSince) do
        if now - since > ANCHOR_RETRY_SECONDS then retry = true end
    end
    if signature ~= layoutSignature or retry then
        layoutSignature = signature
        applyLayout()
    end

    local unit = s.unit or "target"
    updateKill(s, unit)
    updateDots(s, unit)
end

local function safeUpdate()
    local ok, err = pcall(update)
    if not ok and not reportedError then
        reportedError = true
        trace("ERROR in screen icons update: " .. tostring(err))
        print("On-screen icons error (logged): " .. tostring(err))
    end
end

local driver = CreateFrame("Frame")
local elapsedSince = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < UPDATE_INTERVAL then return end
    elapsedSince = 0
    safeUpdate()
end)
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then layoutSignature = nil end
    safeUpdate()
end)

---------------------------------------------------------------------------
-- /did screen ...
---------------------------------------------------------------------------

local HELP = {
    "/did screen - turn the on-screen icons on/off",
    "/did screen unlock | lock - drag the icons into place (preview shown while unlocked)",
    "/did screen kill on|off  /  dots on|off - which icons to show",
    "/did screen size <px>  /  dotsize <px> - icon sizes",
    "/did screen anchor <FrameName> - pin the kill icon on a frame, e.g. TellMeWhen_Group1_Icon1",
    "/did screen dotsanchor <FrameName> - pin the DoT row under a frame;  'anchor off' / 'dotsanchor off' to unpin",
    "/did screen unit target|focus - whose DoTs to show",
    "/did screen frame on|off - the original marker and kill icon on the target frame",
    "/did screen only - on-screen icons on, target frame display off",
    "/did screen reset - default positions and sizes",
}

local function onOff(word, current)
    if word == "on" then return true end
    if word == "off" then return false end
    return not current
end

function ns.screenCommand(msg)
    local first, rest = strtrim(msg):match("^(%S+)%s*(.-)$")
    if not first or strlower(first) ~= "screen" then return false end
    local s = settings()
    if not s then print("Not loaded yet."); return true end
    local db = ns.db
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
    sub = strlower(sub or "")
    local lowerArg = strlower(arg or "")

    if sub == "" then
        s.enabled = not s.enabled
        print("On-screen icons " .. (s.enabled and "ON" or "OFF") .. ". /did screen help for options.")
    elseif sub == "on" or sub == "off" then
        s.enabled = sub == "on"
        print("On-screen icons " .. (s.enabled and "ON" or "OFF") .. ".")
    elseif sub == "unlock" then
        s.enabled, s.locked = true, false
        print("Unlocked: drag the blue boxes. Anchored icons stay on their frame. /did screen lock when done.")
    elseif sub == "lock" then
        s.locked = true
        print("Locked.")
    elseif sub == "kill" then
        s.showKill = onOff(lowerArg, s.showKill)
        print("On-screen kill icon " .. (s.showKill and "ON" or "OFF") .. ".")
    elseif sub == "dots" then
        s.showDots = onOff(lowerArg, s.showDots)
        print("On-screen DoT icons " .. (s.showDots and "ON" or "OFF") .. ".")
    elseif sub == "size" or sub == "dotsize" then
        local n = tonumber(arg)
        if not n or n < 8 or n > 256 then print("Give a size in pixels, 8-256."); return true end
        if sub == "size" then s.killSize = math.floor(n) else s.dotSize = math.floor(n) end
        print((sub == "size" and "Kill icon" or "DoT icon") .. " size " .. math.floor(n) .. ".")
    elseif sub == "anchor" or sub == "dotsanchor" then
        local field = sub == "anchor" and "killAnchor" or "dotsAnchor"
        if arg == "" or lowerArg == "off" or lowerArg == "none" then
            s[field] = nil
            print("Unpinned; back at its dragged position.")
        else
            s[field] = arg
            if resolveFrame(arg) then
                print("Pinned to " .. arg .. ".")
            else
                print("Pinned to " .. arg .. " (not found yet; it will attach when that frame exists).")
            end
        end
    elseif sub == "unit" then
        if lowerArg == "" then print("Unit: " .. tostring(s.unit)); return true end
        s.unit = lowerArg
        print("Showing DoTs on " .. lowerArg .. ".")
    elseif sub == "frame" then
        local show = onOff(lowerArg, db.showSkull or db.showMarkers)
        db.showSkull, db.showMarkers = show, show
        if not show then db.showLabel = false end -- the label keeps the marker bar up on its own
        print("Target frame marker and kill icon " .. (show and "ON" or "OFF") .. ".")
    elseif sub == "only" then
        s.enabled = true
        db.showSkull, db.showMarkers, db.showLabel = false, false, false
        print("On-screen icons ON; target frame marker and kill icon OFF (/did screen frame on to restore).")
    elseif sub == "reset" then
        db.screen = nil
        local fresh = settings()
        fresh.enabled = s.enabled
        print("On-screen icons reset.")
    else
        for _, line in ipairs(HELP) do print(line) end
        return true
    end
    layoutSignature = nil
    safeUpdate()
    if ns.refresh then ns.refresh() end
    return true
end
