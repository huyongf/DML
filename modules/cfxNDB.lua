cfxNDB = {}
cfxNDB.version = "1.0.0"
cfxNDB.verbose = false 
cfxNDB.ups = 10 -- every 10 seconds 
cfxNDB.requiredLibs = {
	"dcsCommon", 
	"cfxZones",  
}
cfxNDB.refresh = 10 -- for moving ndb: interval in secs between refresh  
cfxNDB.power = 100 

cfxNDB.ndbs = {} -- all ndbs 

--
-- NDB zone - *** EXTENDS ZONES ***
--

function cfxNDB.startNDB(theNDB)
	theNDB.ndbRefreshTime = timer.getTime() + theNDB.ndbRefresh -- only used in linkedUnit, but set up anyway
	-- generate new ID 
	theNDB.ndbID = dcsCommon.uuid("ndb")
	local fileName = "l10n/DEFAULT/" .. theNDB.ndbSound -- need to prepend the resource string
	local modulation = 0
	if theNDB.fm then modulation = 1 end 
	
	local loc = cfxZones.getPoint(theNDB)
	trigger.action.radioTransmission(fileName, loc, modulation, true, theNDB.freq, theNDB.power, theNDB.ndbID)
	
	if cfxNDB.verbose then 
		local dsc = ""
		if theNDB.linkedUnit then 
			dsc = " (linked to ".. theNDB.linkedUnit:getName() .. "!, r=" .. theNDB.ndbRefresh .. ") "
		end 
		trigger.action.outText("+++ndb: started " .. theNDB.name .. dsc .. " at " .. theNDB.freq/1000000 .. "mod " .. modulation .. " with w=" .. theNDB.power .. " s=<" .. fileName .. ">", 30)
	end
end

function cfxNDB.stopNDB(theNDB)
	trigger.action.stopRadioTransmission(theNDB.ndbID)
end

function cfxNDB.createNDBWithZone(theZone)
	theZone.freq = cfxZones.getNumberFromZoneProperty(theZone, "NDB", 124) -- in MHz
	-- convert MHz to Hz
	theZone.freq = theZone.freq * 1000000 -- Hz
	theZone.fm = cfxZones.getBoolFromZoneProperty(theZone, "fm", false) 
	theZone.ndbSound = cfxZones.getStringFromZoneProperty(theZone, "soundFile", "<none>")
	theZone.power = cfxZones.getNumberFromZoneProperty(theZone, "watts", cfxNDB.power)
	theZone.loop = true -- always. NDB always loops
	-- UNSUPPORTED refresh. Although read individually, it only works 
	-- when LARGER than module's refresh.
	theZone.ndbRefresh = cfxZones.getNumberFromZoneProperty(theZone, "ndbRefresh", cfxNDB.refresh) -- only used if linked
	theZone.ndbRefreshTime = timer.getTime() + theZone.ndbRefresh -- only used with linkedUnit, but set up nonetheless
	-- start it 
	cfxNDB.startNDB(theZone)
	
	-- add it to my watchlist 
	table.insert(cfxNDB.ndbs, theZone)
end

--
-- update 
--
function cfxNDB.update()
	timer.scheduleFunction(cfxNDB.update, {}, timer.getTime() + 1/cfxNDB.ups)
	local now = timer.getTime()
	-- walk through all NDB and see if they need a refresh
	for idx, theNDB in pairs (cfxNDB.ndbs) do 
		-- see if this ndb is linked, meaning it's potentially 
		-- moving with the linked unit 
		if theNDB.linkedUnit then 
			-- yupp, need to update
			if now > theNDB.ndbRefreshTime then 
				cfxNDB.stopNDB(theNDB)
				cfxNDB.startNDB(theNDB)
			end
		end
	end
end

--
-- start up
--
function cfxNDB.readConfig()
	local theZone = cfxZones.getZoneByName("ndbConfig") 
	if not theZone then 
		if cfxNDB.verbose then 
			trigger.action.outText("***ndb: NO config zone!", 30) 
		end
		return 
	end 
	
	cfxNDB.verbose = cfxZones.getBoolFromZoneProperty(theZone, "verbose", false) 	
	cfxNDB.ndbRefresh = cfxZones.getNumberFromZoneProperty(theZone, "ndbRefresh", 10)
	
	if cfxNDB.verbose then 
		trigger.action.outText("***ndb: read config", 30) 
	end
end

function cfxNDB.start()
	-- lib check 
	if not dcsCommon.libCheck("cfx NDB", 
		cfxNDB.requiredLibs) then
		return false 
	end
	
	-- config 
	cfxNDB.readConfig()
	
	-- read zones 
	local attrZones = cfxZones.getZonesWithAttributeNamed("NDB")
	for idx, aZone in pairs(attrZones) do 
		cfxNDB.createNDBWithZone(aZone)
	end
	
	-- start update 
	cfxNDB.update()
	
	return true 
end

if not cfxNDB.start() then 
	trigger.action.outText("cf/x NDB aborted: missing libraries", 30)
	cfxNDB = nil 
end