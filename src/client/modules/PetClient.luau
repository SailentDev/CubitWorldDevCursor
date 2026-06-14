--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)

-- CONFIGURATION
local GROUND_CHECK_HEIGHT = 5.0     
local RAY_DISTANCE = 25.0           
local MAX_CLIMB_HEIGHT = 5.5        -- Maksymalny stopień/wzniesienie, na które pet może wejść (np. schody)
local EXTRA_GROUND_OFFSET = 0.2     
local SNAP_DISTANCE = 20            
local SMOOTHNESS_NORMAL = 8         
local SMOOTHNESS_FAST = 15          

-- LOD DISTANCES
local LOD_CULL_DISTANCE = 350      

-- OPTIMIZATION: Pre-calculate constant Vectors
local RAY_DIRECTION = Vector3.new(0, -RAY_DISTANCE, 0)
local FALLBACK_LOOK_DIR = Vector3.new(0, 0, -1)

type EquippedPetInfo = { uuid: string, petName: string }
type PlayerPetData = {
	equippedPets: { EquippedPetInfo },
	models: { Model },
	charConn: RBXScriptConnection?,
	isPetsHidden: boolean?,        
}

local playerData: { [Player]: PlayerPetData } = {}
local uuidToPetName: { [string]: string } = {}

type ActivePet = {
	model: Model,
	rootPart: BasePart,
	heightOffset: number, 
	relativeOffset: Vector3,
}

local playerActivePets: { [Player]: {ActivePet} } = {}
local petUpdater: RBXScriptConnection? = nil

local sharedRayParams = RaycastParams.new()
sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
sharedRayParams.RespectCanCollide = true
local raycastExcludeList: {Instance} = {}

local function updateRaycastFilter()
	table.clear(raycastExcludeList)
	for _, modelsList in pairs(playerData) do
		for _, model in ipairs(modelsList.models) do
			table.insert(raycastExcludeList, model)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(raycastExcludeList, p.Character) end
	end
	sharedRayParams.FilterDescendantsInstances = raycastExcludeList
end

local function startPetUpdater()
	if petUpdater then return end
	
	petUpdater = RunService.RenderStepped:Connect(function(deltaTime)
		local localPlayer = Players.LocalPlayer
		if not localPlayer then return end
		local localChar = localPlayer.Character
		local localHrp = localChar and localChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		local localPos = localHrp and localHrp.Position or Vector3.zero

		for player, pets in pairs(playerActivePets) do
			if #pets == 0 then continue end
			
			local character = player.Character
			if not character then continue end
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp or not hrp.Parent then continue end

			local hrpCFrame = hrp.CFrame
			local hrpPos = hrpCFrame.Position
			
			local distToLocal = (hrpPos - localPos).Magnitude
			local isVeryFar = (player ~= localPlayer) and (distToLocal > LOD_CULL_DISTANCE)
			local data = playerData[player]

			local playerLookDir = hrpCFrame.LookVector
			local flatLookDir = Vector3.new(playerLookDir.X, 0, playerLookDir.Z)
			flatLookDir = if flatLookDir.Magnitude > 0.001 then flatLookDir.Unit else FALLBACK_LOOK_DIR
			local flatHrpCFrame = CFrame.lookAt(hrpPos, hrpPos + flatLookDir)

			if isVeryFar then
				if data and not data.isPetsHidden then
					data.isPetsHidden = true
					for _, pet in ipairs(pets) do
						if pet.model then pet.model.Parent = nil end 
					end
				end
				continue 
			else
				if data and data.isPetsHidden then
					data.isPetsHidden = false
					for _, pet in ipairs(pets) do
						if pet.model then 
							pet.model.Parent = Workspace 
							local targetCFrame = flatHrpCFrame * CFrame.new(pet.relativeOffset)
							local finalY = hrpPos.Y - 3 + pet.heightOffset + EXTRA_GROUND_OFFSET
							pet.rootPart.CFrame = CFrame.lookAt(Vector3.new(targetCFrame.Position.X, finalY, targetCFrame.Position.Z), targetCFrame.Position + flatLookDir)
						end
					end
				end
			end

			-- Pobieramy aktualny poziom gruntu gracza jako punkt odniesienia
			local playerRayOrigin = hrpPos + Vector3.new(0, 2, 0)
			local playerRayResult = Workspace:Raycast(playerRayOrigin, Vector3.new(0, -15, 0), sharedRayParams)
			local playerGroundY = if playerRayResult then playerRayResult.Position.Y else (hrpPos.Y - 3)

			for _, pet in ipairs(pets) do
				local rootPart = pet.rootPart
				if not rootPart or not rootPart.Parent then continue end

				local targetCFrame = flatHrpCFrame * CFrame.new(pet.relativeOffset)
				local idealPos = targetCFrame.Position
				
				-- ====================================================================
				-- POZIOME OMIJANIE PRZESZKÓD (np. pni drzew, ścian)
				-- ====================================================================
				local horizontalRayOrigin = Vector3.new(hrpPos.X, hrpPos.Y - 1, hrpPos.Z)
				local horizontalRayDir = idealPos - horizontalRayOrigin
				
				local wallResult = Workspace:Raycast(horizontalRayOrigin, horizontalRayDir, sharedRayParams)
				local finalHorizontalPos = idealPos

				if wallResult then
					finalHorizontalPos = wallResult.Position + (wallResult.Normal * 1.2)
				end
				-- ====================================================================

				-- Pionowy test wysokości gruntu w miejscu, gdzie pet docelowo wyląduje
				local petRayOrigin = Vector3.new(finalHorizontalPos.X, hrpPos.Y + GROUND_CHECK_HEIGHT, finalHorizontalPos.Z)
				local rayResult = Workspace:Raycast(petRayOrigin, RAY_DIRECTION, sharedRayParams)
				
				local baseGroundY = playerGroundY 
				
				if rayResult then
					if (rayResult.Position.Y - playerGroundY) <= MAX_CLIMB_HEIGHT then
						baseGroundY = rayResult.Position.Y
					end
				end

				local finalPos = Vector3.new(finalHorizontalPos.X, baseGroundY + pet.heightOffset + EXTRA_GROUND_OFFSET, finalHorizontalPos.Z)
				local goalCFrame = CFrame.lookAt(finalPos, finalPos + flatLookDir)

				local currentDist = (rootPart.Position - finalPos).Magnitude
				if currentDist > SNAP_DISTANCE then
					rootPart.CFrame = goalCFrame
				else
					local currentSmoothness = (currentDist > 5) and SMOOTHNESS_FAST or SMOOTHNESS_NORMAL
					rootPart.CFrame = rootPart.CFrame:Lerp(goalCFrame, currentSmoothness * deltaTime)
				end
			end
		end
	end)
end

local function stopPetUpdater()
	if petUpdater then petUpdater:Disconnect() petUpdater = nil end
	table.clear(playerActivePets)
end

local PetClient = {}
local equippedChangedEvent = Instance.new("BindableEvent")
PetClient.EquippedChanged = equippedChangedEvent.Event

function PetClient.IsPetEquipped(uuid: string): boolean
	local localData = playerData[Players.LocalPlayer]
	if not localData or not localData.equippedPets then return false end
	
	for _, petInfo in ipairs(localData.equippedPets) do
		if petInfo.uuid == uuid then return true end
	end
	return false
end

local function refreshPets(player: Player, character: Model?)
	if not character then return end
	local hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hrp then return end

	local data = playerData[player]
	if not data then return end

	for _, model in ipairs(data.models) do model:Destroy() end
	data.models = {}
	data.isPetsHidden = false 
	playerActivePets[player] = nil

	local equippedPets = data.equippedPets or {}
	if #equippedPets == 0 then
		local dynamicCount = 0 for _, _ in pairs(playerActivePets) do dynamicCount += 1 end
		if dynamicCount == 0 then stopPetUpdater() end
		updateRaycastFilter()
		return
	end

	local petFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("Pets", 5) :: Folder?
	if not petFolder then return end

	local activeList = {}

	for i, petInfo in ipairs(equippedPets) do
		local petName = petInfo.petName
		local template = petFolder:WaitForChild(petName, 5) :: Model?
		if not template then continue end

		local model = template:Clone() :: Model
		local petRoot = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not petRoot then model:Destroy() continue end

		model.PrimaryPart = petRoot

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				if part ~= petRoot then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part weld.Part1 = petRoot weld.Parent = part
					part.Anchored = false
				else
					part.Anchored = true 
				end
			end
		end

		local spacing = 2.2
		local rightSideShift = 2.8      
		local xOffset = ((i - (#equippedPets + 1) / 2) * spacing) + rightSideShift
		local zOffset = 6.0             
		local petRelativeOffset = Vector3.new(xOffset, 0.1, zOffset)

		model:PivotTo(hrp.CFrame * CFrame.new(petRelativeOffset))
		model.Parent = Workspace
		table.insert(data.models, model)

		local petExtents = model:GetExtentsSize()
		
		table.insert(activeList, {
			model = model,
			rootPart = petRoot,
			heightOffset = petExtents.Y / 2,
			relativeOffset = petRelativeOffset
		})
	end

	if #activeList > 0 then
		playerActivePets[player] = activeList
	end

	updateRaycastFilter()
	startPetUpdater()
end

function PetClient.OnPetSynced(data: { uuid: string, petName: string, level: number, isRemoved: boolean? })
	if data.isRemoved then uuidToPetName[data.uuid] = nil else uuidToPetName[data.uuid] = data.petName end
end

local function onSyncEquippedPets(data: { userId: number, equippedPets: { EquippedPetInfo } })
	local player = Players:GetPlayerByUserId(data.userId)
	if not player then return end

	if not playerData[player] then
		playerData[player] = {
			equippedPets = {},
			models = {},
			charConn = player.CharacterAdded:Connect(function(char) refreshPets(player, char) end)
		}
	end

	playerData[player].equippedPets = data.equippedPets or {}
	refreshPets(player, player.Character)

	if player == Players.LocalPlayer then equippedChangedEvent:Fire(data.equippedPets) end
end

Players.PlayerRemoving:Connect(function(player)
	local data = playerData[player]
	if data then
		if data.charConn then data.charConn:Disconnect() end
		for _, model in ipairs(data.models) do model:Destroy() end
		playerData[player] = nil
		playerActivePets[player] = nil
		
		local dynamicCount = 0 for _, _ in pairs(playerActivePets) do dynamicCount += 1 end
		if dynamicCount == 0 then stopPetUpdater() end
		updateRaycastFilter()
	end
end)

function PetClient.OnInit() end
function PetClient.OnStart() Blink.SyncEquippedPets.On(onSyncEquippedPets) end

return PetClient