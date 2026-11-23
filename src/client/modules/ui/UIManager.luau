--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

export type UIManagerModule = {
	OnInit: () -> (),
	transitionFrame: (frame: Frame, targetPosition: UDim2, show: boolean) -> (),
	applyButtonFeedback: (button: GuiButton) -> (),
}

type PanelInfo = {
	frame: Frame,
	originalPosition: UDim2,
	button: GuiButton,
	isOpen: boolean,
}

type TweenTracker = {
	tween: Tween,
	connection: RBXScriptConnection,
}

local UIManager = {}

local SLIDE_TIME_IN = 0.25
local SLIDE_TIME_OUT = 0.25
local SCALE_TIME = 0.12

local TWEEN_INFO_IN = TweenInfo.new(SLIDE_TIME_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_INFO_OUT = TweenInfo.new(SLIDE_TIME_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_INFO_SCALE = TweenInfo.new(SCALE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TWEEN_INFO_CLICK = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local activeTrackers: { [Frame]: TweenTracker } = {}
local registeredPanels: { [Frame]: PanelInfo } = {}

local function waitForChildPath(parent: Instance, childName: string, timeout: number, parentPath: string): Instance?
	local found = parent:WaitForChild(childName, timeout)
	if not found then
		warn(`[UIManager] Missing instance at path: {parentPath}.{childName}`)
		return nil
	end
	return found
end

local function transitionFrame(frame: Frame, targetPosition: UDim2, show: boolean): ()
	local existingTracker = activeTrackers[frame]
	if existingTracker then
		existingTracker.connection:Disconnect()
		existingTracker.tween:Cancel()
		existingTracker.tween:Destroy()
		activeTrackers[frame] = nil
	end

	if show then
		frame.Position = UDim2.new(targetPosition.X.Scale, targetPosition.X.Offset, 1.5, 0)
		frame.Visible = true

		local tween = TweenService:Create(frame, TWEEN_INFO_IN, { Position = targetPosition })
		local connection: RBXScriptConnection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			tween:Destroy()
			activeTrackers[frame] = nil
		end)

		activeTrackers[frame] = { tween = tween, connection = connection }
		tween:Play()
	else
		local offscreenPos = UDim2.new(targetPosition.X.Scale, targetPosition.X.Offset, 1.5, 0)
		local tween = TweenService:Create(frame, TWEEN_INFO_OUT, { Position = offscreenPos })
		local connection: RBXScriptConnection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			tween:Destroy()
			frame.Visible = false
			activeTrackers[frame] = nil
		end)

		activeTrackers[frame] = { tween = tween, connection = connection }
		tween:Play()
	end
end

local function applyButtonFeedback(button: GuiButton): ()
	local existingScale = button:FindFirstChildOfClass("UIScale")
	local uiScale: UIScale
	if existingScale then
		uiScale = existingScale
	else
		local newScale = Instance.new("UIScale")
		newScale.Scale = 1
		newScale.Parent = button
		uiScale = newScale
	end

	local activeTween: Tween? = nil
	local isHovering = false

	local function playScale(targetScale: number, info: TweenInfo): ()
		if activeTween then
			activeTween:Cancel()
			activeTween:Destroy()
			activeTween = nil
		end

		local tween = TweenService:Create(uiScale, info, { Scale = targetScale })
		activeTween = tween
		tween.Completed:Connect(function()
			if activeTween == tween then
				activeTween = nil
			end
			tween:Destroy()
		end)
		tween:Play()
	end

	button.MouseEnter:Connect(function()
		isHovering = true
		playScale(1.08, TWEEN_INFO_SCALE)
	end)

	button.MouseLeave:Connect(function()
		isHovering = false
		playScale(1.0, TWEEN_INFO_SCALE)
	end)

	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			playScale(0.92, TWEEN_INFO_CLICK)
		end
	end)

	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			playScale(if isHovering then 1.08 else 1.0, TWEEN_INFO_SCALE)
		end
	end)
end

local function togglePanel(targetFrame: Frame): ()
	local info = registeredPanels[targetFrame]
	if not info then
		return
	end

	if info.isOpen then
		info.isOpen = false
		transitionFrame(targetFrame, info.originalPosition, false)
	else
		for otherFrame, otherInfo in registeredPanels do
			if otherFrame ~= targetFrame and otherInfo.isOpen then
				otherInfo.isOpen = false
				transitionFrame(otherFrame, otherInfo.originalPosition, false)
			end
		end

		info.isOpen = true
		transitionFrame(targetFrame, info.originalPosition, true)
	end
end

local function registerPanel(button: GuiButton, frame: Frame): ()
	local originalPosition = frame.Position
	frame.Visible = false

	local info: PanelInfo = {
		frame = frame,
		originalPosition = originalPosition,
		button = button,
		isOpen = false,
	}
	registeredPanels[frame] = info

	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible and activeTrackers[frame] == nil then
			info.isOpen = false
		end
	end)

	button.Activated:Connect(function()
		togglePanel(frame)
	end)
end

function UIManager.OnInit(): ()
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = waitForChildPath(localPlayer, "PlayerGui", 5, "LocalPlayer")
	if not playerGui then
		return
	end

	local mainHUD = waitForChildPath(playerGui, "MainHUD", 4, "PlayerGui")
	if not mainHUD then
		return
	end

	local buttonsFrame = waitForChildPath(mainHUD, "Buttons", 2, "PlayerGui.MainHUD")
	if not buttonsFrame then
		return
	end

	for _, child in buttonsFrame:GetChildren() do
		if child:IsA("GuiButton") then
			applyButtonFeedback(child)
		end
	end

	local settingsButton = waitForChildPath(buttonsFrame, "SettingsButton", 2, "PlayerGui.MainHUD.Buttons")
	local inventoryButton = waitForChildPath(buttonsFrame, "InventoryButton", 2, "PlayerGui.MainHUD.Buttons")
	local eggShopButton = waitForChildPath(buttonsFrame, "EggShopButton", 2, "PlayerGui.MainHUD.Buttons")

	local settingsGui = waitForChildPath(playerGui, "SettingsGui", 2, "PlayerGui")
	local settingsFrame = if settingsGui then waitForChildPath(settingsGui, "Settings", 2, "PlayerGui.SettingsGui") else nil

	local inventoryGui = waitForChildPath(playerGui, "InventoryGui", 2, "PlayerGui")
	local inventoryFrame = if inventoryGui then waitForChildPath(inventoryGui, "InventoryFrame", 2, "PlayerGui.InventoryGui") else nil

	local eggShopGui = waitForChildPath(playerGui, "EggShopGui", 2, "PlayerGui")
	local eggShopFrame = if eggShopGui then waitForChildPath(eggShopGui, "EggShopFrame", 2, "PlayerGui.EggShopGui") else nil

	if settingsButton and settingsButton:IsA("GuiButton") and settingsFrame and settingsFrame:IsA("Frame") then
		registerPanel(settingsButton, settingsFrame)
	end
	if inventoryButton and inventoryButton:IsA("GuiButton") and inventoryFrame and inventoryFrame:IsA("Frame") then
		registerPanel(inventoryButton, inventoryFrame)
	end
	if eggShopButton and eggShopButton:IsA("GuiButton") and eggShopFrame and eggShopFrame:IsA("Frame") then
		registerPanel(eggShopButton, eggShopFrame)
	end
end

UIManager.transitionFrame = transitionFrame
UIManager.applyButtonFeedback = applyButtonFeedback

return UIManager :: UIManagerModule