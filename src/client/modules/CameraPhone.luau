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
	yaw: number,
	pitch: number,
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
	_yaw: number,
	_pitch: number,
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

local function buildRotation(yaw: number, pitch: number): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

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

	self._yaw = 0
	self._pitch = 0
	self._targetDistance = self._core:GetSmoothedDistance()
	self._enabled = false
	self._connections = {} :: { RBXScriptConnection }

	self._activeTouches = {} :: { [InputObject]: Vector2 }
	self._ignoredTouches = {} :: { [InputObject]: boolean } 
	self._lastPinchDistance = 0

	return (self :: any) :: CameraPhone
end

--[[
	Returns the current look rotation passed to CameraCore.
]]
function CameraPhone.GetRotation(self: CameraPhone): CFrame
	return buildRotation(self._yaw, self._pitch)
end

--[[
	Returns the unsmoothed zoom target (CameraCore smooths toward this).
]]
function CameraPhone.GetTargetDistance(self: CameraPhone): number
	return self._targetDistance
end

--[[
	Returns internal yaw and pitch radians without Euler decomposition.
]]
function CameraPhone.GetYawPitch(self: CameraPhone): (number, number)
	return self._yaw, self._pitch
end

--[[
	Returns the smoothed zoom distance held inside CameraCore.
]]
function CameraPhone.GetSmoothedDistance(self: CameraPhone): number
	return self._core:GetSmoothedDistance()
end

--[[
	Captures rotation and zoom for handoff when switching device modules.
]]
function CameraPhone.GetViewState(self: CameraPhone): CameraViewState
	return {
		yaw = self._yaw,
		pitch = self._pitch,
		targetDistance = self._targetDistance,
		smoothedDistance = self._core:GetSmoothedDistance(),
	}
end

--[[
	Applies a captured view state so rotation and zoom do not snap after a switch.
]]
function CameraPhone.ApplyViewState(self: CameraPhone, state: CameraViewState): ()
	self:SetRotation(state.yaw, state.pitch)
	self._targetDistance = state.targetDistance
	self._core:ResetZoom(state.smoothedDistance)
end

--[[
	Sets yaw/pitch instantly (e.g. when snapping behind the character).
]]
function CameraPhone.SetRotation(self: CameraPhone, yaw: number, pitch: number): ()
	self._yaw = yaw
	self._pitch = math.clamp(pitch, self._minPitch, self._maxPitch)
end

--[[
	Sets zoom target; clamping is handled by CameraCore.
]]
function CameraPhone.SetTargetDistance(self: CameraPhone, distance: number): ()
	self._targetDistance = distance
end

--[[
	Disconnects all input listeners registered by Enable.
]]
function CameraPhone._disconnectAll(self: CameraPhone): ()
	for index = #self._connections, 1, -1 do
		local connection = self._connections[index]
		connection:Disconnect()
		self._connections[index] = nil :: any
	end
end

--[[
	Counts entries in the active touch map without allocating an array.
]]
function CameraPhone._getActiveTouchCount(self: CameraPhone): number
	local count = 0
	for _ in self._activeTouches do
		count += 1
	end
	return count
end

--[[
	Returns the two active touch positions when exactly two touches are held.
]]
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

--[[
	Applies two-finger pinch from the current screen positions of both active touches.
]]
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
	Applies single-finger drag rotation from a touch delta vector.
]]
function CameraPhone._applyDragRotation(self: CameraPhone, screenDelta: Vector2): ()
	if screenDelta.Magnitude <= 0 then
		return
	end

	self._yaw -= screenDelta.X * self._yawSensitivity
	self._pitch = math.clamp(
		self._pitch - screenDelta.Y * self._pitchSensitivity,
		self._minPitch,
		self._maxPitch
	)
end

--[[
	Stores a touch and seeds pinch baseline when the second finger lands.
]]
function CameraPhone._onInputBegan(self: CameraPhone, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- If it's a UI tap or inside the movement zone, completely flag it as ignored for camera operations
	if gameProcessed or isMovementZone(input) then
		self._ignoredTouches[input] = true
		return
	end

	-- Only track touches explicitly meant for the camera panned actions
	self._activeTouches[input] = getScreenPosition(input)

	if self:_getActiveTouchCount() == 2 then
		local posA, posB = self:_getPinchPositions()
		if posA and posB then
			self._lastPinchDistance = (posA - posB).Magnitude
		end
	end
end

--[[
	Updates stored touch positions and applies gesture deltas.
]]
function CameraPhone._onInputChanged(self: CameraPhone, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Early exit if this finger belongs to the thumbstick/UI tracking
	if self._ignoredTouches[input] then
		return
	end

	-- Security check if a touch crosses into an active element or wasn't seeded in Began
	if gameProcessed or not self._activeTouches[input] then
		return
	end

	self._activeTouches[input] = getScreenPosition(input)

	-- If two valid camera fingers are down, process zoom
	if self:_getActiveTouchCount() >= 2 then
		self:_applyPinchZoom()
		return
	end

	-- If only one valid camera finger is down, apply look rotation
	local touchDelta = input.Delta
	self:_applyDragRotation(Vector2.new(touchDelta.X, touchDelta.Y))
end

--[[
	Removes ended touches and clears pinch state when fewer than two remain.
]]
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

--[[
	Registers raw touch input. Call once before BindToRenderStep drives Update.
]]
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

--[[
	Unregisters touch listeners and clears gesture state.
]]
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

--[[
	Lightweight render-step entry: delegates current rotation/zoom to CameraCore.
]]
function CameraPhone.Update(self: CameraPhone, input: CameraPhoneUpdateInput): CameraCore.CameraUpdateOutput
	return self._core:Update({
		focusOrigin = input.focusOrigin,
		rotation = buildRotation(self._yaw, self._pitch),
		targetDistance = self._targetDistance,
		deltaTime = input.deltaTime,
		filterInstances = input.filterInstances,
	})
end

return CameraPhone