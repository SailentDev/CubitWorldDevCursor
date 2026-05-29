--!strict
--[[
	CameraPhone
	Mobile camera input: single-finger drag to rotate, two-finger pinch to zoom.
	Touch deltas are applied in input callbacks; pose is resolved in Update (render step).
]]

local UserInputService = game:GetService("UserInputService")

local CameraCore = require(script.Parent.CameraCore)

export type CameraPhoneConfig = {
	coreConfig: CameraCore.CameraCoreConfig?,
	yawSensitivity: number?,
	pitchSensitivity: number?,
	pinchZoomSensitivity: number?,
	minPitch: number?,
	maxPitch: number?,
}

export type CameraPhoneUpdateInput = {
	focusOrigin: Vector3,
	deltaTime: number,
	filterInstances: { Instance }?,
}

export type CameraViewState = {
	rotation: CFrame,
	targetDistance: number,
	smoothedDistance: number,
}

export type CameraPhone = {
	-- Public Methods
	Enable: (self: CameraPhone) -> (),
	Disable: (self: CameraPhone) -> (),
	Update: (self: CameraPhone, input: CameraPhoneUpdateInput) -> CameraCore.CameraUpdateOutput,
	GetRotation: (self: CameraPhone) -> CFrame,
	GetYawPitch: (self: CameraPhone) -> (number, number),
	GetTargetDistance: (self: CameraPhone) -> number,
	GetSmoothedDistance: (self: CameraPhone) -> number,
	GetViewState: (self: CameraPhone) -> CameraViewState,
	ApplyViewState: (self: CameraPhone, state: CameraViewState) -> (),
	SetRotation: (self: CameraPhone, yaw: number, pitch: number) -> (),
	SetTargetDistance: (self: CameraPhone, distance: number) -> (),
	
	-- Internal Properties
	_core: CameraCore.CameraCore,
	_yawSensitivity: number,
	_pitchSensitivity: number,
	_pinchZoomSensitivity: number,
	_minPitch: number,
	_maxPitch: number,
	_rotation: CFrame,
	_targetDistance: number,
	_enabled: boolean,
	_connections: { RBXScriptConnection },
	_activeTouches: { [InputObject]: Vector2 },
	_ignoredTouches: { [InputObject]: boolean },
	_lastPinchDistance: number,

	-- Private Methods
	_disconnectAll: (self: CameraPhone) -> (),
	_getActiveTouchCount: (self: CameraPhone) -> number,
	_getPinchPositions: (self: CameraPhone) -> (Vector2?, Vector2?),
	_applyPinchZoom: (self: CameraPhone) -> (),
	_applyDragRotation: (self: CameraPhone, screenDelta: Vector2) -> (),
	_onInputBegan: (self: CameraPhone, input: InputObject, gameProcessed: boolean) -> (),
	_onInputChanged: (self: CameraPhone, input: InputObject, gameProcessed: boolean) -> (),
	_onInputEnded: (self: CameraPhone, input: InputObject, gameProcessed: boolean) -> (),
}

local DEFAULT_YAW_SENSITIVITY = 0.02
local DEFAULT_PITCH_SENSITIVITY = 0.013
local DEFAULT_PINCH_ZOOM_SENSITIVITY = 0.1
local DEFAULT_MIN_PITCH = math.rad(-70)
local DEFAULT_MAX_PITCH = math.rad(70)

local CameraPhone = {}
CameraPhone.__index = CameraPhone

local function getScreenPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function isMovementZone(input: InputObject): boolean
	local camera = workspace.CurrentCamera
	if not camera then return false end
	
	local viewportSize = camera.ViewportSize
	-- Standardized to 0.50 because Roblox's dynamic thumbstick covers the left 50% of the screen
	return input.Position.X <= (viewportSize.X * 0.50)
end

--[[
	Creates a touch camera controller backed by CameraCore.
]]
function CameraPhone.new(config: CameraPhoneConfig?): CameraPhone
	local resolvedConfig: CameraPhoneConfig = config or {}
	local self = setmetatable({}, CameraPhone) :: any

	self._core = CameraCore.new(resolvedConfig.coreConfig)
	self._yawSensitivity = resolvedConfig.yawSensitivity or DEFAULT_YAW_SENSITIVITY
	self._pitchSensitivity = resolvedConfig.pitchSensitivity or DEFAULT_PITCH_SENSITIVITY
	self._pinchZoomSensitivity = resolvedConfig.pinchZoomSensitivity or DEFAULT_PINCH_ZOOM_SENSITIVITY
	self._minPitch = resolvedConfig.minPitch or DEFAULT_MIN_PITCH
	self._maxPitch = resolvedConfig.maxPitch or DEFAULT_MAX_PITCH

	self._rotation = CFrame.identity
	self._targetDistance = self._core:GetSmoothedDistance()
	self._enabled = false
	self._connections = {} :: { RBXScriptConnection }

	self._activeTouches = {} :: { [InputObject]: Vector2 }
	self._ignoredTouches = {} :: { [InputObject]: boolean } 
	self._lastPinchDistance = 0

	return (self :: any) :: CameraPhone
end

function CameraPhone.GetRotation(self: CameraPhone): CFrame
	return self._rotation
end

function CameraPhone.GetTargetDistance(self: CameraPhone): number
	return self._targetDistance
end

function CameraPhone.GetYawPitch(self: CameraPhone): (number, number)
	local pitch, yaw, _ = self._rotation:ToEulerAnglesYXZ()
	return yaw, pitch
end

function CameraPhone.GetSmoothedDistance(self: CameraPhone): number
	return self._core:GetSmoothedDistance()
end

function CameraPhone.GetViewState(self: CameraPhone): CameraViewState
	return {
		rotation = self._rotation,
		targetDistance = self._targetDistance,
		smoothedDistance = self._core:GetSmoothedDistance(),
	}
end

function CameraPhone.ApplyViewState(self: CameraPhone, state: CameraViewState): ()
	self._rotation = state.rotation
	self._targetDistance = state.targetDistance
	self._core:ResetZoom(state.smoothedDistance)
end

function CameraPhone.SetRotation(self: CameraPhone, yaw: number, pitch: number): ()
	local clampedPitch = math.clamp(pitch, self._minPitch, self._maxPitch)
	self._rotation = CFrame.fromEulerAnglesYXZ(clampedPitch, yaw, 0)
end

function CameraPhone.SetTargetDistance(self: CameraPhone, distance: number): ()
	self._targetDistance = distance
end

function CameraPhone._disconnectAll(self: CameraPhone): ()
	for index = #self._connections, 1, -1 do
		local connection = self._connections[index]
		connection:Disconnect()
		self._connections[index] = nil :: any
	end
end

function CameraPhone._getActiveTouchCount(self: CameraPhone): number
	local count = 0
	for _ in self._activeTouches do
		count += 1
	end
	return count
end

function CameraPhone._getPinchPositions(self: CameraPhone): (Vector2?, Vector2?)
	local first: Vector2? = nil
	local second: Vector2? = nil

	for _, position in self._activeTouches do
		if not first then
			first = position
		else
			second = position
			break
		end
	end

	return first, second
end

function CameraPhone._applyPinchZoom(self: CameraPhone): ()
	local posA, posB = self:_getPinchPositions()
	if not posA or not posB then
		return
	end

	local pinchDistance = (posA - posB).Magnitude
	if self._lastPinchDistance > 0 then
		local pinchDelta = pinchDistance - self._lastPinchDistance
		self._targetDistance -= pinchDelta * self._pinchZoomSensitivity
	end
	self._lastPinchDistance = pinchDistance
end

--[[
	Applies mobile drag input directly onto the unit vector direction.
]]
function CameraPhone._applyDragRotation(self: CameraPhone, screenDelta: Vector2): ()
	if screenDelta.Magnitude <= 0 then
		return
	end

	local yawAngle = -screenDelta.X * self._yawSensitivity
	local pitchAngle = -screenDelta.Y * self._pitchSensitivity

	local look = self._rotation.LookVector
	
	local yawRotation = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yawAngle)
	local newLook = yawRotation:VectorToWorldSpace(look)

	local currentPitch = math.asin(math.clamp(newLook.Y, -0.9999, 0.9999))
	local targetPitch = math.clamp(currentPitch + pitchAngle, self._minPitch, self._maxPitch)

	local flatLook = Vector3.new(newLook.X, 0, newLook.Z)
	if flatLook.Magnitude < 1e-4 then
		flatLook = Vector3.new(self._rotation.RightVector.Z, 0, -self._rotation.RightVector.X)
		if flatLook.Magnitude < 1e-4 then
			flatLook = Vector3.new(0, 0, -1)
		end
	end
	flatLook = flatLook.Unit

	local finalLook = flatLook * math.cos(targetPitch) + Vector3.new(0, math.sin(targetPitch), 0)
	self._rotation = CFrame.lookAt(Vector3.zero, finalLook)
end

function CameraPhone._onInputBegan(self: CameraPhone, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if gameProcessed or isMovementZone(input) then
		self._ignoredTouches[input] = true
		return
	end

	self._activeTouches[input] = getScreenPosition(input)

	if self:_getActiveTouchCount() == 2 then
		local posA, posB = self:_getPinchPositions()
		if posA and posB then
			self._lastPinchDistance = (posA - posB).Magnitude
		end
	end
end

function CameraPhone._onInputChanged(self: CameraPhone, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if self._ignoredTouches[input] then
		return
	end

	if gameProcessed or not self._activeTouches[input] then
		return
	end

	self._activeTouches[input] = getScreenPosition(input)

	if self:_getActiveTouchCount() >= 2 then
		if not self._core._shiftLockActive then
			self:_applyPinchZoom()
		end
		return
	end

	local touchDelta = input.Delta
	self:_applyDragRotation(Vector2.new(touchDelta.X, touchDelta.Y))
end

function CameraPhone._onInputEnded(self: CameraPhone, input: InputObject, _gameProcessed: boolean): ()
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if self._ignoredTouches[input] then
		self._ignoredTouches[input] = nil
		return
	end

	self._activeTouches[input] = nil
	if self:_getActiveTouchCount() < 2 then
		self._lastPinchDistance = 0
	end
end

function CameraPhone.Enable(self: CameraPhone): ()
	if self._enabled then
		return
	end

	self._enabled = true

	local connections = self._connections
	local onInputBegan = function(input: InputObject, gameProcessed: boolean)
		self:_onInputBegan(input, gameProcessed)
	end
	local onInputChanged = function(input: InputObject, gameProcessed: boolean)
		self:_onInputChanged(input, gameProcessed)
	end
	local onInputEnded = function(input: InputObject, gameProcessed: boolean)
		self:_onInputEnded(input, gameProcessed)
	end

	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, UserInputService.InputEnded:Connect(onInputEnded))
end

function CameraPhone.Disable(self: CameraPhone): ()
	if not self._enabled then
		return
	end

	self._enabled = false
	table.clear(self._activeTouches)
	table.clear(self._ignoredTouches)
	self._lastPinchDistance = 0
	self:_disconnectAll()
end

function CameraPhone.Update(self: CameraPhone, input: CameraPhoneUpdateInput): CameraCore.CameraUpdateOutput
	return self._core:Update({
		focusOrigin = input.focusOrigin,
		rotation = self._rotation,
		targetDistance = self._targetDistance,
		deltaTime = input.deltaTime,
		filterInstances = input.filterInstances,
	})
end

return CameraPhone