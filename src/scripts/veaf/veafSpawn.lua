-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- VEAF spawn command and functions for DCS World
-- By zip (2018)
--
-- Features:
-- ---------
-- * Listen to marker change events and execute spawn commands, with optional parameters
-- * Possibilities : 
-- *    - spawn a specific ennemy unit or group
-- *    - create a cargo drop to be picked by a helo
-- * Works with all current and future maps (Caucasus, NTTR, Normandy, PG, ...)
--
-- Prerequisite:
-- ------------
-- * This script requires DCS 2.5.1 or higher and MIST 4.3.74 or higher.
-- * It also requires the base veaf.lua script library (version 1.0 or higher)
-- * It also requires the veafMarkers.lua script library (version 1.0 or higher)
-- * It also requires the dcsUnits.lua script library (version 1.0 or higher)
-- * It also requires the veafUnits.lua script library (version 1.0 or higher)
--
-- Load the script:
-- ----------------
-- 1.) Download the script and save it anywhere on your hard drive.
-- 2.) Open your mission in the mission editor.
-- 3.) Add a new trigger:
--     * TYPE   "4 MISSION START"
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location of MIST and click OK.
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location of veaf.lua and click OK.
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location of veafMarkers.lua and click OK.
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location of veafUnits.lua and click OK.
--     * ACTION "DO SCRIPT FILE"
--     * OPEN --> Browse to the location of this script and click OK.
--     * ACTION "DO SCRIPT"
--     * set the script command to "veafSpawn.initialize()" and click OK.
-- 4.) Save the mission and start it.
-- 5.) Have fun :)
--
-- Basic Usage:
-- ------------
-- 1.) Place a mark on the F10 map.
-- 2.) As text enter a command
-- 3.) Click somewhere else on the map to submit the new text.
-- 4.) The command will be processed. A message will appear to confirm this
-- 5.) The original mark will disappear.
--
-- Commands and options: see online help function veafSpawn.help()
--
-- *** NOTE ***
-- * All keywords are CaSE inSenSITvE.
-- * Commas are the separators between options ==> They are IMPORTANT!
--
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- veafSpawn Table.
veafSpawn = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings. Stores the script constants
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Identifier. All output in DCS.log will start with this.
veafSpawn.Id = "SPAWN - "

--- Version.
veafSpawn.Version = "1.9.1"

-- trace level, specific to this module
veafSpawn.Trace = false

--- Key phrase to look for in the mark text which triggers the spawn command.
veafSpawn.SpawnKeyphrase = "_spawn"

--- Key phrase to look for in the mark text which triggers the destroy command.
veafSpawn.DestroyKeyphrase = "_destroy"

--- Key phrase to look for in the mark text which triggers the teleport command.
veafSpawn.TeleportKeyphrase = "_teleport"

--- Name of the spawned units group 
veafSpawn.RedSpawnedUnitsGroupName = "VEAF Spawned Units"

--- Illumination flare default initial altitude (in meters AGL)
veafSpawn.IlluminationFlareAglAltitude = 1000

veafSpawn.RadioMenuName = "SPAWN"

--- static object type spawned when using the "logistic" keyword
veafSpawn.LogisticUnitType = "FARP Ammo Dump Coating"
veafSpawn.LogisticUnitCategory = "Fortifications"

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Do not change anything below unless you know what you are doing!
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veafSpawn.rootPath = nil

-- counts the units generated 
veafSpawn.spawnedUnitsCounter = 0

-- store all the convoys spawned
veafSpawn.spawnedConvoys = {}


-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utility methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafSpawn.logError(message)
    veaf.logError(veafSpawn.Id .. message)
end

function veafSpawn.logInfo(message)
    veaf.logInfo(veafSpawn.Id .. message)
end    

function veafSpawn.logDebug(message)
    veaf.logDebug(veafSpawn.Id .. message)
end    

function veafSpawn.logTrace(message)
    if message and veafSpawn.Trace then
        veaf.logTrace(veafSpawn.Id .. message)
    end
end    

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Event handler functions.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Function executed when a mark has changed. This happens when text is entered or changed.
function veafSpawn.onEventMarkChange(eventPos, event)
    if veafSpawn.executeCommand(eventPos, event.text, event.coalition) then 
        
        -- Delete old mark.
        veafSpawn.logTrace(string.format("Removing mark # %d.", event.idx))
        trigger.action.removeMark(event.idx)

    end
end

function veafSpawn.executeCommand(eventPos, eventText, eventCoalition, bypassSecurity, spawnedGroups)
    -- choose by default the coalition opposing the player who triggered the event
    local coalition = 1
    if eventCoalition == 1 then
        coalition = 2
    end

    -- Check if marker has a text and the veafSpawn.keyphrase keyphrase.
    if eventText ~= nil and (eventText:lower():find(veafSpawn.SpawnKeyphrase) or eventText:lower():find(veafSpawn.DestroyKeyphrase) or eventText:lower():find(veafSpawn.TeleportKeyphrase)) then
        
        -- Analyse the mark point text and extract the keywords.
        local options = veafSpawn.markTextAnalysis(eventText)

        if options then
            local spawnedGroup = nil
            if not options.side then
                veafSpawn.logTrace(string.format("coalition=%d",coalition or -1))
                options.side = coalition
            end

            if not options.country then
                veafSpawn.logTrace(string.format("options.side=%d",options.side or -1))
                options.country = veaf.getFirstCountryInCoalition(options.side)
            end

            local routeDone = false

            -- Check options commands
            if options.unit then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnUnit(eventPos, options.name, options.country, options.speed, options.altitude, options.heading, options.unitName, options.role, options.laserCode, bypassSecurity)
            elseif options.group then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnGroup(eventPos, options.name, options.country, options.altitude, options.heading, options.spacing, bypassSecurity)
            elseif options.infantryGroup then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnInfantryGroup(eventPos, options.country, options.side, options.heading, options.spacing, options.defense, options.armor, options.size, bypassSecurity)
            elseif options.armoredPlatoon then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnArmoredPlatoon(eventPos, options.country, options.side, options.heading, options.spacing, options.defense, options.armor, options.size, bypassSecurity)
            elseif options.airDefenseBattery then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnAirDefenseBattery(eventPos, options.country, options.side, options.heading, options.spacing, options.defense, bypassSecurity)
            elseif options.transportCompany then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnTransportCompany(eventPos, options.country, options.side, options.heading, options.spacing, options.defense, options.size, bypassSecurity)
            elseif options.fullCombatGroup then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnFullCombatGroup(eventPos, options.country, options.side, options.heading, options.spacing, options.defense, options.armor, options.size, bypassSecurity)
            elseif options.convoy then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnConvoy(eventPos, options.country, options.side, options.patrol, options.offroad, options.destination, options.defense, options.size, options.armor, bypassSecurity)
                routeDone = true
            elseif options.cargo then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnCargo(eventPos, options.cargoType, options.cargoSmoke, options.unitName, bypassSecurity)
            elseif options.logistic then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L9(options.password)) then return end
                spawnedGroup = veafSpawn.spawnLogistic(eventPos, bypassSecurity)
            elseif options.destroy then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L1(options.password)) then return end
                veafSpawn.destroy(eventPos, options.radius, options.unitName)
            elseif options.teleport then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L1(options.password)) then return end
                veafSpawn.teleport(eventPos, options.name, bypassSecurity)
            elseif options.bomb then
                -- check security
                if not (bypassSecurity or veafSecurity.checkSecurity_L1(options.password)) then return end
                veafSpawn.spawnBomb(eventPos, options.bombPower, options.password)
            elseif options.smoke then
                veafSpawn.spawnSmoke(eventPos, options.smokeColor)
            elseif options.flare then
                veafSpawn.spawnIlluminationFlare(eventPos, options.alt)
            end
            if spawnedGroup then
                if not routeDone and options.destination then
                    --  make the group go to destination
                    local route = veaf.generateVehiclesRoute(eventPos, options.destination, not options.offroad, options.speed, options.patrol)
                    mist.goRoute(spawnedGroup, route)
                end
                if spawnedGroups then
                    table.insert(spawnedGroups, spawnedGroup)
                end
            end
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Analyse the mark text and extract keywords.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Extract keywords from mark text.
function veafSpawn.markTextAnalysis(text)
    veafSpawn.logTrace(string.format("veafSpawn.markTextAnalysis(text=%s)", text))

    -- Option parameters extracted from the mark text.
    local switch = {}
    switch.unit = false
    switch.group = false
    switch.cargo = false
    switch.logistic = false
    switch.smoke = false
    switch.flare = false
    switch.bomb = false
    switch.destroy = false
    switch.teleport = false
    switch.convoy = false
    switch.role = nil
    switch.laserCode = 1688
    switch.infantryGroup = false
    switch.armoredPlatoon = false
    switch.airDefenseBattery = false
    switch.transportCompany = false
    switch.fullCombatGroup = false
    switch.speed = nil

    -- spawned group/unit type/alias
    switch.name = ""

    -- spawned unit name
    switch.unitName = nil

    -- spawned group units spacing
    switch.spacing = 5
    
    switch.country = nil
    switch.side = nil
    switch.altitude = 0
    switch.heading = 0
    
    -- if true, group is part of a road convoy
    switch.isConvoy = false

    -- if true, group is patroling between its spawn point and its destination named point
    switch.patrol = false

    -- if true, group is set to not follow roads
    switch.offroad = false

    -- if set and convoy is true, send the group to the named point
    switch.destination = nil

    -- the size of the generated dynamic groups (platoons, convoys, etc.)
    switch.size = math.random(7) + 8

    -- defenses force ; ranges from 1 to 5, 5 being the toughest.
    switch.defense = math.random(5)

    -- armor force ; ranges from 1 to 5, 5 being the strongest and most modern.
    switch.armor = math.random(5)

    -- bomb power
    switch.bombPower = 100

    -- smoke color
    switch.smokeColor = trigger.smokeColor.Red

    -- optional cargo smoke
    switch.cargoSmoke = false

    -- destruction radius
    switch.radius = 150

    -- cargo type
    switch.cargoType = "ammo_cargo"

    -- flare agl altitude (meters)
    switch.alt = veafSpawn.IlluminationFlareAglAltitude

    switch.password = nil

    -- Check for correct keywords.
    if text:lower():find(veafSpawn.SpawnKeyphrase .. " unit") then
        switch.unit = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " group") then
        switch.group = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " convoy") then
        switch.convoy = true
        switch.size = 10 -- default the size parameter to 10
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " infantrygroup") then
        switch.infantryGroup = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " armorgroup") then
        switch.armoredPlatoon = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " samgroup") then
        switch.airDefenseBattery = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " transportgroup") then
        switch.transportCompany = true
        switch.size = math.random(2, 5)
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " combatgroup") then
        switch.fullCombatGroup = true
        switch.size = 1 -- default the size parameter to 1
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " smoke") then
        switch.smoke = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " flare") then
        switch.flare = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " cargo") then
        switch.cargo = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " logistic") then
        switch.logistic = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " bomb") then
        switch.bomb = true
    elseif text:lower():find(veafSpawn.SpawnKeyphrase .. " jtac") then
        switch.role = 'jtac'
        switch.unit = true
        -- default country for friendly JTAC: USA
        switch.country = "USA"
        -- default name for JTAC
        switch.name = "APC M1025 HMMWV"
        -- default JTAC name (will overwrite previous unit with same name)
        switch.unitName = "JTAC1"
    elseif text:lower():find(veafSpawn.DestroyKeyphrase) then
        switch.destroy = true
    elseif text:lower():find(veafSpawn.TeleportKeyphrase) then
        switch.teleport = true
    else
        return nil
    end

    -- keywords are split by ","
    local keywords = veaf.split(text, ",")

    for _, keyphrase in pairs(keywords) do
        -- Split keyphrase by space. First one is the key and second, ... the parameter(s) until the next comma.
        local str = veaf.breakString(veaf.trim(keyphrase), " ")
        local key = str[1]
        local val = str[2]

        if key:lower() == "unitname" then
            -- Set name.
            veafSpawn.logTrace(string.format("Keyword unitname = %s", val))
            switch.unitName = val
        end

        if (switch.group or switch.teleport or switch.unit) and key:lower() == "name" then
            -- Set name.
            veafSpawn.logTrace(string.format("Keyword name = %s", val))
            switch.name = val
        end

        if (key:lower() == "destination" or key:lower() == "dest") then
            -- Set destination.
            veafSpawn.logTrace(string.format("Keyword destination = %s", val))
            switch.destination = val
        end

        if key:lower() == "isconvoy" then
            veafSpawn.logTrace(string.format("Keyword isconvoy found", val))
            switch.convoy = true
        end

        if key:lower() == "patrol" then
            veafSpawn.logTrace(string.format("Keyword patrol found", val))
            switch.patrol = true
        end

        if key:lower() == "offroad" then
            veafSpawn.logTrace(string.format("Keyword offroad found", val))
            switch.offroad = true
        end

        if switch.destroy and key:lower() == "radius" then
            -- Set name.
            veafSpawn.logTrace(string.format("Keyword radius = %d", val))
            local nVal = tonumber(val)
            switch.radius = nVal
        end

        if key:lower() == "spacing" then
            -- Set spacing.
            veafSpawn.logTrace(string.format("Keyword spacing = %d", val))
            local nVal = tonumber(val)
            switch.spacing = nVal
        end
        
        if key:lower() == "alt" then
            -- Set altitude.
            veafSpawn.logTrace(string.format("Keyword alt = %d", val))
            local nVal = tonumber(val)
            switch.altitude = nVal
        end
        
        if key:lower() == "speed" then
            -- Set altitude.
            veafSpawn.logTrace(string.format("Keyword speed = %d", val))
            local nVal = tonumber(val)
            switch.speed = nVal
        end
        
        if key:lower() == "hdg" then
            -- Set heading.
            veafSpawn.logTrace(string.format("Keyword hdg = %d", val))
            local nVal = tonumber(val)
            switch.heading = nVal
        end
        
        if key:lower() == "heading" then
            -- Set heading.
            veafSpawn.logTrace(string.format("Keyword heading = %d", val))
            local nVal = tonumber(val)
            switch.heading = nVal
        end

        if key:lower() == "country" then
            -- Set country
            veafSpawn.logTrace(string.format("Keyword country = %s", val))
            switch.country = val:upper()
        end
        
        if key:lower() == "side" then
            -- Set side
            veafSpawn.logTrace(string.format("Keyword side = %s", val))
            if val:upper() == "BLUE" then
                switch.side = veafCasMission.SIDE_BLUE
            else
                switch.side = veafCasMission.SIDE_RED
            end
        end

        if key:lower() == "password" then
            -- Unlock the command
            veafSpawn.logTrace(string.format("Keyword password", val))
            switch.password = val
        end

        if key:lower() == "power" then
            -- Set bomb power.
            veafSpawn.logTrace(string.format("Keyword power = %d", val))
            local nVal = tonumber(val)
            switch.bombPower = nVal
        end
        
        if key:lower() == "laser" then
            -- Set laser code.
            veafSpawn.logTrace(string.format("laser code = %d", val))
            local nVal = tonumber(val)
            switch.laserCode = nVal
        end        
        
        if key:lower() == "color" then
            -- Set smoke color.
            veafSpawn.logTrace(string.format("Keyword color = %s", val))
            if (val:lower() == "red") then 
                switch.smokeColor = trigger.smokeColor.Red
            elseif (val:lower() == "green") then 
                switch.smokeColor = trigger.smokeColor.Green
            elseif (val:lower() == "orange") then 
                switch.smokeColor = trigger.smokeColor.Orange
            elseif (val:lower() == "blue") then 
                switch.smokeColor = trigger.smokeColor.Blue
            elseif (val:lower() == "white") then 
                switch.smokeColor = trigger.smokeColor.White
            end
        end

        if key:lower() == "alt" then
            -- Set alt.
            veafSpawn.logTrace(string.format("Keyword alt = %d", val))
            local nVal = tonumber(val)
            switch.alt = nVal
        end

        if switch.cargo and key:lower() == "name" then
            -- Set cargo type.
            veafSpawn.logTrace(string.format("Keyword name = %s", val))
            switch.cargoType = val
        end

        if switch.cargo and key:lower() == "smoke" then
            -- Mark with green smoke.
            veafSpawn.logTrace("Keyword smoke is set")
            switch.cargoSmoke = true
        end
        
        if key:lower() == "size" then
            -- Set size.
            veafSpawn.logTrace(string.format("Keyword size = %d", val))
            local nVal = tonumber(val)
            switch.size = nVal
        end

        if key:lower() == "defense" then
            -- Set defense.
            veafSpawn.logTrace(string.format("Keyword defense = %d", val))
            local nVal = tonumber(val)
            if nVal <= 5 and nVal >= 0 then
                switch.defense = nVal
            end
        end

        if key:lower() == "armor" then
            -- Set armor.
            veafSpawn.logTrace(string.format("Keyword armor = %d", val))
            local nVal = tonumber(val)
            if nVal <= 5 and nVal >= 0 then
                switch.armor = nVal
            end
        end
    end

    -- check mandatory parameter "name" for command "group"
    if switch.group and not(switch.name) then return nil end
    
    -- check mandatory parameter "name" for command "unit"
    if switch.unit and not(switch.name) then return nil end
    
    return switch
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Group spawn command
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Spawn a specific group at a specific spot
function veafSpawn.doSpawnGroup(spawnSpot, groupDefinition, country, alt, hdg, spacing, groupName, silent, shuffle)
    veafSpawn.logDebug(string.format("doSpawnGroup(country=%s, alt=%d, hdg=%d, spacing=%d, groupName=%s)", country, alt, hdg, spacing, groupName or ""))
    veafSpawn.logTrace("spawnSpot=" .. veaf.vecToString(spawnSpot))
    
    veafSpawn.spawnedUnitsCounter = veafSpawn.spawnedUnitsCounter + 1

    if type(groupDefinition) == "string" then
        local name = groupDefinition
        -- find the desired group in the groups database
        groupDefinition = veafUnits.findGroup(name)
        if not(groupDefinition) then
            veafSpawn.logInfo("cannot find group "..name)
            if not(silent) then
                trigger.action.outText("cannot find group "..name, 5) 
            end
            return    
        end
    end

    veafSpawn.logTrace("doSpawnGroup: groupDefinition.description=" .. groupDefinition.description)

    local units = {}

    -- place group units on the map
    local group, cells = veafUnits.placeGroup(groupDefinition, spawnSpot, spacing, hdg)
    veafUnits.traceGroup(group, cells)
    
    if not(groupName) then 
        groupName = group.groupName .. " #" .. veafSpawn.spawnedUnitsCounter
    end

    for i=1, #group.units do
        local unit = group.units[i]
        local unitType = unit.typeName
        local unitName = groupName .. " / " .. unit.displayName .. " #" .. i
        
        local spawnPoint = unit.spawnPoint
        if alt > 0 then
            spawnPoint.y = alt
        end
        
        -- check if position is correct for the unit type
        if not veafUnits.checkPositionForUnit(spawnPoint, unit) then
            veafSpawn.logInfo("cannot find a suitable position for spawning unit ".. unitType)
            if not(silent) then
                trigger.action.outText("cannot find a suitable position for spawning unit "..unitType, 5)
            end
        else 
            local toInsert = {
                    ["x"] = spawnPoint.x,
                    ["y"] = spawnPoint.z,
                    ["alt"] = spawnPoint.y,
                    ["type"] = unitType,
                    ["name"] = unitName,
                    ["speed"] = 0,  -- speed in m/s
                    ["skill"] = "Random",
                    ["heading"] = spawnPoint.hdg
            }
            
            veafSpawn.logTrace(string.format("toInsert x=%.1f y=%.1f, alt=%.1f, type=%s, name=%s, speed=%d, heading=%d, skill=%s, country=%s", toInsert.x, toInsert.y, toInsert.alt, toInsert.type, toInsert.name, toInsert.speed, mist.utils.toDegree(toInsert.heading), toInsert.skill, country ))
            table.insert(units, toInsert)
        end
    end

    -- shuffle the group if needed (useful for randomizing convoys)
    if shuffle then
        units = veaf.shuffle(units)
    end

    -- actually spawn the group
    if group.naval then
        mist.dynAdd({country = country, category = "SHIP", name = groupName, hidden = false, units = units})
    elseif group.air then
        mist.dynAdd({country = country, category = "AIRPLANE", name = groupName, hidden = false, units = units})
    else
        mist.dynAdd({country = country, category = "GROUND_UNIT", name = groupName, hidden = false, units = units})
    end

    if not(silent) then
        -- message the group spawning
        trigger.action.outText("A " .. group.description .. "("..country..") has been spawned", 5)
    end

    return groupName
end

--- Spawn a specific group at a specific spot
function veafSpawn.spawnGroup(spawnSpot, name, country, alt, hdg, spacing, silent)
    veafSpawn.logDebug(string.format("spawnGroup(name = %s, country=%s, alt=%d, hdg=%d, spacing=%d)",name, country, alt, hdg, spacing))
    veafSpawn.logTrace("spawnGroup: spawnSpot " .. veaf.vecToString(spawnSpot))
    local spawnedGroupName = veafSpawn.doSpawnGroup(spawnSpot, name, country, alt, hdg, spacing, nil, silent)

    return spawnedGroupName
end

function veafSpawn._createDcsUnits(country, units, groupName)
    veafSpawn.logDebug(string.format("veafSpawn._createDcsUnits([%s])",country or ""))
    local dcsUnits = {}
    for i=1, #units do
        local unit = units[i]
        local unitType = unit.typeName
        local unitName = groupName .. " / " .. unit.displayName .. " #" .. i
        local hdg = unit.heading or math.random(0, 359)
        local spawnPosition = unit.spawnPoint
        
        -- check if position is correct for the unit type
        if veafUnits.checkPositionForUnit(spawnPosition, unit) then
            local toInsert = {
                    ["x"] = spawnPosition.x,
                    ["y"] = spawnPosition.z,
                    ["alt"] = spawnPosition.y,
                    ["type"] = unitType,
                    ["name"] = unitName,
                    ["speed"] = 0,
                    ["skill"] = "Excellent",
                    ["heading"] = hdg
            }

            veafSpawn.logTrace(string.format("toInsert x=%.1f y=%.1f, alt=%.1f, type=%s, name=%s, speed=%d, heading=%d, skill=%s, country=%s", toInsert.x, toInsert.y, toInsert.alt, toInsert.type, toInsert.name, toInsert.speed, toInsert.heading, toInsert.skill, country ))
            table.insert(dcsUnits, toInsert)
        end
    end

    -- actually spawn groups
    mist.dynAdd({country = country, category = "GROUND_UNIT", name = groupName, hidden = false, units = dcsUnits})

    -- set AI options
    local controller = Group.getByName(groupName):getController()
    controller:setOption(AI.Option.Ground.id.ENGAGE_AIR_WEAPONS, true) -- engage air-to-ground weapons with SAMs
    controller:setOption(AI.Option.Air.id.ROE, 2) -- set fire at will
    controller:setOption(AI.Option.Ground.id.ROE, 2) -- set fire at will
    controller:setOption(AI.Option.Naval.id.ROE, 2) -- set fire at will
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, 2) -- set alarm state to red
    controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, 1) -- set disperse on attack according to the option
end

--- Spawns a dynamic infantry group 
function veafSpawn.spawnInfantryGroup(eventPos, country, side, heading, spacing, defense, armor, size, silent)
    veafSpawn.logDebug(string.format("spawnInfantryGroup(country=%s, side=%d, heading=%d, spacing=%d, defense=%d, armor=%d)",country, side, heading, spacing, defense, armor))
    veafSpawn.logTrace("eventPos=" .. veaf.vecToString(eventPos))

    local groupName = "spawn-" .. math.random(99999) .. " - Infantry Section "
    local group = veafCasMission.generateInfantryGroup(groupName, defense, armor, side, size)
    local group = veafUnits.processGroup(group)
    local groupPosition = veaf.placePointOnLand(eventPos)
    veafSpawn.logTrace(string.format("groupPosition = %s",veaf.vecToString(groupPosition)))
    local group, cells = veafUnits.placeGroup(group, groupPosition, spacing, heading)

    -- shuffle the units in the group
    units = veaf.shuffle(group.units)

    veafSpawn._createDcsUnits(country, group.units, groupName)
 
    if not silent then 
        trigger.action.outText("Spawned dynamic infantry group "..groupName, 5)
    end

    return groupName
end

--- Spawns a dynamic armored platoon
function veafSpawn.spawnArmoredPlatoon(eventPos, country, side, heading, spacing, defense, armor, size, silent)
    veafSpawn.logDebug(string.format("spawnArmoredPlatoon(country=%s, side=%d, heading=%d, spacing=%d, defense=%d, armor=%d, size=%d)",country, side, heading, spacing, defense, armor, size))
    veafSpawn.logTrace("eventPos=" .. veaf.vecToString(eventPos))

    local groupName = "spawn-" .. math.random(99999) .. " - Armored Platoon "
    local group = veafCasMission.generateArmorPlatoon(groupName, defense, armor, side, size)
    local group = veafUnits.processGroup(group)
    local groupPosition = veaf.placePointOnLand(eventPos)
    veafSpawn.logTrace(string.format("groupPosition = %s",veaf.vecToString(groupPosition)))
    local group, cells = veafUnits.placeGroup(group, groupPosition, spacing, heading)

    -- shuffle the units in the group
    units = veaf.shuffle(group.units)

    veafSpawn._createDcsUnits(country, group.units, groupName)
 
    if not silent then 
        trigger.action.outText("Spawned dynamic armored platoon "..groupName, 5)
    end

    return groupName
end

--- Spawns a dynamic air defense battery
function veafSpawn.spawnAirDefenseBattery(eventPos, country, side, heading, spacing, defense, silent)
    veafSpawn.logDebug(string.format("spawnAirDefenseBattery(country=%s, side=%d, heading=%d, spacing=%d, defense=%d)",country, side, heading, spacing, defense))
    veafSpawn.logTrace("eventPos=" .. veaf.vecToString(eventPos))

    local groupName = "spawn-" .. math.random(99999) .. " - Air Defense Battery "
    local group = veafCasMission.generateAirDefenseGroup(groupName, defense, side)
    local group = veafUnits.processGroup(group)
    local groupPosition = veaf.placePointOnLand(eventPos)
    veafSpawn.logTrace(string.format("groupPosition = %s",veaf.vecToString(groupPosition)))
    local group, cells = veafUnits.placeGroup(group, groupPosition, spacing, heading)

    -- shuffle the units in the group
    units = veaf.shuffle(group.units)

    veafSpawn._createDcsUnits(country or veaf.getFirstCountryInCoalition(side), group.units, groupName)
 
    if not silent then 
        trigger.action.outText("Spawned dynamic air defense battery "..groupName, 5)
    end

    return groupName
end

--- Spawns a dynamic transport company
function veafSpawn.spawnTransportCompany(eventPos, country, side, heading, spacing, defense, size, silent)
    veafSpawn.logDebug(string.format("spawnTransportCompany(country=%s, side=%d, heading=%d, spacing=%d, defense=%d, size=%d)",country, side, heading, spacing, defense, size))
    veafSpawn.logTrace("eventPos=" .. veaf.vecToString(eventPos))

    local groupName = "spawn-" .. math.random(99999) .. " - Transport Company "
    local group = veafCasMission.generateTransportCompany(groupName, defense, side, size)
    local group = veafUnits.processGroup(group)
    local groupPosition = veaf.placePointOnLand(eventPos)
    veafSpawn.logTrace(string.format("groupPosition = %s",veaf.vecToString(groupPosition)))
    local group, cells = veafUnits.placeGroup(group, groupPosition, spacing, heading)

    -- shuffle the units in the group
    units = veaf.shuffle(group.units)

    veafSpawn._createDcsUnits(country, group.units, groupName)
 
    if not silent then 
        trigger.action.outText("Spawned dynamic transport company "..groupName, 5)
    end

    return groupName
end

--- Spawns a dynamic full combat group composed of multiple platoons
function veafSpawn.spawnFullCombatGroup(eventPos, country, side, heading, spacing, defense, armor, size, silent)
    veafSpawn.logDebug(string.format("spawnFullCombatGroup(country=%s, side=%d, heading=%d, spacing=%d, defense=%d, armor=%d, size=%d)",country, side, heading, spacing, defense, armor, size))
    veafSpawn.logTrace("eventPos=" .. veaf.vecToString(eventPos))

    local groupName = "spawn-" .. math.random(99999) .. " - Full Combat Group "
    local groupPosition = veaf.placePointOnLand(eventPos)
    local units = veafCasMission.generateCasGroup(country, groupName, groupPosition, size, defense, armor, spacing, true, side)

    veafSpawn._createDcsUnits(country, units, groupName)
 
    if not silent then 
        trigger.action.outText("Spawned full combat group "..groupName, 5)
    end

    return groupName
end

--- Spawn a specific group at a specific spot
function veafSpawn.spawnConvoy(spawnSpot, country, side, patrol, offroad, destination, defense, size, armor, silent)
    veafSpawn.logDebug(string.format("spawnConvoy(country=%s, destination=%s, defense=%d, size=%d, armor=%d)",country, destination, defense, size, armor))
    veafSpawn.logTrace("spawnSpot=" .. veaf.vecToString(spawnSpot))
    if not destination then return end

    local units = {}
    local groupId = math.random(99999)
    local groupName = "convoy-" .. groupId

    
    -- generate the transport vehicles and air defense
    if size and size > 0 then -- this is only for reading clarity sake
        -- generate the group
        local group = veafCasMission.generateTransportCompany(groupId, defense, side, size)

        -- process the group 
        local group = veafUnits.processGroup(group)
        
        -- place its units
        local group, cells = veafUnits.placeGroup(group, veaf.placePointOnLand(spawnSpot), 4, math.random(359))
        veafUnits.traceGroup(group, cells)
        
        -- add the units to the global units list
        for _,u in pairs(group.units) do
            table.insert(units, u)
        end
    end

    -- generate the armored vehicles
    if armor and armor > 0 then
        -- generate the group
        local group = veafCasMission.generateArmorPlatoon(groupId, defense, armor)
        
        -- process the group 
        local group = veafUnits.processGroup(group)
        
        -- place its units
        local group, cells = veafUnits.placeGroup(group, veaf.placePointOnLand(spawnSpot), 4, math.random(359))
        
        -- add the units to the global units list
        for _,u in pairs(group.units) do
            table.insert(units, u)
        end
    end

    -- shuffle the units in the convoy
    units = veaf.shuffle(units)

    veafSpawn._createDcsUnits(country, units, groupName)
 
    local route = veaf.generateVehiclesRoute(spawnSpot, destination, not offroad)
    veafSpawn.spawnedConvoys[groupName] = route

    --  make the group go to destination
    veafSpawn.logTrace("make the group go to destination : ".. groupName)
    mist.goRoute(groupName, route)

    -- make it patrol
    if patrol then
        veafSpawn.logTrace("make the group patrol : ".. groupName)
        -- TODO later 
        -- for now it crashes with an error like "MIST|getGroupRoute|5982: convoy-68254 not found in mist.DBs.MEgroupsByName"
        -- I tried making it scheduled but it still doesn't work
        
        -- mist.ground.patrol(groupName, 'doubleBack')
    end

    if not silent then 
        trigger.action.outText("Spawned convoy "..groupName, 5)
    end

    return groupName
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Unit spawn command
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Spawn a specific unit at a specific spot
-- @param position spawnPosition
-- @param string name
-- @param string country
-- @param int speed
-- @param int alt
-- @param int speed
-- @param int hdg (0..359)
-- @param string unitName (callsign)
-- @param string role (ex: jtac)
-- @param int laserCode (ex: 1688)
function veafSpawn.spawnUnit(spawnPosition, name, country, speed, alt, hdg, unitName, role, laserCode, silent)
    veafSpawn.logDebug(string.format("spawnUnit(name = %s, country=%s, speed=%d, alt=%d, hdg= %d)",name, country, speed, alt, hdg))
    veafSpawn.logTrace(string.format("spawnUnit: spawnPosition  x=%.1f y=%.1f, z=%.1f", spawnPosition.x, spawnPosition.y, spawnPosition.z))
    
    veafSpawn.spawnedUnitsCounter = veafSpawn.spawnedUnitsCounter + 1

    -- find the desired unit in the groups database
    local unit = veafUnits.findUnit(name)
    
    if not(unit) then
        veafSpawn.logInfo("cannot find unit "..name)
        trigger.action.outText("cannot find unit "..name, 5)
        return    
    end
  
    -- cannot spawn planes or helos yet [TODO]
    if unit.air then
        veafSpawn.logInfo("Air units cannot be spawned at the moment (work in progress)")
        trigger.action.outText("Air units cannot be spawned at the moment (work in progress)", 5)
        return    
    end
    
    local units = {}
    local groupName = nil
    
    veafSpawn.logTrace("spawnUnit unit = " .. unit.displayName .. ", dcsUnit = " .. tostring(unit.typeName))
    
    if role == "jtac" then
      groupName = "jtac_" .. laserCode
      unitName = "jtac_" .. laserCode
    else
      groupName = veafSpawn.RedSpawnedUnitsGroupName .. " #" .. veafSpawn.spawnedUnitsCounter
      if not unitName then
        unitName = unit.displayName .. " #" .. veafSpawn.spawnedUnitsCounter
      end
    end
    
    veafSpawn.logTrace("groupName="..groupName)
    veafSpawn.logTrace("unitName="..unitName)

    if alt > 0 then
        spawnPosition.y = alt
    end

    -- check if position is correct for the unit type
    if not  veafUnits.checkPositionForUnit(spawnPosition, unit) then
        veafSpawn.logInfo("cannot find a suitable position for spawning unit "..unit.displayName)
        trigger.action.outText("cannot find a suitable position for spawning unit "..unit.displayName, 5)
        return
    else 
        local toInsert = {
                ["x"] = spawnPosition.x,
                ["y"] = spawnPosition.z,
                ["alt"] = spawnPosition.y,
                ["type"] = unit.typeName,
                ["name"] = unitName,
                ["speed"] = 0,
                ["skill"] = "Random",
                ["heading"] = mist.utils.toRadian(hdg),
        }

        veafSpawn.logTrace(string.format("toInsert x=%.1f y=%.1f, alt=%.1f, type=%s, name=%s, speed=%d, skill=%s, country=%s", toInsert.x, toInsert.y, toInsert.alt, toInsert.type, toInsert.name, toInsert.speed, toInsert.skill, country ))
        table.insert(units, toInsert)       
    end

    -- actually spawn the unit
    if unit.naval then
        veafSpawn.logTrace("Spawning SHIP")
        mist.dynAdd({country = country, category = "SHIP", name = groupName, units = units})
    elseif unit.air then
        veafSpawn.logTrace("Spawning AIRPLANE")
        mist.dynAdd({country = country, category = "PLANE", name = groupName, units = units})
    else
        veafSpawn.logTrace("Spawning GROUND_UNIT")
        mist.dynAdd({country = country, category = "GROUND_UNIT", name = groupName, units = units})
    end

    if role == "jtac" then
        -- JTAC needs to be invisible and immortal
        local _setImmortal = {
            id = 'SetImmortal',
            params = {
                value = true
            }
        }
        -- invisible to AI, Shagrat
        local _setInvisible = {
            id = 'SetInvisible',
            params = {
                value = true
            }
        }

        local spawnedGroup = Group.getByName(groupName)
        local controller = spawnedGroup:getController()
        Controller.setCommand(controller, _setImmortal)
        Controller.setCommand(controller, _setInvisible)

        -- start lasing 
        if ctld then 
            ctld.JTACAutoLase(groupName, laserCode, false, "vehicle")
        end
      end

    -- message the unit spawning
    if not silent then 
        trigger.action.outText("A " .. unit.displayName .. "("..country..") has been spawned", 5)
    end

    return groupName
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Cargo spawn command
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Spawn a specific cargo at a specific spot
function veafSpawn.spawnCargo(spawnSpot, cargoType, cargoSmoke, unitName, silent)
    veafSpawn.logDebug("spawnCargo(cargoType = " .. cargoType ..")")
    veafSpawn.logTrace(string.format("spawnCargo: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))

    return veafSpawn.doSpawnCargo(spawnSpot, cargoType, unitName, cargoSmoke, silent)
end

--- Spawn a logistic unit for CTLD at a specific spot
function veafSpawn.spawnLogistic(spawnSpot, silent)
    veafSpawn.logDebug("spawnLogistic()")
    veafSpawn.logTrace(string.format("spawnLogistic: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))

    local unitName = veafSpawn.doSpawnStatic(spawnSpot, veafSpawn.LogisticUnitCategory, veafSpawn.LogisticUnitType, nil, false, true)
    
    veafSpawn.logDebug(string.format("spawnLogistic: inserting %s into CTLD logistics list", unitName))
    if ctld then 
        table.insert(ctld.logisticUnits, unitName)
    end

    -- message the unit spawning
    if not silent then 
        local message = "Logistic unit " .. unitName .. " has been spawned and was added to CTLD."
        trigger.action.outText(message, 5)
    end
    
end

--- Spawn a specific cargo at a specific spot
function veafSpawn.doSpawnCargo(spawnSpot, cargoType, unitName, cargoSmoke, silent)
    veafSpawn.logDebug("spawnCargo(cargoType = " .. cargoType ..")")
    veafSpawn.logTrace(string.format("spawnCargo: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))

    local units = {}

    local spawnPosition = veaf.findPointInZone(spawnSpot, 50, false)

    -- check spawned position validity
    if spawnPosition == nil then
        veafSpawn.logInfo("cannot find a suitable position for spawning cargo "..cargoType)
        if not(silent) then trigger.action.outText("cannot find a suitable position for spawning cargo "..cargoType, 5) end
        return
    end

    veafSpawn.logTrace(string.format("spawnCargo: spawnPosition  x=%.1f y=%.1f", spawnPosition.x, spawnPosition.y))
  
    -- compute cargo weight
    local cargoWeight = 250
    local unit = veafUnits.findDcsUnit(cargoType)
    if not unit then
        cargoType = cargoType.. "_cargo"
        unit = veafUnits.findDcsUnit(cargoType)
    end
    if unit then
        if unit.desc.minMass and unit.desc.maxMass then
            cargoWeight = math.random(unit.desc.minMass, unit.desc.maxMass)
        elseif unit.defaultMass then
            cargoWeight = unit.defaultMass
            cargoWeight = math.random(cargoWeight - cargoWeight / 2, cargoWeight + cargoWeight / 2)
        end
        if cargoWeight then

            if not(unitName) then
                veafSpawn.spawnedUnitsCounter = veafSpawn.spawnedUnitsCounter + 1
                unitName = unit.desc.displayName .. " #" .. veafSpawn.spawnedUnitsCounter
            end

            -- create the cargo
            local cargoTable = {
                type = cargoType,
                country = 'USA',
                category = 'Cargos',
                name = unitName,
                x = spawnPosition.x,
                y = spawnPosition.y,
                canCargo = true,
                mass = cargoWeight
            }
            
            mist.dynAddStatic(cargoTable)
            
            -- smoke the cargo if needed
            if cargoSmoke then 
                local smokePosition={x=spawnPosition.x + mist.random(10,20), y=0, z=spawnPosition.y + mist.random(10,20)}
                local height = veaf.getLandHeight(smokePosition)
                smokePosition.y = height
                veafSpawn.logTrace(string.format("spawnCargo: smokePosition  x=%.1f y=%.1f z=%.1f", smokePosition.x, smokePosition.y, smokePosition.z))
                veafSpawn.spawnSmoke(smokePosition, trigger.smokeColor.Green)
                for i = 1, 10 do
                    veafSpawn.logTrace("Signal flare 1 at " .. timer.getTime() + i*7)
                    mist.scheduleFunction(veafSpawn.spawnSignalFlare, {smokePosition,trigger.flareColor.Red, mist.random(359)}, timer.getTime() + i*3)
                end
            end

            -- message the unit spawning
            local message = "Cargo " .. unitName .. " weighting " .. cargoWeight .. " kg has been spawned"
            if cargoSmoke then 
                message = message .. ". It's marked with green smoke and red flares"
            end
            if not(silent) then trigger.action.outText(message, 5) end
        end
    end
    return unitName
end


--- Spawn a specific static at a specific spot
function veafSpawn.doSpawnStatic(spawnSpot, staticCategory, staticType, unitName, smoke, silent)
    veafSpawn.logDebug("doSpawnStatic(staticCategory = " .. staticCategory ..")")
    veafSpawn.logDebug("doSpawnStatic(staticType = " .. staticType ..")")
    veafSpawn.logTrace(string.format("doSpawnStatic: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))

    local units = {}

    local spawnPosition = veaf.findPointInZone(spawnSpot, 50, false)

    -- check spawned position validity
    if spawnPosition == nil then
        veafSpawn.logInfo("cannot find a suitable position for spawning static "..staticType)
        if not(silent) then trigger.action.outText("cannot find a suitable position for spawning static "..staticType, 5) end
        return
    end

    veafSpawn.logTrace(string.format("doSpawnStatic: spawnPosition  x=%.1f y=%.1f", spawnPosition.x, spawnPosition.y))
  
    local unit = veafUnits.findDcsUnit(staticType)
    if unit then
        if not(unitName) then
            veafSpawn.spawnedUnitsCounter = veafSpawn.spawnedUnitsCounter + 1
            unitName = unit.desc.displayName .. " #" .. veafSpawn.spawnedUnitsCounter
        end

        -- create the static
        local staticTable = {
            category = staticCategory,
            type = staticType,
            country = 'USA',
            name = unitName,
            x = spawnPosition.x,
            y = spawnPosition.y
        }
        
        mist.dynAddStatic(staticTable)
        
        -- smoke if needed
        if smoke then 
            local smokePosition={x=spawnPosition.x + mist.random(10,20), y=0, z=spawnPosition.y + mist.random(10,20)}
            local height = veaf.getLandHeight(smokePosition)
            smokePosition.y = height
            veafSpawn.logTrace(string.format("doSpawnStatic: smokePosition  x=%.1f y=%.1f z=%.1f", smokePosition.x, smokePosition.y, smokePosition.z))
            veafSpawn.spawnSmoke(smokePosition, trigger.smokeColor.Green)
            for i = 1, 10 do
                veafSpawn.logTrace("Signal flare 1 at " .. timer.getTime() + i*7)
                mist.scheduleFunction(veafSpawn.spawnSignalFlare, {smokePosition,trigger.flareColor.Red, mist.random(359)}, timer.getTime() + i*3)
            end
        end

        -- message the unit spawning
        local message = "Static " .. unitName .. " has been spawned"
        if smoke then 
            message = message .. ". It's marked with green smoke and red flares"
        end
        if not(silent) then trigger.action.outText(message, 5) end
    end
    return unitName
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Smoke and Flare commands
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- trigger an explosion at the marker area
function veafSpawn.spawnBomb(spawnSpot, power, password)
    veafSpawn.logDebug("spawnBomb(power=" .. power ..")")
    veafSpawn.logTrace(string.format("spawnBomb: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))
    -- check security
    if not veafSecurity.checkPassword_L0(password) then
        if power > 1000 then power = 1000 end
    end

    trigger.action.explosion(spawnSpot, power);
end

--- add a smoke marker over the marker area
function veafSpawn.spawnSmoke(spawnSpot, color)
    veafSpawn.logDebug("spawnSmoke(color = " .. color ..")")
    veafSpawn.logTrace(string.format("spawnSmoke: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))
    local spawnSmoke_yCorrected  = veaf.placePointOnLand(spawnSpot)
    veafSpawn.logTrace(string.format("spawnSmoke_yCorrected: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSmoke_yCorrected.x, spawnSmoke_yCorrected.y, spawnSmoke_yCorrected.z))
	trigger.action.smoke(spawnSmoke_yCorrected, color)
end

--- add a signal flare over the marker area
function veafSpawn.spawnSignalFlare(spawnSpot, color, azimuth)
    veafSpawn.logDebug("spawnSignalFlare(color = " .. color ..")")
    veafSpawn.logTrace(string.format("spawnSignalFlare: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))
	trigger.action.signalFlare(spawnSpot, color, azimuth)
end

--- add an illumination flare over the target area
function veafSpawn.spawnIlluminationFlare(spawnSpot, height)
    if height == nil then height = veafSpawn.IlluminationFlareAglAltitude end
    veafSpawn.logDebug("spawnIlluminationFlare(height = " .. height ..")")
    veafSpawn.logTrace(string.format("spawnIlluminationFlare: spawnSpot  x=%.1f y=%.1f, z=%.1f", spawnSpot.x, spawnSpot.y, spawnSpot.z))
    local vec3 = {x = spawnSpot.x, y = veaf.getLandHeight(spawnSpot) + height, z = spawnSpot.z}
	trigger.action.illuminationBomb(vec3)
end

--- destroy unit(s)
function veafSpawn.destroy(spawnSpot, radius, unitName)
    if unitName then
        -- destroy a specific unit
        local c = Unit.getByName(unitName)
        if c then
            Unit.destroy(c)
        end

        -- or a specific static
        c = StaticObject.getByName(unitName)
        if c then
            StaticObject.destroy(c)
        end

        -- or a specific group
        c = Group.getByName(unitName)
        if c then
            Group.destroy(c)
        end
    else
        -- TODO radius based destruction
        local units = veaf.findUnitsInCircle(spawnSpot, radius)
        if units then
            for name, _ in pairs(units) do
                -- try and find a  unit
                local unit = Unit.getByName(name)
                if unit then 
                    Unit.destroy(unit)
                else
                    unit = StaticObject.getByName(name)
                    if unit then 
                        StaticObject.destroy(unit)
                    end
                end
            end
        end
    end
end

--- teleport group
function veafSpawn.teleport(spawnSpot, name, silent)
    veafSpawn.logDebug("teleport(name = " .. name ..")")
    local vars = { groupName = name, point = spawnSpot, action = "teleport" }
    local grp = mist.teleportToPoint(vars)
    if not silent then 
        if grp then
            trigger.action.outText("Teleported group "..name, 5) 
        else
            trigger.action.outText("Cannot teleport group : "..name, 5) 
        end
    end
end

function veafSpawn.markClosestConvoyWithSmoke(unitName)
    return veafSpawn._markClosestConvoyWithSmoke(unitName, false)
end

function veafSpawn.markClosestConvoyRouteWithSmoke(unitName)
    return veafSpawn._markClosestConvoyWithSmoke(unitName, true)
end

function veafSpawn._markClosestConvoyWithSmoke(unitName, markRoute)
    veafSpawn.logDebug(string.format("veafSpawn.markClosestConvoyWithSmoke(unitName=%s)",unitName))
    local closestConvoyName = nil
    local minDistance = 99999999
    local unit = Unit.getByName(unitName)
    if unit then
        for name, _ in pairs(veafSpawn.spawnedConvoys) do
            local averageGroupPosition = veaf.getAveragePosition(name)
            distanceFromPlayer = ((averageGroupPosition.x - unit:getPosition().p.x)^2 + (averageGroupPosition.z - unit:getPosition().p.z)^2)^0.5
            veafSpawn.logTrace(string.format("distanceFromPlayer = %d",distanceFromPlayer))
            if distanceFromPlayer < minDistance then
                minDistance = distanceFromPlayer
                closestConvoyName = name
                veafSpawn.logTrace(string.format("convoy %s is closest",closestConvoyName))
            end
        end
    end
    if closestConvoyName then
        if markRoute then
            local route = veafSpawn.spawnedConvoys[closestConvoyName]
            local startPoint = veaf.placePointOnLand({x = route[1].x, y = 0, z = route[1].y})
            local endPoint = veaf.placePointOnLand({x = route[2].x, y = 0, z = route[2].y})
            trigger.action.smoke(startPoint, trigger.smokeColor.Green)
            trigger.action.smoke(endPoint, trigger.smokeColor.Red)
            veaf.outTextForUnit(unitName, closestConvoyName .. " is going from green to red smoke", 10)
        else
            local averageGroupPosition = veaf.getAveragePosition(closestConvoyName)
            trigger.action.smoke(averageGroupPosition, trigger.smokeColor.White)
            veaf.outTextForUnit(unitName, closestConvoyName .. " marked with white smoke", 10)
        end
    else
        veaf.outTextForUnit(unitName, "No convoy found", 10)
    end
end

function veafSpawn.infoOnAllConvoys(unitName)
    veafSpawn.logDebug(string.format("veafSpawn.infoOnAllConvoys(unitName=%s)",unitName))
    local text = ""
    for name, _ in pairs(veafSpawn.spawnedConvoys) do
        local nbVehicles, nbInfantry = veafUnits.countInfantryAndVehicles(name)
        if nbVehicles > 0 then
            local averageGroupPosition = veaf.getAveragePosition(name)
            local lat, lon = coord.LOtoLL(averageGroupPosition)
            local llString = mist.tostringLL(lat, lon, 0, true)
            text = text .. " - " .. name .. ", " .. nbVehicles .. " vehicles : " .. llString
        else
            text = text .. " - " .. name .. "has been destroyed"
            -- convoy has been dispatched, remove it from the convoys list
            veafSpawn.spawnedConvoys[name] = nil
        end
    end
    if text == "" then
        veaf.outTextForUnit(unitName, "No convoy found", 10)
    else
        veaf.outTextForUnit(unitName, text, 30)
    end
end

function veafSpawn.cleanupAllConvoys()
    veafSpawn.logDebug("veafSpawn.cleanupAllConvoys()")
    local foundOne = false
    for name, _ in pairs(veafSpawn.spawnedConvoys) do
        foundOne = true
        local nbVehicles, nbInfantry = veafUnits.countInfantryAndVehicles(name)
        if nbVehicles > 0 then
            local group = Group.getByName(name)
            if group then
                Group.destroy(group)
            end
        end
        -- convoy has been dispatched, remove it from the convoys list
        veafSpawn.spawnedConvoys[name] = nil
    end
    if foundOne then
        trigger.action.outText("All convoys cleaned up", 10)
    else
        trigger.action.outText("No convoy found", 10)
    end
end    
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Radio menu and help
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Build the initial radio menu
function veafSpawn.buildRadioMenu()
    veafSpawn.rootPath = veafRadio.addSubMenu(veafSpawn.RadioMenuName)
    veafRadio.addCommandToSubmenu("HELP", veafSpawn.rootPath, veafSpawn.help, nil, veafRadio.USAGE_ForGroup)
    veafRadio.addCommandToSubmenu("HELP - all units", veafSpawn.rootPath, veafSpawn.helpAllUnits, nil, veafRadio.USAGE_ForGroup)
    veafRadio.addCommandToSubmenu("HELP - all groups", veafSpawn.rootPath, veafSpawn.helpAllGroups, nil, veafRadio.USAGE_ForGroup)
    veafRadio.addCommandToSubmenu("HELP - all cargoes", veafSpawn.rootPath, veafSpawn.helpAllCargoes, nil, veafRadio.USAGE_ForGroup)
    veafRadio.addCommandToSubmenu("Info on all convoys", veafSpawn.rootPath, veafSpawn.infoOnAllConvoys, nil, veafRadio.USAGE_ForGroup)
    local infoOnClosestConvoyPath = veafRadio.addSubMenu("Mark closest convoy route", veafSpawn.rootPath)
    veafRadio.addCommandToSubmenu("Mark closest convoy route" , infoOnClosestConvoyPath, veafSpawn.markClosestConvoyRouteWithSmoke, nil, veafRadio.USAGE_ForUnit)    
    local infoOnClosestConvoyPath = veafRadio.addSubMenu("Mark closest convoy", veafSpawn.rootPath)
    veafRadio.addCommandToSubmenu("Mark closest convoy" , infoOnClosestConvoyPath, veafSpawn.markClosestConvoyWithSmoke, nil, veafRadio.USAGE_ForUnit)    
    veafRadio.addSecuredCommandToSubmenu('Cleanup all convoys', veafSpawn.rootPath, veafSpawn.cleanupAllConvoys)
    veafRadio.refreshRadioMenu()
end

function veafSpawn.help(unitName)
    local text = 
        'Create a marker and type "_spawn <unit|group|convoy|cargo|bomb|logistic|smoke|flare|jtac> " in the text\n' ..
        'This will spawn the requested object in the DCS world\n' ..
        'You can add options (comma separated) :\n' ..
        '"_spawn unit, name [unit name]" spawns a target vehicle/ship  ; name can be any DCS type\n' ..
        '   "country [country name]" spawns a unit of a specific country ; name can be any DCS country\n' ..
        '   "alt [altitude]" spawns the unit at the specified altitude\n' ..
        '   "hdg [heading]" spawns the unit facing a heading\n' ..
        '_spawn group, name [group name]" spawns a specific group ; name must be a group name from the VEAF Groups Database\n' ..
        '   "spacing <spacing>" specifies the (randomly modified) units spacing in unit size multiples\n' ..
        '   "country [country name]" spawns a group of a specific country ; name can be any DCS country\n' ..
        '   "speed [speed]" spawns the group already moving\n' ..
        '   "alt [altitude]" spawns the group at the specified altitude\n' ..
        '   "hdg [heading]" spawns the group facing a heading\n' ..
        '_spawn convoy, destination [named point]" spawns a convoy ; destination must be a known named point\n' ..
        '   "country [country name]" spawns a group of a specific country ; name can be any DCS country\n' ..
        '   "defense 0" completely disables air defenses\n' ..
        '   "defense [1-5]" specifies air defense cover (1 = light, 5 = heavy)\n' ..
        '   "size [nb]" changes the number of transport vehicles\n' ..
        '   "armor [1-5]" specifies armor presence (1 = light, 5 = heavy)\n' ..
        '"_spawn cargo" creates a cargo ready to be picked up\n' ..
        '   "name [cargo type]" spawns a specific cargo ; name can be any of [ammo, barrels, container, fueltank, f_bar, iso_container, iso_container_small, m117, oiltank, pipes_big, pipes_small, tetrapod, trunks_long, trunks_small, uh1h]\n' ..
        '   "smoke adds a smoke marker\n' ..
        '"_spawn bomb" spawns a bomb on the ground\n' ..
        '   "power [value]" specifies the bomb power (default is 100, max is 1000)\n' ..
        '"_spawn logistic" spawns a logistic respawn area for CTLD on the ground\n' ..
        '"_spawn smoke" spawns a smoke on the ground\n' ..
        '   "color [red|green|blue|white|orange]" specifies the smoke color\n' ..
        '"_spawn flare" lights things up with a flare\n' ..
        '   "alt <altitude in meters agl>" specifies the initial altitude\n' ..
        '"_spawn jtac" spawns a humvee with JTAC capacity\n' ..
        '"_destroy" will destroy the units around the marker\n' ..
        '   "radius <radius in meters>" specifies the destruction radius\n' ..
        '   "unit <unit name>" specifies the name of the unit to destroy\n' ..
        '"_teleport" will teleport a group to the marker\n' ..
        '   "name <group name>" specifies the name of the group to teleport' 
            
    veaf.outTextForUnit(unitName, text, 30)
end

function veafSpawn.helpAllGroups(unitName)
    local text = 'List of all groups defined in dcsUnits :\n'
            
    for _, g in pairs(veafUnits.GroupsDatabase) do
        if not g.hidden then
            text = text .. " - " .. (g.group.description or g.group.groupName) .. " -> "
            for i=1, #g.aliases do
                text = text .. g.aliases[i]
                if i < #g.aliases then text = text .. ", " end
            end
            text = text .. "\n"
        end
    end
    veaf.outTextForUnit(unitName, text, 30)
end

function veafSpawn.helpAllUnits(unitName)
    local text = 'List of all units defined in dcsUnits :\n'
            
    for _, u in pairs(veafUnits.UnitsDatabase) do
        if not u.hidden then
            text = text .. " - " .. u.unitType .. " -> "
            for i=1, #u.aliases do
                text = text .. u.aliases[i]
                if i < #u.aliases then text = text .. ", " end
            end
            text = text .. "\n"
        end
    end
    veaf.outTextForUnit(unitName, text, 30)
end

function veafSpawn.helpAllCargoes(unitName)
    local text = 'List of all cargoes defined in dcsUnits :\n'
            
    for name, unit in pairs(dcsUnits.DcsUnitsDatabase) do
        if unit and unit.desc and unit.desc.attributes and unit.desc.attributes.Cargos then
            text = text .. " - " .. unit.desc.typeName .. " -> " .. unit.desc.displayName 
            if unit.desc.minMass and unit.desc.maxMass then
                text = text .. " (" .. unit.desc.minMass .. " - " .. unit.desc.maxMass .. " kg)"
            elseif unit.defaultMass then
                text = text .. " (" .. unit.defaultMass .. " kg)"
            end
            text = text .."\n"
        end
    end
    veaf.outTextForUnit(unitName, text, 30)
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- initialisation
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafSpawn.initialize()
    veafSpawn.buildRadioMenu()
    veafMarkers.registerEventHandler(veafMarkers.MarkerChange, veafSpawn.onEventMarkChange)
end

veafSpawn.logInfo(string.format("Loading version %s", veafSpawn.Version))
