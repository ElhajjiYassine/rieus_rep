-- ============================================================================
-- GANG REPUTATION NPC DEALER - CLIENT SIDE
-- ============================================================================
-- Spawns NPC and handles giving cards to dealer for reputation

local NPCPed = nil
local UIOpen = false
local InteractionDistance = 2.0

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function SendNotification(title, message, notifType)
    if Config.NotificationType == 'qbcore' then
        TriggerEvent('QBCore:Notify', message, notifType or 'info', Config.NotificationDuration)
    elseif Config.NotificationType == 'chat' then
        TriggerEvent('chat:addMessage', {
            args = { title, message },
            color = { 0, 255, 0 }
        })
    else
        TriggerEvent('chat:addMessage', {
            args = { title, message },
            color = { 0, 255, 0 }
        })
    end
end

local function DebugLog(message)
    if Config.DebugMode then
        print("^2[Gang Rep NPC - Client]^7 " .. message)
    end
end

local function LoadModel(modelHash)
    if not IsModelValid(modelHash) then
        modelHash = GetHashKey(modelHash)
    end
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 10000 do
        Wait(10)
        timeout = timeout + 10
    end
    return HasModelLoaded(modelHash)
end

local function IsPlayerNearNPC()
    if not NPCPed or not DoesEntityExist(NPCPed) then
        return false
    end
    local playerCoords = GetEntityCoords(PlayerPedId())
    local npcCoords = GetEntityCoords(NPCPed)
    return #(playerCoords - npcCoords) <= InteractionDistance
end

--- Get player's gang info using brutal_gangs client exports
-- @return table {isInGang: boolean, gangRank: number/boolean}
local function GetPlayerGangInfo()
    local isInGang = false
    local gangRank = false
    
    -- Use brutal_gangs client exports
    local success1, result1 = pcall(function()
        return exports.brutal_gangs:isPlayerInGangJob()
    end)
    
    if success1 then
        isInGang = result1 or false
    end
    
    local success2, result2 = pcall(function()
        return exports.brutal_gangs:playerGangRank()
    end)
    
    if success2 then
        gangRank = result2 or false
    end
    
    DebugLog(("Gang info: isInGang=%s, gangRank=%s"):format(tostring(isInGang), tostring(gangRank)))
    
    return {
        isInGang = isInGang,
        gangRank = gangRank
    }
end

-- ============================================================================
-- NPC SPAWNING
-- ============================================================================

local function SpawnNPC()
    if not Config.NPC or not Config.NPC.enabled then
        DebugLog("NPC system disabled in config")
        return
    end

    DebugLog("Spawning NPC dealer...")

    local modelHash = GetHashKey(Config.NPC.model)
    if LoadModel(modelHash) then
        NPCPed = CreatePed(4, modelHash, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z, Config.NPC.coords.w, false, true)
        
        if NPCPed then
            SetEntityInvincible(NPCPed, true)
            SetBlockingOfNonTemporaryEvents(NPCPed, true)
            FreezeEntityPosition(NPCPed, true)
            TaskStartScenarioInPlace(NPCPed, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
            
            DebugLog("NPC spawned successfully")

            -- Create blip
            if Config.NPC.blip and Config.NPC.blip.enabled then
                local blip = AddBlipForCoord(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
                SetBlipSprite(blip, Config.NPC.blip.sprite)
                SetBlipColour(blip, Config.NPC.blip.color)
                SetBlipScale(blip, Config.NPC.blip.scale)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(Config.NPC.label)
                EndTextCommandSetBlipName(blip)
                DebugLog("NPC blip created")
            end
        else
            DebugLog("Failed to create NPC ped")
        end
    else
        DebugLog("Failed to load NPC model: " .. Config.NPC.model)
    end
end

-- ============================================================================
-- NPC INTERACTION
-- ============================================================================

local function OpenCardUI()
    if UIOpen then return end
    
    if not IsPlayerNearNPC() then
        DebugLog("UI open blocked: player not near NPC")
        return
    end

    DebugLog("Requesting player cards from server...")
    TriggerServerEvent('gangRep:getPlayerCards')
end

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

RegisterNetEvent('gangRep:receivePlayerCards', function(playerCards)
    if not IsPlayerNearNPC() then
        DebugLog("Receive cards blocked: player no longer near NPC")
        return
    end

    if #playerCards == 0 then
        SendNotification('Error', 'You do not have any reputation cards', 'error')
        return
    end

    UIOpen = true
    DebugLog("Opening card UI with " .. #playerCards .. " cards")

    -- Calculate stats for UI
    local availableCards = #playerCards
    local totalRep = 0
    for _, card in ipairs(playerCards) do
        totalRep = totalRep + (card.reputation or 0)
    end

    SendNUIMessage({
        type = 'SHOW_UI',
        cards = playerCards,
        stats = {
            available = availableCards,
            totalRep = totalRep
        }
    })

    SetNuiFocus(true, true)
end)

RegisterNetEvent('gangRep:itemUsedSuccess', function(itemName, gangName, reputation)
    -- Handle both full and empty event calls
    if not itemName or not gangName or not reputation then
        DebugLog("Card given successfully - UI closing")
        SendNUIMessage({
            type = 'CLOSE_UI'
        })
        Wait(500)
        SetNuiFocus(false, false)
        UIOpen = false
        return
    end
    
    DebugLog("Card given successfully: " .. itemName)
    
    SendNotification('Success', ('You gave the card! +%d gang reputation for %s'):format(reputation, gangName), 'success')
    
    SendNUIMessage({
        type = 'CLOSE_UI'
    })
    
    Wait(1000)
    SetNuiFocus(false, false)
    UIOpen = false
end)

RegisterNetEvent('gangRep:cardError', function(errorMessage)
    local msg = errorMessage or 'An error occurred'
    DebugLog("Card error: " .. msg)
    
    SendNotification('Error', msg, 'error')
    
    SendNUIMessage({
        type = 'CLOSE_UI'
    })
    
    Wait(500)
    SetNuiFocus(false, false)
    UIOpen = false
end)

-- ============================================================================
-- NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('giveCard', function(data, cb)
    if data.cardData and data.cardData.itemName then
        DebugLog("Card give requested: " .. data.cardData.itemName)
        TriggerServerEvent('gangRep:giveCardToNPC', data.cardData.itemName)
    else
        DebugLog("Invalid card data received")
    end
    cb('ok')
end)

RegisterNUICallback('cancelGive', function(data, cb)
    DebugLog("Card give cancelled")
    SetNuiFocus(false, false)
    UIOpen = false
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    DebugLog("UI closed")
    SetNuiFocus(false, false)
    UIOpen = false
    cb('ok')
end)

-- Server callback to get player gang info using brutal_gangs client exports
RegisterNetEvent('gangRep:requestGangInfo', function()
    local gangInfo = GetPlayerGangInfo()
    TriggerServerEvent('gangRep:sendGangInfo', gangInfo)
end)

-- ============================================================================
-- MAIN LOOP - PROXIMITY & INTERACTION
-- ============================================================================

Citizen.CreateThread(function()
    local isShowingText = false
    
    while true do
        Wait(0)

        if Config.NPC and Config.NPC.enabled and NPCPed then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local npcCoords = GetEntityCoords(NPCPed)
            local distance = #(playerCoords - npcCoords)

            if distance < InteractionDistance then
                if not isShowingText then
                    exports['qb-core']:DrawText('[E] Talk to ' .. Config.NPC.label, 'left')
                    isShowingText = true
                end

                if IsControlJustReleased(0, 38) and not UIOpen then  -- E key
                    exports['qb-core']:HideText()
                    isShowingText = false
                    OpenCardUI()
                end
            else
                if isShowingText then
                    exports['qb-core']:HideText()
                    isShowingText = false
                end
                Wait(500)
            end
        else
            if isShowingText then
                exports['qb-core']:HideText()
                isShowingText = false
            end
            Wait(500)
        end
    end
end)

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

Citizen.CreateThread(function()
    Wait(1000)
    SpawnNPC()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        exports['qb-core']:HideText()
        if NPCPed then
            DeleteEntity(NPCPed)
        end
    end
end)

DebugLog("Gang Reputation NPC System initialized")
