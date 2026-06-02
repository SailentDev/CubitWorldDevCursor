--!strict
--[[
	CameraPC
	Desktop camera controller: right-click drag to rotate, scroll wheel to zoom.
	Raw input is captured via UserInputService; pose is resolved in Update for RenderStep use.
]]

local UserInputService = game:GetService("UserInputService")

local CameraCore = require(script.Parent.CameraCore)

local math_clamp = math.clamp

export type CameraPCConfig = {
	coreConfig: CameraCore.CameraCoreConfig?,
	yawSensitivity: number?,
	pitchSensitivity: number?,
	zoomStep: number?,
	minPitch: number?,
	maxPitch: number?,
	orchestrator: any?, -- Reference to the orchestrator module (CameraScript)
}

export type CameraPCUpdateInput = {
	focusOrigin: Vector3,
	deltaTime: number,
	filterInstances: { Instance }?,
}

export type CameraViewState = {
	rotation: CFrame,
	targetDistance: number,
	smoothedDistance: number,
}

export type CameraPC = {
	Enable: (self: CameraPC) -> (),
	Disable: (self: CameraPC) -> (),
	Update: (self: CameraPC, input: CameraPCUpdateInput) -> CameraCore.CameraUpdateOutput,
	GetRotation: (self: CameraPC) -> CFrame,
	GetYawPitch: (self: CameraPC) -> (number, number),
	GetTargetDistance: (self: CameraPC) -> number,
	GetSmoothedDistance: (self: CameraPC) -> number,
	GetViewState: (self: CameraPC) -> CameraViewState,
	ApplyViewState: (self: CameraPC, state: CameraViewState) -> (),
	SetRotation: (self: CameraPC, yaw: number, pitch: number) -> (),
	SetTargetDistance: (self: CameraPC, distance: number) -> (),
	
	-- Internal Properties
	_core: CameraCore.CameraCore,
	_yawSensitivity: number,
	_pitchSensitivity: number,
	_zoomStep: number,
	_minPitch: number,
	_maxPitch: number,
	_rotation: CFrame,
	_targetDistance: number,
	_isRotating: boolean,
	_enabled: boolean,
	_savedMouseBehavior: Enum.MouseBehavior,
	_connections: { RBXScriptConnection },
	_orchestrator: any,

	-- Private Methods
	_disconnectAll: (self: CameraPC) -> (),
	_beginRotation: (self: CameraPC) -> (),
	_endRotation: (self: CameraPC) -> (),
	_applyDragRotation: (self: CameraPC, mouseDelta: Vector2) -> (),
	_onInputChanged: (self: CameraPC, input: InputObject, gameProcessed: boolean) -> (),
	_onInputBegan: (self: CameraPC, input: InputObject, gameProcessed: boolean) -> (),
	_onInputEnded: (self: CameraPC, input: InputObject, gameProcessed: boolean) -> (),
}

local DEFAULT_YAW_SENSITIVITY = 0.01
local DEFAULT_PITCH_SENSITIVITY = 0.01
local DEFAULT_ZOOM_STEP = 2.2
local DEFAULT_MIN_PITCH = math.rad(-70)
local DEFAULT_MAX_PITCH = math.rad(70)

local MOUSE_BUTTON_RIGHT = Enum.UserInputType.MouseButton2
local MOUSE_WHEEL = Enum.UserInputType.MouseWheel
local MOUSE_LOCK_BEHAVIOR = Enum.MouseBehavior.LockCurrentPosition

local CameraPC = {}
CameraPC.__index = CameraPC

--[[
	Creates a PC camera controller backed by CameraCore.
]]
function CameraPC.new(config: CameraPCConfig?): CameraPC
	local resolvedConfig: CameraPCConfig = config or {}
	local self = setmetatable({}, CameraPC) :: any

	self._core = CameraCore.new(resolvedConfig.coreConfig)
	self._yawSensitivity = resolvedConfig.yawSensitivity or DEFAULT_YAW_SENSITIVITY
	self._pitchSensitivity = resolvedConfig.pitchSensitivity or DEFAULT_PITCH_SENSITIVITY
	self._zoomStep = resolvedConfig.zoomStep or DEFAULT_ZOOM_STEP
	self._minPitch = resolvedConfig.minPitch or DEFAULT_MIN_PITCH
	self._maxPitch = resolvedConfig.maxPitch or DEFAULT_MAX_PITCH

	self._rotation = CFrame.identity
	self._targetDistance = self._core:GetSmoothedDistance()
	self._isRotating = false
	self._enabled = false
	self._savedMouseBehavior = Enum.MouseBehavior.Default
	self._connections = table.create(3) :: { RBXScriptConnection }
	self._orchestrator = resolvedConfig.orchestrator

	return (self :: any) :: CameraPC
end

function CameraPC.GetRotation(self: CameraPC): CFrame
	return self._rotation
end

function CameraPC.GetYawPitch(self: CameraPC): (number, number)
	local pitch, yaw, _ = self._rotation:ToEulerAnglesYXZ()
	return yaw, pitch
end

function CameraPC.GetTargetDistance(self: CameraPC): number
	return self._targetDistance
end

function CameraPC.GetSmoothedDistance(self: CameraPC): number
	return self._core:GetSmoothedDistance()
end

function CameraPC.GetViewState(self: CameraPC): CameraViewState
	return {
		rotation = self._rotation,
		targetDistance = self._targetDistance,
		smoothedDistance = self._core:GetSmoothedDistance(),
	}
end

function CameraPC.ApplyViewState(self: CameraPC, state: CameraViewState): ()
	self._rotation = state.rotation
	self._targetDistance = state.targetDistance
	self._core:ResetZoom(state.smoothedDistance)
end

function CameraPC.SetRotation(self: CameraPC, yaw: number, pitch: number): ()
	local clampedPitch = math_clamp(pitch, self._minPitch, self._maxPitch)
	self._rotation = CFrame.fromEulerAnglesYXZ(clampedPitch, yaw, 0)
end

function CameraPC.SetTargetDistance(self: CameraPC, distance: number): ()
	local min, max = self._core:GetLimits()
	self._targetDistance = math_clamp(distance, min, max)
end

function CameraPC._disconnectAll(self: CameraPC): ()
	for index = #self._connections, 1, -1 do
		if self._connections[index] then
			self._connections[index]:Disconnect()
		end
		self._connections[index] = nil :: any
	end
end

function CameraPC._beginRotation(self: CameraPC): ()
	if self._isRotating then
		return
	end

	self._isRotating = true
	self._savedMouseBehavior = UserInputService.MouseBehavior
	
	if UserInputService.MouseBehavior ~= MOUSE_LOCK_BEHAVIOR then
		UserInputService.MouseBehavior = MOUSE_LOCK_BEHAVIOR
	end
end

function CameraPC._endRotation(self: CameraPC): ()
	if not self._isRotating then
		return
	end

	self._isRotating = false
	if UserInputService.MouseBehavior ~= self._savedMouseBehavior then
		UserInputService.MouseBehavior = self._savedMouseBehavior
	end
end

--[[
	Applies 3D rotation using look vectors, preserving upright alignment
	and clamping vertical pitch using vector projections.
]]
function CameraPC._applyDragRotation(self: CameraPC, mouseDelta: Vector2): ()
	if mouseDelta.Magnitude <= 0 then
		return
	end

	local yawAngle = -mouseDelta.X * self._yawSensitivity
	local pitchAngle = -mouseDelta.Y * self._pitchSensitivity

	local look = self._rotation.LookVector
	
	-- Rotate yaw around global up-axis
	local yawRotation = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yawAngle)
	local newLook = yawRotation:VectorToWorldSpace(look)

	-- Calculate vertical pitch angle from look vector
	local currentPitch = math.asin(math_clamp(newLook.Y, -0.9999, 0.9999))
	local targetPitch = math_clamp(currentPitch + pitchAngle, self._minPitch, self._maxPitch)

	-- Resolve horizontal direction components
	local flatLook = Vector3.new(newLook.X, 0, newLook.Z)
	if flatLook.Magnitude < 1e-4 then
		-- Fallback to right vector direction if looking straight up or down
		flatLook = Vector3.new(self._rotation.RightVector.Z, 0, -self._rotation.RightVector.X)
		if flatLook.Magnitude < 1e-4 then
			flatLook = Vector3.new(0, 0, -1)
		end
	end
	flatLook = flatLook.Unit

	-- Rebuild LookVector and generate new CFrame orientation
	local finalLook = flatLook * math.cos(targetPitch) + Vector3.new(0, math.sin(targetPitch), 0)
	self._rotation = CFrame.lookAt(Vector3.zero, finalLook)
end

function CameraPC._onInputChanged(self: CameraPC, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled or gameProcessed then
		return
	end

	if input.UserInputType == MOUSE_WHEEL then
		if self._core._shiftLockActive then
			return
		end

		local min, max = self._core:GetLimits()
		local delta = input.Position.Z * self._zoomStep
		self._targetDistance = math_clamp(self._targetDistance - delta, min, max)
	end
end

function CameraPC._onInputBegan(self: CameraPC, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType == MOUSE_BUTTON_RIGHT then
		if not self._core._shiftLockActive then
			self:_beginRotation()
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift and not gameProcessed then
		local orchestrator = self._orchestrator
		if orchestrator and typeof(orchestrator.ToggleShiftLock) == "function" then
			(orchestrator :: any):ToggleShiftLock() -- Fixed colon-call warning via explicit cast
		end
	end
end

function CameraPC._onInputEnded(self: CameraPC, input: InputObject, _gameProcessed: boolean): ()
	if not self._enabled then
		return
	end

	if input.UserInputType == MOUSE_BUTTON_RIGHT then
		if not self._core._shiftLockActive then
			self:_endRotation()
		end
	end
end

function CameraPC.Enable(self: CameraPC): ()
	if self._enabled then
		return
	end

	self._enabled = true

	local connections = self._connections
	connections[1] = UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_onInputChanged(input, gameProcessed)
	end)
	connections[2] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_onInputBegan(input, gameProcessed)
	end)
	connections[3] = UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_onInputEnded(input, gameProcessed)
	end)
end

function CameraPC.Disable(self: CameraPC): ()
	if not self._enabled then
		return
	end

	self._enabled = false
	self:_endRotation()
	self:_disconnectAll()
end

function CameraPC.Update(self: CameraPC, input: CameraPCUpdateInput): CameraCore.CameraUpdateOutput
	local isShiftLocked = self._core._shiftLockActive

	if isShiftLocked then
		if self._isRotating then
			self:_endRotation()
		end

		-- Enforce mouse lock behavior only when it differs (avoids 2x overhead of continuous writes)
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end

		self:_applyDragRotation(UserInputService:GetMouseDelta())
	else
		if not UserInputService.MouseIconEnabled and not self._isRotating then
			UserInputService.MouseIconEnabled = true
		end

		if UserInputService:IsMouseButtonPressed(MOUSE_BUTTON_RIGHT) then
			if not self._isRotating then
				self:_beginRotation()
			end

			self:_applyDragRotation(UserInputService:GetMouseDelta())
		elseif self._isRotating then
			self:_endRotation()
		end
	end

	return self._core:Update({
		focusOrigin = input.focusOrigin,
		rotation = self._rotation,
		targetDistance = self._targetDistance,
		deltaTime = input.deltaTime,
		filterInstances = input.filterInstances,
	})
end

return CameraPC