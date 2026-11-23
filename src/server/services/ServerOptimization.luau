--!strict
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ServerOptimization = {}

local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function disconnectAll(connections: { RBXScriptConnection }): ()
	for _, connection in connections do
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

local function cleanUpCharacter(player: Player): ()
	local connections = characterConnections[player]
	if connections then
		disconnectAll(connections)
		characterConnections[player] = nil
	end
end

local function cleanUpPlayer(player: Player): ()
	cleanUpCharacter(player)
	local connections = playerConnections[player]
	if connections then
		disconnectAll(connections)
		playerConnections[player] = nil
	end
end

local function optimizePart(part: BasePart): ()
	if part:FindFirstAncestorOfClass("Accessory") then
		part.CanTouch = false
		part.CanCollide = false
		part.CanQuery = false
	end

	part.CollisionGroup = "Players"
	part.CastShadow = false
end

local function optimizeCharacter(player: Player, character: Model): ()
	cleanUpCharacter(player)

	local connections: { RBXScriptConnection } = {}

	local function runInitialPass(): ()
		if not character:IsDescendantOf(Workspace) then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutomaticScalingEnabled = false
			humanoid.BreakJointsOnDeath = false

			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			pcall(function()
				if rootPart:CanSetNetworkOwnership() then
					rootPart:SetNetworkOwner(player)
				end
			end)
		end

		for _, descendant in character:GetDescendants() do
			if descendant:IsA("FaceControls") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				optimizePart(descendant)
			end
		end
	end

	task.defer(runInitialPass)

	local descAddedConn = character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("FaceControls") then
			task.defer(function()
				if descendant.Parent then
					descendant:Destroy()
				end
			end)
		elseif descendant:IsA("BasePart") then
			optimizePart(descendant)
		end
	end)

	table.insert(connections, descAddedConn)
	characterConnections[player] = connections
end

function ServerOptimization.OnInit(): ()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Camera")
	end)
end

function ServerOptimization.OnStart(): ()
	local function onPlayerAdded(player: Player): ()
		local connections: { RBXScriptConnection } = {}

		table.insert(connections, player.CharacterAdded:Connect(function(character: Model)
			optimizeCharacter(player, character)
		end))

		table.insert(connections, player.CharacterRemoving:Connect(function()
			cleanUpCharacter(player)
		end))

		playerConnections[player] = connections

		if player.Character then
			optimizeCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(cleanUpPlayer)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ServerOptimization