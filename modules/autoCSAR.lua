autoCSAR = {}
autoCSAR.version = "1.1.0" 
autoCSAR.requiredLibs = {
	"dcsCommon", -- always
	"cfxZones", -- Zones, of course 
}
autoCSAR.killDelay = 2 * 60 
autoCSAR.counter = 31 -- any number is good, to kick-off counting
autoCSAR.trackedEjects = {} -- we start tracking on eject 

--[[--
	VERSION HISTORY
	1.0.0 - Initial Version
	1.1.0 - allow open water CSAR, fake pilot with GRG Soldier 
		  - can be disabled by seaCSAR = false 
--]]--

function autoCSAR.removeGuy(args)
	local theGuy = args.theGuy
	if theGuy and theGuy:isExist() then  
		Unit.destroy(theGuy)
	end
end 

function autoCSAR.isOverWater(theUnit)
	local pPoint = theUnit:getPoint()
	pPoint.y = pPoint.z -- make it getSurfaceType compatible 
	local surf = land.getSurfaceType(pPoint)
	return surf == 2 or surf == 3
end

function autoCSAR.createNewCSAR(theUnit)
	if not csarManager then 
		trigger.action.outText("+++aCSAR: CSAR Manager not loaded, aborting", 30)
		-- return
	end	
	-- enter with unit from landing_after_eject event
	-- unit has no group 
	local coa = theUnit:getCoalition()
	if coa == 0 then -- neutral
		trigger.action.outText("Neutral Pilot made it safely to ground.", 30)
		return 
	end
	if coa == 1 and not autoCSAR.redCSAR then 
		return -- we don't do red
	end
	if coa == 2 and not autoCSAR.blueCSAR then 
		return -- no blue rescue
	end
	
	-- for later expansion
	local theGroup = theUnit:getGroup()
	if theGroup then 
		-- now happens for faked sea CSAR units
		--trigger.action.outText("We have a group for <" .. theUnit:getName() .. ">", 30)
	end
	
	-- now, if theUnit is over open water, this will be killed instantly
	-- and must therefore be replaced with a stand-in 
	local pPoint = theUnit:getPoint()
	pPoint.y = pPoint.z -- make it getSurfaceType compatible 
	local surf = land.getSurfaceType(pPoint)
	local splashdown = false 
	
	if surf == 2 or surf == 3 then 
		trigger.action.outTextForCoalition(coa, "Parachute splashdown over open water reported!", 30)
		splashdown = true 
		-- create a replacement unit since pilot will be killed 
		local theBoyGroup = dcsCommon.createSingleUnitGroup(
			"Xray-" .. autoCSAR.counter, 
			"Soldier M4 GRG", -- "Soldier M4 GRG",
			pPoint.x, 
			pPoint.z, 
			0)
		local theSideCJTF = dcsCommon.coalition2county(coa) -- get the correct county CJTF 
		local theGroup = coalition.addGroup(theSideCJTF, Group.Category.GROUND, theBoyGroup)
		-- now access replacement unit 
		local allUnits = theGroup:getUnits()
		theUnit = allUnits[1] -- get first (and only) unit
	end
	-- create a CSAR mission now
	csarManager.createCSARForParachutist(theUnit, "Xray-" .. autoCSAR.counter)
	autoCSAR.counter = autoCSAR.counter + 1
	
	-- schedule removal of pilot
	local args = {}
	args.theGuy = theUnit 
	if splashdown then
		timer.scheduleFunction(autoCSAR.removeGuy, args, timer.getTime() + 1) -- in one second
	else
		timer.scheduleFunction(autoCSAR.removeGuy, args, timer.getTime() + autoCSAR.killDelay)
	end 
end

function autoCSAR:onEvent(event)
--	trigger.action.outText("autoCSAR: event = " .. event.id, 30)
	if event.id == 31 then -- landing_after_eject, does not happen at sea
		-- to prevent double invocations for same process
		-- check that we are still tracking this ejection 
		if event.initiator then 
			local uid = tonumber(event.initiator:getID())
			if autoCSAR.trackedEjects[uid] then
				trigger.action.outText("aCSAR: filtered double sea csar (player) event for uid = <" .. uid .. ">", 30)
				autoCSAR.trackedEjects[uid] = nil -- reset 
				return 
			end
				autoCSAR.createNewCSAR(event.initiator)
--				autoCSAR.trackedEjects[event.initiator] = nil
--				trigger.action.outText("autocsar: LAE for " .. autoCSAR.trackedEjects[event.initiator], 30)				
--			else 
--				trigger.action.outText("autoCSAR: ignored LAE event", 30)
--			end
		end
	end

	if event.id == 6 and autoCSAR.seaCSAR then -- eject, start tracking 
		if event.initiator then
			-- see if this happened over open water and immediately 
		    -- create a seaCSAR 
			
			--local uid = tonumber(event.initiator:getID())
--			trigger.action.outText("autoCSAR: started tracking - chair + pilot", 30)
--			autoCSAR.trackedEjects[event.initiator] = "chair+pilot" -- start with this 
			if autoCSAR.isOverWater(event.initiator) then 
				--trigger.action.outText("attempting to walk on water", 30)
				autoCSAR.createNewCSAR(event.initiator)
			end
			
			-- also mark this one as completed 
			local uid = tonumber(event.initiator:getID())
			autoCSAR.trackedEjects[uid] = "processed"
		end
	end

--[[--	
	if event.id == 33 then -- separate chair from pilot 
		if event.initiator then 
			--local uid = tonumber(event.initiator:getID())
			--local pid = tonumber(event.target:getID()) 
			--if uid == 0 then 
				--trigger.action.outText("uid = 0, abort tracking", 30)
				--return
			--end
			trigger.action.outText("autoCSAR: track change from seat to pilot <" .. event.target:getName() .. ">", 30)
			autoCSAR.trackedEjects[event.initiator] = "chair only"
			autoCSAR.trackedEjects[event.target] = "pilot"
		end
	end
	
	if event.id == 9 then -- pilot dead 
		if event.initiator then 
			--local uid = tonumber(event.initiator:getID())
			trigger.action.outText("autoCSAR: pilot id=xxx dead", 30)
			if autoCSAR.trackedEjects[event.initiator] then 
				trigger.action.outText("confirm tracked pilot dead after ejection", 30)
				if autoCSAR.isOverWater(event.initiator) then 
					trigger.action.outText("attempt to walk on water", 30)
					autoCSAR.createNewCSAR(event.initiator)
				end
				autoCSAR.trackedEjects[event.initiator] = nil
			end
		else 
			trigger.action.outText("autoCSAR - no initiator for zed", 30)
		end
	end
--]]--

end

function autoCSAR.readConfigZone()
	local theZone = cfxZones.getZoneByName("autoCSARConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("autoCSARConfig")
		if autoCSAR.verbose then 
			trigger.action.outText("+++aCSAR: NO config zone!", 30)
		end 
	end 

	autoCSAR.redCSAR = cfxZones.getBoolFromZoneProperty(theZone, "red", true)
	if cfxZones.hasProperty(theZone, "redCSAR") then 
		autoCSAR.redCSAR = cfxZones.getBoolFromZoneProperty(theZone, "redCSAR", true)
	end
	
	autoCSAR.blueCSAR = cfxZones.getBoolFromZoneProperty(theZone, "blue", true)
	if cfxZones.hasProperty(theZone, "blueCSAR") then 
		autoCSAR.blueCSAR = cfxZones.getBoolFromZoneProperty(theZone, "blueCSAR", true)
	end

	autoCSAR.seaCSAR = cfxZones.getBoolFromZoneProperty(theZone, "seaCSAR", true)

	if autoCSAR.verbose then 
		trigger.action.outText("+++aCSAR: read config", 30)
	end 
end

function autoCSAR.start()
	-- lib check
	if not dcsCommon.libCheck then 
		trigger.action.outText("cfx autoCSAR requires dcsCommon", 30)
		return false 
	end 
	if not dcsCommon.libCheck("cfx autoCSAR", autoCSAR.requiredLibs) then
		return false 
	end
	
	-- read config 
	autoCSAR.readConfigZone()
	
	-- connect event handler
	world.addEventHandler(autoCSAR)
	
	trigger.action.outText("cfx autoCSAR v" .. autoCSAR.version .. " started.", 30)
	return true 
end

-- let's go!
if not autoCSAR.start() then 
	trigger.action.outText("cfx autoCSAR aborted: missing libraries", 30)
	autoCSAR = nil 
end
