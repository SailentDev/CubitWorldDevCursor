--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local CurrencyService = require(ServerScriptService.services.CurrencyService)
local DataManager = require(ServerScriptService.services.DataManager)

local EggService = {}

local BUY_COOLDOWN_SECONDS = 0.25
local HATCH_COOLDOWN_SECONDS = 0.5
local MAX_EGG_PER_TYPE = 9999
local MAX_PET_INVENTORY = 500

local VALID_HATCH_AMOUNTS: { [number]: boolean } = {
	[1] = true,
	[2] = true,
	[5] = true,
	[10] = true,
}

local rng = Random.new()
local lastBuyTimes: { [Player]: number } = {}
local lastHatchTimes: { [Player]: number } = {}

local function countPets(pets: { [string]: Types.PetInstanceData }): number
	local count = 0
	for _ in pets do
		count += 1
	end
	return count
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
		local now = os.clock()
		if (now - (lastBuyTimes[player] or 0)) < BUY_COOLDOWN_SECONDS then
			return
		end
		lastBuyTimes[player] = now

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

		local currentEggCount = profile.Data.Eggs[data.eggName] or 0
		if currentEggCount >= MAX_EGG_PER_TYPE then
			return
		end

		if not CurrencyService:RemoveCurrency(player, eggInfo.Price, eggInfo.CurrencyType) then
			return
		end

		local newEggAmount = currentEggCount + 1
		profile.Data.Eggs[data.eggName] = newEggAmount

		Blink.SyncEggs.Fire(player, {
			eggName = data.eggName,
			amount = newEggAmount,
		})
	end)

	Blink.RequestHatch.On(function(player: Player, data: { eggName: string, amount: number })
		local now = os.clock()
		if (now - (lastHatchTimes[player] or 0)) < HATCH_COOLDOWN_SECONDS then
			return
		end
		lastHatchTimes[player] = now

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

		local currentEggs = profile.Data.Eggs[data.eggName] or 0
		if currentEggs < amount then
			return
		end

		if countPets(profile.Data.Pets) + amount > MAX_PET_INVENTORY then
			return
		end

		-- Pre-verify egg has valid drop candidates before deducting eggs
		if not rollPetFromEgg(eggInfo) then
			warn(`[EggService] Egg '{data.eggName}' has no valid drops configured`)
			return
		end

		local remainingEggs = currentEggs - amount
		profile.Data.Eggs[data.eggName] = if remainingEggs > 0 then remainingEggs else nil

		Blink.SyncEggs.Fire(player, {
			eggName = data.eggName,
			amount = remainingEggs,
		})

		for _ = 1, amount do
			local rolledPet = rollPetFromEgg(eggInfo)
			if not rolledPet then
				continue
			end

			local petUUID = HttpService:GenerateGUID(false)
			profile.Data.Pets[petUUID] = {
				petName = rolledPet,
				level = 1,
			}

			Blink.SyncPets.Fire(player, {
				isRemoved = false,
				level = 1,
				petName = rolledPet,
				uuid = petUUID,
			})

			Blink.EggHatched.Fire(player, {
				petName = rolledPet,
			})
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastBuyTimes[player] = nil
		lastHatchTimes[player] = nil
	end)
end

return EggService