--!strict
--!native
--[[
    ControlPC Module (Fixed Jump)
    - Zero idle CPU usage.
    - Fixed infinite jumping bug.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

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

local MOVE_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.W] = "Backward",
	[Enum.KeyCode.S] = "Forward",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",
}

local _player = (Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()) :: Player
local _activeConnections: { RBXScriptConnection } = {}
local _updateConnection: RBXScriptConnection? = nil

local _isJumping = false
local _cachedHumanoid: Humanoid? = nil
local _inputState: InputState = { Forward = 0, Backward = 0, Left = 0, Right = 0 }

local ControlPC = {} :: ControlPC

local function updateCharacterCache(character: Model)
	_cachedHumanoid = character:WaitForChild("Humanoid") :: Humanoid
end

local function shouldUpdate(): boolean
	return _isJumping or _inputState.Forward > 0 or _inputState.Backward > 0 or _inputState.Left > 0 or _inputState.Right > 0
end

local function onUpdate(): ()
	if not _cachedHumanoid then return end

	-- NAPRAWA: Zawsze przypisujemy aktualny stan (włącza i wyłącza skok)
	_cachedHumanoid.Jump = _isJumping

	local camera = Workspace.CurrentCamera
	local moveDirection = Vector3.new(
		_inputState.Right - _inputState.Left,
		0,
		_inputState.Backward - _inputState.Forward
	)

	if moveDirection.Magnitude > 0 and camera then
		local camCFrame = camera.CFrame
		local forward = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
		local right = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z).Unit

		_cachedHumanoid:Move((forward * moveDirection.Z) + (right * moveDirection.X), false)
	else
		_cachedHumanoid:Move(Vector3.zero, false)
	end
end

local function evaluateUpdateLoop(): ()
	if shouldUpdate() then
		if not _updateConnection then
			_updateConnection = RunService.PreSimulation:Connect(onUpdate)
		end
	else
		if _updateConnection then
			_updateConnection:Disconnect()
			_updateConnection = nil
			if _cachedHumanoid then
				_cachedHumanoid:Move(Vector3.zero, false)
				_cachedHumanoid.Jump = false -- NAPRAWA: Zerowanie skoku przy usypianiu skryptu
			end
		end
	end
end

local function resetInputState(): ()
	_isJumping = false
	_inputState.Forward = 0
	_inputState.Backward = 0
	_inputState.Left = 0
	_inputState.Right = 0

	evaluateUpdateLoop()
end

local function handleInput(input: InputObject, isProcessed: boolean, active: number): ()
	if isProcessed then return end
	
	local action = MOVE_KEYS[input.KeyCode]
	if action then
		(_inputState :: any)[action] = active
		evaluateUpdateLoop()
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		_isJumping = (active == 1)
		evaluateUpdateLoop()
	end
end

function ControlPC:Enable(): ()
	self:Disable()

	if _player.Character then
		task.spawn(updateCharacterCache, _player.Character)
	end
	table.insert(_activeConnections, _player.CharacterAdded:Connect(function(char)
		task.spawn(updateCharacterCache, char)
	end))
	table.insert(_activeConnections, _player.CharacterRemoving:Connect(function()
		_cachedHumanoid = nil
		evaluateUpdateLoop()
	end))

	table.insert(_activeConnections, UserInputService.InputBegan:Connect(function(input, processed) handleInput(input, processed, 1) end))
	table.insert(_activeConnections, UserInputService.InputEnded:Connect(function(input, processed) handleInput(input, processed, 0) end))
	table.insert(_activeConnections, GuiService.MenuOpened:Connect(resetInputState))
	table.insert(_activeConnections, UserInputService.WindowFocusReleased:Connect(resetInputState))

	evaluateUpdateLoop()
end

function ControlPC:Disable(): ()
	for _, connection in _activeConnections do
		connection:Disconnect()
	end
	table.clear(_activeConnections)

	if _updateConnection then
		_updateConnection:Disconnect()
		_updateConnection = nil
	end

	resetInputState()
	_cachedHumanoid = nil
end

return ControlPC