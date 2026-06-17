--!strict
--!native
--[[ 
    ControlPhone Module (Fixed Jump)
    - Zero idle CPU usage.
    - Fixed infinite jumping bug.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

export type ControlPhone = {
	Enable: (self: ControlPhone) -> (),
	Disable: (self: ControlPhone) -> ()
}

type JoystickData = {
	IsDragging: boolean,
	TouchId: InputObject?,
	MoveVector: Vector2
}

local ZONE_WIDTH_LIMIT = 0.4   
local ZONE_HEIGHT_LIMIT = 0.33  

local _player = Players.LocalPlayer :: Player
local _activeConnections: { RBXScriptConnection } = {}
local _updateConnection: RBXScriptConnection? = nil

local _joystickState: JoystickData = { IsDragging = false, TouchId = nil, MoveVector = Vector2.zero }
local _isJumping = false
local _cachedHumanoid: Humanoid? = nil
local _viewportSize: Vector2 = Vector2.zero

local _joystickBase: Frame? = nil
local _joystickThumb: ImageButton? = nil
local _jumpButton: ImageButton? = nil

local ControlPhone = {} :: ControlPhone

local function updateCharacterCache(character: Model)
	_cachedHumanoid = character:WaitForChild("Humanoid") :: Humanoid
end

local function isWithinTouchZone(pos: Vector3): boolean
	if _viewportSize.X == 0 then return false end
	return pos.X < (_viewportSize.X * ZONE_WIDTH_LIMIT) and pos.Y > (_viewportSize.Y * ZONE_HEIGHT_LIMIT)
end

local function shouldUpdate(): boolean
	return _isJumping or _joystickState.IsDragging
end

local function onUpdate(dt: number): ()
	if not _cachedHumanoid then return end

	-- NAPRAWA: Zawsze przypisujemy aktualny stan (włącza i wyłącza skok)
	_cachedHumanoid.Jump = _isJumping

	local camera = Workspace.CurrentCamera
	if camera and _joystickState.MoveVector.Magnitude > 0 then
		local camCF = camera.CFrame
		local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
		local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
		
		local dir = (forward * -_joystickState.MoveVector.Y) + (right * _joystickState.MoveVector.X)
		_cachedHumanoid:Move(dir, false)
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

local function updateJoystickPosition(input: InputObject): ()
	local joystickBase = _joystickBase
	local joystickThumb = _joystickThumb
	if not joystickBase or not joystickThumb then return end

	local basePos = joystickBase.AbsolutePosition + (joystickBase.AbsoluteSize / 2)
	local diff = Vector2.new(input.Position.X, input.Position.Y) - basePos
	local radius = joystickBase.AbsoluteSize.X / 2
	local dist = math.min(diff.Magnitude, radius)
	local dir = if diff.Magnitude > 0 then diff.Unit else Vector2.zero

	_joystickState.MoveVector = dir * (dist / radius)

	joystickThumb.Position = UDim2.fromOffset(
		(joystickBase.AbsoluteSize.X / 2) + (dir.X * dist), 
		(joystickBase.AbsoluteSize.Y / 2) + (dir.Y * dist)
	)
end

function ControlPhone:Enable(): ()
	self:Disable()

	local playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui
	local hud = playerGui:WaitForChild("GameHUD") :: ScreenGui
	
	local joystickBaseInstance = hud:WaitForChild("JoystickBase") :: Frame
	local joystickThumbInstance = joystickBaseInstance:WaitForChild("JoystickThumb") :: ImageButton
	local jumpButtonInstance = hud:WaitForChild("JumpButton") :: ImageButton

	_joystickBase = joystickBaseInstance
	_joystickThumb = joystickThumbInstance
	_jumpButton = jumpButtonInstance

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

	local camera = Workspace.CurrentCamera
	if camera then
		_viewportSize = camera.ViewportSize
		table.insert(_activeConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			_viewportSize = camera.ViewportSize
		end))
	end

	table.insert(_activeConnections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		
		if (isTouch or isMouse) and isWithinTouchZone(input.Position) then
			_joystickState.IsDragging = true
			_joystickState.TouchId = input
			
			joystickBaseInstance.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
			joystickThumbInstance.Position = UDim2.fromScale(0.5, 0.5)
			_joystickState.MoveVector = Vector2.zero
			joystickBaseInstance.Visible = true
			evaluateUpdateLoop()
		end
	end))

	table.insert(_activeConnections, UserInputService.InputChanged:Connect(function(input, processed)
		if _joystickState.IsDragging and input == _joystickState.TouchId then 
			updateJoystickPosition(input) 
		end
	end))

	table.insert(_activeConnections, UserInputService.InputEnded:Connect(function(input, processed)
		if input == _joystickState.TouchId then
			_joystickState.IsDragging = false
			_joystickState.TouchId = nil
			_joystickState.MoveVector = Vector2.zero
			joystickBaseInstance.Visible = false 
			evaluateUpdateLoop()
		end
	end))

	table.insert(_activeConnections, jumpButtonInstance.InputBegan:Connect(function() 
		_isJumping = true 
		evaluateUpdateLoop()
	end))
	
	table.insert(_activeConnections, jumpButtonInstance.InputEnded:Connect(function() 
		_isJumping = false 
		evaluateUpdateLoop()
	end))

	table.insert(_activeConnections, GuiService.MenuOpened:Connect(function()
		_joystickState.IsDragging = false
		_joystickState.TouchId = nil
		_joystickState.MoveVector = Vector2.zero
		_isJumping = false
		joystickBaseInstance.Visible = false
		evaluateUpdateLoop()
	end))

	evaluateUpdateLoop()
end

function ControlPhone:Disable(): ()
	for _, c in _activeConnections do
		c:Disconnect()
	end
	table.clear(_activeConnections)

	if _updateConnection then
		_updateConnection:Disconnect()
		_updateConnection = nil
	end

	_isJumping = false
	_joystickState.IsDragging = false
	_joystickState.MoveVector = Vector2.zero
	_cachedHumanoid = nil

	local joystickBase = _joystickBase
	if joystickBase then 
		joystickBase.Visible = false 
	end
end

return ControlPhone