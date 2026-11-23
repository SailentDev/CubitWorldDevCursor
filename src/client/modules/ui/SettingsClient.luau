--!strict
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Blink = require(ReplicatedStorage.Shared.Blink.network_client)
local Types = require(ReplicatedStorage.Shared.Types)

local StatisticsTracker = require(script.Parent:WaitForChild("StatisticsTracker"))

local SettingsClient = {}

local COLOR_ENABLED = Color3.fromRGB(46, 204, 113)
local COLOR_DISABLED = Color3.fromRGB(231, 76, 60)
local SETTING_LOCK_DURATION = 1.2

local isInitialized = false
local isTrackerActive = false

local cachedSettings: Types.Settings = {
	FOV = 70,
	MusicVol = 50,
	ShowFPS = false,
	GlobalShadows = true,
}

local lastLocalUpdates: { [Types.SettingKey]: number } = {}

local settingsUpdatedSignal = Instance.new("BindableEvent")
SettingsClient.SettingsUpdated = settingsUpdatedSignal.Event

local fovFill: Frame? = nil
local fovController: Frame? = nil
local fovValueLabel: TextLabel? = nil
local musicFill: Frame? = nil
local musicController: Frame? = nil
local musicValueLabel: TextLabel? = nil
local shadowsButton: TextButton? = nil
local statisticsButton: TextButton? = nil
local statisticsLabel: TextLabel? = nil

local function waitForChildPath(parent: Instance, childName: string, timeout: number, parentPath: string): Instance?
	local found = parent:WaitForChild(childName, timeout)
	if not found then
		warn(`[SettingsClient] Missing instance at path: {parentPath}.{childName}`)
		return nil
	end
	return found
end

local function getSettingInternal(key: Types.SettingKey): number | boolean
	if key == "FOV" then
		return cachedSettings.FOV
	elseif key == "MusicVol" then
		return cachedSettings.MusicVol
	elseif key == "ShowFPS" then
		return cachedSettings.ShowFPS
	else
		return cachedSettings.GlobalShadows
	end
end

local function setNumberSetting(key: "FOV" | "MusicVol", value: number): ()
	if key == "FOV" then
		cachedSettings.FOV = value
	else
		cachedSettings.MusicVol = value
	end
end

local function setBooleanSetting(key: "ShowFPS" | "GlobalShadows", value: boolean): ()
	if key == "ShowFPS" then
		cachedSettings.ShowFPS = value
	else
		cachedSettings.GlobalShadows = value
	end
end

local function applyEngineSettings(): ()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = cachedSettings.FOV
	end
	Lighting.GlobalShadows = cachedSettings.GlobalShadows
end

local function updateVisuals(): ()
	if not isInitialized then
		return
	end

	if fovFill and fovController and fovValueLabel then
		local fovPct = math.clamp((cachedSettings.FOV - 30) / 90, 0, 1)
		fovFill.Size = UDim2.fromScale(fovPct, 1)
		fovController.Position = UDim2.fromScale(fovPct, fovController.Position.Y.Scale)
		fovValueLabel.Text = tostring(math.round(cachedSettings.FOV))
	end

	if musicFill and musicController and musicValueLabel then
		local musicPct = math.clamp(cachedSettings.MusicVol / 100, 0, 1)
		musicFill.Size = UDim2.fromScale(musicPct, 1)
		musicController.Position = UDim2.fromScale(musicPct, musicController.Position.Y.Scale)
		musicValueLabel.Text = tostring(math.round(cachedSettings.MusicVol))
	end

	if shadowsButton then
		shadowsButton.BackgroundColor3 = if cachedSettings.GlobalShadows then COLOR_ENABLED else COLOR_DISABLED
	end
	if statisticsButton then
		statisticsButton.BackgroundColor3 = if cachedSettings.ShowFPS then COLOR_ENABLED else COLOR_DISABLED
	end

	if statisticsLabel then
		if cachedSettings.ShowFPS then
			statisticsLabel.Visible = true
			if not isTrackerActive then
				isTrackerActive = true
				StatisticsTracker.Start(statisticsLabel)
			end
		else
			statisticsLabel.Visible = false
			if isTrackerActive then
				isTrackerActive = false
				StatisticsTracker.Stop()
			end
		end
	end

	applyEngineSettings()
end

function SettingsClient.GetSetting(settingName: Types.SettingKey): number | boolean
	return getSettingInternal(settingName)
end

function SettingsClient.UpdateSetting(settingName: Types.SettingKey, value: number | boolean): ()
	if (settingName == "FOV" or settingName == "MusicVol") and typeof(value) == "number" then
		setNumberSetting(settingName, value)
	elseif (settingName == "ShowFPS" or settingName == "GlobalShadows") and typeof(value) == "boolean" then
		setBooleanSetting(settingName, value)
	else
		return
	end

	lastLocalUpdates[settingName] = os.clock()
	updateVisuals()
	settingsUpdatedSignal:Fire(settingName, value)

	Blink.UpdateSettings.Fire({
		FOV = if settingName == "FOV" then cachedSettings.FOV else nil,
		MusicVol = if settingName == "MusicVol" then cachedSettings.MusicVol else nil,
		ShowFPS = if settingName == "ShowFPS" then cachedSettings.ShowFPS else nil,
		GlobalShadows = if settingName == "GlobalShadows" then cachedSettings.GlobalShadows else nil,
	})
end

local function setupSlider(
	sliderFrame: Frame,
	canvasGroup: CanvasGroup,
	fillFrame: Frame,
	sliderController: Frame,
	valueLabel: TextLabel,
	settingName: "FOV" | "MusicVol",
	minValue: number,
	maxValue: number
): ()
	sliderFrame.Active = true
	sliderController.Active = true
	canvasGroup.Active = false
	fillFrame.Active = false
	canvasGroup.Interactable = true
	fillFrame.Interactable = false
	sliderController.Interactable = true

	sliderController.AnchorPoint = Vector2.new(0.5, sliderController.AnchorPoint.Y)
	local isDragging = false

	local function calculateAndUpdate(input: InputObject): ()
		local frameSize = sliderFrame.AbsoluteSize
		if frameSize.X <= 0 then
			return
		end

		local relativeX = input.Position.X - sliderFrame.AbsolutePosition.X
		local percentage = math.clamp(relativeX / frameSize.X, 0, 1)

		fillFrame.Size = UDim2.fromScale(percentage, 1)
		sliderController.Position = UDim2.fromScale(percentage, sliderController.Position.Y.Scale)

		local calculatedValue = math.round(minValue + (percentage * (maxValue - minValue)))
		valueLabel.Text = tostring(calculatedValue)

		setNumberSetting(settingName, calculatedValue)
		lastLocalUpdates[settingName] = os.clock()

		applyEngineSettings()
		settingsUpdatedSignal:Fire(settingName, calculatedValue)
	end

	local function commitDrag(): ()
		if not isDragging then
			return
		end
		isDragging = false
		local finalPct = fillFrame.Size.Width.Scale
		local finalValue = math.round(minValue + (finalPct * (maxValue - minValue)))
		SettingsClient.UpdateSetting(settingName, finalValue)
	end

	local function beginDrag(input: InputObject): ()
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			calculateAndUpdate(input)
		end
	end

	sliderFrame.InputBegan:Connect(beginDrag)
	sliderController.InputBegan:Connect(beginDrag)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			calculateAndUpdate(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			commitDrag()
		end
	end)

	GuiService.MenuOpened:Connect(commitDrag)
	UserInputService.WindowFocusReleased:Connect(commitDrag)
end

local function applyServerSetting<T>(
	key: Types.SettingKey,
	incoming: T?,
	current: T,
	now: number
): (T, boolean)
	if incoming == nil then
		return current, false
	end
	if now - (lastLocalUpdates[key] or 0) <= SETTING_LOCK_DURATION then
		return current, false
	end
	if incoming ~= current then
		settingsUpdatedSignal:Fire(key, incoming)
		return incoming, true
	end
	return current, false
end

function SettingsClient.OnInit(): ()
	if isInitialized then
		return
	end

	Blink.SyncSettings.On(function(validatedSettings: Types.SettingsUpdate)
		local now = os.clock()
		local changed = false

		local newFov, fovChanged = applyServerSetting("FOV", validatedSettings.FOV, cachedSettings.FOV, now)
		if fovChanged then
			cachedSettings.FOV = newFov
			changed = true
		end

		local newVol, volChanged = applyServerSetting("MusicVol", validatedSettings.MusicVol, cachedSettings.MusicVol, now)
		if volChanged then
			cachedSettings.MusicVol = newVol
			changed = true
		end

		local newFps, fpsChanged = applyServerSetting("ShowFPS", validatedSettings.ShowFPS, cachedSettings.ShowFPS, now)
		if fpsChanged then
			cachedSettings.ShowFPS = newFps
			changed = true
		end

		local newShadows, shadowsChanged = applyServerSetting("GlobalShadows", validatedSettings.GlobalShadows, cachedSettings.GlobalShadows, now)
		if shadowsChanged then
			cachedSettings.GlobalShadows = newShadows
			changed = true
		end

		if changed then
			updateVisuals()
		end
	end)

	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = waitForChildPath(localPlayer, "PlayerGui", 5, "LocalPlayer")
	if not playerGui or not playerGui:IsA("PlayerGui") then
		return
	end

	local settingsGui = waitForChildPath(playerGui, "SettingsGui", 5, "PlayerGui")
	if not settingsGui or not settingsGui:IsA("ScreenGui") then
		if settingsGui then
			warn("[SettingsClient] PlayerGui.SettingsGui is not a ScreenGui")
		end
		return
	end

	local settingsFrame = waitForChildPath(settingsGui, "Settings", 3, "PlayerGui.SettingsGui")
	if not settingsFrame or not settingsFrame:IsA("Frame") then
		if settingsFrame then
			warn("[SettingsClient] PlayerGui.SettingsGui.Settings is not a Frame")
		end
		return
	end

	local settingsPath = "PlayerGui.SettingsGui.Settings"

	local fovSliderFrame = waitForChildPath(settingsFrame, "FovSliderFrame", 3, settingsPath)
	if not fovSliderFrame or not fovSliderFrame:IsA("Frame") then
		return
	end
	local fovCanvasGroup = waitForChildPath(fovSliderFrame, "CanvasGroup", 3, settingsPath .. ".FovSliderFrame")
	if not fovCanvasGroup or not fovCanvasGroup:IsA("CanvasGroup") then
		return
	end
	local fovFillInst = waitForChildPath(fovCanvasGroup, "Fill", 3, settingsPath .. ".FovSliderFrame.CanvasGroup")
	local fovControllerInst = waitForChildPath(fovCanvasGroup, "SliderController", 3, settingsPath .. ".FovSliderFrame.CanvasGroup")
	if not fovFillInst or not fovFillInst:IsA("Frame") or not fovControllerInst or not fovControllerInst:IsA("Frame") then
		return
	end

	local musicSliderFrame = waitForChildPath(settingsFrame, "MusicSliderFrame", 3, settingsPath)
	if not musicSliderFrame or not musicSliderFrame:IsA("Frame") then
		return
	end
	local musicCanvasGroup = waitForChildPath(musicSliderFrame, "CanvasGroup", 3, settingsPath .. ".MusicSliderFrame")
	if not musicCanvasGroup or not musicCanvasGroup:IsA("CanvasGroup") then
		return
	end
	local musicFillInst = waitForChildPath(musicCanvasGroup, "Fill", 3, settingsPath .. ".MusicSliderFrame.CanvasGroup")
	local musicControllerInst = waitForChildPath(musicCanvasGroup, "SliderController", 3, settingsPath .. ".MusicSliderFrame.CanvasGroup")
	if not musicFillInst or not musicFillInst:IsA("Frame") or not musicControllerInst or not musicControllerInst:IsA("Frame") then
		return
	end

	local shadowsButtonInst = waitForChildPath(settingsFrame, "ShadowsButton", 3, settingsPath)
	local statisticsButtonInst = waitForChildPath(settingsFrame, "StatisticsButton", 3, settingsPath)
	local statisticsLabelInst = waitForChildPath(settingsGui, "StatisticsLabel", 3, "PlayerGui.SettingsGui")
	local fovValueLabelInst = waitForChildPath(settingsFrame, "FovValue", 3, settingsPath)
	local musicValueLabelInst = waitForChildPath(settingsFrame, "MusicValue", 3, settingsPath)

	if not shadowsButtonInst or not shadowsButtonInst:IsA("TextButton")
		or not statisticsButtonInst or not statisticsButtonInst:IsA("TextButton")
		or not statisticsLabelInst or not statisticsLabelInst:IsA("TextLabel")
		or not fovValueLabelInst or not fovValueLabelInst:IsA("TextLabel")
		or not musicValueLabelInst or not musicValueLabelInst:IsA("TextLabel")
	then
		return
	end

	fovFill = fovFillInst
	fovController = fovControllerInst
	fovValueLabel = fovValueLabelInst
	musicFill = musicFillInst
	musicController = musicControllerInst
	musicValueLabel = musicValueLabelInst
	shadowsButton = shadowsButtonInst
	statisticsButton = statisticsButtonInst
	statisticsLabel = statisticsLabelInst

	isInitialized = true

	setupSlider(fovSliderFrame, fovCanvasGroup, fovFillInst, fovControllerInst, fovValueLabelInst, "FOV", 30, 120)
	setupSlider(musicSliderFrame, musicCanvasGroup, musicFillInst, musicControllerInst, musicValueLabelInst, "MusicVol", 0, 100)

	shadowsButtonInst.Activated:Connect(function()
		SettingsClient.UpdateSetting("GlobalShadows", not cachedSettings.GlobalShadows)
	end)

	statisticsButtonInst.Activated:Connect(function()
		SettingsClient.UpdateSetting("ShowFPS", not cachedSettings.ShowFPS)
	end)

	localPlayer.CharacterAdded:Connect(function()
		task.defer(applyEngineSettings)
	end)

	updateVisuals()
end

return SettingsClient