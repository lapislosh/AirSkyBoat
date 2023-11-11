-----------------------------------
-- Dynamic lottery chance for placeholder-based NMs
-----------------------------------
require("modules/module_utils")
-----------------------------------
local m = Module:new("dynamic_lottery_chance")

-- HOW TO USE
-- Populate the nmList table with one entry for every NM to enable the feature on. See below for how to define a rule.

-- Dynamic lottery chance rules work as follows:
-- minValue (default 1.0): Multiplier for the base lottery chance of the NM when the NM window opens
-- maxValue (default 1.0): Multiplier for the base lottery chance of the NM when killsToMaxValue or timeToMaxValue has been reached (scaling linearly from minValue)
-- killsToMaxValue (optional, default 0): The number of times all placeholders must be killed to reach the maxValue multiplier (killsToMaxValue * numPlaceholders = totalKillsToMaxValue)
-- timeToMaxValue (optional, default 0): How long, in seconds, since the NM window opened to reach the maxValue multiplier
-- zone (optional): If using timeToMaxValue, the name of the zone the NM lives in so that its initial spawn time can be stored

local secondsPerHour = 3600
-- Replace the contents of this table with your custom spawn rules. Some sample rules are provided by default for example purposes.
local nmList =
{
    ["Aquarius"]                = { maxValue = 2.0, killsToMaxValue = 15 }, -- 2x after 15*9 kills (~4hr, if all placeholders are killed on cooldown)
    ["Cargo_Crab_Colin"]        = { maxValue = 2.0, killsToMaxValue = 18 }, -- 2x after 18*2 kills (~4hr)
    ["Charybdis"]               = { maxValue = 4.0, killsToMaxValue = 45 }, -- 4x after 90 kills (1x per ~8hr) - killsToMaxValue is halved because there are 2 ph but only 1 is spawned
    ["Jaggedy-Eared_Jack"]      = { maxValue = 2.0, timeToMaxValue = 6 * secondsPerHour, zone = "West_Ronfaure" }, -- 2x after 6 hours
    ["Mee_Deggi_the_Punisher"]  = { minValue = 0.9, maxValue = 2.0, timeToMaxValue = 12 * secondsPerHour, zone = "Castle_Oztroja" }, -- 0.9x to 2.0x over 12 hours, reaching 1.0x after 1.09hrs
    ["Novv_the_Whitehearted"]   = { maxValue = 2.0, timeToMaxValue = 48 * secondsPerHour, zone = "Sea_Serpent_Grotto" }, -- 2x after 48 hours
    ["Ungur"]                   = { maxValue = 2.0, killsToMaxValue = 15 }, -- 2x after 15 kills (~4hr)
    ["Valkurm_Emperor"]         = { minValue = 0.8, maxValue = 1.2, killsToMaxValue = 10 }, -- 0.8x to 1.2x over 10 kills (~55m)
    ["Wyvernpoacher_Drachlox"]  = { maxValue = 3.0, timeToMaxValue = 48 * secondsPerHour, zone = "Gustav_Tunnel" }, -- 3x after 48 hours(1x per 24hr)
}

local getRule = function(name)
    -- Note: If you want one rule to apply to all NMs (or any other advanced functionality), update this function to return the desired rule
    return nmList[name]
end

local countPH = function(phList)
    local count = 0

    for _ in pairs(phList) do
        count = count + 1
    end

    return count
end

-- Copied from mobs.lua
local function lotteryPrimed(phList)
    for k, v in pairs(phList) do
        local nm = GetMobByID(v)
        if
            nm ~= nil and
            (nm:isSpawned() or nm:getRespawnTime() ~= 0)
        then
            return true
        end
    end

    return false
end

-- Copied from mobs.lua
local function persistLotteryPrimed(phList)
    for k, v in pairs(phList) do
        local nm = GetMobByID(v)
        local zone = nm:getZone()
        local respawnPersist = zone:getLocalVar(string.format("\\[SPAWN\\]%s", nm:getID()))

        if respawnPersist == 0 then
            return false
        elseif
            nm ~= nil and
            (nm:isSpawned() or nm:getRespawnTime() ~= 0 or
            (respawnPersist > os.time()))
        then
            return true
        end
    end

    return false
end

-- Copy all the logic from phOnDespawn to see if a NM should pop except for the chance check
-- If everything here passes, the phOnDespawn will trigger the chance check to spawn the NM
local getNMIfSpawnable = function(ph, phList)
    local nmId = phList[ph:getID()]
    if
        nmId ~= nil and
        not lotteryPrimed(phList) and
        not persistLotteryPrimed(phList)
    then
        local nm = GetMobByID(nmId)
        if nm ~= nil then
            local pop = nm:getLocalVar("pop")
            if os.time() > pop then
                return nm
            end
        end
    end

    return nil
end

m:addOverride("xi.mob.phOnDespawn", function(ph, phList, chance, cooldown, immediate)
    -- Only run dynamic lottery code if the NM is actually has a chance to spawn, otherwise the tracking of ph kills will be incorrect
    local nm = getNMIfSpawnable(ph, phList)
    if nm ~= nil then
        local rule = getRule(nm:getName())

        if rule ~= nil then
            local percentToMaxValue = -1

            if rule.timeToMaxValue > 0 then
                local windowOpenedAt = nm:getLocalVar("pop")
                -- If for some reason pop hasn't been set, something has gone wrong so just use the default chance value
                if windowOpenedAt > 0 then
                    percentToMaxValue = (os.time() - windowOpenedAt) / rule.timeToMaxValue
                end
            elseif rule.killsToMaxValue > 0 then
                -- The specified kill count is how many times each PH must be killed
                local totalKillsToMaxValue = rule.killsToMaxValue * math.max(1, countPH(phList))

                -- The phKills rule increments by 1 every time a PH is killed, and when the number of PH kills reaches the target, maxValue is reached
                local phKills = nm:getLocalVar("phKills")
                percentToMaxValue = phKills / totalKillsToMaxValue
                nm:setLocalVar("phKills", phKills + 1)
            end

            -- Normalize percentToMaxValue from minValue to maxValue to determine the final multiplier
            if percentToMaxValue >= 0 then
                local multiplier = utils.clamp(percentToMaxValue * (rule.maxValue - rule.minValue) + rule.minValue, rule.minValue, rule.maxValue)
                chance = utils.clamp(chance * multiplier, 0, 100)
            end
        end
    end

    super(ph, phList, chance, cooldown, immediate)
end)

local onMobInit = function(mob)
    -- Normally phOnDespawn sets "pop" equal to when the window opens after a NM kill, but before the first kill the var won't exist
    local time = GetServerVariable(string.format("\\[SPAWN\\]%s", mob:getID()))
    if time == 0 then
        time = os.time()
    end

    mob:setLocalVar("pop", time)

    super(mob)
end

local initRule = function(name, rule)
    if rule ~= nil then
        if rule.minValue == nil then
            rule.minValue = 1.0
        end

        if rule.maxValue == nil then
            rule.maxValue = 1.0
        end

        if rule.killsToMaxValue == nil then
            rule.killsToMaxValue = 0
        end

        if rule.timeToMaxValue == nil then
            rule.timeToMaxValue = 0
        elseif rule.zone == nil then
            error("Cannot use a time-based dynamic lottery chance rule without specifying a zone for " .. name)
        else
            m:addOverride(string.format("xi.zones.%s.mobs.%s.onMobInitialize", rule.zone, name), onMobInit)
        end
    end
end

for name, rule in pairs(nmList) do
    initRule(name, rule)
end

return m
