--!strict
--[[
    ControlPC Module (Updated)
    - Inverted W/S movement logic.
    - Continuous/Single Jump logic via Spacebar.
    - Optimized for Luau and memory safety.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- TYPES
export type ControlPC = {
	Enable: (self: ControlPC) -> (),
	Disable: (self: ControlPC) -> (),
}

type InputState = {
	Forward: number,
	Backward: number,
	Left: number,
	Right: number,
}

-- CONSTANTS
-- Logic Inversion: W is mapped to Backward, S is mapped to Forward
local MOVE_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.W] = "Backward",
	[Enum.KeyCode.S] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",
}

-- MICRO-OPTIMIZATIONS
local V3_NEW = Vector3.new
local V3_ZERO = Vector3.zero

-- PRIVATE STATE
local _player = Players.LocalPlayer
local _activeConnections: { RBXScriptConnection } = {}
local _isJumping = false
local _inputState: InputState = {
	Forward = 0,
	Backward = 0,
	Left = 0,
	Right = 0,
}

local ControlPC = {} :: ControlPC

-- PRIVATE FUNCTIONS

--[[
    Main update loop running on PreSimulation.
    Handles both movement calculation and jump state.
]]
local function onUpdate(): ()
	local character = _player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Handle Jumping (Setting .Jump to true every frame allows continuous jumping)
	if _isJumping then
		humanoid.Jump = true
	end

	-- Handle Movement
	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- Calculate raw direction from input state
	local moveDirection = V3_NEW(
		_inputState.Right - _inputState.Left,
		0,
		_inputState.Backward - _inputState.Forward
	)

	if moveDirection.Magnitude > 0 then
		local camCFrame = camera.CFrame
		local lookVector = camCFrame.LookVector
		local rightVector = camCFrame.RightVector

		-- Flatten vectors to XZ plane
		local forward = V3_NEW(lookVector.X, 0, lookVector.Z).Unit
		local right = V3_NEW(rightVector.X, 0, rightVector.Z).Unit

		-- moveDirection.Z is positive when W (Backward) is pressed
		local finalDirection = (forward * moveDirection.Z) + (right * moveDirection.X)
		
		humanoid:Move(finalDirection, false)
	else
		humanoid:Move(V3_ZERO, false)
	end
end

--[[
    Processes keyboard input for movement and jumping.
]]
local function handleInput(input: InputObject, isProcessed: boolean, active: number): ()
	if isProcessed then return end
	
	-- Movement Keys
	local action = MOVE_KEYS[input.KeyCode]
	if action then
		(_inputState :: any)[action] = active
		return
	end

	-- Jump Key
	if input.KeyCode == Enum.KeyCode.Space then
		_isJumping = (active == 1)
	end
end

-- PUBLIC METHODS

function ControlPC:Enable(): ()
	self:Disable()

	-- Input Listeners
	table.insert(_activeConnections, UserInputService.InputBegan:Connect(function(input, processed)
		handleInput(input, processed, 1)
	end))

	table.insert(_activeConnections, UserInputService.InputEnded:Connect(function(input, processed)
		handleInput(input, processed, 0)
	end))

	-- Movement & Jump Loop
	table.insert(_activeConnections, RunService.PreSimulation:Connect(onUpdate))
end

function ControlPC:Disable(): ()
	for _, connection in _activeConnections do
		connection:Disconnect()
	end
	table.clear(_activeConnections)

	-- Reset State
	_isJumping = false
	_inputState.Forward = 0
	_inputState.Backward = 0
	_inputState.Left = 0
	_inputState.Right = 0

	-- Stop Character
	local character = _player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Move(V3_ZERO, false)
		end
	end
end

return ControlPC