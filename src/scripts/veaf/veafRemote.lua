-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- VEAF remote callback functions for DCS World
-- By zip (2020)
--
-- Features:
-- ---------
-- * This module offers support for calling script from a web server
--
-- Prerequisite:
-- ------------
-- * This script requires DCS 2.5.1 or higher and MIST 4.3.74 or higher.
-- * It also requires NIOD !
-- * It also requires all the veaf scripts !
--
-- Basic Usage:
-- ------------
-- TODO
--
-------------------------------------------------------------------------------------------------------------------------------------------------------------
package.path  = package.path..";"..lfs.currentdir().."/LuaSocket/?.lua"..";"..lfs.writedir() .. "/Mods/services/BufferingSocket/lua/?.lua"
package.cpath = package.cpath..";"..lfs.currentdir().."/LuaSocket/?.dll"..';'.. lfs.writedir()..'/Mods/services/BufferingSocket/bin/' ..'?.dll;'
local socket = require("socket")
veafRemote.config = require "BufferingSocketConfig"

veafRemote = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings. Stores the script constants
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Identifier. All output in DCS.log will start with this.
veafRemote.Id = "REMOTE - "

--- Version.
veafRemote.Version = "2.1.0"

-- trace level, specific to this module
veafRemote.Debug = true
veafRemote.Trace = true

-- if false, SLMOD will not be called for regular commands
veafRemote.USE_SLMOD = false

-- if false, SLMOD will never be called
veafRemote.USE_SLMOD_FOR_SPECIAL_COMMANDS = false

veafRemote.SecondsBetweenFlagMonitorChecks = 5

veafRemote.CommandStarter = "_remote"

veafRemote.MIN_LEVEL_FOR_MARKER = 10
veafRemote.PACKET_DELAY_IN_SECONDS = 0.5
veafRemote.DATA_REFRESH_IN_SECONDS = 10
veafRemote.DATASET_SLICE_SIZE = 500
veafRemote.DATASET_PACKET_SIZE = 500

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Do not change anything below unless you know what you are doing!
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veafRemote.monitoredFlags = {}
veafRemote.monitoredCommands = {}
veafRemote.maxMonitoredFlag = 27000
veafRemote.remoteUsers = {}
veafRemote.udpSocket = nil
veafRemote.config = {}
veafRemote.dataSet = nil
veafRemote.dataSets = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utility methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.logError(message)
    veaf.logError(veafRemote.Id .. message)
end

function veafRemote.logWarning(message)
    veaf.logWarning(veafRemote.Id .. message)
end

function veafRemote.logInfo(message)
    veaf.logInfo(veafRemote.Id .. message)
end

function veafRemote.logDebug(message)
    if message and veafRemote.Debug then 
        veaf.logDebug(veafRemote.Id .. message)
    end
end

function veafRemote.logTrace(message)
    if message and veafRemote.Trace then 
        veaf.logTrace(veafRemote.Id .. message)
    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- SLMOD monitoring
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function veafRemote.monitorWithSlModSpecialCommand(command, script, requireAdmin, flag, coalition)
    -- don't schedule because it causes problems with interpreter commands that are being executed too soon
    -- mist.scheduleFunction(veafRemote._monitorWithSlMod, {command, script, flag, coalition, requireAdmin, true}, timer.getTime()+5)    
    veafRemote._monitorWithSlMod(command, script, flag, coalition, requireAdmin, true)
end

function veafRemote.monitorWithSlMod(command, script, requireAdmin, flag, coalition)
    -- don't schedule because it causes problems with interpreter commands that are being executed too soon
    --mist.scheduleFunction(veafRemote._monitorWithSlMod, {command, script, flag, coalition, requireAdmin, false}, timer.getTime()+5)    
    veafRemote._monitorWithSlMod(command, script, flag, coalition, requireAdmin, false)
end

function veafRemote._monitorWithSlMod(command, script, flag, coalition, requireAdmin, isSpecialCommand)
    
    local actualFlag = flag
    if not actualFlag then
        actualFlag = veafRemote.maxMonitoredFlag + 1
        veafRemote.maxMonitoredFlag = actualFlag
    end
    
    local actualCoalition = coalition or "all"
    
    local actualRequireAdmin = requireAdmin
    if actualRequireAdmin == nil then
        actualRequireAdmin = true
    end
    
    local isSpecialCommand = isSpecialCommand
    if isSpecialCommand == nil then
        isSpecialCommand = false
    end

    veafRemote.logTrace(string.format("setting remote configuration for command=[%s], script=[%s], flag=[%d], requireAdmin=[%s], coalition=[%s]",tostring(command), tostring(script), actualFlag, tostring(actualRequireAdmin), tostring(actualCoalition)))
    veafRemote.monitoredCommands[command:lower()] = {script=script, requireAdmin=requireAdmin}
    if veafRemote.USE_SLMOD or (veafRemote.USE_SLMOD_FOR_SPECIAL_COMMANDS and isSpecialCommand) then 
        if slmod  then
            slmod.chat_cmd(command, actualFlag, -1, actualCoalition, actualRequireAdmin)
            veafRemote.startMonitoringFlag(actualFlag, script)
        end
    end
end

function veafRemote.startMonitoringFlag(flag, scriptToExecute)
    -- reset the flag
    trigger.action.setUserFlag(flag, false)
    veafRemote.monitoredFlags[flag] = scriptToExecute
    veafRemote._monitorFlags()
end

function veafRemote._monitorFlags()
    --veafRemote.logTrace("veafRemote._monitorFlags()")
    for flag, scriptToExecute in pairs(veafRemote.monitoredFlags) do
        --veafRemote.logTrace(string.format("veafRemote._monitorFlags() - checking flag %s", flag))
        local flagValue = trigger.misc.getUserFlag(flag)
        --veafRemote.logTrace(string.format("veafRemote._monitorFlags() - flagValue = [%d]", flagValue))
        if flagValue > 0 then
            -- call the script
            veafRemote.logDebug(string.format("veafRemote._monitorFlags() - flag %s was TRUE", flag))
            veafRemote.logDebug(string.format("veafRemote._monitorFlags() - calling lua code [%s]", scriptToExecute))
            local result, err = mist.utils.dostring(scriptToExecute)
            if result then
                veafRemote.logDebug(string.format("veafRemote._monitorFlags() - lua code was successfully called for flag [%s]", flag))
            else
                veafRemote.logError(string.format("veafRemote._monitorFlags() - error [%s] calling lua code for flag [%s]", err, flag))
            end
            -- reset the flag
            trigger.action.setUserFlag(flag, false)
            veafRemote.logDebug(string.format("veafRemote._monitorFlags() - flag [%s] was reset", flag))
        else
            --veafRemote.logTrace(string.format("veafRemote._monitorFlags() - flag %s was FALSE or not set", flag))
        end
    end
    mist.scheduleFunction(veafRemote._monitorFlags, nil, timer.getTime()+veafRemote.SecondsBetweenFlagMonitorChecks)    
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- NIOD callbacks
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.addNiodCallback(name, parameters, code)
    if niod then 
        veafRemote.logInfo("Adding NIOD function "..name)
        niod.functions[name] = function(payload)
        -- start of inline function
            
            veafRemote.logDebug(string.format("niod callback [%s] was called with payload %s", veaf.p(name), veaf.p(payload)))
            
            local errors = {}
            
            -- check mandatory parameters presence
            for parameterName, parameterData in pairs(parameters) do
                veafRemote.logTrace(string.format("checking if parameter [%s] is mandatory", veaf.p(parameterName)))
                if parameterData and parameterData.mandatory then 
                    if not (payload and payload[parameterName]) then 
                        local text = "missing mandatory parameter "..parameterName
                        veafRemote.logTrace(text)
                        table.insert(errors, text)
                    end
                end
            end
            
            -- check parameters type
            if payload then 
                for parameterName, value in pairs(payload) do
                    local parameter = parameters[parameterName]
                    if not parameter then 
                        table.insert(errors, "unknown parameter "..parameterName)
                    elseif value and not(type(value) == parameter.type) then
                        local text =  string.format("parameter %s should have type %s, has %s ", parameterName, parameter.type, type(value))
                        veafRemote.logTrace(text)
                        table.insert(errors, text)
                    end
                end
            end
            
            -- stop on error
            if #errors > 0 then
                local errorMessage = ""
                for _, error in pairs(errors) do
                    errorMessage = errorMessage .. "\n" .. error
                end
                veafRemote.logError(string.format("niod callback [%s] was called with incorrect parameters :", veaf.p(name), errorMessage))
                return errorMessage
            else
                veafRemote.logTrace(string.format("payload = %s", veaf.p(payload)))
                veafRemote.logTrace(string.format("unpacked payload = %s", veaf.p(veaf.safeUnpack(payload))))
                local status, retval = pcall(code,veaf.safeUnpack(payload))
                if status then
                    return retval
                else
                    return "an error occured : "..veaf.p(status)
                end
            end

        end -- of inline function

    else
        veafRemote.logError("NIOD is not loaded !")
    end
end

function veafRemote.addNiodCommand(name, command)
    veafRemote.addNiodCallback(
        name, 
        {
            parameters={   mandatory=false, type="string"}, 
            x={   mandatory=false, type="number"}, 
            y={   mandatory=false, type="number"}, 
            z={   mandatory=false, type="number"}, 
            silent={    mandatory=false, type="boolean"}
        },
        function(parameters, x, y, z, silent)
            veaf.logDebug(string.format("niod->command %s (%s, %s, %s, %s, %s)", veaf.p(parameters), veaf.p(x), veaf.p(y), veaf.p(z), veaf.p(silent)))
            return veafRemote.executeCommand({x=x or 0, y=y or 0, z=z or 0}, command..parameters, 99)
        end
    )
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- UDP socket send/receive
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- called every veafRemote.PACKET_DELAY_IN_SECONDS, send a partial dataset through the UDP socket (if a dataset exists)
function veafRemote.sendPartialDataset()
    -- reschedule the function
    timer.scheduleFunction(veafRemote.sendPartialDataset, nil, timer.getTime() + veafRemote.PACKET_DELAY_IN_SECONDS)
    
    if veafRemote.sendPartialDatasetInProgress then
        veafRemote.logWarning(string.format("veafRemote.sendPartialDataset reentry detected"))
        return
    end

    veafRemote.sendPartialDatasetInProgress = true

    -- slice the dataSet if needed 
    if veafRemote.dataSet and not(veafRemote.dataSets) then
        veafRemote.logTrace(string.format("#veafRemote.dataSet=%s",p(#veafRemote.dataSet)))
        veafRemote.dataSets = VeafDeque.new(veaf.tableSlice(veafRemote.dataSet, veafRemote.DATASET_SLICE_SIZE))
        veafRemote.logTrace(string.format("#veafRemote.dataSets=%s",p(#veafRemote.dataSets)))
    end

    if veafRemote.dataSets and not(veafRemote.dataSets:isempty()) then
        veafRemote.logTrace(string.format("#veafRemote.dataSets=%s",p(#veafRemote.dataSets)))
        local dataSet = veafRemote.dataSets:peekleft()
        if dataSet then 
            local nbUnits = 0
            local dataToSend = {}
            for _, unitName in pairs(dataSet) do
                veafRemote.logTrace(string.format("processing unittName=%s",veaf.p(unitName)))
                local unit = Unit.getByName(unitName)
                if unit then
                    unitData = {
                        name = unitName
                    }
                    unitData.typeName = unit:getTypeName()
                    if unit:getGroup() then 
                        unitData.groupName = unit:getGroup():getName()
                    end
                    unitData.coalition = unit:getCoalition()
                    unitData.country = unit:getCountry()
                    unitData.human = unit:getPlayerName()
                    unitData.isActive = unit:isActive()
                    unitData.life = unit:getLife()
                    unitData.fullLife = unit:getLife0()
                    unitData.fuel = unit:getFuel()
                    --unitData.ammo = unit:getAmmo() -- table is too big, will need to refine this later
                    
                    if (includePosition) then
                        unitData.position = unit:getPoint()
                        unitData.velocity = unit:getVelocity()
                        unitData.isInAir = unit:inAir()
                    end
                    veafRemote.logTrace(string.format("unitData=%s", veaf.p(unitData)))
                    table.insert(dataToSend, unitData)
                    nbUnits = nbUnits + 1
                end
            end
        
            veafRemote.logTrace(string.format("nbUnits=%s", veaf.p(nbUnits)))
        
            if json then
                -- prepare the data package
                veafRemote.logTrace(string.format("prepare the data package"))
                veafRemote.logTrace(string.format("data_package=%s",p(dataToSend)))
            
                local _payload = json.stringify(dataToSend) .. veafRemote.EOT_MARKER
            
                veafRemote.logTrace(string.format("_payload=%s",p(_payload)))
            
                -- send the payload
                veafRemote.logTrace(string.format("send the payload"))
                if not(veafRemote.udpSocket) then
                    veafRemote.udpSocket = socket.udp()
                    veafRemote.udpSocket:setpeername(veafRemote.config.host, veafRemote.config.port)
                end

                -- cut the payload into veafRemote.DATASET_PACKET_SIZE bytes packet
                for i=1, #_payload, veafRemote.DATASET_PACKET_SIZE do
                    veafRemote.udpSocket:send(_payload:sub(i, i+veafRemote.DATASET_PACKET_SIZE-1))
                end
            end      
        end
    end

    veafRemote.sendPartialDatasetInProgress = false
end

--- called every veafRemote.DATA_REFRESH_IN_SECONDS, prepares a new dataset
function veafRemote.prepareNewDataset(mistFilter, onlyHumans, includePosition)
    -- reschedule the function
    timer.scheduleFunction(veafRemote.prepareNewDataset, {mistFilter, onlyHumans, includePosition}, timer.getTime() + veafRemote.DATA_REFRESH_IN_SECONDS)

    if veafRemote.prepareNewDatasetInProgress then
        veafRemote.logWarning(string.format("veafRemote.prepareNewDataset reentry detected"))
        return
    end

    veafRemote.prepareNewDatasetInProgress = true
        
    

    veafRemote.prepareNewDatasetInProgress = false
end

-- returns a list of units for the remote interface to consume
function veafRemote.getUnitsListForRemote(mistFilter, onlyHumans, includePosition)
    veafRemote.logDebug(string.format("veafRemote.getUnitsListForRemote()"))
    veafRemote.logTrace(string.format("mistFilter=%s", veaf.p(mistFilter)))
    veafRemote.logTrace(string.format("onlyHumans=%s", veaf.p(onlyHumans)))
    veafRemote.logTrace(string.format("includePosition=%s", veaf.p(includePosition)))

    local mistFilter = mistFilter
    if not(mistFilter) or (#mistFilter == 0) then mistFilter = {"[all]"} end
    local result = {}
    local unitNames = mist.makeUnitTable(mistFilter, onlyHumans)
    --veafRemote.logTrace(string.format("unitNames=%s", veaf.p(unitNames)))
    local nbUnits = 0
    for _, unitName in pairs(unitNames) do
        --veafRemote.logTrace(string.format("processing unittName=%s",veaf.p(unitName)))
        local unit = Unit.getByName(unitName)
        if unit then
            unitData = {
                name = unitName
            }
            unitData.typeName = unit:getTypeName()
            if unit:getGroup() then 
                unitData.groupName = unit:getGroup():getName()
            end
            unitData.coalition = unit:getCoalition()
            unitData.country = unit:getCountry()
            unitData.human = unit:getPlayerName()
            unitData.isActive = unit:isActive()
            unitData.life = unit:getLife()
            unitData.fullLife = unit:getLife0()
            unitData.fuel = unit:getFuel()
            --unitData.ammo = unit:getAmmo() -- table is too big, will need to refine this later
            
            if (includePosition) then
                unitData.position = unit:getPoint()
                unitData.velocity = unit:getVelocity()
                unitData.isInAir = unit:inAir()
            end
            veafRemote.logTrace(string.format("unitData=%s", veaf.p(unitData)))
            table.insert(result, unitData)
            nbUnits = nbUnits + 1
        end
    end

    veafRemote.logTrace(string.format("nbUnits=%s", veaf.p(nbUnits)))

    if json then
        local resultAsJson = json.stringify(result)
        veafRemote.logTrace(string.format("resultAsJson=%s", veaf.p(resultAsJson)))
        resultAsJson = [[ [{ "name":"A-10C Batumi-0"}] ]]
        veafRemote.logTrace(string.format("resultAsJson=%s", veaf.p(resultAsJson)))
        return resultAsJson
    end

    return nil
end
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- default endpoints list
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.buildDefaultList()
    local TEST = false

    -- add all the combat missions
    if veafCombatMission then
        for _, mission in pairs(veafCombatMission.missionsDict) do
            local missionName = mission:getName()
            veafRemote.logTrace(string.format("Adding %s", missionName))
            veafRemote.monitorWithSlMod("-veaf start-silent-" .. missionName, [[ veafCombatMission.ActivateMission("]] .. missionName .. [[", true) ]])
            veafRemote.monitorWithSlMod("-veaf stop-silent-" .. missionName, [[ veafCombatMission.DesactivateMission("]] .. missionName .. [[", true) ]])
            veafRemote.monitorWithSlMod("-veaf start-" .. missionName, [[ veafCombatMission.ActivateMission("]] .. missionName .. [[", false) ]])
            veafRemote.monitorWithSlMod("-veaf stop-" .. missionName, [[ veafCombatMission.DesactivateMission("]] .. missionName .. [[", false) ]])
        end
    end

    -- add all the combat zones
    if veafCombatZone then
        for _, zone in pairs(veafCombatZone.zonesDict) do
            local zoneName = zone:getMissionEditorZoneName()
            veafRemote.logTrace(string.format("Adding %s", zoneName))
            veafRemote.monitorWithSlMod("-veaf start-silent-" .. zoneName, [[ veafCombatZone.ActivateZone("]] .. zoneName .. [[", true) ]])
            veafRemote.monitorWithSlMod("-veaf stop-silent-" .. zoneName, [[ veafCombatZone.DesactivateZone("]] .. zoneName .. [[", true) ]])
            veafRemote.monitorWithSlMod("-veaf start-" .. zoneName, [[ veafCombatZone.ActivateZone("]] .. zoneName .. [[", false) ]])
            veafRemote.monitorWithSlMod("-veaf stop-" .. zoneName, [[ veafCombatZone.DesactivateZone("]] .. zoneName .. [[", false) ]])
        end
    end

    if TEST then

        -- test
        veafRemote.addNiodCallback(
            "test", 
            {
                param1S_M={  mandatory=true, type="string"}, 
                param2S={  mandatory=false, type="string"}, 
                param3N={  mandatory=false, type="number"}, 
                param4B={  mandatory=false, type="boolean"}, 
            },
            function(param1S_M, param2S, param3N, param4B)
                local text = string.format("niod.test(%s, %s, %s, %s)", veaf.p(param1S_M), veaf.p(param2S), veaf.p(param3N), veaf.p(param4B))
                veafRemote.logDebug(text)
                trigger.action.outText(text, 15)
            end
        )
        -- login
        veafRemote.addNiodCallback(
            "login", 
            {
                password={  mandatory=true, type="string"}, 
                timeout={   mandatory=false, type="number"}, 
                silent={    mandatory=false, type="boolean"}
            },
            function(password, timeout, silent)
                veafRemote.logDebug(string.format("niod.login(%s, %s, %s)",veaf.p(password), veaf.p(timeout),veaf.p(silent))) -- TODO remove password from log
                if veafSecurity.checkPassword_L1(password) then
                    veafSecurity.authenticate(silent, timeout)
                    return "Mission is unlocked"
                else
                    return "wrong password"
                end
            end
        )

    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Event handler functions.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Function executed when a mark has changed. This happens when text is entered or changed.
function veafRemote.onEventMarkChange(eventPos, event)
    if veafRemote.executeCommand(eventPos, event.text) then 
        
        -- Delete old mark.
        veafRemote.logTrace(string.format("Removing mark # %d.", event.idx))
        trigger.action.removeMark(event.idx)

    end
end


function veafRemote.executeCommand(eventPos, eventText)
    veafRemote.logDebug(string.format("veafRemote.executeCommand(eventText=[%s])", tostring(eventText)))

    -- Check if marker has a text and the veafRemote.CommandStarter keyphrase.
    if eventText ~= nil and eventText:lower():find(veafRemote.CommandStarter) then
        
        -- Analyse the mark point text and extract the keywords.
        local command, password = veafRemote.markTextAnalysis(eventText)

        if command then
            -- do the magic
            return veafRemote.executeRemoteCommand(command, password)
        end
    end
end

--- Extract keywords from mark text.
function veafRemote.markTextAnalysis(text)
    veafRemote.logTrace(string.format("veafRemote.markTextAnalysis(text=[%s])", tostring(text)))
  
    if text then 
        -- extract command and password
        local password, command = text:match(veafRemote.CommandStarter.."#?([^%s]*)%s+(.+)")
        if command then
            veafRemote.logTrace(string.format("command = [%s]", command))
            return command, password
        end
    end
    return nil
end

-- execute a command
function veafRemote.executeRemoteCommand(command, password)
    local command = command or ""
    local password = password or ""
    veafRemote.logDebug(string.format("veafRemote.executeRemoteCommand([%s])",command))
    if not(veafSecurity.checkPassword_L1(password)) then
        veafRemote.logError(string.format("veafRemote.executeRemoteCommand([%s]) - bad or missing password",command))
        trigger.action.outText("Bad or missing password",5)
        return false
    end
    local commandData = veafRemote.monitoredCommands[command:lower()]
    if commandData then 
        local scriptToExecute = commandData.script
        veafRemote.logTrace(string.format("found script [%s] for command [%s]", scriptToExecute, command))
        local authorized = (not(commandData.requireAdmin)) or (veafSecurity.checkSecurity_L9(password))
        if not authorized then 
            return false
        else
            local result, err = mist.utils.dostring(scriptToExecute)
            if result then
                veafRemote.logDebug(string.format("veafRemote.executeRemoteCommand() - lua code was successfully called for script [%s]", scriptToExecute))
                return true
            else
                veafRemote.logError(string.format("veafRemote.executeRemoteCommand() - error [%s] calling lua code for script [%s]", err, scriptToExecute))
                return false
            end
        end
    else
        veafRemote.logWarning(string.format("veafRemote.executeRemoteCommand : cannot find command [%s]",command or ""))
    end
    return false
end

-- execute command from the remote interface (see VEAF-server-hook.lua)
function veafRemote.executeCommandFromRemote(username, level, unitName, veafModule, command)
    veafRemote.logDebug(string.format("veafRemote.executeCommandFromRemote([%s], [%s], [%s], [%s], [%s])", veaf.p(username), veaf.p(level), veaf.p(unitName), veaf.p(veafModule), veaf.p(command)))
    --local _user = veafRemote.getRemoteUser(username)
    --veafRemote.logTrace(string.format("_user = [%s]",veaf.p(_user)))
    --if not _user then 
    --    return false
    --end
    if not veafModule or not username or not command then
        return false
    end
    local _user = { name = username, level = tonumber(level or "-1")}
    local _parameters = { _user, username, unitName, command }
    local _status, _retval
    local _module = veafModule:lower()
    if _module == "air" then
        veafRemote.logDebug(string.format("running veafCombatMission.executeCommandFromRemote"))
        _status, _retval = pcall(veafCombatMission.executeCommandFromRemote, _parameters)
    elseif _module == "point" then
        veafRemote.logDebug(string.format("running veafNamedPoints.executeCommandFromRemote"))
        _status, _retval = pcall(veafNamedPoints.executeCommandFromRemote, _parameters)
    elseif _module == "alias" then
        veafRemote.logDebug(string.format("running veafShortcuts.executeCommandFromRemote"))
        _status, _retval = pcall(veafShortcuts.executeCommandFromRemote, _parameters)
    elseif _module == "carrier" then
        veafRemote.logDebug(string.format("running veafShortcuts.executeCommandFromRemote"))
        _status, _retval = pcall(veafCarrierOperations.executeCommandFromRemote, _parameters)
    elseif _module == "secu" then
        veafRemote.logDebug(string.format("running veafSecurity.executeCommandFromRemote"))
        _status, _retval = pcall(veafSecurity.executeCommandFromRemote, _parameters)
    else
        veafRemote.logError(string.format("Module not found : [%s]", veaf.p(veafModule)))
        return false
    end
    veafRemote.logTrace(string.format("_status = [%s]",veaf.p(_status)))
    veafRemote.logTrace(string.format("_retval = [%s]",veaf.p(_retval)))
    if not _status then
        veafRemote.logError(string.format("Error when [%s] tried running [%s] : %s", veaf.p(_user.name), veaf.p(_code), veaf.p(_retval)))
    else
        veafRemote.logInfo(string.format("[%s] ran [%s] : %s", veaf.p(_user.name), veaf.p(_code), veaf.p(_retval)))
    end
    return _status
end

-- register a user from the server
function veafRemote.registerUser(username, userpower, ucid)
    veafRemote.logDebug(string.format("veafRemote.registerUser([%s], [%s], [%s])",veaf.p(username), veaf.p(userpower), veaf.p(ucid)))
    if not username or not ucid then 
        return false
    end
    veafRemote.remoteUsers[username:lower()] = { name = username, level = tonumber(userpower or "-1"), ucid = ucid }
end

-- return a user from the server table
function veafRemote.getRemoteUser(username)
    veafRemote.logDebug(string.format("veafRemote.getRemoteUser([%s])",veaf.p(username)))
    veafRemote.logTrace(string.format("veafRemote.remoteUsers = [%s]",veaf.p(veafRemote.remoteUsers)))
    if not username then 
        return nil
    end
    return veafRemote.remoteUsers[username:lower()]
end

function veafRemote.getTestValue(mistFilter, onlyHumans, includePosition)
    return 42
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- initialisation
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.initialize()
    veafRemote.logInfo("Initializing module")
    veafRemote.buildDefaultList()
    veafMarkers.registerEventHandler(veafMarkers.MarkerChange, veafRemote.onEventMarkChange)
end

veafRemote.logInfo(string.format("Loading version %s", veafRemote.Version))
