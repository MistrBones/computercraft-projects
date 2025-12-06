--todo 
--standardize modem packet format
--all command lists should end with an acknowledgement
--consider batching messages on the listener side so we dont have to keep track of a variable number of expected messages based on the input commands
--consider breaking functions up into separate files

local args = {...}
-- argument validation here

local pretty = require "cc.pretty"
local strings = require "cc.strings"

local modem = peripheral.find("modem") or error("No modem attached", 0)
modem.open(77)
local transmitTo = 69
local listenChannel = 77

-- List of remote device IDs
devices = {}
-- Table of available commands (populated by registerCommand)
local availableCommands = {}

-- Command function definitions
local printText = [[
    function(text)
        if text then
            print(text)
        end
        return
    end
]]

local registerFunction = [[
    function(src, name)
        src = "return " .. src
        local ok, err = pcall(function()
            local fn = load(src, name, "t", _ENV)()
            _G[name] = fn
        end)
        if not ok then
            local message = "Could not register function: " .. name
            print(message)
            print(err)
        end
    end
]]

local createStartup = [[
    function(contents)
        local mode = "w"
        if fs.exists("/startup.lua") then
            mode = "w+"
        end
        local startup = fs.open("/startup.lua", mode)
        startup.write(contents)
        startup.close()
    end
]]

local restart = [[
    function()
        modemSend("Rebooting now")
        public_os.reboot()
    end
]]

local getName = [[
    function()
        label = public_os.getComputerLabel()
        id = public_os.computerID()
        if label == nil then
            name = "unknown(cpu_" .. tostring(id) .. ")"
        else
            name = label .. "(cpu_" .. tostring(id) .. ")"
        end
        return name
    end
]]

local modemSend = [[
    function(text)
        local name = getName()
        message = name ..": " .. text
        local id = public_os.computerID()
        modem.transmit(77, 69, {
            ['message'] = message,
            ['id'] = id
        })
    end
]]

local updateListener = [[
    function(src)
        if src == nil then
            error("No source provided for listener update", 0)
        end
        -- Initialize config in case it doesnt exist first
        initConfig()

        -- Load config
        local configFile = fs.open("/config.txt", "r")
        local config = configFile.readAll()
        local unserialized = textutils.unserialize(config)
        configFile.close()

        -- Get current listener file
        local currentListener = unserialized['listener']

        -- Get version (if set) and update file name
        local version = string.match(currentListener, "%d+")
        if version == nil then
            version = "0"
        end
        version = tonumber(version)
        version = version + 1
        local newListener = "/listen_v" .. tostring(version) .. ".lua"

        -- Create new listener file
        local file = fs.open(newListener, "w")
        file.write(src)
        file.close()

        -- Update the startup file
        local contents = "os.run({}, '/rom/programs/shell.lua', '" .. newListener .. "')"
        createStartup(contents)

        -- Update the config file
        unserialized['listener'] = newListener
        local config = fs.open("/config.txt", "w+")
        config.write(textutils.serialize(unserialized))
        config.close()

        -- Restart
        restart()
    end
]]

local enumerateDevices = [[
    function()
        local res = {
            ["message"] = "\n Request acknowledged"
        }
        return res
    end
]]

local downloadFile = [[
    function(path, contents)
        local mode = "w+"
        local file = fs.open(path, mode)
        file.write(contents)
        file.close()
        local res = { 
            ["message"] = "Download successful" 
        }
        return res
    end
]]

local runScript = [[
    function(path, args)
        load_program(path, args)
        local res = {
            ["message"] = "Program loaded"
        }
    end
]]

local stopScript = [[
    function(path)
        if running_tasks[path] then
            running_tasks[path] = nil
            modemSend("Stopped task: " .. path)
            local res = { ["message"] = "Stopped task: " .. path }
            return res
        else
            local res = { ["message"] = "Task not found: " .. path }
            return res
        end
    end
]]

local bees = [[
    function()
        redstone.setOutput("right", true)
    end
]]

local beesOff = [[
    function()
        redstone.setOutput("right", false)
    end
]]

-- Add programs that remote host should run on startup (fixes issue with computers unloading/not properly resuming)
local addToStartup = [[

]]

-- Utility functions
function makeFn(fn)
    local src = "return " .. fn
    return src
end

function makeCommand(fn, args, name)
    local src = makeFn(fn)
    local command = {
        ["fn"] = src,
        ["args"] = args,
        ["name"] = name
    }
    return command
end

function loadFileContents(path)
    local file = fs.open(path, "r")
    local contents = file.readAll()
    file.close()
    return contents
end

-- Register a command for use in the parser
-- name: command name (e.g., "runScript")
-- fnString: the function string definition
function registerCommand(name, fnString)
    availableCommands[name] = fnString
    return true
end

-- Register all available commands
registerCommand("getName", getName)
registerCommand("modemSend", modemSend)
registerCommand("enumerateDevices", enumerateDevices)
registerCommand("registerFunction", registerFunction)
registerCommand("createStartup", createStartup)
registerCommand("restart", restart)
registerCommand("updateListener", updateListener)
registerCommand("downloadFile", downloadFile)
registerCommand("runScript", runScript)
registerCommand("stopScript", stopScript)
registerCommand("printText", printText)
registerCommand("bees", bees)
registerCommand("beesOff", beesOff)

-- Gets a list of all responding (online) devices on our network
local function enumerate()
    devices = {}
    local commandList = {}
    table.insert(commandList, makeCommand(registerFunction, {getName, "getName"}, "Get remote cpu label"))
    table.insert(commandList, makeCommand(registerFunction, {modemSend, "modemSend"}, "Send packet via remote modem"))

    -- Transmit request for enumeration
    local packet = {
        ["message"] = "Announce your presence",
        ["commands"] = commandList
    }
    modem.transmit(transmitTo, listenChannel, packet)

    -- Sets a timeout so we can enumerate without knowing the # of devices
    -- on the network
    local duration = 0.
    local timer = os.startTimer(duration)
    local timedOut = false
    while not timedOut do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()

        if event == "modem_message" then
            local side, channel, replyChannel, message, distance =
                p1, p2, p3, p4, p5

            if channel == 77 then
                -- reset timer because we heard from a device
                timer = os.startTimer(duration)
                local id = message.id
                table.insert(devices, id)
            end

        elseif event == "timer" and p1 == timer then
            timedOut = true
        end
    end
    return devices
end

-- Parse user input as function calls and convert to command list
function parseCommands(input)
    local commandList = {}
    
    -- Create sandbox environment with registered commands
    local env = {}
    
    -- Populate environment with command functions that capture arguments
    for cmdName, fnString in pairs(availableCommands) do
        env[cmdName] = function(...)
            local args = {...}
            table.insert(commandList, makeCommand(fnString, args, cmdName))
        end
    end
    
    -- Wrap input to make it valid Lua code
    local code = "return function() " .. input .. " end"
    
    -- Load and execute in sandbox
    local chunk, err = load(code, "input", "t", env)
    if not chunk then
        return nil, "Parse error: " .. err
    end
    
    local ok, fn = pcall(chunk)
    if not ok then
        return nil, "Load error: " .. fn
    end
    
    -- Execute the function to populate commandList
    ok, err = pcall(fn)
    if not ok then
        return nil, "Execution error: " .. err
    end
    
    return commandList
end

-- Send commands and wait for responses
function sendCommands(commandList, addresses)
    local packet = {
        ["message"] = "Command execution",
        ["commands"] = commandList,
        ["addresses"] = addresses
    }
    
    -- Determine expected response count
    local expectedCount = addresses and #addresses or #devices
    
    -- Track pending responses
    local pending = {}
    local remaining = 0
    
    if addresses then
        for _, id in ipairs(addresses) do
            pending[id] = true
            remaining = remaining + 1
        end
    else
        for _, id in ipairs(devices) do
            pending[id] = true
            remaining = remaining + 1
        end
    end
    
    -- Send packet
    modem.transmit(transmitTo, listenChannel, packet)
    print("Commands sent. Waiting for responses...")
    
    -- Wait for responses with timeout
    local duration = 5
    local timer = os.startTimer(duration)
    
    while remaining > 0 do
        local event, p1, p2, p3, message, distance = os.pullEvent()
        
        if event == "modem_message" then
            print(tostring(message.message))
            local id = message.id
            if pending[id] then
                pending[id] = nil
                remaining = remaining - 1
            end
        elseif event == "timer" and p1 == timer then
            print("Timeout - " .. remaining .. " devices did not respond")
            break
        end
    end
    
    print("Transmission complete\n")
end




-- Main command loop
while true do
    print("Enter commands (e.g., runScript('/play.lua', {'https://example.com/music.dfpwm'}) restart()):")
    print("Or type 'help' for available commands, 'quit' to exit")
    print("")
    write("> ")
    local input = read()
    print("")
    
    if input == "quit" or input == "exit" then
        print("Exiting command server")
        break
    end
    
    if input == "help" then
        print("Available commands:")
        for name, _ in pairs(availableCommands) do
            print("  - " .. name)
        end
        print("")
    elseif input == "" then
        print("No commands entered\n")
    else
        -- Parse commands
        local commandList, err = parseCommands(input)
        
        if not commandList then
            print("Error: " .. err .. "\n")
        else
            print("Parsed " .. #commandList .. " command(s)")

            -- Enumerate available devices for the user
            local devices = enumerate()
            print("Available decvices: ")
            pretty.pretty_print(devices)
            
            -- Get target addresses
            print("Enter target IDs (space-separated) or 'all':")
            write("Targets: ")
            local targetInput = read()
            
            local addresses = {}
            if targetInput ~= "all" and targetInput ~= "" then
                for id in string.gmatch(targetInput, "%d+") do
                    table.insert(addresses, tonumber(id))
                end
            end
            
            -- Send commands
            sendCommands(commandList, addresses)
        end
    end
end