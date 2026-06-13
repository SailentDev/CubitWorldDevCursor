--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local DataManager = require(script.Parent.DataManager)
local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)

local MAX_EQUIPPED_PETS = 3

local PetService = {}

-- Funkcja pomocnicza do bezpiecznej replikacji modelu do ReplicatedStorage
local function przekazModelDoReplicatedStorage(petName: string)
	local sharedAssets = ReplicatedStorage.Shared:WaitForChild("Assets") :: Folder
	local replicatedFolder = sharedAssets:FindFirstChild("Pets") :: Folder
	if not replicatedFolder then
		replicatedFolder = Instance.new("Folder")
		replicatedFolder.Name = "Pets"
		replicatedFolder.Parent = sharedAssets
		print("[PetService] Utworzono folder 'Pets' w Shared.Assets")
	end

	if not replicatedFolder:FindFirstChild(petName) then
		local sourceModel = ServerStorage.Assets.Pets:FindFirstChild(petName)
		if sourceModel then
			local clone = sourceModel:Clone()
			clone.Parent = replicatedFolder
			print("[PetService] Zreplikowano model do ReplicatedStorage:", petName)
		else
			warn("[PetService] Model nie znaleziony w ServerStorage dla peta:", petName)
		end
	end
end

function PetService.OnInit()
	print("[PetService] Initialized (OnInit)")
end

function PetService.OnStart()
	print("[PetService] Starting – hooking events")

	Blink.RequestEquip.On(function(player: Player, data: { uuid: string })
		local profile = DataManager:GetProfile(player)
		if not profile then return end

		if not profile.Data.EquippedPets then
			profile.Data.EquippedPets = {}
		end

		local uuid = data.uuid
		local petData = profile.Data.Pets[uuid]
		if not petData then return end

		local equippedList: { string } = profile.Data.EquippedPets
		local foundIndex = table.find(equippedList, uuid)

		if foundIndex then
			-- Zdejmowanie peta
			table.remove(equippedList, foundIndex)
			print("[PetService] Zdjęto peta o UUID:", uuid)
		else
			-- Zakładanie peta
			if #equippedList >= MAX_EQUIPPED_PETS then return end
			table.insert(equippedList, uuid)

			-- Replikacja modelu na żądanie przy założeniu
			przekazModelDoReplicatedStorage(petData.petName)
		end

		-- POPRAWKA: Wysyłamy oryginalną listę UUID do klientów, a nie nazwy!
		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedUUIDs = equippedList, 
		})
	end)

	-- Replikacja modeli przy wejściu gracza, aby zapobiec Timeoutom na starcie
	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = nil
			for i = 1, 30 do
				profile = DataManager:GetProfile(player)
				if profile then break end
				task.wait(0.1)
			end

			if profile and profile.Data.EquippedPets then
				for _, petUUID in ipairs(profile.Data.EquippedPets) do
					local pData = profile.Data.Pets[petUUID]
					if pData then
						przekazModelDoReplicatedStorage(pData.petName)
					end
				end
			end
		end)
	end

	local function onPlayerRemoving(player: Player)
		local profile = DataManager:GetProfile(player)
		if profile and profile.Data.EquippedPets then
			Blink.SyncEquippedPets.FireAll({
				userId = player.UserId,
				equippedUUIDs = {},
			})
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PetService