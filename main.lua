
-- Imports --
local characters = include("mod.stats")
local heartConverter = include("lib.heartConversion")
-- file loc
local _, _err = pcall(require, "")
---@type string
local modName = _err:match("/mods/(.*)/%.lua")

-- Init --
local mod = RegisterMod(modName, 1)
-- CODE --
local config = Isaac.GetItemConfig()
local game = Game()
local pool = game:GetItemPool()
local game_started = false -- a hacky check for if the game is continued.
local is_continued = false -- a hacky check for if the game is continued.
local isBirthRightPickedUp = false
local isBirthRightCleared = false
local item1FromStart = -1
local item2FromStart = -1
local is1969 = false
local isDeadCatCleared = false
local itemTrack = {}
-- local catItemCount = 0
-- Utility Functions

---converts tearRate to the FireDelay formula, then modifies the FireDelay by the request amount, returns Modified FireDelay
---@param currentTearRate number
---@param offsetBy number
---@return number
local function calculateNewFireDelay(currentTearRate, offsetBy)
    local currentTears = 30 / (currentTearRate + 1)
    local newTears = currentTears + offsetBy
    return math.max((30 / newTears) - 1, -0.9999)
end

local function contains(array, target)
    for _, value in ipairs(array) do
        if value == target then
            return true
        end
    end
    return false
end

-- Character Code

-- go through each our characters and register them to the heartConverter if need be
local didConvert = false

for i,v in pairs(characters) do
    if type(v) == "table" then
        ---@cast v CharacterSet
        local normalPType = Isaac.GetPlayerTypeByName(v.normal.name)
        if v.normal.soulHeartOnly then
            didConvert = true
            heartConverter.registerCharacterHealthConversion(normalPType, HeartSubType.HEART_SOUL)
        elseif v.normal.blackHeartOnly then
            didConvert = true
            heartConverter.registerCharacterHealthConversion(normalPType, HeartSubType.HEART_BLACK)
        end
        if v.hasTainted then
            local taintedPType = Isaac.GetPlayerTypeByName(v.tainted.name, true)
            if v.tainted.soulHeartOnly then
                didConvert = true
                heartConverter.registerCharacterHealthConversion(taintedPType, HeartSubType.HEART_SOUL)
            elseif v.tainted.blackHeartOnly then
                didConvert = true
                heartConverter.registerCharacterHealthConversion(taintedPType, HeartSubType.HEART_BLACK)
            end
        end
    end
end

if didConvert then
    heartConverter.characterHealthConversionInit(mod)
end

---@param _ any
---@param player EntityPlayer
---@param cache CacheFlag | BitSet128
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, function(_, player, cache)
    if not (characters:isACharacterDescription(player)) then return end

    local playerStat = characters:getCharacterDescription(player).stats

    if not (playerStat) then return end

    if (playerStat.Damage and cache & CacheFlag.CACHE_DAMAGE == CacheFlag.CACHE_DAMAGE) then
        player.Damage = player.Damage + playerStat.Damage
    end

    if (playerStat.Firedelay and cache & CacheFlag.CACHE_FIREDELAY == CacheFlag.CACHE_FIREDELAY) then
        player.MaxFireDelay = calculateNewFireDelay(player.MaxFireDelay, playerStat.Firedelay)
    end

    if (playerStat.Shotspeed and cache & CacheFlag.CACHE_SHOTSPEED == CacheFlag.CACHE_SHOTSPEED) then
        player.ShotSpeed = player.ShotSpeed + playerStat.Shotspeed
    end

    if (playerStat.Range and cache & CacheFlag.CACHE_RANGE == CacheFlag.CACHE_RANGE) then
        player.TearRange = player.TearRange + playerStat.Range
    end

    if (playerStat.Speed and cache & CacheFlag.CACHE_SPEED == CacheFlag.CACHE_SPEED) then
        player.MoveSpeed = player.MoveSpeed + playerStat.Speed
    end

    if (playerStat.Luck and cache & CacheFlag.CACHE_LUCK == CacheFlag.CACHE_LUCK) then
        player.Luck = player.Luck + playerStat.Luck
    end

    if (cache & CacheFlag.CACHE_FLYING == CacheFlag.CACHE_FLYING and playerStat.Flying == true) then player.CanFly = true end

    if (playerStat.Tearflags and cache & CacheFlag.CACHE_TEARFLAG == CacheFlag.CACHE_TEARFLAG) then
        player.TearFlags = player.TearFlags | playerStat.Tearflags
    end

    if (playerStat.Tearcolor and cache & CacheFlag.CACHE_TEARCOLOR == CacheFlag.CACHE_TEARCOLOR) then
        player.TearColor = playerStat.Tearcolor
    end
end)

---applies the costume to the player
---@param CostumeName string
---@param player EntityPlayer
local function applyCostume(CostumeName, player) -- actually adds the costume.
    local cost = Isaac.GetCostumeIdByPath("gfx/characters/" .. CostumeName .. ".anm2")
    if (cost ~= -1) then player:AddNullCostume(cost) end
end

---goes through each costume and applies it
---@param AppliedCostume table
---@param player EntityPlayer
local function addCostumes(AppliedCostume, player) -- costume logic
    if #AppliedCostume == 0 then return end
    if (type(AppliedCostume) == "table") then
        for i = 1, #AppliedCostume do
            applyCostume(AppliedCostume[i], player)
        end
    end
end

local function getRandomItem(seed)
    local RECOMMENDED_SHIFT_IDX = 35
    local game = Game()
    local seeds = game:GetSeeds()
    local startSeed = seeds:GetStartSeed()
    local rng = RNG()
    rng:SetSeed(startSeed, RECOMMENDED_SHIFT_IDX + seed)
    local randomItem = -1
    local curSeed = -10;
    while (randomItem == -1 or randomItem == 550 or randomItem == 552 or 
    randomItem == 551 or randomItem == 668 or randomItem == 714 or 
    randomItem == 715 or randomItem == 626 or randomItem == 627 or randomItem == 258) do
        randomItem = rng:RandomInt(719)
        rng:SetSeed(startSeed, RECOMMENDED_SHIFT_IDX + seed + curSeed)
        curSeed = curSeed - 1
    end
    return randomItem
end

--Add two random items at the start of the game
--1969 can get at most 1 active item, and more likely to get low quality items
local function addRandomItems()
    local player = Isaac.GetPlayer()
    if (player:GetName() == '1969_b' or player:GetName() == '1969') then
        local item1 = -1 
        local item2 = -1
        local seed = 1

        local isItem1Added = false

        while (not isItem1Added) do
            item1 = getRandomItem(seed)
            seed = seed + 1 
            local item1Config = Isaac.GetItemConfig():GetCollectible(item1)
            if (not item1Config) then
                goto continue
            end
            
            if (item1Config.Quality >= 3) then
                item1 = getRandomItem(seed)
                seed = seed + 1
            end
            player:AddCollectible(item1, 0, true, 0, 0)
            isItem1Added = true
            item1FromStart = item1
            if (not contains(itemTrack, item1)) then
                table.insert(itemTrack, item1)
            end
            ::continue::
        end

        local isItem2Added = false
        while (item2 == -1 or not isItem2Added) do 
            item2 = getRandomItem(seed)
            seed = seed + 1
            local item2Config = Isaac.GetItemConfig():GetCollectible(item2)
            if (not item2Config) then
                goto continue
            end
            if (item2Config.Quality >= 3) then
                goto continue
            elseif (item2Config.Type ~= 1) then
                goto continue
            elseif (item2 == item1) then
                goto continue
            else
                isItem2Added = true
                item2FromStart = item2
                if (not contains(itemTrack, item2)) then
                    table.insert(itemTrack, item2)
                end
                player:AddCollectible(item2, 0, true, 0, 0)
            end
            ::continue::
        end
    end
 
end


---@param player EntityPlayer
local function CriticalHitCacheCallback(player)
    if not (characters:isACharacterDescription(player)) then return end

    local playerStat = characters:getCharacterDescription(player).stats
    local data = player:GetData()

    if (playerStat.criticalChance) then
        data.critChance = data.critChance + playerStat.criticalChance
    end

    if (playerStat.criticalMultiplier) then
        data.critMultiplier = data.critMultiplier + playerStat.criticalMultiplier
    end
end

function mod:newRoomCallBack()
    player = Isaac.GetPlayer()
    if (not (player:GetName() == '1969_b' or player:GetName() == '1969') and is1969 == true) then
        is1969 = false
        local hair = Isaac.GetCostumeIdByPath("gfx/characters/" .. "character_1969_hair" .. ".anm2")
        player:TryRemoveNullCostume(hair)
    end
    if (player:GetName() == '1969_b' or player:GetName() == '1969') then
        if (item1FromStart ~= -1 and item2FromStart ~= -1) then
            Game():GetItemPool():RemoveCollectible(item1FromStart)
            Game():GetItemPool():RemoveCollectible(item2FromStart)
        end

        if (player:HasCollectible(619)) then
            for i, entity in ipairs(Isaac.GetRoomEntities()) do
                if (entity:IsActiveEnemy() and not entity:IsBoss() and entity:IsVulnerableEnemy()) then
                    Isaac.Spawn(entity.Type, entity.Variant,entity.SubType, entity.Position, entity.Velocity, entity.SpawnerEntity)
                end
            end
        end
    end

end

---@param player? EntityPlayer
local function postPlayerInitLate(player)
    player = player or Isaac.GetPlayer()
    if not (characters:isACharacterDescription(player)) then return end
    local statTable = characters:getCharacterDescription(player)
    if statTable == nil then return end
    -- Costume
    addCostumes(statTable.costume, player)

    local items = statTable.items
    if (#items > 0) then
        for i, v in ipairs(items) do
            player:AddCollectible(v[1])
            if (v[2]) then
                local ic = config:GetCollectible(v[1])
                player:RemoveCostume(ic)
            end
        end
        local charge = statTable.charge
        if (charge and player:GetActiveItem()) then
            if (charge == true) then
                player:FullCharge()
            else
                player:SetActiveCharge(charge)
            end
        end
    end

    local trinket = statTable.trinket
    if (trinket) then player:AddTrinket(trinket, true) end

    if (statTable.PocketItem) then
        if statTable.isPill then
            player:SetPill(0, pool:ForceAddPillEffect(statTable.PocketItem))
        else
            player:SetCard(0, statTable.PocketItem)
        end
    end

    if CriticalHit then
        CriticalHit:AddCacheCallback(CriticalHitCacheCallback)
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
    itemTrack = {}
    addRandomItems();

    if (player:GetName() == '1969_b' or player:GetName() == '1969') then
        local hair = Isaac.GetCostumeIdByPath("gfx/characters/" .. "character_1969_hair" .. ".anm2")
        player:AddNullCostume(hair)
        is1969 = true
    end
    
end

---@param _ any
---@param Is_Continued boolean
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, Is_Continued)
    if (not Is_Continued) then
        is_continued = false
        postPlayerInitLate()
    end
    game_started = true
    isBirthRightPickedUp = false
    isBirthRightCleared = false
    isDeadCatCleared = false
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    game_started = false
end)

---@param _ any
---@param player EntityPlayer
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_INIT, function(_, player)
    if (game_started == false) then return end
    if (not is_continued) then
        postPlayerInitLate(player)
    end
end)

-- put your custom code here!

local function birthright()
    local player = Isaac.GetPlayer()
    if (player:GetName() == '1969_b' or player:GetName() == '1969') then
        for i = 1, #itemTrack do
            player:AddCollectible(itemTrack[i], 0, true, 0, 0)
        end
        isBirthRightPickedUp = true
    end
end

-- local function birthrightClear()
--     local player = Isaac.GetPlayer()
--     if (player:GetName() == '1969_b') then
--         local newCount = catCount()
--         if (newCount >= catItemCount + 1) then
--             for i, entity in ipairs(Isaac.GetRoomEntities()) do
--             if (entity.Type == 5 and entity.Variant == 100 and 
--                 (entity.SubType == 145 or entity.SubType == 133 or entity.SubType == 81 or entity.SubType == 212 or 
--                 entity.SubType == 187 or entity.SubType == 134 or entity.SubType == 665)) then
--                     entity:Remove()
--                 end
--             end
--             isBirthRightCleared = true
--         end
--     end
-- end

local function deadCatClear()
    local player = Isaac.GetPlayer()
    if (player:GetName() == '1969_b') then
        local curHeart = player:GetSoulHearts()
        player:AddBlackHearts(-curHeart)
        player:AddBlackHearts(2)
        isDeadCatCleared = true
    end
end

local function ConvertRedHearts(player)
	local skipConversion = false
	local redHeartContainerCost = 2
	local blackHeartsPerRedHeart = 2
    local boneHeartContainerCost = 1
    local blackHeartsPerBoneHeart = 2
	local healBeforeConversion = true

	if skipConversion == false then
		if healBeforeConversion == true then
			player:SetFullHearts() -- Heal all red hearts
		end
		local blackHeartsConverted = 0
		while player:GetHearts() + player:GetBoneHearts() >= redHeartContainerCost do -- While Mei has enough red hearts containers to convert
            if player:GetBoneHearts() >= boneHeartContainerCost then
                player:AddBoneHearts(-boneHeartContainerCost ) -- Remove them
                player:AddBlackHearts(blackHeartsPerBoneHeart) -- Add their value in black hearts
				blackHeartsConverted = blackHeartsConverted + blackHeartsPerBoneHeart
            else
                player:AddMaxHearts(-redHeartContainerCost, true) -- Remove them
                player:AddBlackHearts(blackHeartsPerRedHeart) -- Add their value in black hearts
				blackHeartsConverted = blackHeartsConverted + blackHeartsPerRedHeart
            end
		end
		player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
		player:EvaluateItems()
	end
end


function mod:PostRender()
    local player = Isaac.GetPlayer()
    if (player:GetName() == '1969_b') then
        ConvertRedHearts( player )
        if (player:HasCollectible(619) and not isBirthRightPickedUp) then
            birthright()
        end

        if (player:HasCollectible(81) and not isDeadCatCleared) then
            deadCatClear()
        end
        local queueItemData = player.QueuedItem
        if (queueItemData.Item) then
            if (not contains(itemTrack, queueItemData.Item.ID) and (Isaac.GetItemConfig():GetCollectible(queueItemData.Item.ID).Type ~= 3)) then
                table.insert(itemTrack, queueItemData.Item.ID)
            end
        end
    end
    if (player:GetName() == '1969') then
        if (player:HasCollectible(619) and not isBirthRightPickedUp) then
            birthright()
        end

        if (player:HasCollectible(81) and not isDeadCatCleared) then
            deadCatClear()
        end
        local queueItemData = player.QueuedItem
        if (queueItemData.Item) then
            if (not contains(itemTrack, queueItemData.Item.ID) and (Isaac.GetItemConfig():GetCollectible(queueItemData.Item.ID).Type ~= 3)) then
                table.insert(itemTrack, queueItemData.Item.ID)
            end
        end
    end

end

mod:AddCallback( ModCallbacks.MC_POST_RENDER, mod.PostRender)
mod:AddCallback( ModCallbacks.MC_POST_NEW_ROOM, mod.newRoomCallBack)
::EndOfFile::
