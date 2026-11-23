--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.services.DataManager)
local CurrencyService = require(ServerScriptService.services.CurrencyService)

local AdminService = {}

-- ⚠️ WAŻNE: Właściciel gry i zaufani admini
local ADMIN_USER_IDS: { [number]: boolean } = {
    [8936344866] = true,  -- Wstaw swoje UserId
    [000] = true,  -- Inni admini
}

local function isAdmin(player: Player): boolean
    return ADMIN_USER_IDS[player.UserId] == true
end

local COMMANDS: { [string]: (player: Player, args: { string }) -> () } = {
    givecoins = function(player: Player, args: { string }): ()
        local targetName = args[1]
        local amountStr = args[2]
        
        local target = Players:FindFirstChild(targetName) :: Player?
        if not target then
            warn(`[ADMIN] Nie znaleziono gracza: {targetName}`)
            return
        end
        
        local amount = tonumber(amountStr)
        if not amount or amount <= 0 then
            warn("[ADMIN] Nieprawidłowa kwota.")
            return
        end
        
        CurrencyService:AddCurrency(target, amount, "Coins")
        print(`[ADMIN] {player.Name} dał {amount} monet graczowi {target.Name}`)
    end,
    
    setcoins = function(player: Player, args: { string }): ()
        local targetName = args[1]
        local amountStr = args[2]
        
        local target = Players:FindFirstChild(targetName) :: Player?
        if not target then return end
        
        local amount = tonumber(amountStr)
        if not amount then return end
        
        local profile = DataManager:GetProfile(target)
        if not profile then return end
        
        profile.Data.Coins = amount
        -- Natychmiastowa synchronizacja z klientem
        require(game.ServerScriptService.Net.network_server).SyncCurrency.Fire(target, {
            currencyType = "Coins",
            value = amount,
        })
        print(`[ADMIN] {player.Name} ustawił {amount} monet graczowi {target.Name}`)
    end,
}

function AdminService.OnInit(): ()
end

function AdminService.OnStart(): ()
    -- Nasłuchiwanie komend z czatu
    Players.PlayerAdded:Connect(function(player: Player)
        player.Chatted:Connect(function(message: string)
            if not isAdmin(player) then return end
            
            local args = string.split(message, " ")
            local command = args[1]:lower():gsub("^/", "")  -- /givecoins
            local rest = table.move(args, 2, #args, 1, {})
            
            local handler = COMMANDS[command]
            if handler then
                task.spawn(handler, player, rest)
            end
        end)
    end)
end

return AdminService