print("Attempting to play music")

local dfpwm = require("cc.audio.dfpwm")
local speakers = { peripheral.find("speaker") }
local drive = peripheral.find("drive")
local decoder = dfpwm.make_decoder()
local args = {...}

local uri = args[1]
local volume = tonumber(args[2])


if uri == nil or not uri:find("^https") then
	print("ERR - Invalid URI: " .. tostring(uri))
	return
end

function playChunk(chunk)
	local returnValue = nil
	local callbacks = {}

	for i, speaker in pairs(speakers) do
		if i > 1 then
			table.insert(callbacks, function()
				speaker.playAudio(chunk, volume or 1.0)
			end)
		else
			table.insert(callbacks, function()
				returnValue = speaker.playAudio(chunk, volume or 1.0)
			end)
		end
	end

	parallel.waitForAll(table.unpack(callbacks))

	return returnValue
end

local quit = false
function play()
    while true do
        print("In play loop")
        
        -- Start async HTTP request
        http.request(uri)
        
        -- Wait for http_success or http_failure
        local event, url, response
        repeat
            event, url, response = await_event()
        until (event == "http_success" or event == "http_failure") and url == uri
        
        if event == "http_failure" then
            print("HTTP request failed")
            break
        end

        local chunkSize = 4 * 1024
        local chunk = response.read(chunkSize)
        while chunk ~= nil do
            local buffer = decoder(chunk)
            print("buffer loaded")
            while not playChunk(buffer) do
                print("chunk buffer empty")
                await_event("speaker_audio_empty")  -- Use await_event instead
            end

            chunk = response.read(chunkSize)
        end
        
        response.close()
    end
end
play()