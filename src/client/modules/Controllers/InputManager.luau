--!strict
--[[
    InputManager
    Handles device detection (PC vs Phone). 
    Self-initializes upon first require to keep MainClient decoupled.
]]

local UserInputService = game:GetService("UserInputService")

-- Types
export type DeviceType = "PC" | "Phone"
type DeviceChangedCallback = (newDevice: DeviceType) -> ()

local InputManager = {}

-- Private State
local _currentDevice: DeviceType = "PC"
local _listeners: { DeviceChangedCallback } = {}

-- Constants (Rule 3.2: Localization)
local PC_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.MouseMovement] = true,
}

--[[
    Internal logic to determine device type.
]]
local function _calculateDeviceType(recentInput: Enum.UserInputType?): DeviceType
	if recentInput == Enum.UserInputType.Touch then
		return "Phone"
	end

	if recentInput and PC_INPUT_TYPES[recentInput] then
		return "PC"
	end

	if UserInputService.KeyboardEnabled or UserInputService.MouseEnabled then
		return "PC"
	end

	return "Phone"
end

--[[
    Returns the current detected device type.
]]
function InputManager:GetDeviceType(): DeviceType
	return _currentDevice
end

--[[
    Registers a callback for device changes.
]]
function InputManager:OnDeviceChanged(callback: DeviceChangedCallback): ()
	table.insert(_listeners, callback)
end

-- SELF-INITIALIZATION BLOCK
-- This runs once when the module is first required.
do
    _currentDevice = _calculateDeviceType(UserInputService:GetLastInputType())

    UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
        local newDevice: DeviceType = _calculateDeviceType(inputType)
        
        if newDevice ~= _currentDevice then
            _currentDevice = newDevice
            -- Rule 5.1: Use task library for deferred execution
            for _, callback in _listeners do
                task.spawn(callback, _currentDevice)
            end
        end
    end)
end

return InputManager