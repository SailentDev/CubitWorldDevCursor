--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

-- Łatwa konfiguracja pozycji peta względem gracza
local PET_OFFSET = Vector3.new(5.0, 0.1, 5.0)

-- NEW CONFIGURATION
local GROUND_CHECK_HEIGHT = 100      
local RAY_DISTANCE = 300            
local EXTRA_GROUND_OFFSET = 0.2     
local SNAP_DISTANCE = 20            -- Max horizontal distance before teleporting
local SMOOTHNESS_NORMAL = 8         
local SMOOTHNESS_FAST = 15          

type PlayerPetData = {
	equippedUUIDs: { string },
	models: { Model },
	charConn: RBXScriptConnection?,
}

local playerData: { [Player]: PlayerPetData } = {}
local uuidToPetName: { [string]: string } = {}

type ActivePet = {
	model: Model,
	rootPart: BasePart,
	heightOffset: number, 
}
local activePets: {ActivePet} = {}
local petUpdater: RBXScriptConnection? = nil

local function startPetUpdater()
	if petUpdater then return end
	
	petUpdater = RunService.RenderStepped:Connect(function(deltaTime)
		local pets = table.clone(activePets)
		local character = Players.LocalPlayer.Character
		if not character then return end
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
		if not hrp then return end

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.RespectCanCollide = true 
		
		local excludeList = {character}
		for _, pet in pairs(pets) do
			table.insert(excludeList, pet.model)
		end
		rayParams.FilterDescendantsInstances = excludeList

		for i, pet in pairs(pets) do
			local rootPart = pet.rootPart
			if not rootPart or not rootPart.Parent then continue end

			-- 1. Calculate target position behind player
			local targetCFrame = hrp.CFrame * CFrame.new(PET_OFFSET)
			local targetWorldPos = targetCFrame.Position

			-- 2. Raycast straight down from high up to find the floor
			local origin = targetWorldPos + Vector3.new(0, GROUND_CHECK_HEIGHT, 0)
			local rayResult = Workspace:Raycast(origin, Vector3.new(0, -RAY_DISTANCE, 0), rayParams)

			local finalPos = targetWorldPos
			if rayResult then
				finalPos = rayResult.Position + Vector3.new(0, pet.heightOffset + EXTRA_GROUND_OFFSET, 0)
			else
				finalPos = targetWorldPos - Vector3.new(0, 5, 0)
			end

			-- 3. Calculate Orientation (Look in the same direction as the player)
			local playerLookDir = hrp.CFrame.LookVector
			local flatLookDir = Vector3.new(playerLookDir.X, 0, playerLookDir.Z)
			
			if flatLookDir.Magnitude > 0.001 then
				flatLookDir = flatLookDir.Unit
			else
				flatLookDir = Vector3.new(0, 0, -1)
			end
			
			local lookAtPos = finalPos + flatLookDir
			local goalCFrame = CFrame.lookAt(finalPos, lookAtPos)

			-- 4. Apply Movement
			local distXZ = Vector3.new(rootPart.Position.X - finalPos.X, 0, rootPart.Position.Z - finalPos.Z).Magnitude
			local distY = math.abs(rootPart.Position.Y - finalPos.Y)

			if distXZ > SNAP_DISTANCE or distY > 150 then
				rootPart.CFrame = goalCFrame
			else
				local currentSmoothness = (distXZ > 8) and SMOOTHNESS_FAST or SMOOTHNESS_NORMAL
				rootPart.CFrame = rootPart.CFrame:Lerp(goalCFrame, currentSmoothness * deltaTime)
			end
		end
	end)
end

local function stopPetUpdater()
	if petUpdater then
		petUpdater:Disconnect()
		petUpdater = nil
	end
	table.clear(activePets)
end

local PetClient = {}

local equippedChangedEvent = Instance.new("BindableEvent")
PetClient.EquippedChanged = equippedChangedEvent.Event

function PetClient.IsPetEquipped(uuid: string): boolean
	local localData = playerData[Players.LocalPlayer]
	if not localData then return false end
	return table.find(localData.equippedUUIDs, uuid) ~= nil
end

local function refreshPets(player: Player, character: Model?)
	if not character then return end

	local hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hrp then return end

	local data = playerData[player]
	if not data then return end

	for _, model in ipairs(data.models) do
		model:Destroy()
	end
	data.models = {}

	for _, child in ipairs(hrp:GetChildren()) do
		if child.Name:sub(1, 13) == "PetFollowAtt_" then
			child:Destroy()
		end
	end

	local equippedUUIDs = data.equippedUUIDs
	if #equippedUUIDs == 0 then
		stopPetUpdater()
		return
	end

	local shared = ReplicatedStorage:WaitForChild("Shared")
	local assets = shared:WaitForChild("Assets")
	local petFolder = assets:WaitForChild("Pets", 5) :: Folder?

	if not petFolder then
		warn("[PetClient] Folder 'Pets' nie pojawił się w Assets!")
		return
	end

	table.clear(activePets)

	for i, uuid in ipairs(equippedUUIDs) do
		local petName = uuidToPetName[uuid]
		if not petName then continue end

		local template = petFolder:WaitForChild(petName, 5) :: Model?
		if not template then continue end

		local model = template:Clone() :: Model

		local petRoot = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not petRoot then
			model:Destroy()
			continue
		end

		model.PrimaryPart = petRoot

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				-- REMOVED: part.CollisionGroup = "Pets"
				
				if part ~= petRoot then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = petRoot
					weld.Parent = part
					part.Anchored = false
				else
					part.Anchored = true
				end
			end
		end

		model:PivotTo(hrp.CFrame)
		model.Parent = Workspace

		table.insert(data.models, model)

		local petExtents = model:GetExtentsSize()
		local calculatedHeightOffset = petExtents.Y / 2

		table.insert(activePets, {
			model = model,
			rootPart = petRoot,
			heightOffset = calculatedHeightOffset, 
		})
	end

	startPetUpdater()
end

function PetClient.OnPetSynced(data: { uuid: string, petName: string, level: number, isRemoved: boolean? })
	if data.isRemoved then
		uuidToPetName[data.uuid] = nil
	else
		uuidToPetName[data.uuid] = data.petName
	end
end

local function onSyncEquippedPets(data: { userId: number, equippedUUIDs: { string } })
	local player = Players:GetPlayerByUserId(data.userId)
	if not player then return end

	if not playerData[player] then
		local newData: PlayerPetData = {
			equippedUUIDs = {},
			models = {},
		}
		playerData[player] = newData

		newData.charConn = player.CharacterAdded:Connect(function(char)
			refreshPets(player, char)
		end)
	end

	local pdata = playerData[player]
	pdata.equippedUUIDs = data.equippedUUIDs
	refreshPets(player, player.Character)

	if player == Players.LocalPlayer then
		equippedChangedEvent:Fire(data.equippedUUIDs)
	end
end

Players.PlayerRemoving:Connect(function(player)
	local data = playerData[player]
	if data then
		if data.charConn then data.charConn:Disconnect() end
		for _, model in ipairs(data.models) do
			model:Destroy()
		end
		playerData[player] = nil
		if player == Players.LocalPlayer then
			stopPetUpdater()
		end
	end
end)

function PetClient.OnInit()
	print("[PetClient] Initialized (OnInit)")
end

function PetClient.OnStart()
	print("[PetClient] Starting – hooking Blink network events")
	Blink.SyncEquippedPets.On(onSyncEquippedPets)
end

return PetClient