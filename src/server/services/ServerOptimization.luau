--!strict
local Players = game:GetService("Players")

local ServerOptimization = {}

-- Track active script connections for memory cleanup
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

-- Disconnects a list of connections safely
local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

-- Cleans up any character-specific listeners
local function cleanUpCharacter(player: Player)
	local connections = characterConnections[player]
	if connections then
		disconnectAll(connections)
		characterConnections[player] = nil
	end
end

-- Cleans up player-specific listeners on leave
local function cleanUpPlayer(player: Player)
	cleanUpCharacter(player)
	local connections = playerConnections[player]
	if connections then
		disconnectAll(connections)
		playerConnections[player] = nil
	end
end

-- Disables collision and query overhead on accessories
local function optimizeAccessory(accessory: Accessory)
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanTouch = false
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
end

-- Applies global optimization routines on a spawned character
local function optimizeCharacter(player: Player, character: Model)
	cleanUpCharacter(player)

	local connections: { RBXScriptConnection } = {}

	-- Helper function to apply part-specific configurations
	local function optimizePart(part: BasePart)
		part.CollisionGroup = "Players"
	end

	-- Full scanning pass of the character
	local function runInitialPass()
		if not character:IsDescendantOf(workspace) then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			-- Disable server-side scaling updates to limit joint recalculations
			humanoid.AutomaticScalingEnabled = false

			-- Disable unnecessary physics/state check routines
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		end

		-- Apply updates to existing structures
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("FaceControls") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				local ancestorAccessory = descendant:FindFirstAncestorOfClass("Accessory")
				if ancestorAccessory then
					descendant.CanTouch = false
					descendant.CanCollide = false
					descendant.CanQuery = false
				end
				optimizePart(descendant)
			elseif descendant:IsA("Accessory") then
				optimizeAccessory(descendant)
			end
		end
	end

	-- Defer execution to prevent thread blocking during the spawn pipeline
	task.defer(runInitialPass)

	-- Handle late-loading dynamic descendants (accessories, shirts, or faces)
	local descAddedConn = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("FaceControls") then
			-- Defer deletion to avoid structural errors during initialization
			task.defer(function()
				if descendant.Parent then
					descendant:Destroy()
				end
			end)
		elseif descendant:IsA("BasePart") then
			local ancestorAccessory = descendant:FindFirstAncestorOfClass("Accessory")
			if ancestorAccessory then
				descendant.CanTouch = false
				descendant.CanCollide = false
				descendant.CanQuery = false
			end
			optimizePart(descendant)
		elseif descendant:IsA("Accessory") then
			optimizeAccessory(descendant)
		end
	end)

	table.insert(connections, descAddedConn)
	characterConnections[player] = connections
end

-- Initializes player connections and registers listeners
function ServerOptimization.Init()
	local function onPlayerAdded(player: Player)
		local connections: { RBXScriptConnection } = {}

		local charAddedConn = player.CharacterAdded:Connect(function(character)
			optimizeCharacter(player, character)
		end)
		table.insert(connections, charAddedConn)

		playerConnections[player] = connections

		-- Check for an already existing character
		if player.Character then
			optimizeCharacter(player, player.Character)
		end
	end

	-- Register hooks for server players
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(cleanUpPlayer)

	-- Scan players already in-game upon execution
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return ServerOptimization