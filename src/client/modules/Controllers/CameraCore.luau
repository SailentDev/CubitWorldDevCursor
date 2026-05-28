--!strict
--!native
--[[
	CameraCore
	Shared third-person camera math: spherecast collision, smoothed zoom distance,
	and instantaneous positional/orientational updates for responsive feel.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

export type CameraCoreConfig = {
	sphereRadius: number?,
	minDistance: number?,
	maxDistance: number?,
	defaultDistance: number?,
	zoomLerpSpeed: number?,
	collisionPadding: number?,
	raycastOriginEpsilon: number?,
}

export type CameraUpdateInput = {
	focusOrigin: Vector3,
	rotation: CFrame,
	targetDistance: number,
	deltaTime: number,
	filterInstances: { Instance }?, -- Retained in type for compatibility; ignored internally
}

export type CameraUpdateOutput = {
	cframe: CFrame,
	focus: Vector3,
	distance: number,
}

export type CameraCore = {
	-- Internal State
	_sphereRadius: number,
	_minDistance: number,
	_maxDistance: number,
	_zoomLerpSpeed: number,
	_collisionPadding: number,
	_raycastOriginEpsilon: number,
	_smoothedDistance: number,
	_raycastParams: RaycastParams,
	_shiftLockActive: boolean,
	_preSimulationConnection: RBXScriptConnection?,
	
	-- Methods
	Update: (self: CameraCore, input: CameraUpdateInput) -> CameraUpdateOutput,
	SetFilterInstances: (self: CameraCore, instances: { Instance }) -> (),
	GetSmoothedDistance: (self: CameraCore) -> number,
	ResetZoom: (self: CameraCore, distance: number?) -> (),
	_resolveCollision: (self: CameraCore, focus: Vector3, lookVector: Vector3, distance: number) -> Vector3,
	GetLimits: (self: CameraCore) -> (number, number),
	ApplyShiftLock: (self: CameraCore, isActive: boolean) -> (),
}

local DEFAULT_SPHERE_RADIUS = 0.25
local DEFAULT_MIN_DISTANCE = 2
local DEFAULT_MAX_DISTANCE = 24
local DEFAULT_DISTANCE = 12
local DEFAULT_ZOOM_LERP_SPEED = 12
local DEFAULT_COLLISION_PADDING = 0.15
local DEFAULT_ORIGIN_EPSILON = 0.1

local SHIFT_LOCK_OFFSET = Vector3.new(0, 0, 0)
local EPSILON = 1e-4

local CameraCore = {}
CameraCore.__index = CameraCore

--[[
	Exponential smoothing for zoom; framerate-independent via deltaTime.
]]
local function lerpZoom(current: number, target: number, speed: number, deltaTime: number): number
	if deltaTime <= 0 then
		return target
	end

	local clampedDT = math.min(deltaTime, 0.1)
	local alpha = 1 - math.exp(-speed * clampedDT)
	return current + (target - current) * alpha
end

--[[
	Builds a CameraCore instance with RaycastParams configured for the "Camera" collision group.
]]
function CameraCore.new(config: CameraCoreConfig?): CameraCore
	local resolvedConfig: CameraCoreConfig = config or {}

	local self = setmetatable({}, CameraCore) :: any

	self._sphereRadius = resolvedConfig.sphereRadius or DEFAULT_SPHERE_RADIUS
	self._minDistance = resolvedConfig.minDistance or DEFAULT_MIN_DISTANCE
	self._maxDistance = resolvedConfig.maxDistance or DEFAULT_MAX_DISTANCE
	self._zoomLerpSpeed = resolvedConfig.zoomLerpSpeed or DEFAULT_ZOOM_LERP_SPEED
	self._collisionPadding = resolvedConfig.collisionPadding or DEFAULT_COLLISION_PADDING
	self._raycastOriginEpsilon = resolvedConfig.raycastOriginEpsilon or DEFAULT_ORIGIN_EPSILON

	local defaultDistance = resolvedConfig.defaultDistance or DEFAULT_DISTANCE
	self._smoothedDistance = math.clamp(defaultDistance, self._minDistance, self._maxDistance)

	-- Configure RaycastParams to respect the Collision Group matrix
	self._raycastParams = RaycastParams.new()
	self._raycastParams.CollisionGroup = "Camera" -- Automatically ignores "Players" and "Assets2" groups
	self._raycastParams.IgnoreWater = true
	self._raycastParams.RespectCanCollide = true
	
	self._shiftLockActive = false
	self._preSimulationConnection = nil

	return (self :: any) :: CameraCore
end

--[[
	No-op implementation to maintain structural interface compatibility.
	Filtering is handled natively by the "Camera" CollisionGroup.
]]
function CameraCore.SetFilterInstances(self: CameraCore, instances: { Instance }): ()
	-- Intentional no-op: prevents unnecessary allocation and preserves performance.
end

--[[
	Returns the current smoothed zoom distance (post-lerp, pre-collision).
]]
function CameraCore.GetSmoothedDistance(self: CameraCore): number
	return self._smoothedDistance
end

--[[
	Snap or seed the internal zoom distance (e.g. on character respawn).
]]
function CameraCore.ResetZoom(self: CameraCore, distance: number?): ()
	local resolved = distance or self._smoothedDistance
	self._smoothedDistance = math.clamp(resolved, self._minDistance, self._maxDistance)
end

--[[
	Resolves the final camera world position using a spherecast from focus toward the ideal offset.
	Origin is nudged along the cast direction so casts do not start inside the focus volume.
]]
function CameraCore._resolveCollision(
	self: CameraCore,
	focus: Vector3,
	lookVector: Vector3,
	distance: number
): Vector3
	local backward = -lookVector
	local castDirection = backward * distance
	local castLength = castDirection.Magnitude

	if castLength < EPSILON then
		return focus
	end

	local castOrigin = focus + backward.Unit * self._raycastOriginEpsilon
	local castVector = backward * math.max(castLength - self._raycastOriginEpsilon, 0)

	if castVector.Magnitude < EPSILON then
		return focus + castDirection
	end

	local result = Workspace:Spherecast(castOrigin, self._sphereRadius, castVector, self._raycastParams)
	if not result then
		return focus + castDirection
	end

	local safeDistance = math.max(result.Distance - self._collisionPadding, 0)
	return castOrigin + backward.Unit * safeDistance
end

--[[
	Computes an instantaneous camera CFrame and focus point from rotation and zoom inputs.
	Only target distance is smoothed; position and orientation follow inputs directly each frame.
]]
function CameraCore.Update(self: CameraCore, input: CameraUpdateInput): CameraUpdateOutput
	local clampedTarget = math.clamp(input.targetDistance, self._minDistance, self._maxDistance)
	self._smoothedDistance = lerpZoom(
		self._smoothedDistance,
		clampedTarget,
		self._zoomLerpSpeed,
		input.deltaTime
	)

	local focus = input.focusOrigin

	-- Apply Shift Lock positional offset
	if self._shiftLockActive then
		local offsetWorld = input.rotation:VectorToWorldSpace(SHIFT_LOCK_OFFSET)
		focus = focus + offsetWorld
	end

	local lookVector = input.rotation.LookVector
	local cameraPosition = self:_resolveCollision(focus, lookVector, self._smoothedDistance)

	-- Offset translation directly onto pre-existing rotation matrix.
	local cframe = input.rotation + cameraPosition

	return {
		cframe = cframe,
		focus = focus,
		distance = (cameraPosition - focus).Magnitude,
	}
end

--[[
	Returns the min and max distance limits.
]]
function CameraCore.GetLimits(self: CameraCore) : (number, number)
	return self._minDistance, self._maxDistance
end

--[[
	Modifies the camera core's shift lock status. Handles state changes for UserInputService
	and Humanoid behavior changes.
]]
function CameraCore.ApplyShiftLock(self: CameraCore, isActive: boolean): ()
	self._shiftLockActive = isActive
	
	-- Clean up prior physics loop connections
	if self._preSimulationConnection then
		self._preSimulationConnection:Disconnect()
		self._preSimulationConnection = nil
	end

	-- Configure mouse lock behavior and visibility
	if isActive then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		UserInputService.MouseIconEnabled = false

		-- Align the character CFrame before the physics solver runs (PreSimulation).
		self._preSimulationConnection = RunService.PreSimulation:Connect(function()
			if not LocalPlayer then return end
			local character = LocalPlayer.Character
			if not character then return end
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local camera = Workspace.CurrentCamera
			if rootPart and camera then
				local lookVector = camera.CFrame.LookVector
				local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
				if horizontalLook.Magnitude > EPSILON then
					rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + horizontalLook.Unit)
				end
			end
		end)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end

	-- Configure Humanoid AutoRotate state
	if LocalPlayer then
		local character = LocalPlayer.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.AutoRotate = not isActive
			end
		end
	end
end

return CameraCore