local storage = peripheral.wrap("minecraft:barrel_0")
local altar = peripheral.wrap("left")

function getCurrentItem(storage)
  local storageSize = storage.size()
  for i = 1, storageSize do
    item = storage.getItemDetail(i)
    if (item) then
      break
    end
  end
  if (item) then
    print(item.name)
  end
  return item
end

-- Define recipes
local recipes = {
  ["minecraft:stone"] = "bloodmagic:blankslate",
  ["bloodmagic:blankslate"] = "bloodmagic:reinforcedslate",
  ["bloodmagic:reinforcedslate"] = "bloodmagic:infusedslate",
  ["bloodmagic:infusedslate"] = "bloodmagic:demonslate"
}

-- Make sure redstone signal is off to start
redstone.setOutput("right", false)
redstone.setOutput("front", false)
local lastSeen
-- Main program loop
while (true) do
    -- Check last seen item in barrel

    local currentItem = getCurrentItem(storage)
    --print("altar item: " .. altarItem.name)
    --print("current recipe item: " .. currentItem.name)

    if (currentItem ~= nil or lastSeen ~= nil) then

        -- Attempt to send item to altar
        redstone.setOutput("right", true)
        os.sleep(0.1)
        redstone.setOutput("right", false)
        os.sleep(0.25)
        local altarItem = altar.getItemDetail(1)

        if (lastSeen ~= nil and altarItem ~= nil) then
            -- Make sure to finish the previous recipe first
            print("Altar item and lastseen both set")
            local targetItem = recipes[lastSeen.name]
            while (altarItem.name ~= targetItem) do
                altarItem = altar.getItemDetail(1)
            end
        -- We should have the target item at the altar now so send a pulse to the factory manager
            redstone.setOutput("front", true)
            os.sleep(0.1)
            redstone.setOutput("front", false)
            -- Update last seen now that we've ensured recipe completion
            lastSeen = currentItem
        else
            lastSeen = currentItem
        end
    end
end