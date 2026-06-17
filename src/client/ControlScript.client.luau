--!strict
--[[
    ControlScript (Orchestrator)
    Manages device-specific modules and UI visibility.
]]

local Players = game:GetService("Players")
local task_defer = task.defer
local task_spawn = task.spawn

-- TYPES
type DeviceType = "PC" | "Phone"
type ControlModule = { Enable: (self: ControlModule) -> (), Disable: (self: ControlModule) -> () }
type InputManagerModule = { 
	GetDeviceType: (self: InputManagerModule) -> DeviceType, 
	OnDeviceChanged: (self: InputManagerModule, callback: (newDevice: DeviceType) -> ()) -> () 
}

-- STATE
local _activeController: ControlModule? = nil
local _currentDevice: DeviceType? = nil

-- UI REFERENCES
local player = Players.LocalPlayer :: Player
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local gameHUD = playerGui:WaitForChild("GameHUD") :: ScreenGui
local joystickBase = gameHUD:WaitForChild("JoystickBase") :: Frame
local jumpButton = gameHUD:WaitForChild("JumpButton") :: ImageButton

-- REFERENCES
local modulesFolder = script.Parent:WaitForChild("modules") :: Folder
local ControllersFolder = modulesFolder:WaitForChild("controllers") :: Folder

local InputManager = require(ControllersFolder:WaitForChild("InputManager")) :: InputManagerModule
local ControlPC = require(ControllersFolder:WaitForChild("ControlPC")) :: ControlModule
local ControlPhone = require(ControllersFolder:WaitForChild("ControlPhone")) :: ControlModule

local function switchController(newDevice: DeviceType): ()
	if _currentDevice == newDevice then return end
	
	if _activeController then _activeController:Disable() end

	-- UI Visibility Logic
	local isPhone = (newDevice == "Phone")
	jumpButton.Visible = isPhone
	joystickBase.Visible = false -- Phone module handles dynamic visibility

	if newDevice == "PC" then
		_activeController = ControlPC
	elseif newDevice == "Phone" then
		_activeController = ControlPhone
	end

	if _activeController then
		_activeController:Enable()
		_currentDevice = newDevice
	end
end

local function initialize(): ()
	switchController(InputManager:GetDeviceType())
	InputManager:OnDeviceChanged(function(newDevice: DeviceType)
		task_defer(switchController, newDevice) -- Optimized: defer instead of spawn
	end)
end

task_spawn(initialize)