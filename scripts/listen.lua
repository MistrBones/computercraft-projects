os.run({}, "/rom/programs/shell.lua", "clear")
print("Listening for commands from command server")

modem = peripheral.find("modem") or error("No modem found")
modem.open(69)
public_os = os
message = ""


-- Cleans up extraneous listener files
local function cleanup()
    if fs.exists("/config.txt") then
        local configFile = fs.open("/config.txt", "r")
        local configSerialized = configFile.readAll()
        local config = textutils.unserialize(configSerialized)
        local currentListener = config['listener']
        local currentListener = currentListener:gsub("/", "")
        for index, fileName in ipairs(fs.list("/")) do
            -- Iterate over files and see if there is an old listener file
            if string.find(fileName, "listen") then
                -- Check to make sure you don't see the active listener
                local friendlyName = fileName:gsub("/", "")
                if friendlyName ~= currentListener then
                    -- Not the current listener, delete it
                    local path = "/" .. fileName
                    fs.delete(path)
                end
            end
        end
    end
end

local function safe_execute(src, args)
    local ok, res = pcall(function()
        local fn = load(src, "remote_fn", "t", _ENV)()
            fn(table.unpack(args))
        end)
        if not ok then
            local message = "Could not execute function with src: \n" .. src
            print(message)
            print(res)
            modem.transmit(77, 69, message)
        end
        return res
end

-- Set up a scheduler for starting and stopping co-routines
running_tasks = {}
event_queue = {}

local function scheduler_loop()
    while true do
        -- Process event queue first
        while #event_queue > 0 do
            local event_data = table.remove(event_queue, 1)
            
            -- Find all tasks waiting for this event
            for path, task in pairs(running_tasks) do
                if task.status == "waiting" then
                    local filter = task.filter
                    local matches = false
                    
                    if not filter then
                        -- No filter, accept any event
                        matches = true
                    elseif type(filter) == "string" then
                        -- String filter, match event name
                        matches = (event_data[1] == filter)
                    elseif type(filter) == "table" then
                        -- Table filter (for multiple event types)
                        for _, f in ipairs(filter) do
                            if event_data[1] == f then
                                matches = true
                                break
                            end
                        end
                    end
                    
                    if matches then
                        -- Resume the coroutine with the event
                        task.status = "running"
                        local ok, result = coroutine.resume(task.coro, table.unpack(event_data))
                        
                        if not ok then
                            print("Error in " .. path .. ": " .. tostring(result))
                            running_tasks[path] = nil
                        elseif coroutine.status(task.coro) == "dead" then
                            running_tasks[path] = nil
                        else
                            -- Check what the coroutine is waiting for
                            if type(result) == "table" and result.type == "wait_event" then
                                task.status = "waiting"
                                task.filter = result.filter
                                task.raw = result.raw or false
                            else
                                -- Coroutine yielded without event request, resume next cycle
                                task.status = "ready"
                            end
                        end
                    end
                end
            end
        end
        
        -- Resume any tasks that are ready (not waiting for events)
        for path, task in pairs(running_tasks) do
            if task.status == "ready" then
                task.status = "running"
                local ok, result = coroutine.resume(task.coro)
                
                if not ok then
                    print("Error in " .. path .. ": " .. tostring(result))
                    running_tasks[path] = nil
                elseif coroutine.status(task.coro) == "dead" then
                    running_tasks[path] = nil
                else
                    -- Check what the coroutine is waiting for
                    if type(result) == "table" and result.type == "wait_event" then
                        task.status = "waiting"
                        task.filter = result.filter
                        task.raw = result.raw or false
                    else
                        task.status = "ready"
                    end
                end
            end
        end
        
        -- Yield to allow other work
        coroutine.yield()
    end
end

-- Drop in replacement for os.pullEvent() to work with coroutines
local function await_event(filter)
    return coroutine.yield({ type = "wait_event", filter = filter })
end

-- Creates a copy of the listener env to pass to coroutines so we dont pollute global env
function make_env(args)
    local env = {}
    -- inherit CC APIs and globals safely
    setmetatable(env, { __index = _ENV })

    -- add program args
    env.args = args or {}
    env.await_event = await_event
    env.spawn_task = spawn_task
    env.require = require
    env.package = package
    return env
end

-- Allows command server to register coroutines
function load_program(path, args)
    local env = make_env(args)
    local chunk, err = loadfile(path, "t", env)
    if not chunk then return nil, err end
    
    -- Pass args as varargs to spawn_task
    if args and type(args) == "table" then
        spawn_task(path, chunk, table.unpack(args))
    else
        spawn_task(path, chunk)
    end
    return
end

-- Clean up extraneous listener files in root folder
cleanup()

function spawn_task(path, func, ...)
    local args = {...}
    local coro
    
    if type(func) == "function" then
        -- Create environment that merges custom event handling with global scope
        local env = make_env()
        -- Copy over important globals that the task might need
        env.spawn_task = spawn_task
        env.running_tasks = running_tasks
        env.arg = args  -- Make args available as 'arg' table
        
        setfenv(func, env)
        coro = coroutine.create(func)
    else
        -- Assume it's already a coroutine
        coro = func
    end
    
    print("Spawning task:", path)
    
    running_tasks[path] = {
        coro = coro,
        status = "ready",
        filter = nil,
        raw = false,
        args = args
    }
    
    -- Immediately try to start the task with its arguments
    local task = running_tasks[path]
    task.status = "running"
    local ok, result = coroutine.resume(task.coro, table.unpack(args))
    
    if not ok then
        print("Error starting task " .. path .. ": " .. tostring(result))
        running_tasks[path] = nil
    elseif coroutine.status(task.coro) == "dead" then
        print("Task " .. path .. " completed immediately")
        running_tasks[path] = nil
    else
        -- Coroutine started successfully so save state
        saveState()
        -- Check what the coroutine is waiting for
        if type(result) == "table" and result.type == "wait_event" then
            task.status = "waiting"
            task.filter = result.filter
            task.raw = result.raw or false
            print("Task " .. path .. " waiting for event:", result.filter)
        else
            task.status = "ready"
            print("Task " .. path .. " yielded, will resume next cycle")
        end
    end
end


-- Save coroutine state in a file so we can restore state if the computer unloads
function saveState()
--    local file = fs.open("/state.txt", "w+")
--    local state = textutils.serialize(running_tasks, {})
--    file.write(state)
--    file.close()
--    return true
    return
end

-- Load coroutine state from file
function loadState()
    if (fs.exists("/state.txt")) then
        local file = fs.open("/state.txt", "r")
        local stateSerialized = file.readAll()
        -- Overwrite running tasks to put our coroutines back in place
        running_tasks = textutils.unserialize(stateSerialized)
        end
    return
end

local function initConfig()
    if fs.exists("/config.txt") then
        -- do nothing
    else
        -- create startup file
        local startup = fs.open("/startup.lua", "w+")
        startup.write("os.run({}, '/rom/programs/shell.lua', 'listen.lua')")
        startup.close()

        -- initialize config with required values
        local config = {
            ['listener'] = '/listen.lua'
        }
        local serialized = textutils.serialize(config, {})
        local configFile = fs.open("/config.txt", "w")
        configFile.write(serialized)
        configFile.close()
    end
end

local function scheduler_tick(event_data)
    -- Process the event for all waiting tasks
    for path, task in pairs(running_tasks) do
        if task.status == "waiting" then
            local filter = task.filter
            local matches = false
            
            if not filter then
                -- No filter, accept any event
                matches = true
            elseif type(filter) == "string" then
                -- String filter, match event name
                matches = (event_data[1] == filter)
            elseif type(filter) == "table" then
                -- Table filter (for multiple event types)
                for _, f in ipairs(filter) do
                    if event_data[1] == f then
                        matches = true
                        break
                    end
                end
            end
            
            if matches then
                -- Resume the coroutine with the event
                task.status = "running"
                local ok, result = coroutine.resume(task.coro, table.unpack(event_data))
                
                if not ok then
                    print("Error in " .. path .. ": " .. tostring(result))
                    running_tasks[path] = nil
                elseif coroutine.status(task.coro) == "dead" then
                    running_tasks[path] = nil
                else
                    -- Check what the coroutine is waiting for
                    if type(result) == "table" and result.type == "wait_event" then
                        task.status = "waiting"
                        task.filter = result.filter
                        task.raw = result.raw or false
                    else
                        -- Coroutine yielded without event request, resume next cycle
                        task.status = "ready"
                    end
                end
            end
        end
    end
    
    -- Resume any tasks that are ready (not waiting for events)
    for path, task in pairs(running_tasks) do
        if task.status == "ready" then
            task.status = "running"
            local ok, result = coroutine.resume(task.coro)
            
            if not ok then
                print("Error in " .. path .. ": " .. tostring(result))
                running_tasks[path] = nil
            elseif coroutine.status(task.coro) == "dead" then
                running_tasks[path] = nil
            else
                -- Check what the coroutine is waiting for
                if type(result) == "table" and result.type == "wait_event" then
                    task.status = "waiting"
                    task.filter = result.filter
                    task.raw = result.raw or false
                else
                    task.status = "ready"
                end
            end
        end
    end
end

-- Listen for messages from command server
local function listener_loop()
    print("Listener loop started")
    while true do
        local event, side, channel, replyChannel, message, distance = os.pullEventRaw()
        
        if event == "modem_message" and channel == 69 then
            print("Command received")
            local commands = message['commands']
            local isAddressed = true
            
            if message['addresses'] ~= nil then
                -- Command is only meant for certain devices
                isAddressed = false
                local id = os.getComputerID()
                for index, addressed in ipairs(message['addresses']) do
                    if id == addressed then
                        isAddressed = true
                        break
                    end
                end
            end

            if isAddressed then
                local response_msg = "Begin message: "
                for index, command in ipairs(commands) do
                    print("Executing received command")
                    local args = command["args"]
                    local fn = command["fn"]
                    
                    -- Spawn as a task if it needs to run concurrently
                    -- or execute directly if it's synchronous
                    local res = safe_execute(fn, args)
                    if res ~= nil and res['message'] ~= nil then
                        response_msg = response_msg .. res['message']
                    end
                end
                
                local finalMessage = response_msg .. "\n"
                modemSend(finalMessage)
                os.sleep(0.5)
            end
        end
        
        if event == "terminate" then
            print("Manual termination requested.")
            error("terminate", 0)
        end
    end
end

-- Restarts crashed listener/scheduler loops with clean environments
-- Keeps track of crashes to prevent restart loops
-- Creates scheduler and listener loops in parallel
local function supervisor(max_restarts, window_seconds)
    local crashes = {}
    loadState()

    while true do
        -- Create coroutine for listener
        local listener = coroutine.create(listener_loop)
        
        -- Initial resume to start the listener
        local ok, err = coroutine.resume(listener)
        if not ok then
            print("Listener failed to start:", err)
            return
        end
        
        local ok, err = pcall(function()
            while true do
                -- Pull event in supervisor (main loop)
                local event_data = {os.pullEventRaw()}
                
                -- Check for terminate in supervisor
                if event_data[1] == "terminate" then
                    -- Try to gracefully resume listener with terminate event
                    if coroutine.status(listener) ~= "dead" then
                        coroutine.resume(listener, table.unpack(event_data))
                    end
                    error("terminate")
                end
                
                -- Pass event to scheduler for spawned tasks
                scheduler_tick(event_data)
                
                -- Resume listener with the event
                if coroutine.status(listener) ~= "dead" then
                    local ok, listener_err = coroutine.resume(listener, table.unpack(event_data))
                    if not ok then
                        -- Check if listener threw terminate
                        local err_str = tostring(listener_err)
                        if err_str:match("terminate") then
                            error("terminate")
                        end
                        error("Listener error: " .. err_str)
                    end
                end
                
                -- Check if listener died
                if coroutine.status(listener) == "dead" then
                    error("Listener coroutine died unexpectedly")
                end
            end
        end)
        
        if ok then
            return
        end

        -- Check if error contains "terminate"
        local err_str = tostring(err)
        if err_str:match("terminate") then
            print("Termination acknowledged")
            return
        end
        
        -- Record crash
        local now = os.clock()
        table.insert(crashes, now)

        -- Prune old crashes
        for i = #crashes, 1, -1 do
            if now - crashes[i] > window_seconds then
                table.remove(crashes, i)
            end
        end
        
        print("Loop crashed:", err)
        
        if #crashes >= max_restarts then
            print("Too many errors, shutting down.")
            return
        end

        print("Restarting listener/scheduler...")
        running_tasks = {}
    end
end


initConfig()
-- Start the supervisor
supervisor(3, 10)
