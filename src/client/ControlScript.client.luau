--!strict
local Players = game:GetService("Players")

local modulesFolder = script.Parent:WaitForChild("modules") :: Folder
local controllersFolder = modulesFolder:WaitForChild("Controllers") :: Folder

local InputManager = require(controllersFolder:WaitForChild("InputManager"))
local ControlPC = require(controllersFolder:WaitForChild("ControlPC"))
local ControlPhone = require(controllersFolder:WaitForChild("ControlPhone"))

type DeviceType = InputManager.DeviceType
type ControlModule = {
	Enable: (self: ControlModule) -> (),
	Disable: (self: ControlModule) -> (),
}

local localPlayer = Players.LocalPlayer :: Player
local activeController: ControlModule? = nil
local currentDevice: DeviceType? = nil

local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
local gameHUD = playerGui:WaitForChild("GameHUD", 10) :: ScreenGui?
local joystickBase = if gameHUD then gameHUD:WaitForChild("JoystickBase", 5) :: Frame? else nil
local jumpButton = if gameHUD then gameHUD:WaitForChild("JumpButton", 5) :: ImageButton? else nil

local function switchController(newDevice: DeviceType): ()
	if currentDevice == newDevice then
		return
	end

	if activeController then
		activeController:Disable()
	end

	local isPhone = (newDevice == "Phone")
	if jumpButton then
		jumpButton.Visible = isPhone
	end
	if joystickBase then
		joystickBase.Visible = false
	end

	if newDevice == "PC" then
		activeController = ControlPC
	elseif newDevice == "Phone" then
		activeController = ControlPhone
	end

	if activeController then
		activeController:Enable()
		currentDevice = newDevice
	end
end

switchController(InputManager:GetDeviceType())
InputManager:OnDeviceChanged(function(newDevice: DeviceType)
	task.defer(switchController, newDevice)
end)