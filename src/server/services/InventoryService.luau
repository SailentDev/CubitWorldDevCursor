--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Blink = require(ServerScriptService.Net.network_server)
local EggDatabase = require(ReplicatedStorage.Shared.EggDatabase)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local DataManager = require(ServerScriptService.services.DataManager)

export type PetChangeAction = "Added" | "Removed"
export type PetsChangedCallback = (player: Player, action: PetChangeAction, uuid: string, petData: Types.PetInstanceData) -> ()
export type EggsChangedCallback = (player: Player, eggName: string, newAmount: number) -> ()

local MAX_PET_INVENTORY = 500
local MAX_EGG_PER_TYPE = 9999

local InventoryService = {}
InventoryService.MAX_PET_INVENTORY = MAX_PET_INVENTORY
InventoryService.MAX_EGG_PER_TYPE = MAX_EGG_PER_TYPE

local petsChangedCallbacks: { PetsChangedCallback } = {}
local eggsChangedCallbacks: { EggsChangedCallback } = {}

local function isValidPlayer(player: Player): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent ~= nil
end

local function isPositiveInteger(value: number): boolean
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value % 1 == 0
end

local function countPets(pets: { [string]: Types.PetInstanceData }): number
	local count = 0
	for _ in pets do
		count += 1
	end
	return count
end

local function firePetsChanged(player: Player, action: PetChangeAction, uuid: string, petData: Types.PetInstanceData): ()
	for _, callback in table.clone(petsChangedCallbacks) do
		local ok, err = pcall(callback, player, action, uuid, petData)
		if not ok then
			warn(`[InventoryService] OnPetsChanged callback error: {tostring(err)}`)
		end
	end
end

local function fireEggsChanged(player: Player, eggName: string, newAmount: number): ()
	for _, callback in table.clone(eggsChangedCallbacks) do
		local ok, err = pcall(callback, player, eggName, newAmount)
		if not ok then
			warn(`[InventoryService] OnEggsChanged callback error: {tostring(err)}`)
		end
	end
end

function InventoryService.OnPetsChanged(callback: PetsChangedCallback): () -> ()
	table.insert(petsChangedCallbacks, callback)
	return function(): ()
		local index = table.find(petsChangedCallbacks, callback)
		if index then
			table.remove(petsChangedCallbacks, index)
		end
	end
end

function InventoryService.OnEggsChanged(callback: EggsChangedCallback): () -> ()
	table.insert(eggsChangedCallbacks, callback)
	return function(): ()
		local index = table.find(eggsChangedCallbacks, callback)
		if index then
			table.remove(eggsChangedCallbacks, index)
		end
	end
end

function InventoryService:GetPetCount(player: Player): number
	if not isValidPlayer(player) then
		return 0
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return 0
	end

	return countPets(profile.Data.Pets)
end

function InventoryService:CanAddPets(player: Player, amount: number?): boolean
	if not isValidPlayer(player) then
		return false
	end

	local addCount = if amount ~= nil then amount else 1
	if not isPositiveInteger(addCount) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	return countPets(profile.Data.Pets) + addCount <= MAX_PET_INVENTORY
end

function InventoryService:GetEggCount(player: Player, eggName: string): number
	if not isValidPlayer(player) or typeof(eggName) ~= "string" then
		return 0
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return 0
	end

	return profile.Data.Eggs[eggName] or 0
end

function InventoryService:CanAddEggs(player: Player, eggName: string, amount: number): boolean
	if not isValidPlayer(player) or typeof(eggName) ~= "string" or not EggDatabase.GetEggInfo(eggName) then
		return false
	end
	if not isPositiveInteger(amount) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local current = profile.Data.Eggs[eggName] or 0
	return current + amount <= MAX_EGG_PER_TYPE
end

function InventoryService:AddPet(player: Player, petName: string, level: number?): string?
	if not isValidPlayer(player) then
		return nil
	end

	if typeof(petName) ~= "string" or not PetDatabase.GetPetInfo(petName) then
		warn(`[InventoryService] Invalid petName '{tostring(petName)}'`)
		return nil
	end

	local petLevel = if level ~= nil then level else 1
	if not isPositiveInteger(petLevel) or petLevel > 65535 then
		warn(`[InventoryService] Invalid pet level '{tostring(level)}'`)
		return nil
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return nil
	end

	if countPets(profile.Data.Pets) >= MAX_PET_INVENTORY then
		return nil
	end

	local uuid = HttpService:GenerateGUID(false)
	local petData: Types.PetInstanceData = {
		petName = petName,
		level = petLevel,
	}
	profile.Data.Pets[uuid] = petData

	Blink.SyncPets.Fire(player, {
		isRemoved = false,
		level = petLevel,
		petName = petName,
		uuid = uuid,
	})

	firePetsChanged(player, "Added", uuid, petData)
	return uuid
end

function InventoryService:RemovePet(player: Player, uuid: string): boolean
	if not isValidPlayer(player) then
		return false
	end

	if typeof(uuid) ~= "string" or #uuid == 0 or #uuid > 64 then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local petData = profile.Data.Pets[uuid]
	if not petData then
		return false
	end

	profile.Data.Pets[uuid] = nil

	local equippedPets = profile.Data.EquippedPets
	for i = #equippedPets, 1, -1 do
		if equippedPets[i] == uuid then
			table.remove(equippedPets, i)
		end
	end

	Blink.SyncPets.Fire(player, {
		isRemoved = true,
		level = petData.level or 1,
		petName = petData.petName,
		uuid = uuid,
	})

	firePetsChanged(player, "Removed", uuid, petData)
	return true
end

function InventoryService:AddEggs(player: Player, eggName: string, amount: number): boolean
	if not isValidPlayer(player) then
		return false
	end

	if typeof(eggName) ~= "string" or not EggDatabase.GetEggInfo(eggName) then
		warn(`[InventoryService] Invalid eggName '{tostring(eggName)}'`)
		return false
	end

	if not isPositiveInteger(amount) then
		warn(`[InventoryService] Invalid AddEggs amount '{tostring(amount)}'`)
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local currentAmount = profile.Data.Eggs[eggName] or 0
	if currentAmount + amount > MAX_EGG_PER_TYPE then
		return false
	end

	local newAmount = currentAmount + amount
	profile.Data.Eggs[eggName] = newAmount

	Blink.SyncEggs.Fire(player, {
		eggName = eggName,
		amount = newAmount,
	})

	fireEggsChanged(player, eggName, newAmount)
	return true
end

function InventoryService:SpendEggs(player: Player, eggName: string, amount: number): boolean
	if not isValidPlayer(player) then
		return false
	end

	if typeof(eggName) ~= "string" or not EggDatabase.GetEggInfo(eggName) then
		return false
	end

	if not isPositiveInteger(amount) then
		return false
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return false
	end

	local currentAmount = profile.Data.Eggs[eggName] or 0
	if currentAmount < amount then
		return false
	end

	local remainingAmount = currentAmount - amount
	profile.Data.Eggs[eggName] = if remainingAmount > 0 then remainingAmount else nil

	Blink.SyncEggs.Fire(player, {
		eggName = eggName,
		amount = remainingAmount,
	})

	fireEggsChanged(player, eggName, remainingAmount)
	return true
end

function InventoryService.OnInit(): ()
end

function InventoryService.OnStart(): ()
end

return InventoryService