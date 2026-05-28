--!strict
--[[
	CameraPC
	Desktop camera controller: right-click drag to rotate, scroll wheel to zoom.
	Raw input is captured via UserInputService; pose is resolved in Update for RenderStep use.
]]

local GuiService = game:GetService("GuiService")
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
	_yaw: number,
	_pitch: number,
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
	Builds the look CFrame passed into CameraCore.
]]
local function buildRotation(yaw: number, pitch: number): CFrame
	return CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

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

	self._yaw = 0
	self._pitch = 0
	self._targetDistance = self._core:GetSmoothedDistance()
	self._isRotating = false
	self._enabled = false
	self._savedMouseBehavior = Enum.MouseBehavior.Default
	self._connections = table.create(3) :: { RBXScriptConnection }
	self._orchestrator = resolvedConfig.orchestrator

	return (self :: any) :: CameraPC
end

function CameraPC.GetRotation(self: CameraPC): CFrame
	return buildRotation(self._yaw, self._pitch)
end

function CameraPC.GetYawPitch(self: CameraPC): (number, number)
	return self._yaw, self._pitch
end

function CameraPC.GetTargetDistance(self: CameraPC): number
	return self._targetDistance
end

function CameraPC.GetSmoothedDistance(self: CameraPC): number
	return self._core:GetSmoothedDistance()
end

function CameraPC.GetViewState(self: CameraPC): CameraViewState
	return {
		rotation = buildRotation(self._yaw, self._pitch),
		targetDistance = self._targetDistance,
		smoothedDistance = self._core:GetSmoothedDistance(),
	}
end

function CameraPC.ApplyViewState(self: CameraPC, state: CameraViewState): ()
	local pitch, yaw, _ = state.rotation:ToEulerAnglesYXZ()
	self:SetRotation(yaw, pitch)
	self._targetDistance = state.targetDistance
	self._core:ResetZoom(state.smoothedDistance)
end

function CameraPC.SetRotation(self: CameraPC, yaw: number, pitch: number): ()
	self._yaw = yaw
	self._pitch = math_clamp(pitch, self._minPitch, self._maxPitch)
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
	UserInputService.MouseBehavior = MOUSE_LOCK_BEHAVIOR
end

function CameraPC._endRotation(self: CameraPC): ()
	if not self._isRotating then
		return
	end

	self._isRotating = false
	UserInputService.MouseBehavior = self._savedMouseBehavior
end

function CameraPC._onInputChanged(self: CameraPC, input: InputObject, gameProcessed: boolean): ()
	if not self._enabled or gameProcessed then
		return
	end

	if input.UserInputType == MOUSE_WHEEL then
		-- Block zoom adjustments when shift lock is active
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
		-- Prevent right-click conflicts when shift lock is actively managing the mouse state
		if not self._core._shiftLockActive then
			self:_beginRotation()
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift and not gameProcessed then
		local orchestrator = self._orchestrator or require(script.Parent :: any)
		if orchestrator and typeof(orchestrator.ToggleShiftLock) == "function" then
			orchestrator:ToggleShiftLock()
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
		-- Terminate any ongoing manual RMB dragging state if shift lock was activated mid-drag
		if self._isRotating then
			self:_endRotation()
		end

		-- Ensure Shift Lock settings remain active and override other script requests.
		-- LockCurrentPosition keeps the cursor exactly where it was on screen when Shift Lock started.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = false

		local mouseDelta = UserInputService:GetMouseDelta()
		if mouseDelta.Magnitude > 0 then
			self._yaw -= mouseDelta.X * self._yawSensitivity
			self._pitch = math_clamp(
				self._pitch - mouseDelta.Y * self._pitchSensitivity,
				self._minPitch,
				self._maxPitch
			)
		end
	else
		-- Ensure default mouse visibility is restored when shift lock is turned off
		if not UserInputService.MouseIconEnabled and not self._isRotating then
			UserInputService.MouseIconEnabled = true
		end

		if UserInputService:IsMouseButtonPressed(MOUSE_BUTTON_RIGHT) then
			if not self._isRotating then
				self:_beginRotation()
			end

			local mouseDelta = UserInputService:GetMouseDelta()
			if mouseDelta.Magnitude > 0 then
				self._yaw -= mouseDelta.X * self._yawSensitivity
				self._pitch = math_clamp(
					self._pitch - mouseDelta.Y * self._pitchSensitivity,
					self._minPitch,
					self._maxPitch
				)
			end
		elseif self._isRotating then
			self:_endRotation()
		end
	end

	return self._core:Update({
		focusOrigin = input.focusOrigin,
		rotation = buildRotation(self._yaw, self._pitch),
		targetDistance = self._targetDistance,
		deltaTime = input.deltaTime,
		filterInstances = input.filterInstances,
	})
end

return CameraPC