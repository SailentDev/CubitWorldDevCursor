--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Blink = require(ReplicatedStorage.Shared.Blink.network_server)
local DataManager = require(script.Parent.DataManager)
local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)

-- Zmieniono limit na 1
local MAX_EQUIPPED_PETS = 1

local PetService = {}

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
		
		-- ANTY-CHEAT ZABEZPIECZENIE: Jeśli gracz nie posiada peta o takim UUID w bazie, przerywamy!
		if not petData then 
			warn(string.format("[PetService -> ANTY-CHEAT] Gracz %s próbował założyć nieposiadanego peta!", player.Name))
			return 
		end

		local equippedList: { string } = profile.Data.EquippedPets
		local foundIndex = table.find(equippedList, uuid)

		if foundIndex then
			-- Jeśli gracz kliknął peta, którego JUŻ MA załozonego -> zdejmij go
			table.remove(equippedList, foundIndex)
			print("[PetService] Zdjęto peta o UUID:", uuid)
		else
			-- AUTOMATYCZNA PODMIANA & ANTY-CHEAT: 
			-- Czyszczenie całej tablicy gwarantuje, że stary pet zostanie automatycznie zdjęty,
			-- a cheater nie będzie w stanie ominąć limitu poprzez spamowanie pakietami.
			table.clear(equippedList)
			table.insert(equippedList, uuid)
			print("[PetService] Założono nowy pet o UUID:", uuid, "oraz automatycznie zdjęto poprzedni.")

			-- Replikacja modelu na żądanie przy założeniu
			przekazModelDoReplicatedStorage(petData.petName)
		end

		-- Wysłanie aktualnej listy (zawsze max 1 pet) do wszystkich klientów
		Blink.SyncEquippedPets.FireAll({
			userId = player.UserId,
			equippedUUIDs = equippedList, 
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