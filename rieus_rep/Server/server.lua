-- ============================================================================
-- GANG REPUTATION ITEM SYSTEM - SERVER SIDE
-- ============================================================================
-- All validation and brutal_gangs integration happens here
-- Ensures security and prevents exploits

local GangRepSystem = {}
local PlayerCooldowns = {}
local QBCore = nil
local ESX = nil
local PendingGangInfoCallbacks = {} -- Store callbacks for gang info requests

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Debug logging
-- @param message string Message to log
local function DebugLog(message)
    if Config.DebugMode then
        print("^5[Gang Rep System - Server]^7 " .. message)
    end
end

--- Send webhook notification
-- @param title string Webhook embed title
-- @param description string Webhook embed description
-- @param color number Hex color code (e.g., 3092272 for green)
-- @param fields table Optional fields array for detailed info
local function SendWebhook(title, description, color, fields)
    DebugLog(("[SendWebhook] Checking conditions - Enabled: %s, URL exists: %s"):format(tostring(Config.WebhookEnabled), tostring(Config.WebhookURL ~= nil)))
    
    if not Config.WebhookEnabled then
        DebugLog("[SendWebhook] Webhooks disabled in config")
        return
    end
    
    if not Config.WebhookURL or Config.WebhookURL == "" then
        DebugLog("[SendWebhook] No webhook URL configured")
        return
    end
    
    if Config.WebhookURL == "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN" then
        DebugLog("[SendWebhook] Webhook URL is still placeholder")
        return
    end

    local embed = {
        title = title,
        description = description,
        color = color or 3092272,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer = {
            text = "Gang Rep System"
        }
    }

    if fields and #fields > 0 then
        embed.fields = fields
    end

    DebugLog(("[SendWebhook] Sending webhook: %s"):format(title))
    PerformHttpRequest(Config.WebhookURL, function(statusCode, response, headers)
        DebugLog(("[SendWebhook] Response status: %d"):format(statusCode))
        if statusCode ~= 204 then
            DebugLog("Webhook request failed with status: " .. statusCode)
        else
            DebugLog("[SendWebhook] Webhook sent successfully")
        end
    end, 'POST', json.encode({
        embeds = { embed }
    }), {
        ['Content-Type'] = 'application/json'
    })
end

--- Check player permission level
-- @param source number Player source/ID
-- @return boolean True if player has admin permission
local function HasAdminPermission(source)
    -- For qb-core
    if GetResourceState('qb-core') == 'started' then
        local player = exports['qb-core']:GetPlayer(source)
        if player then
            local job = player.PlayerData.job.name
            DebugLog(("Player %d job: %s"):format(source, job))
            return job == Config.AdminPermissionGroup or player.PlayerData.job.isboss
        end
    end

    -- For ESX
    if GetResourceState('es_extended') == 'started' then
        local xPlayer = exports['es_extended']:xPlayer(source)
        if xPlayer then
            local job = xPlayer.getJob().name
            DebugLog(("Player %d job: %s"):format(source, job))
            return job == Config.AdminPermissionGroup
        end
    end

    return false
end

--- Get player name for logging
-- @param source number Player source/ID
-- @return string Player name or "Unknown"
local function GetPlayerName(source)
    local playerName = GetPlayerName(source)
    return playerName or ("Player#%d"):format(source)
end

--- Notify player
-- @param source number Player source/ID
-- @param title string Notification title
-- @param message string Notification message
local function NotifyPlayer(source, title, message)
    TriggerClientEvent('gangRep:itemUsedError', source, message)
end

--- Notify player of success
-- @param source number Player source/ID
-- @param itemName string Item name
-- @param gangName string Gang name
-- @param reputation number Reputation amount
-- @param gangMoney number Optional gang money amount
local function NotifyPlayerSuccess(source, itemName, gangName, reputation, gangMoney)
    TriggerClientEvent('gangRep:itemUsedSuccess', source, itemName, gangName, reputation, gangMoney)
end

--- Check if player is on cooldown (server-side anti-spam)
-- @param source number Player source/ID
-- @param item string Item name
-- @return boolean True if on cooldown
local function IsOnCooldown(source, item)
    if not Config.EnableCooldown then return false end

    if not PlayerCooldowns[source] then
        PlayerCooldowns[source] = {}
    end

    if PlayerCooldowns[source][item] then
        local remainingTime = PlayerCooldowns[source][item] - GetGameTimer()
        if remainingTime > 0 then
            DebugLog(("Player %d is on cooldown for item %s"):format(source, item))
            return true
        end
    end

    return false
end

--- Set cooldown for player on item (server-side anti-spam)
-- @param source number Player source/ID
-- @param item string Item name
-- @param cooldown number Cooldown duration in seconds
local function SetCooldown(source, item, cooldown)
    if not Config.EnableCooldown or cooldown == 0 then return end

    if not PlayerCooldowns[source] then
        PlayerCooldowns[source] = {}
    end

    PlayerCooldowns[source][item] = GetGameTimer() + (cooldown * 1000)
    DebugLog(("Set cooldown for player %d on item %s for %d seconds"):format(source, item, cooldown))
end

--- Check if player has item in inventory
-- @param source number Player source/ID
-- @param itemName string Item name
-- @return boolean True if player has item
local function HasItem(source, itemName)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local item = Player.Functions.GetItemByName(itemName)
            return item ~= nil and item.amount > 0
        end
    end

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local item = xPlayer.getInventoryItem(itemName)
            return item ~= nil and item.count > 0
        end
    end

    return false
end

--- Remove item from player inventory
-- @param source number Player source/ID
-- @param itemName string Item name
-- @param amount number Amount to remove
-- @return boolean Success
local function RemoveItem(source, itemName, amount)
    amount = amount or 1

    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.Functions.RemoveItem(itemName, amount)
        end
    end

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(itemName, amount)
            return true
        end
    end

    return false
end

--- Get item quantity in player inventory
-- @param source number Player source/ID
-- @param itemName string Item name
-- @return number Amount of item, 0 if not found
local function GetItemAmount(source, itemName)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local item = Player.Functions.GetItemByName(itemName)
            return item and item.amount or 0
        end
    end

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local item = xPlayer.getInventoryItem(itemName)
            return item and item.count or 0
        end
    end

    return 0
end

-- ============================================================================
-- FRAMEWORK INITIALIZATION
-- ============================================================================

if GetResourceState('qb-core') == 'started' then
    QBCore = exports['qb-core']:GetCoreObject()
    DebugLog("QBCore detected and loaded")
end

if GetResourceState('es_extended') == 'started' then
    ESX = exports['es_extended']:getSharedObject()
    DebugLog("ESX detected and loaded")
end

-- ============================================================================
-- BRUTAL_GANGS INTEGRATION
-- ============================================================================

--- Check if player is in a gang
-- @param source number Player source/ID
-- @return boolean True if player is in a gang
local function IsPlayerInGang(source)
    local gangName = exports["brutal_gangs"]:GetPlayerGangName(source)
    local inGang = gangName ~= nil and gangName ~= false and gangName ~= ""
    DebugLog(("Player %d gang check result: %s (gang: %s)"):format(source, tostring(inGang), gangName or "None"))
    return inGang
end

--- Get player's gang name
-- @param source number Player source/ID
-- @return string Gang name or nil
local function GetPlayerGangName(source)
    local gangName = exports["brutal_gangs"]:GetPlayerGangName(source)
    DebugLog(("Player %d gang name: %s"):format(source, gangName or "None"))
    return gangName
end

--- Get player's gang rank from client using brutal_gangs export
-- @param source number Player source/ID
-- @param callback function Callback with gangInfo {isInGang, gangRank}
local function RequestGangInfoFromClient(source, callback)
    if not callback then return end
    
    DebugLog(("Requesting gang info from client %d..."):format(source))
    
    -- Store callback with timeout
    local requestId = source .. "_" .. os.time()
    PendingGangInfoCallbacks[requestId] = {
        callback = callback,
        source = source,
        time = os.time()
    }
    
    -- Request from client
    TriggerClientEvent('gangRep:requestGangInfo', source)
    
    -- Timeout after 5 seconds
    SetTimeout(5000, function()
        if PendingGangInfoCallbacks[requestId] then
            DebugLog(("Gang info request timed out for player %d"):format(source))
            PendingGangInfoCallbacks[requestId] = nil
            callback(nil)
        end
    end)
end

--- Get player's gang rank
-- @param source number Player source/ID
-- @return number Player's grade in gang or nil
local function GetPlayerGangRank(source)
    local rank = nil
    
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player and Player.PlayerData and Player.PlayerData.job then
            rank = Player.PlayerData.job.grade and Player.PlayerData.job.grade.level
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            rank = xPlayer.job.grade
        end
    end
    
    DebugLog(("Player %d gang rank/grade: %s"):format(source, rank or "None"))
    return rank
end

--- Get all gangs and their data
-- @return table Gangs table or empty table
local function GetGangsData()
    local success, gangs = pcall(function()
        return exports["brutal_gangs"]:GetGangs()
    end)
    
    if not success then
        DebugLog(("Error getting gangs data: %s"):format(tostring(gangs)))
        return {}
    end
    
    if not gangs then
        DebugLog("GetGangs returned nil")
        return {}
    end
    
    -- brutal_gangs might return a table with gang names as keys, not array
    local gangCount = 0
    for k, v in pairs(gangs) do
        gangCount = gangCount + 1
        DebugLog(("Gang found: %s (type: %s)"):format(tostring(k), type(v)))
    end
    
    DebugLog(("Retrieved gangs data, total gangs: %d"):format(gangCount))
    return gangs or {}
end

--- Find the leader rank of a gang (highest grade)
-- @param gangName string Gang name
-- @return number Leader rank or nil
local function GetGangLeaderRank(gangName)
    local gangs = GetGangsData()

    if not gangs or (type(gangs) == "table" and next(gangs) == nil) then
        DebugLog("No gangs data available from brutal_gangs")
        return nil
    end

    -- Try array format first (ipairs)
    for _, gang in ipairs(gangs) do
        if gang.name == gangName or gang.job == gangName then
            local leaderRank = gang.leader or (gang.grades and gang.grades[#gang.grades])
            DebugLog(("Gang %s leader rank from array: %s"):format(gangName, tostring(leaderRank)))
            return leaderRank
        end
    end
    
    -- Try key-value format (pairs) - brutal_gangs uses gang name as key
    for gangKey, gangData in pairs(gangs) do
        if gangKey == gangName or (gangData.name == gangName) or (gangData.job == gangName) then
            -- Find highest grade
            if gangData.grades then
                local maxGrade = 0
                for gradeName, gradeData in pairs(gangData.grades) do
                    local gradeLevel = gradeData.level or gradeData.grade or tonumber(gradeName) or 0
                    if gradeLevel > maxGrade then
                        maxGrade = gradeLevel
                    end
                end
                DebugLog(("Gang %s leader rank from key-value (max grade): %d"):format(gangName, maxGrade))
                return maxGrade
            end
            DebugLog(("Gang %s found but no grades data"):format(gangName))
            return nil
        end
    end

    DebugLog(("Gang %s not found in brutal_gangs data"):format(gangName))
    return nil
end

--- Check if player is a gang leader
-- @param source number Player source/ID
-- @param gangName string Gang name
-- @param playerRank number/string Player's current rank/grade (can be string name or number)
-- @return boolean True if player is leader
local function IsPlayerLeader(source, gangName, playerRank)
    -- Handle string rank names (brutal_gangs client export returns rank name)
    if type(playerRank) == "string" then
        local rankLower = playerRank:lower()
        if rankLower:find("leader") or rankLower:find("boss") or rankLower:find("chief") or rankLower:find("capo") then
            DebugLog(("Player %d is leader based on rank name: %s"):format(source, playerRank))
            return true
        end
    end
    
    -- Handle numeric ranks
    if type(playerRank) == "number" then
        -- Method 1: Check if player is boss in their job (QBCore/ESX)
        if QBCore then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player and Player.PlayerData and Player.PlayerData.job then
                if Player.PlayerData.job.isboss then
                    DebugLog(("Player %d is boss according to QBCore"):format(source))
                    return true
                end
            end
        elseif ESX then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer and xPlayer.job then
                -- ESX doesn't have isboss, use grade name check
                if xPlayer.job.grade_name and (xPlayer.job.grade_name:lower():find("boss") or xPlayer.job.grade_name:lower():find("leader")) then
                    DebugLog(("Player %d is boss/leader according to ESX grade name"):format(source))
                    return true
                end
            end
        end
        
        -- Method 2: Try to get leader rank from brutal_gangs
        local leaderRank = GetGangLeaderRank(gangName)
        if leaderRank and playerRank then
            local isLeader = playerRank >= leaderRank
            DebugLog(("Player %d rank %d vs leader rank %d: %s"):format(source, playerRank, leaderRank, tostring(isLeader)))
            return isLeader
        end
        
        -- Method 3: Fallback - check if player rank is high enough
        if playerRank >= Config.MinimumLeaderRank then
            DebugLog(("Player %d rank %d >= minimum leader rank %d (fallback)"):format(source, playerRank, Config.MinimumLeaderRank))
            return true
        end
    end
    
    DebugLog(("Player %d does not meet any leader criteria (rank: %s, type: %s)"):format(source, tostring(playerRank), type(playerRank)))
    return false
end

--- Add reputation to player's gang
-- @param source number Player source/ID
-- @param gangName string Gang name
-- @param amount number Reputation amount to add
-- @return boolean True if successful
local function AddGangReputation(source, gangName, amount)
    local success = exports['brutal_gangs']:AddGangReputation(gangName, amount)
    if success then
        DebugLog(("Added %d reputation to gang %s for player %d"):format(amount, gangName, source))
    else
        DebugLog(("Failed to add reputation to gang %s"):format(gangName))
    end
    return success
end

--- Add money to gang
-- @param gangName string Gang name
-- @param amount number Money amount to add
-- @return boolean True if successful
local function AddGangMoney(gangName, amount)
    if not Config.EnableGangMoneyReward or not amount or amount <= 0 then
        return false
    end

    -- This assumes brutal_gangs has an export for adding money
    -- If not available, you may need to directly update the database
    if exports["brutal_gangs"].AddGangMoney then
        local success = exports["brutal_gangs"]:AddGangMoney(gangName, amount)
        if success then
            DebugLog(("Added $%d to gang %s"):format(amount, gangName))
        end
        return success
    end

    DebugLog(("AddGangMoney not available in brutal_gangs"))
    return false
end

--- Remove item from player's inventory
-- @param source number Player source/ID
-- @param itemName string Item name to remove
-- @return boolean True if successful
local function RemoveItemFromPlayer(source, itemName)
    -- For qb-core
    if GetResourceState('qb-core') == 'started' then
        local player = exports['qb-core']:GetPlayer(source)
        if player then
            player.Functions.RemoveItem(itemName, 1)
            DebugLog(("Removed item %s from player %d (qb-core)"):format(itemName, source))
            return true
        end
    end

    -- For ESX
    if GetResourceState('es_extended') == 'started' then
        local xPlayer = exports['es_extended']:xPlayer(source)
        if xPlayer then
            xPlayer.removeInventoryItem(itemName, 1)
            DebugLog(("Removed item %s from player %d (ESX)"):format(itemName, source))
            return true
        end
    end

    DebugLog(("Could not remove item %s from player %d - no framework detected"):format(itemName, source))
    return false
end

-- ============================================================================
-- MAIN REPUTATION ITEM HANDLER
-- ============================================================================

--- Process reputation item usage with gang info from client
-- @param source number Player source/ID
-- @param itemName string Item name
-- @param itemConfig table Item configuration
-- @param gangInfo table Gang info from client {isInGang, gangRank}
local function UseReputationItemWithGangInfo(source, itemName, itemConfig, gangInfo)
    DebugLog(("=== Item Usage Started: %s by player %d ==="):format(itemName, source))

    -- Validate item config exists
    if not itemConfig or not Config.ReputationItems[itemName] then
        TriggerClientEvent('gangRep:cardError', source, 'Item not configured in the system')
        DebugLog(("Item %s not found in configuration"):format(itemName))
        return
    end

    -- Server-side cooldown check (anti-spam)
    if IsOnCooldown(source, itemName) then
        TriggerClientEvent('gangRep:cardError', source, 'Please wait before using this item again')
        return
    end

    -- Check if player is in a gang using client export data
    if not gangInfo.isInGang then
        TriggerClientEvent('gangRep:cardError', source, 'You must be in a gang')
        DebugLog(("Player %d not in a gang (brutal_gangs client export)"):format(source))
        return
    end

    -- Get player's gang name (still need from server for brutal_gangs exports)
    local gangName = GetPlayerGangName(source)
    if not gangName or gangName == "" then
        TriggerClientEvent('gangRep:cardError', source, 'Unable to determine your gang')
        DebugLog(("Player %d has invalid gang name"):format(source))
        return
    end

    -- Use gang rank from client (brutal_gangs export)
    local playerRank = gangInfo.gangRank
    if not playerRank or playerRank == false then
        TriggerClientEvent('gangRep:cardError', source, 'Unable to determine your gang rank')
        DebugLog(("Player %d has invalid rank"):format(source))
        return
    end
    
    DebugLog(("Player %d gang: %s, rank: %s (from brutal_gangs client)"):format(source, gangName, tostring(playerRank)))

    -- Check access restrictions
    if itemConfig.allowed == "leader" then
        DebugLog("Checking if player is gang leader...")
        
        if not IsPlayerLeader(source, gangName, playerRank) then
            TriggerClientEvent('gangRep:cardError', source, 'Only the gang leader can use this item')
            DebugLog(("Player %d (rank %s) is not a leader for gang %s"):format(source, tostring(playerRank), gangName))
            return
        end

        DebugLog(("Player %d is verified as gang leader (rank: %s)"):format(source, tostring(playerRank)))
    elseif itemConfig.allowed == "all" then
        DebugLog(("Item %s allows all gang members, player %d authorized"):format(itemName, source))
    else
        TriggerClientEvent('gangRep:cardError', source, 'Invalid item restriction configuration')
        DebugLog(("Invalid allowed value for item %s: %s"):format(itemName, itemConfig.allowed))
        return
    end

    -- All checks passed - proceed with reputation addition
    DebugLog("[STEP 1] Starting item removal process...")
    DebugLog(("[STEP 1] Item: %s, Player: %d, Gang: %s"):format(itemName, source, gangName))
    
    -- Remove item from inventory
    local removeSuccess, removeErr = pcall(function()
        return RemoveItem(source, itemName, 1)
    end)
    
    DebugLog(("[STEP 1] RemoveItem pcall result - success: %s, result: %s"):format(tostring(removeSuccess), tostring(removeErr)))
    
    if not removeSuccess then
        DebugLog(("[STEP 1 FAILED] Item removal error occurred: %s"):format(tostring(removeErr)))
        NotifyPlayer(source, 'Error removing item: ' .. tostring(removeErr))
        TriggerClientEvent('gangRep:cardError', source, 'Error removing card: ' .. tostring(removeErr))
        DebugLog(("Error removing item %s from player %d: %s"):format(itemName, source, tostring(removeErr)))
        return
    end
    
    if not removeErr then
        DebugLog(("[STEP 1 FAILED] Item removal returned false"))
        NotifyPlayer(source, 'Failed to remove item from inventory')
        TriggerClientEvent('gangRep:cardError', source, 'Failed to remove card from inventory')
        DebugLog(("Failed to remove item %s from player %d"):format(itemName, source))
        SendWebhook(
            "❌ Item Removal Failed",
            ("Failed to remove item %s from player %s"):format(itemName, GetPlayerName(source)),
            16711680,
            { { name = "Player", value = GetPlayerName(source), inline = true }, { name = "Item", value = itemName, inline = true }, { name = "Gang", value = gangName, inline = true } }
        )
        return
    end
    
    DebugLog(("[STEP 1 SUCCESS] Item %s removed from player %d inventory"):format(itemName, source))

    -- Add gang reputation
    DebugLog("[STEP 2] Starting reputation addition...")
    local reputation = itemConfig.reputation or 0
    DebugLog(("[STEP 2] Reputation to add: %d to gang %s"):format(reputation, gangName))
    
    if reputation > 0 then
        local success, err = pcall(function()
            return AddGangReputation(source, gangName, reputation)
        end)
        
        DebugLog(("[STEP 2] AddGangReputation pcall result - success: %s, result: %s"):format(tostring(success), tostring(err)))
        
        if not success then
            DebugLog(("[STEP 2 ERROR] Error adding reputation to gang %s: %s"):format(gangName, tostring(err)))
            TriggerClientEvent('gangRep:cardError', source, 'Failed to add reputation: ' .. tostring(err))
            return
        elseif not err then
            DebugLog(("[STEP 2 WARNING] Failed to add reputation to gang %s for player %d"):format(gangName, source))
        else
            DebugLog(("[STEP 2 SUCCESS] Added %d reputation to gang %s"):format(reputation, gangName))
        end
    else
        DebugLog("[STEP 2 SKIPPED] No reputation to add")
    end

    -- Add gang money (optional)
    DebugLog("[STEP 3] Starting gang money addition...")
    local gangMoney = 0
    if itemConfig.gang_money and itemConfig.gang_money > 0 then
        DebugLog(("[STEP 3] Gang money to add: $%d"):format(itemConfig.gang_money))
        local success, result = pcall(function()
            return AddGangMoney(gangName, itemConfig.gang_money)
        end)
        
        DebugLog(("[STEP 3] AddGangMoney pcall result - success: %s, result: %s"):format(tostring(success), tostring(result)))
        
        if success and result then
            gangMoney = itemConfig.gang_money
            DebugLog(("[STEP 3 SUCCESS] Added $%d to gang %s"):format(gangMoney, gangName))
        elseif not success then
            DebugLog(("[STEP 3 ERROR] Error adding gang money: %s"):format(tostring(result)))
        end
    else
        DebugLog("[STEP 3 SKIPPED] No gang money to add")
    end

    -- Set cooldown
    DebugLog("[STEP 4] Setting cooldown...")
    pcall(function()
        SetCooldown(source, itemName, itemConfig.cooldown or 0)
        DebugLog(("[STEP 4 SUCCESS] Cooldown set for item %s"):format(itemName))
    end)

    -- Notify client of success
    DebugLog("[STEP 5] Sending success notification to client...")
    pcall(function()
        NotifyPlayerSuccess(source, itemName, gangName, reputation, gangMoney)
        DebugLog("[STEP 5 SUCCESS] Success notification sent")
    end)

    -- Log success to webhook
    DebugLog("[STEP 7] Preparing webhook logging...")
    pcall(function()
        DebugLog("[STEP 7] Building webhook data...")
        local fields = {}
        pcall(function()
            table.insert(fields, { name = "Player", value = tostring(GetPlayerName(source) or "Unknown"), inline = true })
            table.insert(fields, { name = "Player ID", value = tostring(source), inline = true })
            table.insert(fields, { name = "Item", value = tostring(itemName), inline = true })
            table.insert(fields, { name = "Reputation Added", value = tostring(reputation), inline = true })
            table.insert(fields, { name = "Gang", value = tostring(gangName), inline = true })
            table.insert(fields, { name = "Player Rank", value = tostring(playerRank or "Unknown"), inline = true })
            
            if gangMoney and gangMoney > 0 then
                table.insert(fields, { name = "Gang Money Added", value = tostring(gangMoney), inline = true })
            end
            DebugLog("[STEP 7] Fields built successfully, field count: " .. #fields)
        end)

        DebugLog("[STEP 7] Sending webhook...")
        SendWebhook(
            "✅ Item Used Successfully",
            ("Reputation item used by **%s** in gang **%s**"):format(tostring(GetPlayerName(source) or "Unknown"), tostring(gangName)),
            3092272,
            fields
        )
        DebugLog("[STEP 7 SUCCESS] Webhook sent")
    end)

    DebugLog(("[COMPLETE] Item Usage Completed Successfully: %s by player %d"):format(itemName, source))
end

-- ============================================================================
-- EVENTS
-- ============================================================================

--- Get player's inventory cards for NPC UI
RegisterServerEvent('gangRep:getPlayerCards', function()
    local source = source
    local playerCards = {}

    DebugLog(("=== Checking player %d inventory for cards ==="):format(source))
    
    for itemName, itemData in pairs(Config.ReputationItems) do
        local quantity = GetItemAmount(source, itemName)
        DebugLog(("Item: %s - Quantity: %d"):format(itemName, quantity))
        
        if quantity > 0 then
            local cardData = {}
            for k, v in pairs(itemData) do
                cardData[k] = v
            end
            cardData.quantity = quantity
            table.insert(playerCards, cardData)
            DebugLog(("  Added %s (qty: %d) to player cards"):format(itemName, quantity))
        end
    end

    DebugLog(("=== Total unique cards found: %d ==="):format(#playerCards))
    TriggerClientEvent('gangRep:receivePlayerCards', source, playerCards)
    DebugLog(("Player %d has %d different card types in inventory"):format(source, #playerCards))
end)

--- Give card to NPC dealer
RegisterServerEvent('gangRep:giveCardToNPC', function(itemName)
    local source = source
    
    DebugLog(("=== Card Given to NPC: %s by player %d ==="):format(itemName, source))

    local itemConfig = Config.ReputationItems[itemName]
    if not itemConfig then
        TriggerClientEvent('gangRep:cardError', source, 'Invalid card')
        return
    end

    -- Check if player has the item
    if not HasItem(source, itemName) then
        TriggerClientEvent('gangRep:cardError', source, 'You do not have this card')
        return
    end

    -- Request gang info from client using brutal_gangs exports
    RequestGangInfoFromClient(source, function(gangInfo)
        if not gangInfo then
            TriggerClientEvent('gangRep:cardError', source, 'Failed to get gang information')
            return
        end
        
        -- Process with gang info
        UseReputationItemWithGangInfo(source, itemName, itemConfig, gangInfo)
    end)
end)

-- Receive gang info from client
RegisterServerEvent('gangRep:sendGangInfo', function(gangInfo)
    local source = source
    
    DebugLog(("Received gang info from client %d: isInGang=%s, gangRank=%s"):format(
        source, 
        tostring(gangInfo.isInGang), 
        tostring(gangInfo.gangRank)
    ))
    
    -- Find and execute pending callback
    for requestId, data in pairs(PendingGangInfoCallbacks) do
        if data.source == source then
            data.callback(gangInfo)
            PendingGangInfoCallbacks[requestId] = nil
            break
        end
    end
end)

--- Triggered when player attempts to use a reputation item
RegisterServerEvent('gangRep:useReputationItem', function(itemName, itemConfig)
    local source = source
    UseReputationItem(source, itemName, itemConfig)
end)

-- Clear cooldowns when player disconnects
AddEventHandler('playerDropped', function(reason)
    local source = source
    PlayerCooldowns[source] = nil
    DebugLog(("Cleared cooldowns for player %d"):format(source))
end)

-- ============================================================================
-- ADMIN COMMANDS
-- ============================================================================

--- /addreputation [gangName] [amount] - Manually add reputation to a gang
if Config.AdminCommandsEnabled and Config.AdminCommands.addreputation.enabled then
    RegisterCommand('addreputation', function(source, args, rawCommand)
        if not HasAdminPermission(source) then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'You do not have permission to use this command.' },
                color = { 255, 0, 0 }
            })
            return
        end

        if #args < 2 then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'Usage: /addreputation [gangName] [amount]' },
                color = { 255, 165, 0 }
            })
            return
        end

        local gangName = args[1]
        local amount = tonumber(args[2])

        if not amount or amount <= 0 then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'Amount must be a positive number.' },
                color = { 255, 0, 0 }
            })
            return
        end

        local success = AddGangReputation(source, gangName, amount)
        
        if success then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', ("Successfully added %d reputation to %s"):format(amount, gangName) },
                color = { 0, 255, 0 }
            })

            if Config.WebhookSettings.logAdminCommands then
                SendWebhook(
                    "🔧 Admin Command Executed",
                    ("Admin %s manually added reputation"):format(GetPlayerName(source)),
                    3092272,
                    {
                        { name = "Command", value = "/addreputation", inline = true },
                        { name = "Admin", value = GetPlayerName(source), inline = true },
                        { name = "Admin ID", value = tostring(source), inline = true },
                        { name = "Gang", value = gangName, inline = true },
                        { name = "Amount", value = tostring(amount), inline = true }
                    }
                )
            end

            DebugLog(("Admin %d added %d reputation to gang %s"):format(source, amount, gangName))
        else
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', ("Failed to add reputation to %s"):format(gangName) },
                color = { 255, 0, 0 }
            })
        end
    end, false)
end

--- /ganginfo - Check current player gang information
if Config.AdminCommandsEnabled and Config.AdminCommands.ganginfo.enabled then
    RegisterCommand('ganginfo', function(source, args, rawCommand)
        if not HasAdminPermission(source) then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'You do not have permission to use this command.' },
                color = { 255, 0, 0 }
            })
            return
        end

        local targetId = source
        if #args >= 1 then
            targetId = tonumber(args[1])
            if not targetId or targetId < 1 then
                TriggerClientEvent('chat:addMessage', source, {
                    args = { 'System', 'Invalid player ID.' },
                    color = { 255, 0, 0 }
                })
                return
            end
        end

        local inGang = IsPlayerInGang(targetId)
        if not inGang then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', ("Player %d is not in a gang."):format(targetId) },
                color = { 255, 165, 0 }
            })
            return
        end

        local gangName = GetPlayerGangName(targetId)
        local rank = GetPlayerGangRank(targetId)
        local leaderRank = GetGangLeaderRank(gangName)
        local isLeader = rank == leaderRank

        TriggerClientEvent('chat:addMessage', source, {
            args = { 'Gang Info', ("[%s] Player %d - Gang: %s | Rank: %s | Leader: %s"):format(GetPlayerName(targetId), targetId, gangName, rank, isLeader and 'Yes' or 'No') },
            color = { 0, 200, 255 }
        })

        DebugLog(("Admin %d checked gang info for player %d"):format(source, targetId))
    end, false)
end

--- /gangrepcheck [gangName] - Check gang reputation
if Config.AdminCommandsEnabled and Config.AdminCommands.gangrepcheck.enabled then
    RegisterCommand('gangrepcheck', function(source, args, rawCommand)
        if not HasAdminPermission(source) then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'You do not have permission to use this command.' },
                color = { 255, 0, 0 }
            })
            return
        end

        if #args < 1 then
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'System', 'Usage: /gangrepcheck [gangName]' },
                color = { 255, 165, 0 }
            })
            return
        end

        local gangName = args[1]
        local gangs = GetGangsData()

        for _, gang in ipairs(gangs) do
            if gang.name == gangName then
                local reputation = gang.reputation or 0
                TriggerClientEvent('chat:addMessage', source, {
                    args = { 'Gang Rep', ("Gang: %s | Reputation: %d | Members: %d"):format(gangName, reputation, gang.members_count or 0) },
                    color = { 0, 200, 255 }
                })
                DebugLog(("Admin %d checked reputation for gang %s"):format(source, gangName))
                return
            end
        end

        TriggerClientEvent('chat:addMessage', source, {
            args = { 'System', ("Gang %s not found."):format(gangName) },
            color = { 255, 0, 0 }
        })
    end, false)
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

--- Get item configuration
-- @param itemName string Item name
-- @return table Item config or nil
exports('getItemConfig', function(itemName)
    return Config.ReputationItems[itemName]
end)

--- Get all reputation items
-- @return table All reputation items config
exports('getReputationItems', function()
    return Config.ReputationItems
end)

--- Manually add reputation to player's gang
-- @param source number Player source/ID
-- @param gangName string Gang name
-- @param amount number Reputation amount
-- @return boolean Success status
exports('addGangReputation', function(source, gangName, amount)
    if not gangName or not amount or amount <= 0 then
        return false
    end
    return AddGangReputation(source, gangName, amount)
end)

--- Check if player is in gang
-- @param source number Player source/ID
-- @return boolean Player in gang status
exports('isPlayerInGang', function(source)
    return IsPlayerInGang(source)
end)

--- Get player's gang name
-- @param source number Player source/ID
-- @return string Gang name
exports('getPlayerGangName', function(source)
    return GetPlayerGangName(source)
end)

--- Get player's gang rank
-- @param source number Player source/ID
-- @return string Gang rank
exports('getPlayerGangRank', function(source)
    return GetPlayerGangRank(source)
end)

DebugLog("Gang Reputation Item System initialized successfully")
