--!strict
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- 1. Explicitly define the module's type to force Luau to recognize the functions
export type CameraInputModule = {
	GetDeltas: () -> (number, number, number),
	IsDragging: () -> boolean
}

-- 2. Apply the type to the table
local CameraInput = {} :: CameraInputModule

-- Primitive State
local yawDelta: number = 0
local pitchDelta: number = 0
local zoomDelta: number = 0

local isDragging: boolean = false
local touch1: InputObject? = nil
local touch2: InputObject? = nil
local lastPinchDistance: number = 0

-- Viewport Cache (Micro-optimization)
local cachedViewportWidth: number = 1000
local viewportConn: RBXScriptConnection?

local function updateViewportCache()
	local camera = Workspace.CurrentCamera
	if camera then
		cachedViewportWidth = camera.ViewportSize.X
		if viewportConn then viewportConn:Disconnect() end
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			cachedViewportWidth = camera.ViewportSize.X
		end)
	end
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateViewportCache)
updateViewportCache()

-- Constants
local MOUSE_SENSITIVITY = 0.007
local TOUCH_SENSITIVITY = 0.02
local ZOOM_STEP = 2.2
local PINCH_SENSITIVITY = 0.1

-- Flushes and returns the accumulated deltas for this frame
function CameraInput.GetDeltas(): (number, number, number)
	local y, p, z = yawDelta, pitchDelta, zoomDelta
	yawDelta, pitchDelta, zoomDelta = 0, 0, 0
	return y, p, z
end

-- Expose dragging state to avoid polling UserInputService in RenderStep
function CameraInput.IsDragging(): boolean
	return isDragging
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end -- Ignore clicks on UI elements
	
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isDragging = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if input.Position.X <= cachedViewportWidth * 0.5 then return end -- Ignore movement thumbstick zone
		
		-- O(1) Zero-allocation touch tracking
		if not touch1 then
			touch1 = input
		elseif not touch2 then
			touch2 = input
			local t1 = touch1 :: InputObject
			local dx = t1.Position.X - input.Position.X
			local dy = t1.Position.Y - input.Position.Y
			lastPinchDistance = math.sqrt(dx * dx + dy * dy)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isDragging = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if touch1 == input then
			touch1 = nil
			lastPinchDistance = 0
		elseif touch2 == input then
			touch2 = nil
			lastPinchDistance = 0
		end
		
		-- Shift touch2 to touch1 if the primary finger was released
		if not touch1 and touch2 then
			touch1 = touch2
			touch2 = nil
		end
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if isDragging or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then
			yawDelta -= input.Delta.X * MOUSE_SENSITIVITY
			pitchDelta -= input.Delta.Y * MOUSE_SENSITIVITY
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		zoomDelta -= input.Position.Z * ZOOM_STEP
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if touch1 and not touch2 and input == touch1 then
			yawDelta -= input.Delta.X * TOUCH_SENSITIVITY
			pitchDelta -= input.Delta.Y * TOUCH_SENSITIVITY
		elseif touch1 and touch2 and (input == touch1 or input == touch2) then
			local t1 = touch1 :: InputObject
			local t2 = touch2 :: InputObject
			
			local dx = t1.Position.X - t2.Position.X
			local dy = t1.Position.Y - t2.Position.Y
			local dist = math.sqrt(dx * dx + dy * dy)
			
			if lastPinchDistance > 0 then
				zoomDelta -= (dist - lastPinchDistance) * PINCH_SENSITIVITY
			end
			lastPinchDistance = dist
		end
	end
end)

return CameraInput