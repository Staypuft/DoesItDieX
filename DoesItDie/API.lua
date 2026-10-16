-- DoesItDie public API: a global table other addons (TellMeWhen Lua conditions, WeakAuras, macros) can read.
--
-- Everything returned here is a PLAIN number/boolean/string you can compare and do math with, because it's the
-- addon's own estimate built from your casts and the UNIT_COMBAT hits it saw. The one exception is
-- GetKillBar's second return value, the unit's health, which Forever keeps SECRET: it can only be handed to a
-- StatusBar (or a TellMeWhen "Lua Value" bar), never compared. That's also why there is no WillDie() function:
-- "remaining damage >= health" can't be computed by addon code on Forever. A StatusBar can show it, which is how
-- the kill icon works (see ScreenIcons.lua).
--
-- Unit arguments default to "target" and accept any unit token the addon can see ("focus", "nameplate3", ...).
-- Spell arguments accept a spell name ("Corruption", case-insensitive) or a spell ID (any rank's ID matches
-- only that rank, so names are usually what you want).
--
-- Examples (TellMeWhen > Conditions > Misc > Lua):
--   DoesItDieAPI.GetRemaining() > 2000                -- my DoTs on the target still have 2000+ damage to deal
--   not DoesItDieAPI.HasDot("target", "Corruption")   -- Corruption is missing on the target
--   DoesItDieAPI.DotTimeLeft("target", "Immolate") < 3 -- Immolate is about to fall off (0 when missing)
--   DoesItDieAPI.CountDots() >= 3                      -- three or more of my DoTs are on the target

local ADDON_NAME, ns = ...

local API = {}
DoesItDieAPI = API
API.version = 1

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

local function unitIsDead(unit)
    local ok, dead = pcall(UnitIsDead, unit)
    return ok and not isSecret(dead) and dead or false
end

-- The live dot records for a unit, or nil. Records whose time is up are skipped by the callers below (the main
-- file's housekeeping removes them every 0.1s, but a caller may run in between).
local function dotsFor(unit)
    if not ns.unitKey or not ns.dotsByTarget then return nil end -- DoesItDie.lua failed to load
    unit = unit or "target"
    if not UnitExists(unit) or unitIsDead(unit) then return nil end
    local key = ns.unitKey(unit)
    return key and ns.dotsByTarget[key]
end

local function matches(name, dot, spell)
    if spell == nil then return true end
    if type(spell) == "number" then return dot.spellID == spell end
    return strlower(name) == strlower(tostring(spell))
end

local function entryFor(name, dot, now)
    local waiting = ns.isWaiting(dot)
    return {
        name = name,
        spellID = dot.spellID,
        school = dot.school,
        appliedAt = dot.appliedAt,
        duration = dot.duration,
        expiresAt = dot.expiresAt,
        timeLeft = math.max(0, dot.expiresAt - now),
        -- What it still has to deal. Waiting DoTs (no tick seen yet, and the settings say to wait) have an
        -- estimate too, but the marker and kill icon leave them out until they tick; so does GetRemaining.
        damage = math.floor(ns.remainingDamage(dot) + 0.5),
        waiting = waiting,
        ticksSeen = dot.ticksSeen,
        -- true once ticks were seen or a learned tick size was used: the estimate is trustworthy
        confident = dot.ticksSeen > 0 or not dot.unsure,
    }
end

-- Damage your DoTs on `unit` still have to deal, and how many DoTs that counts. Same number the target frame
-- marker shows (DoTs waiting for their first tick are left out).
function API.GetRemaining(unit)
    local dots = dotsFor(unit)
    if not dots then return 0, 0 end
    local now, total, count = GetTime(), 0, 0
    for _, dot in pairs(dots) do
        if now <= dot.expiresAt and not ns.isWaiting(dot) then
            total = total + ns.remainingDamage(dot)
            count = count + 1
        end
    end
    return math.floor(total + 0.5), count
end

-- Every DoT of yours on `unit` (waiting ones included, with waiting = true), oldest first. See entryFor for the
-- fields. Returns a new table each call.
function API.GetDots(unit)
    local list, dots = {}, dotsFor(unit)
    if not dots then return list end
    local now = GetTime()
    for name, dot in pairs(dots) do
        if now <= dot.expiresAt then table.insert(list, entryFor(name, dot, now)) end
    end
    table.sort(list, function(a, b) return a.appliedAt < b.appliedAt end)
    return list
end

-- One DoT (see GetDots for the fields), or nil.
function API.GetDot(unit, spell)
    local dots = dotsFor(unit)
    if not dots then return nil end
    local now = GetTime()
    for name, dot in pairs(dots) do
        if now <= dot.expiresAt and matches(name, dot, spell) then return entryFor(name, dot, now) end
    end
    return nil
end

-- Whether that DoT of yours is on `unit` (waiting ones count: it was cast and not seen to miss). No table
-- allocation, so it's cheap to poll.
function API.HasDot(unit, spell)
    return API.DotTimeLeft(unit, spell) > 0
end

-- Seconds until that DoT expires, 0 if it isn't there.
function API.DotTimeLeft(unit, spell)
    local dots = dotsFor(unit)
    if not dots then return 0 end
    local now = GetTime()
    for name, dot in pairs(dots) do
        if now <= dot.expiresAt and matches(name, dot, spell) then return math.max(0, dot.expiresAt - now) end
    end
    return 0
end

-- Damage that DoT still has to deal, 0 if it isn't there (waiting ones included).
function API.DotDamage(unit, spell)
    local dots = dotsFor(unit)
    if not dots then return 0 end
    local now = GetTime()
    for name, dot in pairs(dots) do
        if now <= dot.expiresAt and matches(name, dot, spell) then
            return math.floor(ns.remainingDamage(dot) + 0.5)
        end
    end
    return 0
end

-- Number of your DoTs on `unit`, waiting ones included (GetRemaining's count leaves those out).
function API.CountDots(unit)
    local dots = dotsFor(unit)
    if not dots then return 0 end
    local now, count = GetTime(), 0
    for _, dot in pairs(dots) do
        if now <= dot.expiresAt then count = count + 1 end
    end
    return count
end

-- For StatusBars only: remaining DoT damage and the unit's CURRENT health (SECRET on Forever). Put them in a
-- bar as value and max: the bar is full exactly when your DoTs will kill the unit. Never compare the second value.
function API.GetKillBar(unit)
    unit = unit or "target"
    local damage = API.GetRemaining(unit)
    local ok, health = pcall(UnitHealth, unit)
    if not ok then return damage, 1 end
    return damage, health -- no `ok and health or 1`: even a truth test on a secret can error
end
