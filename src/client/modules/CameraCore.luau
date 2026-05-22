--!strict
--!native
--[[
	CameraCore
	Shared third-person camera math: spherecast collision, smoothed zoom distance,
	and instantaneous positional/orientational updates for responsive feel.
]]

local Workspace = game:GetService("Workspace")

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
	filterInstances: { Instance }?,
}

export type CameraUpdateOutput = {
	cframe: CFrame,
	focus: Vector3,
	distance: number,
}

-- [UPDATED] Added all internal properties and the _resolveCollision method to the type definition.
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
	_filterInstances: { Instance },
	
	-- Methods
	Update: (self: CameraCore, input: CameraUpdateInput) -> CameraUpdateOutput,
	SetFilterInstances: (self: CameraCore, instances: { Instance }) -> (),
	GetSmoothedDistance: (self: CameraCore) -> number,
	ResetZoom: (self: CameraCore, distance: number?) -> (),
	_resolveCollision: (self: CameraCore, focus: Vector3, lookVector: Vector3, distance: number) -> Vector3,
	GetLimits: (self: CameraCore) -> (number, number),
}

local DEFAULT_SPHERE_RADIUS = 0.35
local DEFAULT_MIN_DISTANCE = 2
local DEFAULT_MAX_DISTANCE = 24
local DEFAULT_DISTANCE = 12
local DEFAULT_ZOOM_LERP_SPEED = 12
local DEFAULT_COLLISION_PADDING = 0.15
local DEFAULT_ORIGIN_EPSILON = 0.1

local EPSILON = 1e-4

local CameraCore = {}
CameraCore.__index = CameraCore

--[[
	Exponential smoothing for zoom only; framerate-independent via deltaTime.
]]
local function lerpZoom(current: number, target: number, speed: number, deltaTime: number): number
	if deltaTime <= 0 then
		return target
	end

	local alpha = 1 - math.exp(-speed * deltaTime)
	return current + (target - current) * alpha
end

-- In CameraCore
function CameraCore.GetLimits(self: CameraCore): (number, number)
    return self._minDistance, self._maxDistance
end

--[[
	Builds a CameraCore instance with cached RaycastParams for spherecasts.
]]
function CameraCore.new(config: CameraCoreConfig?): CameraCore
	-- [UPDATED] Explicitly define the type here so Luau knows what properties exist
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

	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.IgnoreWater = true
	self._raycastParams.RespectCanCollide = true
	self._filterInstances = {} :: { Instance }

	return (self :: any) :: CameraCore
end

--[[
	Replaces the exclude list used by spherecast collision queries.
]]
function CameraCore.SetFilterInstances(self: CameraCore, instances: { Instance }): ()
	-- BLOKADA: Jeśli to dokładnie ta sama lista, przerwij!
	if self._filterInstances == instances then
		return
	end
	
	self._filterInstances = instances
	self._raycastParams.FilterDescendantsInstances = instances
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

-- We allow the camera to get closer than minDistance if a wall is blocking it.
-- We only clamp to 0 to ensure it doesn't go "inside" the focus point.
local safeDistance = math.max(result.Distance - self._collisionPadding, 0)
return castOrigin + backward.Unit * safeDistance
end

--[[
	Computes an instantaneous camera CFrame and focus point from rotation and zoom inputs.
	Only target distance is smoothed; position and orientation follow inputs directly each frame.
]]
function CameraCore.Update(self: CameraCore, input: CameraUpdateInput): CameraUpdateOutput
	if input.filterInstances then
		self:SetFilterInstances(input.filterInstances)
	end

	local clampedTarget = math.clamp(input.targetDistance, self._minDistance, self._maxDistance)
	self._smoothedDistance = lerpZoom(
		self._smoothedDistance,
		clampedTarget,
		self._zoomLerpSpeed,
		input.deltaTime
	)

	local focus = input.focusOrigin
	local lookVector = input.rotation.LookVector
	local cameraPosition = self:_resolveCollision(focus, lookVector, self._smoothedDistance)

	-- Instantaneous aim at focus; no positional/orientational smoothing.
	local cframe = CFrame.lookAt(cameraPosition, focus)

	return {
		cframe = cframe,
		focus = focus,
		distance = (cameraPosition - focus).Magnitude,
	}
end

--[[
	Returns the min and max distance limits.
]]
function CameraCore.GetLimits(self: CameraCore): (number, number)
	return self._minDistance, self._maxDistance
end

return CameraCore