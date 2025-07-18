local levelDoor = MoveEvent()

function levelDoor.onStepIn(creature, item, position, fromPosition)
	if not creature:isPlayer() then
		return false
	end

	if creature:getLevel() < item.actionid - actionIds.levelDoor then
		creature:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Only the worthy may pass.")
		creature:teleportTo(fromPosition, true)
		return false
	end
	return true
end
for _, i in ipairs(openLevelDoors) do
	levelDoor:id(i)
end
levelDoor:type("stepin")
levelDoor:register()