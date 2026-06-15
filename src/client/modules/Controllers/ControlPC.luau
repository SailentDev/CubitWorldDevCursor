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
local GuiService = game:GetService("GuiService")

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
local _player = (Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()) :: Player -- Cast to Player to resolve strict typing warnings
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

--[[ Resets all active inputs back to 0 ]]
local function resetInputState(): ()
	_isJumping = false
	_inputState.Forward = 0
	_inputState.Backward = 0
	_inputState.Left = 0
	_inputState.Right = 0

	local character = _player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(V3_ZERO, false)
	end
end

--[[ Main update loop running on PreSimulation ]]
local function onUpdate(): ()
	local character = _player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- ROZWIĄZANIE DLA CCL: Przypisujemy bezpośrednio true/false
	humanoid.Jump = _isJumping

	-- Handle Movement
	local camera = Workspace.CurrentCamera

	local moveDirection = V3_NEW(
		_inputState.Right - _inputState.Left,
		0,
		_inputState.Backward - _inputState.Forward
	)

	if moveDirection.Magnitude > 0 then
		local camCFrame = camera.CFrame
		local lookVector = camCFrame.LookVector
		local rightVector = camCFrame.RightVector

		local forward = V3_NEW(lookVector.X, 0, lookVector.Z).Unit
		local right = V3_NEW(rightVector.X, 0, rightVector.Z).Unit

		local finalDirection = (forward * moveDirection.Z) + (right * moveDirection.X)
		
		humanoid:Move(finalDirection, false)
	else
		humanoid:Move(V3_ZERO, false)
	end
end

--[[ Processes keyboard input for movement and jumping ]]
local function handleInput(input: InputObject, isProcessed: boolean, active: number): ()
	if isProcessed then return end
	
	local action = MOVE_KEYS[input.KeyCode]
	if action then
		(_inputState :: any)[action] = active
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		_isJumping = (active == 1)
	end
end

-- PUBLIC METHODS

function ControlPC:Enable(): ()
	self:Disable()

	-- Input Listeners
	table.insert(_activeConnections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		handleInput(input, processed, 1)
	end))

	table.insert(_activeConnections, UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		handleInput(input, processed, 0)
	end))

	-- System overlays & Menu listeners to clear focus stuck states
	table.insert(_activeConnections, GuiService.MenuOpened:Connect(resetInputState))
	table.insert(_activeConnections, UserInputService.WindowFocusReleased:Connect(resetInputState))

	-- Movement & Jump Loop
	table.insert(_activeConnections, RunService.PreSimulation:Connect(onUpdate))
end

function ControlPC:Disable(): ()
	for _, connection in _activeConnections do
		connection:Disconnect()
	end
	table.clear(_activeConnections)

	resetInputState()
end

return ControlPC