-- Vicious Bee Stinger Hunter Script v3.7 - SECURED WITH WEBHOOK TOKEN + WHITELIST
-- Detects "Thorn" parts (Size: 3×2×1.5) that spawn near fields (ONCE per spawn event)
-- NEW: Whitelist system - Auto marks as NOT ACTIVE after 50 seconds for whitelisted players

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local request = request or http_request or syn.request
local player = Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")
local USE_HTTP_HOP = true
local lastHop = 0


local config = {
    _lastStingerDetectionTime = 0,
    _stingerSpawnCooldown = 2, -- seconds
    _whitelistConsumed = false, -- 🔒 whitelist can trigger only once per stinger
    _playerMonitorConnection = nil,
    _playerRemovingConnection = nil,  -- existing line
    _whitelistAddedConnection = nil,   -- ← ADD THIS
    _whitelistRemovingConnection = nil, -- ← ADD THIS
    _whitelistLock = false,            -- ← ADD THIS
    _monitoringActive = false,
    playerCountThreshold = 6,
    webhookUrl = "",
    pcServerUrl = "",
    webhookSecret = "",
    isRunning = false,
    stingerDetected = false,
    currentField = "None",
    _descendantConnection = nil,
    _detectedStingers = {},
    detectionCount = 0,
    serverType = "Public",
    privateServerLink = "",
    expectedSize = Vector3.new(3.0, 2.0, 1.5),
    sizeTolerance = 0.1,
    stingerActiveTime = 240,
    _activeStatusTimer = nil,
    whitelistPlayers = {"", "", "", "", ""},
    whitelistTimer = 40,
    _whitelistTimers = {},
    _renderConnection = nil  -- ← ADD THIS LINE
}

-- Load saved webhook
if isfile and readfile and isfile("vicious_bee_webhook.txt") then
    local saved = readfile("vicious_bee_webhook.txt")
    if saved and saved ~= "" then
        config.webhookUrl = saved
        print("✅ Loaded saved webhook")
    end
end

-- Load saved PC server URL
if isfile and readfile and isfile("vicious_bee_pcserver.txt") then
    local saved = readfile("vicious_bee_pcserver.txt")
    if saved and saved ~= "" then
        config.pcServerUrl = saved
        print("✅ Loaded saved PC server URL")
    end
end

-- Load saved webhook secret
if isfile and readfile and isfile("vicious_bee_secret.txt") then
    local saved = readfile("vicious_bee_secret.txt")
    if saved and saved ~= "" then
        config.webhookSecret = saved
        print("✅ Loaded saved webhook secret")
    end
end

-- Load saved whitelist
if isfile and readfile and isfile("vicious_bee_whitelist.txt") then
    local success, result = pcall(function()
        local saved = readfile("vicious_bee_whitelist.txt")
        if saved and saved ~= "" then
            return HttpService:JSONDecode(saved)
        end
    end)
    if success and result then
        config.whitelistPlayers = result
        print("✅ Loaded saved whitelist:", table.concat(result, ", "))
    end
end

-- Load saved server type and private link
if isfile and readfile and isfile("vicious_bee_serverconfig.txt") then
    local success, result = pcall(function()
        local saved = readfile("vicious_bee_serverconfig.txt")
        if saved and saved ~= "" then
            return HttpService:JSONDecode(saved)
        end
    end)
    if success and result then
        config.serverType = result.serverType or "Public"
        config.privateServerLink = result.privateServerLink or ""
        print("✅ Loaded saved server config:", config.serverType)
    end
end

-- ANTI-IDLE SYSTEM
player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
    print("🔄 Anti-idle triggered (idle detection)")
end)

spawn(function()
    while true do
        wait(600)
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        print("🔄 Anti-idle triggered (10 min auto)")
    end
end)

local fields = {
    ["Sunflower Field"] = Vector3.new(183, 4, 165),
    ["Mushroom Field"] = Vector3.new(-253, 4, 299),
    ["Dandelion Field"] = Vector3.new(-30, 4, 225),
    ["Blue Flower Field"] = Vector3.new(113, 4, 88),
    ["Clover Field"] = Vector3.new(174, 34, 189),
    ["Strawberry Field"] = Vector3.new(-169, 20, 165),
    ["Spider Field"] = Vector3.new(-57, 20, 4),
    ["Bamboo Field"] = Vector3.new(93, 20, -25),
    ["Pineapple Patch"] = Vector3.new(262, 68, -201),
    ["Pumpkin Patch"] = Vector3.new(-194, 68, -182),
    ["Cactus Field"] = Vector3.new(-194, 68, -107),
    ["Rose Field"] = Vector3.new(-322, 20, 124),
    ["Pine Tree Forest"] = Vector3.new(-318, 68, -150),
    ["Stump Field"] = Vector3.new(439, 96, -179),
    ["Coconut Field"] = Vector3.new(-255, 72, 459),
    ["Pepper Patch"] = Vector3.new(-486, 124, 517),
    ["Mountain Top Field"] = Vector3.new(76, 176, -191)
}
local function getRandomPublicServer()
    local placeId = game.PlaceId
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"

    local success, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not success then
        warn("HTTP blocked, falling back to normal teleport")
        USE_HTTP_HOP = false
        return nil
    end

    local data = HttpService:JSONDecode(result)
    local valid = {}

    for _, server in ipairs(data.data or {}) do
        if server.playing >= 2 and server.playing <= 3 then
            table.insert(valid, server.id)
        end
    end

    if #valid == 0 then
        return nil
    end

    return valid[math.random(1, #valid)]
end

TeleportService.TeleportInitFailed:Connect(function(player, result, err)
    warn("❌ Teleport failed:", result, err)
    task.wait(5)
    hopRandomServer()
end)


local function hopRandomServer()
    if tick() - lastHop < 40 then return end
    lastHop = tick()

    if config.stingerDetected then return end
    if not config.isRunning then return end

    print("🔁 Hopping servers...")

    task.wait(2)

    local placeId = game.PlaceId

    if USE_HTTP_HOP then
        local serverId = getRandomPublicServer()
        if serverId then
            print("🌐 True random server:", serverId)
            TeleportService:TeleportToPlaceInstance(placeId, serverId, player)
            return
        else
            print("⚠️ No 2–3 player servers found, using fallback")
        end
    end

    -- Fallback (Delta-safe)
    print("🎲 Matchmaking random")
    TeleportService:Teleport(placeId, player)
end


spawn(function()
    while true do
        task.wait(20) -- TIME PER SERVER (change if you want)
        if config.isRunning and not config.stingerDetected then
            hopRandomServer()
        end
    end
end)


local function sendWebhook(title, description, color, webhookFields)
    if config.webhookUrl == "" then return end
    
    -- 🔒 WEBHOOK DEBOUNCE: Prevent same webhook within 2 seconds
    local webhookKey = title .. description
    local now = tick()
    
    if not config._lastWebhooks then
        config._lastWebhooks = {}
    end
    
    if config._lastWebhooks[webhookKey] and now - config._lastWebhooks[webhookKey] < 2 then
        print("⏭️ Skipping duplicate webhook:", title)
        return
    end
    
    config._lastWebhooks[webhookKey] = now
    
    local embed = {
        ["title"] = title,
        ["description"] = description,
        ["color"] = color,
        ["fields"] = webhookFields or {},
        ["timestamp"] = DateTime.now():ToIsoDate(),
        ["footer"] = {["text"] = "Vicious Bee Hunter | " .. player.Name}
    }
    
    local success, err = pcall(function()
        request({
            Url = config.webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({["embeds"] = {embed}, ["content"] = "@everyone"})
        })
    end)
    
    if not success then
        warn("Webhook failed:", err)
    end
end

local function getActiveField()
    return config.currentField or "None"
end

local function getClosestField(position)
    local closestField = "Unknown"
    local closestDistance = math.huge
    
    for fieldName, fieldPos in pairs(fields) do
        local dist = (position - fieldPos).Magnitude
        if dist < closestDistance then
            closestDistance = dist
            closestField = fieldName
        end
    end
    
    return closestField, closestDistance
end

local function verifySizeMatch(objSize)
    return math.abs(objSize.X - config.expectedSize.X) <= config.sizeTolerance and
           math.abs(objSize.Y - config.expectedSize.Y) <= config.sizeTolerance and
           math.abs(objSize.Z - config.expectedSize.Z) <= config.sizeTolerance
end

local function generateJoinLink()
    if config.serverType == "Private" and config.privateServerLink ~= "" then
        return config.privateServerLink
    else
        local placeId = game.PlaceId
        local jobId = game.JobId
        return string.format("roblox://experiences/start?placeId=%d&gameInstanceId=%s", placeId, jobId)
    end
end

local function isPlayerWhitelisted(playerName)
    for _, whitelistedName in ipairs(config.whitelistPlayers) do
        if whitelistedName ~= "" and whitelistedName:lower() == playerName:lower() then
            return true
        end
    end
    return false
end

local function getPlayerCount()
    return #Players:GetPlayers()
end

local function updateStingerLog(playerName, field, status, joinLink)
    -- 🔒 PC SERVER DEBOUNCE (prevents duplicate ngrok requests)
    config._lastLogSend = config._lastLogSend or {}
    local key = playerName .. "|" .. field .. "|" .. status
    local now = os.time()

    if config._lastLogSend[key] and now - config._lastLogSend[key] < 2 then
        print("⏭️ Skipping duplicate PC log:", key)
        return
    end

    config._lastLogSend[key] = now
    if config.pcServerUrl ~= "" then
        local logData = {
            player = playerName,
            field = field,
            status = status,
            timestamp = os.time(),
            detectionTime = os.time(),
            serverLink = joinLink or "N/A"
        }
        
        local success, err = pcall(function()
            request({
                Url = config.pcServerUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["X-Webhook-Token"] = config.webhookSecret
                },
                Body = HttpService:JSONEncode(logData)
            })
        end)
        
        if success then
            print("✅ Log sent to PC server (SECURE):", playerName, "-", field, "-", status)
        else
            warn("❌ Failed to send log to PC:", err)
        end
    end
    
    if not writefile or not readfile or not isfile then
        return
    end
    
    local logData = {}
    
    if isfile("vicious_bee_stinger_log.txt") then
        local success, result = pcall(function()
            local content = readfile("vicious_bee_stinger_log.txt")
            if content and content ~= "" then
                return HttpService:JSONDecode(content)
            end
        end)
        if success and result then
            logData = result
        end
    end
    
    local timestamp = os.time()
    logData[playerName] = {
        Field = field,
        Status = status,
        LastUpdate = timestamp,
        DetectionTime = logData[playerName] and logData[playerName].DetectionTime or timestamp,
        ServerLink = joinLink or "N/A"
    }
    
    pcall(function()
        writefile("vicious_bee_stinger_log.txt", HttpService:JSONEncode(logData, true))
    end)
end

local function formatLogToReadable()
    if not readfile or not isfile or not isfile("vicious_bee_stinger_log.txt") then
        return "No log file found"
    end
    
    local success, logData = pcall(function()
        local content = readfile("vicious_bee_stinger_log.txt")
        if content and content ~= "" then
            return HttpService:JSONDecode(content)
        end
    end)
    
    if not success or not logData then
        return "Failed to read log file"
    end
    
    local output = "=== VICIOUS BEE STINGER LOG ===\n\n"
    local currentTime = os.time()
    
    for playerName, data in pairs(logData) do
        output = output .. "Player: " .. playerName .. "\n"
        output = output .. "Field: " .. data.Field .. "\n"
        
        local timeSinceDetection = currentTime - (data.DetectionTime or 0)
        local status = (timeSinceDetection < config.stingerActiveTime) and "ACTIVE" or "NOT ACTIVE"
        
        output = output .. "Status: " .. status .. "\n"
        
        if status == "ACTIVE" then
            local remainingTime = config.stingerActiveTime - timeSinceDetection
            output = output .. "Time Remaining: " .. math.floor(remainingTime / 60) .. "m " .. (remainingTime % 60) .. "s\n"
        end
        
        output = output .. "Server Link: " .. (data.ServerLink or "N/A") .. "\n"
        output = output .. "\n"
    end
    
    return output
end

-- Auto-update status every 30 seconds
spawn(function()
    while true do
        wait(30)
        if readfile and isfile and writefile and isfile("vicious_bee_stinger_log.txt") then
            local success, logData = pcall(function()
                local content = readfile("vicious_bee_stinger_log.txt")
                if content and content ~= "" then
                    return HttpService:JSONDecode(content)
                end
            end)
            
            if success and logData then
                local currentTime = os.time()
                local updated = false
                
                for playerName, data in pairs(logData) do
                    local timeSinceDetection = currentTime - (data.DetectionTime or 0)
                    local newStatus = (timeSinceDetection < config.stingerActiveTime) and "ACTIVE" or "NOT ACTIVE"
                    
                    if data.Status ~= newStatus then
                        data.Status = newStatus
                        data.LastUpdate = currentTime
                        updated = true
                    end
                end
                
                if updated then
                    pcall(function()
                        writefile("vicious_bee_stinger_log.txt", HttpService:JSONEncode(logData, true))
                        print("🔄 Stinger log statuses updated")
                    end)
                end
            end
        end
    end
end)

local function startPlayerCountMonitoring(field, joinLink)
    config._monitoringSessionId = tick()
    local sessionId = config._monitoringSessionId
    -- 🔧 ENHANCED CLEANUP: Stop any existing monitoring COMPLETELY
    print("🔄 Starting fresh player count monitoring...")
    
    -- Force stop monitoring flag
    config._monitoringActive = false
    
    -- Disconnect PlayerAdded connection
    if config._playerMonitorConnection then
        pcall(function()
            config._playerMonitorConnection:Disconnect()
        end)
        config._playerMonitorConnection = nil
        print("✅ Cleared old PlayerAdded connection")
    end
    
    -- Disconnect PlayerRemoving connection
    if config._playerRemovingConnection then
        pcall(function()
            config._playerRemovingConnection:Disconnect()
        end)
        config._playerRemovingConnection = nil
        print("✅ Cleared old PlayerRemoving connection")
    end
    
    -- Cancel 4-minute timer
    if config._activeStatusTimer then
        pcall(function()
            task.cancel(config._activeStatusTimer)
        end)
        config._activeStatusTimer = nil
        print("✅ Cleared old 4-minute timer")
    end
    
    -- Small delay to ensure cleanup completes
    task.wait(0.1)
    
    config._monitoringActive = true
    local monitorStartTime = tick()
    local lastPlayerCount = getPlayerCount()
    local lastStatus = lastPlayerCount < config.playerCountThreshold and "ACTIVE" or "NOT ACTIVE"
    
    -- Set initial status based on player count
    updateStingerLog(player.Name, getActiveField(), lastStatus, joinLink)
    print(string.format("👥 Initial player count: %d - Status: %s", lastPlayerCount, lastStatus))
    
    -- Monitor player joins/leaves
    local function onPlayerCountChange()
        if sessionId ~= config._monitoringSessionId then return end
    task.wait() -- first yield

    if not config._monitoringActive then
        return
    end

    task.wait() -- 🔧 ADD THIS SECOND YIELD

    if not config._monitoringActive then
        return
    end
    
    local currentPlayerCount = getPlayerCount()
        local newStatus = currentPlayerCount < config.playerCountThreshold and "ACTIVE" or "NOT ACTIVE"
        -- ✅ Whitelist override
        if config._whitelistLock and currentPlayerCount >= config.playerCountThreshold then
            newStatus = "NOT ACTIVE"
        end

        
        -- Only update if status changed
        if newStatus ~= lastStatus then
            updateStingerLog(player.Name, getActiveField(), newStatus, joinLink)
            
            local changeType = currentPlayerCount > lastPlayerCount and "joined" or "left"
            print(string.format("👥 Player %s! Count: %d → Status changed to: %s", changeType, currentPlayerCount, newStatus))
            
            sendWebhook(
                "👥 Player Count Changed",
                string.format("Player count changed from **%d** to **%d**\n\nStatus updated to: **%s**", lastPlayerCount, currentPlayerCount, newStatus),
                newStatus == "ACTIVE" and 0x00FF00 or 0xFF5252,
                {
                    { name = "📊 Player Count", value = tostring(currentPlayerCount), inline = true },
                    { name = "📊 Status", value = newStatus, inline = true },
                    { name = "📍 Field", value = getActiveField(), inline = true },
                    { name = "🤖 Bot", value = player.Name, inline = true }
                }
            )
            
            lastStatus = newStatus
        end
        
        lastPlayerCount = currentPlayerCount
    end
    
    -- Connect to player events WITH DEBOUNCE
    config._playerMonitorConnection = Players.PlayerAdded:Connect(function()
        task.delay(0.5, onPlayerCountChange) -- Delay to batch rapid joins
    end)
    
    -- 🔧 STORE THIS CONNECTION GLOBALLY (NOT LOCAL!)
    config._playerRemovingConnection = Players.PlayerRemoving:Connect(function()
        task.delay(0.5, onPlayerCountChange) -- Delay to batch rapid leaves
    end)
    
    -- 4-minute timer
config._activeStatusTimer = task.delay(config.stingerActiveTime, function()
    if sessionId ~= config._monitoringSessionId then return end
    print("⏰ 4-minute monitoring window ended")
    
    -- Check if monitoring is still active (whitelist timer might have stopped it)
    if not config._monitoringActive then
        print("ℹ️ Monitoring already stopped (likely by whitelist timer)")
        return
    end
    
    -- Stop monitoring completely
    config._monitoringActive = false
    
    -- 🔧 DISCONNECT BOTH CONNECTIONS (was missing _playerRemovingConnection)
    if config._playerMonitorConnection then
        pcall(function()
            config._playerMonitorConnection:Disconnect()
        end)
        config._playerMonitorConnection = nil
    end
    
    if config._playerRemovingConnection then  -- ← ADD THIS ENTIRE BLOCK
        pcall(function()
            config._playerRemovingConnection:Disconnect()
        end)
        config._playerRemovingConnection = nil
    end
    
    -- Set final status to NOT ACTIVE
    updateStingerLog(player.Name, getActiveField(), "NOT ACTIVE", joinLink)
    
    sendWebhook(
        "⏰ Monitoring Period Ended",
        "4-minute window has expired.\n\nStatus set to: **NOT ACTIVE**",
        0xFFA500,
        {
            { name = "📍 Field", value = getActiveField(), inline = true },
            { name = "🤖 Bot", value = player.Name, inline = true },
            { name = "⏱️ Duration", value = "4 minutes", inline = true }
        }
    )
end)
    
    sendWebhook(
        "🎯 Player Count Monitoring Started",
        string.format("Monitoring player count for **4 minutes**\n\nCurrent players: **%d**\nThreshold: **%d players**\nInitial status: **%s**", lastPlayerCount, config.playerCountThreshold, lastStatus),
        0x2196F3,
        {
            { name = "📊 Current Players", value = tostring(lastPlayerCount), inline = true },
            { name = "📊 Threshold", value = tostring(config.playerCountThreshold), inline = true },
            { name = "📊 Initial Status", value = lastStatus, inline = true },
            { name = "📍 Field", value = getActiveField(), inline = true },
            { name = "⏱️ Duration", value = "4 minutes", inline = true }
        }
    )
end

-- Monitor for whitelisted players joining (GUARDED - CONNECTS ONCE ONLY)
local function handleWhitelistedJoin(joinedPlayer)
    -- ❌ Ignore whitelist joins if no stinger is active
    if not config.stingerDetected then
        return
    end

    -- 🔒 Whitelist already used for this stinger → ignore
    if config._whitelistConsumed then
        return
    end

    task.wait(0.3) -- Debounce delay to prevent replication spam
    
    -- Ignore if script stopped or monitoring not active
    if not config.isRunning then
        return
    end
    
    local playerName = joinedPlayer.Name
    
    -- 🔒 GLOBAL LOCK: Only allow ONE whitelist timer at a time
    if config._whitelistLock then
        print("🔒 Whitelist timer already active, ignoring", playerName)
        return
    end
    
    if not isPlayerWhitelisted(playerName) then
        return
    end
    
    -- 🔒 CHECK IF THIS SPECIFIC PLAYER ALREADY HAS A TIMER
    if config._whitelistTimers[playerName] then
        print("⏳ Timer already running for", playerName)
        return
    end
    
    print("⚠️ WHITELISTED PLAYER JOINED:", playerName)
    config._whitelistConsumed = true
    
    -- DO NOT lock immediately
    -- Lock only when timer expires

    
    -- Store if monitoring was active when whitelist player joined
    local monitoringWasActive = config._monitoringActive
    
    sendWebhook(
        "⚠️ Whitelisted Player Detected",
        "A whitelisted player **" .. playerName .. "** has joined the server!\n\n**Timer started: " .. config.whitelistTimer .. " seconds**\n*Will mark " .. player.Name .. " as NOT ACTIVE after timer expires*",
        0xFFFF00,
        {
            { name = "👤 Whitelisted Player", value = playerName, inline = true },
            { name = "🤖 Bot", value = player.Name, inline = true },
            { name = "⏱️ Timer", value = config.whitelistTimer .. " seconds", inline = true },
            { name = "📊 Action", value = player.Name .. " → NOT ACTIVE after " .. config.whitelistTimer .. "s", inline = false }
        }
    )
    
    -- 🔒 MARK THIS PLAYER AS HAVING AN ACTIVE TIMER
    config._whitelistTimers[playerName] = "pending"
    
    -- Start 50-second timer
    config._whitelistTimers[playerName] = task.delay(config.whitelistTimer, function()
        if not config._monitoringActive then return end
        config._whitelistLock = true
        print("⏰ 40 seconds passed - Changing", player.Name, "status to NOT ACTIVE due to", playerName, "joining")
        
        local joinLink = generateJoinLink()
        
        updateStingerLog(player.Name, getActiveField(), "NOT ACTIVE", joinLink)
        
        -- ONLY stop monitoring if it was active when whitelisted player joined
        if monitoringWasActive and config._monitoringActive then
            print("🛑 Stopping player count monitoring (whitelisted player was present)")
            
            -- FIRST: Cancel the 4-minute timer to prevent conflict
            if config._activeStatusTimer then
                task.cancel(config._activeStatusTimer)
                config._activeStatusTimer = nil
                print("🛑 Cancelled 4-minute timer (whitelist timer takes priority)")
            end
            
            -- THEN: Stop monitoring safely
            config._monitoringActive = false
            
            -- 🔧 DISCONNECT BOTH CONNECTIONS
            if config._playerMonitorConnection then
                pcall(function()
                    config._playerMonitorConnection:Disconnect()
                end)
                config._playerMonitorConnection = nil
            end
            
            if config._playerRemovingConnection then
                pcall(function()
                    config._playerRemovingConnection:Disconnect()
                end)
                config._playerRemovingConnection = nil
            end
            
            sendWebhook(
                "⏰ Whitelisted Player Timer Expired",
                "40 seconds have passed since **" .. playerName .. "** joined.\n\n**" .. player.Name .. "'s status changed to NOT ACTIVE**\n\n🛑 **Player count monitoring stopped** (stinger likely collected)",
                0xFFA500,
                {
                    { name = "⚠️ Whitelisted Player", value = playerName, inline = true },
                    { name = "🤖 Bot Affected", value = player.Name, inline = true },
                    { name = "📍 Field", value = getActiveField(), inline = true },
                    { name = "⏱️ Timer", value = config.whitelistTimer .. " seconds", inline = true },
                    { name = "📊 New Status", value = "NOT ACTIVE", inline = true },
                    { name = "🛑 Monitoring", value = "Stopped (stinger gone)", inline = true }
                }
            )
        else
            -- Monitoring wasn't active, just send status update
            sendWebhook(
                "⏰ Whitelisted Player Timer Expired",
                "40 seconds have passed since **" .. playerName .. "** joined.\n\n**" .. player.Name .. "'s status changed to NOT ACTIVE**",
                0xFFA500,
                {
                    { name = "⚠️ Whitelisted Player", value = playerName, inline = true },
                    { name = "🤖 Bot Affected", value = player.Name, inline = true },
                    { name = "📍 Field", value = getActiveField(), inline = true },
                    { name = "⏱️ Timer", value = config.whitelistTimer .. " seconds", inline = true },
                    { name = "📊 New Status", value = "NOT ACTIVE", inline = true }
                }
            )
        end
        
        config._whitelistTimers[playerName] = nil
    end)
end

-- CONNECT ONCE ONLY (prevents duplicate connections)
if not config._whitelistAddedConnection then
    config._whitelistAddedConnection = Players.PlayerAdded:Connect(handleWhitelistedJoin)
    print("✅ Whitelist PlayerAdded connection established (ONCE)")
end

-- Monitor for whitelisted players leaving (timer continues regardless)
if not config._whitelistRemovingConnection then
    config._whitelistRemovingConnection = Players.PlayerRemoving:Connect(function(leavingPlayer)
        local playerName = leavingPlayer.Name
        
        if isPlayerWhitelisted(playerName) then
            print("🚪 Whitelisted player", playerName, "left - Timer continues running")
        end
    end)
    print("✅ Whitelist PlayerRemoving connection established (ONCE)")
end

-- SMART DETECTION: Only alert ONCE per spawn event with size verification
local function onNewObject(obj)
    local now = tick()
    if now - config._lastStingerDetectionTime < config._stingerSpawnCooldown then
        return
    end

    if not config.isRunning then return end

    task.wait(0.05)

    if not obj or not obj.Parent then return end
    if not obj:IsA("BasePart") then return end
    
    if obj.Name ~= "Thorn" then return end
    
    if not verifySizeMatch(obj.Size) then
        print("⚠️ Ignored 'Thorn' with wrong size:", string.format("%.2f×%.2f×%.2f", obj.Size.X, obj.Size.Y, obj.Size.Z))
        return
    end

    local field, distance = getClosestField(obj.Position)

    if field == "Unknown" or distance > 150 then
        return
    end

    if config._detectedStingers[obj] then return end

    config._detectedStingers[obj] = true
    config._defeatReported = false
    config._lastStingerDetectionTime = now
    -- 🔄 RESET whitelist state for NEW stinger lifecycle
    config._whitelistLock = false
    config._whitelistConsumed = false
    
    -- Cancel any leftover whitelist timers (safety)
    for name, timer in pairs(config._whitelistTimers) do
        if typeof(timer) == "thread" then
            pcall(function()
                task.cancel(timer)
            end)
        end
    end
    
    config._whitelistTimers = {}
    config._defeatCheckActive = true
    config.stingerDetected = true
    config.currentField = field
    config.detectionCount = config.detectionCount + 1

    local joinLink = generateJoinLink()
    local serverTypeText = config.serverType == "Private" and "🔒 Private Server" or "🌐 Public Server"
    
    -- Start player count monitoring for 4 minutes
    startPlayerCountMonitoring(field, joinLink)
    
    local playerDistance = "Unknown"
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            playerDistance = math.floor((hrp.Position - obj.Position).Magnitude) .. " studs"
        end
    end

    local currentPlayerCount = getPlayerCount()
    local webhookFields = {
        { name = "📦 Object Name", value = obj.Name, inline = true },
        { name = "🔧 Type", value = obj.ClassName, inline = true },
        { name = "📍 Field", value = config.currentField, inline = true },
        { name = "📏 Field Distance", value = math.floor(distance) .. " studs", inline = true },
        { name = "👤 Player Distance", value = playerDistance, inline = true },
        { name = "🖥️ Server Type", value = serverTypeText, inline = true },
        { name = "📐 Size", value = string.format("%.1f×%.1f×%.1f", obj.Size.X, obj.Size.Y, obj.Size.Z), inline = true },
        { name = "✅ Size Verified", value = "Matches stinger (3×2×1.5)", inline = true },
        { name = "🧭 Position", value = string.format("(%.1f, %.1f, %.1f)", obj.Position.X, obj.Position.Y, obj.Position.Z), inline = false },
        { name = "🔢 Detection #", value = tostring(config.detectionCount), inline = true }
    }
    
    sendWebhook(
    "🎯 VICIOUS BEE STINGER DETECTED!",
    "🚨 A stinger was found!\n\n**🔗 [CLICK HERE TO JOIN THIS SERVER](" .. joinLink .. ")**\n\n**👥 Player Count Monitoring: ACTIVE (4 minutes)**",
    0xFF0000,
    webhookFields
    )

    print("🎯 VICIOUS BEE STINGER DETECTED!")
    print("📍 Field:", config.currentField)
    print("📏 Distance from field:", math.floor(distance), "studs")
    print("📐 Size:", string.format("%.1f×%.1f×%.1f", obj.Size.X, obj.Size.Y, obj.Size.Z))
    print("✅ Size verified: Matches stinger dimensions")
    print("🖥️ Server Type:", serverTypeText)
    print("🔗 Join Link:", joinLink)
    print("🔢 Detection count:", config.detectionCount)
    print("🔐 Log sent with webhook secret token")
    print("⚠️ Whitelist system: Active (monitors for whitelisted players joining)")

    obj.AncestryChanged:Connect(function()
        if not obj.Parent then
            -- 🔒 Per-object dedupe
            if config._detectedStingers[obj] == "defeated" then
                return
            end
    
            -- 🔒 Global dedupe
            if config._defeatReported then
                return
            end
    
            config._defeatReported = true
            config._detectedStingers[obj] = "defeated"
    
            print("⚠️ Stinger removed from workspace")
    
            config.stingerDetected = false
    
            local joinLink = generateJoinLink()
    
            local defeatedField = getActiveField()

            updateStingerLog(player.Name, defeatedField, "NOT ACTIVE", joinLink)
            
            -- Reset AFTER sending
            config.currentField = "None"
    
            sendWebhook(
                "🏆 Vicious Bee Defeated!",
                "The stinger at **"..defeatedField.."** has been removed from the workspace!\n\nStatus set to **NOT ACTIVE**",
                0x00FF00,
                {
                    { name = "🤖 Bot", value = player.Name, inline = true },
                    { name = "📍 Field", value = defeatedField, inline = true },
                    { name = "🔗 Join Link", value = joinLink, inline = false },
                    { name = "⏱️ Time", value = os.date("%X"), inline = true }
                }
            )
    
            -- 🔹 Stop monitoring
            config._defeatCheckActive = false
            if config._monitoringActive then
                print("🛑 Stopping player monitoring (stinger defeated)...")
                config._monitoringActive = false
                
                -- Disconnect PlayerAdded
                if config._playerMonitorConnection then
                    pcall(function() 
                        config._playerMonitorConnection:Disconnect() 
                    end)
                    config._playerMonitorConnection = nil
                    print("✅ Disconnected PlayerAdded")
                end
                
                -- Disconnect PlayerRemoving
                if config._playerRemovingConnection then
                    pcall(function() 
                        config._playerRemovingConnection:Disconnect() 
                    end)
                    config._playerRemovingConnection = nil
                    print("✅ Disconnected PlayerRemoving")
                end
                
                -- Cancel 4-minute timer
                if config._activeStatusTimer then
                    pcall(function()
                        task.cancel(config._activeStatusTimer)
                    end)
                    config._activeStatusTimer = nil
                    print("✅ Cancelled 4-minute timer")
                end
                    
                print("🛑 Player monitoring stopped (stinger defeated)")
            end
    
            -- 🔹 Clear whitelist timers (INCLUDING ACTIVE ONES)
            config._whitelistLock = false
            config._whitelistConsumed = false
            
            -- ✅ CANCEL ALL ACTIVE WHITELIST TIMERS
            for name, timer in pairs(config._whitelistTimers) do
                if typeof(timer) == "thread" then
                    pcall(function()
                        task.cancel(timer)
                    end)
                    print("🛑 Cancelled whitelist timer for", name)
                end
            end
            config._whitelistTimers = {}
            print("🔄 Whitelist timers cleared")
            print("🔁 Resuming server hopping...")
            task.delay(5, function()
                if config.isRunning then
                    config.stingerDetected = false
                    hopRandomServer()
                end
            end)
        end
    end)
end

local function createGUI()
    task.delay(4, function()
        if not config.isRunning then
            print("🔁 Auto-starting detection...")
            config.isRunning = true
            for _, obj in ipairs(Workspace:GetDescendants()) do
                onNewObject(obj)
            end
    
            end
        end
    end)

    if CoreGui:FindFirstChild("ViciousBeeHunterGUI") then
        CoreGui:FindFirstChild("ViciousBeeHunterGUI"):Destroy()
    end
    
    local ScreenGui = Instance.new("ScreenGui")
    local MainFrame = Instance.new("Frame")
    local Title = Instance.new("TextLabel")
    local WebhookBox = Instance.new("TextBox")
    local PCServerBox = Instance.new("TextBox")
    local PCServerLabel = Instance.new("TextLabel")
    local WebhookSecretBox = Instance.new("TextBox")
    local WebhookSecretLabel = Instance.new("TextLabel")
    local WhitelistLabel = Instance.new("TextLabel")
    local WhitelistSlots = {}
    local ServerTypeLabel = Instance.new("TextLabel")
    local PublicButton = Instance.new("TextButton")
    local PrivateButton = Instance.new("TextButton")
    local PrivateServerBox = Instance.new("TextBox")
    local StartButton = Instance.new("TextButton")
    local StatusLabel = Instance.new("TextLabel")
    local FieldLabel = Instance.new("TextLabel")
    local InfoLabel = Instance.new("TextLabel")
    local CloseButton = Instance.new("TextButton")
    local PositionLabel = Instance.new("TextLabel")
    local DetectionCountLabel = Instance.new("TextLabel")
    local AntiIdleLabel = Instance.new("TextLabel")
    local ViewLogButton = Instance.new("TextButton")
    local WhitelistInfoLabel = Instance.new("TextLabel")
    
    ScreenGui.Name = "ViciousBeeHunterGUI"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    MainFrame.BorderSizePixel = 0
    MainFrame.Position = UDim2.new(0.5, -200, 0.5, -450)
    MainFrame.Size = UDim2.new(0, 400, 0, 950)
    MainFrame.Active = true
    MainFrame.Draggable = true
    
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
    
    Title.Parent = MainFrame
    Title.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
    Title.Size = UDim2.new(1, 0, 0, 50)
    Title.Font = Enum.Font.GothamBold
    Title.Text = "🐝 Vicious Bee Detector v3.8 👥"
    Title.TextColor3 = Color3.fromRGB(20, 20, 20)
    Title.TextSize = 17
    
    Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 12)
    
    CloseButton.Parent = MainFrame
    CloseButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    CloseButton.Position = UDim2.new(1, -35, 0, 10)
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.TextSize = 16
    
    Instance.new("UICorner", CloseButton)
    
    WebhookBox.Parent = MainFrame
    WebhookBox.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    WebhookBox.Position = UDim2.new(0, 20, 0, 70)
    WebhookBox.Size = UDim2.new(1, -40, 0, 40)
    WebhookBox.Font = Enum.Font.Gotham
    WebhookBox.PlaceholderText = "Enter Discord Webhook URL..."
    WebhookBox.Text = config.webhookUrl
    WebhookBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    WebhookBox.TextSize = 14
    WebhookBox.ClearTextOnFocus = false
    
    Instance.new("UICorner", WebhookBox).CornerRadius = UDim.new(0, 8)
    
    PCServerLabel.Parent = MainFrame
    PCServerLabel.BackgroundTransparency = 1
    PCServerLabel.Position = UDim2.new(0, 20, 0, 120)
    PCServerLabel.Size = UDim2.new(1, -40, 0, 20)
    PCServerLabel.Font = Enum.Font.GothamBold
    PCServerLabel.Text = "PC Server URL (for log file):"
    PCServerLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
    PCServerLabel.TextSize = 12
    PCServerLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    PCServerBox.Parent = MainFrame
    PCServerBox.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    PCServerBox.Position = UDim2.new(0, 20, 0, 145)
    PCServerBox.Size = UDim2.new(1, -40, 0, 40)
    PCServerBox.Font = Enum.Font.Gotham
    PCServerBox.PlaceholderText = "https://YOUR-NGROK-URL.ngrok-free.app/log"
    PCServerBox.Text = config.pcServerUrl
    PCServerBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    PCServerBox.TextSize = 13
    PCServerBox.ClearTextOnFocus = false
    
    Instance.new("UICorner", PCServerBox).CornerRadius = UDim.new(0, 8)
    
    WebhookSecretLabel.Parent = MainFrame
    WebhookSecretLabel.BackgroundTransparency = 1
    WebhookSecretLabel.Position = UDim2.new(0, 20, 0, 195)
    WebhookSecretLabel.Size = UDim2.new(1, -40, 0, 20)
    WebhookSecretLabel.Font = Enum.Font.GothamBold
    WebhookSecretLabel.Text = "🔐 Webhook Secret Token:"
    WebhookSecretLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    WebhookSecretLabel.TextSize = 12
    WebhookSecretLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    WebhookSecretBox.Parent = MainFrame
    WebhookSecretBox.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    WebhookSecretBox.Position = UDim2.new(0, 20, 0, 220)
    WebhookSecretBox.Size = UDim2.new(1, -40, 0, 40)
    WebhookSecretBox.Font = Enum.Font.Gotham
    WebhookSecretBox.PlaceholderText = "Enter secret token (must match server)..."
    WebhookSecretBox.Text = config.webhookSecret ~= "" and config.webhookSecret or ""
    WebhookSecretBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    WebhookSecretBox.TextSize = 13
    WebhookSecretBox.ClearTextOnFocus = false
    
    Instance.new("UICorner", WebhookSecretBox).CornerRadius = UDim.new(0, 8)
    
    WhitelistLabel.Parent = MainFrame
    WhitelistLabel.BackgroundTransparency = 1
    WhitelistLabel.Position = UDim2.new(0, 20, 0, 275)
    WhitelistLabel.Size = UDim2.new(1, -40, 0, 20)
    WhitelistLabel.Font = Enum.Font.GothamBold
    WhitelistLabel.Text = "⚠️ Whitelist (Auto NOT ACTIVE after 40s):"
    WhitelistLabel.TextColor3 = Color3.fromRGB(255, 150, 50)
    WhitelistLabel.TextSize = 12
    WhitelistLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    for i = 1, 5 do
        local slot = Instance.new("TextBox")
        slot.Parent = MainFrame
        slot.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
        slot.Position = UDim2.new(0, 20, 0, 295 + (i - 1) * 35)
        slot.Size = UDim2.new(1, -40, 0, 30)
        slot.Font = Enum.Font.Gotham
        slot.PlaceholderText = "Player Name #" .. i
        slot.Text = config.whitelistPlayers[i]
        slot.TextColor3 = Color3.fromRGB(255, 255, 255)
        slot.TextSize = 12
        slot.ClearTextOnFocus = false
        slot.Name = "WhitelistSlot" .. i
        
        Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)
        
        WhitelistSlots[i] = slot
        
        slot.FocusLost:Connect(function()
            config.whitelistPlayers[i] = slot.Text
            if writefile then
                writefile("vicious_bee_whitelist.txt", HttpService:JSONEncode(config.whitelistPlayers))
                print("✅ Whitelist saved:", table.concat(config.whitelistPlayers, ", "))
            end
        end)
    end
    
    WhitelistInfoLabel.Parent = MainFrame
    WhitelistInfoLabel.BackgroundTransparency = 1
    WhitelistInfoLabel.Position = UDim2.new(0, 20, 0, 475)
    WhitelistInfoLabel.Size = UDim2.new(1, -40, 0, 30)
    WhitelistInfoLabel.Font = Enum.Font.Gotham
    WhitelistInfoLabel.Text = "ℹ️ Only 1st whitelisted player join triggers 40s timer"
    WhitelistInfoLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    WhitelistInfoLabel.TextSize = 10
    WhitelistInfoLabel.TextWrapped = true
    WhitelistInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    ServerTypeLabel.Parent = MainFrame
    ServerTypeLabel.BackgroundTransparency = 1
    ServerTypeLabel.Position = UDim2.new(0, 20, 0, 515)
    ServerTypeLabel.Size = UDim2.new(1, -40, 0, 20)
    ServerTypeLabel.Font = Enum.Font.GothamBold
    ServerTypeLabel.Text = "Server Type:"
    ServerTypeLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
    ServerTypeLabel.TextSize = 13
    ServerTypeLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    PublicButton.Parent = MainFrame
    PublicButton.BackgroundColor3 = config.serverType == "Public" and Color3.fromRGB(50, 150, 255) or Color3.fromRGB(60, 60, 65)
    PublicButton.Position = UDim2.new(0, 20, 0, 540)
    PublicButton.Size = UDim2.new(0.48, -15, 0, 35)
    PublicButton.Font = Enum.Font.GothamBold
    PublicButton.Text = "🌐 Public Server"
    PublicButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    PublicButton.TextSize = 14
    
    Instance.new("UICorner", PublicButton).CornerRadius = UDim.new(0, 8)
    
    PrivateButton.Parent = MainFrame
    PrivateButton.BackgroundColor3 = config.serverType == "Private" and Color3.fromRGB(50, 150, 255) or Color3.fromRGB(60, 60, 65)
    PrivateButton.Position = UDim2.new(0.52, 5, 0, 540)
    PrivateButton.Size = UDim2.new(0.48, -15, 0, 35)
    PrivateButton.Font = Enum.Font.GothamBold
    PrivateButton.Text = "🔒 Private Server"
    PrivateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    PrivateButton.TextSize = 14
    
    Instance.new("UICorner", PrivateButton).CornerRadius = UDim.new(0, 8)
    
    PrivateServerBox.Parent = MainFrame
    PrivateServerBox.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    PrivateServerBox.Position = UDim2.new(0, 20, 0, 585)
    PrivateServerBox.Size = UDim2.new(1, -40, 0, 40)
    PrivateServerBox.Font = Enum.Font.Gotham
    PrivateServerBox.PlaceholderText = "Paste Private Server Link Here..."
    PrivateServerBox.Text = config.privateServerLink
    PrivateServerBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    PrivateServerBox.TextSize = 13
    PrivateServerBox.ClearTextOnFocus = false
    PrivateServerBox.Visible = config.serverType == "Private"
    
    Instance.new("UICorner", PrivateServerBox).CornerRadius = UDim.new(0, 8)
    
    StartButton.Parent = MainFrame
    StartButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    StartButton.Position = UDim2.new(0, 20, 0, 635)
    StartButton.Size = UDim2.new(1, -40, 0, 45)
    StartButton.Font = Enum.Font.GothamBold
    StartButton.Text = "START DETECTING"
    StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    StartButton.TextSize = 16
    
    Instance.new("UICorner", StartButton).CornerRadius = UDim.new(0, 8)
    
    StatusLabel.Parent = MainFrame
    StatusLabel.Name = "StatusLabel"
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Position = UDim2.new(0, 20, 0, 695)
    StatusLabel.Size = UDim2.new(1, -40, 0, 25)
    StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.Text = "Status: Idle"
    StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    StatusLabel.TextSize = 14
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    FieldLabel.Parent = MainFrame
    FieldLabel.Name = "FieldLabel"
    FieldLabel.BackgroundTransparency = 1
    FieldLabel.Position = UDim2.new(0, 20, 0, 720)
    FieldLabel.Size = UDim2.new(1, -40, 0, 25)
    FieldLabel.Font = Enum.Font.Gotham
    FieldLabel.Text = "Field: Waiting..."
    FieldLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    FieldLabel.TextSize = 13
    FieldLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    DetectionCountLabel.Parent = MainFrame
    DetectionCountLabel.Name = "DetectionCountLabel"
    DetectionCountLabel.BackgroundTransparency = 1
    DetectionCountLabel.Position = UDim2.new(0, 20, 0, 745)
    DetectionCountLabel.Size = UDim2.new(1, -40, 0, 25)
    DetectionCountLabel.Font = Enum.Font.Gotham
    DetectionCountLabel.Text = "Detections: 0"
    DetectionCountLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    DetectionCountLabel.TextSize = 13
    DetectionCountLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    AntiIdleLabel.Parent = MainFrame
    AntiIdleLabel.Name = "AntiIdleLabel"
    AntiIdleLabel.BackgroundTransparency = 1
    AntiIdleLabel.Position = UDim2.new(0, 20, 0, 770)
    AntiIdleLabel.Size = UDim2.new(1, -40, 0, 25)
    AntiIdleLabel.Font = Enum.Font.Gotham
    AntiIdleLabel.Text = "🔄 Anti-Idle: Active"
    AntiIdleLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    AntiIdleLabel.TextSize = 13
    AntiIdleLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    InfoLabel.Parent = MainFrame
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Position = UDim2.new(0, 20, 0, 800)
    InfoLabel.Size = UDim2.new(1, -40, 0, 25)
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.Text = "🔐 Secured | Whitelist: 40s timer"
    InfoLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    InfoLabel.TextSize = 11
    InfoLabel.TextWrapped = true
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left

    PositionLabel.Name = "PositionLabel"
    PositionLabel.Parent = MainFrame
    PositionLabel.BackgroundTransparency = 1
    PositionLabel.Position = UDim2.new(0, 20, 0, 830)
    PositionLabel.Size = UDim2.new(1, -40, 0, 25)
    PositionLabel.Font = Enum.Font.Gotham
    PositionLabel.Text = "Position: Waiting..."
    PositionLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    PositionLabel.TextSize = 13
    PositionLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    ViewLogButton.Parent = MainFrame
    ViewLogButton.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
    ViewLogButton.Position = UDim2.new(0, 20, 0, 860)
    ViewLogButton.Size = UDim2.new(1, -40, 0, 35)
    ViewLogButton.Font = Enum.Font.GothamBold
    ViewLogButton.Text = "📋 VIEW STINGER LOG"
    ViewLogButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    ViewLogButton.TextSize = 14
    
    Instance.new("UICorner", ViewLogButton).CornerRadius = UDim.new(0, 8)

    -- Player Count Label (LIVE DISPLAY)
    local PlayerCountLabel = Instance.new("TextLabel")
    PlayerCountLabel.Parent = MainFrame
    PlayerCountLabel.Name = "PlayerCountLabel"
    PlayerCountLabel.BackgroundTransparency = 1
    PlayerCountLabel.Position = UDim2.new(0, 20, 0, 905)  -- Below ViewLogButton
    PlayerCountLabel.Size = UDim2.new(1, -40, 0, 25)
    PlayerCountLabel.Font = Enum.Font.Gotham
    PlayerCountLabel.Text = "👥 Players: " .. getPlayerCount()
    PlayerCountLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    PlayerCountLabel.TextSize = 13
    PlayerCountLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Button handlers
    PublicButton.MouseButton1Click:Connect(function()
        config.serverType = "Public"
        PublicButton.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
        PrivateButton.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
        PrivateServerBox.Visible = false
        
        if writefile then
            writefile("vicious_bee_serverconfig.txt", HttpService:JSONEncode({
                serverType = config.serverType,
                privateServerLink = config.privateServerLink
            }))
            print("✅ Server type set to Public")
        end
    end)
    
    PrivateButton.MouseButton1Click:Connect(function()
        config.serverType = "Private"
        PrivateButton.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
        PublicButton.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
        PrivateServerBox.Visible = true
        
        if writefile then
            writefile("vicious_bee_serverconfig.txt", HttpService:JSONEncode({
                serverType = config.serverType,
                privateServerLink = config.privateServerLink
            }))
            print("✅ Server type set to Private")
        end
    end)
    
    PrivateServerBox.FocusLost:Connect(function()
        config.privateServerLink = PrivateServerBox.Text
        if writefile then
            writefile("vicious_bee_serverconfig.txt", HttpService:JSONEncode({
                serverType = config.serverType,
                privateServerLink = config.privateServerLink
            }))
            print("✅ Private server link saved")
        end
    end)
    
    WebhookBox.FocusLost:Connect(function()
        if writefile then
            writefile("vicious_bee_webhook.txt", WebhookBox.Text)
        end
    end)
    
    PCServerBox.FocusLost:Connect(function()
        config.pcServerUrl = PCServerBox.Text
        if writefile then
            writefile("vicious_bee_pcserver.txt", PCServerBox.Text)
            print("✅ PC server URL saved:", config.pcServerUrl)
        end
    end)
    
    WebhookSecretBox.FocusLost:Connect(function()
        config.webhookSecret = WebhookSecretBox.Text
        if writefile then
            writefile("vicious_bee_secret.txt", WebhookSecretBox.Text)
            print("✅ Webhook secret saved (KEEP THIS SECRET!)")
        end
    end)
    
    StartButton.MouseButton1Click:Connect(function()
        if not config.isRunning then
            local webhook = WebhookBox.Text
            if webhook == "" or not webhook:match("^https://discord%.com/api/webhooks/") then
                StatusLabel.Text = "Status: ❌ Invalid Webhook URL"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                return
            end
            
            if config.webhookSecret == "" then
                StatusLabel.Text = "Status: ❌ Set webhook secret token first!"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                return
            end
            
            if config.serverType == "Private" and (config.privateServerLink == "" or not config.privateServerLink:match("^https://")) then
                StatusLabel.Text = "Status: ❌ Invalid Private Server Link"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
                return
            end
            
            config.webhookUrl = webhook
            
            if writefile then
                writefile("vicious_bee_webhook.txt", webhook)
                print("✅ Webhook saved")
            end
            
            config.isRunning = true
            
                print("✅ Monitoring Workspace for 'Thorn' parts with size 3×2×1.5...")
            end
            
            StartButton.Text = "STOP DETECTING"
            StartButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            StatusLabel.Text = "Status: 👀 Watching (SECURED)"
            StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            
            local serverTypeText = config.serverType == "Private" and "🔒 Private Server" or "🌐 Public Server"
            
            
            print("🎯 DETECTION ACTIVE - Watching for 'Thorn' parts with size 3×2×1.5...")
            print("🔄 Anti-idle system is active!")
            print("🖥️ Server Type:", serverTypeText)
            print("🔐 Webhook secret token is configured")
            print("⚠️ Whitelist system active - 40s timer on whitelisted player join")
        else
            config.isRunning = false
            
            if config._descendantConnection then
                config._descendantConnection:Disconnect()
                config._descendantConnection = nil
                print("✅ Stopped monitoring")
            end
            -- Stop player count monitoring if active
            config._monitoringActive = false
            if config._playerMonitorConnection then
                config._playerMonitorConnection:Disconnect()
                config._playerMonitorConnection = nil
            end
            if config._playerRemovingConnection then
                config._playerRemovingConnection:Disconnect()
                config._playerRemovingConnection = nil
            end
            if config._activeStatusTimer then
                task.cancel(config._activeStatusTimer)
                config._activeStatusTimer = nil
            end
            
            StartButton.Text = "START DETECTING"
            StartButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
            StatusLabel.Text = "Status: Stopped"
            StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            FieldLabel.Text = "Field: Waiting..."
            FieldLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
    end)
    
    CloseButton.MouseButton1Click:Connect(function()
        config.isRunning = false
        if config._descendantConnection then
            config._descendantConnection:Disconnect()
        end
        if config._activeStatusTimer then
            task.cancel(config._activeStatusTimer)
        end
        ScreenGui:Destroy()
    end)
    
    ViewLogButton.MouseButton1Click:Connect(function()
        local logContent = formatLogToReadable()
        print("\n" .. logContent)
        
        StatusLabel.Text = "Status: 📋 Log printed to console!"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
        
        task.wait(2)
        if config.isRunning then
            StatusLabel.Text = "Status: 👀 Watching (SECURED)"
            StatusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            StatusLabel.Text = "Status: Idle"
            StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end)
    
    -- Update GUI labels in real-time
    if config._renderConnection then
        config._renderConnection:Disconnect()
    end

    config._renderConnection = RunService.RenderStepped:Connect(function()
        local gui = CoreGui:FindFirstChild("ViciousBeeHunterGUI")
        if not gui then return end
        
        local mainFrame = gui:FindFirstChild("MainFrame")
        if not mainFrame then return end
        
        -- Update player count label
        local playerCountLabel = mainFrame:FindFirstChild("PlayerCountLabel")
        if playerCountLabel then
            local monitoring = config._monitoringActive and " (MONITORING)" or ""
            playerCountLabel.Text = "👥 Players: " .. getPlayerCount() .. monitoring
            playerCountLabel.TextColor3 = config._monitoringActive and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
        end
        
        -- Update position label
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local pos = char.HumanoidRootPart.Position
            local posLabel = mainFrame:FindFirstChild("PositionLabel")
            if posLabel then
                posLabel.Text = string.format("Position: (%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z)
            end
        end
        
        -- Update field label
        local fieldLabel = mainFrame:FindFirstChild("FieldLabel")
        if fieldLabel then
            if config.stingerDetected and config.currentField ~= "None" then
                fieldLabel.Text = "Field: 🎯 " .. config.currentField
                fieldLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                -- ✅ RESET WHEN NO STINGER
                fieldLabel.Text = "Field: Waiting..."
                fieldLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
        end
        
        -- Update detection count label
        local countLabel = mainFrame:FindFirstChild("DetectionCountLabel")
        if countLabel then
            countLabel.Text = "Detections: " .. config.detectionCount
        end
    end)
end

        

print("🐝 Vicious Bee Stinger Detector v3.8 Loaded!")
print("📱 Opening GUI...")
print("🎯 This script detects 'Thorn' parts (Size: 3×2×1.5) spawning near fields!")
print("🔄 Anti-idle system enabled!")
print("🖥️ Server Type:", config.serverType)
print("✅ Size verification active: Only detects stingers with exact size 3.0×2.0×1.5")
print("🔐 SECURITY: Webhook secret token system enabled!")
print("⚠️ Whitelist system active - 40s timer on first whitelisted player join")
print("⚠️ IMPORTANT: Set your webhook secret token before starting!")
createGUI()
