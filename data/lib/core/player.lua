local foodCondition = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)

function Player.feed(self, food)
	local condition = self:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if condition then
		condition:setTicks(condition:getTicks() + (food * 1000))
	else
		local vocation = self:getVocation()
		if not vocation then
			return nil
		end

		foodCondition:setTicks(food * 1000)
		foodCondition:setParameter(CONDITION_PARAM_HEALTHGAIN, vocation:getHealthGainAmount())
		foodCondition:setParameter(CONDITION_PARAM_HEALTHTICKS, vocation:getHealthGainTicks() * 1000)
		foodCondition:setParameter(CONDITION_PARAM_MANAGAIN, vocation:getManaGainAmount())
		foodCondition:setParameter(CONDITION_PARAM_MANATICKS, vocation:getManaGainTicks() * 1000)

		self:addCondition(foodCondition)
	end
	return true
end

function Player.getClosestFreePosition(self, position, extended)
	if self:getGroup():getAccess() and self:getAccountType() >= ACCOUNT_TYPE_GOD then
		return position
	end
	return Creature.getClosestFreePosition(self, position, extended)
end

function Player.getDepotItems(self, depotId)
	return self:getDepotChest(depotId, true):getItemHoldingCount()
end

function Player.hasFlag(self, flag)
	return self:getGroup():hasFlag(flag)
end

function Player.getLossPercent(self)
	local blessings = 0
	local lossPercent = {
		[0] = 100,
		[1] = 70,
		[2] = 45,
		[3] = 25,
		[4] = 10,
		[5] = 0
	}

	for i = 1, 5 do
		if self:hasBlessing(i) then
			blessings = blessings + 1
		end
	end
	return lossPercent[blessings]
end

function Player.getPremiumTime(self)
	return math.max(0, self:getPremiumEndsAt() - os.time())
end

function Player.setPremiumTime(self, seconds)
	self:setPremiumEndsAt(os.time() + seconds)
	return true
end

function Player.addPremiumTime(self, seconds)
	self:setPremiumTime(self:getPremiumTime() + seconds)
	return true
end

function Player.removePremiumTime(self, seconds)
	local currentTime = self:getPremiumTime()
	if currentTime < seconds then
		return false
	end

	self:setPremiumTime(currentTime - seconds)
	return true
end

function Player.getPremiumDays(self)
	return math.floor(self:getPremiumTime() / 86400)
end

function Player.addPremiumDays(self, days)
	return self:addPremiumTime(days * 86400)
end

function Player.removePremiumDays(self, days)
	return self:removePremiumTime(days * 86400)
end

function Player.isPremium(self)
	return self:getPremiumTime() > 0 or configManager.getBoolean(configKeys.FREE_PREMIUM) or self:hasFlag(PlayerFlag_IsAlwaysPremium)
end

function Player.sendCancelMessage(self, message)
	if type(message) == "number" then
		message = Game.getReturnMessage(message)
	end
	return self:sendTextMessage(MESSAGE_STATUS_SMALL, message)
end

function Player.isUsingOtClient(self)
	return self:getClient().os >= CLIENTOS_OTCLIENT_LINUX
end

function Player.sendExtendedOpcode(self, opcode, buffer)
	if not self:isUsingOtClient() then
		return false
	end

	local networkMessage = NetworkMessage()
	networkMessage:addByte(0x32)
	networkMessage:addByte(opcode)
	networkMessage:addString(buffer)
	networkMessage:sendToPlayer(self)
	networkMessage:delete()
	return true
end

APPLY_SKILL_MULTIPLIER = true
local addSkillTriesFunc = Player.addSkillTries
function Player.addSkillTries(...)
	APPLY_SKILL_MULTIPLIER = false
	local ret = addSkillTriesFunc(...)
	APPLY_SKILL_MULTIPLIER = true
	return ret
end

local addManaSpentFunc = Player.addManaSpent
function Player.addManaSpent(...)
	APPLY_SKILL_MULTIPLIER = false
	local ret = addManaSpentFunc(...)
	APPLY_SKILL_MULTIPLIER = true
	return ret
end

-- Always pass the number through the isValidMoney function first before using the transferMoneyTo
function Player.transferMoneyTo(self, target, amount)
	if not target then
		return false
	end

	-- See if you can afford this transfer
	local balance = self:getBankBalance()
	if amount > balance then
		return false
	end

	-- See if player is online
	local targetPlayer = Player(target.guid)
	if targetPlayer then
		targetPlayer:setBankBalance(targetPlayer:getBankBalance() + amount)
	else
		db.query("UPDATE `players` SET `balance` = `balance` + " .. amount .. " WHERE `id` = '" .. target.guid .. "'")
	end

	self:setBankBalance(self:getBankBalance() - amount)
	return true
end

function Player.canCarryMoney(self, amount)
	-- Anyone can carry as much imaginary money as they desire
	if amount == 0 then
		return true
	end

	-- The 3 below loops will populate these local variables
	local totalWeight = 0
	local inventorySlots = 0

	-- Add crystal coins to totalWeight and inventorySlots
	local type_crystal = ItemType(ITEM_CRYSTAL_COIN)
	local crystalCoins = math.floor(amount / 10000)
	if crystalCoins > 0 then
		amount = amount - (crystalCoins * 10000)
		while crystalCoins > 0 do
			local count = math.min(100, crystalCoins)
			totalWeight = totalWeight + type_crystal:getWeight(count)
			crystalCoins = crystalCoins - count
			inventorySlots = inventorySlots + 1
		end
	end

	-- Add platinum coins to totalWeight and inventorySlots
	local type_platinum = ItemType(ITEM_PLATINUM_COIN)
	local platinumCoins = math.floor(amount / 100)
	if platinumCoins > 0 then
		amount = amount - (platinumCoins * 100)
		while platinumCoins > 0 do
			local count = math.min(100, platinumCoins)
			totalWeight = totalWeight + type_platinum:getWeight(count)
			platinumCoins = platinumCoins - count
			inventorySlots = inventorySlots + 1
		end
	end

	-- Add gold coins to totalWeight and inventorySlots
	local type_gold = ItemType(ITEM_GOLD_COIN)
	if amount > 0 then
		while amount > 0 do
			local count = math.min(100, amount)
			totalWeight = totalWeight + type_gold:getWeight(count)
			amount = amount - count
			inventorySlots = inventorySlots + 1
		end
	end

	-- If player don't have enough capacity to carry this money
	if self:getFreeCapacity() < totalWeight then
		return false
	end

	-- If player don't have enough available inventory slots to carry this money
	local backpack = self:getSlotItem(CONST_SLOT_BACKPACK)
	if not backpack or backpack:getEmptySlots(true) < inventorySlots then
		return false
	end
	return true
end

function Player.withdrawMoney(self, amount)
	local balance = self:getBankBalance()
	if amount > balance or not self:addMoney(amount) then
		return false
	end

	self:setBankBalance(balance - amount)
	return true
end

function Player.depositMoney(self, amount)
	if not self:removeMoney(amount) then
		return false
	end

	self:setBankBalance(self:getBankBalance() + amount)
	return true
end

function Player.removeTotalMoney(self, amount)
	local moneyCount = self:getMoney()
	local bankCount = self:getBankBalance()
	if amount <= moneyCount then
		self:removeMoney(amount)
		return true
	elseif amount <= (moneyCount + bankCount) then
		if moneyCount ~= 0 then
			self:removeMoney(moneyCount)
			local remains = amount - moneyCount
			self:setBankBalance(bankCount - remains)
			self:sendTextMessage(MESSAGE_INFO_DESCR, ("Paid %d from inventory and %d gold from bank account. Your account balance is now %d gold."):format(moneyCount, amount - moneyCount, self:getBankBalance()))
			return true
		else
			self:setBankBalance(bankCount - amount)
			self:sendTextMessage(MESSAGE_INFO_DESCR, ("Paid %d gold from bank account. Your account balance is now %d gold."):format(amount, self:getBankBalance()))
			return true
		end
	end
	return false
end

function Player.addLevel(self, amount, round)
	round = round or false
	local level, amount = self:getLevel(), amount or 1
	if amount > 0 then
		return self:addExperience(Game.getExperienceForLevel(level + amount) - (round and self:getExperience() or Game.getExperienceForLevel(level)))
	else
		return self:removeExperience(((round and self:getExperience() or Game.getExperienceForLevel(level)) - Game.getExperienceForLevel(level + amount)))
	end
end

function Player.addMagicLevel(self, value)
	local currentMagLevel = self:getBaseMagicLevel()
	local sum = 0

	if value > 0 then
		while value > 0 do
			sum = sum + self:getVocation():getRequiredManaSpent(currentMagLevel + value)
			value = value - 1
		end

		return self:addManaSpent(sum - self:getManaSpent())
	else
		value = math.min(currentMagLevel, math.abs(value))
		while value > 0 do
			sum = sum + self:getVocation():getRequiredManaSpent(currentMagLevel - value + 1)
			value = value - 1
		end

		return self:removeManaSpent(sum + self:getManaSpent())
	end
end

function Player.addSkillLevel(self, skillId, value)
	local currentSkillLevel = self:getSkillLevel(skillId)
	local sum = 0

	if value > 0 then
		while value > 0 do
			sum = sum + self:getVocation():getRequiredSkillTries(skillId, currentSkillLevel + value)
			value = value - 1
		end

		return self:addSkillTries(skillId, sum - self:getSkillTries(skillId))
	else
		value = math.min(currentSkillLevel, math.abs(value))
		while value > 0 do
			sum = sum + self:getVocation():getRequiredSkillTries(skillId, currentSkillLevel - value + 1)
			value = value - 1
		end

		return self:removeSkillTries(skillId, sum + self:getSkillTries(skillId), true)
	end
end

function Player.addSkill(self, skillId, value, round)
	if skillId == SKILL_LEVEL then
		return self:addLevel(value, round or false)
	elseif skillId == SKILL_MAGLEVEL then
		return self:addMagicLevel(value)
	end
	return self:addSkillLevel(skillId, value)
end

function Player.getWeaponType(self)
	local weapon = self:getSlotItem(CONST_SLOT_LEFT)
	if weapon then
		return weapon:getType():getWeaponType()
	end
	return WEAPON_NONE
end

function Player.getTotalMoney(self)
	return self:getMoney() + self:getBankBalance()
end

--function Player.getMaxTrackedQuests(self)
	--return configManager.getNumber(self:isPremium() and configKeys.QUEST_TRACKER_PREMIUM_LIMIT or configKeys.QUEST_TRACKER_FREE_LIMIT)
--end
function Player.getQuests(self)
	local quests = {}
	for _, quest in pairs(Game.getQuests()) do
		if quest:isStarted(self) then
			quests[#quests + 1] = quest
		end
	end
	return quests
end
function Player.sendQuestLog(self)
	local msg = NetworkMessage()
	msg:addByte(0xF0)
	local quests = self:getQuests()
	msg:addU16(#quests)
	for _, quest in pairs(quests) do
		msg:addU16(quest.id)
		msg:addString(quest.name)
		msg:addByte(quest:isCompleted(self))
	end
	msg:sendToPlayer(self)
	msg:delete()
	return true
end
function Player.sendQuestLine(self, quest)
	local msg = NetworkMessage()
	msg:addByte(0xF1)
	msg:addU16(quest.id)
	local missions = quest:getMissions(self)
	msg:addByte(#missions)
	for _, mission in pairs(missions) do
		msg:addU16(mission.id)
		msg:addString(mission:getName(self))
		msg:addString(mission:getDescription(self))
	end
	msg:sendToPlayer(self)
	msg:delete()
	return true
end
function Player.getTrackedQuests(self, missionsId)
	local playerId = self:getId()
	local maxTrackedQuests = self:getMaxTrackedQuests()
	local trackedQuests = {}
	Game.getTrackedQuests()[playerId] = trackedQuests
	local quests = Game.getQuests()
	local missions = Game.getMissions()
	local trackeds = 0
	for _, missionId in pairs(missionsId) do
		local mission = missions[missionId]
		if mission and mission:isStarted(self) then
			trackedQuests[mission] = quests[mission.questId]
			trackeds = trackeds + 1
			if trackeds >= maxTrackedQuests then
				break
			end
		end
	end
	return trackedQuests, trackeds
end
function Player.sendQuestTracker(self, missionsId)
	local msg = NetworkMessage()
	msg:addByte(0xD0)
	msg:addByte(1)
	local trackedQuests, trackeds = self:getTrackedQuests(missionsId)
	msg:addByte(self:getMaxTrackedQuests() - trackeds)
	msg:addByte(trackeds)
	for mission, quest in pairs(trackedQuests or {}) do
		msg:addU16(mission.id)
		msg:addString(quest.name)
		msg:addString(mission:getName(self))
		msg:addString(mission:getDescription(self))
	end
	msg:sendToPlayer(self)
	msg:delete()
	return true
end
function Player.sendUpdateQuestTracker(self, mission)
	local msg = NetworkMessage()
	msg:addByte(0xD0)
	msg:addByte(0)
	msg:addU16(mission.id)
	msg:addString(mission:getName(self))
	msg:addString(mission:getDescription(self))
	msg:sendToPlayer(self)
	msg:delete()
	return true
end