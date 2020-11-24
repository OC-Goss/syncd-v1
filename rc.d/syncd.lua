local component = require("component")
local internet = require("internet")
local event = require("event")
local filesystem = require("filesystem")
local serialization = require("serialization")

local configPath = "/etc/syncd.cfg"
local logPath = "/etc/syncd.log"
local heartbeatPattern =  "(%a+) ([%w%s%p]-) (%a+)\n"
local defaultConfig = {
	pollTime = 1.0,
	address = nil,
	targetDir = nil
}

local config = {}
local actions = {}
local heartbeatTimer
local logFile

local function shallowCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

local function toBool(str)
	if type(str) == "string" then
		return string.lower(str) == "true"
	end
end

local function log(fmt, ...)
	logFile:write(string.format(fmt, ...))
end

local function urlEncode(str)
   if str then
      str = str:gsub("\n", "\r\n")
      str = str:gsub("([^%w %-%_%.%~])", function(c)
         return ("%%%02X"):format(string.byte(c))
      end)
      str = str:gsub(" ", "+")
   end
   return str
end

-- returns: response body, status, status message, headers
local function getResponse(r)
	repeat
		ok, err = r.finishConnect()
		if type(ok) ~= "boolean" then
			return
		end
		os.sleep()
	until ok

	if r.response() then
		local chunks = {}
		for chunk in r do
			chunks[#chunks + 1] = chunk
		end
		return table.concat(chunks), r.response()
	end
end

local function requestFile(filepath)
	local request = internet.request(string.format("%s/file/%s", config.address, urlEncode(filepath)))
	local response, status, msg, headers = getResponse(request)
	if response then
		if status == 200 then
			return response
		else
			log("Accessing file %s failed, server returned %u: %s", filepath, status, msg)
		end
	else
		log("Connecting to the server failed while trying to access file %s", filepath)
	end
end

local function writeFile(filepath, data)
	local file = io.open(filepath, "w")	
	file:write(data)
	file:close()
end

local function removeIfExists(filepath)
	if filesystem.exists(filepath) then
		filesystem.remove(filepath)
	end
end

local function getFullpath(filepath)
	return filesystem.concat(config.targetDir, filepath)
end

function actions.create(filepath, isDir)
	local fullpath = getFullpath(filepath)
	removeIfExists(fullpath)
	if isDir then
		filesystem.makeDirectory(fullpath)
	else
		writeFile(fullpath, requestFile(filepath))
	end
end

function actions.update(filepath, isDir)
	if not isDir then
		local fullpath = getFullpath(filepath)
		removeIfExists(fullpath)
		writeFile(fullpath, requestFile(filepath))
	end
end

function actions.delete(filepath, isDir)
	local fullpath = getFullpath(filepath)
	removeIfExists(fullpath)
end

local function heartbeat()
	local request = internet.request(string.format("%s/%s", config.address, "heartbeat"))
	local response, status, msg, headers = getResponse(request)
	if response then
		if status == 200 then
			for action, filepath, isDir in string.gmatch(response, heartbeatPattern) do
				if actions[action] then
					log("%s: %s (is directory: %s)", action, filepath, isDir)
					actions[action](filepath, toBool(isDir))
				else
					log("Invalid action name %s, skipping", action)
				end
			end
		elseif status ~= 304 then
			error(string.format("Accessing heartbeat failed, server returned %u: %s", status, msg))
		end
	else
		error(string.format("Connecting to the server failed while trying to access heartbeat"))
	end
end

local function writeConfig(cfg)
	writeFile(configPath, serialization.serialize(cfg))
end

local function readConfig()
	if filesystem.exists(configPath) then
		local configFile = io.open(configPath, "r")
		local cfg = serialization.unserialize(configFile:read("*all"))
		configFile:close()
		return cfg
	else
		writeConfig(defaultConfig)
		return defaultConfig
	end
end

function start()
	if not component.isAvailable("internet") then
		error("This service requires an internet card to run")
	end

	config = readConfig()
	if not config.address then
		error("You need to specify server address first with 'rc syncd setAddress <address>'")
	end
	if not config.targetDir then
		error("You need to specify target directory where the files will be stored first with 'rc syncd setDirectory <directory>'")
	end

	heartbeatTimer = event.timer(config.pollTime, heartbeat, math.huge)
	logFile = io.open(logPath, "a")
	heartbeat()
end

function stop()
	if heartbeatTimer then
		event.cancel(heartbeatTimer)
	end
	logFile:close()
end

function setPolling(pollTime)
	pollTime = tonumber(pollTime)
	if pollTime then
		config = readConfig()
		config.pollTime = pollTime
		writeConfig(config)
		if heartbeatTimer then
			event.cancel(heartbeatTimer)
			event.timer(config.pollTime, heartbeat, math.huge)
		end
	else
		error("Usage: rc syncd setPolling <seconds>")
	end
end

function setAddress(address)
	if not string.match(address, "https?://.+") then
		address = "http://" .. address
	end
	config = readConfig()
	config.address = address
	writeConfig(config)
end

function setDirectory(targetDir)
	local fullpath = filesystem.concat(os.getenv("PWD"), targetDir)
	if filesystem.isDirectory(fullpath) then
		config = readConfig()
		config.targetDir = fullpath
		writeConfig(config)
	else
		error("Usage: rc syncd setDirectory <valid path to existing directory>")
	end
end
