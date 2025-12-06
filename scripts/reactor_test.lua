-- Reactor output flow_gate_0
-- Reactor input flow_gate_1
-- Containment projector / Reactor status draconic_reactor_0

-- Initialize peripherals

-- Available methods:
-- activateReactor()
-- toggleFailSafe()
-- stopReactor()
-- getReactorInfo()
-- chargeReactor()
reactor = peripheral.wrap("draconic_reactor_0")


-- Available methods:
-- getFlow()
-- setSignalLowFlow()
-- setSignalHighFlow()
-- setOverrideEnabled()
-- setFlowOverride()
reactor_input = peripheral.wrap("flow_gate_1")
reactor_output = peripheral.wrap("flow_gate_0")


-- Load monitors
local monitorHelper = require("monitors")
local monitors = monitorHelper.attachAll()
local monitor = peripheral.wrap("monitor_0")
monitor.setTextScale(0.5)

local function getChildrenHeight(container)
    local height = 0
    for _, child in ipairs(container.get("children")) do
        if(child.get("visible"))then
            local newHeight = child.get("y") + child.get("height")
            if newHeight > height then
                height = newHeight
            end
        end
    end
    return height
end

-- Load basalt GUI and attach to monitor
local basalt = require("basalt")
local mainFrame = basalt.getMainFrame()
local monitorFrame = mainFrame:addFrame({width = 53, height = 20, x = 0, y = 0, backgroundColor = colors.gray})
monitorFrame:onScroll(function(self, delta)
    local offset = math.max(0, math.min(self.get("offsetY") + delta, getChildrenHeight(self) - self.get("height")))
    self:setOffsetY(offset)
end)

local clock = monitorFrame:addLabel()
    :setText("Local time: ")
    :setPosition(2, 2)
    :setForeground(colors.white)

local reactorHeader = monitorFrame:addLabel()
    :setText("Reactor status: ")
    :setPosition(2, 4)
    :setForeground(colors.white)

local saturation = monitorFrame:addLabel()
    :setText("Saturation: ")
    :setPosition(2, 5)
    :setForeground(colors.white)

local failsafe = monitorFrame:addLabel()
    :setText("Failsafe enabled: ")
    :setPosition(2, 6)
    :setForeground(colors.white)

local fieldDrainRate = monitorFrame:addLabel()
    :setText("Field drain rate: ")
    :setPosition(2, 7)
    :setForeground(colors.white)

local fieldStrength = monitorFrame:addLabel()
    :setText("Field strength: ")
    :setPosition(2, 8)
    :setForeground(colors.white)

local fuelConversion = monitorFrame:addLabel()
    :setText("Fuel conversion: ")
    :setPosition(2, 9)
    :setForeground(colors.white)

local fuelConversionRate = monitorFrame:addLabel()
    :setText("Fuel conversion rate: ")
    :setPosition(2, 10)
    :setForeground(colors.white)

local generationRate = monitorFrame:addLabel()
    :setText("Power generation rate: ")
    :setPosition(2, 11)
    :setForeground(colors.white)

local maxEnergySaturation = monitorFrame:addLabel()
    :setText("Max energy saturation: ")
    :setPosition(2, 12)
    :setForeground(colors.white)

local maxFieldStrength = monitorFrame:addLabel()
    :setText("Max field strength: ")
    :setPosition(2, 13)
    :setForeground(colors.white)

local maxFuelConversion = monitorFrame:addLabel()
    :setText("Max fuel conversion: ")
    :setPosition(2, 14)
    :setForeground(colors.white)

local reactorState = monitorFrame:addLabel()
    :setText("Reactor state: ")
    :setPosition(2, 15)
    :setForeground(colors.white)

local reactorTemp = monitorFrame:addLabel()
    :setText("Reactor temperature: ")
    :setPosition(2, 16)
    :setForeground(colors.white)



local fluxGateInputHeader = monitorFrame:addLabel()
    :setText("Reactor input status: ")
    :setPosition(2, 20)
    :setForeground(colors.white)

local fluxGateInputFlow = monitorFrame:addLabel()
    :setText("Current flow: ")
    :setPosition(2, 21)
    :setForeground(colors.white)

local fluxGateInputOverrideStatus = monitorFrame:addLabel()
    :setText("Flux gate override status: ")
    :setPosition(2, 22)
    :setForeground(colors.white)

local fluxGateInputOverrideValue = monitorFrame:addLabel()
    :setText("Override value: ")
    :setPosition(2, 23)
    :setForeground(colors.white)

local fluxGateOutputHeader = monitorFrame:addLabel()
    :setText("Reactor output status: ")
    :setPosition(31, 20)
    :setForeground(colors.white)

local fluxGateOutputFlow = monitorFrame:addLabel()
    :setText("Current flow: ")
    :setPosition(31, 21)
    :setForeground(colors.white)

local fluxGateOutputOverrideStatus = monitorFrame:addLabel()
    :setText("Flow signal override status: ")
    :setPosition(31, 22)
    :setForeground(colors.white)

local fluxGateOutputOverrideValue = monitorFrame:addLabel()
    :setText("Override value: ")
    :setPosition(31, 23)
    :setForeground(colors.white)

-- Configure our input/output flow gate values
-- We are not using redstone signals so we will set the override flag
reactor_input.setOverrideEnabled(true)
local inputOverrideValue = 0
reactor_input.setFlowOverride(inputOverrideValue)
fluxGateInputOverrideValue:setText("Override value: " .. tostring(inputOverrideValue))

-- Create input fields for updating flow rates
local inputFlowRate = monitorFrame:addInput()
    :setPlaceholder(" New input flow rate")
    :setPosition(2, 25)
    :setForeground(colors.black)
    :setBackground(colors.white)
    :setSize(22, 1)

reactor_output.setOverrideEnabled(true)
local outputOverrideValue = 0
reactor_output.setFlowOverride(outputOverrideValue)
fluxGateOutputOverrideValue:setText("Override value: " .. tostring(outputOverrideValue))

basalt.run()
-- Core program loop
while (true) do
    local time = os.date("%H:%M:%S")
    clock:setText("Local time: " .. time)

    local reactorStatus = reactor.getReactorInfo()
    saturation:setText("Saturation: " .. tostring(reactorStatus.energySaturation))
    failsafe:setText("Failsafe enabled: " .. tostring(reactorStatus.failSafe))
    fieldDrainRate:setText("Field drain rate: " .. tostring(reactorStatus.fieldDrainRate))
    fieldStrength:setText("Field strength: " .. tostring(reactorStatus.fieldStrength))
    fuelConversion:setText("Fuel conversion: " .. tostring(reactorStatus.fuelConversion))
    fuelConversionRate:setText("Fuel conversion rate: " .. tostring(reactorStatus.fuelConversionRate))
    generationRate:setText("Energy generation rate: " .. tostring(reactorStatus.generationRate))
    maxEnergySaturation:setText("Max energy saturation: " .. tostring(reactorStatus.maxEnergySaturation))
    maxFieldStrength:setText("Max field strength: " .. tostring(reactorStatus.maxFieldStrength))
    maxFuelConversion:setText("Max fuel conversion " .. tostring(reactorStatus.maxFuelConversion))
    reactorState:setText("Reactor state: " .. tostring(reactorStatus.status))
    reactorTemp:setText("Reactor temperature: " .. tostring(reactorStatus.temperature))

   
    fluxGateInputFlow:setText("Current flow: " .. tostring(reactor_input.getFlow()))
    fluxGateInputOverrideStatus:setText("Signal override: " .. tostring(reactor_input.getOverrideEnabled()))

    fluxGateOutputFlow:setText("Current flow: " .. tostring(reactor_output.getFlow()))
    fluxGateOutputOverrideStatus:setText("Signal override: " .. tostring(reactor_output.getOverrideEnabled()))

    basalt.update()
    sleep(1.0)
end