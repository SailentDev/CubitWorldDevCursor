--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local PetDatabase = require(ReplicatedStorage.Shared:WaitForChild("PetDatabase") :: ModuleScript)

local ANIM_IDS = {
	Idle = "rbxassetid://0000000000",
	Walk = "rbxassetid://0000000001",
}

local SLOT_OFFSETS = {
	Vector3.new(-2, 0, -2.5),
	Vector3.new( 0, 0, -3),  
	Vector3.new( 2, 0, -2.5),
}

type PlayerPetData = {
	equippedUUIDs: { string },
	models: { Model },
	charConn: RBXScriptConnection?,
	lastPositions: { [Model]: Vector3 },
}
local playerData: { [Player]: PlayerPetData } = {}
local petAnimations: { [Model]: { idleTrack: AnimationTrack?, walkTrack: AnimationTrack? } } = {}

-- Słownik wiążący UUID z nazwą modelu zasobu
local uuidToPetName: { [string]: string } = {}

local PetClient = {}

local equippedChangedEvent = Instance.new("BindableEvent")
PetClient.EquippedChanged = equippedChangedEvent.Event

function PetClient.IsPetEquipped(uuid: string): boolean
	local localData = playerData[Players.LocalPlayer]
	if not localData then return false end
	return table.find(localData.equippedUUIDs, uuid) ~= nil
end

local function getGroundHeight(origin: Vector3, rootPos: Vector3): number?
	local RAY_DISTANCE = 20
	local MAX_STEPS = 10
	local STEP_DISTANCE = 0.5

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}

	local currentPos = origin
	for step = 0, MAX_STEPS do
		local rayOrigin = currentPos + Vector3.new(0, 1, 0)
		local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -RAY_DISTANCE, 0), params)
		if result then
			return result.Position.Y
		end
		local direction = (rootPos - currentPos) * Vector3.new(1, 0, 1)
		if direction.Magnitude < 0.01 then
			break
		end
		currentPos += direction.Unit * STEP_DISTANCE
	end
	return nil
end

local function setupAnimations(model: Model)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		local controller = model:FindFirstChildWhichIsA("AnimationController")
		if controller then
			animator = controller.Animator
		end
	end
	
	if not animator then 
		petAnimations[model] = { idleTrack = nil, walkTrack = nil }
		return 
	end

	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = ANIM_IDS.Idle
	local idleTrack = animator:LoadAnimation(idleAnim)

	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = ANIM_IDS.Walk
	local walkTrack = animator:LoadAnimation(walkAnim)

	petAnimations[model] = {
		idleTrack = idleTrack,
		walkTrack = walkTrack
	}

	if idleTrack then idleTrack:Play() end
end

local function refreshPets(player: Player, character: Model?)
	if not character then return end

	local data = playerData[player]
	if not data then return end

	for _, model in ipairs(data.models) do
		petAnimations[model] = nil
		model:Destroy()
	end
	data.models = {}
	data.lastPositions = {}

	local equippedUUIDs = data.equippedUUIDs
	if #equippedUUIDs == 0 then return end

	local shared = ReplicatedStorage:WaitForChild("Shared")
	local assets = shared:WaitForChild("Assets")
	local petFolder = assets:WaitForChild("Pets", 5) :: Folder?
	
	if not petFolder then
		warn("[PetClient] Folder 'Pets' nie pojawił się w Assets!")
		return
	end

	for i, uuid in ipairs(equippedUUIDs) do
		local petName = uuidToPetName[uuid]
		if not petName then
			warn("[PetClient] Brak zmapowanej nazwy zasobu dla UUID:", uuid)
			continue
		end

		local template = petFolder:WaitForChild(petName, 5) :: Model?
		if not template then
			warn("[PetClient] Brak zreplikowanego modelu dla peta (Timeout):", petName)
			continue
		end

		local model = template:Clone() :: Model
		model.Parent = Workspace

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end

		setupAnimations(model)

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			model:PivotTo(rootPart.CFrame)
		end

		table.insert(data.models, model)
		data.lastPositions[model] = model:GetPivot().Position
	end
end

local function onHeartbeat(dt: number)
	for player, data in pairs(playerData) do
		local character = player.Character
		if not character then continue end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end

		local playerCFrame = rootPart.CFrame
		local playerPos = playerCFrame.Position
		local playerLook = playerCFrame.LookVector

		for i, model in ipairs(data.models) do
			local offset = SLOT_OFFSETS[i] or SLOT_OFFSETS[#SLOT_OFFSETS]
			local targetWorld = playerCFrame:PointToWorldSpace(offset)

			local groundY = getGroundHeight(targetWorld, playerPos)
			if groundY then
				targetWorld = Vector3.new(targetWorld.X, groundY, targetWorld.Z)
			else
				targetWorld = Vector3.new(targetWorld.X, playerPos.Y, targetWorld.Z)
			end

			local prevPos = data.lastPositions[model]
			local currentPos = model:GetPivot().Position
			local velocity = prevPos and ((currentPos - prevPos) / dt) or Vector3.zero
			data.lastPositions[model] = currentPos

			local moveMagnitude = velocity.Magnitude

			local lookTarget
			if moveMagnitude > 0.5 then
				local moveDir = Vector3.new(velocity.X, 0, velocity.Z).Unit
				if moveDir.Magnitude > 0.01 then
					lookTarget = currentPos + moveDir
				else
					lookTarget = currentPos + playerLook
				end
			else
				lookTarget = currentPos + Vector3.new(playerLook.X, 0, playerLook.Z).Unit
			end

			local desiredCF = CFrame.lookAt(targetWorld, lookTarget)
			local currentCF = model:GetPivot()
			local newCF = currentCF:Lerp(desiredCF, 1 - math.exp(-10 * dt))
			model:PivotTo(newCF)

			-- Bezpieczne pobieranie animacji z tabeli, a nie z Instancji modelu
			local anims = petAnimations[model]
			local idleTrack = anims and anims.idleTrack
			local walkTrack = anims and anims.walkTrack

			if idleTrack and walkTrack then
				if moveMagnitude > 0.5 then
					if walkTrack.IsPlaying == false then
						walkTrack:Play()
						idleTrack:Stop()
					end
				else
					if idleTrack.IsPlaying == false then
						idleTrack:Play()
						walkTrack:Stop()
					end
				end
			end
		end
	end
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
			lastPositions = {},
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
			petAnimations[model] = nil
			model:Destroy() 
		end
		playerData[player] = nil
	end
end)

function PetClient.OnInit()
	print("[PetClient] Initialized (OnInit)")
end

function PetClient.OnStart()
	print("[PetClient] Starting – hooking network events and Heartbeat")
	Blink.SyncEquippedPets.On(onSyncEquippedPets)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return PetClient