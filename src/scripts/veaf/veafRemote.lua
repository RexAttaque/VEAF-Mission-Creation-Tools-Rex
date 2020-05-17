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

veafRemote = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings. Stores the script constants
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Identifier. All output in DCS.log will start with this.
veafRemote.Id = "REMOTE - "

--- Version.
veafRemote.Version = "0.0.1"

-- trace level, specific to this module
veafRemote.Trace = true

veafRemote.SecondsBetweenFlagMonitorChecks = 5

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Do not change anything below unless you know what you are doing!
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veafRemote.monitoredFlags = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utility methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.logError(message)
    veaf.logError(veafRemote.Id .. message)
end

function veafRemote.logInfo(message)
    veaf.logInfo(veafRemote.Id .. message)
end

function veafRemote.logDebug(message)
    veaf.logDebug(veafRemote.Id .. message)
end

function veafRemote.logTrace(message)
    if message and veafRemote.Trace then 
        veaf.logTrace(veafRemote.Id .. message)
    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- SLMOD monitoring
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.monitorWithSlMod(command, script, flag, coalition, requireAdmin)
    mist.scheduleFunction(veafRemote._monitorWithSlMod, {command, script, flag, coalition, requireAdmin}, timer.getTime()+5)    
end

function veafRemote._monitorWithSlMod(command, script, flag, coalition, requireAdmin)
    if slmod then
        veafRemote.logDebug(string.format("setting SLMOD configuration for command=[%s], script=[%s], flag=[%d], requireAdmin=[%s]",tostring(command), tostring(script), flag, tostring(requireAdmin)))
        slmod.chat_cmd(command, flag, -1, coalition or "all", requireAdmin or false)
        veafRemote.startMonitoringFlag(flag, script)
    else
        veafRemote.logInfo("SLMOD not found")
    end
end

function veafRemote.startMonitoringFlag(flag, scriptToExecute)
    -- reset the flag
    trigger.action.setUserFlag(flag, false)
    veafRemote.monitoredFlags[flag] = scriptToExecute
    veafRemote._monitorFlags()
end

function veafRemote._monitorFlags()
    veafRemote.mainLogDebug("_monitorFlags()")
    for flag, scriptToExecute in pairs(veafRemote.monitoredFlags) do
        veafRemote.mainLogTrace(string.format("_monitorFlags() - checking flag %s", flag))
        local flagValue = trigger.misc.getUserFlag(flag)
        veafRemote.mainLogTrace(string.format("_monitorFlags() - flagValue = [%d]", flagValue))
        if flagValue > 0 then
            -- call the script
            veafRemote.mainLogTrace(string.format("_monitorFlags() - flag %s was TRUE", flag))
            veafRemote.mainLogTrace(string.format("_monitorFlags() - calling lua code [%s]", scriptToExecute))
            local result, err = mist.utils.dostring(scriptToExecute)
            if result then
                veafRemote.mainLogDebug(string.format("_monitorFlags() - lua code was successfully called for flag [%s]", flag))
            else
                veafRemote.mainLogError(string.format("_monitorFlags() - error [%s] calling lua code for flag [%s]", err, flag))
            end
            -- reset the flag
            trigger.action.setUserFlag(flag, false)
            veafRemote.mainLogDebug(string.format("_monitorFlags() - flag [%s] was reset", flag))
        else
            veafRemote.mainLogTrace(string.format("_monitorFlags() - flag %s was FALSE or not set", flag))
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
                veafRemote.logTrace(string.format("unpacked payload = %s", veaf.p(unpack(payload))))
                local status, retval = pcall(code,unpack(payload))
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
            return veafShortcuts.executeCommand({x=x or 0, y=y or 0, z=z or 0}, command..parameters, 99)
        end
    )
end
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- initialisation
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.initialize()
    veafRemote.logInfo("Initializing module")
    veafRemote.buildDefaultList()
end

veafRemote.logInfo(string.format("Loading version %s", veafRemote.Version))

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- default endpoints list
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafRemote.buildDefaultList()
    veafRemote.monitorWithSlMod("-veaf test", [[trigger.action.outText("VEAF - test command received from SLMOD, flag=66600", 10)]], 66600, "all", false)
    veafRemote.monitorWithSlMod("-veaf login", [[veafSecurity.authenticate()]], 66601, "all", true)
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
