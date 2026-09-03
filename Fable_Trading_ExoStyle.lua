--[[
    FABLE // Trading
    Exo-style Trading UI built from the supplied Exo UI design patterns.
    Trading only. Garden Ascension is intentionally not included.

    Verified game-facing structures supplied in this project:
      TradeEvents.SendRequest:FireServer(player)
      TradeEvents.RespondRequest:FireServer(requestId, true/false)
      TradeEvents.Accept:FireServer()
      TradeEvents.Confirm:FireServer()
      TradeEvents.Decline:FireServer()
      TradeEvents.AddItem:FireServer("Pet", uuid)
      GameEvents.Favorite_Item:FireServer(tool)
      GameEvents.PetGiftingService:FireServer("GivePet", player)

    Verified pet data:
      DataService:GetData().PetsData.PetInventory.Data[uuid]
      pet.PetType
      pet.PetData.Level
      pet.PetData.BaseWeight
      pet.PetData.MutationType
      pet.PetData.IsFavorite
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local TradeEvents = GameEvents:WaitForChild("TradeEvents")

local DataService = require(ReplicatedStorage.Modules:WaitForChild("DataService"))
local TradingController = require(ReplicatedStorage.Modules.TradeControllers:WaitForChild("TradingController"))
local TradeData = require(ReplicatedStorage.Data:WaitForChild("TradeData"))
local InventoryEnums = require(ReplicatedStorage.Data.EnumRegistry:WaitForChild("InventoryServiceEnums"))

local PetRegistry
pcall(function()
    PetRegistry = require(ReplicatedStorage.Data.PetRegistry)
end)

local SendRequest = TradeEvents:WaitForChild("SendRequest")
local RespondRequest = TradeEvents:WaitForChild("RespondRequest")
local AddItem = TradeEvents:WaitForChild("AddItem")
local AcceptRemote = TradeEvents:WaitForChild("Accept")
local ConfirmRemote = TradeEvents:WaitForChild("Confirm")
local DeclineRemote = TradeEvents:WaitForChild("Decline")
local FavoriteRemote = GameEvents:FindFirstChild("Favorite_Item")
local GiftRemote = GameEvents:FindFirstChild("PetGiftingService")

local Config = {
    AutoSendTicket = false,
    AutoAcceptRequest = true,
    AutoAcceptTrade = true,
    AutoConfirmTrade = true,
    AutoUnfavorite = true,
    SkipLocked = true,
    GiftSystem = false,
    MinLevel = 0,
    MaxLevel = 100,
    MinWeight = 0,
    MaxWeight = math.huge,
    SelectedPets = {},
    SelectedMutations = {},
    SelectedRarities = {},
}

local Stats = {
    Sent = 0,
    Requests = 0,
    Accepts = 0,
    Confirms = 0,
    Added = 0,
    Unfavorited = 0,
    Failed = 0,
}

local Running = true
local LastSend = 0
local SendCooldown = 4
local LastAction = "Ready"

-- =========================================================
-- THEME / EXO-LIKE STRUCTURE
-- =========================================================

local Theme = {
    Background = Color3.fromRGB(15, 15, 15),
    Main = Color3.fromRGB(25, 25, 25),
    Surface = Color3.fromRGB(20, 20, 22),
    Content = Color3.fromRGB(17, 17, 19),
    Outline = Color3.fromRGB(40, 40, 40),
    Accent = Color3.fromRGB(125, 85, 255),
    AccentSoft = Color3.fromRGB(50, 37, 76),
    Text = Color3.fromRGB(245, 245, 245),
    Muted = Color3.fromRGB(135, 135, 145),
    Green = Color3.fromRGB(90, 225, 140),
    Red = Color3.fromRGB(255, 75, 90),
    Yellow = Color3.fromRGB(245, 205, 90),
    Font = Enum.Font.Code,
}

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = obj
    return c
end

local function stroke(obj, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Outline
    s.Transparency = transparency or 0
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end

local function label(parent, text, size, color, height)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextColor3 = color or Theme.Text
    l.Font = Theme.Font
    l.TextSize = size or 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Size = UDim2.new(1, 0, 0, height or 20)
    l.Parent = parent
    return l
end

local old = (gethui and gethui():FindFirstChild("Fable_Trading")) or CoreGui:FindFirstChild("Fable_Trading")
if old then old:Destroy() end

local Gui = Instance.new("ScreenGui")
Gui.Name = "Fable_Trading"
Gui.IgnoreGuiInset = true
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = (gethui and gethui()) or CoreGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(700, 470)
Main.Position = UDim2.new(0.5, -350, 0.5, -235)
Main.BackgroundColor3 = Theme.Background
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui
corner(Main, 6)
stroke(Main, Theme.Outline, 0, 1)

-- top and divider lines like Exo
local TopLine = Instance.new("Frame")
TopLine.Size = UDim2.new(1, 0, 0, 1)
TopLine.Position = UDim2.fromOffset(0, 48)
TopLine.BorderSizePixel = 0
TopLine.BackgroundColor3 = Theme.Outline
TopLine.Parent = Main

local SideLine = Instance.new("Frame")
SideLine.Size = UDim2.new(0, 1, 1, -69)
SideLine.Position = UDim2.new(0.30, 0, 0, 49)
SideLine.BorderSizePixel = 0
SideLine.BackgroundColor3 = Theme.Outline
SideLine.Parent = Main

local FooterLine = Instance.new("Frame")
FooterLine.Size = UDim2.new(1, 0, 0, 1)
FooterLine.Position = UDim2.new(0, 0, 1, -21)
FooterLine.BorderSizePixel = 0
FooterLine.BackgroundColor3 = Theme.Outline
FooterLine.Parent = Main

-- =========================================================
-- HEADER
-- =========================================================

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 48)
TopBar.BackgroundTransparency = 1
TopBar.Parent = Main

local TitleHolder = Instance.new("Frame")
TitleHolder.Size = UDim2.new(0.30, 0, 1, 0)
TitleHolder.BackgroundTransparency = 1
TitleHolder.Parent = TopBar

local Title = label(TitleHolder, "FABLE", 20, Theme.Text, 48)
Title.Size = UDim2.new(1, -20, 1, 0)
Title.Position = UDim2.fromOffset(10, 0)
Title.TextXAlignment = Enum.TextXAlignment.Center

local Search = Instance.new("TextBox")
Search.Size = UDim2.new(0.35, 0, 0, 28)
Search.Position = UDim2.new(0.48, 0, 0.5, -14)
Search.BackgroundColor3 = Theme.Main
Search.BorderSizePixel = 0
Search.PlaceholderText = "Search settings..."
Search.PlaceholderColor3 = Theme.Muted
Search.TextColor3 = Theme.Text
Search.Font = Theme.Font
Search.TextSize = 13
Search.ClearTextOnFocus = false
Search.Parent = TopBar
corner(Search, 6)
stroke(Search, Theme.Outline, 0.15)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 10)
searchPad.Parent = Search

local Minimize = Instance.new("TextButton")
Minimize.Size = UDim2.fromOffset(30, 28)
Minimize.Position = UDim2.new(1, -68, 0, 10)
Minimize.BackgroundColor3 = Theme.Main
Minimize.Text = "—"
Minimize.TextColor3 = Theme.Text
Minimize.Font = Theme.Font
Minimize.TextSize = 18
Minimize.Parent = TopBar
corner(Minimize, 6)
stroke(Minimize, Theme.Outline, 0.1)

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(30, 28)
Close.Position = UDim2.new(1, -34, 0, 10)
Close.BackgroundColor3 = Color3.fromRGB(34, 20, 23)
Close.Text = "×"
Close.TextColor3 = Theme.Red
Close.Font = Theme.Font
Close.TextSize = 18
Close.Parent = TopBar
corner(Close, 6)
stroke(Close, Color3.fromRGB(65, 30, 35), 0.05)

-- =========================================================
-- SIDEBAR + CONTENT
-- =========================================================

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Size = UDim2.new(0.30, 0, 1, -69)
Sidebar.Position = UDim2.fromOffset(0, 49)
Sidebar.BackgroundColor3 = Theme.Background
Sidebar.BorderSizePixel = 0
Sidebar.ScrollBarThickness = 0
Sidebar.CanvasSize = UDim2.fromScale(0, 0)
Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
Sidebar.Parent = Main

local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 8)
sidePad.PaddingLeft = UDim.new(0, 6)
sidePad.PaddingRight = UDim.new(0, 6)
sidePad.Parent = Sidebar
local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 2)
sideList.Parent = Sidebar

local Content = Instance.new("Frame")
Content.Size = UDim2.new(0.70, -1, 1, -69)
Content.Position = UDim2.new(0.30, 1, 0, 49)
Content.BackgroundColor3 = Color3.fromRGB(16, 16, 17)
Content.BorderSizePixel = 0
Content.Parent = Main

local pageHolder = Instance.new("Frame")
pageHolder.Size = UDim2.new(1, 0, 1, 0)
pageHolder.BackgroundTransparency = 1
pageHolder.Parent = Content

local pages = {}
local tabButtons = {}

local function createPage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = name
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = Theme.Accent
    p.CanvasSize = UDim2.fromScale(0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = pageHolder

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 12)
    pad.Parent = p

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 7)
    list.Parent = p

    pages[name] = p
    return p
end

local function createTab(name, icon)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 40)
    b.BackgroundColor3 = Theme.Background
    b.BackgroundTransparency = 1
    b.Text = ""
    b.AutoButtonColor = false
    b.Parent = Sidebar
    corner(b, 4)

    local iconLabel = label(b, icon or "□", 14, Theme.Accent, 40)
    iconLabel.Size = UDim2.fromOffset(24, 40)
    iconLabel.Position = UDim2.fromOffset(7, 0)
    iconLabel.TextXAlignment = Enum.TextXAlignment.Center

    local txt = label(b, name, 14, Theme.Text, 40)
    txt.Position = UDim2.fromOffset(33, 0)
    txt.Size = UDim2.new(1, -40, 1, 0)
    txt.TextTransparency = 0.5

    b.Activated:Connect(function()
        for n, page in pairs(pages) do
            page.Visible = n == name
        end
        for n, btn in pairs(tabButtons) do
            local active = n == name
            btn.BackgroundTransparency = active and 0 or 1
            btn.BackgroundColor3 = active and Theme.AccentSoft or Theme.Background
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("TextLabel") then
                    child.TextTransparency = active and 0 or 0.5
                end
            end
        end
    end)

    tabButtons[name] = b
    return b
end

local TradePage = createPage("Trading")
local PetPage = createPage("Pet Filters")
local StatsPage = createPage("Stats")
createTab("Trading", "◇")
createTab("Pet Filters", "◆")
createTab("Stats", "▣")

local function showTab(name)
    pages[name].Visible = true
    for n, btn in pairs(tabButtons) do
        local active = n == name
        btn.BackgroundTransparency = active and 0 or 1
        btn.BackgroundColor3 = active and Theme.AccentSoft or Theme.Background
        for _, child in ipairs(btn:GetChildren()) do
            if child:IsA("TextLabel") then
                child.TextTransparency = active and 0 or 0.5
            end
        end
    end
end

local function groupbox(parent, titleText, description, icon)
    local box = Instance.new("Frame")
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.Size = UDim2.new(1, 0, 0, 0)
    box.BackgroundColor3 = Color3.fromRGB(12, 12, 13)
    box.BorderSizePixel = 0
    box.Parent = parent
    corner(box, 8)
    stroke(box, Color3.fromRGB(47, 47, 49), 0.05)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundTransparency = 1
    header.Parent = box

    local ic = label(header, icon or "□", 14, Theme.Accent, 32)
    ic.Size = UDim2.fromOffset(28, 32)
    ic.Position = UDim2.fromOffset(9, 5)
    ic.TextXAlignment = Enum.TextXAlignment.Center

    local title = label(header, titleText, 14, Theme.Text, 20)
    title.Position = UDim2.fromOffset(41, 5)
    title.Size = UDim2.new(1, -50, 0, 20)

    if description and description ~= "" then
        local desc = label(header, description, 10, Theme.Muted, 16)
        desc.Position = UDim2.fromOffset(41, 23)
        desc.Size = UDim2.new(1, -50, 0, 16)
    end

    local inner = Instance.new("Frame")
    inner.AutomaticSize = Enum.AutomaticSize.Y
    inner.Size = UDim2.new(1, 0, 0, 0)
    inner.BackgroundColor3 = Color3.fromRGB(11, 11, 12)
    inner.BorderSizePixel = 0
    inner.Parent = box
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = inner
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.Parent = inner

    return inner
end

local function addButton(parent, text, callback, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = color or Color3.fromRGB(25, 25, 28)
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = Theme.Text
    b.Font = Theme.Font
    b.TextSize = 12
    b.AutoButtonColor = false
    b.Parent = parent
    corner(b, 6)
    stroke(b, Theme.Outline, 0.15)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = (color or Color3.fromRGB(25, 25, 28)):Lerp(Theme.Accent, 0.12)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = color or Color3.fromRGB(25, 25, 28)}):Play()
    end)
    if callback then b.Activated:Connect(callback) end
    return b
end

local function addToggle(parent, text, default, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = Theme.Main
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = parent
    corner(row, 6)
    stroke(row, Theme.Outline, 0.2)

    local name = label(row, text, 12, Theme.Text, 34)
    name.Position = UDim2.fromOffset(10, 0)
    name.Size = UDim2.new(1, -80, 1, 0)

    local pill = Instance.new("Frame")
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, -9, 0.5, 0)
    pill.Size = UDim2.fromOffset(48, 22)
    pill.BackgroundColor3 = Theme.Outline
    pill.BorderSizePixel = 0
    pill.Parent = row
    corner(pill, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 11, 0.5, 0)
    knob.BackgroundColor3 = Theme.Muted
    knob.BorderSizePixel = 0
    knob.Parent = pill
    corner(knob, 9)

    local state = default == true
    local function render()
        TweenService:Create(pill, TweenInfo.new(0.12), {BackgroundColor3 = state and Theme.Accent or Theme.Outline}):Play()
        TweenService:Create(knob, TweenInfo.new(0.12), {
            Position = UDim2.new(0, state and 37 or 11, 0.5, 0),
            BackgroundColor3 = state and Theme.Text or Theme.Muted,
        }):Play()
    end
    render()

    row.Activated:Connect(function()
        state = not state
        render()
        if callback then callback(state) end
    end)

    return row, function() return state end, function(v)
        state = v == true
        render()
        if callback then callback(state) end
    end
end

local function addInput(parent, caption, default, numeric)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 50)
    holder.BackgroundTransparency = 1
    holder.Parent = parent

    local cap = label(holder, caption, 11, Theme.Muted, 16)
    cap.Position = UDim2.fromOffset(0, 0)

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 30)
    box.Position = UDim2.fromOffset(0, 18)
    box.BackgroundColor3 = Theme.Main
    box.BorderSizePixel = 0
    box.Text = tostring(default or "")
    box.PlaceholderText = caption
    box.PlaceholderColor3 = Theme.Muted
    box.TextColor3 = Theme.Text
    box.Font = Theme.Font
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.Parent = holder
    corner(box, 6)
    stroke(box, Theme.Outline, 0.12)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 9)
    pad.Parent = box

    if numeric then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            if box.Text == "" then return end
            local filtered = box.Text:gsub("[^%d%.%-]", "")
            if filtered ~= box.Text then box.Text = filtered end
        end)
    end

    return box
end

-- =========================================================
-- TRADING PAGE
-- =========================================================

local targetBox = groupbox(TradePage, "Target Player", "Send requests to a selected player", "◇")
local TargetInput = addInput(targetBox, "Username", "", false)
local targetStatus = label(targetBox, "Target: NONE", 10, Theme.Muted, 18)
addButton(targetBox, "FIND / REFRESH TARGET", function()
    local query = string.lower((TargetInput.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    local found
    if query ~= "" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local n = string.lower(player.Name)
                local d = string.lower(player.DisplayName)
                if n == query or d == query or string.find(n, query, 1, true) then
                    found = player
                    break
                end
            end
        end
    end
    if found then
        TargetInput.Text = found.Name
        targetStatus.Text = "Target: @" .. found.Name
        targetStatus.TextColor3 = Theme.Green
        LastAction = "Target selected"
    else
        targetStatus.Text = "Target: NOT FOUND"
        targetStatus.TextColor3 = Theme.Red
        LastAction = "Target not found"
    end
end)

local automation = groupbox(TradePage, "Automation", "Verified trade state machine", "◆")
local _, getAutoReq = addToggle(automation, "Auto Accept Requests", Config.AutoAcceptRequest, function(v) Config.AutoAcceptRequest = v end)
local _, getAutoAccept = addToggle(automation, "Auto Accept Trade", Config.AutoAcceptTrade, function(v) Config.AutoAcceptTrade = v end)
local _, getAutoConfirm = addToggle(automation, "Auto Confirm Trade", Config.AutoConfirmTrade, function(v) Config.AutoConfirmTrade = v end)
local _, getAutoSend = addToggle(automation, "Auto Send Trading Ticket", Config.AutoSendTicket, function(v) Config.AutoSendTicket = v end)
local _, getAutoUnfav = addToggle(automation, "Auto Unfavorite Matching Pets", Config.AutoUnfavorite, function(v) Config.AutoUnfavorite = v end)
local _, getSkip = addToggle(automation, "Skip Locked / Favorite Pets", Config.SkipLocked, function(v) Config.SkipLocked = v end)

local actions = groupbox(TradePage, "Actions", "Manual controls", "□")
addButton(actions, "SEND TRADE REQUEST", function()
    local target
    local q = string.lower((TargetInput.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (string.lower(player.Name) == q or string.lower(player.DisplayName) == q) then
            target = player
            break
        end
    end
    if target then
        local ok = pcall(function() SendRequest:FireServer(target) end)
        if ok then Stats.Sent += 1; LastAction = "Request sent" else Stats.Failed += 1; LastAction = "Request failed" end
    else
        Stats.Failed += 1
        LastAction = "Target not found"
    end
end, Color3.fromRGB(36, 30, 52))
addButton(actions, "ACCEPT CURRENT REQUEST", function()
    LastAction = "Waiting for incoming request event"
end)
addButton(actions, "CONFIRM CURRENT TRADE", function()
    if TradingController.CurrentTradeReplicator then
        local ok = pcall(function() ConfirmRemote:FireServer() end)
        if ok then Stats.Confirms += 1; LastAction = "Confirm sent" else Stats.Failed += 1; LastAction = "Confirm failed" end
    else
        LastAction = "No active trade"
    end
end, Color3.fromRGB(36, 30, 52))

local live = groupbox(TradePage, "Live Status", "Current session", "▣")
local LiveText = label(live, "Trade: IDLE\nTarget: NONE\nTicket: CHECKING", 11, Theme.Muted, 50)
LiveText.TextWrapped = true

-- =========================================================
-- PET FILTER PAGE
-- =========================================================

local petSelect = groupbox(PetPage, "Pet Selection", "Only matching pets are offered", "◆")
local PetFilter = addInput(petSelect, "Pet names (comma separated, blank = all)", "", false)

local mutationSelect = groupbox(PetPage, "Mutation / Rarity", "Matches live PetData.MutationType and PetList rarity", "◇")
local MutationFilter = addInput(mutationSelect, "Mutations (comma separated, blank = all)", "", false)
local RarityFilter = addInput(mutationSelect, "Rarities (comma separated, blank = all)", "", false)

local range = groupbox(PetPage, "Level / Weight", "Safe numeric ranges", "▣")
local MinLevel = addInput(range, "Min Level", 0, true)
local MaxLevel = addInput(range, "Max Level", 100, true)
local MinWeight = addInput(range, "Min BaseWeight", 0, true)
local MaxWeight = addInput(range, "Max BaseWeight", 999999, true)

local filterInfo = label(PetPage, "", 10, Theme.Muted, 36)
filterInfo.TextWrapped = true
filterInfo.TextYAlignment = Enum.TextYAlignment.Center

local function splitSet(text)
    local result = {}
    for part in string.gmatch(text or "", "[^,]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then result[part] = true end
    end
    return result
end

local function refreshFilters()
    Config.SelectedPets = splitSet(PetFilter.Text)
    Config.SelectedMutations = splitSet(MutationFilter.Text)
    Config.SelectedRarities = splitSet(RarityFilter.Text)
    Config.MinLevel = math.max(0, tonumber(MinLevel.Text) or 0)
    Config.MaxLevel = math.max(Config.MinLevel, tonumber(MaxLevel.Text) or 100)
    Config.MinWeight = math.max(0, tonumber(MinWeight.Text) or 0)
    Config.MaxWeight = math.max(Config.MinWeight, tonumber(MaxWeight.Text) or math.huge)
end
for _, field in ipairs({PetFilter, MutationFilter, RarityFilter, MinLevel, MaxLevel, MinWeight, MaxWeight}) do
    field.FocusLost:Connect(refreshFilters)
end

-- =========================================================
-- STATS PAGE
-- =========================================================

local statBox = groupbox(StatsPage, "Trade Stats", "Session counters", "▣")
local StatsText = label(statBox, "", 12, Theme.Text, 98)
StatsText.TextWrapped = true
StatsText.TextYAlignment = Enum.TextYAlignment.Center

local activityBox = groupbox(StatsPage, "Activity", "Latest state", "□")
local ActivityText = label(activityBox, "", 11, Theme.Muted, 74)
ActivityText.TextWrapped = true
ActivityText.TextYAlignment = Enum.TextYAlignment.Top

addButton(StatsPage, "RESET SESSION STATS", function()
    for key in pairs(Stats) do Stats[key] = 0 end
    LastAction = "Stats reset"
end)

showTab("Trading")

-- =========================================================
-- DRAG / MINIMIZE / CLOSE
-- =========================================================

local dragging = false
local dragStart
local startPos
local dragInput

TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local minimized = false
Minimize.Activated:Connect(function()
    minimized = not minimized
    local targetSize = minimized and UDim2.fromOffset(700, 48) or UDim2.fromOffset(700, 470)
    for _, child in ipairs({Sidebar, Content, FooterLine, SideLine, Search}) do
        child.Visible = not minimized
    end
    TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = targetSize}):Play()
    Minimize.Text = minimized and "+" or "—"
end)

Close.Activated:Connect(function()
    Running = false
    Gui:Destroy()
end)

-- =========================================================
-- DATA / HELPERS
-- =========================================================

local function getData()
    local ok, data = pcall(function() return DataService:GetData() end)
    return ok and data or nil
end

local function getInventory()
    local data = getData()
    return data and data.PetsData and data.PetsData.PetInventory and data.PetsData.PetInventory.Data or {}
end

local function getRarity(petType)
    local entry = PetRegistry and PetRegistry.PetList and PetRegistry.PetList[petType]
    return entry and (entry.Rarity or entry.RarityName) or nil
end

local function setLookupFromComma(text)
    local out = {}
    for part in string.gmatch(string.lower(text or ""), "[^,]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then out[part] = true end
    end
    return out
end

local function matchesPet(uuid, pet)
    local pd = pet and pet.PetData
    if not pd then return false end

    local level = tonumber(pd.Level) or 0
    local weight = tonumber(pd.BaseWeight) or 0
    local mutation = tostring(pd.MutationType or "")
    local rarity = tostring(getRarity(pet.PetType) or "")

    if level < Config.MinLevel or level > Config.MaxLevel then return false end
    if weight < Config.MinWeight or weight > Config.MaxWeight then return false end

    if next(Config.SelectedPets) then
        local wanted = Config.SelectedPets[pet.PetType] or Config.SelectedPets[string.lower(pet.PetType or "")]
        if not wanted then
            local lower = string.lower(pet.PetType or "")
            for name in pairs(Config.SelectedPets) do
                if string.lower(name) == lower then wanted = true break end
            end
        end
        if not wanted then return false end
    end

    if next(Config.SelectedMutations) then
        local ok = Config.SelectedMutations[mutation] or Config.SelectedMutations[string.lower(mutation)]
        if not ok then
            local lower = string.lower(mutation)
            for name in pairs(Config.SelectedMutations) do
                if string.lower(name) == lower then ok = true break end
            end
        end
        if not ok then return false end
    end

    if next(Config.SelectedRarities) then
        local ok = Config.SelectedRarities[rarity] or Config.SelectedRarities[string.lower(rarity)]
        if not ok then
            local lower = string.lower(rarity)
            for name in pairs(Config.SelectedRarities) do
                if string.lower(name) == lower then ok = true break end
            end
        end
        if not ok then return false end
    end

    if Config.SkipLocked and not Config.AutoUnfavorite and pd.IsFavorite == true then
        return false
    end

    if Config.SkipLocked and pet.tradeLock and pet.tradeLock.Type == "Permanent" then
        return false
    end

    return true
end

local function findTarget()
    local q = string.lower((TargetInput.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if q == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local n, d = string.lower(p.Name), string.lower(p.DisplayName)
            if n == q or d == q or string.find(n, q, 1, true) then return p end
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

local function equipTicket(ticket)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not ticket or not humanoid then return false end
    if ticket.Parent ~= character then
        local ok = pcall(function() humanoid:EquipTool(ticket) end)
        if not ok then return false end
        task.wait(0.12)
    end
    return ticket.Parent == character
end

local function findToolByUUID(uuid)
    for _, container in ipairs({LocalPlayer.Character, LocalPlayer.Backpack}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local id = tool:GetAttribute("PET_UUID") or tool:GetAttribute(InventoryEnums.ITEM_UUID)
                    if id == uuid then return tool end
                end
            end
        end
    end
end

local function unfavorite(uuid)
    if not FavoriteRemote then return false end
    local tool = findToolByUUID(uuid)
    if not tool then return false end
    if tool:GetAttribute(InventoryEnums.Favorite) ~= true then return false end
    local ok = pcall(function() FavoriteRemote:FireServer(tool) end)
    if ok then
        Stats.Unfavorited += 1
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
    if not myIndex then return end
    local offer = trade.offers[myIndex]
    local existing = {}
    for _, item in pairs(offer.items or {}) do existing[item.id] = true end

    local limit = tonumber(TradeData.ItemLimit) or 6
    local count = 0
    for _ in pairs(existing) do count += 1 end

    for uuid, pet in pairs(getInventory()) do
        if count >= limit then break end
        if not existing[uuid] and matchesPet(uuid, pet) then
            local pd = pet.PetData or {}
            if Config.AutoUnfavorite and pd.IsFavorite == true then
                unfavorite(uuid)
                task.wait(0.05)
            end
            local ok = pcall(function() AddItem:FireServer("Pet", uuid) end)
            if ok then
                Stats.Added += 1
                count += 1
                existing[uuid] = true
                task.wait(0.07)
            else
                Stats.Failed += 1
            end
        end
    end
end

local function sendTicket()
    local now = os.clock()
    if now - LastSend < SendCooldown then return end
    if TradingController.CurrentTradeReplicator then return end
    local target = findTarget()
    if not target then
        LastAction = "Target not found"
        return
    end
    local ticket = findTicket()
    if not ticket then
        LastAction = "Trading Ticket not found"
        return
    end
    if not equipTicket(ticket) then
        LastAction = "Could not equip ticket"
        return
    end
    LastSend = now
    local ok = pcall(function() SendRequest:FireServer(target) end)
    if ok then
        Stats.Sent += 1
        LastAction = "Request sent to @" .. target.Name
    else
        Stats.Failed += 1
        LastAction = "Request failed"
    end
end

-- Incoming request automation. The game's client callback provides request id and sender.
TradeEvents.SendRequest.OnClientEvent:Connect(function(requestId, sender)
    if not Running then return end
    if not Config.AutoAcceptRequest then return end
    if typeof(sender) ~= "Instance" or not sender:IsA("Player") then return end
    local ok = pcall(function() RespondRequest:FireServer(requestId, true) end)
    if ok then
        Stats.Requests += 1
        LastAction = "Accepted request from @" .. sender.Name
    else
        Stats.Failed += 1
        LastAction = "Request accept failed"
    end
end)

-- =========================================================
-- STATE MACHINE
-- =========================================================

local lastTradeId
local lastAcceptAt = 0
local lastConfirmAt = 0
local lastAddAt = 0

local function processTrade()
    local rep = TradingController.CurrentTradeReplicator
    if not rep then return end
    local trade = rep:GetData()
    if not trade then return end

    local myIndex = table.find(trade.players, LocalPlayer)
    if not myIndex then return end
    local otherIndex = myIndex == 1 and 2 or 1
    local myState = trade.states[myIndex]
    local otherState = trade.states[otherIndex]
    local elapsed = workspace:GetServerTimeNow() - (trade.lastChange or 0)
    local cooldown = tonumber(TradeData.ButtonCooldown) or 5

    if lastTradeId ~= TradingController.CurrentTradeId then
        lastTradeId = TradingController.CurrentTradeId
        lastAcceptAt = 0
        lastConfirmAt = 0
        lastAddAt = 0
    end

    if Config.AutoUnfavorite and os.clock() - lastAddAt > 0.4 then
        local hasRoom = trade.offers[myIndex] and #trade.offers[myIndex].items < (tonumber(TradeData.ItemLimit) or 6)
        if hasRoom then
            addMatchingPets()
            lastAddAt = os.clock()
        end
    end

    if Config.AutoAcceptTrade and myState == "None" and elapsed >= cooldown then
        if os.clock() - lastAcceptAt > 0.7 then
            local ok = pcall(function() AcceptRemote:FireServer() end)
            lastAcceptAt = os.clock()
            if ok then
                Stats.Accepts += 1
                LastAction = "Accept sent"
            else
                Stats.Failed += 1
                LastAction = "Accept failed"
            end
        end
    end

    if Config.AutoConfirmTrade and myState == "Accepted" and (otherState == "Accepted" or otherState == "Confirmed") and elapsed >= cooldown then
        if os.clock() - lastConfirmAt > 0.7 then
            local ok = pcall(function() ConfirmRemote:FireServer() end)
            lastConfirmAt = os.clock()
            if ok then
                Stats.Confirms += 1
                LastAction = "Confirm sent"
            else
                Stats.Failed += 1
                LastAction = "Confirm failed"
            end
        end
    end
end

-- =========================================================
-- LIVE UI LOOP
-- =========================================================

task.spawn(function()
    while Running do
        refreshFilters()

        local target = findTarget()
        local ticket = findTicket()
        local rep = TradingController.CurrentTradeReplicator
        local targetName = target and ("@" .. target.Name) or "NONE"
        local ticketState = ticket and "FOUND" or "MISSING"
        local tradeState = rep and "ACTIVE" or "IDLE"

        LiveText.Text = string.format("Trade: %s\nTarget: %s\nTicket: %s\nAction: %s", tradeState, targetName, ticketState, LastAction)
        LiveText.TextColor3 = rep and Theme.Green or Theme.Muted

        StatsText.Text = string.format(
            "Tickets sent       %d\nRequests accepted   %d\nTrades accepted     %d\nTrades confirmed    %d\nPets added          %d\nUnfavorited         %d\nFailures            %d",
            Stats.Sent, Stats.Requests, Stats.Accepts, Stats.Confirms, Stats.Added, Stats.Unfavorited, Stats.Failed
        )

        ActivityText.Text = string.format(
            "Last action: %s\nTarget: %s\nTrade: %s\nFilter range: Lvl %d-%d  •  %.2f-%.2fkg",
            LastAction, targetName, tradeState, Config.MinLevel, Config.MaxLevel, Config.MinWeight, Config.MaxWeight
        )

        local matched = 0
        for uuid, pet in pairs(getInventory()) do
            if matchesPet(uuid, pet) then matched += 1 end
        end
        filterInfo.Text = string.format("Matching inventory: %d pets", matched)

        pcall(processTrade)

        if Config.AutoSendTicket then
            pcall(sendTicket)
        end

        task.wait(0.18)
    end
end)

_G.FableTrading = {
    Config = Config,
    Stats = Stats,
    SendRequest = function(player)
        if player and player:IsA("Player") then
            return SendRequest:FireServer(player)
        end
    end,
    Accept = function() return AcceptRemote:FireServer() end,
    Confirm = function() return ConfirmRemote:FireServer() end,
    Decline = function() return DeclineRemote:FireServer() end,
    Gift = function(player)
        if GiftRemote and player and player:IsA("Player") then
            return GiftRemote:FireServer("GivePet", player)
        end
    end,
}

print("[FABLE] Exo-style Trading UI loaded")
