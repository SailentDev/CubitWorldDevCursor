--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local DataManager = require(ServerScriptService.services.DataManager)
local Types = require(ReplicatedStorage.Shared.Types)

local CurrencyService = {}

local VALID_CURRENCIES: { [string]: boolean } = {
	Coins = true,
}

local function isValidAmount(amount: number): boolean
	return typeof(amount) == "number"
		and amount == amount -- NaN check
		and amount > 0
		and amount < math.huge
end

local function validateParams(player: Player, amount: number, currencyType: string): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false
	end

	if not isValidAmount(amount) then
		warn(`[CurrencyService] Invalid amount received: {tostring(amount)}`)
		return false
	end

	if typeof(currencyType) ~= "string" or not VALID_CURRENCIES[currencyType] then
		warn(`[CurrencyService] Invalid currencyType: {tostring(currencyType)}`)
		return false
	end

	return true
end

local function getBalance(profile: Types.PlayerProfile, currencyType: Types.CurrencyType): number
	if currencyType == "Coins" then
		return profile.Data.Coins or 0
	end
	return 0
end

local function setBalance(profile: Types.PlayerProfile, currencyType: Types.CurrencyType, newValue: number): ()
	if currencyType == "Coins" then
		profile.Data.Coins = newValue
	end
end

function CurrencyService.OnInit(): ()
end

function CurrencyService.OnStart(): ()
end

function CurrencyService:HasEnoughCurrency(player: Player, amount: number, currencyType: Types.CurrencyType): boolean
	if not validateParams(player, amount, currencyType) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	return getBalance(profile, currencyType) >= amount
end

function CurrencyService:AddCurrency(player: Player, amount: number, currencyType: Types.CurrencyType): boolean
	if not validateParams(player, amount, currencyType) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local newValue = getBalance(profile, currencyType) + math.floor(amount)
	setBalance(profile, currencyType, newValue)

	Blink.SyncCurrency.Fire(player, {
		currencyType = currencyType,
		value = newValue,
	})

	return true
end

function CurrencyService:RemoveCurrency(player: Player, amount: number, currencyType: Types.CurrencyType): boolean
	if not validateParams(player, amount, currencyType) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local cost = math.floor(amount)
	local current = getBalance(profile, currencyType)
	if current < cost then
		return false
	end

	local newValue = current - cost
	setBalance(profile, currencyType, newValue)

	Blink.SyncCurrency.Fire(player, {
		currencyType = currencyType,
		value = newValue,
	})

	return true
end

return CurrencyService