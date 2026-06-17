-- script: modules/controllers/InputManager.luau
--!strict
-- Removed --!native as it provides no benefit here and wastes memory

local UserInputService = game:GetService("UserInputService")

export type DeviceType = "PC" | "Phone"
type DeviceChangedCallback = (newDevice: DeviceType) -> ()

local InputManager = {}
local _currentDevice: DeviceType = "PC"
local _listeners: { DeviceChangedCallback } = {}

local PC_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.MouseMovement] = true,
}

local function _calculateDeviceType(recentInput: Enum.UserInputType?): DeviceType
	if recentInput == Enum.UserInputType.Touch then return "Phone" end
	if recentInput and PC_INPUT_TYPES[recentInput] then return "PC" end
	if UserInputService.KeyboardEnabled or UserInputService.MouseEnabled then return "PC" end
	return "Phone"
end

function InputManager:GetDeviceType(): DeviceType
	return _currentDevice
end

function InputManager:OnDeviceChanged(callback: DeviceChangedCallback): ()
	table.insert(_listeners, callback)
end

do
	_currentDevice = _calculateDeviceType(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local newDevice: DeviceType = _calculateDeviceType(inputType)
		if newDevice ~= _currentDevice then
			_currentDevice = newDevice
			for _, callback in _listeners do
				task.defer(callback, _currentDevice) -- Optimized: defer is better for event propagation
			end
		end
	end)
end

return InputManager