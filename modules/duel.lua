duel = {}
duel.version = "1.0.0"
duel.verbose = false 
duel.requiredLibs = {
	"dcsCommon",
	"cfxZones",
	"cfxMX",
}
--[[--
	Version History 
	1.0.0 - Initial Version
		  
--]]--

--[[--
	ATTENTION!
	- REQUIRES that SSB is running on the host
	- REQUIRTES that SSB is confgured that '0' (zero) means slot is enabled (this is SSB default)
	- This script must run at MISSION START and will enable SSB 
	
--]]--

duel.duelZones = {}
duel.activeDuelists = {}
duel.allDuelists = {}
-- 
-- reading attributes
--
function duel.createDuelZone(theZone)
	theZone.duelists = {} -- all player units in this zone 
	-- iterate all players and find any unit that is placed in this zone
	for unitName, unitData in pairs(cfxMX.playerUnitByName) do 
		local p = {}
		p.x = unitData.x 
		p.z = unitData.y -- !!
		p.y = 0 
		
		if theZone:pointInZone(p) then 
			-- this is a player aircraft in this zone 
			local duelist = {}
			duelist.data = unitData
			duelist.name = unitName
			duelist.type = unitData.type
			local groupData = cfxMX.playerUnit2Group[unitName]
			duelist.groupName = groupData.name 
			duelist.coa = cfxMX.groupCoalitionByName[duelist.groupName] 
			if duel.verbose then 
				trigger.action.outText("Detected player unit <" .. duelist.name .. ">, type <" .. duelist.type .. "> of group <" .. duelist.groupName .. "> of coa <" .. duelist.coa .. "> in zone <" .. theZone.name .. "> as duelist", 30)
			end 
			
			duelist.active = false 
			duelist.arena = theZone.name
			duelist.zone = theZone 
			
			-- enter into global table 
			-- player can only be in at maximum one duelist zones
			if duel.allDuelists[unitName] then 
				trigger.action.outText("+++WARNING: overlapping duelists! Overwriting previous data", 30)
			end
			duel.allDuelists[unitName] = duelist
			theZone.duelists[unitName] = duelist
		end
	end
	
	theZone.state = "waiting" -- FSM, init to waiting state
	
end

--
-- Event processing 
--
function duel.closeSlotsForZoneAndCoaExceptGroupNamed(theZone, coa, groupName)
	-- iterate this zone's duelist groups and tell SSB to close them now
	local allDuelists = theZone.duelists 
	for unitName, theDuelist in pairs(allDuelists) do 
		local dgName = theDuelist.groupName 
		if (theDuelist.coa == coa) and (dgName ~= groupName) then 
			if duel.verbose then 
				trigger.action.outText("+++duel: closing SSB slot for group <" .. dgName .. ">, coa <" .. theDuelist.coa .. ">", 30)
				trigger.action.setUserFlag(dgName,100) -- anything but 0 means closed 
			end
		end
	end
end


function duel.openSlotsForZoneAndCoa(theZone, coa)
	local allDuelists = theZone.duelists
	for unitName, theDuelist in pairs(allDuelists) do 
		if (theDuelist.coa == coa) then 
			if duel.verbose then 
				trigger.action.outText("+++duel: opening SSB slot for group <" .. theDuelist.groupName .. ">, coa <" .. theDuelist.coa .. ">", 30)
				trigger.action.setUserFlag(theDuelist.groupName, 0) -- 0 means OPEN 
			end
		end
	end	
end

function duel.checkReopenSlotsForZoneAndCoa(theZone, coa)
	-- test if one side can reopen all slots to enter the duel 
	-- if so, will reset FSM for zone 
	local allDuelists = theZone.duelists
	local allUnengaged = true 
	for unitName, theDuelist in pairs(allDuelists) do 
		if (theDuelist.coa == coa) then 
			local theUnit = Unit.getByName(unitName)
			if theUnit and Unit.isExist(theUnit) then 
				-- unit is still alive on this side, can't reopen 
				allUnengaged = false 
			end
		end
	end
	
	if allUnengaged then 
		duel.openSlotsForZoneAndCoa(theZone, coa)
		theZone.state = "waiting"
	end
end

function duel.duelistEnteredArena(theUnit, theDuelist)
	-- we connect the player with duelist slot 
	theDuelist.playerName = theUnit:getPlayerName()
	theDuelist.active = true 
	
	local player = theUnit:getPlayerName()
	local unitName = theUnit:getName()
	local groupName = theDuelist.groupName
	local theZone = theDuelist.zone --duel.duelZones[theDuelist.arena]
	local coa = theDuelist.coa 
	
	if duel.verbose then 
		trigger.action.outText("Player <" .. player .. "> entered arena <" .. theZone:getName() .. "> in unit <" .. unitName .. "> of group <" .. groupName .. "> type <" .. theDuelist.type .. ">, belongs to coalition <" .. coa .. ">", 30)
	end
	
	-- close all slots for this zone and coalition 
	duel.closeSlotsForZoneAndCoaExceptGroupNamed(theZone, coa, groupName)
	
end 

function duel:onEvent(event)
	if not event then return end 
	if duel.verbose then 
		--trigger.action.outText("Event: " .. event.id .. " (" .. dcsCommon.event2text(event.id)  .. ")", 30)
	end
	local theUnit = event.initiator
	if not theUnit then return end 
	
	if event.id == 15 then -- birth 
		local unitName = theUnit:getName()
		-- see if this is a duelist that has spawned
		if not duel.allDuelists[unitName] then 
			return -- not a duelist, not my problem
		end
		
		-- unit that entered is player controlled, and duelist
		duel.duelistEnteredArena(theUnit, duel.allDuelists[unitName])
	end
end

--
-- update 
--

function duel.update()
	-- call me in a second to poll triggers
	timer.scheduleFunction(duel.update, {}, timer.getTime() + 1/duel.ups)
	
	-- find units that have disappeared, and react accordingly
	for unitName, theDuelist in pairs (duel.allDuelists) do 
		local theZone = theDuelist.zone 
		if theDuelist.active then 
--			trigger.action.outText("+++duel: unit <" .. unitName .. "> is active in zone <" .. theZone:getName() .. ">, controlled by <" .. theDuelist.playerName .. ">", 30)

			local theUnit = Unit.getByName(unitName)
			if theUnit and Unit.isExist(theUnit) then 
				-- all is well
			else 
				if duel.verbose then 
					trigger.action.outText("+++duel: unit <" .. unitName .. "> controlled by <" .. theDuelist.playerName .. "> has disappeared, starting cleanup", 30)
				end 

				theDuelist.playerName = nil 
				theDuelist.active = false 
				duel.checkReopenSlotsForZoneAndCoa(theZone, theDuelist.coa)
			end
		end 
	end 
	
	-- now handle FSM for each zone separately 
	for zoneName, theZone in pairs(duel.duelZones) do 
	
	end
end


--
-- Config & start 
--
function duel.readConfigZone()
	local theZone = cfxZones.getZoneByName("duelConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("duelConfig")
	end 
	
	duel.verbose = theZone.verbose
	duel.ups = theZone:getNumberFromZoneProperty("ups", 1)
	
	duel.inside = theZone:getBoolFromZoneProperty("inside", true)
	duel.gracePeriod = theZone:getNumberFromZoneProperty("gracePeriod", 30)
	duel.keepScore = theZone:getBoolFromZoneProperty("score", true)
	
	if duel.verbose then 
		trigger.action.outText("+++duel: read config", 30)
	end 
end

function duel.start()
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx duel requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx Duel", duel.requiredLibs) then
		return false 
	end
	
	-- turn on SSB
	trigger.action.setUserFlag("SSB",100)
	
	-- read config 
	duel.readConfigZone()
	
	-- process cloner Zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("duel")
	for k, aZone in pairs(attrZones) do 
		duel.createDuelZone(aZone) -- process attributes
		duel.duelZones[aZone.name] = aZone -- add to list
	end
	
	-- connect event handler 
	world.addEventHandler(duel)
	
	-- start update 
	duel.update()
	
	trigger.action.outText("cfx Duel v" .. duel.version .. " started.", 30)
	return true 

end

if not duel.start() then 
	trigger.action.outText("cfx Duel aborted: missing libraries", 30)
	duel = nil
end
