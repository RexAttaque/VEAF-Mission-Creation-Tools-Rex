--------------------------------------------------------------------------------------------------------------------------------------------------------------- VEAF root script library for DCS Workd
-- By zip (2018)
--
-- Features:
-- ---------
-- Contains all the constants and utility functions required by the other VEAF script libraries
--
-- Prerequisite:
-- ------------
-- * This script requires DCS 2.5.1 or higher and MIST 4.3.74 or higher.
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
--     * OPEN --> Browse to the location where you saved the script and click OK.
--
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veaf = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Global settings. Stores the root VEAF constants
-------------------------------------------------------------------------------------------------------------------------------------------------------------

--- Identifier. All output in DCS.log will start with this.
veaf.Id = "VEAF - "
veaf.MainId = "MAIN - "

--- Version.
veaf.Version = "1.10.0"

-- trace level, specific to this module
veaf.MainTrace = false

--- Development version ?
veaf.Development = true
veaf.SecurityDisabled = false

--- Enable logDebug ==> give more output to DCS log file.
veaf.Debug = veaf.Development
--- Enable logTrace ==> give even more output to DCS log file.
veaf.Trace = veaf.Development

veaf.DEFAULT_GROUND_SPEED_KPH = 30
-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Do not change anything below unless you know what you are doing!
-------------------------------------------------------------------------------------------------------------------------------------------------------------

veaf.monitoredFlags = {}
veaf.maxMonitoredFlag = 27000
veaf.config = {}

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utility methods
-------------------------------------------------------------------------------------------------------------------------------------------------------------

function veaf.logError(message)
    log.error(veaf.Id .. message)
end

function veaf.logWarning(message)
    log.warning(veaf.Id ..  message)
end

function veaf.logInfo(message)
    env.info(veaf.Id .."I - " ..  message)
end

function veaf.logDebug(message)
    if veaf.Debug then
        env.info(veaf.Id .."D - " ..  message)
    end
end

function veaf.logTrace(message)
    if veaf.Trace then
        env.info(veaf.Id .."T - " ..  message)
    end
end

function veaf.logMarker(id, header, message, position, markersTable)
    if veaf.Trace then
        local correctedPos = {}
        correctedPos.x = position.x
        if not(position.z) then
            correctedPos.z = position.y
            correctedPos.y = position.alt
        else
            correctedPos.z = position.z
            correctedPos.y = position.y
        end
        if not (correctedPos.y) then
            correctedPos.y = 0
        end
        local message = message
        if header and id then
            message = header..id.." "..message
        end
        veaf.logTrace("creating trace marker #"..id.." at point "..veaf.vecToString(correctedPos))
        trigger.action.markToAll(id, message, correctedPos, false) 
        if markersTable then
            table.insert(markersTable, id)
        end
    end
    return id + 1
end

function veaf.cleanupLogMarkers(markersTable)
    for _, markerId in pairs(markersTable) do
        veaf.logTrace("deleting trace marker #"..markerId)
        trigger.action.removeMark(markerId)    
    end
end

function veaf.mainLogError(message)
    veaf.logError(veaf.MainId .. message)
end

function veaf.mainLogInfo(message)
    veaf.logInfo(veaf.MainId .. message)
end

function veaf.mainLogDebug(message)
    veaf.logDebug(veaf.MainId .. message)
end

function veaf.mainLogTrace(message)
    if message and veaf.MainTrace then
        veaf.logTrace(veaf.MainId .. message)
    end
end

function veaf.mainLogMarker(id, message, position, markersTable)
    if veaf.MainTrace then 
        return veaf.logMarker(id, veaf.Id, message, position, markersTable)
    end
end

--[[ json.lua

Used from https://gist.github.com/tylerneylon/59f4bcf316be525b30ab with authorization

A compact pure-Lua JSON library.
The main functions are: json.stringify, json.parse.
## json.stringify:
This expects the following to be true of any tables being encoded:
 * They only have string or number keys. Number keys must be represented as
   strings in json; this is part of the json spec.
 * They are not recursive. Such a structure cannot be specified in json.
A Lua table is considered to be an array if and only if its set of keys is a
consecutive sequence of positive integers starting at 1. Arrays are encoded like
so: `[2, 3, false, "hi"]`. Any other type of Lua table is encoded as a json
object, encoded like so: `{"key1": 2, "key2": false}`.
Because the Lua nil value cannot be a key, and as a table value is considerd
equivalent to a missing key, there is no way to express the json "null" value in
a Lua table. The only way this will output "null" is if your entire input obj is
nil itself.
An empty Lua table, {}, could be considered either a json object or array -
it's an ambiguous edge case. We choose to treat this as an object as it is the
more general type.
To be clear, none of the above considerations is a limitation of this code.
Rather, it is what we get when we completely observe the json specification for
as arbitrary a Lua object as json is capable of expressing.
## json.parse:
This function parses json, with the exception that it does not pay attention to
\u-escaped unicode code points in strings.
It is difficult for Lua to return null as a value. In order to prevent the loss
of keys with a null value in a json string, this function uses the one-off
table value json.null (which is just an empty table) to indicate null values.
This way you can check if a value is null with the conditional
`val == json.null`.
If you have control over the data and are using Lua, I would recommend just
avoiding null values in your data to begin with.
--]]


json = {}


-- Internal functions.

local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then
      error('Expected ' .. delim .. ' near position ' .. pos)
    end
    return pos, false
  end
  return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'End of input found while parsing string.'
  if pos > #str then error(early_end_error) end
  local c = str:sub(pos, pos)
  if c == '"'  then return val, pos + 1 end
  if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
  -- We must have a \ character.
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then error(early_end_error) end
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then error('Error parsing number at position ' .. pos .. '.') end
  return val, pos + #num_str
end


-- Public values and functions.

function json.stringify(obj, as_key)
  local s = {}  -- We'll build the string as an array of strings to be concatenated.
  local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
  if kind == 'array' then
    if as_key then error('Can\'t encode array as key.') end
    s[#s + 1] = '['
    for i, val in ipairs(obj) do
      if i > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(val)
    end
    s[#s + 1] = ']'
  elseif kind == 'table' then
    if as_key then error('Can\'t encode table as key.') end
    s[#s + 1] = '{'
    for k, v in pairs(obj) do
      if #s > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(k, true)
      s[#s + 1] = ':'
      s[#s + 1] = json.stringify(v)
    end
    s[#s + 1] = '}'
  elseif kind == 'string' then
    return '"' .. escape_str(obj) .. '"'
  elseif kind == 'number' then
    if as_key then return '"' .. tostring(obj) .. '"' end
    return tostring(obj)
  elseif kind == 'boolean' then
    return tostring(obj)
  elseif kind == 'nil' then
    return 'null'
  else
    return '"Unjsonifiable type: ' .. kind .. '."'
    --error('Unjsonifiable type: ' .. kind .. '.')
  end
  return table.concat(s)
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
  pos = pos or 1
  if pos > #str then error('Reached unexpected end of input.') end
  local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
  local first = str:sub(pos, pos)
  if first == '{' then  -- Parse an object.
    local obj, key, delim_found = {}, true, true
    pos = pos + 1
    while true do
      key, pos = json.parse(str, pos, '}')
      if key == nil then return obj, pos end
      if not delim_found then error('Comma missing between object items.') end
      pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
      obj[key], pos = json.parse(str, pos)
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '[' then  -- Parse an array.
    local arr, val, delim_found = {}, true, true
    pos = pos + 1
    while true do
      val, pos = json.parse(str, pos, ']')
      if val == nil then return arr, pos end
      if not delim_found then error('Comma missing between array items.') end
      arr[#arr + 1] = val
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '"' then  -- Parse a string.
    return parse_str_val(str, pos + 1)
  elseif first == '-' or first:match('%d') then  -- Parse a number.
    return parse_num_val(str, pos)
  elseif first == end_delim then  -- End of an object or array.
    return nil, pos + 1
  else  -- Parse true, false, or null.
    local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
    for lit_str, lit_val in pairs(literals) do
      local lit_end = pos + #lit_str - 1
      if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
    end
    local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
    error('Invalid json syntax starting at ' .. pos_info_str)
  end
end

--- efficiently remove elements from a table
--- credit : Mitch McMabers (https://stackoverflow.com/questions/12394841/safely-remove-items-from-an-array-table-while-iterating)
function veaf.arrayRemoveWhen(t, fnKeep)
    local pristine = true    
    local j, n = 1, #t;
    for i=1,n do
        if (fnKeep(t, i, j)) then
            if (i ~= j) then
                -- Keep i's value, move it to j's pos.
                t[j] = t[i];
                t[i] = nil;
            else
                -- Keep i's value, already at j's pos.
            end
            j = j + 1;
        else
            t[i] = nil;
            pristine = false
        end
    end
    return not pristine;
end

function veaf.vecToString(vec)
    local result = ""
    if vec.x then
        result = result .. string.format(" x=%.1f", vec.x)
    end
    if vec.y then
        result = result .. string.format(" y=%.1f", vec.y)
    end
    if vec.z then
        result = result .. string.format(" z=%.1f", vec.z)
    end
    return result
end

function veaf.discoverMetadata(o)
    local text = ""
    for key,value in pairs(getmetatable(o)) do
       text = text .. " - ".. key.."\n";
    end
	return text
end

function veaf.serialize(name, value, level)
    -- mostly based on slMod serializer 
  
    local function _basicSerialize(s)
      if s == nil then
        return "\"\""
      else
        if ((type(s) == 'number') or (type(s) == 'boolean') or (type(s) == 'function') or (type(s) == 'table') or (type(s) == 'userdata') ) then
          return tostring(s)
        elseif type(s) == 'string' then
          return string.format('%q', s)
        end
      end	
    end
  
    -----Based on ED's serialize_simple2
    local basicSerialize = function(o)
        if type(o) == "number" then
            return tostring(o)
        elseif type(o) == "boolean" then
            return tostring(o)
        else -- assume it is a string
            return _basicSerialize(o)
        end
    end
  
    local serialize_to_t = function(name, value, level)
        ----Based on ED's serialize_simple2
  
        local var_str_tbl = {}
        if level == nil then
            level = ""
        end
        if level ~= "" then
            level = level .. "  "
        end
  
        table.insert(var_str_tbl, level .. name .. " = ")
  
        if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
            table.insert(var_str_tbl, basicSerialize(value) .. ",\n")
        elseif type(value) == "table" then
            table.insert(var_str_tbl, "{\n")
            local tkeys = {}
            -- populate the table that holds the keys
            for k in pairs(value) do table.insert(tkeys, k) end
            -- sort the keys
            table.sort(tkeys, _sortNumberOrCaseInsensitive)
            -- use the keys to retrieve the values in the sorted order
            for _, k in ipairs(tkeys) do  -- serialize its fields
              local v = value[k]
                local key
                if type(k) == "number" then
                    key = string.format("[%s]", k)
                else
                    key = string.format("[%q]", k)
                end
  
                table.insert(var_str_tbl, veaf.serialize(key, v, level .. "  "))
            end
            if level == "" then
                table.insert(var_str_tbl, level .. "} -- end of " .. name .. "\n")
            else
                table.insert(var_str_tbl, level .. "}, -- end of " .. name .. "\n")
            end
        else
            veaf.mainLogError("Cannot serialize a " .. type(value))
        end
        return var_str_tbl
    end
  
    local t_str = serialize_to_t(name, value, level)
  
    return table.concat(t_str)
  end
  
function veaf.p(o, level)
    local MAX_LEVEL = 20
    if level == nil then level = 0 end
    if level > MAX_LEVEL then 
        veaf.mainLogError("max depth reached in veaf.p : "..tostring(MAX_LEVEL))
        return ""
    end
      local text = ""
      if (type(o) == "table") then
          text = "\n"
          for key,value in pairs(o) do
              for i=0, level do
                  text = text .. " "
              end
              text = text .. ".".. key.."="..veaf.p(value, level+1) .. "\n";
          end
      elseif (type(o) == "function") then
          text = "[function]";
      elseif (type(o) == "boolean") then
          if o == true then 
              text = "[true]";
          else
              text = "[false]";
          end
      else
          if o == nil then
              text = "[nil]";    
          else
              text = tostring(o);
          end
      end
      return text
  end

--- Simple round
function veaf.round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

--- shuffle a table elements around
function veaf.shuffle(tbl)
    for i = #tbl, 2, -1 do
      local j = math.random(i)
      tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

--- Return the height of the land at the coordinate.
function veaf.getLandHeight(vec3)
    veaf.mainLogTrace(string.format("getLandHeight: vec3  x=%.1f y=%.1f, z=%.1f", vec3.x, vec3.y, vec3.z))
    local vec2 = {x = vec3.x, y = vec3.z}
    veaf.mainLogTrace(string.format("getLandHeight: vec2  x=%.1f z=%.1f", vec3.x, vec3.z))
    -- We add 1 m "safety margin" because data from getlandheight gives the surface and wind at or below the surface is zero!
    local height = math.floor(land.getHeight(vec2) + 1)
    veaf.mainLogTrace(string.format("getLandHeight: result  height=%.1f",height))
    return height
end

--- Return a point at the same coordinates, but on the surface
function veaf.placePointOnLand(vec3)
    -- convert a vec2 to a vec3
    if not vec3.z then
        vec3.z = vec3.y 
        vec3.y = 0
    end
    
    if not vec3.y then
        vec3.y = 0
    end
    
    veaf.mainLogTrace(string.format("getLandHeight: vec3  x=%.1f y=%.1f, z=%.1f", vec3.x, vec3.y, vec3.z))
    local height = veaf.getLandHeight(vec3)
    veaf.mainLogTrace(string.format("getLandHeight: result  height=%.1f",height))
    local result={x=vec3.x, y=height, z=vec3.z}
    veaf.mainLogTrace(string.format("placePointOnLand: result  x=%.1f y=%.1f, z=%.1f", result.x, result.y, result.z))
    return result
end

--- Trim a string
function veaf.trim(s)
    local a = s:match('^%s*()')
    local b = s:match('()%s*$', a)
    return s:sub(a,b-1)
end

--- Split string. C.f. http://stackoverflow.com/questions/1426954/split-string-in-lua
function veaf.split(str, sep)
    local result = {}
    local regex = ("([^%s]+)"):format(sep)
    for each in str:gmatch(regex) do
        table.insert(result, each)
    end
    return result
end

--- Break string around a separator
function veaf.breakString(str, sep)
    local regex = ("^([^%s]+)%s(.*)$"):format(sep, sep)
    local a, b = str:match(regex)
    if not a then a = str end
    local result = {a, b}
    return result
end

--- Get the average center of a group position (average point of all units position)
function veaf.getAveragePosition(group)
    if type(group) == "string" then 
        group = Group.getByName(group)
    end

    local count

	local totalPosition = {x = 0,y = 0,z = 0}
	if group then
		local units = Group.getUnits(group)
		for count = 1,#units do
			if units[count] then 
				totalPosition = mist.vec.add(totalPosition,Unit.getPosition(units[count]).p)
			end
		end
		if #units > 0 then
			return mist.vec.scalar_mult(totalPosition,1/#units)
		else
			return nil
		end
	else
		return nil
	end
end

function veaf.emptyFunction()
end

--- Returns the wind direction (from) and strength.
function veaf.getWind(point)

    -- Get wind velocity vector.
    local windvec3  = atmosphere.getWind(point)
    local direction = math.floor(math.deg(math.atan2(windvec3.z, windvec3.x)))
    
    if direction < 0 then
      direction = direction + 360
    end
    
    -- Convert TO direction to FROM direction. 
    if direction > 180 then
      direction = direction-180
    else
      direction = direction+180
    end
    
    -- Calc 2D strength.
    local strength=math.floor(math.sqrt((windvec3.x)^2+(windvec3.z)^2))
    
    -- Debug output.
    veaf.mainLogTrace(string.format("Wind data: point x=%.1f y=%.1f, z=%.1f", point.x, point.y,point.z))
    veaf.mainLogTrace(string.format("Wind data: wind  x=%.1f y=%.1f, z=%.1f", windvec3.x, windvec3.y,windvec3.z))
    veaf.mainLogTrace(string.format("Wind data: |v| = %.1f", strength))
    veaf.mainLogTrace(string.format("Wind data: ang = %.1f", direction))
    
    -- Return wind direction and strength (in m/s).
    return direction, strength, windvec3
  end

--- Find a suitable point for spawning a unit in a <dispersion>-sized circle around a spot
function veaf.findPointInZone(spawnSpot, dispersion, isShip)
    local unitPosition
    local tryCounter = 1000
    
    repeat -- Place the unit in a "dispersion" ft radius circle from the spawn spot
        unitPosition = mist.getRandPointInCircle(spawnSpot, dispersion)
        local landType = land.getSurfaceType(unitPosition)
        tryCounter = tryCounter - 1
    until ((isShip and landType == land.SurfaceType.WATER) or (not(isShip) and (landType == land.SurfaceType.LAND or landType == land.SurfaceType.ROAD or landType == land.SurfaceType.RUNWAY))) or tryCounter == 0
    if tryCounter == 0 then
        return nil
    else
        return unitPosition
    end
end

--- TODO doc
function veaf.generateVehiclesRoute(startPoint, destination, onRoad, speed, patrol)
    veaf.mainLogTrace(string.format("veaf.generateVehiclesRoute(onRoad=[%s], speed=[%s], patrol=[%s])", tostring(onRoad or ""), tostring(speed or ""), tostring(patrol or "")))

    speed = speed or veaf.DEFAULT_GROUND_SPEED_KPH
    onRoad = onRoad or false
    patrol = patrol or false
    veaf.mainLogTrace(string.format("startPoint = {x = %d, y = %d, z = %d}", startPoint.x, startPoint.y, startPoint.z))
    local action = "Diamond"
    if onRoad then
        action = "On Road"
    end

    local endPoint = veafNamedPoints.getPoint(destination)
    if not(endPoint) then
        trigger.action.outText("A point named "..destination.." cannot be found !", 5)
        return
    end
    veaf.mainLogTrace(string.format("endPoint = {x = %d, y = %d, z = %d}", endPoint.x, endPoint.y, endPoint.z))

    if onRoad then
        veaf.mainLogTrace("setting startPoint on a road")
        local road_x, road_z = land.getClosestPointOnRoads('roads',startPoint.x, startPoint.z)
        startPoint = veaf.placePointOnLand({x = road_x, y = 0, z = road_z})
    else
        startPoint = veaf.placePointOnLand({x = startPoint.x, y = 0, z = startPoint.z})
    end
    
    veaf.mainLogTrace(string.format("startPoint = {x = %d, y = %d, z = %d}", startPoint.x, startPoint.y, startPoint.z))

    if onRoad then
        veaf.mainLogTrace("setting endPoint on a road")
        road_x, road_z =land.getClosestPointOnRoads('roads',endPoint.x, endPoint.z)
        endPoint = veaf.placePointOnLand({x = road_x, y = 0, z = road_z})
    else
        endPoint = veaf.placePointOnLand({x = endPoint.x, y = 0, z = endPoint.z})
    end
    veaf.mainLogTrace(string.format("endPoint = {x = %d, y = %d, z = %d}", endPoint.x, endPoint.y, endPoint.z))
    
    local vehiclesRoute = {
        [1] = 
        {
            ["x"] = startPoint.x,
            ["y"] = startPoint.z,
            ["alt"] = startPoint.y,
            ["type"] = "Turning Point",
            ["ETA"] = 0,
            ["alt_type"] = "BARO",
            ["formation_template"] = "",
            ["name"] = "STA",
            ["ETA_locked"] = true,
            ["speed"] = speed / 3.6,
            ["action"] = action,
            ["task"] = 
            {
                ["id"] = "ComboTask",
                ["params"] = 
                {
                    ["tasks"] = 
                    {
                    }, -- end of ["tasks"]
                }, -- end of ["params"]
            }, -- end of ["task"]
            ["speed_locked"] = true,
        }, -- end of [1]
        [2] = 
        {
            ["x"] = endPoint.x,
            ["y"] = endPoint.z,
            ["alt"] = endPoint.y,
            ["type"] = "Turning Point",
            ["ETA"] = 0,
            ["alt_type"] = "BARO",
            ["formation_template"] = "",
            ["name"] = "END",
            ["ETA_locked"] = false,
            ["speed"] = speed / 3.6,
            ["action"] = action,
            ["speed_locked"] = true,
        }, -- end of [2]
    }

    if patrol then
        vehiclesRoute[3] = 
        {
            ["x"] = startPoint.x,
            ["y"] = startPoint.z,
            ["alt"] = startPoint.y,
            ["type"] = "Turning Point",
            ["ETA"] = 0,
            ["alt_type"] = "BARO",
            ["formation_template"] = "",
            ["name"] = "STA",
            ["ETA_locked"] = true,
            ["speed"] = speed / 3.6,
            ["action"] = action,
            ["task"] = 
            {
                ["id"] = "ComboTask",
                ["params"] = 
                {
                    ["tasks"] = 
                    {
                        [1] = 
                        {
                            ["enabled"] = true,
                            ["auto"] = false,
                            ["id"] = "GoToWaypoint",
                            ["number"] = 1,
                            ["params"] = 
                            {
                                ["fromWaypointIndex"] = 3,
                                ["nWaypointIndx"] = 1,
                            }, -- end of ["params"]
                        }, -- end of [1]
                    }, -- end of ["tasks"]
                }, -- end of ["params"]
            }, -- end of ["task"]
            ["speed_locked"] = true,
        }
    end
    veaf.mainLogTrace(string.format("vehiclesRoute = %s", veaf.p(vehiclesRoute)))

    return vehiclesRoute
end


--- Add a unit to the <group> on a suitable point in a <dispersion>-sized circle around a spot
function veaf.addUnit(group, spawnSpot, dispersion, unitType, unitName, skill)
    local unitPosition = veaf.findPointInZone(spawnSpot, dispersion, false)
    if unitPosition ~= nil then
        table.insert(
            group,
            {
                ["x"] = unitPosition.x,
                ["y"] = unitPosition.y,
                ["type"] = unitType,
                ["name"] = unitName,
                ["heading"] = 0,
                ["skill"] = skill
            }
        )
    else
        veaf.mainLogInfo("cannot find a suitable position for unit "..unitType)
    end
end

--- Makes a group move to a waypoint set at a specific heading and at a distance covered at a specific speed in an hour
function veaf.moveGroupAt(groupName, leadUnitName, heading, speed, timeInSeconds, endPosition, pMiddlePointDistance)
    veaf.mainLogDebug("veaf.moveGroupAt(groupName=" .. groupName .. ", heading="..heading.. ", speed=".. speed..", timeInSeconds="..(timeInSeconds or 0))

    local unitGroup = Group.getByName(groupName)
    if unitGroup == nil then
        veaf.mainLogError("veaf.moveGroupAt: " .. groupName .. ' not found')
		return false
    end
    
    local leadUnit = unitGroup:getUnits()[1]
    if leadUnitName then
        leadUnit = Unit.getByName(leadUnitName)
    end
    if leadUnit == nil then
        veaf.mainLogError("veaf.moveGroupAt: " .. leadUnitName .. ' not found')
		return false
    end
    
    local headingRad = mist.utils.toRadian(heading)
    veaf.mainLogTrace("headingRad="..headingRad)
    local fromPosition = leadUnit:getPosition().p
    fromPosition = { x = fromPosition.x, y = fromPosition.z }
    veaf.mainLogTrace("fromPosition="..veaf.vecToString(fromPosition))

    local mission = { 
		id = 'Mission', 
		params = { 
			["communication"] = true,
			["start_time"] = 0,
			route = { 
				points = { 
					-- first point
                    [1] = 
                    {
                        --["alt"] = 0,
                        ["type"] = "Turning Point",
                        --["formation_template"] = "Diamond",
                        --["alt_type"] = "BARO",
                        ["x"] = fromPosition.x,
                        ["y"] = fromPosition.z,
                        ["name"] = "Starting position",
                        ["action"] = "Turning Point",
                        ["speed"] = 9999, -- ahead flank
                        ["speed_locked"] = true,
                    }, -- end of [1]
				}, 
			} 
		} 
	}

    if pMiddlePointDistance then
        -- middle point (helps with having a more exact final bearing, specially with big hunks of steel like carriers)
        local middlePointDistance = 2000
        if pMiddlePointDistance then
            middlePointDistance = pMiddlePointDistance
        end

        local newWaypoint1 = {
            x = fromPosition.x + middlePointDistance * math.cos(headingRad),
            y = fromPosition.y + middlePointDistance * math.sin(headingRad),
        }
        fromPosition.x = newWaypoint1.x
        fromPosition.y = newWaypoint1.y
        veaf.mainLogTrace("newWaypoint1="..veaf.vecToString(newWaypoint1))

        table.insert(mission.params.route.points, 
            {
                --["alt"] = 0,
                ["type"] = "Turning Point",
                --["formation_template"] = "Diamond",
                --["alt_type"] = "BARO",
                ["x"] = newWaypoint1.x,
                ["y"] = newWaypoint1.y,
                ["name"] = "Middle point",
                ["action"] = "Turning Point",
                ["speed"] = 9999, -- ahead flank
                ["speed_locked"] = true,
            }
        )
    end

    local length
    if timeInSeconds then 
        length = speed * timeInSeconds
    else
        length = speed * 3600 -- m travelled in 1 hour
    end
    veaf.mainLogTrace("length="..length .. " m")

    -- new route point
	local newWaypoint2 = {
		x = fromPosition.x + length * math.cos(headingRad),
		y = fromPosition.y + length * math.sin(headingRad),
	}
    veaf.mainLogTrace("newWaypoint2="..veaf.vecToString(newWaypoint2))

    table.insert(mission.params.route.points, 
        {
            --["alt"] = 0,
            ["type"] = "Turning Point",
            --["formation_template"] = "Diamond",
            --["alt_type"] = "BARO",
            ["x"] = newWaypoint2.x,
            ["y"] = newWaypoint2.y,
            ["name"] = "",
            ["action"] = "Turning Point",
            ["speed"] = speed,
            ["speed_locked"] = true,
        }
    )

    if endPosition then
        table.insert(mission.params.route.points, 
            {
                --["alt"] = 0,
                ["type"] = "Turning Point",
                --["formation_template"] = "Diamond",
                --["alt_type"] = "BARO",
                ["x"] = endPosition.x,
                ["y"] = endPosition.z,
                ["name"] = "Back to starting position",
                ["action"] = "Turning Point",
                ["speed"] = 9999, -- ahead flank
                ["speed_locked"] = true,
            }
        )
    end

	-- replace whole mission
	unitGroup:getController():setTask(mission)
    
    return true
end

function veaf.readyForCombat(group)
    if type(group) == 'string' then
        group = Group.getByName(group)
    end
    if group then
        local cont = group:getController()
        cont:setOnOff(true)
        cont:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)	
        cont:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)
    end
end

-- Makes a group move to a specific waypoint at a specific speed
function veaf.moveGroupTo(groupName, pos, speed, altitude)
    if not(altitude) then
        altitude = 0
    end
    veaf.mainLogDebug("veaf.moveGroupTo(groupName=" .. groupName .. ", speed=".. speed .. ", altitude=".. altitude)
    veaf.mainLogDebug("pos="..veaf.vecToString(pos))

	local unitGroup = Group.getByName(groupName)
    if unitGroup == nil then
        veaf.mainLogError("veaf.moveGroupTo: " .. groupName .. ' not found')
		return false
    end
    
    local route = {
        [1] =
        {
            ["alt"] = altitude,
            ["action"] = "Turning Point",
            ["alt_type"] = "BARO",
            ["speed"] = veaf.round(speed, 2),
            ["type"] = "Turning Point",
            ["x"] = pos.x,
            ["y"] = pos.z,
            ["speed_locked"] = true,
        },
        [2] = 
        {
            ["alt"] = altitude,
            ["action"] = "Turning Point",
            ["alt_type"] = "BARO",
            ["speed"] = 0,
            ["type"] = "Turning Point",
            ["x"] = pos.x,
            ["y"] = pos.z,
            ["speed_locked"] = true,
        },
    }

    -- order group to new waypoint
	mist.goRoute(groupName, route)

    return true
end

function veaf.getAvgGroupPos(groupName) -- stolen from Mist and corrected
	local group = groupName -- sometimes this parameter is actually a group
	if type(groupName) == 'string' and Group.getByName(groupName) and Group.getByName(groupName):isExist() == true then
		group = Group.getByName(groupName)
	end
	local units = {}
	for i = 1, group:getSize() do
		table.insert(units, group:getUnit(i):getName())
	end

	return mist.getAvgPos(units)
end

--- Computes the coordinates of a point offset from a route of a certain distance, at a certain distance from route start
--- e.g. we go from [startingPoint] to [destinationPoint], and at [distanceFromStartingPoint] we look at [offset] meters (left if <0, right else)
function veaf.computeCoordinatesOffsetFromRoute(startingPoint, destinationPoint, distanceFromStartingPoint, offset)
    veaf.mainLogTrace("startingPoint="..veaf.vecToString(startingPoint))
    veaf.mainLogTrace("destinationPoint="..veaf.vecToString(destinationPoint))
    
    local vecAB = {x = destinationPoint.x +- startingPoint.x, y = destinationPoint.y - startingPoint.y, z = destinationPoint.z - startingPoint.z}
    veaf.mainLogTrace("vecAB="..veaf.vecToString(vecAB))
    local alpha = math.atan2(vecAB.x, vecAB.z) -- atan2(y, x) 
    veaf.mainLogTrace("alpha="..alpha)
    local r = math.sqrt(distanceFromStartingPoint * distanceFromStartingPoint + offset * offset)
    veaf.mainLogTrace("r="..r)
    local beta = math.atan(offset / distanceFromStartingPoint)
    veaf.mainLogTrace("beta="..beta)
    local tho = alpha + beta
    veaf.mainLogTrace("tho="..tho)
    local offsetPoint = { z = r * math.cos(tho) + startingPoint.z, y = 0, x = r * math.sin(tho) + startingPoint.x}
    veaf.mainLogTrace("offsetPoint="..veaf.vecToString(offsetPoint))
    local offsetPointOnLand = veaf.placePointOnLand(offsetPoint)
    veaf.mainLogTrace("offsetPointOnLand="..veaf.vecToString(offsetPointOnLand))

    return offsetPointOnLand, offsetPoint
end

function veaf.getBearingAndRangeFromTo(fromPoint, toPoint)
    veaf.mainLogTrace("fromPoint="..veaf.vecToString(fromPoint))
    veaf.mainLogTrace("toPoint="..veaf.vecToString(toPoint))
    
    local vec = { z = toPoint.z - fromPoint.z, x = toPoint.x - fromPoint.x}
    local angle = mist.utils.round(mist.utils.toDegree(mist.utils.getDir(vec)), 0)
    local distance = mist.utils.get2DDist(toPoint, fromPoint)
    return angle, distance, mist.utils.round(distance / 1000, 0), mist.utils.round(mist.utils.metersToNM(distance), 0)
end

function veaf.getGroupsOfCoalition(coa)
    local coalitions = { coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL}
    if coa then 
        coalitions = { coa } 
    end
    local allDcsGroups = {}
    for _, coa in pairs(coalitions) do
        local dcsGroups = coalition.getGroups(coa)
        for _, dcsGroup in pairs(dcsGroups) do
            table.insert(allDcsGroups, dcsGroup)
        end
    end
    return allDcsGroups
end

function veaf.getStaticsOfCoalition(coa)
    local coalitions = { coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL}
    if coa then 
        coalitions = { coa } 
    end
    local allDcsStatics = {}
    for _, coa in pairs(coalitions) do
        local dcsStatics = coalition.getStaticObjects(coa)
        for _, dcsStatic in pairs(dcsStatics) do
            table.insert(allDcsStatics, dcsStatic)
        end
    end
    return allDcsStatics
end

function veaf.getUnitsOfAllCoalitions(includeStatics)
    return veaf.getUnitsOfCoalition(includeStatics)
end

function veaf.getUnitsOfCoalition(includeStatics, coa)
    local allDcsUnits = {}
    local allDcsGroups = veaf.getGroupsOfCoalition(coa)
    for _, group in pairs(allDcsGroups) do
        for _, unit in pairs(group:getUnits()) do
            table.insert(allDcsUnits, unit)
        end
    end
    if includeStatics then
        local allDcsStatics = veaf.getStaticsOfCoalition(coa)
        for _, staticUnit in pairs(allDcsStatics) do
            table.insert(allDcsUnits, staticUnit)
        end
    end
    return allDcsUnits
end

function veaf.findUnitsInCircle(center, radius, includeStatics)
    veaf.mainLogTrace(string.format("findUnitsInCircle(radius=%s)", tostring(radius)))
    veaf.mainLogTrace(string.format("center=%s", veaf.p(center)))


    local allDcsUnits = veaf.getUnitsOfAllCoalitions(includeStatics)
    
    local result = {}
    for _, unit in pairs(allDcsUnits) do
        local pos = unit:getPosition().p
        if pos then -- you never know O.o
            local name = unit:getName()
            distanceFromCenter = ((pos.x - center.x)^2 + (pos.z - center.z)^2)^0.5
            veaf.mainLogTrace(string.format("name=%s; distanceFromCenter=%s", tostring(name), veaf.p(distanceFromCenter)))
            if distanceFromCenter <= radius then
                result[name] = unit
            end
        end
    end
    return result
end

--- modified version of mist.getGroupRoute that returns raw DCS group data
function veaf.getGroupData(groupIdent)
    -- refactor to search by groupId and allow groupId and groupName as inputs
    local gpId = groupIdent
        if mist.DBs.MEgroupsByName[groupIdent] then
            gpId = mist.DBs.MEgroupsByName[groupIdent].groupId
        else
            veaf.mainLogInfo(groupIdent..' not found in mist.DBs.MEgroupsByName')
        end

    for coa_name, coa_data in pairs(env.mission.coalition) do
        if (coa_name == 'red' or coa_name == 'blue') and type(coa_data) == 'table' then
            if coa_data.country then --there is a country table
                for cntry_id, cntry_data in pairs(coa_data.country) do
                    for obj_type_name, obj_type_data in pairs(cntry_data) do
                        if obj_type_name == "helicopter" or obj_type_name == "ship" or obj_type_name == "plane" or obj_type_name == "vehicle" then	-- only these types have points
                            if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then	--there's a group!
                                for group_num, group_data in pairs(obj_type_data.group) do
                                    if group_data and group_data.groupId == gpId	then -- this is the group we are looking for
                                        return group_data
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    veaf.mainLogInfo(' no group data found for '..groupIdent)
    return nil
end

function veaf.findInTable(data, key)
    local result = nil
    if data then
        result = data[key]
    end
    if result then 
        veaf.mainLogTrace(".findInTable found ".. key)
    end
    return result
end

function veaf.getTankerData(tankerGroupName)
    veaf.mainLogTrace("getTankerData " .. tankerGroupName)
    local result = nil
    local tankerData = veaf.getGroupData(tankerGroupName)
    if tankerData then
        result = {}
        -- find callsign
        local units = veaf.findInTable(tankerData, "units")
        if units and units[1] then 
            local callsign = veaf.findInTable(units[1], "callsign")
            if callsign then 
                local name = veaf.findInTable(callsign, "name")
                if name then 
                    result.tankerCallsign = name
                end
            end
        end

        -- find frequency
        local communication = veaf.findInTable(tankerData, "communication")
        if communication == true then
            local frequency = veaf.findInTable(tankerData, "frequency")
            if frequency then 
                result.tankerFrequency = frequency
            end
        end
        local route = veaf.findInTable(tankerData, "route")
        local points = veaf.findInTable(route, "points")
        if points then
            veaf.mainLogTrace("found a " .. #points .. "-points route for tanker " .. tankerGroupName)
            for i, point in pairs(points) do
                veaf.mainLogTrace("found point #" .. i)
                local task = veaf.findInTable(point, "task")
                if task then
                    local tasks = task.params.tasks
                    if (tasks) then
                        veaf.mainLogTrace("found " .. #tasks .. " tasks")
                        for j, task in pairs(tasks) do
                            veaf.mainLogTrace("found task #" .. j)
                            if task.params then
                                veaf.mainLogTrace("has .params")
                                if task.params.action then
                                    veaf.mainLogTrace("has .action")
                                    if task.params.action.params then
                                        veaf.mainLogTrace("has .params")
                                        if task.params.action.params.channel then
                                            veaf.mainLogTrace("has .channel")
                                            veaf.mainLogInfo("Found a TACAN task for tanker " .. tankerGroupName)
                                            result.tankerTacanTask = task
                                            result.tankerTacanChannel = task.params.action.params.channel
                                            result.tankerTacanMode = task.params.action.params.modeChannel
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

function veaf.outTextForUnit(unitName, message, duration)
    local groupId = nil
    if unitName then
    local unit = Unit.getByName(unitName)
    if unit then 
        local group = unit:getGroup()
        if group then 
            groupId = group:getID()
        end
    end
    end
    if groupId then 
        trigger.action.outTextForGroup(groupId, message, duration)
    else
        trigger.action.outText(message, duration)
    end
end

--- Weather Report. Report pressure QFE/QNH, temperature, wind at certain location.
--- stolen from the weatherReport script and modified to fit our usage
function veaf.weatherReport(vec3, alt, withLASTE)
     
    -- Get Temperature [K] and Pressure [Pa] at vec3.
    local T
    local Pqfe
    if not alt then
        alt = veaf.getLandHeight(vec3)
    end

    -- At user specified altitude.
    T,Pqfe=atmosphere.getTemperatureAndPressure({x=vec3.x, y=alt, z=vec3.z})
    veaf.mainLogTrace(string.format("T = %.1f, Pqfe = %.2f", T,Pqfe))
    
    -- Get pressure at sea level.
    local _,Pqnh=atmosphere.getTemperatureAndPressure({x=vec3.x, y=0, z=vec3.z})
    veaf.mainLogTrace(string.format("Pqnh = %.2f", Pqnh))
    
    -- Convert pressure from Pascal to hecto Pascal.
    Pqfe=Pqfe/100
    Pqnh=Pqnh/100 
     
    -- Pressure unit conversion hPa --> mmHg or inHg
    local _Pqnh=string.format("%.2f mmHg (%.2f inHg)", Pqnh * weathermark.hPa2mmHg, Pqnh * weathermark.hPa2inHg)
    local _Pqfe=string.format("%.2f mmHg (%.2f inHg)", Pqfe * weathermark.hPa2mmHg, Pqfe * weathermark.hPa2inHg)
   
    -- Temperature unit conversion: Kelvin to Celsius or Fahrenheit.
    T=T-273.15
    local _T=string.format('%d°C (%d°F)', T, weathermark._CelsiusToFahrenheit(T))
  
    -- Get wind direction and speed.
    local Dir,Vel=weathermark._GetWind(vec3, alt)
    veaf.mainLogTrace(string.format("Dir = %.1f, Vel = %.1f", Dir,Vel))

    -- Get Beaufort wind scale.
    local Bn,Bd=weathermark._BeaufortScale(Vel)
    
    -- Formatted wind direction.
    local Ds = string.format('%03d°', Dir)
      
    -- Velocity in player units.
    local Vs=string.format('%.1f m/s (%.1f kn)', Vel, Vel * weathermark.mps2knots) 
    
    -- Altitude.
    local _Alt=string.format("%d m (%d ft)", alt, alt * weathermark.meter2feet)
      
    local text="" 
    text=text..string.format("Altitude %s ASL\n",_Alt)
    text=text..string.format("QFE %.2f hPa = %s\n", Pqfe,_Pqfe)
    text=text..string.format("QNH %.2f hPa = %s\n", Pqnh,_Pqnh)
    text=text..string.format("Temperature %s\n",_T)
    if Vel > 0 then
        text=text..string.format("Wind from %s at %s (%s)", Ds, Vs, Bd)
    else
        text=text.."No wind"
    end

    local function getLASTEat(vec3, alt)
        local T,_=atmosphere.getTemperatureAndPressure({x=vec3.x, y=alt, z=vec3.z})
        local Dir,Vel=weathermark._GetWind(vec3, alt)
        local laste = string.format("\nFL%02d W%03d/%02d T%d", alt * weathermark.meter2feet / 1000, Dir, Vel * weathermark.mps2knots, T-273.15)
        return laste
    end

    if withLASTE then
        text=text.."\n\nLASTE:"
        text=text..getLASTEat(vec3, math.floor(((alt * weathermark.meter2feet + 2000)/1000)*1000+500)/weathermark.meter2feet)
        text=text..getLASTEat(vec3, math.floor(((alt * weathermark.meter2feet + 8000)/1000)*1000+500)/weathermark.meter2feet)
        text=text..getLASTEat(vec3, math.floor(((alt * weathermark.meter2feet + 16000)/1000)*1000+500)/weathermark.meter2feet)
        --text=text..getLASTEat(vec3, _Alt + 7500)
    end

    return text
end

local function _initializeCountriesAndCoalitions()
    veaf.countriesByCoalition={}
    veaf.coalitionByCountry={}

    local function _sortByImportance(c1,c2)
        local importantCountries = { ['usa']=true, ['russia']=true}
        if c1 then
            return importantCountries[c1:lower()]
        end
        return string.lower(c1) < string.lower(c2)
    end

    for coalitionName, countries in pairs(mist.DBs.units) do
        coalitionName = coalitionName:lower()
        veaf.mainLogTrace(string.format("coalitionName=%s", veaf.p(coalitionName)))

        if not veaf.countriesByCoalition[coalitionName] then 
            veaf.countriesByCoalition[coalitionName]={} 
        end
        for countryName, _ in pairs(countries) do
            countryName = countryName:lower()
            table.insert(veaf.countriesByCoalition[coalitionName], countryName)
            veaf.coalitionByCountry[countryName]=coalitionName:lower()
        end

        table.sort(veaf.countriesByCoalition[coalitionName], _sortByImportance)
    end

    veaf.mainLogTrace(string.format("veaf.countriesByCoalition=%s", veaf.p(veaf.countriesByCoalition)))
    veaf.mainLogTrace(string.format("veaf.coalitionByCountry=%s", veaf.p(veaf.coalitionByCountry)))
end

function veaf.getCountryForCoalition(coalition)
    veaf.mainLogTrace(string.format("veaf.getCountryForCoalition(coalition=%s)", tostring(coalition)))
    local coalition = coalition
    if not coalition then 
        coalition = 1 
    end

    local coalitionName = nil
    if type(coalition) == "number" then
        if coalition == 1 then 
            coalitionName = "red" 
        elseif coalition == 2 then 
            coalitionName = "blue" 
        else
            coalitionName = "neutral" 
        end
    else
        coalitionName = tostring(coalition)
    end

    if coalitionName then
        coalitionName = coalitionName:lower()
    else
        return nil
    end

    if not veaf.countriesByCoalition then 
        _initializeCountriesAndCoalitions() 
    end
    
    return veaf.countriesByCoalition[coalitionName][1]
end

function veaf.getCoalitionForCountry(countryName, asNumber)
    veaf.mainLogTrace(string.format("veaf.getCoalitionForCountry(countryName=%s, asNumber=%s)", tostring(countryName), tostring(asNumber)))

    if countryName then
        countryName = countryName:lower()
    else
        return nil
    end

    if not veaf.coalitionByCountry then 
        _initializeCountriesAndCoalitions() 
    end
    
    local result = veaf.coalitionByCountry[countryName]
    if asNumber then
        if result == 'neutral' then result = 0 end
        if result == 'red' then result = 1 end
        if result == 'blue' then result = 2 end
    end
    return result
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- mission restart at a certain hour of the day
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function veaf._endMission(delay1, message1, delay2, message2, delay3, message3)
    veaf.mainLogTrace(string.format("veaf._endMission(delay1=%s, message1=%s, delay2=%s, message2=%s, delay3=%s, message3=%s)", veaf.p(delay1), veaf.p(message1), veaf.p(delay2), veaf.p(message2), veaf.p(delay3), veaf.p(message3)))

    if not delay1 then
        -- no more delay, let's end this !
        trigger.action.outText("Ending mission !",30)
        veaf.mainLogInfo("ending mission")
        trigger.action.setUserFlag("666", 1)
    else 
        -- show the message
        trigger.action.outText(message1,30)
        -- schedule this function after "delay1" seconds
        veaf.mainLogInfo(string.format("schedule veaf._endMission after %d seconds", delay1))
        mist.scheduleFunction(veaf._endMission, {delay2, message2, delay3, message3}, timer.getTime()+delay1)
    end
end

function veaf._checkForEndMission(endTimeInSeconds, checkIntervalInSeconds, checkMessage, delay1, message1, delay2, message2, delay3, message3)
    veaf.mainLogTrace(string.format("veaf._checkForEndMission(endTimeInSeconds=%s, checkIntervalInSeconds=%s, checkMessage=%s, delay1=%s, message1=%s, delay2=%s, message2=%s, delay3=%s, message3=%s)", veaf.p(endTimeInSeconds), veaf.p(checkIntervalInSeconds), veaf.p(checkMessage), veaf.p(delay1), veaf.p(message1), veaf.p(delay2), veaf.p(message2), veaf.p(delay3), veaf.p(message3)))
    
    veaf.mainLogTrace(string.format("timer.getAbsTime()=%d", timer.getAbsTime()))

    if timer.getAbsTime() >= endTimeInSeconds then
        veaf.mainLogTrace("calling veaf._endMission")
        veaf._endMission(delay1, message1, delay2, message2, delay3, message3)
    else
        -- output the message if specified
        if checkMessage then
            trigger.action.outText(checkMessage,30)
        end
        -- schedule this function after a delay
        veaf.mainLogTrace(string.format("schedule veaf._checkForEndMission after %d seconds", checkIntervalInSeconds))
        mist.scheduleFunction(veaf._checkForEndMission, {endTimeInSeconds, checkIntervalInSeconds, checkMessage, delay1, message1, delay2, message2, delay3, message3}, timer.getTime()+checkIntervalInSeconds)
    end
end

function veaf.endMissionAt(endTimeHour, endTimeMinute, checkIntervalInSeconds, checkMessage, delay1, message1, delay2, message2, delay3, message3)
    veaf.mainLogTrace(string.format("veaf.endMissionAt(endTimeHour=%s, endTimeMinute=%s, checkIntervalInSeconds=%s, checkMessage=%s, delay1=%s, message1=%s, delay2=%s, message2=%s, delay3=%s, message3=%s)", veaf.p(endTimeHour), veaf.p(endTimeMinute), veaf.p(checkIntervalInSeconds), veaf.p(checkMessage), veaf.p(delay1), veaf.p(message1), veaf.p(delay2), veaf.p(message2), veaf.p(delay3), veaf.p(message3)))

    local endTimeInSeconds = endTimeHour * 3600 + endTimeMinute * 60
    veaf.mainLogTrace(string.format("endTimeInSeconds=%d", endTimeInSeconds))
    veaf._checkForEndMission(endTimeInSeconds, checkIntervalInSeconds, checkMessage, delay1, message1, delay2, message2, delay3, message3)    
end

function veaf.randomlyChooseFrom(aTable, bias)
    veaf.mainLogTrace(string.format("randomlyChooseFrom(%d):%s",bias or 0, veaf.p(aTable)))
    local index = math.floor(math.random(1, #aTable)) + (bias or 0)
    if index < 1 then index = 1 end
    if index > #aTable then index = #aTable end
    return aTable[index]
end

function veaf.safeUnpack(package)
    if type(package) == 'table' then
        return unpack(package)
    else
        return package
    end
end

function veaf.getRandomizableNumeric_random(val)
    veaf.mainLogTrace(string.format("getRandomizableNumeric_random(%s)", tostring(val)))
    local nVal = tonumber(val)
    veaf.mainLogTrace(string.format("nVal=%s", tostring(nVal)))
    if nVal == nil then 
        --[[
        local dashPos = nil
        for i = 1, #val do
            local c = val:sub(i,i)
            if c == '-' then 
                dashPos = i
                break
            end
        end
        if dashPos then 
            local lower = val:sub(1, dashPos-1)
            veaf.mainLogTrace(string.format("lower=%s", tostring(lower)))
            if lower then 
                lower = tonumber(lower)
            end
            if lower == nil then lower = 0 end
            local upper = val:sub(dashPos+1)
            veaf.mainLogTrace(string.format("upper=%s", tostring(upper)))
            if upper then 
                upper = tonumber(upper)
            end
            if upper == nil then upper = 5 end
            nVal = math.random(lower, upper)
            veaf.mainLogTrace(string.format("random nVal=%s", tostring(nVal)))
        end
        --]]

        -- [[
        if val == "1-2" then nVal = math.random(1,2) end
        if val == "1-3" then nVal = math.random(1,3) end
        if val == "1-4" then nVal = math.random(1,4) end
        if val == "1-5" then nVal = math.random(1,5) end

        if val == "2-3" then nVal = math.random(2,3) end
        if val == "2-4" then nVal = math.random(2,4) end
        if val == "2-5" then nVal = math.random(2,5) end

        if val == "3-4" then nVal = math.random(3,4) end
        if val == "3-5" then nVal = math.random(3,5) end

        if val == "4-5" then nVal = math.random(4,5) end

        if val == "5-10" then nVal = math.random(5,10) end

        if val == "10-15" then nVal = math.random(10,15) end
        --]]

        --[[
        if val == "1-2" then nVal = 2 end
        if val == "1-3" then nVal = 3 end
        if val == "1-4" then nVal = 3 end
        if val == "1-5" then nVal = 3 end

        if val == "2-3" then nVal = 2 end
        if val == "2-4" then nVal = 3 end
        if val == "2-5" then nVal = 3 end

        if val == "3-4" then nVal = 3 end
        if val == "3-5" then nVal = 4 end

        if val == "4-5" then nVal = 4 end

        if val == "5-10" then nVal = 7 end
        
        if val == "10-15" then nVal = 12 end
        --]]

    --[[
        -- maybe it's a range ?
        local dashPos = val:find("-")
        veaf.mainLogTrace(string.format("dashPos=%s", tostring(dashPos)))
        if dashPos then 
            local lower = val:sub(1, dashPos-1)
            veaf.mainLogTrace(string.format("lower=%s", tostring(lower)))
            if lower then 
                lower = tonumber(lower)
            end
            if lower == nil then lower = 0 end
            local upper = val:sub(dashPos+1)
            veaf.mainLogTrace(string.format("upper=%s", tostring(upper)))
            if upper then 
                upper = tonumber(upper)
            end
            if upper == nil then upper = 5 end
            nVal = math.random(lower, upper)
            veaf.mainLogTrace(string.format("random nVal=%s", tostring(nVal)))
        end
        --]]
    end
    veaf.mainLogTrace(string.format("nVal=%s", tostring(nVal)))
    return nVal
end

function veaf.getRandomizableNumeric_norandom(val)
    veaf.mainLogTrace(string.format("getRandomizableNumeric_norandom(%s)", tostring(val)))
    local nVal = tonumber(val)
    veaf.mainLogTrace(string.format("nVal=%s", tostring(nVal)))
    if nVal == nil then 
        if val == "1-2" then nVal = 2 end
        if val == "1-3" then nVal = 3 end
        if val == "1-4" then nVal = 3 end
        if val == "1-5" then nVal = 3 end

        if val == "2-3" then nVal = 2 end
        if val == "2-4" then nVal = 3 end
        if val == "2-5" then nVal = 3 end

        if val == "3-4" then nVal = 3 end
        if val == "3-5" then nVal = 4 end

        if val == "4-5" then nVal = 4 end

        if val == "5-10" then nVal = 7 end
        
        if val == "10-15" then nVal = 12 end
    end
    veaf.mainLogTrace(string.format("nVal=%s", tostring(nVal)))
    return nVal
end

function veaf.getRandomizableNumeric(val)
    veaf.mainLogTrace(string.format("getRandomizableNumeric(%s)", tostring(val)))
    return veaf.getRandomizableNumeric_random(val)
end

function veaf.exportAsJson(data, name, jsonify, filename, export_path)
    local l_veafSanitized_lfs = veafSanitized_lfs
    if not l_veafSanitized_lfs then l_veafSanitized_lfs = lfs end

    local l_veafSanitized_io = veafSanitized_io
    if not l_veafSanitized_io then l_veafSanitized_io = io end

    local l_veafSanitized_os = veafSanitized_os
    if not veafSanitized_os then l_veafSanitized_os = os end

    local function writeln(file, text)
        file:write(text.."\r\n")
    end
    
    local export_path = export_path
    if not export_path then
        export_path = l_veafSanitized_os.getenv("VEAF_EXPORT_DIR")
        if export_path then export_path = export_path .. "\\" end
    end
    if not export_path then
        export_path = l_veafSanitized_os.getenv("TEMP")
        if export_path then export_path = export_path .. "\\" end
    end
    if not export_path then
        export_path = l_veafSanitized_lfs.writedir()
    end

    local filename = filename or name .. ".json"

    veafCombatMission.logInfo("Dumping ".. name .." as json to "..filename .. " in "..export_path)

    local header =    '{\n'
    header = header .. '  "' .. name .. '": [\n'   

    local content = {}
    for key, value in pairs(data) do
        local line =  jsonify(key, value)
        table.insert(content, line)
    end
    local footer =    '\n'
    footer = footer .. ']\n'
    footer = footer .. '}\n'

    local file = l_veafSanitized_io.open(export_path..filename, "w")
    writeln(file, header)
    writeln(file, table.concat(content, ",\n"))
    writeln(file, footer)
    file:close()
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- initialisation
-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- initialize the random number generator to make it almost random
math.random(); math.random(); math.random()

--- Enable/Disable error boxes displayed on screen.
env.setErrorMessageBoxEnabled(false)

veaf.mainLogInfo(string.format("Loading version %s", veaf.Version))
