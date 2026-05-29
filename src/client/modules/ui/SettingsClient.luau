--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Types = require(ReplicatedStorage.Shared.Types)
local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local StatisticsTracker = require(script.Parent:WaitForChild("StatisticsTracker"))

local SettingsClient = {}
local isInitialized = false
local isTrackerActive = false

local cachedSettings: Types.Settings = {
	FOV = 70,
	MusicVol = 50,
	ShowFPS = false,
	GlobalShadows = true,
}

local lastLocalUpdates: { [string]: number } = {}
local SETTING_LOCK_DURATION = 1.2

local settingsUpdatedSignal = Instance.new("BindableEvent")
SettingsClient.SettingsUpdated = settingsUpdatedSignal.Event

local fovFill, fovController, fovValueLabel
local musicFill, musicController, musicValueLabel
local shadowsButton, statisticsButton, statisticsLabel

local COLOR_ENABLED = Color3.fromRGB(46, 204, 113)
local COLOR_DISABLED = Color3.fromRGB(231, 76, 60)

local function applyEngineSettings()
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = cachedSettings.FOV
	end
	Lighting.GlobalShadows = cachedSettings.GlobalShadows
end

local function updateVisuals()
	if not isInitialized then return end
	
	-- FOV Progress Calculation
	local fovPct = math.clamp((cachedSettings.FOV - 30) / 90, 0, 1)
	fovFill.Size = UDim2.fromScale(fovPct, 1)
	fovController.Position = UDim2.fromScale(fovPct, fovController.Position.Y.Scale)
	fovValueLabel.Text = tostring(math.round(cachedSettings.FOV))

	-- Music Progress Calculation
	local musicPct = math.clamp(cachedSettings.MusicVol / 100, 0, 1)
	musicFill.Size = UDim2.fromScale(musicPct, 1)
	musicController.Position = UDim2.fromScale(musicPct, musicController.Position.Y.Scale)
	musicValueLabel.Text = tostring(math.round(cachedSettings.MusicVol))

	-- Standard toggles updates
	shadowsButton.BackgroundColor3 = if cachedSettings.GlobalShadows then COLOR_ENABLED else COLOR_DISABLED
	statisticsButton.BackgroundColor3 = if cachedSettings.ShowFPS then COLOR_ENABLED else COLOR_DISABLED

	-- Manage performance statistics lifecycle
	if cachedSettings.ShowFPS then
		statisticsLabel.Visible = true
		if not isTrackerActive then
			isTrackerActive = true
			StatisticsTracker.Init(statisticsLabel)
		end
	else
		statisticsLabel.Visible = false
		if isTrackerActive then
			isTrackerActive = false
			StatisticsTracker.Stop()
		end
	end

	applyEngineSettings()
end

function SettingsClient.GetSetting(settingName: string): any
	return (cachedSettings :: any)[settingName]
end

function SettingsClient.UpdateSetting(settingName: string, value: any)
	if (cachedSettings :: any)[settingName] == nil then return end
	
	cachedSettings[settingName] = value
	lastLocalUpdates[settingName] = os.clock()
	
	updateVisuals()
	settingsUpdatedSignal:Fire(settingName, value)

	local payload: Types.SettingsUpdate = { [settingName] = value }
	Blink.UpdateSettings.Fire(payload)
end

local function setupSlider(
	sliderFrame: Frame, 
	canvasGroup: CanvasGroup,
	fillFrame: Frame, 
	sliderController: GuiObject,
	valueLabel: TextLabel, 
	settingName: "FOV" | "MusicVol", 
	minValue: number, 
	maxValue: number
)
	sliderFrame.Active = true
	sliderController.Active = true
	canvasGroup.Active = false
	fillFrame.Active = false
	
	pcall(function()
		(canvasGroup :: any).Interactable = true
		(fillFrame :: any).Interactable = false
		(sliderController :: any).Interactable = true
	end)
	
	sliderController.AnchorPoint = Vector2.new(0.5, sliderController.AnchorPoint.Y)
	local isDragging = false

	local function calculateAndUpdate(input: InputObject)
		local frameSize = sliderFrame.AbsoluteSize
		if frameSize.X <= 0 then return end

		local relativeX = input.Position.X - sliderFrame.AbsolutePosition.X
		local percentage = math.clamp(relativeX / frameSize.X, 0, 1)

		fillFrame.Size = UDim2.fromScale(percentage, 1)
		sliderController.Position = UDim2.fromScale(percentage, sliderController.Position.Y.Scale)

		local calculatedValue = math.round(minValue + (percentage * (maxValue - minValue)))
		valueLabel.Text = tostring(calculatedValue)
		
		cachedSettings[settingName] = calculatedValue
		lastLocalUpdates[settingName] = os.clock()
		
		applyEngineSettings()
		settingsUpdatedSignal:Fire(settingName, calculatedValue)
	end

	sliderFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			calculateAndUpdate(input)
		end
	end)

	sliderController.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			calculateAndUpdate(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if isDragging then
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				calculateAndUpdate(input)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isDragging then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				isDragging = false
				local finalPct = fillFrame.Size.Width.Scale
				local finalValue = math.round(minValue + (finalPct * (maxValue - minValue)))
				SettingsClient.UpdateSetting(settingName, finalValue)
			end
		end
	end)
end

function SettingsClient.init()
	if isInitialized then return end
	
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local settingsGui = playerGui:WaitForChild("SettingsGui", 5) :: ScreenGui
	if not settingsGui then warn("[SettingsClient] SettingsGui missing") return end
	
	local settingsFrame = settingsGui:WaitForChild("Settings", 5) :: Frame
	if not settingsFrame then warn("[SettingsClient] Settings Frame missing") return end

	-- Slider resolution
	local fovSliderFrame = settingsFrame:WaitForChild("FovSliderFrame") :: Frame
	local fovCanvasGroup = fovSliderFrame:WaitForChild("CanvasGroup") :: CanvasGroup
	fovFill = fovCanvasGroup:WaitForChild("Fill") :: Frame
	fovController = fovCanvasGroup:WaitForChild("SliderController") :: GuiObject

	local musicSliderFrame = settingsFrame:WaitForChild("MusicSliderFrame") :: Frame
	local musicCanvasGroup = musicSliderFrame:WaitForChild("CanvasGroup") :: CanvasGroup
	musicFill = musicCanvasGroup:WaitForChild("Fill") :: Frame
	musicController = musicCanvasGroup:WaitForChild("SliderController") :: GuiObject

	-- Element connections
	shadowsButton = settingsFrame:WaitForChild("ShadowsButton") :: GuiButton
	statisticsButton = settingsFrame:WaitForChild("StatisticsButton") :: GuiButton
	statisticsLabel = settingsGui:WaitForChild("StatisticsLabel") :: TextLabel
	fovValueLabel = settingsFrame:WaitForChild("FovValue") :: TextLabel
	musicValueLabel = settingsFrame:WaitForChild("MusicValue") :: TextLabel

	isInitialized = true

	setupSlider(fovSliderFrame, fovCanvasGroup, fovFill, fovController, fovValueLabel, "FOV", 30, 120)
	setupSlider(musicSliderFrame, musicCanvasGroup, musicFill, musicController, musicValueLabel, "MusicVol", 0, 100)

	shadowsButton.Activated:Connect(function()
		SettingsClient.UpdateSetting("GlobalShadows", not cachedSettings.GlobalShadows)
	end)

	statisticsButton.Activated:Connect(function()
		SettingsClient.UpdateSetting("ShowFPS", not cachedSettings.ShowFPS)
	end)

	updateVisuals()
end

Players.LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.2)
	applyEngineSettings()
end)

Blink.SyncSettings.On(function(validatedSettings: any)
	if typeof(validatedSettings) == "table" then
		local changed = false
		local now = os.clock()
		
		for key, val in pairs(validatedSettings) do
			if (cachedSettings :: any)[key] ~= nil then
				local lastUpdate = lastLocalUpdates[key] or 0
				if now - lastUpdate > SETTING_LOCK_DURATION then
					if (cachedSettings :: any)[key] ~= val then
						(cachedSettings :: any)[key] = val
						settingsUpdatedSignal:Fire(key, val)
						changed = true
					end
				end
			end
		end
		if changed then 
			updateVisuals() 
		end
	end
end)

return SettingsClient