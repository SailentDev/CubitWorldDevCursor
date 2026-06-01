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

-- Disables collision, query, and redundant rendering properties on accessories
local function optimizeAccessory(accessory: Accessory)
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanTouch = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CastShadow = false -- Reduces lighting payload data replicated to clients
		end
	end
end

-- Applies global optimization routines on a spawned character
local function optimizeCharacter(player: Player, character: Model)
	cleanUpCharacter(player)

	local connections: { RBXScriptConnection } = {}

	-- Helper function to apply part-specific physics and rendering configurations
	local function optimizePart(part: BasePart)
		part.CollisionGroup = "Players"
		part.CastShadow = false -- ROZWIĄZANIE: Wyłącza cień dla KAŻDEJ części ciała postaci (głowa, tors, kończyny)
	end

	-- Full scanning pass of the character
	local function runInitialPass()
		if not character:IsDescendantOf(workspace) then
			return
		end

		-- 1. Optimize Humanoid settings
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutomaticScalingEnabled = false
			humanoid.BreakJointsOnDeath = false -- Prevents expensive joint-breaking calculations

			-- Disable unnecessary physics state updates
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		end

		-- 2. Explicitly assign network ownership of the RootPart to the client
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			-- Wrap in a pcall as SetNetworkOwner can fail if the character is in the middle of loading/removing
			pcall(function()
				if rootPart:CanSetNetworkOwnership() then
					rootPart:SetNetworkOwner(player)
				end
			end)
		end

		-- 3. Optimize existing descendants
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
				optimizePart(descendant) -- Ta funkcja teraz poprawnie zdejmuje cienie ze wszystkiego
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
			optimizePart(descendant) -- Obsługa części doczytywanych w trakcie gry (np. ubrań z katalogu)
		elseif descendant:IsA("Accessory") then
			optimizeAccessory(descendant)
		end
	end)

	table.insert(connections, descAddedConn)
	characterConnections[player] = connections
end

-- DODANE: Wymagane przez ServerLoader do poprawnej rejestracji modułu
function ServerOptimization.OnInit()
	-- Puste przygotowanie (logika rejestracji eventów leci do OnStart)
end

-- ZMIENIONE: Zmieniono nazwę z 'Init' na 'OnStart', aby Loader mógł to automatycznie wywołać
function ServerOptimization.OnStart()
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