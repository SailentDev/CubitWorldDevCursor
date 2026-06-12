--!strict
local UIManager = {}

-- Services
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Types
export type UIManagerModule = {
    OnInit: () -> (),
    transitionFrame: (frame: Frame, targetPosition: UDim2, show: boolean) -> (),
    applyButtonFeedback: (button: GuiButton) -> ()
}

type PanelInfo = {
    frame: Frame,
    originalPosition: UDim2,
    button: GuiButton,
    isOpen: boolean
}

type TweenTracker = {
    tween: Tween,
    connection: RBXScriptConnection
}

-- Private Variables
local localPlayer = Players.LocalPlayer :: Player
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local activeTrackers: { [Frame]: TweenTracker } = {}
local registeredPanels: { [Frame]: PanelInfo } = {}

-- Animation Constants
local SLIDE_TIME_IN = 0.25
local SLIDE_TIME_OUT = 0.25
local SCALE_TIME = 0.15

local TWEEN_INFO_IN = TweenInfo.new(SLIDE_TIME_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_INFO_OUT = TweenInfo.new(SLIDE_TIME_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_INFO_SCALE = TweenInfo.new(SCALE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

--[=[
    Slides a frame from below the screen up to its designated position, or back down.
    Disconnects active completed-event listeners prior to cancellation to prevent 
    race conditions during rapid interactions.
]=]
local function transitionFrame(frame: Frame, targetPosition: UDim2, show: boolean): ()
    -- Disconnect the completed listener first so cancelling does not fire frame visibility overrides
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
            activeTrackers[frame] = nil
        end)

        activeTrackers[frame] = {
            tween = tween,
            connection = connection
        }

        tween:Play()
    else
        local offscreenPosition = UDim2.new(targetPosition.X.Scale, targetPosition.X.Offset, 1.5, 0)
        local tween = TweenService:Create(frame, TWEEN_INFO_OUT, { Position = offscreenPosition })
        local connection: RBXScriptConnection
        
        connection = tween.Completed:Connect(function()
            connection:Disconnect()
            frame.Visible = false
            activeTrackers[frame] = nil
        end)

        activeTrackers[frame] = {
            tween = tween,
            connection = connection
        }

        tween:Play()
    end
end

--[=[
    Applies unified micro-interaction feedback (hover scale-up & click squash) 
    to target GuiButtons to keep interface behavior consistent.
]=]
local function applyButtonFeedback(button: GuiButton): ()
    local originalSize = button.Size
    
    local hoverSize = UDim2.new(
        originalSize.X.Scale * 1.08, originalSize.X.Offset,
        originalSize.Y.Scale * 1.08, originalSize.Y.Offset
    )
    local clickSize = UDim2.new(
        originalSize.X.Scale * 0.92, originalSize.X.Offset,
        originalSize.Y.Scale * 0.92, originalSize.Y.Offset
    )

    local tweenHover = TweenService:Create(button, TWEEN_INFO_SCALE, { Size = hoverSize })
    local tweenReset = TweenService:Create(button, TWEEN_INFO_SCALE, { Size = originalSize })
    local tweenClick = TweenService:Create(button, TweenInfo.new(0.05), { Size = clickSize })

    button.MouseEnter:Connect(function()
        tweenHover:Play()
    end)

    button.MouseLeave:Connect(function()
        tweenReset:Play()
    end)

    button.MouseButton1Down:Connect(function()
        tweenClick:Play()
    end)

    button.MouseButton1Up:Connect(function()
        tweenHover:Play()
    end)
end

--[=[
    Toggles the targeted frame. Closes any other registered active panels 
    prior to performing the transition.
]=]
local function togglePanel(targetFrame: Frame): ()
    -- Global Transition Lock: If any panel is currently animating, ignore the input entirely
    if next(activeTrackers) ~= nil then
        return
    end

    local info = registeredPanels[targetFrame]
    if not info then return end

    if info.isOpen then
        info.isOpen = false
        transitionFrame(targetFrame, info.originalPosition, false)
    else
        -- Scan and transition away any other open panel
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

--[=[
    Registers a panel to the global layout configuration pool.
]=]
local function registerPanel(button: GuiButton, frame: Frame): ()
    local originalPosition = frame.Position
    frame.Visible = false

    registeredPanels[frame] = {
        frame = frame,
        originalPosition = originalPosition,
        button = button,
        isOpen = false
    }

    -- Standardized to 'Activated' for instant, responsive input detection across all devices
    button.Activated:Connect(function()
        togglePanel(frame)
    end)
end

--[=[
    Initializes references, retrieves target frames/buttons based on PlayerGui structure,
    and applies automated setup behaviors.
]=]
function UIManager.OnInit(): ()
    -- Pobieranie głównego HUDu i kontenera przycisków
    local mainHUD = playerGui:WaitForChild("MainHUD") :: ScreenGui
    local buttonsFrame = mainHUD:WaitForChild("Buttons") :: Frame
    
    -- Referencje do przycisków
    local settingsButton = buttonsFrame:WaitForChild("SettingsButton") :: ImageButton
    local inventoryButton = buttonsFrame:WaitForChild("InventoryButton") :: ImageButton
    local eggShopButton = buttonsFrame:WaitForChild("EggShopButton") :: ImageButton -- NOWOŚĆ

    -- Referencje do ramion interfejsów (Frames)
    local settingsGui = playerGui:WaitForChild("SettingsGui") :: ScreenGui
    local settingsFrame = settingsGui:WaitForChild("Settings") :: Frame

    local inventoryGui = playerGui:WaitForChild("InventoryGui") :: ScreenGui
    local inventoryFrame = inventoryGui:WaitForChild("InventoryFrame") :: Frame

    local eggShopGui = playerGui:WaitForChild("EggShopGui") :: ScreenGui -- NOWOŚĆ
    local eggShopFrame = eggShopGui:WaitForChild("EggShopFrame") :: Frame -- NOWOŚĆ

    -- Automatyczne przypisanie animacji najechania/kliknięcia (działa też na EggShopButton!)
    for _, child in buttonsFrame:GetChildren() do
        if child:IsA("GuiButton") then
            applyButtonFeedback(child)
        end
    end

    -- Centralna rejestracja paneli do systemu otwierania/zamykania
    registerPanel(settingsButton, settingsFrame)
    registerPanel(inventoryButton, inventoryFrame)
    registerPanel(eggShopButton, eggShopFrame) -- NOWOŚĆ
end

-- Bind internal functions to the returned module
UIManager.transitionFrame = transitionFrame
UIManager.applyButtonFeedback = applyButtonFeedback

return UIManager :: UIManagerModule