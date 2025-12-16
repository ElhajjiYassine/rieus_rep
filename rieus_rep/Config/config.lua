-- ============================================================================
-- GANG REPUTATION ITEM SYSTEM - CONFIGURATION
-- ============================================================================
-- Configuration for items that grant gang reputation
-- Fully customizable per item with restrictions

Config = Config or {}

-- ============================================================================
-- REPUTATION ITEMS CONFIGURATION
-- ============================================================================
-- Structure:
-- [item_name] = {
--     reputation = amount to add to gang reputation,
--     allowed = "all" (all members) or "leader" (leader only),
--     gang_money = optional amount of money to give to gang,
--     cooldown = optional cooldown in seconds per player (0 = no cooldown)
-- }

Config.ReputationItems = {
    ["gangrep1"] = {
        itemName = "gangrep1",
        label = "Reputation Card LVL 1",
        description = "Give to dealer for 1,000 gang reputation",
        reputation = 1000,
        allowed = "all",
        gang_money = 0
    },
    ["gangrep2"] = {
        itemName = "gangrep2",
        label = "Reputation Card LVL 2",
        description = "Give to dealer for 5,000 gang reputation",
        reputation = 5000,
        allowed = "leader",
        gang_money = 0
    },
    ["gangrep3"] = {
        itemName = "gangrep3",
        label = "Reputation Card LVL 3",
        description = "Give to dealer for 10,000 gang reputation",
        reputation = 10000,
        allowed = "leader",
        gang_money = 0
    }
}

-- ============================================================================
-- NPC DEALER CONFIGURATION
-- ============================================================================

Config.NPC = {
    enabled = true,
    model = "a_m_m_business_01",
    coords = vector4(-616.81, -1622.71, 32.01, 358.72),  -- x, y, z, heading
    label = "Reputation Card Exchanger",
    blip = {
        enabled = true,
        sprite = 58,
        color = 1,
        scale = 0.8
    }
}

-- ============================================================================
-- GENERAL SETTINGS
-- ============================================================================

-- Enable/disable gang money rewards
Config.EnableGangMoneyReward = false

-- Enable/disable cooldown system
Config.EnableCooldown = true

-- Minimum rank/grade to be considered a leader (fallback if brutal_gangs data unavailable)
-- If player's rank is >= this value, they're considered a leader
Config.MinimumLeaderRank = 10

-- Notification type: 'qbcore', 'chat', or 'custom'
-- 'qbcore' = QBCore framework notification
-- 'chat' = TriggerEvent('chat:addMessage')
-- 'custom' = Customize in client.lua SendNotification()
Config.NotificationType = 'qbcore'

-- How long to display notifications (in milliseconds)
Config.NotificationDuration = 5000

-- Debug mode (shows console logs)
Config.DebugMode = false

-- ============================================================================
-- WEBHOOK CONFIGURATION
-- ============================================================================

-- Enable/disable webhook logging
Config.WebhookEnabled = true

-- Discord webhook URL for detailed logging
-- Replace with your actual Discord webhook URL
-- Get it from: Server Settings → Integrations → Webhooks → Create New Webhook → Copy Webhook URL
Config.WebhookURL = "https://discord.com/api/webhooks/1450565986569945200/uC-rM4pVhhh9Gra7wAMjE6aHGWEKk__fcIOxzIArEPHicnKIsEQUZnMelqMaQYXxCZjd"

-- Webhook logging settings
Config.WebhookSettings = {
    -- Log item usage (success and failure)
    logItemUsage = true,
    -- Log admin commands
    logAdminCommands = true,
    -- Log reputation additions
    logReputation = true,
    -- Include player details in logs
    includePlayerDetails = true,
    -- Include gang details in logs
    includeGangDetails = true
}

-- ============================================================================
-- ADMIN COMMANDS CONFIGURATION
-- ============================================================================

-- Enable/disable admin commands
Config.AdminCommandsEnabled = true

-- Required permission level for admin commands
-- For qb-core: use job names (e.g., "admin")
-- For ESX: use job names (e.g., "admin")
Config.AdminPermissionGroup = "admin"

-- Admin commands available
Config.AdminCommands = {
    -- Command to manually add gang reputation
    addreputation = {
        enabled = true,
        description = "Add reputation to a gang: /addreputation [gangName] [amount]",
        permission = "admin"
    },
    -- Command to check player gang info
    ganginfo = {
        enabled = true,
        description = "Check your current gang info: /ganginfo",
        permission = "admin"
    },
    -- Command to check gang reputation
    gangrepcheck = {
        enabled = true,
        description = "Check gang reputation: /gangrepcheck [gangName]",
        permission = "admin"
    }
}
