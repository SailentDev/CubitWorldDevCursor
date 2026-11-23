--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local Types = require(ReplicatedStorage.Shared.Types)

local GROUND_CHECK_HEIGHT = 5.0
local RAY_DISTANCE = 25.0
local MAX_CLIMB_HEIGHT = 5.5
local EXTRA_GROUND_OFFSET = 0.2
local SNAP_DISTANCE = 20
local SMOOTHNESS_NORMAL = 8
local SMOOTHNESS_FAST = 15
local LOD_CULL_DISTANCE = 350

-- Multi-part welded pets must be verified in Studio when using BulkMoveTo vs direct rootPart.CFrame.
local USE_BULK_MOVE = true

local IDLE_POS_EPSILON_SQ = 0.0025
local IDLE_LOOK_DOT = 0.9995
local CONVERGED_DIST_SQ = 0.0025

local RAY_DIRECTION = Vector3.new(0, -RAY_DISTANCE, 0)
local PLAYER_GROUND_RAY = Vector3.new(0, -15, 0)
local FALLBACK_LOOK_DIR = Vector3.new(0, 0, -1)

type EquippedPetInfo = Types.EquippedPetInfo

type ActivePet = {
	model: Model,
	rootPart: BasePart,
	heightOffset: number,
	relativeOffset: Vector3,
}

type PlayerPetData = {
	equippedPets: { EquippedPetInfo },
	models: { Model },
	connections: { RBXScriptConnection },
	isPetsHidden: boolean,
	refreshGen: number,
	lastHrpPos: Vector3?,
	lastLookDir: Vector3?,
	converged: boolean,
}

local playerData: { [Player]: PlayerPetData } = {}
local playerActivePets: { [Player]: { ActivePet } } = {}
local petUpdater: RBXScriptConnection? = nil
local cachedPetsFolder: Folder? = nil

local sharedRayParams = RaycastParams.new()
sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
sharedRayParams.CollisionGroup = "PetProbe"
sharedRayParams.RespectCanCollide = true

local bulkParts: { BasePart } = {}
local bulkCFrames: { CFrame } = {}

local PetClient = {}
local equippedChangedEvent = Instance.new("BindableEvent")
PetClient.EquippedChanged = equippedChangedEvent.Event

local function getPetsFolder(): Folder?
	if cachedPetsFolder and cachedPetsFolder.Parent then
		return cachedPetsFolder
	end

	local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
	local assetsFolder = if sharedFolder then sharedFolder:WaitForChild("Assets", 10) else nil
	local petsFolder = if assetsFolder then assetsFolder:WaitForChild("Pets", 10) else nil

	if petsFolder and petsFolder:IsA("Folder") then
		cachedPetsFolder = petsFolder
		return petsFolder
	end
	return nil
end

local function clearPlayerModels(data: PlayerPetData): ()
	for _, model in data.models do
		model:Destroy()
	end
	table.clear(data.models)
	data.isPetsHidden = false
	data.lastHrpPos = nil
	data.lastLookDir = nil
	data.converged = false
end

local function stopPetUpdater(): ()
	if petUpdater then
		petUpdater:Disconnect()
		petUpdater = nil
	end
	table.clear(playerActivePets)
	table.clear(bulkParts)
	table.clear(bulkCFrames)
end

local function startPetUpdater(): ()
	if petUpdater then
		return
	end

	petUpdater = RunService.Heartbeat:Connect(function(deltaTime: number)
		local localPlayer = Players.LocalPlayer
		if not localPlayer then
			return
		end

		local localChar = localPlayer.Character
		local localHrp = if localChar then localChar:FindFirstChild("HumanoidRootPart") else nil
		local localPos = if localHrp and localHrp:IsA("BasePart") then localHrp.Position else Vector3.zero

		local clampedDt = math.min(deltaTime, 0.1)
		local alphaNormal = 1 - math.exp(-SMOOTHNESS_NORMAL * clampedDt)
		local alphaFast = 1 - math.exp(-SMOOTHNESS_FAST * clampedDt)

		if USE_BULK_MOVE then
			table.clear(bulkParts)
			table.clear(bulkCFrames)
		end

		for player, pets in playerActivePets do
			if #pets == 0 then
				continue
			end

			local data = playerData[player]
			if not data then
				continue
			end

			local character = player.Character
			local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if not hrp or not hrp:IsA("BasePart") or not hrp.Parent then
				continue
			end

			local hrpCFrame = hrp.CFrame
			local hrpPos = hrpCFrame.Position

			-- LOD check before vector/raycast work
			if player ~= localPlayer and (hrpPos - localPos).Magnitude > LOD_CULL_DISTANCE then
				if not data.isPetsHidden then
					data.isPetsHidden = true
					for _, pet in pets do
						if pet.model then
							pet.model.Parent = nil
						end
					end
				end
				continue
			end

			local lookVec = hrpCFrame.LookVector
			local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
			local flatLookDir = if flatLook.Magnitude > 1e-3 then flatLook.Unit else FALLBACK_LOOK_DIR
			local flatHrpCFrame = CFrame.lookAt(hrpPos, hrpPos + flatLookDir)

			if data.isPetsHidden then
				data.isPetsHidden = false
				data.converged = false
				for _, pet in pets do
					if pet.model then
						pet.model.Parent = Workspace
						local targetPos = (flatHrpCFrame * CFrame.new(pet.relativeOffset)).Position
						local snapY = hrpPos.Y - 3 + pet.heightOffset + EXTRA_GROUND_OFFSET
						local snapPos = Vector3.new(targetPos.X, snapY, targetPos.Z)
						pet.rootPart.CFrame = CFrame.lookAt(snapPos, snapPos + flatLookDir)
					end
				end
			end

			-- Skip expensive raycasts if player is stationary and pets have converged
			local lastPos = data.lastHrpPos
			local lastDir = data.lastLookDir
			if data.converged and lastPos and lastDir then
				local posDelta = hrpPos - lastPos
				if posDelta:Dot(posDelta) < IDLE_POS_EPSILON_SQ and flatLookDir:Dot(lastDir) > IDLE_LOOK_DOT then
					continue
				end
			end

			data.lastHrpPos = hrpPos
			data.lastLookDir = flatLookDir

			local playerRayResult = Workspace:Raycast(hrpPos + Vector3.new(0, 2, 0), PLAYER_GROUND_RAY, sharedRayParams)
			local playerGroundY = if playerRayResult then playerRayResult.Position.Y else (hrpPos.Y - 3)

			local allConverged = true

			for _, pet in pets do
				local rootPart = pet.rootPart
				if not rootPart or not rootPart.Parent then
					continue
				end

				local idealPos = (flatHrpCFrame * CFrame.new(pet.relativeOffset)).Position
				local horizOrigin = Vector3.new(hrpPos.X, hrpPos.Y - 1, hrpPos.Z)
				local horizDir = idealPos - horizOrigin

				local wallResult = Workspace:Raycast(horizOrigin, horizDir, sharedRayParams)
				local finalHorizPos = if wallResult then wallResult.Position + (wallResult.Normal * 1.2) else idealPos

				local petRayOrigin = Vector3.new(finalHorizPos.X, hrpPos.Y + GROUND_CHECK_HEIGHT, finalHorizPos.Z)
				local rayResult = Workspace:Raycast(petRayOrigin, RAY_DIRECTION, sharedRayParams)

				local baseGroundY = playerGroundY
				if rayResult and (rayResult.Position.Y - playerGroundY) <= MAX_CLIMB_HEIGHT then
					baseGroundY = rayResult.Position.Y
				end

				local finalPos = Vector3.new(finalHorizPos.X, baseGroundY + pet.heightOffset + EXTRA_GROUND_OFFSET, finalHorizPos.Z)
				local goalCFrame = CFrame.lookAt(finalPos, finalPos + flatLookDir)

				local diff = finalPos - rootPart.Position
				local distSq = diff:Dot(diff)

				local nextCFrame: CFrame
				if distSq > (SNAP_DISTANCE * SNAP_DISTANCE) then
					nextCFrame = goalCFrame
					allConverged = false
				elseif distSq <= CONVERGED_DIST_SQ and rootPart.CFrame.LookVector:Dot(flatLookDir) > IDLE_LOOK_DOT then
					nextCFrame = goalCFrame
				else
					local alpha = if distSq > 25 then alphaFast else alphaNormal
					nextCFrame = rootPart.CFrame:Lerp(goalCFrame, alpha)
					allConverged = false
				end

				if USE_BULK_MOVE then
					table.insert(bulkParts, rootPart)
					table.insert(bulkCFrames, nextCFrame)
				else
					rootPart.CFrame = nextCFrame
				end
			end

			data.converged = allConverged
		end

		if USE_BULK_MOVE and #bulkParts > 0 then
			Workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

local function refreshPetsAsync(player: Player, character: Model?): ()
	local data = playerData[player]
	if not data then
		return
	end

	data.refreshGen += 1
	local myGen = data.refreshGen

	clearPlayerModels(data)
	playerActivePets[player] = nil

	local equippedPets = data.equippedPets
	if #equippedPets == 0 or not character or not character.Parent then
		if next(playerActivePets) == nil then
			stopPetUpdater()
		end
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if myGen ~= data.refreshGen then
		return
	end
	if not character.Parent then
		clearPlayerModels(data)
		return
	end
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local petFolder = getPetsFolder()
	if myGen ~= data.refreshGen then
		return
	end
	if not character.Parent then
		clearPlayerModels(data)
		return
	end
	if not petFolder then
		return
	end

	local activeList: { ActivePet } = {}
	local totalCount = #equippedPets

	for i, petInfo in equippedPets do
		local template = petFolder:FindFirstChild(petInfo.petName) or petFolder:WaitForChild(petInfo.petName, 5)
		if myGen ~= data.refreshGen then
			return
		end
		if not character.Parent then
			clearPlayerModels(data)
			return
		end

		if not template or not template:IsA("Model") then
			continue
		end

		local model = template:Clone()
		local petRoot = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not petRoot then
			model:Destroy()
			continue
		end

		model.PrimaryPart = petRoot

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.CastShadow = false

				if descendant ~= petRoot then
					descendant.Massless = true
					descendant.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = descendant
					weld.Part1 = petRoot
					weld.Parent = descendant
				else
					descendant.Anchored = true
				end
			end
		end

		local spacing = 2.2
		local rightSideShift = 2.8
		local xOffset = ((i - (totalCount + 1) / 2) * spacing) + rightSideShift
		local zOffset = 6.0
		local relativeOffset = Vector3.new(xOffset, 0.1, zOffset)

		model:PivotTo(hrp.CFrame * CFrame.new(relativeOffset))
		model.Parent = Workspace
		table.insert(data.models, model)

		local petExtents = model:GetExtentsSize()
		table.insert(activeList, {
			model = model,
			rootPart = petRoot,
			heightOffset = petExtents.Y / 2,
			relativeOffset = relativeOffset,
		})
	end

	if #activeList > 0 then
		playerActivePets[player] = activeList
		startPetUpdater()
	elseif next(playerActivePets) == nil then
		stopPetUpdater()
	end
end

function PetClient.IsPetEquipped(uuid: string): boolean
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return false
	end

	local localData = playerData[localPlayer]
	if not localData then
		return false
	end

	for _, petInfo in localData.equippedPets do
		if petInfo.uuid == uuid then
			return true
		end
	end
	return false
end

local function setupPlayerTracking(player: Player): PlayerPetData
	local existing = playerData[player]
	if existing then
		return existing
	end

	local data: PlayerPetData = {
		equippedPets = {},
		models = {},
		connections = {},
		isPetsHidden = false,
		refreshGen = 0,
		lastHrpPos = nil,
		lastLookDir = nil,
		converged = false,
	}

	table.insert(data.connections, player.CharacterAdded:Connect(function(char: Model)
		task.spawn(refreshPetsAsync, player, char)
	end))

	table.insert(data.connections, player.CharacterRemoving:Connect(function()
		data.refreshGen += 1
		clearPlayerModels(data)
		playerActivePets[player] = nil
		if next(playerActivePets) == nil then
			stopPetUpdater()
		end
	end))

	playerData[player] = data
	return data
end

local function onSyncEquippedPets(payload: { userId: number, equippedPets: { EquippedPetInfo } }): ()
	local player = Players:GetPlayerByUserId(payload.userId)
	if not player then
		return
	end

	local data = setupPlayerTracking(player)
	data.equippedPets = payload.equippedPets or {}

	if player == Players.LocalPlayer then
		equippedChangedEvent:Fire(data.equippedPets)
	end

	task.spawn(refreshPetsAsync, player, player.Character)
end

function PetClient.OnInit(): ()
end

function PetClient.OnStart(): ()
	Blink.SyncEquippedPets.On(onSyncEquippedPets)

	Players.PlayerRemoving:Connect(function(player: Player)
		local data = playerData[player]
		if data then
			data.refreshGen += 1
			for _, conn in data.connections do
				conn:Disconnect()
			end
			clearPlayerModels(data)
			playerData[player] = nil
		end

		playerActivePets[player] = nil
		if next(playerActivePets) == nil then
			stopPetUpdater()
		end
	end)
end

return PetClient