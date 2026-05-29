--!strict
local Players = game:GetService("Players")

type ManagerType = { init: () -> () }

local localPlayer = Players.LocalPlayer :: Player
local playerScripts = script.Parent
local modulesFolder = playerScripts:WaitForChild("modules") :: Folder
local uiFolder = modulesFolder:WaitForChild("ui") :: Folder

local uiManagerInstance = uiFolder:WaitForChild("UIManager") :: ModuleScript
local settingsClientInstance = uiFolder:WaitForChild("SettingsClient") :: ModuleScript

local UIManager = require(uiManagerInstance) :: ManagerType
local SettingsClient = require(settingsClientInstance) :: ManagerType

local function initClient(): ()
	if UIManager and typeof(UIManager.init) == "function" then
		UIManager.init()
	end
	
	if SettingsClient and typeof(SettingsClient.init) == "function" then
		SettingsClient.init()
	else
		warn("[Client] SettingsClient module does not implement an 'init' function.")
	end
end

initClient()