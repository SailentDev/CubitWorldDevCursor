--!strict
local UserInputService = game:GetService("UserInputService")

export type DeviceType = "PC" | "Phone"
export type DeviceChangedCallback = (newDevice: DeviceType) -> ()
export type InputManagerModule = {
	GetDeviceType: (self: InputManagerModule) -> DeviceType,
	OnDeviceChanged: (self: InputManagerModule, callback: DeviceChangedCallback) -> (() -> ()),
}

local InputManager = {}

local PC_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.MouseMovement] = true,
}

local currentDevice: DeviceType = "PC"
local listeners: { DeviceChangedCallback } = {}

local function calculateDeviceType(recentInput: Enum.UserInputType?): DeviceType?
	if recentInput == Enum.UserInputType.Touch then
		return "Phone"
	end
	if recentInput and PC_INPUT_TYPES[recentInput] then
		return "PC"
	end
	return nil
end

local function getInitialDeviceType(): DeviceType
	local detected = calculateDeviceType(UserInputService:GetLastInputType())
	if detected then
		return detected
	end
	if UserInputService.KeyboardEnabled or UserInputService.MouseEnabled then
		return "PC"
	end
	return "Phone"
end

function InputManager:GetDeviceType(): DeviceType
	return currentDevice
end

function InputManager:OnDeviceChanged(callback: DeviceChangedCallback): () -> ()
	table.insert(listeners, callback)
	return function()
		local idx = table.find(listeners, callback)
		if idx then
			table.remove(listeners, idx)
		end
	end
end

currentDevice = getInitialDeviceType()

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	local newDevice = calculateDeviceType(inputType)
	if newDevice and newDevice ~= currentDevice then
		currentDevice = newDevice
		for _, callback in table.clone(listeners) do
			task.defer(callback, currentDevice)
		end
	end
end)

return InputManager :: InputManagerModule