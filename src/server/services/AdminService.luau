--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CurrencyService = require(ServerScriptService.services.CurrencyService)

local AdminService = {}

type CommandHandler = (admin: Player, args: { string }) -> ()

local MAX_ADMIN_COINS = 1_000_000_000_000_000

-- Add only verified UserIds here
local ADMIN_USER_IDS: { [number]: boolean } = {
	[8936344866] = true,
}

local chatConnections: { [Player]: RBXScriptConnection } = {}

local function isAdmin(player: Player): boolean
	return player.UserId > 0 and ADMIN_USER_IDS[player.UserId] == true
end

local function findTargetPlayer(targetName: string?): Player?
	if typeof(targetName) ~= "string" or #targetName == 0 then
		return nil
	end

	local candidate = Players:FindFirstChild(targetName)
	if candidate and candidate:IsA("Player") then
		return candidate
	end

	return nil
end

local function parseCoinAmount(rawValue: string?, allowZero: boolean): number?
	if typeof(rawValue) ~= "string" or #rawValue == 0 then
		return nil
	end

	local parsed = tonumber(rawValue)
	if typeof(parsed) ~= "number"
		or parsed ~= parsed -- NaN check
		or parsed > MAX_ADMIN_COINS
		or parsed % 1 ~= 0
	then
		return nil
	end

	local minValue = if allowZero then 0 else 1
	if parsed < minValue then
		return nil
	end

	return parsed
end

local COMMANDS: { [string]: CommandHandler } = {
	givecoins = function(admin: Player, args: { string }): ()
		local target = findTargetPlayer(args[1])
		if not target then
			warn(`[ADMIN] Player not found: {tostring(args[1])}`)
			return
		end

		local amount = parseCoinAmount(args[2], false)
		if not amount then
			warn(`[ADMIN] Invalid coin amount: {tostring(args[2])}`)
			return
		end

		if CurrencyService:AddCurrency(target, amount, "Coins") then
			print(`[ADMIN] {admin.Name} gave {amount} Coins to {target.Name}`)
		else
			warn(`[ADMIN] Failed to give Coins to {target.Name} (profile not loaded yet)`)
		end
	end,

	setcoins = function(admin: Player, args: { string }): ()
		local target = findTargetPlayer(args[1])
		if not target then
			warn(`[ADMIN] Player not found: {tostring(args[1])}`)
			return
		end

		local amount = parseCoinAmount(args[2], true)
		if not amount then
			warn(`[ADMIN] Invalid coin amount: {tostring(args[2])}`)
			return
		end

		if CurrencyService:SetCurrency(target, amount, "Coins") then
			print(`[ADMIN] {admin.Name} set {target.Name}'s Coins to {amount}`)
		else
			warn(`[ADMIN] Failed to set Coins for {target.Name} (profile not loaded yet)`)
		end
	end,
}

local function bindAdminChat(player: Player): ()
	if chatConnections[player] or not isAdmin(player) then
		return
	end

	chatConnections[player] = player.Chatted:Connect(function(message: string)
		if not isAdmin(player) then
			return
		end

		if string.sub(message, 1, 1) ~= "/" then
			return
		end

		local tokens: { string } = {}
		for token in string.gmatch(string.sub(message, 2), "%S+") do
			table.insert(tokens, token)
		end

		if #tokens == 0 then
			return
		end

		local command = string.lower(tokens[1])
		local handler = COMMANDS[command]
		if not handler then
			return
		end

		local args: { string } = {}
		for i = 2, #tokens do
			table.insert(args, tokens[i])
		end

		task.spawn(handler, player, args)
	end)
end

function AdminService.OnInit(): ()
end

function AdminService.OnStart(): ()
	Players.PlayerAdded:Connect(bindAdminChat)

	Players.PlayerRemoving:Connect(function(player: Player)
		local conn = chatConnections[player]
		if conn then
			conn:Disconnect()
			chatConnections[player] = nil
		end
	end)

	for _, player in Players:GetPlayers() do
		bindAdminChat(player)
	end
end

return AdminService