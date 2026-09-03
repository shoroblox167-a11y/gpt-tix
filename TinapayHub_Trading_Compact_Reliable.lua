-- TinapayHub Trading UI
-- Compact, movable, minimizable trading scaffold.
-- Auto actions are OFF by default.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local TradeEvents = GameEvents:WaitForChild("TradeEvents")
local TradingController = require(ReplicatedStorage.Modules.TradeControllers.TradingController)

local old = PlayerGui:FindFirstChild("TinapayHub_Trading")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TinapayHub_Trading"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(390, 290)
main.Position = UDim2.new(0.5, -195, 0.5, -145)
main.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(67, 74, 96)
stroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 0, 38)
title.Position = UDim2.fromOffset(14, 2)
title.BackgroundTransparency = 1
title.Text = "TinapayHub  •  Trading"
title.TextColor3 = Color3.fromRGB(240, 242, 250)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(32, 28)
minimize.Position = UDim2.new(1, -40, 0, 7)
minimize.BackgroundColor3 = Color3.fromRGB(34, 38, 51)
minimize.Text = "—"
minimize.TextColor3 = Color3.fromRGB(230, 232, 240)
minimize.Font = Enum.Font.GothamBold
minimize.TextSize = 15
minimize.Parent = main
Instance.new("UICorner", minimize).CornerRadius = UDim.new(0, 8)

local tabs = Instance.new("Frame")
tabs.Size = UDim2.new(1, -20, 0, 34)
tabs.Position = UDim2.fromOffset(10, 42)
tabs.BackgroundTransparency = 1
tabs.Parent = main
local tabLayout = Instance.new("UIListLayout", tabs)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 7)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -20, 1, -88)
content.Position = UDim2.fromOffset(10, 82)
content.BackgroundTransparency = 1
content.Parent = main

local pages = {}
for _, name in ipairs({"Automation", "Trading", "Settings"}) do
    local p = Instance.new("Frame")
    p.Name = name
    p.Size = UDim2.fromScale(1, 1)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = content
    pages[name] = p
end

local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(112, 32)
    b.BackgroundColor3 = Color3.fromRGB(34, 38, 51)
    b.Text = name
    b.TextColor3 = Color3.fromRGB(205, 210, 225)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.Parent = tabs
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local tabAutomation = makeTab("Automation")
local tabTrading = makeTab("Trading")
local tabSettings = makeTab("Settings")

local function addToggle(parent, y, text, default)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.Position = UDim2.fromOffset(0, y)
    b.BackgroundColor3 = Color3.fromRGB(29, 33, 44)
    b.TextColor3 = Color3.fromRGB(195, 199, 214)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local state = default
    local function render()
        b.Text = (state and "  ON   " or "  OFF  ") .. text
        b.TextColor3 = state and Color3.fromRGB(108, 240, 125) or Color3.fromRGB(195, 199, 214)
    end
    b.Activated:Connect(function()
        state = not state
        render()
    end)
    render()
    return b, function() return state end
end

local autoSendButton, getAutoSend = addToggle(pages.Automation, 0, "Auto Send Ticket", false)
local autoAcceptRequestButton, getAutoAcceptRequest = addToggle(pages.Automation, 42, "Auto Accept Request", false)
local autoAcceptButton, getAutoAccept = addToggle(pages.Automation, 84, "Auto Accept Trade", false)
local autoConfirmButton, getAutoConfirm = addToggle(pages.Automation, 126, "Auto Confirm Trade", false)
local autoUnfavButton, getAutoUnfav = addToggle(pages.Automation, 168, "Auto Unfavorite", false)

local targetBox = Instance.new("TextBox")
targetBox.Size = UDim2.new(1, 0, 0, 34)
targetBox.Position = UDim2.fromOffset(0, 0)
targetBox.BackgroundColor3 = Color3.fromRGB(29, 33, 44)
targetBox.PlaceholderText = "Target username"
targetBox.Text = ""
targetBox.TextColor3 = Color3.fromRGB(235, 237, 245)
targetBox.PlaceholderColor3 = Color3.fromRGB(120, 126, 143)
targetBox.Font = Enum.Font.Gotham
targetBox.TextSize = 12
targetBox.ClearTextOnFocus = false
targetBox.Parent = pages.Trading
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 90)
status.Position = UDim2.fromOffset(0, 46)
status.BackgroundTransparency = 1
status.Text = "Status: Ready"
status.TextColor3 = Color3.fromRGB(145, 151, 170)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = pages.Trading

local settingsText = Instance.new("TextLabel")
settingsText.Size = UDim2.new(1, 0, 1, 0)
settingsText.BackgroundTransparency = 1
settingsText.Text = "Trading settings\n\nTargeted automation uses the game's trade events.\nAll automation starts OFF."
settingsText.TextColor3 = Color3.fromRGB(180, 185, 202)
settingsText.Font = Enum.Font.Gotham
settingsText.TextSize = 11
settingsText.TextXAlignment = Enum.TextXAlignment.Left
settingsText.TextYAlignment = Enum.TextYAlignment.Top
settingsText.Parent = pages.Settings

local function showPage(name)
    for k, p in pairs(pages) do p.Visible = (k == name) end
    tabAutomation.BackgroundColor3 = name == "Automation" and Color3.fromRGB(60, 130, 255) or Color3.fromRGB(34, 38, 51)
    tabTrading.BackgroundColor3 = name == "Trading" and Color3.fromRGB(60, 130, 255) or Color3.fromRGB(34, 38, 51)
    tabSettings.BackgroundColor3 = name == "Settings" and Color3.fromRGB(60, 130, 255) or Color3.fromRGB(34, 38, 51)
end

tabAutomation.Activated:Connect(function() showPage("Automation") end)
tabTrading.Activated:Connect(function() showPage("Trading") end)
tabSettings.Activated:Connect(function() showPage("Settings") end)
showPage("Automation")

-- draggable window
local dragging = false
local dragStart
local startPosition
local dragInput
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
main.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)

local minimized = false
minimize.Activated:Connect(function()
    minimized = not minimized
    tabs.Visible = not minimized
    content.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(390, 46) or UDim2.fromOffset(390, 290)
    minimize.Text = minimized and "+" or "—"
end)

-- verified game-facing helpers from the provided decompiles
local function sendTradeRequest(player)
    if player and player:IsA("Player") then
        TradeEvents.SendRequest:FireServer(player)
        status.Text = "Status: Request sent to @" .. player.Name
    end
end

local function respondTradeRequest(requestId, accepted)
    TradeEvents.RespondRequest:FireServer(requestId, accepted)
end

local function acceptCurrentTrade()
    TradeEvents.Accept:FireServer()
end

local function confirmCurrentTrade()
    TradeEvents.Confirm:FireServer()
end

local function declineCurrentTrade()
    TradeEvents.Decline:FireServer()
end

_G.TinapayHubTrading = {
    SendRequest = sendTradeRequest,
    RespondRequest = respondTradeRequest,
    Accept = acceptCurrentTrade,
    Confirm = confirmCurrentTrade,
    Decline = declineCurrentTrade,
    Controller = TradingController,
}

print("[TinapayHub] Trading UI loaded")
