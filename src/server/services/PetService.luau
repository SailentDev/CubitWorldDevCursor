--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local DataManager = require(script.Parent.DataManager)

local MAX_EQUIPPED_PETS = 1

local PetService = {}
local currentEquippedCache: { [number]: { { uuid: string, petName: string } } } = {}

local function przekazModelDoReplicatedStorage(petName: string)
	local sharedAssets = ReplicatedStorage.Shared:WaitForChild("Assets") :: Folder
	local replicatedFolder = sharedAssets:FindFirstChild("Pets") :: Folder
	if not replicatedFolder then
		replicatedFolder = Instance.new("Folder")
		replicatedFolder.Name = "Pets"
		replicatedFolder.Parent = sharedAssets
	end

	if not replicatedFolder:FindFirstChild(petName) then
		local sourceModel = ServerStorage.Assets.Pets:FindFirstChild(petName)
		if sourceModel then
			local clone = sourceModel:Clone()
			clone.Parent = replicatedFolder
		end
	end
end

local function getEquippedPetsData(profile: any): { { uuid: string, petName: string } }
	local result = {}
	if profile and profile.Data.EquippedPets then
		for _, uuid in ipairs(profile.Data.EquippedPets) do
			local petData = profile.Data.Pets[uuid]
			if petData then
				table.insert(result, { uuid = uuid, petName = petData.petName })
			end
		end
	end
	return result
end

function PetService.OnInit() end

function PetService.OnStart()
	print("[PetService] Server Started")

	Blink.RequestEquip.On(function(player: Player, data: { uuid: string })
		local profile = DataManager:GetProfile(player)
		if not profile then return end

		local uuid = data.uuid
		local petData = profile.Data.Pets[uuid]
		if not petData then return end

		local equippedList: { string } = profile.Data.EquippedPets or {}
		local foundIndex = table.find(equippedList, uuid)

		if foundIndex then
			table.remove(equippedList, foundIndex)
		else
			table.clear(equippedList)
			table.insert(equippedList, uuid)
			przekazModelDoReplicatedStorage(petData.petName)
		end
		profile.Data.EquippedPets = equippedList

		local sendData = getEquippedPetsData(profile)
		currentEquippedCache[player.UserId] = sendData

		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedPets = sendData, 
		})
	end)

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = nil
			for i = 1, 30 do
				profile = DataManager:GetProfile(player)
				if profile then break end
				task.wait(0.1)
			end

			if not player:IsDescendantOf(Players) or not profile then return end

			local sendData = getEquippedPetsData(profile)
			currentEquippedCache[player.UserId] = sendData

			for _, pInfo in ipairs(sendData) do
				przekazModelDoReplicatedStorage(pInfo.petName)
			end

			-- Powiedz wszystkim o tym nowym graczu
			Blink.SyncEquippedPets.FireAll({
				userId = player.UserId,
				equippedPets = sendData,
			})

			-- Daj nowemu graczowi dane o wszystkich obecnych na serwerze
			for onlineUserId, onlinePets in pairs(currentEquippedCache) do
				if onlineUserId == player.UserId then continue end
				Blink.SyncEquippedPets.Fire(player, {
					userId = onlineUserId,
					equippedPets = onlinePets,
				})
			end
		end)
	end

	local function onPlayerRemoving(player: Player)
		currentEquippedCache[player.UserId] = nil
		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedPets = {},
		})
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PetService