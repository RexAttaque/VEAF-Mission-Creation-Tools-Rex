-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- VEAF CTLD wrapper
-- By zip (2020)
--
-- Features:
-- ---------
-- * This module wraps CTLD to add and modify some of its features
--
-- Prerequisite:
-- ------------
-- * This script requires DCS 2.5.1 or higher and MIST 4.3.74 or higher.
-- * It also requires CTLD !
-- * It also requires the veaf and veadRadio scripts !
--
-- Basic Usage:
-- ------------
-- TODO
--
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veafCTLD = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings. Stores the script constants
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Identifier. All output in DCS.log will start with this.
veafCTLD.Id = "CTLD - "

--- Version.
veafCTLD.Version = "1.0.0.1"

-- trace level, specific to this module
veafCTLD.Trace = true

veafCTLD.SecondsBetweenRadioMenuRebuild = 5

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Do not change anything below unless you know what you are doing!
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Radio menus paths
veafCTLD.rootPath = nil

--- human pilots CTLD status
veafCTLD.humanPilotsCtldStatus = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utility methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafCTLD.logError(message)
    veaf.logError(veafCTLD.Id .. message)
end

function veafCTLD.logInfo(message)
    veaf.logInfo(veafCTLD.Id .. message)
end

function veafCTLD.logDebug(message)
    veaf.logDebug(veafCTLD.Id .. message)
end

function veafCTLD.logTrace(message)
    if message and veafCTLD.Trace then 
        veaf.logTrace(veafCTLD.Id .. message)
    end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Radio menu 
-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Set slingload method.
function veafCTLD.setSlingLoad(parameters)

    veafCTLD.logDebug(string.format("veafCTLD.setSlingLoad - parameters", veaf.p(parameters)))
    local unitName, slingLoadActivated = veaf.safeUnpack(parameters)
    veafCTLD.logDebug(string.format("veafCTLD.setSlingLoad(%s, %d)", unitName, slingLoadActivated))
    ctld.slingLoad = slingLoadActivated

    local _msg = "Sling loading has been deactivated ; crates have limbs now !"
    if _activate then _msg = "Sling loading has been activated ; load those ropes !" end
    ctld.displayMessageToGroup(unitName, _msg, 20)

    veafCTLD.rebuildRadioMenu()
end

local function getHumanPilotCtldStatus(humanPilot)
    if veafCTLD.humanPilotsCtldStatus[humanPilot] == nil then
        veafCTLD.humanPilotsCtldStatus[humanPilot] = false
        for _, _unitName in pairs(ctld.transportPilotNames) do
            if _unitName == humanPilot then
                veafCTLD.humanPilotsCtldStatus[humanPilot] = true
                break
            end
        end
    end
    return veafCTLD.humanPilotsCtldStatus[humanPilot]
end

--- Rebuild the radio menu
function veafCTLD.rebuildRadioMenu()
    veafCTLD.logDebug("veafCTLD.rebuildRadioMenu()")
    veafRadio.clearSubmenu(veafCTLD.rootPath)

    for unitName, _ in ipairs(veafRadio.humanUnits) do
        if getHumanPilotCtldStatus(unitName) then
            
            -- human unit is a transport pilot
            local _unit = ctld.getTransportUnit(_unitName)

            if _unit ~= nil then
                local _unitActions = ctld.getUnitActions(_unit:getTypeName())

                if _unitActions.troops then

                    local _troopCommandsPath = veafRadio.addSubMenuForGroup(_groupId, "Troop Transport",   veafCTLD.rootPath)

                    missionCommands.addCommandForGroup(_groupId, "Unload / Extract Troops", _troopCommandsPath, ctld.unloadExtractTroops, { _unitName })

                    missionCommands.addCommandForGroup(_groupId, "Check Cargo", _troopCommandsPath, ctld.checkTroopStatus, { _unitName })

                    for _,_loadGroup in pairs(ctld.loadableGroups) do
                        if not _loadGroup.side or _loadGroup.side == _unit:getCoalition() then

                            -- check size & unit
                            if ctld.getTransportLimit(_unit:getTypeName()) >= _loadGroup.total then
                                missionCommands.addCommandForGroup(_groupId, "Load ".._loadGroup.name, _troopCommandsPath, ctld.loadTroopsFromZone, { _unitName, true,_loadGroup,false })
                            end
                        end
                    end

                    if ctld.unitCanCarryVehicles(_unit) then

                        local _vehicleCommandsPath = missionCommands.addSubMenuForGroup(_groupId, "Vehicle / FOB Transport",   veafCTLD.rootPath)

                        missionCommands.addCommandForGroup(_groupId, "Unload Vehicles", _vehicleCommandsPath, ctld.unloadTroops, { _unitName, false })
                        missionCommands.addCommandForGroup(_groupId, "Load / Extract Vehicles", _vehicleCommandsPath, ctld.loadTroopsFromZone, { _unitName, false,"",true })

                        if ctld.enabledFOBBuilding and ctld.staticBugWorkaround == false then

                            missionCommands.addCommandForGroup(_groupId, "Load / Unload FOB Crate", _vehicleCommandsPath, ctld.loadUnloadFOBCrate, { _unitName, false })
                        end
                        missionCommands.addCommandForGroup(_groupId, "Check Cargo", _vehicleCommandsPath, ctld.checkTroopStatus, { _unitName })
                    end

                end


                if ctld.enableCrates and _unitActions.crates then

                    if ctld.unitCanCarryVehicles(_unit) == false then

                        -- add menu for spawning crates
                        for _subMenuName, _crates in pairs(ctld.spawnableCrates) do

                            local _cratePath = missionCommands.addSubMenuForGroup(_groupId, _subMenuName,   veafCTLD.rootPath)
                            for _, _crate in pairs(_crates) do

                                if ctld.isJTACUnitType(_crate.unit) == false
                                        or (ctld.isJTACUnitType(_crate.unit) == true and ctld.JTAC_dropEnabled) then
                                    if _crate.side == nil or (_crate.side == _unit:getCoalition()) then

                                        local _crateRadioMsg = _crate.desc

                                        --add in the number of crates required to build something
                                        if _crate.cratesRequired ~= nil and _crate.cratesRequired > 1 then
                                            _crateRadioMsg = _crateRadioMsg.." (".._crate.cratesRequired..")"
                                        end

                                        missionCommands.addCommandForGroup(_groupId,_crateRadioMsg, _cratePath, ctld.spawnCrate, { _unitName, _crate.weight })
                                    end
                                end
                            end
                        end
                    end
                end

                if (ctld.enabledFOBBuilding or ctld.enableCrates) and _unitActions.crates then

                    local _crateCommands = missionCommands.addSubMenuForGroup(_groupId, "CTLD Commands",   veafCTLD.rootPath)
                    if ctld.hoverPickup == false then
                        if  ctld.slingLoad == false then
                            missionCommands.addCommandForGroup(_groupId, "Load Nearby Crate", _crateCommands, ctld.loadNearbyCrate,  _unitName )
                        end
                    end

                    missionCommands.addCommandForGroup(_groupId, "Unpack Any Crate", _crateCommands, ctld.unpackCrates, { _unitName })

                    if ctld.slingLoad == false then
                        missionCommands.addCommandForGroup(_groupId, "Drop Crate", _crateCommands, ctld.dropSlingCrate, { _unitName })
                        missionCommands.addCommandForGroup(_groupId, "Current Cargo Status", _crateCommands, ctld.slingCargoStatus, { _unitName })
                    end

                    missionCommands.addCommandForGroup(_groupId, "List Nearby Crates", _crateCommands, ctld.listNearbyCrates, { _unitName })

                    if ctld.enabledFOBBuilding then
                        missionCommands.addCommandForGroup(_groupId, "List FOBs", _crateCommands, ctld.listFOBS, { _unitName })
                    end

                    if ctld.slingLoad == false then
                        missionCommands.addCommandForGroup(_groupId, "Activate slingload", _crateCommands, ctld.setSlingLoad, { _unitName, true })
                    else
                        missionCommands.addCommandForGroup(_groupId, "Deactivate slingload", _crateCommands, ctld.setSlingLoad, { _unitName, false })
                    end

                end


                if ctld.enableSmokeDrop then
                    local _smokeMenu = missionCommands.addSubMenuForGroup(_groupId, "Smoke Markers",   veafCTLD.rootPath)
                    missionCommands.addCommandForGroup(_groupId, "Drop Red Smoke", _smokeMenu, ctld.dropSmoke, { _unitName, trigger.smokeColor.Red })
                    missionCommands.addCommandForGroup(_groupId, "Drop Blue Smoke", _smokeMenu, ctld.dropSmoke, { _unitName, trigger.smokeColor.Blue })
                    missionCommands.addCommandForGroup(_groupId, "Drop Orange Smoke", _smokeMenu, ctld.dropSmoke, { _unitName, trigger.smokeColor.Orange })
                    missionCommands.addCommandForGroup(_groupId, "Drop Green Smoke", _smokeMenu, ctld.dropSmoke, { _unitName, trigger.smokeColor.Green })
                end

                if ctld.enabledRadioBeaconDrop then
                    local _radioCommands = missionCommands.addSubMenuForGroup(_groupId, "Radio Beacons",   veafCTLD.rootPath)
                    missionCommands.addCommandForGroup(_groupId, "List Beacons", _radioCommands, ctld.listRadioBeacons, { _unitName })
                    missionCommands.addCommandForGroup(_groupId, "Drop Beacon", _radioCommands, ctld.dropRadioBeacon, { _unitName })
                    missionCommands.addCommandForGroup(_groupId, "Remove Closet Beacon", _radioCommands, ctld.removeRadioBeacon, { _unitName })
                elseif ctld.deployedRadioBeacons ~= {} then
                    local _radioCommands = missionCommands.addSubMenuForGroup(_groupId, "Radio Beacons",   veafCTLD.rootPath)
                    missionCommands.addCommandForGroup(_groupId, "List Beacons", _radioCommands, ctld.listRadioBeacons, { _unitName })
                end
            end
        else
            -- human unit is not a transport pilot
        end
    end
    -- add specific protected recovery radio commands
    --veafRadio.addSecuredCommandToSubmenu( "Start CASE I - 45'",   veafCTLD.rootPath, veafCTLD.startRecovery, {case=1, time=45}, veafRadio.USAGE_ForGroup)
    veafRadio.addSecuredCommandToSubmenu( "Start CASE I - 90'",   veafCTLD.rootPath, veafCTLD.startRecovery, {case=1, time=90}, veafRadio.USAGE_ForGroup)
    veafRadio.addSecuredCommandToSubmenu( "Start CASE II - 90'",   veafCTLD.rootPath, veafCTLD.startRecovery, {case=2, time=90}, veafRadio.USAGE_ForGroup)
    veafRadio.addSecuredCommandToSubmenu( "Start CASE III - 90'",   veafCTLD.rootPath, veafCTLD.startRecovery, {case=3, time=90}, veafRadio.USAGE_ForGroup)
    veafRadio.addSecuredCommandToSubmenu( "Stop Recovery",   veafCTLD.rootPath, veafCTLD.stopRecovery, nil, veafRadio.USAGE_ForGroup)

    veafRadio.refreshRadioMenu()
end

--- Build the initial radio menu
function veafCTLD.buildRadioMenu()
    veafCTLD.logDebug("veafCTLD.buildRadioMenu")

    veafCTLD.rootPath = veafRadio.addSubMenu(veafCTLD.RadioMenuName)

    veafCTLD.rebuildRadioMenu()
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- initialisation
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veafCTLD.initialize()
    veafCTLD.logInfo("Initializing module")
    veafCTLD.buildDefaultList()
    veafMarkers.registerEventHandler(veafMarkers.MarkerChange, veafCTLD.onEventMarkChange)
end

veafCTLD.logInfo(string.format("Loading version %s", veafCTLD.Version))
