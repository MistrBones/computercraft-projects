local storage = peripheral.wrap("minecraft:barrel_0")
local altar = peripheral.wrap("left")

while (true) do
    print("Hello World")
    redstone.setOutput("front", true)
    os.sleep(0.25)
    redstone.setOutput("front", false)
    os.sleep(0.25)
end