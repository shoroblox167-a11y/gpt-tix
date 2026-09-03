-- FABLE // Trading Compact
-- Compact Exo-inspired trading UI with the verified trading backend.
-- Trading only. Garden Ascension is intentionally not included.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local TradeEvents = GameEvents:WaitForChild("TradeEvents")

local DataService = require(Modules:WaitForChild("DataService"))
local TradingController = require(Modules.TradeControllers:WaitForChild("TradingController"))
local TradeData = require(ReplicatedStorage.Data:WaitForChild("TradeData"))
local InvEnums = require(ReplicatedStorage.Data.EnumRegistry:WaitForChild("InventoryServiceEnums"))

local PetRegistry
pcall(function()
    PetRegistry = require(ReplicatedStorage.Data.PetRegistry)
end)

local SendRequest = TradeEvents:WaitForChild("SendRequest")
local RespondRequest = TradeEvents:WaitForChild("RespondRequest")
local AddItem = TradeEvents:WaitForChild("AddItem")
local AcceptRemote = TradeEvents:WaitForChild("Accept")
local ConfirmRemote = TradeEvents:WaitForChild("Confirm")
local FavoriteRemote = GameEvents:FindFirstChild("Favorite_Item")

local Config = {
    AutoSendTicket = false,
    AutoAcceptRequest = true,
    AutoAcceptTrade = true,
    AutoConfirmTrade = true,
    AutoUnfavorite = true,
    SkipFavorites = true,
    MinLevel = 0,
    MaxLevel = 100,
    MinWeight = 0,
    MaxWeight = math.huge,
    Pets = {},
    Mutations = {},
    Rarities = {},
}

local Stats = {
    Sent = 0,
    Requests = 0,
    Accepted = 0,
    Confirmed = 0,
    Added = 0,
    Unfav = 0,
    Failed = 0,
}

local Running = true
local lastRequest = 0
local lastReplicator
local requestCooldown = 4

local Theme = {
    Background = Color3.fromRGB(14, 14, 17),
    Panel = Color3.fromRGB(19, 19, 23),
    Surface = Color3.fromRGB(25, 24, 30),
    Surface2 = Color3.fromRGB(30, 29, 36),
    Accent = Color3.fromRGB(132, 87, 255),
    AccentDark = Color3.fromRGB(57, 39, 82),
    Text = Color3.fromRGB(238, 236, 245),
    Muted = Color3.fromRGB(132, 128, 146),
    Success = Color3.fromRGB(92, 226, 148),
    Danger = Color3.fromRGB(255, 92, 112),
    Border = Color3.fromRGB(47, 45, 54),
    Font = Enum.Font.Code,
}

local function getRoot()
    if type(gethui) == "function" then
        local ok, root = pcall(gethui)
        if ok and root then return root end
    end
    return CoreGui
end

local Root = getRoot()
local old = Root:FindFirstChild("Fable_Trading_Compact")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "Fable_Trading_Compact"
Gui.IgnoreGuiInset = true
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = Root

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Active = true
Main.Size = UDim2.fromOffset(448, 314)
Main.Position = UDim2.new(0.5, -224, 0.5, -157)
Main.BackgroundColor3 = Theme.Background
Main.BorderSizePixel = 0
Main.Parent = Gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 7)
mainCorner.Parent = Main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Theme.Border
mainStroke.Thickness = 1
mainStroke.Parent = Main

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Theme.Panel
Header.BorderSizePixel = 0
Header.Parent = Main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 3)
title.Size = UDim2.new(0, 110, 1, -5)
title.Text = "FABLE"
title.TextColor3 = Theme.Text
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = Header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(65, 21)
subtitle.Size = UDim2.new(0, 140, 0, 14)
subtitle.Text = "TRADING"
subtitle.TextColor3 = Theme.Muted
subtitle.Font = Theme.Font
subtitle.TextSize = 8
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(28, 26)
Minimize.Position = UDim2.new(1, -62, 0, 8)
Minimize.BackgroundColor3 = Theme.Surface
Minimize.Text = "—"
Minimize.TextColor3 = Theme.Text
Minimize.Font = Enum.Font.GothamBold
Minimize.TextSize = 15
Minimize.AutoButtonColor = false
Minimize.Parent = Header
Instance.new("UICorner", Minimize).CornerRadius = UDim.new(0, 6)

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(28, 26)
Close.Position = UDim2.new(1, -32, 0, 8)
Close.BackgroundColor3 = Color3.fromRGB(48, 28, 35)
Close.Text = "×"
Close.TextColor3 = Theme.Danger
Close.Font = Enum.Font.GothamBold
Close.TextSize = 16
Close.AutoButtonColor = false
Close.Parent = Header
Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 6)

local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(1, 0, 0, 1)
Divider.Position = UDim2.fromOffset(0, 42)
Divider.BackgroundColor3 = Theme.Border
Divider.BorderSizePixel = 0
Divider.Parent = Main

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 92, 1, -63)
Sidebar.Position = UDim2.fromOffset(0, 43)
Sidebar.BackgroundColor3 = Theme.Background
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main

local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 7)
sidePad.PaddingLeft = UDim.new(0, 6)
sidePad.PaddingRight = UDim.new(0, 6)
sidePad.Parent = Sidebar

local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 3)
sideList.Parent = Sidebar

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -93, 1, -63)
Content.Position = UDim2.fromOffset(93, 43)
Content.BackgroundColor3 = Theme.Background
Content.BorderSizePixel = 0
Content.Parent = Main

local Pages = {}
local TabButtons = {}

local function makePage(name)
    local page = Instance.new("Frame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = Content
    Pages[name] = page
    return page
end

local TradePage = makePage("Trade")
local FilterPage = makePage("Filters")
local StatsPage = makePage("Stats")

local function makeTab(name, icon)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = Theme.Background
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Text = icon .. "  " .. name
    b.TextColor3 = Theme.Muted
    b.Font = Theme.Font
    b.TextSize = 10
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.AutoButtonColor = false
    b.Parent = Sidebar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    TabButtons[name] = b
    return b
end

local TradeTab = makeTab("Trade", "◇")
local FilterTab = makeTab("Filters", "◆")
local StatsTab = makeTab("Stats", "▣")

local function showPage(name)
    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end
    for tabName, button in pairs(TabButtons) do
        local active = tabName == name
        button.BackgroundTransparency = active and 0 or 1
        button.BackgroundColor3 = active and Theme.AccentDark or Theme.Background
        button.TextColor3 = active and Theme.Text or Theme.Muted
    end
end

TradeTab.Activated:Connect(function() showPage("Trade") end)
FilterTab.Activated:Connect(function() showPage("Filters") end)
StatsTab.Activated:Connect(function() showPage("Stats") end)

local function makeGroup(parent, y, titleText, height)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, -12, 0, height)
    box.Position = UDim2.fromOffset(6, y)
    box.BackgroundColor3 = Theme.Panel
    box.BorderSizePixel = 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
    local s = Instance.new("UIStroke", box)
    s.Color = Theme.Border
    s.Transparency = 0.15
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, 20)
    l.Position = UDim2.fromOffset(8, 4)
    l.BackgroundTransparency = 1
    l.Text = titleText
    l.TextColor3 = Theme.Text
    l.Font = Theme.Font
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = box
    return box
end

local function makeInput(parent, x, y, w, placeholder, value)
    local b = Instance.new("TextBox")
    b.Size = UDim2.fromOffset(w, 28)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = Theme.Surface
    b.BorderSizePixel = 0
    b.Text = value or ""
    b.PlaceholderText = placeholder
    b.PlaceholderColor3 = Theme.Muted
    b.TextColor3 = Theme.Text
    b.Font = Theme.Font
    b.TextSize = 10
    b.ClearTextOnFocus = false
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local s = Instance.new("UIStroke", b)
    s.Color = Theme.Border
    s.Transparency = 0.1
    local p = Instance.new("UIPadding", b)
    p.PaddingLeft = UDim.new(0, 7)
    return b
end

local function makeButton(parent, x, y, w, h, text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = Theme.Surface2
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Theme.Text
    b.Font = Theme.Font
    b.TextSize = 10
    b.AutoButtonColor = false
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local s = Instance.new("UIStroke", b)
    s.Color = Theme.Border
    s.Transparency = 0.1
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.08), {BackgroundColor3 = Theme.AccentDark}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.08), {BackgroundColor3 = Theme.Surface2}):Play()
    end)
    return b
end

local function makeToggle(parent, x, y, w, text, default, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.fromOffset(w, 29)
    row.Position = UDim2.fromOffset(x, y)
    row.BackgroundColor3 = Theme.Surface
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Position = UDim2.fromOffset(8, 0)
    name.Size = UDim2.new(1, -60, 1, 0)
    name.Text = text
    name.TextColor3 = Theme.Text
    name.Font = Theme.Font
    name.TextSize = 9
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = row
    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(38, 18)
    pill.Position = UDim2.new(1, -46, 0.5, -9)
    pill.BackgroundColor3 = Theme.Border
    pill.BorderSizePixel = 0
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(14, 14)
    dot.BackgroundColor3 = Theme.Muted
    dot.BorderSizePixel = 0
    dot.Parent = pill
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    local state = default == true
    local function draw()
        pill.BackgroundColor3 = state and Theme.Accent or Theme.Border
        dot.Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.fromOffset(3, 2)
        dot.BackgroundColor3 = state and Theme.Text or Theme.Muted
    end
    row.Activated:Connect(function()
        state = not state
        draw()
        if callback then callback(state) end
    end)
    draw()
    return function() return state end
end

local function makeStat(parent, x, y, titleText, valueText)
    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(128, 54)
    box.Position = UDim2.fromOffset(x, y)
    box.BackgroundColor3 = Theme.Panel
    box.BorderSizePixel = 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local s = Instance.new("UIStroke", box)
    s.Color = Theme.Border
    local a = Instance.new("TextLabel")
    a.Size = UDim2.new(1, -12, 0, 15)
    a.Position = UDim2.fromOffset(6, 5)
    a.BackgroundTransparency = 1
    a.Text = titleText
    a.TextColor3 = Theme.Muted
    a.Font = Theme.Font
    a.TextSize = 8
    a.TextXAlignment = Enum.TextXAlignment.Left
    a.Parent = box
    local v = Instance.new("TextLabel")
    v.Size = UDim2.new(1, -12, 0, 25)
    v.Position = UDim2.fromOffset(6, 20)
    v.BackgroundTransparency = 1
    v.Text = tostring(valueText)
    v.TextColor3 = Theme.Text
    v.Font = Enum.Font.GothamBold
    v.TextSize = 14
    v.TextXAlignment = Enum.TextXAlignment.Left
    v.Parent = box
    return v
end

-- Trade page
local TargetBox = makeGroup(TradePage, 6, "TARGET PLAYER", 85)
local Target = makeInput(TargetBox, 8, 27, 180, "username")
local FindButton = makeButton(TargetBox, 193, 27, 83, 28, "FIND")
local TargetStatus = makeStat(TargetBox, 8, 57, "STATUS", "NONE")
TargetStatus.Size = UDim2.new(1, -16, 0, 17)
TargetStatus.Position = UDim2.fromOffset(8, 58)
TargetStatus.Font = Theme.Font
TargetStatus.TextSize = 8
TargetStatus.TextColor3 = Theme.Muted

local ActionBox = makeGroup(TradePage, 97, "TRADE ACTIONS", 156)
local getAutoSend = makeToggle(ActionBox, 8, 27, 129, "Auto Send Ticket", false)
local getAutoReq = makeToggle(ActionBox, 143, 27, 129, "Auto Accept Request", true)
local getAutoAccept = makeToggle(ActionBox, 8, 59, 129, "Auto Accept Trade", true)
local getAutoConfirm = makeToggle(ActionBox, 143, 59, 129, "Auto Confirm Trade", true)
local getAutoUnfav = makeToggle(ActionBox, 8, 91, 129, "Auto Unfavorite", true)
local getSkipFav = makeToggle(ActionBox, 143, 91, 129, "Skip Favorites", true)
local SendNow = makeButton(ActionBox, 8, 123, 264, 26, "SEND TRADE REQUEST")

local TradeStatus = Instance.new("TextLabel")
TradeStatus.Size = UDim2.new(1, -16, 0, 18)
TradeStatus.Position = UDim2.fromOffset(8, 255)
TradeStatus.BackgroundTransparency = 1
TradeStatus.Text = "● READY"
TradeStatus.TextColor3 = Theme.Success
TradeStatus.Font = Theme.Font
TradeStatus.TextSize = 9
TradeStatus.TextXAlignment = Enum.TextXAlignment.Left
TradeStatus.Parent = TradePage

-- Filter page
local FilterBox = makeGroup(FilterPage, 6, "PET FILTERS", 210)
local PetNames = makeInput(FilterBox, 8, 27, 264, "Pets (comma separated)")
local MutNames = makeInput(FilterBox, 8, 61, 264, "Mutations (comma separated)")
local RarityNames = makeInput(FilterBox, 8, 95, 264, "Rarities (comma separated)")
local MinLevel = makeInput(FilterBox, 8, 129, 83, "Min level", "0")
local MaxLevel = makeInput(FilterBox, 97, 129, 83, "Max level", "100")
local MinWeight = makeInput(FilterBox, 186, 129, 86, "Min weight", "0")
local MaxWeight = makeInput(FilterBox, 8, 163, 264, "Max weight", "999999")
local FilterHint = Instance.new("TextLabel")
FilterHint.Size = UDim2.new(1, -16, 0, 27)
FilterHint.Position = UDim2.fromOffset(8, 195)
FilterHint.BackgroundTransparency = 1
FilterHint.Text = "Examples: Peacock, Giant Ant   •   Rainbow, EV"
FilterHint.TextColor3 = Theme.Muted
FilterHint.Font = Theme.Font
FilterHint.TextSize = 8
FilterHint.TextXAlignment = Enum.TextXAlignment.Left
FilterHint.Parent = FilterBox

local Options = makeGroup(FilterPage, 222, "OPTIONS", 90)
local getSkipFilter = makeToggle(Options, 8, 27, 129, "Skip Favorites", true)
local getUnfavFilter = makeToggle(Options, 143, 27, 129, "Auto Unfavorite", true)
local Apply = makeButton(Options, 8, 59, 264, 24, "APPLY FILTERS")

-- Stats page
local StatsPageBox = makeGroup(StatsPage, 6, "SESSION", 153)
local vSent = makeStat(StatsPageBox, 8, 29, "SENT", 0)
local vReq = makeStat(StatsPageBox, 143, 29, "REQUESTS", 0)
local vAcc = makeStat(StatsPageBox, 8, 89, "ACCEPTED", 0)
local vConf = makeStat(StatsPageBox, 143, 89, "CONFIRMED", 0)
local vAdd = makeStat(StatsPage, 6, 165, "PETS ADDED", 0)
local vUnfav = makeStat(StatsPage, 142, 165, "UNFAVORITED", 0)
local vFail = makeStat(StatsPage, 278, 165, "FAILED", 0)
local Info = makeGroup(StatsPage, 228, "LIVE", 67)
local LiveText = Instance.new("TextLabel")
LiveText.Size = UDim2.new(1, -16, 1, -26)
LiveText.Position = UDim2.fromOffset(8, 25)
LiveText.BackgroundTransparency = 1
LiveText.Text = "Target: NONE\nTrade: IDLE"
LiveText.TextColor3 = Theme.Muted
LiveText.Font = Theme.Font
LiveText.TextSize = 8
LiveText.TextXAlignment = Enum.TextXAlignment.Left
LiveText.TextYAlignment = Enum.TextYAlignment.Top
LiveText.Parent = Info

-- drag
local dragging = false
local dragStart
local startPos
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local delta = input.Position - dragStart
    Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end)

local minimized = false
Minimize.Activated:Connect(function()
    minimized = not minimized
    Sidebar.Visible = not minimized
    Content.Visible = not minimized
    Divider.Visible = not minimized
    Main.Size = minimized and UDim2.fromOffset(448, 42) or UDim2.fromOffset(448, 314)
    Minimize.Text = minimized and "+" or "—"
end)

Close.Activated:Connect(function()
    Running = false
    Gui:Destroy()
end)

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function csvSet(text)
    local result = {}
    for part in string.gmatch(text or "", "[^,]+") do
        local value = trim(part)
        if value ~= "" then result[string.lower(value)] = true end
    end
    return result
end

local function refreshConfig()
    Config.AutoSendTicket = getAutoSend()
    Config.AutoAcceptRequest = getAutoReq()
    Config.AutoAcceptTrade = getAutoAccept()
    Config.AutoConfirmTrade = getAutoConfirm()
    Config.AutoUnfavorite = getAutoUnfav() and getUnfavFilter()
    Config.SkipFavorites = getSkipFav() or getSkipFilter()
    Config.Pets = csvSet(PetNames.Text)
    Config.Mutations = csvSet(MutNames.Text)
    Config.Rarities = csvSet(RarityNames.Text)
    Config.MinLevel = math.max(0, tonumber(MinLevel.Text) or 0)
    Config.MaxLevel = math.max(Config.MinLevel, tonumber(MaxLevel.Text) or 100)
    Config.MinWeight = math.max(0, tonumber(MinWeight.Text) or 0)
    Config.MaxWeight = math.max(Config.MinWeight, tonumber(MaxWeight.Text) or math.huge)
end

local function getData()
    local ok, result = pcall(function()
        return DataService:GetData()
    end)
    return ok and result or nil
end

local function getPetInventory()
    local data = getData()
    return data and data.PetsData and data.PetsData.PetInventory and data.PetsData.PetInventory.Data or {}
end

local function getRarity(petType)
    local entry = PetRegistry and PetRegistry.PetList and PetRegistry.PetList[petType]
    return entry and entry.Rarity or nil
end

local function selectedMatch(set, value)
    if not next(set) then return true end
    return set[string.lower(tostring(value or ""))] == true
end

local function matchesPet(pet)
    local pd = pet and pet.PetData
    if not pd then return false end
    local level = tonumber(pd.Level) or 0
    local weight = tonumber(pd.BaseWeight) or 0
    if level < Config.MinLevel or level > Config.MaxLevel then return false end
    if weight < Config.MinWeight or weight > Config.MaxWeight then return false end
    if not selectedMatch(Config.Pets, pet.PetType) then return false end
    if not selectedMatch(Config.Mutations, pd.MutationType) then return false end
    if not selectedMatch(Config.Rarities, getRarity(pet.PetType)) then return false end
    if Config.SkipFavorites and not Config.AutoUnfavorite and pd.IsFavorite == true then return false end
    return true
end

local function findTarget()
    local q = string.lower(trim(Target.Text or ""))
    if q == "" then return nil end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local name = string.lower(player.Name)
            local display = string.lower(player.DisplayName)
            if name == q or display == q or string.find(name, q, 1, true) or string.find(display, q, 1, true) then
                return player
            end
        end
    end
end

local function findTicket()
    local function scan(container)
        if not container then return nil end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Tool") then
                local n = string.lower(obj.Name)
                if string.find(n, "trading ticket", 1, true) or string.find(n, "trade ticket", 1, true) then
                    return obj
                end
            end
        end
    end
    return scan(LocalPlayer.Character) or scan(LocalPlayer.Backpack)
end

local function setStatus(text, good)
    TradeStatus.Text = "● " .. text
    TradeStatus.TextColor3 = good and Theme.Success or Theme.Danger
end

local function sendRequest()
    if TradingController.CurrentTradeReplicator then return false end
    if os.clock() - lastRequest < requestCooldown then return false end
    local target = findTarget()
    if not target then
        setStatus("TARGET NOT FOUND", false)
        return false
    end
    local ticket = findTicket()
    if not ticket then
        setStatus("TRADING TICKET NOT FOUND", false)
        return false
    end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and ticket.Parent ~= character then
        local ok = pcall(function() humanoid:EquipTool(ticket) end)
        if not ok then
            setStatus("COULD NOT EQUIP TICKET", false)
            return false
        end
        task.wait(0.12)
    end
    lastRequest = os.clock()
    local ok = pcall(function()
        SendRequest:FireServer(target)
    end)
    if ok then
        Stats.Sent += 1
        setStatus("REQUEST SENT", true)
        return true
    end
    Stats.Failed += 1
    setStatus("REQUEST FAILED", false)
    return false
end

local function findToolByUUID(uuid)
    local function scan(container)
        if not container then return nil end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local id = tool:GetAttribute(InvEnums.ITEM_UUID) or tool:GetAttribute("PET_UUID")
                if id == uuid then return tool end
            end
        end
    end
    return scan(LocalPlayer.Character) or scan(LocalPlayer.Backpack)
end

local function unfavorite(uuid)
    if not FavoriteRemote then return false end
    local tool = findToolByUUID(uuid)
    if not tool then return false end
    if tool:GetAttribute(InvEnums.Favorite) ~= true then return false end
    local ok = pcall(function() FavoriteRemote:FireServer(tool) end)
    if ok then
        Stats.Unfav += 1
        return true
    end
    Stats.Failed += 1
    return false
end

local function addMatchingPets()
    local rep = TradingController.CurrentTradeReplicator
    if not rep then return end
    local trade = rep:GetData()
    if not trade then return end
    local myIndex = table.find(trade.players, LocalPlayer)
    if not myIndex or not trade.offers or not trade.offers[myIndex] then return end
    local items = trade.offers[myIndex].items or {}
    local existing = {}
    for _, item in pairs(items) do existing[item.id] = true end
    local limit = tonumber(TradeData.ItemLimit) or 12
    local count = #items
    if count >= limit then return end
    for uuid, pet in pairs(getPetInventory()) do
        if count >= limit then break end
        if not existing[uuid] and matchesPet(pet) then
            if Config.AutoUnfavorite and pet.PetData and pet.PetData.IsFavorite == true then
                unfavorite(uuid)
                task.wait(0.10)
            end
            if getPetInventory()[uuid] then
                local ok = pcall(function() AddItem:FireServer("Pet", uuid) end)
                if ok then
                    existing[uuid] = true
                    count += 1
                    Stats.Added += 1
                else
                    Stats.Failed += 1
                end
            end
        end
    end
end

RespondRequest.OnClientEvent:Connect(function(sender)
    if not getAutoReq() then return end
    if typeof(sender) ~= "Instance" or not sender:IsA("Player") then return end
    local ok = pcall(function() RespondRequest:FireServer(sender, true) end)
    if ok then
        Stats.Requests += 1
        setStatus("ACCEPTED REQUEST", true)
    else
        Stats.Failed += 1
        setStatus("REQUEST ACCEPT FAILED", false)
    end
end)

local function processTrade()
    local rep = TradingController.CurrentTradeReplicator
    if not rep then
        lastReplicator = nil
        return
    end
    local trade = rep:GetData()
    if not trade or not trade.players or not trade.states then return end
    if lastReplicator ~= rep then
        lastReplicator = rep
        setStatus("TRADE OPENED", true)
    end
    local myIndex = table.find(trade.players, LocalPlayer)
    if not myIndex then return end
    local otherIndex = myIndex == 1 and 2 or 1
    local myState = trade.states[myIndex]
    local otherState = trade.states[otherIndex]
    local elapsed = workspace:GetServerTimeNow() - (tonumber(trade.lastChange) or 0)
    local cooldown = tonumber(TradeData.ButtonCooldown) or 5

    if myState == "None" then
        addMatchingPets()
        if getAutoAccept() and otherState ~= "None" and elapsed >= cooldown then
            local ok = pcall(function() AcceptRemote:FireServer() end)
            if ok then Stats.Accepted += 1 else Stats.Failed += 1 end
        end
    elseif myState == "Processing" then
        setStatus("PROCESSING", true)
    elseif myState == "Accepted" then
        if getAutoConfirm() and otherState == "Accepted" and elapsed >= cooldown then
            local ok = pcall(function() ConfirmRemote:FireServer() end)
            if ok then Stats.Confirmed += 1; setStatus("CONFIRMED", true) else Stats.Failed += 1 end
        elseif getAutoConfirm() and otherState == "Confirmed" and elapsed >= cooldown then
            pcall(function() ConfirmRemote:FireServer() end)
            setStatus("CONFIRMING", true)
        else
            setStatus("WAITING FOR OTHER PLAYER", true)
        end
    elseif myState == "Confirmed" then
        setStatus(otherState == "Confirmed" and "TRADE COMPLETE" or "WAITING FOR CONFIRM", true)
    end
end

FindButton.Activated:Connect(function()
    local target = findTarget()
    if target then
        Target.Text = target.Name
        TargetStatus.Text = "@" .. target.Name
        TargetStatus.TextColor3 = Theme.Success
        setStatus("TARGET READY", true)
    else
        TargetStatus.Text = "NOT FOUND"
        TargetStatus.TextColor3 = Theme.Danger
        setStatus("TARGET NOT FOUND", false)
    end
end)

SendNow.Activated:Connect(function()
    refreshConfig()
    sendRequest()
end)

Apply.Activated:Connect(function()
    refreshConfig()
    setStatus("FILTERS APPLIED", true)
end)

Target.FocusLost:Connect(function()
    local target = findTarget()
    if target then
        TargetStatus.Text = "@" .. target.Name
        TargetStatus.TextColor3 = Theme.Success
    end
end)

showPage("Trade")

-- live status and stats
local function countMatches()
    local n = 0
    for _, pet in pairs(getPetInventory()) do
        if matchesPet(pet) then n += 1 end
    end
    return n
end

task.spawn(function()
    while Running and Gui.Parent do
        refreshConfig()
        local target = findTarget()
        local active = TradingController.CurrentTradeReplicator ~= nil
        local ticket = findTicket()
        vSent.Text = tostring(Stats.Sent)
        vReq.Text = tostring(Stats.Requests)
        vAcc.Text = tostring(Stats.Accepted)
        vConf.Text = tostring(Stats.Confirmed)
        vAdd.Text = tostring(Stats.Added)
        vUnfav.Text = tostring(Stats.Unfav)
        vFail.Text = tostring(Stats.Failed)
        LiveText.Text = string.format(
            "Target: %s\nTrade: %s\nTicket: %s\nMatching pets: %d",
            target and ("@" .. target.Name) or "NONE",
            active and "ACTIVE" or "IDLE",
            ticket and "FOUND" or "NONE",
            countMatches()
        )
        task.wait(0.5)
    end
end)

task.spawn(function()
    while Running and Gui.Parent do
        refreshConfig()
        if Config.AutoSendTicket then pcall(sendRequest) end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while Running and Gui.Parent do
        refreshConfig()
        pcall(processTrade)
        task.wait(0.15)
    end
end)

print("[FABLE] Compact Trading UI loaded")
