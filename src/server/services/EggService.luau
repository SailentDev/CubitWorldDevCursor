--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ServerScriptService.Net.network_server)
local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local CurrencyService = require(ServerScriptService.services.CurrencyService)
local DataManager = require(ServerScriptService.services.DataManager)
local InventoryService = require(ServerScriptService.services.InventoryService)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)

local EggService = {}

local BUY_COOLDOWN_SECONDS = 0.25
local HATCH_COOLDOWN_SECONDS = 0.5
local SAVE_THROTTLE_SECONDS = 15

local VALID_HATCH_AMOUNTS: { [number]: boolean } = {
	[1] = true,
	[2] = true,
	[5] = true,
	[10] = true,
}

local rng = Random.new()
local buyLimiter = RateLimiter.new(1, 1 / BUY_COOLDOWN_SECONDS)
local hatchLimiter = RateLimiter.new(1, 1 / HATCH_COOLDOWN_SECONDS)
local lastSaveTimes: { [Player]: number } = {}

local function tryThrottledSave(player: Player, profile: Types.PlayerProfile): ()
	local now = os.clock()
	local lastSave = lastSaveTimes[player]
	if lastSave and (now - lastSave) < SAVE_THROTTLE_SECONDS then
		return
	end
	lastSaveTimes[player] = now
	if profile:IsActive() then
		profile:Save()
	end
end

local function rollPetFromEgg(eggInfo: Types.EggInfo): string?
	local totalWeight = 0
	local lastValidPet: string? = nil

	for petName, weight in eggInfo.DropChances do
		if weight > 0 and PetDatabase.GetPetInfo(petName) then
			totalWeight += weight
			lastValidPet = petName
		end
	end

	if totalWeight <= 0 or not lastValidPet then
		return nil
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cumulative = 0

	for petName, weight in eggInfo.DropChances do
		if weight > 0 and PetDatabase.GetPetInfo(petName) then
			cumulative += weight
			if roll <= cumulative then
				return petName
			end
		end
	end

	return lastValidPet
end

function EggService.OnInit(): ()
end

function EggService.OnStart(): ()
	Blink.RequestBuyEgg.On(function(player: Player, data: { eggName: string })
		if not buyLimiter:Consume(player) then
			return
		end

		if typeof(data) ~= "table" or typeof(data.eggName) ~= "string" then
			return
		end

		local eggInfo = EggDatabase.GetEggInfo(data.eggName)
		if not eggInfo then
			return
		end

		local profile = DataManager:GetProfile(player)
		if not profile then
			return
		end

		if not InventoryService:CanAddEggs(player, data.eggName, 1) then
			return
		end

		if not CurrencyService:RemoveCurrency(player, eggInfo.Price, eggInfo.CurrencyType) then
			return
		end

		if not InventoryService:AddEggs(player, data.eggName, 1) then
			CurrencyService:AddCurrency(player, eggInfo.Price, eggInfo.CurrencyType)
			return
		end

		tryThrottledSave(player, profile)
	end)

	Blink.RequestHatch.On(function(player: Player, data: { eggName: string, amount: number })
		if not hatchLimiter:Consume(player) then
			return
		end

		if typeof(data) ~= "table" or typeof(data.eggName) ~= "string" or typeof(data.amount) ~= "number" then
			return
		end

		local amount = data.amount
		if not VALID_HATCH_AMOUNTS[amount] then
			warn(`[EggService] Invalid hatch amount '{tostring(amount)}' from {player.Name}`)
			return
		end

		local eggInfo = EggDatabase.GetEggInfo(data.eggName)
		if not eggInfo then
			return
		end

		local profile = DataManager:GetProfile(player)
		if not profile then
			return
		end

		if InventoryService:GetEggCount(player, data.eggName) < amount then
			return
		end

		if not InventoryService:CanAddPets(player, amount) then
			return
		end

		local rolledPets: { string } = {}
		for _ = 1, amount do
			local rolledPet = rollPetFromEgg(eggInfo)
			if not rolledPet then
				warn(`[EggService] Egg '{data.eggName}' has no valid drops configured`)
				return
			end
			table.insert(rolledPets, rolledPet)
		end

		if not InventoryService:SpendEggs(player, data.eggName, amount) then
			return
		end

		local hatchedAny = false
		for _, rolledPet in rolledPets do
			local petUUID = InventoryService:AddPet(player, rolledPet, 1)
			if petUUID then
				hatchedAny = true
				Blink.EggHatched.Fire(player, {
					petName = rolledPet,
				})
			end
		end

		if hatchedAny then
			tryThrottledSave(player, profile)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		buyLimiter:Clear(player)
		hatchLimiter:Clear(player)
		lastSaveTimes[player] = nil
	end)
end

return EggService