-- CC Tweaked monitor available methods:
-- See documentation @ https://tweaked.cc/peripheral/monitor.html
local function attachAll(id)
    local peripherals = peripheral.getNames()
    local monitors = {}
    for index, name in ipairs(peripherals) do
        if (string.find(name, "monitor")) then
            local monitor = peripheral.wrap(name)
            table.insert(monitors, monitor)
        end
    end
    return monitors
end

local function draw(monitors, content)
    for index, monitor in ipairs(monitors) do
        monitor.clear()
        monitor.setCursorPos(1,1)
        monitor.write(content)
    end
end

return { attachAll = attachAll, draw = draw }