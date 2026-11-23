--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Blink = require(ServerScriptService.Net.network_server)
local PetDatabase = require(ReplicatedStorage.Shared.PetDatabase)
local Types = require(ReplicatedStorage.Shared.Types)

local DataManager = require(ServerScriptService.services.DataManager)
local InventoryService = require(ServerScriptService.services.InventoryService)
local RateLimiter = require(ServerScriptService.Util.RateLimiter)

local MAX_EQUIPPED_PETS = 1
local EQUIP_COOLDOWN_SECONDS = 0.2

local PetService = {}

local currentEquippedCache: { [number]: { Types.EquippedPetInfo } } = {}
local equipLimiter = RateLimiter.new(1, 1 / EQUIP_COOLDOWN_SECONDS)

local function getOrCreateReplicatedPetsFolder(): Folder
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared") :: Folder

	local assetsFolder = sharedFolder:FindFirstChild("Assets")
	if not assetsFolder or not assetsFolder:IsA("Folder") then
		local newAssets = Instance.new("Folder")
		newAssets.Name = "Assets"
		newAssets.Parent = sharedFolder
		assetsFolder = newAssets
	end

	local petsFolder = (assetsFolder :: Folder):FindFirstChild("Pets")
	if not petsFolder or not petsFolder:IsA("Folder") then
		local newPets = Instance.new("Folder")
		newPets.Name = "Pets"
		newPets.Parent = assetsFolder
		petsFolder = newPets
	end

	return petsFolder :: Folder
end

local function ensurePetTemplateReplicated(petName: string): ()
	local replicatedFolder = getOrCreateReplicatedPetsFolder()
	if replicatedFolder:FindFirstChild(petName) then
		return
	end

	local serverAssets = ServerStorage:FindFirstChild("Assets")
	local serverPets = if serverAssets then serverAssets:FindFirstChild("Pets") else nil
	local sourceModel = if serverPets then serverPets:FindFirstChild(petName) else nil

	if sourceModel and sourceModel:IsA("Model") then
		local clone = sourceModel:Clone()
		clone.Parent = replicatedFolder
	end
end

local function pruneEquippedList(profile: Types.PlayerProfile): { string }
	local rawList = profile.Data.EquippedPets
	local validList: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, uuid in rawList do
		if typeof(uuid) == "string" and not seen[uuid] then
			local petData = profile.Data.Pets[uuid]
			if petData and PetDatabase.GetPetInfo(petData.petName) then
				seen[uuid] = true
				table.insert(validList, uuid)
				if #validList >= MAX_EQUIPPED_PETS then
					break
				end
			end
		end
	end

	profile.Data.EquippedPets = validList
	return validList
end

local function buildEquippedPetsData(profile: Types.PlayerProfile): { Types.EquippedPetInfo }
	local result: { Types.EquippedPetInfo } = {}
	for _, uuid in profile.Data.EquippedPets do
		local petData = profile.Data.Pets[uuid]
		if petData then
			table.insert(result, {
				uuid = uuid,
				petName = petData.petName,
			})
		end
	end
	return result
end

local function equippedListsEqual(a: { Types.EquippedPetInfo }?, b: { Types.EquippedPetInfo }): boolean
	if not a or #a ~= #b then
		return false
	end
	for i, itemA in a do
		local itemB = b[i]
		if not itemB or itemA.uuid ~= itemB.uuid or itemA.petName ~= itemB.petName then
			return false
		end
	end
	return true
end

local function onInventoryPetsChanged(player: Player, action: InventoryService.PetChangeAction, _uuid: string, _petData: Types.PetInstanceData): ()
	if action ~= "Removed" then
		return
	end

	local profile = DataManager:GetProfile(player)
	if not profile then
		return
	end

	local previousCache = currentEquippedCache[player.UserId]
	pruneEquippedList(profile)
	local sendData = buildEquippedPetsData(profile)
	currentEquippedCache[player.UserId] = sendData

	if not equippedListsEqual(previousCache, sendData) then
		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedPets = sendData,
		})
	end
end

local function onProfileLoaded(player: Player, profile: Types.PlayerProfile): ()
	pruneEquippedList(profile)
	local sendData = buildEquippedPetsData(profile)
	currentEquippedCache[player.UserId] = sendData

	for _, petInfo in sendData do
		ensurePetTemplateReplicated(petInfo.petName)
	end

	-- Replicate immediately to already-connected players; the joining player receives all snapshots on RequestInitialSync
	Blink.SyncEquippedPets.FireExcept(player, {
		userId = player.UserId,
		equippedPets = sendData,
	})
end

local function onPlayerInitialSync(player: Player, _profile: Types.PlayerProfile): ()
	for onlineUserId, onlinePets in currentEquippedCache do
		Blink.SyncEquippedPets.Fire(player, {
			userId = onlineUserId,
			equippedPets = onlinePets,
		})
	end
end

function PetService.OnInit(): ()
	getOrCreateReplicatedPetsFolder()
	DataManager.OnProfileLoaded(onProfileLoaded)
	DataManager.OnInitialSync(onPlayerInitialSync)
	InventoryService.OnPetsChanged(onInventoryPetsChanged)
end

function PetService.OnStart(): ()
	Blink.RequestEquip.On(function(player: Player, data: { uuid: string })
		if not equipLimiter:Consume(player) then
			return
		end

		if typeof(data) ~= "table" or typeof(data.uuid) ~= "string" or #data.uuid == 0 or #data.uuid > 64 then
			return
		end

		local profile = DataManager:GetProfile(player)
		if not profile then
			return
		end

		local uuid = data.uuid
		local petData = profile.Data.Pets[uuid]
		if not petData or not PetDatabase.GetPetInfo(petData.petName) then
			return
		end

		local equippedList = pruneEquippedList(profile)
		local foundIndex = table.find(equippedList, uuid)

		if foundIndex then
			table.remove(equippedList, foundIndex)
		else
			while #equippedList >= MAX_EQUIPPED_PETS do
				table.remove(equippedList, 1)
			end
			table.insert(equippedList, uuid)
			ensurePetTemplateReplicated(petData.petName)
		end

		profile.Data.EquippedPets = equippedList

		local sendData = buildEquippedPetsData(profile)
		currentEquippedCache[player.UserId] = sendData

		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedPets = sendData,
		})
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		equipLimiter:Clear(player)
		currentEquippedCache[player.UserId] = nil

		Blink.SyncEquippedPets.FireExcept(player, {
			userId = player.UserId,
			equippedPets = {},
		})
	end)
end

return PetService