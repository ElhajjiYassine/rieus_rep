-- ============================================================================
-- GANG REPUTATION ITEM SYSTEM - CLIENT SIDE
-- ============================================================================
-- Handles item usage and communicates with server for validation

local GangRepSystem = {}
local PlayerCooldowns = {}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Send notification to player
-- @param title string Notification title
-- @param message string Notification message
-- @param type string 'success', 'error', or 'info'
local function SendNotification(title, message, type)
    if Config.NotificationType == 'qbcore' then
        -- QBCore Framework notification
        local notifType = type or 'info'
        if notifType == 'success' then notifType = 'success' end
        if notifType == 'error' then notifType = 'error' end
        
        TriggerEvent('QBCore:Notify', message, notifType, Config.NotificationDuration)
    elseif Config.NotificationType == 'chat' then
        TriggerEvent('chat:addMessage', {
            args = { title, message },
            color = { 0, 255, 0 }
        })
    else
        -- Custom notification - modify this to use your framework's notification system
        TriggerEvent('chat:addMessage', {
            args = { title, message },
            color = { 0, 255, 0 }
        })
    end
end

--- Check if player is on cooldown for an item
-- @param item string Item name
-- @return boolean True if on cooldown
local function IsOnCooldown(item)
    if not Config.EnableCooldown then return false end

    local playerId = GetPlayerServerId(PlayerId())
    if not PlayerCooldowns[playerId] then
        PlayerCooldowns[playerId] = {}
    end

    if PlayerCooldowns[playerId][item] then
        local remainingTime = PlayerCooldowns[playerId][item] - GetGameTimer()
        if remainingTime > 0 then
            SendNotification('Cooldown', ('Please wait %d seconds before using this item again.'):format(math.ceil(remainingTime / 1000)), 'error')
            return true
        end
    end

    return false
end

--- Set cooldown for an item
-- @param item string Item name
-- @param cooldown number Cooldown duration in seconds
local function SetCooldown(item, cooldown)
    if not Config.EnableCooldown or cooldown == 0 then return end

    local playerId = GetPlayerServerId(PlayerId())
    if not PlayerCooldowns[playerId] then
        PlayerCooldowns[playerId] = {}
    end

    PlayerCooldowns[playerId][item] = GetGameTimer() + (cooldown * 1000)
end

--- Debug logging
-- @param message string Message to log
local function DebugLog(message)
    if Config.DebugMode then
        print("^2[Gang Rep System]^7 " .. message)
    end
end

-- ============================================================================
-- ITEM USAGE HANDLER
-- ============================================================================

--- Handle item usage - called by your inventory system
-- @param itemName string The item being used
function GangRepSystem.UseItem(itemName)
    DebugLog("Player attempting to use item: " .. itemName)

    -- Check if item exists in config
    if not Config.ReputationItems[itemName] then
        SendNotification('Error', 'This item is not configured for gang reputation.', 'error')
        DebugLog("Item not found in configuration: " .. itemName)
        return false
    end

    -- Check cooldown
    if IsOnCooldown(itemName) then
        return false
    end

    -- Get item config
    local itemConfig = Config.ReputationItems[itemName]

    -- Trigger server-side validation and reputation add
    TriggerServerEvent('gangRep:useReputationItem', itemName, itemConfig)

    return true
end

-- ============================================================================
-- SERVER CALLBACK HANDLERS
-- ============================================================================

--- Handle success response from server
RegisterNetEvent('gangRep:itemUsedSuccess', function(itemName, gangName, reputation, gangMoney)
    -- Handle both full and empty event calls
    if not itemName or not gangName or not reputation then
        DebugLog("Card given successfully - UI closing")
        return
    end
    
    local itemConfig = Config.ReputationItems[itemName]
    if itemConfig then
        SetCooldown(itemName, itemConfig.cooldown or 0)
    end

    local message = ('You earned +%d gang reputation for %s'):format(reputation, gangName)
    if gangMoney and gangMoney > 0 then
        message = message .. (' (+$%d gang money)'):format(gangMoney)
    end

    SendNotification('Success', message, 'success')
    DebugLog("Item used successfully: " .. itemName .. " for gang: " .. gangName)
end)

--- Handle error response from server
RegisterNetEvent('gangRep:itemUsedError', function(errorMessage)
    local msg = errorMessage or "An unknown error occurred"
    SendNotification('Error', msg, 'error')
    DebugLog("Item usage failed: " .. msg)
end)

-- ============================================================================
-- INVENTORY INTEGRATION (Example for common frameworks)
-- ============================================================================

-- For qb-core framework
if GetResourceState('qb-core') == 'started' then
    TriggerEvent('QBCore:GetObject', function(obj)
        QBCore = obj
    end)

    -- Register item usage
    if QBCore then
        for itemName, _ in pairs(Config.ReputationItems) do
            QBCore.Functions.CreateUseableItem(itemName, function(source)
                GangRepSystem.UseItem(itemName)
            end)
        end
    end
end

-- For ESX framework
if GetResourceState('es_extended') == 'started' then
    TriggerEvent('esx:getSharedObject', function(obj)
        ESX = obj
    end)

    -- Register item usage
    if ESX then
        for itemName, _ in pairs(Config.ReputationItems) do
            ESX.RegisterUsableItem(itemName, function(source)
                GangRepSystem.UseItem(itemName)
            end)
        end
    end
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('UseReputationItem', function(itemName)
    return GangRepSystem.UseItem(itemName)
end)

exports('SetPlayerCooldown', function(item, cooldown)
    SetCooldown(item, cooldown)
end)

exports('IsOnCooldown', function(item)
    return IsOnCooldown(item)
end)
