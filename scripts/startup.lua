--peripheral config
local sideGateOut = "flow_gate_5"
local sideGateIn = "flow_gate_4"
local gateInEmergency = "flow_gate_"
 
--output multiplier: set by modpack (default = 1.0), change this to the value of draconic evolution config (!!!not tested yet!!!)
local outputMultiplier = 1.0
 
local reactornumber = "1"

local tempPinpoint = 0

--Do not change anything below
 
--originally made by electronx3
--modified by jona23 to work in 1.16+
 
--constants
local val_1div3 = 1.0/3.0
 
--config
 
--emergency shutdown parameters
local maxOvershoot = 200.0      --reactor will shutdown when temperature gets hotter than defaultTemp+maxOvershoot
local minFuel = 0.05
 
--default parameters
local defaultTemp = 8000.0
local defaultField = 0.09
local restartFix = 100

 
local maxTempInc = 400.0        --max. temperature increase per computer tick
local maxOutflow = 300000000.0
 
local chargeInflow = 20000000
local shutDownField = 0.1       --field strength while shutdown
 
local safeMode = true           --when set to false, the automatic emergency shutdown function is disabled
 
 
--peripherals
local reactor
local gateIn
local gateOut
local mon
 
--info
local info
 
local currentEmergency = false
local currentField
local currentFuel
 
local stableTicks = 0
local screenPage = 0
local openConfirmDialog = false
 
local manualStart = false
local manualCharge = false
local manualStop = false
 
 
--the program
function updateInfo()
    info = reactor.getReactorInfo()
    
    if info == nil or info == null then
        gClear()
        gWrite("System Crash!", 1, 1, colors.white, colors.blue)
        gWrite("CODE: invalid_core_setup", 1, 2, colors.white, colors.blue)
      error("Reactor has an invalid setup")
    end
    
    if info.maxFieldStrength == 0 then
      currentField = 0
    else
      currentField = info.fieldStrength / info.maxFieldStrength
    end

    if info.maxFuelConversion == 0 then
      currentFuel = 0
    else
      currentFuel = 1.0 - (info.fuelConversion / info.maxFuelConversion)
    end
end
 
function isEmergency()
    currentEmergency = safeMode and not (info.temperature < 2000.0) and (info.status == "running" or info.status == "online" or info.status == "stopping") and (info.temperature > defaultTemp + maxOvershoot or currentField < 0.004 or currentFuel < minFuel)
    return currentEmergency
end
 
function calcInflow(targetStrength, fieldDrainRate)
    return fieldDrainRate / (1.0 - targetStrength)
end
 
--creators of the setupPeripherals function: https://github.com/acidjazz/drmon/blob/master/drmon.lua
function setupPeripherals()
    local tmpMon = periphSearch("monitor")
    if tmpMon == null then
        mon = null
        print("WARN: No valid monitor was found!")
 
    else
        monX, monY = tmpMon.getSize()
        mon = {}
        mon.monitor, mon.x, mon.y = tmpMon, monX, monY
    end

    print("Setup peripherals...")
    reactor = periphSearch("draconic_reactor")
    gateIn = peripheral.wrap(sideGateIn)
    gateOut = peripheral.wrap(sideGateOut)
    --gateEmergency = peripheral.wrap(gateInEmergency)
    
    if reactor == null then
        gClear()
        gWrite("System Crash!", 1, 1, colors.white, colors.blue)
        gWrite("CODE: no_valid_core_found", 1, 2, colors.white, colors.blue)
        error("No valid reactor was found!")
    end
    if gateIn == null then
        gClear()
        gWrite("System Crash!", 1, 1, colors.white, colors.blue)
        gWrite("CODE: no_valid_input_gate", 1, 2, colors.white, colors.blue)
        error("No valid input fluxgate was found!")
    end  
    if gateOut == null then
        gClear()
        gWrite("System Crash!", 1, 1, colors.white, colors.blue)
        gWrite("CODE: no_valid_output_gate", 1, 2, colors.white, colors.blue)
        error("No valid output fluxgate was found!")
    end
    if gateEmergency == null then
        --gClear()
        --gWrite("System Crash!", 1, 1, colors.white, colors.blue)
        --gWrite("CODE: no_valid_emergency_gate", 1, 2, colors.white, colors.blue)
        --error("No valid emergency fluxgate was found!")
    end
    
    gateIn.setOverrideEnabled(true)
    gateIn.setFlowOverride(0)
    gateOut.setOverrideEnabled(true)
    gateOut.setFlowOverride(0)
    
    print("Done!")
end
 
function periphSearch(type)
    local names = peripheral.getNames()
    local i, name
    for i, name in pairs(names) do
        if peripheral.getType(name) == type then
            return peripheral.wrap(name)
        end
    end
    return null
end
 
function clickListener()
    if mon == null then
        return
    end
    
    while true do
        event, side, xPos, yPos = os.pullEvent("monitor_touch")
        
        local cFlow = 0 --remove local later
        
        if yPos == mon.y and xPos >= 1 and xPos <= 4 then
            openConfirmDialog = false
            screenPage = (screenPage + 1) % 2
        elseif screenPage == 1 then         
            if yPos == 8 then
                local tmpTemp = defaultTemp
            
                if xPos >= 2 and xPos <= 3 then
                    tmpTemp = tmpTemp - 1.0
                elseif xPos >= 5 and xPos <= 6 then
                    tmpTemp = tmpTemp - 10.0
                elseif xPos >= 9 and xPos <= 11 then
                    tmpTemp = tmpTemp - 100.0
                elseif xPos >= 14 and xPos <= 16 then
                    tmpTemp = 8000.0
                elseif xPos >= 19 and xPos <= 21 then
                    tmpTemp = tmpTemp + 100.0
                elseif xPos >= 24 and xPos <= 25 then
                    tmpTemp = tmpTemp + 10.0
                elseif xPos >= 27 and xPos <= 28 then
                    tmpTemp = tmpTemp + 1.0
                end
                
                if tmpTemp < 20.0 then
                    tmpTemp = 20.0
                elseif tmpTemp > 20000.0 then
                    tmpTemp = 20000.0
                end
                
                defaultTemp = tmpTemp
                --print("new default temperature: " .. math.floor(defaultTemp) .. "°C")
            elseif yPos == 12 then
                local tmpField = defaultField
                
                if xPos >= 2 and xPos <= 3 then
                    tmpField = tmpField - 0.001
                elseif xPos >= 5 and xPos <= 6 then
                    tmpField = tmpField - 0.01
                elseif xPos >= 9 and xPos <= 11 then
                    tmpField = tmpField - 0.1
                elseif xPos >= 14 and xPos <= 16 then
                    tmpField = 0.01
                elseif xPos >= 19 and xPos <= 21 then
                    tmpField = tmpField + 0.1
                elseif xPos >= 24 and xPos <= 25 then
                    tmpField = tmpField + 0.01
                elseif xPos >= 27 and xPos <= 28 then
                    tmpField = tmpField + 0.001
                end
                

                if safeMode then
                if tmpField < 0.005 then
                    tmpField = 0.005
                elseif tmpField > 0.6 then
                    tmpField = 0.6
                end
                else
                if tmpField < 0.0001 then
                    tmpField = 0.0001
                elseif tmpField > 0.6 then
                    tmpField = 0.6
                end
                end
                
                defaultField = tmpField
                --print("new default field strength: " .. math.floor(defaultField*1000.0)/10.0 .. "%")
            elseif yPos == 15 then              
                if openConfirmDialog then
                    if xPos >= 25 and xPos <= 28 then
                        openConfirmDialog = false
                    elseif xPos >= 16 and xPos <= 22 then
                        openConfirmDialog = false
                        safeMode = false
                        --print("WARN: Safe mode deactivated!")
                    end
                elseif xPos >= 26 and xPos <= 28 then
                    if safeMode then
                        openConfirmDialog = true
                    else
                        safeMode = true
                        --print("Safe mode activated!")
                    end
                end
            elseif yPos == 17 and info ~= null then
                if not currentEmergency then
                    if (info.status == "running" or info.status == "online") and xPos >= 2 and xPos <= 5 then
                        manualStop = true
                    elseif (info.status == "cold" or info.status == "offline" or info.status == "cooling") and xPos >= 2 and xPos <= 7 then
                        manualCharge = true
                    elseif (info.status == "stopping" or info.status == "warming_up" or info.status == "charged") and xPos >= 2 and xPos <= 6 then
                        manualStart = true
                    elseif info.status == "warming_up" and xPos >= 9 and xPos <= 12 then
                        manualStop = true
                    end
                end
                if info.temperature < 2000.0 and xPos >= 26 and xPos <= 28 then
                    print("Program stopped!")
                    return
                end
            end
        end
        saveConfig()
    end
end
 
--graphic stuff: inspired by https://github.com/acidjazz/drmon/blob/master/drmon.lua
function gClear()
  mon.monitor.setBackgroundColor(colors.black)
  mon.monitor.clear()
  mon.monitor.setCursorPos(1,1)
end
function gWrite(text, x, y, cl, clBg)
    mon.monitor.setCursorPos(x, y)
    mon.monitor.setTextColor(cl)
    mon.monitor.setBackgroundColor(clBg)
    mon.monitor.write(text)
end
function gWriteR(text, x, y, cl, clBg)
    gWrite(text, mon.x - string.len(tostring(text)) - x, y, cl, clBg)
end
function gWriteLR(textL, textR, xL, xR, y, clL, clR, clBg)
    gWrite(textL, xL, y, clL, clBg)
    gWriteR(textR, xR, y, clR, clBg)
end
function gDrawLine(x, y, length, cl)
    if length < 0 then
        return
    end
    mon.monitor.setCursorPos(x, y)
    mon.monitor.setBackgroundColor(cl)
    mon.monitor.write(string.rep(" ", length))
end
function gDrawProgressBar(x, y, length, proportion, cl, clBg)
    if proportion < 0.0 or proportion > 1.0 then
        gDrawLine(x, y, length, cl)
    else
        gDrawLine(x, y, length, clBg)
        gDrawLine(x, y, math.floor(proportion*length), cl)
    end
end
function gDrawStandardProgressBar(y, proportion, cl)
    gDrawProgressBar(2, y, mon.x-2, proportion, cl, colors.gray)
end
 
 
function update()
    local newInflow = 0.0
    local newOutflow = 0.0  
    
    while true do   
        updateInfo()        
        local isStable = true
        local tmpShutDownField = math.max(shutDownField, defaultField)
    
        if peripheral.wrap(sideGateOut) == null then
            reactor.stopReactor()
            newInflow = calcInflow(tmpShutDownField, info.fieldDrainRate)
            gClear()
            gWrite("System Crash!", 1, 1, colors.white, colors.blue)
            gWrite("CODE: output_gate_missing", 1, 2, colors.white, colors.blue)
            error("Output gate missing!")
        end
        
        if manualStop then
            manualStart = false
            manualStop = false
            manualCharge = false
            reactor.stopReactor()
        end
        
        if isEmergency() == true then
            reactor.stopReactor()
            newInflow = calcInflow(0.8, info.fieldDrainRate)
            newOutflow = 0.0
            -- Open the emergency gate, there is still a flux gate before energy is inserted to the core so we are just supplementing
            --gateEmergency.setOverrideEnabled(true)
            --gateEmergency.setFlowOverride(100000000)
            manualStart = false
            manualCharge = false
        elseif info.status == "cold" or info.status == "offline" or info.status == "cooling" then
            newInflow = 0.0
            newOutflow = 0.0
            --gateEmergency.setFlowOverride(0)
            if manualCharge then
                manualStart = false
                manualCharge = false
                reactor.chargeReactor()
            end
        elseif info.status == "charging" then
            newInflow = chargeInflow
            newOutflow = 0.0
            manualStart = false
            manualCharge = false
        elseif info.status == "warming_up" or info.status == "charged" then
            newInflow = chargeInflow
            newOutflow = 0.0
            if manualStart then
                manualStart = false
                manualCharge = false
                reactor.activateReactor()
            end
        elseif info.status == "running" or info.status == "online" then
            manualStart = false
            manualCharge = false
            local temp = info.temperature
            
            if defaultTemp < info.temperature then
            if tempPinpoint < 10 then
            tempPinpoint = tempPinpoint - 0.01
            end
            end

            if defaultTemp > info.temperature then
            if tempPinpoint > -10 then
            tempPinpoint = tempPinpoint + 0.01
            end
            end
            
            defaultTemp = defaultTemp + tempPinpoint

            if temp > defaultTemp - 6.0 and temp < defaultTemp + 5.0 then
                stableTicks = stableTicks + 1
                if stableTicks > 100 then
                    isStable = true
                end
            else
                stableTicks = 0
            end
        
            if temp < defaultTemp then              
                local tempInc
                if temp < defaultTemp - 50.0 then
                    tempInc = math.sqrt(defaultTemp - temp)
                elseif temp < defaultTemp - 0.5 then
                    tempInc = math.sqrt(defaultTemp - temp)/2.0
                end
            
                if tempInc == nil or tempInc < 0.0 then
                    tempInc = 0
                elseif tempInc > maxTempInc then
                    tempInc = maxTempInc
                end

                
                local t50 = temp/200.0
                local convLvl = (info.fuelConversion / info.maxFuelConversion)*1.3 - 0.3
                
                local y = (t50^4)/(100.0-t50)*(1-convLvl) + 1000.0*(tempInc-convLvl) - 444.7
                local dSqrt = math.sqrt((50.0*y)^2 + (y/3.0)^3)
                
                local x             
                local tmpValRoot = dSqrt - 50.0*y
                if tmpValRoot > 0.0 then
                    x = math.pow(dSqrt + 50.0*y, val_1div3) - math.pow(tmpValRoot, val_1div3)
                else
                    x = math.pow(dSqrt + 50.0*y, val_1div3) + math.pow(0.0-tmpValRoot, val_1div3)
                end
                
                newOutflow = info.maxEnergySaturation*x/99.0 + info.energySaturation - info.maxEnergySaturation
                if newOutflow > maxOutflow then
                    newOutflow = maxOutflow
                end
            else
                newOutflow = 0.0
            end
        
            if isStable == true then
                if currentField > defaultField + 0.05 then
                    newInflow = 0.0
                elseif currentField > defaultField*1.2 then
                    newInflow = calcInflow(defaultField*0.98, info.fieldDrainRate)
                elseif currentField > defaultField*0.97 then
                    newInflow = calcInflow(defaultField, info.fieldDrainRate)
                else
                    newInflow = calcInflow(defaultField*1.5, info.fieldDrainRate)
                end
            else
                if currentField > tmpShutDownField then
                    newInflow = calcInflow(tmpShutDownField, info.fieldDrainRate)
                else
                    newInflow = calcInflow(tmpShutDownField*1.2, info.fieldDrainRate)
                end
            end
            defaultTemp = defaultTemp - tempPinpoint

        elseif info.status == "stopping" then
            if currentField > tmpShutDownField then
                newInflow = calcInflow(tmpShutDownField, info.fieldDrainRate)
            else
                newInflow = calcInflow(tmpShutDownField*1.2, info.fieldDrainRate)
            end
            newOutflow = 0.0
            
            if manualStart then
                manualStart = false
                manualCharge = false
                reactor.activateReactor()
            end
        end
        
        if newInflow < 0.0 then
            newInflow = 0.0
        end
        if newOutflow < 0.0 then
            newOutflow = 0.0
        end
        
        if newInflow > 0.0 then
            newInflow = math.floor(newInflow)
        else
            newInflow = 0
        end
        local outflowMultiplied = 0
        if newOutflow > 0.0 then
            outflowMultiplied = math.floor(newOutflow*outputMultiplier)
        else
            newOutflow = 0.0
        end
        if restartFix > 0 then
            outflowMultiplied = 0.0
            newInflow = 10000000.0
            restartFix = restartFix - 1.0
        end
        gateIn.setFlowOverride(newInflow)
        gateOut.setFlowOverride(outflowMultiplied)
        
        
        if mon ~= null then
            gClear()
            
            if screenPage == 0 then
                local clTemp
                if info.temperature < defaultTemp*0.95 then
                    clTemp = colors.green
                elseif info.temperature < defaultTemp + 1.0 then
                    clTemp = colors.yellow
                elseif info.temperature < defaultTemp + maxOvershoot then
                    clTemp = colors.orange
                else
                    clTemp = colors.red
                end
                
                gWriteLR("temperature:", math.floor(info.temperature*10.0)/10.0 .. "C", 2, 0, 7, colors.white, clTemp, colors.black)
                gWriteLR("set: " .. math.floor(defaultTemp) .. "C", "max: " .. math.floor(defaultTemp + maxOvershoot) .. "C", 2, 0, 8, colors.white, colors.white, colors.black)
                gDrawStandardProgressBar(9, info.temperature/16000.0, clTemp)               
                
                local clField
                if currentField > defaultField*1.05 then
                    clField = colors.green
                elseif currentField > defaultField*0.95 then
                    clField = colors.yellow
                else
                    clField = colors.red
                end
                
                gWriteLR("field strength:", math.floor(currentField*10000.0)/100.0 .. "%", 2, 0, 11, colors.white, clField, colors.black)
                gWriteLR("set: " .. math.floor(defaultField*1000)/10.0 .. "%", "min: 0.4%", 2, 0, 12, colors.white, colors.white, colors.black)
                gDrawStandardProgressBar(13, currentField, clField)
                
                gWriteLR("status", info.status:upper(), 2, 0, 15, colors.white, colors.white, colors.black)
                
                local clFuel
                if currentFuel > 0.15 then
                    clFuel = colors.green
                elseif currentFuel > 0.05 then
                    clFuel = colors.yellow
                elseif currentFuel > 0.01 then
                    clFuel = colors.orange
                else
                    clFuel = colors.red
                end
                gWriteLR("fuel:", math.floor(currentFuel*10000.0)/100.0 .. "%", 2, 0, 16, colors.white, clFuel, colors.black)
            elseif screenPage == 1 then
                local clTemp
                if info.temperature < defaultTemp*0.95 then
                    clTemp = colors.green
                elseif info.temperature < defaultTemp + 1.0 then
                    clTemp = colors.yellow
                elseif info.temperature < defaultTemp + maxOvershoot then
                    clTemp = colors.orange
                else
                    clTemp = colors.red
                end
                
                gWriteLR("temp: " .. math.floor(defaultTemp) .. " (" .. math.floor(defaultTemp + maxOvershoot) .. ")", math.floor(info.temperature*10.0)/10.0 .. "C", 2, 0, 7, colors.white, clTemp, colors.black)
                gDrawStandardProgressBar(9, info.temperature/16000.0, clTemp)
                
                gWrite("<", 2, 8, colors.white, colors.blue)
                gWrite("<<", 5, 8, colors.white, colors.blue)
                gWrite("<<<", 9, 8, colors.white, colors.blue)
                gWrite("res", 14, 8, colors.white, colors.blue)
                gWrite(">>>", 19, 8, colors.white, colors.blue)
                gWrite(">>", 24, 8, colors.white, colors.blue)
                gWrite(">", 28, 8, colors.white, colors.blue)               
                
                local clField
                if currentField > defaultField*1.05 then
                    clField = colors.green
                elseif currentField > defaultField*0.95 then
                    clField = colors.yellow
                else
                    clField = colors.red
                end
                
                gWriteLR("field: " .. math.floor(defaultField*1000)/10.0 .. "% (0.4%)", math.floor(currentField*10000.0)/100.0 .. "%", 2, 0, 11, colors.white, clField, colors.black)
                gDrawStandardProgressBar(13, currentField, clField)
                
                gWrite("<", 2, 12, colors.white, colors.blue)
                gWrite("<<", 5, 12, colors.white, colors.blue)
                gWrite("<<<", 9, 12, colors.white, colors.blue)
                gWrite("res", 14, 12, colors.white, colors.blue)
                gWrite(">>>", 19, 12, colors.white, colors.blue)
                gWrite(">>", 24, 12, colors.white, colors.blue)
                gWrite(">", 28, 12, colors.white, colors.blue)
                
                if safeMode then
                    if openConfirmDialog then
                        gWrite("DISABLE?", 2, 15, colors.white, colors.black)
                        gWrite("CONFIRM", 16, 15, colors.white, colors.green)
                        gWrite("EXIT", 25, 15, colors.white, colors.red)
                    else
                        gWrite("safe mode:", 2, 15, colors.white, colors.black)
                        gWrite("ON", 27, 15, colors.green, colors.black)
                    end
                else
                    gWrite("safe mode:", 2, 15, colors.white, colors.black)
                    gWrite("OFF", 26, 15, colors.red, colors.black)
                end
                
                if not currentEmergency then
                    if info.status == "running" or info.status == "online" then
                        gWrite("STOP", 2, 17, colors.white, colors.red)
                    elseif info.status == "cold" or info.status == "offline" or info.status == "cooling" then
                        gWrite("CHARGE", 2, 17, colors.white, colors.blue)
                    elseif info.status == "stopping" or info.status == "charged" then
                        gWrite("START", 2, 17, colors.white, colors.green)
                    elseif info.status == "warming_up" then
                        gWrite("START", 2, 17, colors.white, colors.green)
                        gWrite("STOP", 9, 17, colors.white, colors.red)
                    end
                end
                
                if info.temperature < 2000.0 then
                    gWrite("END", 26, 17, colors.white, colors.red)
                end
            end
            
            gWriteLR("Draconic Reactor Number", reactornumber, 2, 0, 1, colors.white, colors.white, colors.black)         
            
            gWriteLR("inflow:", newInflow .. " RF/t", 2, 0, 3, colors.white, colors.white, colors.black)
            gWriteLR("outflow:", outflowMultiplied .. " RF/t", 2, 0, 4, colors.white, colors.white, colors.black)       
            local gain = outflowMultiplied - newInflow
            if gain > 0.0 then
                gWriteLR("-> gain:", gain .. " RF/t", 2, 0, 5, colors.white, colors.green, colors.black)
            elseif gain < 0.0 then
                gWriteLR("-> gain:", gain .. " RF/t", 2, 0, 5, colors.white, colors.red, colors.black)
            elseif gain == 0.0 then
                gWriteLR("-> gain:", "0 RF/t", 2, 0, 5, colors.white, colors.white, colors.black)
            end
            
            gDrawLine(1, mon.y, 4, colors.gray)
        end
        
        sleep(0.02)
    end
end
 
function setup()
    term.clear()
    print("Starting program...")    
    
    if fs.exists("config.txt") then
        print("Loading config...")
        loadConfig()
        print("Done!")
    else
        print("Creating config...")
        saveConfig()
        print("Done!")
    end
 
    if chargeInflow < 0 then
        chargeInflow = 0
    end
    
    stableTicks = 0
    
    setupPeripherals()
    print("Started!")
end
function loadConfig()
    local config = fs.open("config.txt", "r")
    outputMultiplier = tonumber(config.readLine())/1000000.0
    maxOvershoot = tonumber(config.readLine())
    minFuel = tonumber(config.readLine())/100.0
    defaultTemp = tonumber(config.readLine())
    defaultField = tonumber(config.readLine())/1000.0
    maxTempInc = tonumber(config.readLine())
    maxOutflow = tonumber(config.readLine())
    chargeInflow = tonumber(config.readLine())
    shutDownField = tonumber(config.readLine())/1000.0
    config.close()
end
function saveConfig()
    local config = fs.open("config.txt", "w")
    config.writeLine(outputMultiplier*1000000.0)
    config.writeLine(maxOvershoot)
    config.writeLine(minFuel*100.0)
    config.writeLine(defaultTemp)
    config.writeLine(defaultField*1000.0)
    config.writeLine(maxTempInc)
    config.writeLine(maxOutflow)
    config.writeLine(chargeInflow)
    config.writeLine(shutDownField*1000.0)
    config.close()
end
 
function main()
    setup()
    if mon == null then
        update()
    else
        parallel.waitForAny(update, clickListener)
        gClear()
        gWrite("Program stopped!", 1, 1, colors.white, colors.black)
    end
end
 
main()