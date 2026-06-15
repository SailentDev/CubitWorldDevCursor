--!strict
--[[ ControlPhone Module (Fixed) Features: Dynamic Joystick and Continuous Jump. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService") -- Imported for menu detection

-- TYPES
export type ControlPhone = {
	Enable: (self: ControlPhone) -> (),
	Disable: (self: ControlPhone) -> ()
}

type JoystickData = {
	IsDragging: boolean,
	TouchId: InputObject?,
	MoveVector: Vector2
}

-- CONFIGURATION (Change these to adjust the active zone)
local ZONE_WIDTH_LIMIT = 0.4   -- Maximum percentage from left (0.5 = left half)
local ZONE_HEIGHT_LIMIT = 0.33  -- Minimum percentage from top (0.5 = bottom half)

-- MICRO-OPTIMIZATIONS
local V3_NEW = Vector3.new
local V2_NEW = Vector2.new
local V3_ZERO = Vector3.zero
local MATH_MIN = math.min

-- PRIVATE STATE
local _player = Players.LocalPlayer :: Player -- Type-casted to Player
local _activeConnections: { RBXScriptConnection } = {}
local _joystickState: JoystickData = { IsDragging = false, TouchId = nil, MoveVector = V2_NEW(0, 0) }
local _isJumping = false

-- UI REFERENCES
local _joystickBase: Frame? = nil
local _joystickThumb: ImageButton? = nil
local _jumpButton: ImageButton? = nil

local ControlPhone = {} :: ControlPhone

-- PRIVATE FUNCTIONS

--[[ Checks if a touch position is within the configured screen zone ]]
local function isWithinTouchZone(pos: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then return false end
	local screenSize = camera.ViewportSize
	
	return pos.X < (screenSize.X * ZONE_WIDTH_LIMIT) and pos.Y > (screenSize.Y * ZONE_HEIGHT_LIMIT)
end

--[[ Main update loop for movement and jumping ]]
local function onUpdate(dt: number): ()
	local character = _player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- ROZWIĄZANIE DLA CCL: Gwarantuje wyłączenie skoku po puszczeniu UI
	humanoid.Jump = _isJumping

	-- Camera-Relative Movement Logic
	local camera = Workspace.CurrentCamera
	if camera and _joystickState.MoveVector.Magnitude > 0 then
		local camCF = camera.CFrame
		local forward = V3_NEW(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
		local right = V3_NEW(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
		
		local dir = (forward * -_joystickState.MoveVector.Y) + (right * _joystickState.MoveVector.X)
		humanoid:Move(dir, false)
	else
		humanoid:Move(V3_ZERO, false)
	end
end

--[[ Updates the visual position of the thumb and the MoveVector ]]
local function updateJoystickPosition(input: InputObject): ()
	-- Localize instances to verify safety in strict mode
	local joystickBase = _joystickBase
	local joystickThumb = _joystickThumb
	if not joystickBase or not joystickThumb then return end

	local basePos = joystickBase.AbsolutePosition + (joystickBase.AbsoluteSize / 2)
	local diff = V2_NEW(input.Position.X, input.Position.Y) - basePos
	local radius = joystickBase.AbsoluteSize.X / 2
	local dist = MATH_MIN(diff.Magnitude, radius)
	local dir = if diff.Magnitude > 0 then diff.Unit else V2_NEW(0, 0)

	_joystickState.MoveVector = dir * (dist / radius)

	joystickThumb.Position = UDim2.fromOffset(
		(joystickBase.AbsoluteSize.X / 2) + (dir.X * dist), 
		(joystickBase.AbsoluteSize.Y / 2) + (dir.Y * dist)
	)
end

-- PUBLIC METHODS

function ControlPhone:Enable(): ()
	self:Disable() -- Ensure clean state

	local playerGui = _player:WaitForChild("PlayerGui") :: PlayerGui
	local hud = playerGui:WaitForChild("GameHUD") :: ScreenGui
	
	-- Create strictly typed local variables to prevent optional nil-warnings
	local joystickBaseInstance = hud:WaitForChild("JoystickBase") :: Frame
	local joystickThumbInstance = joystickBaseInstance:WaitForChild("JoystickThumb") :: ImageButton
	local jumpButtonInstance = hud:WaitForChild("JumpButton") :: ImageButton

	_joystickBase = joystickBaseInstance
	_joystickThumb = joystickThumbInstance
	_jumpButton = jumpButtonInstance

	-- DYNAMIC JOYSTICK START
	table.insert(_activeConnections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		
		if (isTouch or isMouse) and isWithinTouchZone(input.Position) then
			_joystickState.IsDragging = true
			_joystickState.TouchId = input
			
			joystickBaseInstance.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
			joystickThumbInstance.Position = UDim2.fromScale(0.5, 0.5)
			_joystickState.MoveVector = V2_NEW(0, 0)
			joystickBaseInstance.Visible = true
		end
	end))

	table.insert(_activeConnections, UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if _joystickState.IsDragging and input == _joystickState.TouchId then 
			updateJoystickPosition(input) 
		end
	end))

	table.insert(_activeConnections, UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
		if input == _joystickState.TouchId then
			_joystickState.IsDragging = false
			_joystickState.TouchId = nil
			_joystickState.MoveVector = V2_NEW(0, 0)
			
			joystickBaseInstance.Visible = false 
		end
	end))

-- JUMP LOGIC
	table.insert(_activeConnections, jumpButtonInstance.InputBegan:Connect(function(input: InputObject) 
		_isJumping = true 
	end))
	
	table.insert(_activeConnections, jumpButtonInstance.InputEnded:Connect(function(input: InputObject) 
		_isJumping = false 
	end))

	-- MENU OPENED LOGIC (Resets movement immediately when menu is opened)
	table.insert(_activeConnections, GuiService.MenuOpened:Connect(function()
		_joystickState.IsDragging = false
		_joystickState.TouchId = nil
		_joystickState.MoveVector = V2_NEW(0, 0)
		_isJumping = false
		joystickBaseInstance.Visible = false
	end))

	-- UPDATE LOOP
	table.insert(_activeConnections, RunService.PreSimulation:Connect(onUpdate))
end

function ControlPhone:Disable(): ()
	for _, c in _activeConnections do
		c:Disconnect()
	end
	table.clear(_activeConnections)

	_isJumping = false
	_joystickState.IsDragging = false
	_joystickState.MoveVector = V2_NEW(0, 0)

	local joystickBase = _joystickBase
	if joystickBase then 
		joystickBase.Visible = false 
	end
end

return ControlPhone