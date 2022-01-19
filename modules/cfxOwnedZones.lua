cfxOwnedZones = {}
cfxOwnedZones.version = "1.1.0"
cfxOwnedZones.verbose = false 
cfxOwnedZones.announcer = true 
--[[-- VERSION HISTORY

1.0.3 - added getNearestFriendlyZone
	  - added getNearestOwnedZone
	  - added hasOwnedZones
	  - added getNearestOwnedZoneToPoint
1.0.4 - changed addOwnedZone code to use cfxZone.getCoalitionFromZoneProperty 
      - changed to use dcsCommon.coalition2county 
      - changed to using correct coalition for spawing attackers and defenders 
1.0.5 - repairing defenders switches to country instead coalition when calling createGroundUnitsInZoneForCoalition -- fixed 
1.0.6 - removed call to conqTemplate
      - verified that pause will also apply to init 
	  - unbeatable zones 
	  - untargetable zones 
	  - hidden attribute 
1.0.7 - optional cfxGroundTroops module, error message when attackers
      - support of 'none' type string to indicate no attackers/defenders 
	  - updated property access 
	  - module check 
	  - cfxOwnedTroop.usesDefenders(aZone)
	  - verifyZone
1.0.8 - repairDefenders trims types to allow blanks in 
        type separator 
1.1.0 - config zone 
	  - bang! support r, b, n capture
	  - defaulting attackDelta to 10 instead of radius 
	  - verbose code for spawning
	  - verbose code for state transition 
	  - attackers have (A) in name, defenders (D)
	  - exit createDefenders if no troops
	  - exit createAttackers if no troops 
	  - usesAttackers/usesDefenders checks for neutral ownership 
	  - verbose state change 
	  - nearestZone supports moving zones 
	  - remove exiting defenders from zone after cap to avoid 
	    shocked state
      - announcer 		
	  
--]]--
cfxOwnedZones.requiredLibs = {
	"dcsCommon", -- common is of course needed for everything
	             -- pretty stupid to check for this since we 
				 -- need common to invoke the check, but anyway
	"cfxZones", -- Zones, of course 
	"cfxCommander", -- to make troops do stuff
--	"cfxGroundTroops", -- optional, used for attackers only
}

cfxOwnedZones.zones = {}
cfxOwnedZones.ups = 1
cfxOwnedZones.initialized = false 
cfxOwnedZones.defendingTime = 100 -- 100 seconds until new defenders are produced
cfxOwnedZones.attackingTime = 300 -- 300 seconds until new attackers are produced 
cfxOwnedZones.shockTime = 200 -- 200 -- 'shocked' period of inactivity
cfxOwnedZones.repairTime = 200 -- 200 -- time until we raplace one lost unit, also repairs all other units to 100%  

-- owned zones is a module that managers 'conquerable' zones and keeps a 
-- record of who owns the zone
-- based on some simple rules that are regularly checked 

-- 
-- *** EXTENTDS ZONES ***, so compatible with cfxZones, pilotSafe (limited airframes), may conflict with FARPZones 
--

-- owned zones are identified by the 'owner' property. It can be initially set to nothing (default), NEUTRAL, RED or BLUE

-- when a zone changes hands, a callback can be installed to be told of that fact
-- callback has the format (zone, newOwner, formerOwner) with zone being the Zone, and new owner and former owners
cfxOwnedZones.conqueredCallbacks = {}

--
-- zone attributes when owned
--  owner: coalition that owns the zone
--  status: FSM for spawning
--  defendersRED/BLUE - coma separated type string for the group to spawm on defense cycle completion
--  attackersRED/BLUE - as above for attack cycle. 
--  timeStamp - time when zone switched into current state 
--  spawnRadius - overrides zone's radius when placing defenders. can be use to place defenders inside or outside zone itself
--  formation - defender's formation
--  attackFormation - attackers formation 
--  attackRadius - radius of circle in which attackers are spawned. informs formation 
--  attackDelta - polar coord: r from zone center where attackers are spawned
--  attackPhi - polar degrees where attackers are to be spawned
--  paused - will not spawn. default is false 
--  unbeatable - can't be conquered by other side. default is false
--  untargetable - will not be targeted by either side. make unbeatable
--  owned zones untargetable, or they'll become a troop magnet for 
--  zoneAttackers 
--  hidden - if set (default no), it no markings on the map
--
-- to create an owned zone that can't be conquered and does nothing
-- add the following properties to a zone 
-- owner = <x>, paused = true, unbeatable = true 

--
-- callback handling
--

function cfxOwnedZones.addCallBack(conqCallback)
	local cb = {}
	cb.callback = conqCallback -- we use this so we can add more data later
	cfxOwnedZones.conqueredCallbacks[conqCallback] = cb
	
end

function cfxOwnedZones.invokeConqueredCallbacks(aZone, newOwner, lastOwner)
	for key, cb in pairs (cfxOwnedZones.conqueredCallbacks) do 
		cb.aZone = aZone -- set these up for if we need them later
		cb.newOwner = newOwner
		cb.lastOwner = lastOwner
		-- invoke callback
		cb.callback(aZone, newOwner, lastOwner)
	end
end

function cfxOwnedZones.side2name(theSide)
	if theSide == 1 then return "REDFORCE" end
	if theSide == 2 then return "BLUEFORCE" end
	return "Neutral"
end

function cfxOwnedZones.conqTemplate(aZone, newOwner, lastOwner) 
	if true then return end -- do not output

	if lastOwner == 0 then 
		trigger.action.outText(cfxOwnedZones.side2name(newOwner) .. " have taken possession zone " .. aZone.name, 30)
		return 
	end
	
	trigger.action.outText("Zone " .. aZone.name .. " was taken by ".. cfxOwnedZones.side2name(newOwner) .. " from " .. cfxOwnedZones.side2name(lastOwner), 30)
end

--
-- M I S C
--

function cfxOwnedZones.drawZoneInMap(aZone)
	-- will save markID in zone's markID
	if aZone.markID then 
		trigger.action.removeMark(aZone.markID)
	end 
	if aZone.hidden then return end 
	
	local lineColor = {1.0, 0, 0, 1.0} -- red 
	local fillColor = {1.0, 0, 0, 0.2} -- red 
	local owner = cfxOwnedZones.getOwnerForZone(aZone)
	if owner == 2 then 
		lineColor = {0.0, 0, 1.0, 1.0}
		fillColor = {0.0, 0, 1.0, 0.2}
	elseif owner == 0 then 
		lineColor = {0.8, 0.8, 0.8, 1.0}
		fillColor = {0.8, 0.8, 0.8, 0.2}
	end
	
	local theShape = 2 -- circle
	local markID = dcsCommon.numberUUID()

	trigger.action.circleToAll(-1, markID, aZone.point, aZone.radius, lineColor, fillColor, 1, true, "")
	aZone.markID = markID 
	
end


function cfxOwnedZones.addOwnedZone(aZone)
	local owner = cfxZones.getCoalitionFromZoneProperty(aZone, "owner", 0) -- is already readm read it again

	aZone.owner = owner -- add this attribute to zone 
	
	-- now init all other owned zone properties
	aZone.state = "init"
	aZone.timeStamp = timer.getTime()
	--aZone.defendersRED = "Soldier M4,Soldier M4,Soldier M4,Soldier M4,Soldier M4" -- vehicles allocated to defend when red

	aZone.defendersRED = cfxZones.getStringFromZoneProperty(aZone, "defendersRED", "none")
	aZone.defendersBLUE = cfxZones.getStringFromZoneProperty(aZone, "defendersBLUE", "none")

	aZone.attackersRED = cfxZones.getStringFromZoneProperty(aZone, "attackersRED", "none")
	aZone.attackersBLUE = cfxZones.getStringFromZoneProperty(aZone, "attackersBLUE", "none")
	
	local formation = cfxZones.getZoneProperty(aZone, "formation")
	if not formation then formation = "circle_out" end 
	aZone.formation = formation
	formation = cfxZones.getZoneProperty(aZone, "attackFormation")
	if not formation then formation = "circle_out" end
	aZone.attackFormation = formation 
	local spawnRadius = cfxZones.getNumberFromZoneProperty(aZone, "spawnRadius", aZone.radius-5) -- "-5" so they remaininside radius 

	aZone.spawnRadius = spawnRadius
	
	local attackRadius = cfxZones.getNumberFromZoneProperty(aZone, "attackRadius", aZone.radius)
	aZone.attackRadius = attackRadius
	local attackDelta = cfxZones.getNumberFromZoneProperty(aZone, "attackDelta", 10) -- aZone.radius)
	aZone.attackDelta = attackDelta
	local attackPhi = cfxZones.getNumberFromZoneProperty(aZone, "attackPhi", 0)
	aZone.attackPhi = attackPhi 
	
	local paused = cfxZones.getBoolFromZoneProperty(aZone, "paused", false)
	aZone.paused = paused 
	
	aZone.unbeatable = cfxZones.getBoolFromZoneProperty(aZone, "unbeatable", false)
	aZone.untargetable = cfxZones.getBoolFromZoneProperty(aZone, "untargetable", false)
	aZone.hidden = cfxZones.getBoolFromZoneProperty(aZone, "hidden", false)
	cfxOwnedZones.zones[aZone] = aZone 
	cfxOwnedZones.drawZoneInMap(aZone)
	cfxOwnedZones.verifyZone(aZone)
end

function cfxOwnedZones.verifyZone(aZone)
	-- do some sanity checks
	if not cfxGroundTroops and (aZone.attackersRED ~= "none" or aZone.attackersBLUE ~= "none") then 
		trigger.action.outText("+++owdZ: " .. aZone.name .. " attackers need cfxGroundTroops to function")
	end
	
end

function cfxOwnedZones.getOwnerForZone(aZone)
	local theZone = cfxOwnedZones.zones[aZone]
	if not theZone then return 0 end -- unknown zone, return neutral as default 
	return theZone.owner
end

function cfxOwnedZones.getEnemyZonesFor(aCoalition) 
	local enemyZones = {}
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(aCoalition)
	for zKey, aZone in pairs(cfxOwnedZones.zones) do 
		if aZone.owner == ourEnemy then -- only check enemy owned zones
			-- note: will include untargetable zones 
			table.insert(enemyZones, aZone)			
		end
	end
	return enemyZones
end

function cfxOwnedZones.getNearestOwnedZoneToPoint(aPoint)
	local shortestDist = math.huge
	local closestZone = nil
	
	for zKey, aZone in pairs(cfxOwnedZones.zones) do 
		local zPoint = cfxZones.getPoint(aZone) 
		currDist = dcsCommon.dist(zPoint, aPoint)
		if aZone.untargetable ~= true and 
		   currDist < shortestDist then 
			shortestDist = currDist
			closestZone = aZone
		end
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestOwnedZone(theZone)
	local shortestDist = math.huge
	local closestZone = nil
	local aPoint = cfxZones.getPoint(theZone)
	for zKey, aZone in pairs(cfxOwnedZones.zones) do
		local zPoint = cfxZones.getPoint(aZone) 
		currDist = dcsCommon.dist(zPoint, aPoint)
		if aZone.untargetable ~= true and currDist < shortestDist then 
			shortestDist = currDist
			closestZone = aZone
		end
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestEnemyOwnedZone(theZone, targetNeutral)
	if not targetNeutral then targetNeutral = false else targetNeutral = true end
	local shortestDist = math.huge
	local closestZone = nil
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(theZone.owner)
	if not ourEnemy then return nil end -- we called for a neutral zone. they have no enemies 
	local zPoint = cfxZones.getPoint(theZone)
	
	for zKey, aZone in pairs(cfxOwnedZones.zones) do 
		if targetNeutral then 
			-- return all zones that do not belong to us
			if aZone.owner ~= theZone.owner then 
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(aPoint, zPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		else 
			-- return zones that are taken by the Enenmy
			if aZone.owner == ourEnemy then -- only check own zones
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		end 
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.getNearestFriendlyZone(theZone, targetNeutral)
	if not targetNeutral then targetNeutral = false else targetNeutral = true end
	local shortestDist = math.huge
	local closestZone = nil
	local ourEnemy = dcsCommon.getEnemyCoalitionFor(theZone.owner)
	if not ourEnemy then return nil end -- we called for a neutral zone. they have no enemies nor friends, all zones would be legal.
	local zPoint = cfxZones.getPoint(theZone)
	for zKey, aZone in pairs(cfxOwnedZones.zones) do 
		if targetNeutral then 
			-- target all zones that do not belong to the enemy
			if aZone.owner ~= ourEnemy then
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		else 
			-- only target zones that are taken by us
			if aZone.owner == theZone.owner then -- only check own zones
				local aPoint = cfxZones.getPoint(aZone)
				currDist = dcsCommon.dist(zPoint, aPoint)
				if aZone.untargetable ~= true and currDist < shortestDist then 
					shortestDist = currDist
					closestZone = aZone
				end
			end
		end 
	end
	
	return closestZone, shortestDist
end

function cfxOwnedZones.enemiesRemaining(aZone)
	if cfxOwnedZones.getNearestEnemyOwnedZone(aZone) then return true end
	return false
end

function cfxOwnedZones.spawnAttackTroops(theTypes, aZone, aCoalition, aFormation)
	local unitTypes = {} -- build type names
	-- split theTypes into an array of types
	unitTypes = dcsCommon.splitString(theTypes, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
		-- simply exit, no troops specified 
		if cfxOwnedZones.verbose then 
			trigger.action.outText("+++owdZ: no attackers for " .. aZone.name .. ". exiting", 30)
		end
		return
	end
	
	if cfxOwnedZones.verbose then 
			trigger.action.outText("+++owdZ: spawning attackers for " .. aZone.name, 30)
	end
		
	--local theCountry = dcsCommon.coalition2county(aCoalition) 
	
	local spawnPoint = {x = aZone.point.x, y = aZone.point.y, z = aZone.point.z} -- copy struct 
	
	local rads = aZone.attackPhi * 0.01745
	spawnPoint.x = spawnPoint.x + math.cos(aZone.attackPhi) * aZone.attackDelta
	spawnPoint.y = spawnPoint.y + math.sin(aZone.attackPhi) * aZone.attackDelta 
	
	local spawnZone = cfxZones.createSimpleZone("attkSpawnZone", spawnPoint, aZone.attackRadius)
	
	local theGroup = cfxZones.createGroundUnitsInZoneForCoalition (
				aCoalition, -- theCountry,							
				aZone.name .. " (A) " .. dcsCommon.numberUUID(), -- must be unique 
				spawnZone, 											
				unitTypes, 													
				aFormation, -- outward facing
				0)
	return theGroup
end

function cfxOwnedZones.spawnDefensiveTroops(theTypes, aZone, aCoalition, aFormation)
	local unitTypes = {} -- build type names
	-- split theTypes into an array of types
	unitTypes = dcsCommon.splitString(theTypes, ",")
	if #unitTypes < 1 then 
		table.insert(unitTypes, "Soldier M4") -- make it one m4 trooper as fallback
		-- simply exit, no troops specified 
		if cfxOwnedZones.verbose then 
			trigger.action.outText("+++owdZ: no defenders for " .. aZone.name .. ". exiting", 30)
		end
		return
	end
	
	--local theCountry = dcsCommon.coalition2county(aCoalition) 
	local spawnZone = cfxZones.createSimpleZone("spawnZone", aZone.point, aZone.spawnRadius)
	local theGroup = cfxZones.createGroundUnitsInZoneForCoalition (
				aCoalition, --theCountry,				
				aZone.name .. " (D) " .. dcsCommon.numberUUID(), -- must be unique 
				spawnZone, 										unitTypes,
				aFormation, -- outward facing
				0)
	return theGroup
end
--
-- U P D A T E 
--

function cfxOwnedZones.sendOutAttackers(aZone)
	-- only spawn if there are zones to attack
	if not cfxOwnedZones.enemiesRemaining(aZone) then 
		if cfxOwnedZones.verbose then 
			trigger.action.outText("+++owdZ - no enemies, resting ".. aZone.name, 30)
		end
		return 
	end

	if cfxOwnedZones.verbose then 
		trigger.action.outText("+++owdZ - attack cycle for ".. aZone.name, 30)
	end
	-- load the attacker typestring

	-- step one: get the attackers 
	local attackers = aZone.attackersRED;
	if (aZone.owner == 2) then attackers = aZone.attackersBLUE end

	if attackers == "none" then return end 

	local theGroup = cfxOwnedZones.spawnAttackTroops(attackers, aZone, aZone.owner, aZone.attackFormation)
	
	-- submit them to ground troops handler as zoneseekers 
	-- and our groundTroops module will handle the rest 
	if cfxGroundTroops then 
		local troops = cfxGroundTroops.createGroundTroops(theGroup)
		troops.orders = "attackOwnedZone"
		troops.side = aZone.owner
		cfxGroundTroops.addGroundTroopsToPool(troops) -- hand off to ground troops
	else 
		if cfxOwnedZones.verbose then 
			trigger.action.outText("+++ Owned Zones: no ground troops module on send out attackers", 30)
		end 
	end
end

-- bang support 

function cfxOwnedZones.bangNeutral(value)
	if not cfxOwnedZones.neutralTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.neutralTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.neutralTriggerFlag, newVal)
end

function cfxOwnedZones.bangRed(value)
	if not cfxOwnedZones.redTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.redTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.redTriggerFlag, newVal)
end

function cfxOwnedZones.bangBlue(value)
	if not cfxOwnedZones.blueTriggerFlag then return end 
	local newVal = trigger.misc.getUserFlag(cfxOwnedZones.blueTriggerFlag) + value 
	trigger.action.setUserFlag(cfxOwnedZones.blueTriggerFlag, newVal)
end

function cfxOwnedZones.bangSide(theSide, value)
	if theSide == 2 then 
		cfxOwnedZones.bangBlue(value)
		return 
	end 
	if theSide == 1 then 
		cfxOwnedZones.bangRed(value)
		return 
	end 
	cfxOwnedZones.bangNeutral(value)
end

function cfxOwnedZones.zoneConquered(aZone, theSide, formerOwner) -- 0 = neutral 1 = RED 2 = BLUE 
	local who = "REDFORCE"
	if theSide == 2 then who = "BLUEFORCE" end
	if cfxOwnedZones.announcer then 
		trigger.action.outText(who .. " have secured zone " .. aZone.name, 30)
		aZone.owner = theSide
		-- play different sounds depending on who's won
		if theSide == 1 then 
			trigger.action.outSoundForCoalition(1, "Quest Snare 3.wav")
			trigger.action.outSoundForCoalition(2, "Death BRASS.wav")
		else 
			trigger.action.outSoundForCoalition(2, "Quest Snare 3.wav")
			trigger.action.outSoundForCoalition(1, "Death BRASS.wav")
		end
	end 
	-- invoke callbacks now
	cfxOwnedZones.invokeConqueredCallbacks(aZone, theSide, formerOwner)
	
	-- bang! flag support 
	cfxOwnedZones.bangSide(theSide, 1) -- winner 
	cfxOwnedZones.bangSide(formerOwner, -1) -- loser 
	
	-- update map
	cfxOwnedZones.drawZoneInMap(aZone) -- update status in map. will erase previous version 
	-- remove all defenders to avoid shock state 
	aZone.defenders = nil

	-- change to captured 
	
	aZone.state = "captured"
	aZone.timeStamp = timer.getTime()
end

function cfxOwnedZones.repairDefenders(aZone)
	--trigger.action.outText("+++ enter repair for ".. aZone.name, 30)
	-- find a unit that is missing from my typestring and replace it 
	-- one by one until we are back to full strength
	-- step one: get the defenders and create a type array 
	local defenders = aZone.defendersRED;
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	local unitTypes = {} -- build type names
	
	-- if none, we are done
	if defenders == "none" then return end 

	-- split theTypes into an array of types	
	allTypes = dcsCommon.trimArray(
			dcsCommon.splitString(defenders, ",")
		)
	local livingTypes = {} -- init to emtpy, so we can add to it if none are alive
	if (aZone.defenders) then 
		-- some remain. add one of the killed
		livingTypes = dcsCommon.getGroupTypes(aZone.defenders)
		-- we now iterate over the living types, and remove their 
		-- counterparts from the allTypes. We then take the first that 
		-- is left
		
		if #livingTypes > 0 then 
			for key, aType in pairs (livingTypes) do 
				if not dcsCommon.findAndRemoveFromTable(allTypes, aType) then 
					trigger.action.outText("+++OwdZ WARNING: found unmatched type <" .. aType .. "> while trying to repair defenders for ".. aZone.name, 30)
				else 
					-- all good
				end 
			end
		end 
	end
	
	-- when we get here, allTypes is reduced to those that have been killed 
	if #allTypes < 1 then 
		trigger.action.outText("+++owdZ: WARNING: all types exist when repairing defenders for ".. aZone.name, 30)
	else 
		table.insert(livingTypes, allTypes[1]) -- we simply use the first that we find
	end
	-- remove the old defenders
	if aZone.defenders then 
		aZone.defenders:destroy()
	end
	
	-- now livingTypes holds the full array of units we need to spawn 
	local theCountry = dcsCommon.getACountryForCoalition(aZone.owner) 
	local spawnZone = cfxZones.createSimpleZone("spawnZone", aZone.point, aZone.spawnRadius)
	local theGroup = cfxZones.createGroundUnitsInZoneForCoalition (
				aZone.owner, -- was wrongly: theCountry		
				aZone.name .. dcsCommon.numberUUID(), -- must be unique 
				spawnZone, 											
				livingTypes, 
				
				aZone.formation, -- outward facing
				0)
	aZone.defenders = theGroup
	aZone.lastDefenders = theGroup:getSize()
end

function cfxOwnedZones.inShock(aZone)
	-- a unit was destroyed, everyone else is in shock, no rerpairs 
	-- group can re-shock when another unit is destroyed 
end

function cfxOwnedZones.spawnDefenders(aZone)
	local defenders = aZone.defendersRED;
	
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	-- before we spawn new defenders, remove the old ones
	if aZone.defenders then 
		if aZone.defenders:isExist() then 
			aZone.defenders:destroy()
		end
		aZone.defenders = nil
	end
	
	-- if 'none', simply exit
	if defenders == "none" then return end
	
	local theGroup = cfxOwnedZones.spawnDefensiveTroops(defenders, aZone, aZone.owner, aZone.formation)
	-- the troops reamin, so no orders to move, no handing off to ground troop manager
	aZone.defenders = theGroup;
	if theGroup then 
		aZone.defenderMax = theGroup:getInitialSize() -- so we can determine if some units were destroyed
		aZone.lastDefenders = aZone.defenderMax -- if this is larger than current number, someone bit the dust  
		--trigger.action.outText("+++ spawned defenders for ".. aZone.name, 30)
	else 
		trigger.action.outText("+++owdZ: WARNING: spawned no defenders for ".. aZone.name, 30)
	end 
end

--
-- per-zone update, run down the FSM to determine what to do.
-- FSM uses timeStamp since when state was set. Possible states are 
--	- init -- has just been inited for the first time. will usually immediately produce defenders, 
--    and then transition to defending 
--  - catured -- has just been captured. transition to defending 
--  - defending -- wait until timer has reached goal, then produce defending units and transition to attacking. 
--  - attacking -- wait until timer has reached goal, and then produce attacking units and send them to closest enemy zone.
--                 state is interrupted as soon as a defensive unit is lost. state then goes to defending with timer starting
--  - idle - do nothing, zone's actions are turned off 
--  - shocked -- a unit was destroyed. group is in shock for a time until it starts repairing. If another unit is 
--               destroyed during the shocked period, the timer resets to zero and repairs are delayed
--  - repairing -- as long as we aren't at full strength, units get replaced one by one until at full strength
--                 each time the timer counts down, another missing unit is replaced, and all other unit's health 
--                 is reset to 100%
--  
--  a Zone with the paused attribute set to true will cause it to not do anything 
--
-- check if defenders are specified
function cfxOwnedZones.usesDefenders(aZone) 
	if aZone.owner == 0 then return false end 
	local defenders = aZone.defendersRED;	
	if (aZone.owner == 2) then defenders = aZone.defendersBLUE end
	
	return defenders ~= "none"
end

function cfxOwnedZones.usesAttackers(aZone) 
	if aZone.owner == 0 then return false end 
	local attackers = aZone.attackersRED;	
	if (aZone.owner == 2) then defenders = aZone.attackersBLUE end
	
	return attackers ~= "none"
end

function cfxOwnedZones.updateZone(aZone)
	-- a zone can be paused, causing it to not progress anything
	-- even if zone status is still init, will NOT produce anything
	-- if paused is on.
	if aZone.paused then return end 

	nextState = aZone.state;
	
	-- first, check if my defenders have been attacked and one of them has been killed
	-- if so, we immediately switch to 'shocked' 
	if cfxOwnedZones.usesDefenders(aZone) and 
	   aZone.defenders then 
		-- we have defenders
		if aZone.defenders:isExist() then
			-- isee if group was damaged 
			if aZone.defenders:getSize() < aZone.lastDefenders then 
				-- yes, at least one unit destroyed
				aZone.timeStamp = timer.getTime()
				aZone.lastDefenders = aZone.defenders:getSize()
				if aZone.lastDefenders == 0 then 
					aZone.defenders = nil
				end
				aZone.state = "shocked"

				return 
			end
			
		else 
			-- group was destroyed. erase link, and go into shock for the last time 
			aZone.state = "shocked"
			aZone.timeStamp = timer.getTime()
			aZone.lastDefenders = 0
			aZone.defenders = nil

			return 
		end
	end
	
	
	if aZone.state == "init" then 
		-- during init we instantly create the defenders since 
		-- we assume the zone existed already 
		if aZone.owner > 0 then 
			cfxOwnedZones.spawnDefenders(aZone)
			-- now drop into attacking mode to produce attackers
			nextState = "attacking"
		else 
			nextState = "idle"
		end
		
		aZone.timeStamp = timer.getTime()
	
	elseif aZone.state == "idle" then
		-- nothing to do, zone is effectively switched off.
		-- used for neutal zones or when forced to turn off
		-- in some special cases 
		
	elseif aZone.state == "captured" then 
		-- start the clock on defenders
		nextState = "defending"
		aZone.timeStamp = timer.getTime()
		if cfxOwnedZones.verbose then 
			trigger.action.outText("+++owdZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
		end 
	elseif aZone.state == "defending" then 
		if timer.getTime() > aZone.timeStamp + cfxOwnedZones.defendingTime then 
			cfxOwnedZones.spawnDefenders(aZone)
			-- now drop into attacking mode to produce attackers
			nextState = "attacking"
			aZone.timeStamp = timer.getTime()
			if cfxOwnedZones.verbose then 
				trigger.action.outText("+++owdZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
			end
		end

	elseif aZone.state == "repairing" then 
		-- we are currently rebuilding defenders unit by unit 
		if timer.getTime() > aZone.timeStamp + cfxOwnedZones.repairTime then 
			aZone.timeStamp = timer.getTime()
			cfxOwnedZones.repairDefenders(aZone)
			if aZone.defenders:getSize() >= aZone.defenderMax then
--				
				-- we are at max size, time to produce some attackers
				nextState = "attacking"
				aZone.timeStamp = timer.getTime()
				if cfxOwnedZones.verbose then 
					trigger.action.outText("+++owdZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
				end
			end
			-- see if we are full strenght and if so go to attack, else set timer to reair the next unit
		end
		
	elseif aZone.state == "shocked" then 
		-- we are currently rebuilding defenders unit by unit 
		if timer.getTime() > aZone.timeStamp + cfxOwnedZones.shockTime then 
			nextState = "repairing"
			aZone.timeStamp = timer.getTime()
			if cfxOwnedZones.verbose then 
				trigger.action.outText("+++owdZ: State " .. aZone.state .. " to " .. nextState .. " for " .. aZone.name, 30)
			end
		end
		
	elseif aZone.state == "attacking" then 
		if timer.getTime() > aZone.timeStamp + cfxOwnedZones.attackingTime then 
			cfxOwnedZones.sendOutAttackers(aZone)
			-- reset timer
			aZone.timeStamp = timer.getTime()
			if cfxOwnedZones.verbose then 
				trigger.action.outText("+++owdZ: State " .. aZone.state .. " reset for " .. aZone.name, 30)
			end
		end
	else 
		-- unknown zone state 
	end
	aZone.state = nextState
end

function cfxOwnedZones.update()
	cfxOwnedZones.updateSchedule = timer.scheduleFunction(cfxOwnedZones.update, {}, timer.getTime() + 1/cfxOwnedZones.ups)
	
	-- iterate all zones, and determine their current ownership status 
	for key, aZone in pairs(cfxOwnedZones.zones) do 
		-- a hand change can only happen if there are only ground troops from the OTHER side in 
		-- the zone 
		local categ = Group.Category.GROUND
		local theBlues = cfxZones.groupsOfCoalitionPartiallyInZone(2, aZone, categ)
		local theReds = cfxZones.groupsOfCoalitionPartiallyInZone(1, aZone, categ)
		local currentOwner = aZone.owner
		if #theBlues > 0 and #theReds == 0 and aZone.unbeatable ~= true then 
			-- this now belongs to blue
			if currentOwner ~= 2 then 
				cfxOwnedZones.zoneConquered(aZone, 2, currentOwner)
			end
		elseif #theBlues == 0 and #theReds > 0 and aZone.unbeatable ~= true then 
			-- this now belongs to red 
			if currentOwner ~= 1 then 
				cfxOwnedZones.zoneConquered(aZone, 1, currentOwner)
			end
		end 
		
		-- now, perhaps with their new owner call updateZone()
		cfxOwnedZones.updateZone(aZone)
	end
	
end

function cfxOwnedZones.sideOwnsAll(theSide) 
	for key, aZone in pairs(cfxOwnedZones.zones) do 
		if aZone.owner ~= theSide then 
			return false
		end
	end
	-- if we get here, all your base are belong to us 
	return true
end

function cfxOwnedZones.hasOwnedZones() 
	for idx, zone in pairs (cfxOwnedZones.zones) do
		return true -- even the first returns true
	end
	-- no owned zones
	return false 
end

function cfxOwnedZones.readConfigZone(theZone)
	cfxOwnedZones.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false)
	cfxOwnedZones.announcer = cfxZones.getBoolFromZoneProperty(theZone, "announcer", true)
	
	if cfxZones.hasProperty(theZone, "r!") then 
		cfxOwnedZones.redTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "r!", "<none>")
	end
	if cfxZones.hasProperty(theZone, "b!") then 
		cfxOwnedZones.blueTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "b!", "<none>")
	end
	if cfxZones.hasProperty(theZone, "n!") then 
		cfxOwnedZones.neutralTriggerFlag = cfxZones.getStringFromZoneProperty(theZone, "n!", "<none>")
	end
	cfxOwnedZones.defendingTime = cfxZones.getNumberFromZoneProperty(theZone, "defendingTime", 100)
	cfxOwnedZones.attackingTime = cfxZones.getNumberFromZoneProperty(theZone, "attackingTime", 300)
	cfxOwnedZones.shockTime = cfxZones.getNumberFromZoneProperty(theZone, "shockTime", 200)
	cfxOwnedZones.repairTime = cfxZones.getNumberFromZoneProperty(theZone, "repairTime", 200)
end

function cfxOwnedZones.init()
	-- check libs
	if not dcsCommon.libCheck("cfx Owned Zones", 
		cfxOwnedZones.requiredLibs) then
		return false 
	end

	-- read my config zone
	local theZone = cfxZones.getZoneByName("ownedZonesConfig") 
	if not theZone then 
		trigger.action.outText("+++ownZ: no config", 30)
	else
		cfxOwnedZones.readConfigZone(theZone)
	end
	
	-- collect all owned zones by their 'owner' property 
	-- start the process
	local pZones = cfxZones.zonesWithProperty("owner")
	
	-- now add all zones to my zones table, and convert the owner property into 
	-- a proper attribute 
	for k, aZone in pairs(pZones) do
		cfxOwnedZones.addOwnedZone(aZone)
	end
	
	initialized = true 
	cfxOwnedZones.updateSchedule = timer.scheduleFunction(cfxOwnedZones.update, {}, timer.getTime() + 1/cfxOwnedZones.ups)
	
	trigger.action.outText("cx/x owned zones v".. cfxOwnedZones.version .. " started", 30)
	
	return true 
end

if not cfxOwnedZones.init() then 
	trigger.action.outText("cf/x Owned Zones aborted: missing libraries", 30)
	cfxOwnedZones = nil 
end



