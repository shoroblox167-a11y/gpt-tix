-- FABLE AUTO HATCH V6
-- Final compact UI pass based on the approved Fable/Exotic-inspired design.
--
-- Verified game-facing pieces used here:
--   Egg discovery: CollectionService:GetTagged("PetEggServer")
--   READY reveal: GameEvents.EggReadyToHatch_RE (PetType, EggUUID)
--   Normal hatch: GameEvents.PetEggService:FireServer("HatchPet", egg)
--   Inventory: DataService:GetData().PetsData.PetInventory.Data
--   Existing pet weight: pet.PetData.BaseWeight
--
-- The 8-slot team editor is inventory-backed. It intentionally does not invent
-- an unverified multi-pet equip remote. Teams are stored by exact inventory UUID.
-- A verified equip implementation can later be plugged into ApplyTeam().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[FABLE] LocalPlayer unavailable")
    return
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
if not PlayerGui then
    warn("[FABLE] PlayerGui unavailable")
    return
end

local GameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
if not GameEvents then
    warn("[FABLE] GameEvents unavailable")
    return
end

local PetEggService = GameEvents:FindFirstChild("PetEggService")
local ReadyEvent = GameEvents:FindFirstChild("EggReadyToHatch_RE")

local DataService
pcall(function()
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local module = modules and modules:FindFirstChild("DataService")
    if module then
        DataService = require(module)
    end
end)

local PetRegistry
pcall(function()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local registry = data and data:FindFirstChild("PetRegistry")
    if registry then
        PetRegistry = require(registry)
    end
end)

local old = PlayerGui:FindFirstChild("FableAutoHatchV6")
if old then old:Destroy() end
local oldCore = CoreGui:FindFirstChild("FableAutoHatchV6")
if oldCore then oldCore:Destroy() end

local Parent = PlayerGui
pcall(function()
    if type(gethui) == "function" then
        local hui = gethui()
        if hui then
            Parent = hui
        end
    end
end)

local Theme = {
    Background = Color3.fromRGB(10, 10, 14),
    Header = Color3.fromRGB(15, 15, 20),
    Panel = Color3.fromRGB(18, 18, 24),
    Panel2 = Color3.fromRGB(24, 24, 31),
    Panel3 = Color3.fromRGB(30, 30, 39),
    Outline = Color3.fromRGB(58, 58, 72),
    Text = Color3.fromRGB(242, 242, 248),
    Muted = Color3.fromRGB(144, 146, 160),
    Purple = Color3.fromRGB(139, 86, 255),
    PurpleDark = Color3.fromRGB(72, 45, 112),
    Green = Color3.fromRGB(92, 226, 145),
    Red = Color3.fromRGB(238, 87, 100),
    Yellow = Color3.fromRGB(243, 196, 86),
}

local State = {
    Page = "Dashboard",
    AutoHatch = false,
    FastPlacement = false,
    BatchHatching = true,
    MarkBigPet = true,
    PauseUnknownWeight = true,
    AutoSell = false,
    EggESP = false,
    BigPetNotify = true,
    WeightThreshold = 1.30,
    HatchDelay = 0.10,
    PlacementDelay = 0.05,

    Eggs = 0,
    Ready = 0,
    Created = 0,
    Hatched = 0,
    Failed = 0,
    Sold = 0,
    Activity = 0,

    CurrentEgg = "-",
    CurrentUUID = "-",
    CurrentPet = "Unknown",
    CurrentWeight = nil,
    CurrentDecision = "Pending",
    CurrentTeam = "-",
    CurrentStatus = "Fable loaded.",

    ReadyByUUID = {},
    Processing = {},

    Inventory = {},
    InventoryRevision = 0,
    SellPetTypes = {},

    Teams = {
        Hatch = {},
        Bronto = {},
        Reduction = {},
        Sell = {},
    },

    Logs = {},
}

local TeamNames = {
    Hatch = "Hatch Team",
    Bronto = "Pet Size Team",
    Reduction = "Egg Reduction",
    Sell = "Sell Team",
}

local function S(v)
    local ok, result = pcall(tostring, v)
    return ok and result or "?"
end

local function Num(v, fallback)
    local n = tonumber(v)
    if n == nil then return fallback end
    return n
end

local function weightText(v)
    if type(v) ~= "number" then
        return "Unknown"
    end
    return string.format("%.4f KG", v)
end

local function log(message)
    message = S(message)
    State.CurrentStatus = message
    State.Activity += 1
    table.insert(State.Logs, 1, os.date("[%H:%M:%S] ") .. message)
    while #State.Logs > 16 do
        table.remove(State.Logs)
    end
    print("[FABLE] " .. message)
end

local function getData()
    if not DataService then return nil end
    local ok, data = pcall(function()
        return DataService:GetData()
    end)
    if ok and type(data) == "table" then
        return data
    end
end

local function getInventoryTable()
    local data = getData()
    local petsData = data and data.PetsData
    local inventory = petsData and petsData.PetInventory
    local stored = inventory and inventory.Data
    return type(stored) == "table" and stored or {}
end

local function iconValue(petType)
    local list = PetRegistry and PetRegistry.PetList
    local entry = type(list) == "table" and list[petType]
    if type(entry) ~= "table" then return nil end

    for _, key in ipairs({"Icon", "IconId", "Image", "ImageId", "Thumbnail", "ThumbnailId", "IconAsset"}) do
        local value = entry[key]
        if value ~= nil then
            local text = S(value)
            if text:find("rbxassetid://") or text:find("http") or tonumber(value) then
                if tonumber(value) then
                    return "rbxassetid://" .. tonumber(value)
                end
                return text
            end
        end
    end
    return nil
end

local function rebuildInventory()
    local list = {}
    for uuid, pet in pairs(getInventoryTable()) do
        if type(pet) == "table" and pet.PetType then
            local pd = type(pet.PetData) == "table" and pet.PetData or {}
            list[#list + 1] = {
                UUID = S(uuid),
                PetType = S(pet.PetType),
                Level = Num(pd.Level, 1),
                BaseWeight = Num(pd.BaseWeight, nil),
                MutationType = pd.MutationType,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.PetType == b.PetType then
            return a.UUID < b.UUID
        end
        return a.PetType < b.PetType
    end)
    State.Inventory = list
    State.InventoryRevision += 1
end

local function findInventoryPet(uuid)
    for _, pet in ipairs(State.Inventory) do
        if pet.UUID == uuid then return pet end
    end
end

local function teamHasUUID(teamName, uuid)
    for _, pet in ipairs(State.Teams[teamName]) do
        if pet.UUID == uuid then return true end
    end
    return false
end

local function addToTeam(teamName, uuid)
    local team = State.Teams[teamName]
    if not team then return false, "Unknown team." end
    if #team >= 8 then return false, "Team is already 8/8." end

    local pet = findInventoryPet(uuid)
    if not pet then return false, "That pet is no longer in inventory." end
    if teamHasUUID(teamName, uuid) then return false, "That exact pet is already selected." end

    team[#team + 1] = {
        UUID = pet.UUID,
        PetType = pet.PetType,
        Level = pet.Level,
        BaseWeight = pet.BaseWeight,
    }
    return true
end

local function removeFromTeam(teamName, index)
    local team = State.Teams[teamName]
    if team then table.remove(team, index) end
end

local function clearTeam(teamName)
    State.Teams[teamName] = {}
end

local function teamTypeSummary(teamName)
    local counts = {}
    for _, pet in ipairs(State.Teams[teamName]) do
        counts[pet.PetType] = (counts[pet.PetType] or 0) + 1
    end
    local parts = {}
    for typeName, count in pairs(counts) do
        parts[#parts + 1] = count .. "× " .. typeName
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "Empty"
end

-- Hook for a future verified multi-pet equip implementation.
-- Fable will NOT invent ActivePetService arguments here.
local function ApplyTeam(teamName)
    local team = State.Teams[teamName]
    if not team or #team == 0 then
        log(TeamNames[teamName] .. " is empty.")
        return false
    end

    for _, pet in ipairs(team) do
        if not findInventoryPet(pet.UUID) then
            log("Team contains a pet no longer in inventory: " .. pet.PetType)
            return false
        end
    end

    State.CurrentTeam = TeamNames[teamName]
    log("Selected " .. TeamNames[teamName] .. " • " .. #team .. "/8")
    return true
end

local function ownedEggs()
    local result = {}
    for _, egg in ipairs(CollectionService:GetTagged("PetEggServer")) do
        if egg:GetAttribute("OWNER") == LocalPlayer.Name then
            result[#result + 1] = egg
        end
    end
    return result
end

local function eggUUID(egg)
    local value = egg and egg:GetAttribute("OBJECT_UUID")
    return value and S(value) or nil
end

local function isReady(egg)
    local timer = egg and egg:GetAttribute("TimeToHatch")
    return typeof(timer) == "number" and timer <= 0
end

local function refreshEggCounts()
    local eggs = ownedEggs()
    State.Eggs = #eggs
    local ready = 0
    local target
    for _, egg in ipairs(eggs) do
        if isReady(egg) then
            ready += 1
            target = target or egg
        end
    end
    State.Ready = ready

    if target then
        local uuid = eggUUID(target)
        local info = uuid and State.ReadyByUUID[uuid]
        State.CurrentEgg = S(target:GetAttribute("EggName"))
        State.CurrentUUID = uuid or "-"
        if info then
            State.CurrentPet = S(info.PetType)
            State.CurrentWeight = info.BaseWeight
            State.CurrentDecision = info.Decision or "Pending"
            State.CurrentTeam = info.Team or "-"
        else
            State.CurrentPet = "Unknown"
            State.CurrentWeight = nil
            State.CurrentDecision = "Pending"
            State.CurrentTeam = "-"
        end
    else
        State.CurrentEgg = "-"
        State.CurrentUUID = "-"
        State.CurrentPet = "Unknown"
        State.CurrentWeight = nil
        State.CurrentDecision = "Pending"
        State.CurrentTeam = "-"
    end
end

-- A verified external inspector can hand Fable the exact ready weight.
-- This is deliberately opt-in instead of fabricating the RNG.
local Env = (type(getgenv) == "function" and getgenv()) or _G
Env.FableAutoHatch = Env.FableAutoHatch or {}
function Env.FableAutoHatch.SetReadyWeight(uuid, weight)
    local id = S(uuid)
    local n = tonumber(weight)
    if not n then return false end

    local info = State.ReadyByUUID[id]
    if not info then
        info = {PetType = "Unknown"}
        State.ReadyByUUID[id] = info
    end

    info.BaseWeight = n
    if State.MarkBigPet and n > State.WeightThreshold then
        info.Decision = "BRONTO"
        info.Team = "Pet Size Team"
    else
        info.Decision = "KOI"
        info.Team = "Hatch Team"
    end

    log(("Ready weight • %s • %s • %s"):format(info.PetType, weightText(n), info.Decision))
    refreshEggCounts()
    return true
end

function Env.FableAutoHatch.GetState()
    return State
end

if ReadyEvent then
    ReadyEvent.OnClientEvent:Connect(function(petType, uuidValue)
        local uuid = S(uuidValue)
        State.ReadyByUUID[uuid] = State.ReadyByUUID[uuid] or {}
        State.ReadyByUUID[uuid].PetType = S(petType)
        State.ReadyByUUID[uuid].BaseWeight = State.ReadyByUUID[uuid].BaseWeight
        State.ReadyByUUID[uuid].Decision = State.ReadyByUUID[uuid].Decision or "Pending"
        log("Egg READY • " .. S(petType))
        refreshEggCounts()
    end)
end

local function hatchEgg(egg)
    if not PetEggService then
        State.Failed += 1
        log("PetEggService unavailable.")
        return false
    end

    local uuid = eggUUID(egg)
    if not uuid or State.Processing[uuid] then return false end

    local info = State.ReadyByUUID[uuid]
    if not info then
        log("READY egg has no reveal record • paused to avoid guessing.")
        State.Failed += 1
        return false
    end

    if State.PauseUnknownWeight and State.MarkBigPet and type(info.BaseWeight) ~= "number" then
        log("READY weight unavailable • paused instead of guessing.")
        return false
    end

    local excluded = false
    -- Don't-Hatch list can be populated externally in State.DoNotHatch if needed.
    if type(State.DoNotHatch) == "table" and State.DoNotHatch[info.PetType] then
        excluded = true
    end
    if excluded then
        log("Skipped excluded pet • " .. S(info.PetType))
        return false
    end

    State.Processing[uuid] = true
    local started = os.clock()

    local ok, err = pcall(function()
        PetEggService:FireServer("HatchPet", egg)
    end)

    if not ok then
        State.Failed += 1
        State.Processing[uuid] = nil
        log("HatchPet error • " .. S(err))
        return false
    end

    State.Hatched += 1
    State.CurrentWeight = info.BaseWeight
    State.CurrentDecision = info.Decision or "Pending"
    State.CurrentTeam = info.Team or "-"
    State.Processing[uuid] = nil
    State.LastHatchTime = os.clock() - started

    log("Hatched • " .. S(info.PetType) .. " • " .. weightText(info.BaseWeight))
    return true
end

-- ============================================================
-- UI helpers
-- ============================================================

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 7)
    c.Parent = obj
    return c
end

local function outline(obj, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Outline
    s.Thickness = 1
    s.Transparency = transparency or 0.08
    s.Parent = obj
    return s
end

local function text(parent, value, size, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = value or ""
    l.TextColor3 = color or Theme.Text
    l.TextSize = size or 11
    l.Font = font or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function actionButton(parent, caption, position, size, bg)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Text = caption
    b.TextColor3 = Theme.Text
    b.TextSize = 9
    b.Font = Enum.Font.GothamSemibold
    b.BackgroundColor3 = bg or Theme.Panel2
    b.Position = position
    b.Size = size
    b.Parent = parent
    corner(b, 7)
    outline(b, Theme.Outline, 0.12)
    b.MouseEnter:Connect(function()
        b.BackgroundColor3 = (bg or Theme.Panel2):Lerp(Theme.Purple, 0.14)
    end)
    b.MouseLeave:Connect(function()
        b.BackgroundColor3 = bg or Theme.Panel2
    end)
    return b
end

local function makeToggle(parent, caption, description, getter, setter, y)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = Theme.Panel2
    row.BorderSizePixel = 0
    row.Position = UDim2.fromOffset(8, y)
    row.Size = UDim2.new(1, -16, 0, 42)
    row.Parent = parent
    corner(row, 7)

    local name = text(row, caption, 9, Theme.Text, Enum.Font.GothamSemibold)
    name.Position = UDim2.fromOffset(9, 3)
    name.Size = UDim2.new(1, -78, 0, 18)

    local desc = text(row, description or "", 7, Theme.Muted, Enum.Font.Gotham)
    desc.Position = UDim2.fromOffset(9, 20)
    desc.Size = UDim2.new(1, -78, 0, 15)

    local tr = Instance.new("TextButton")
    tr.Text = ""
    tr.AutoButtonColor = false
    tr.Size = UDim2.fromOffset(46, 22)
    tr.Position = UDim2.new(1, -55, 0.5, -11)
    tr.BorderSizePixel = 0
    tr.BackgroundColor3 = Color3.fromRGB(55, 55, 66)
    tr.Parent = row
    corner(tr, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = UDim2.fromOffset(2, 2)
    knob.BackgroundColor3 = Theme.Muted
    knob.BorderSizePixel = 0
    knob.Parent = tr
    corner(knob, 9)

    local function redraw()
        local on = getter()
        tr.BackgroundColor3 = on and Theme.Purple or Color3.fromRGB(55, 55, 66)
        knob.Position = on and UDim2.new(1, -20, 0, 2) or UDim2.fromOffset(2, 2)
        knob.BackgroundColor3 = on and Color3.new(1,1,1) or Theme.Muted
    end

    tr.Activated:Connect(function()
        setter(not getter())
        redraw()
    end)

    redraw()
    return redraw
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "FableAutoHatchV6"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
Gui.DisplayOrder = 2147483647
Gui.Parent = Parent

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(720, 455)
Main.Position = UDim2.new(0.5, -360, 0.5, -227)
Main.BackgroundColor3 = Theme.Background
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui
corner(Main, 9)
outline(Main, Theme.Outline, 0)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 54)
Header.BackgroundColor3 = Theme.Header
Header.BorderSizePixel = 0
Header.Parent = Main
corner(Header, 9)

local Logo = Instance.new("Frame")
Logo.Size = UDim2.fromOffset(40, 40)
Logo.Position = UDim2.fromOffset(10, 7)
Logo.BackgroundColor3 = Theme.Purple
Logo.BorderSizePixel = 0
Logo.Parent = Header
corner(Logo, 10)
local LogoText = text(Logo, "F", 25, Color3.new(1,1,1), Enum.Font.GothamBlack)
LogoText.Size = UDim2.fromScale(1,1)
LogoText.TextXAlignment = Enum.TextXAlignment.Center

local title = text(Header, "FABLE", 17, Theme.Text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(60, 5)
title.Size = UDim2.fromOffset(130, 22)

local subtitle = text(Header, "AUTO HATCH  •  V6", 8, Theme.Muted, Enum.Font.Code)
subtitle.Position = UDim2.fromOffset(60, 27)
subtitle.Size = UDim2.fromOffset(170, 15)

local runningText = text(Header, "IDLE", 8, Theme.Muted, Enum.Font.GothamBold)
runningText.Position = UDim2.fromOffset(205, 18)
runningText.Size = UDim2.fromOffset(65, 18)

local Search = Instance.new("TextBox")
Search.Position = UDim2.new(1, -300, 0, 10)
Search.Size = UDim2.fromOffset(165, 32)
Search.BackgroundColor3 = Theme.Panel2
Search.BorderSizePixel = 0
Search.Text = ""
Search.PlaceholderText = "Search..."
Search.PlaceholderColor3 = Theme.Muted
Search.TextColor3 = Theme.Text
Search.TextSize = 9
Search.Font = Enum.Font.Gotham
Search.ClearTextOnFocus = false
Search.Parent = Header
corner(Search, 7)
outline(Search, Theme.Outline, 0.15)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 9)
searchPad.Parent = Search

local MasterToggle = Instance.new("TextButton")
MasterToggle.Text = ""
MasterToggle.AutoButtonColor = false
MasterToggle.Size = UDim2.fromOffset(54, 24)
MasterToggle.Position = UDim2.new(1, -128, 0, 14)
MasterToggle.BackgroundColor3 = Color3.fromRGB(55,55,66)
MasterToggle.BorderSizePixel = 0
MasterToggle.Parent = Header
corner(MasterToggle, 12)
local masterKnob = Instance.new("Frame")
masterKnob.Size = UDim2.fromOffset(20,20)
masterKnob.Position = UDim2.fromOffset(2,2)
masterKnob.BackgroundColor3 = Theme.Muted
masterKnob.BorderSizePixel = 0
masterKnob.Parent = MasterToggle
corner(masterKnob,10)

local MinButton = actionButton(Header, "—", UDim2.new(1, -70, 0, 12), UDim2.fromOffset(28,30), Theme.Header)
local CloseButton = actionButton(Header, "×", UDim2.new(1, -38, 0, 10), UDim2.fromOffset(28,32), Theme.Header)
CloseButton.TextColor3 = Theme.Red

local Divider = Instance.new("Frame")
Divider.Position = UDim2.fromOffset(154, 54)
Divider.Size = UDim2.new(0, 1, 1, -54)
Divider.BackgroundColor3 = Theme.Outline
Divider.BorderSizePixel = 0
Divider.Parent = Main

local Sidebar = Instance.new("Frame")
Sidebar.Position = UDim2.fromOffset(0, 54)
Sidebar.Size = UDim2.fromOffset(154, 401)
Sidebar.BackgroundColor3 = Theme.Panel
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main
corner(Sidebar, 8)

local sideTitle = text(Sidebar, "FABLE", 9, Theme.Muted, Enum.Font.GothamBold)
sideTitle.Position = UDim2.fromOffset(12, 10)
sideTitle.Size = UDim2.new(1,-24,0,15)
local sideSub = text(Sidebar, "AUTOMATION", 7, Theme.Muted, Enum.Font.Code)
sideSub.Position = UDim2.fromOffset(12, 24)
sideSub.Size = UDim2.new(1,-24,0,12)
local sideLine = Instance.new("Frame")
sideLine.Position = UDim2.fromOffset(10, 41)
sideLine.Size = UDim2.new(1,-20,0,1)
sideLine.BackgroundColor3 = Theme.Outline
sideLine.BorderSizePixel = 0
sideLine.Parent = Sidebar

local PageNames = {"Dashboard", "Hatching", "Teams", "Pet Sell", "Egg ESP", "Settings"}
local Pages = {}
local NavButtons = {}

for _, name in ipairs(PageNames) do
    local p = Instance.new("Frame")
    p.Name = name:gsub(" ", "") .. "Page"
    p.Position = UDim2.fromOffset(164, 63)
    p.Size = UDim2.new(1,-174,1,-72)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = Main
    Pages[name] = p
end

local function activatePage(name)
    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end
    for pageName, nav in pairs(NavButtons) do
        local active = pageName == name
        nav.BackgroundTransparency = active and 0 or 1
        nav.BackgroundColor3 = active and Color3.fromRGB(39,29,51) or Theme.Panel
        nav.TextColor3 = active and Theme.Text or Theme.Muted
        local bar = nav:FindFirstChild("ActiveBar")
        if bar then bar.Visible = active end
    end
    State.Page = name
end

for i, name in ipairs(PageNames) do
    local b = Instance.new("TextButton")
    b.Name = name .. "Nav"
    b.Size = UDim2.new(1,-16,0,34)
    b.Position = UDim2.fromOffset(8, 53 + (i-1)*40)
    b.BackgroundTransparency = 1
    b.BackgroundColor3 = Theme.Panel
    b.BorderSizePixel = 0
    b.Text = name
    b.TextColor3 = Theme.Muted
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 10
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.AutoButtonColor = false
    b.Parent = Sidebar
    corner(b, 6)
    local bar = Instance.new("Frame")
    bar.Name = "ActiveBar"
    bar.Position = UDim2.fromOffset(0, 6)
    bar.Size = UDim2.fromOffset(3,22)
    bar.BackgroundColor3 = Theme.Purple
    bar.BorderSizePixel = 0
    bar.Visible = false
    bar.Parent = b
    corner(bar, 2)
    b.Activated:Connect(function() activatePage(name) end)
    NavButtons[name] = b
end

-- Floating F launcher
local Launcher = Instance.new("TextButton")
Launcher.Name = "Launcher"
Launcher.Size = UDim2.fromOffset(54,54)
Launcher.Position = UDim2.new(0, 20, 0.5, -27)
Launcher.BackgroundColor3 = Theme.Panel
Launcher.Text = "F"
Launcher.TextColor3 = Color3.fromRGB(232,220,255)
Launcher.TextSize = 24
Launcher.Font = Enum.Font.GothamBlack
Launcher.BorderSizePixel = 0
Launcher.Parent = Gui
corner(Launcher, 16)
outline(Launcher, Theme.Purple, 2)
Launcher.Activated:Connect(function()
    Main.Visible = not Main.Visible
    State.uiOpen = Main.Visible
end)

-- Dashboard
local dash = Pages.Dashboard
local stats = Instance.new("Frame")
stats.Size = UDim2.new(1,0,0,66)
stats.BackgroundTransparency = 1
stats.Parent = dash
local statValues = {}
local statDefs = {
    {"EGGS", Theme.Text},
    {"READY", Theme.Green},
    {"HATCHED", Theme.Purple},
    {"FAILED", Theme.Red},
}
for i, def in ipairs(statDefs) do
    local x = (i-1) * 100
    local box = Instance.new("Frame")
    box.Position = UDim2.fromOffset(x,0)
    box.Size = UDim2.fromOffset(94,64)
    box.BackgroundColor3 = Theme.Panel
    box.BorderSizePixel = 0
    box.Parent = stats
    corner(box,7)
    outline(box)
    local cap = text(box, def[1], 7, Theme.Muted, Enum.Font.GothamBold)
    cap.Position = UDim2.fromOffset(8,6)
    cap.Size = UDim2.new(1,-16,0,13)
    local val = text(box, "0", 17, def[2], Enum.Font.GothamBold)
    val.Position = UDim2.fromOffset(8,26)
    val.Size = UDim2.new(1,-16,0,28)
    statValues[def[1]] = val
end

local live = Instance.new("Frame")
live.Position = UDim2.fromOffset(0,76)
live.Size = UDim2.new(0.58,-5,0,140)
live.BackgroundColor3 = Theme.Panel
live.BorderSizePixel = 0
live.Parent = dash
corner(live,8)
outline(live)
local liveCap = text(live,"LIVE STATUS",9,Theme.Muted,Enum.Font.GothamBold)
liveCap.Position = UDim2.fromOffset(10,8)
liveCap.Size = UDim2.new(1,-20,0,15)
local liveState = text(live,"FABLE IS READY",12,Theme.Purple,Enum.Font.GothamBold)
liveState.Position = UDim2.fromOffset(10,30)
liveState.Size = UDim2.new(1,-20,0,20)
local live1 = text(live,"",9,Theme.Text,Enum.Font.Code)
live1.Position = UDim2.fromOffset(10,58)
live1.Size = UDim2.new(1,-20,0,18)
local live2 = text(live,"",9,Theme.Text,Enum.Font.Code)
live2.Position = UDim2.fromOffset(10,80)
live2.Size = UDim2.new(1,-20,0,18)
local live3 = text(live,"",8,Theme.Muted,Enum.Font.Code)
live3.Position = UDim2.fromOffset(10,103)
live3.Size = UDim2.new(1,-20,0,18)
local activity = text(live,"",8,Theme.Muted,Enum.Font.Code)
activity.Position = UDim2.fromOffset(10,122)
activity.Size = UDim2.new(1,-20,0,14)

local ready = Instance.new("Frame")
ready.Position = UDim2.new(0.58,2,0,76)
ready.Size = UDim2.new(0.42,-2,0,140)
ready.BackgroundColor3 = Theme.Panel
ready.BorderSizePixel = 0
ready.Parent = dash
corner(ready,8)
outline(ready)
local readyCap = text(ready,"CURRENT READY EGG",9,Theme.Muted,Enum.Font.GothamBold)
readyCap.Position = UDim2.fromOffset(10,8)
readyCap.Size = UDim2.new(1,-20,0,15)
local readyText = text(ready,"No READY egg.",8,Theme.Text,Enum.Font.Code)
readyText.Position = UDim2.fromOffset(10,31)
readyText.Size = UDim2.new(1,-20,0,99)
readyText.TextWrapped = true
readyText.TextYAlignment = Enum.TextYAlignment.Top

local logBox = Instance.new("Frame")
logBox.Position = UDim2.fromOffset(0,228)
logBox.Size = UDim2.new(1,0,0,107)
logBox.BackgroundColor3 = Theme.Panel
logBox.BorderSizePixel = 0
logBox.Parent = dash
corner(logBox,8)
outline(logBox)
local logCap = text(logBox,"ACTIVITY",9,Theme.Muted,Enum.Font.GothamBold)
logCap.Position = UDim2.fromOffset(10,7)
logCap.Size = UDim2.new(1,-20,0,15)
local logText = text(logBox,"",7,Theme.Text,Enum.Font.Code)
logText.Position = UDim2.fromOffset(10,26)
logText.Size = UDim2.new(1,-20,0,72)
logText.TextYAlignment = Enum.TextYAlignment.Top
logText.TextWrapped = true

-- Hatching page
local hp = Pages.Hatching
local hLeft = Instance.new("Frame")
hLeft.Size = UDim2.new(0.57,-5,1,0)
hLeft.BackgroundColor3 = Theme.Panel
hLeft.BorderSizePixel = 0
hLeft.Parent = hp
corner(hLeft,8)
outline(hLeft)
local hRight = Instance.new("Frame")
hRight.Position = UDim2.new(0.57,2,0,0)
hRight.Size = UDim2.new(0.43,-2,1,0)
hRight.BackgroundColor3 = Theme.Panel
hRight.BorderSizePixel = 0
hRight.Parent = hp
corner(hRight,8)
outline(hRight)
local hTitle = text(hLeft,"HATCHING",10,Theme.Text,Enum.Font.GothamBold)
hTitle.Position=UDim2.fromOffset(11,8)
hTitle.Size=UDim2.new(1,-22,0,17)
local hList = Instance.new("Frame")
hList.Position=UDim2.fromOffset(8,31)
hList.Size=UDim2.new(1,-16,1,-39)
hList.BackgroundTransparency=1
hList.Parent=hLeft
makeToggle(hList,"Auto Hatch","Run the hatch loop",function()return State.AutoHatch end,function(v)State.AutoHatch=v end,0)
makeToggle(hList,"Fast Egg Placement","Use the fast placement setting",function()return State.FastPlacement end,function(v)State.FastPlacement=v end,48)
makeToggle(hList,"Batch Hatching","Process all ready eggs in sequence",function()return State.BatchHatching end,function(v)State.BatchHatching=v end,96)
makeToggle(hList,"Mark Big Pet","Use the weight threshold",function()return State.MarkBigPet end,function(v)State.MarkBigPet=v end,144)
makeToggle(hList,"Pause If Weight Unknown","Never guess the RNG result",function()return State.PauseUnknownWeight end,function(v)State.PauseUnknownWeight=v end,192)
makeToggle(hList,"Auto Sell","Sell explicitly enabled pet types",function()return State.AutoSell end,function(v)State.AutoSell=v end,240)

local ruleTitle=text(hRight,"BIG PET RULE",10,Theme.Text,Enum.Font.GothamBold)
ruleTitle.Position=UDim2.fromOffset(11,8)
ruleTitle.Size=UDim2.new(1,-22,0,17)
local ruleCap=text(hRight,"KEEP WEIGHT ABOVE [KG]",8,Theme.Muted,Enum.Font.GothamBold)
ruleCap.Position=UDim2.fromOffset(11,34)
ruleCap.Size=UDim2.new(1,-22,0,15)
local threshold=Instance.new("TextBox")
threshold.Position=UDim2.fromOffset(11,53)
threshold.Size=UDim2.new(1,-22,0,31)
threshold.BackgroundColor3=Theme.Panel2
threshold.BorderSizePixel=0
threshold.Text="1.30"
threshold.TextColor3=Theme.Text
threshold.TextSize=10
threshold.Font=Enum.Font.Code
threshold.ClearTextOnFocus=false
threshold.Parent=hRight
corner(threshold,7)
outline(threshold)
threshold.FocusLost:Connect(function()
    local n=tonumber(threshold.Text)
    if n and n>=0 then
        State.WeightThreshold=n
        threshold.Text=string.format("%.2f",n)
        log("Weight threshold • "..threshold.Text.." KG")
    else
        threshold.Text=string.format("%.2f",State.WeightThreshold)
        log("Invalid weight threshold")
    end
end)
local ruleBody=text(hRight,"",8,Theme.Text,Enum.Font.Code)
ruleBody.Position=UDim2.fromOffset(11,96)
ruleBody.Size=UDim2.new(1,-22,0,82)
ruleBody.TextWrapped=true
ruleBody.TextYAlignment=Enum.TextYAlignment.Top
local flowCap=text(hRight,"TEAM FLOW",8,Theme.Muted,Enum.Font.GothamBold)
flowCap.Position=UDim2.fromOffset(11,182)
flowCap.Size=UDim2.new(1,-22,0,15)
local flow=text(hRight,"READY → WEIGHT CHECK\n↓\nKOI / HATCH TEAM\n↓\nBRONTO FOR BIG PET\n↓\nHATCH",8,Theme.Text,Enum.Font.Code)
flow.Position=UDim2.fromOffset(11,201)
flow.Size=UDim2.new(1,-22,0,92)
flow.TextYAlignment=Enum.TextYAlignment.Top
local selected=text(hRight,"",8,Theme.Muted,Enum.Font.Code)
selected.Position=UDim2.fromOffset(11,306)
selected.Size=UDim2.new(1,-22,0,28)
selected.TextWrapped=true

-- Teams page
local tp=Pages.Teams
local teamHeader=Instance.new("Frame")
teamHeader.Size=UDim2.new(1,0,0,41)
teamHeader.BackgroundTransparency=1
teamHeader.Parent=tp
local selectedTeam="Hatch"
local teamTabs={}
for i,teamName in ipairs({"Hatch","Bronto","Reduction","Sell"}) do
    local b=actionButton(teamHeader,TeamNames[teamName],UDim2.new((i-1)*0.25,0,0,0),UDim2.new(0.25,-5,0,34),Theme.Panel2)
    teamTabs[teamName]=b
    b.Activated:Connect(function()
        selectedTeam=teamName
        for name,button in pairs(teamTabs) do
            button.BackgroundColor3=(name==selectedTeam) and Theme.PurpleDark or Theme.Panel2
        end
        log("Editing "..TeamNames[selectedTeam])
        redrawTeams()
    end)
end
teamTabs.Hatch.BackgroundColor3=Theme.PurpleDark

local slots=Instance.new("Frame")
slots.Position=UDim2.fromOffset(0,49)
slots.Size=UDim2.new(0.56,-5,1,-49)
slots.BackgroundColor3=Theme.Panel
slots.BorderSizePixel=0
slots.Parent=tp
corner(slots,8)
outline(slots)
local slotTitle=text(slots,"",9,Theme.Text,Enum.Font.GothamBold)
slotTitle.Position=UDim2.fromOffset(10,7)
slotTitle.Size=UDim2.new(1,-20,0,16)
local slotScroll=Instance.new("ScrollingFrame")
slotScroll.Position=UDim2.fromOffset(8,30)
slotScroll.Size=UDim2.new(1,-16,1,-38)
slotScroll.BackgroundTransparency=1
slotScroll.BorderSizePixel=0
slotScroll.ScrollBarThickness=2
slotScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
slotScroll.Parent=slots
local slotGrid=Instance.new("UIGridLayout")
slotGrid.CellSize=UDim2.fromOffset(94,82)
slotGrid.CellPadding=UDim2.fromOffset(5,5)
slotGrid.Parent=slotScroll

local inv=Instance.new("Frame")
inv.Position=UDim2.new(0.56,2,0,49)
inv.Size=UDim2.new(0.44,-2,1,-49)
inv.BackgroundColor3=Theme.Panel
inv.BorderSizePixel=0
inv.Parent=tp
corner(inv,8)
outline(inv)
local invTitle=text(inv,"YOUR INVENTORY",9,Theme.Text,Enum.Font.GothamBold)
invTitle.Position=UDim2.fromOffset(10,7)
invTitle.Size=UDim2.new(1,-20,0,16)
local invSub=text(inv,"Only owned inventory pets can be selected",7,Theme.Muted,Enum.Font.Code)
invSub.Position=UDim2.fromOffset(10,22)
invSub.Size=UDim2.new(1,-20,0,13)
local invSearch=Instance.new("TextBox")
invSearch.Position=UDim2.fromOffset(8,40)
invSearch.Size=UDim2.new(1,-16,0,28)
invSearch.BackgroundColor3=Theme.Panel2
invSearch.BorderSizePixel=0
invSearch.Text=""
invSearch.PlaceholderText="Search pets..."
invSearch.PlaceholderColor3=Theme.Muted
invSearch.TextColor3=Theme.Text
invSearch.TextSize=8
invSearch.Font=Enum.Font.Gotham
invSearch.ClearTextOnFocus=false
invSearch.Parent=inv
corner(invSearch,7)
outline(invSearch)
local invScroll=Instance.new("ScrollingFrame")
invScroll.Position=UDim2.fromOffset(8,74)
invScroll.Size=UDim2.new(1,-16,1,-112)
invScroll.BackgroundTransparency=1
invScroll.BorderSizePixel=0
invScroll.ScrollBarThickness=2
invScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
invScroll.Parent=inv
local invList=Instance.new("UIListLayout")
invList.Padding=UDim.new(0,4)
invList.Parent=invScroll

local invRefresh=actionButton(inv,"REFRESH INVENTORY",UDim2.new(0,8,1,-32),UDim2.new(1,-16,0,25),Theme.Panel2)

function redrawTeams()
    for _,child in ipairs(slotScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    for _,child in ipairs(invScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local team=State.Teams[selectedTeam]
    slotTitle.Text=(TeamNames[selectedTeam].."  •  "..#team.."/8")

    for i=1,8 do
        local entry=team[i]
        local card=Instance.new("Frame")
        card.BackgroundColor3=entry and Theme.Panel2 or Color3.fromRGB(15,15,19)
        card.BorderSizePixel=0
        card.Parent=slotScroll
        corner(card,7)
        outline(card,entry and Theme.PurpleDark or Theme.Outline,entry and 0.15 or 0.45)
        local slot=text(card,"SLOT "..i,7,Theme.Muted,Enum.Font.GothamBold)
        slot.Position=UDim2.fromOffset(7,4)
        slot.Size=UDim2.new(1,-14,0,13)
        if entry then
            local name=text(card,entry.PetType,8,Theme.Text,Enum.Font.GothamSemibold)
            name.Position=UDim2.fromOffset(7,20)
            name.Size=UDim2.new(1,-14,0,21)
            name.TextWrapped=true
            local wt=text(card,weightText(entry.BaseWeight),6,Theme.Muted,Enum.Font.Code)
            wt.Position=UDim2.fromOffset(7,46)
            wt.Size=UDim2.new(1,-14,0,13)
            local id=text(card,entry.UUID:sub(1,8),6,Theme.Muted,Enum.Font.Code)
            id.Position=UDim2.fromOffset(7,61)
            id.Size=UDim2.new(1,-14,0,11)
            local rm=actionButton(card,"×",UDim2.fromOffset(20,20),UDim2.fromOffset(25,23),Theme.Background)
            rm.Position=UDim2.new(1,-28,0,3)
            rm.TextColor3=Theme.Red
            rm.Activated:Connect(function()
                removeFromTeam(selectedTeam,i)
                redrawTeams()
            end)
        else
            local empty=text(card,"EMPTY",7,Theme.Muted,Enum.Font.Code)
            empty.Position=UDim2.fromOffset(7,29)
            empty.Size=UDim2.new(1,-14,0,18)
            empty.TextXAlignment=Enum.TextXAlignment.Center
        end
    end

    local query=string.lower(invSearch.Text or "")
    for _,pet in ipairs(State.Inventory) do
        if query=="" or string.find(string.lower(pet.PetType),query,1,true) then
            local row=Instance.new("Frame")
            row.Size=UDim2.new(1,0,0,46)
            row.BackgroundColor3=Theme.Panel2
            row.BorderSizePixel=0
            row.Parent=invScroll
            corner(row,7)
            local icon=iconValue(pet.PetType)
            if icon then
                local image=Instance.new("ImageLabel")
                image.BackgroundTransparency=1
                image.Position=UDim2.fromOffset(6,6)
                image.Size=UDim2.fromOffset(32,32)
                image.Image=icon
                image.Parent=row
            else
                local badge=text(row,string.sub(pet.PetType,1,1),14,Theme.Purple,Enum.Font.GothamBold)
                badge.Position=UDim2.fromOffset(6,6)
                badge.Size=UDim2.fromOffset(32,32)
                badge.TextXAlignment=Enum.TextXAlignment.Center
            end
            local name=text(row,pet.PetType,8,Theme.Text,Enum.Font.GothamSemibold)
            name.Position=UDim2.fromOffset(43,4)
            name.Size=UDim2.new(1,-91,0,17)
            local info=text(row,("%.4f KG  •  Lv.%d"):format(pet.BaseWeight or 0,pet.Level),6,Theme.Muted,Enum.Font.Code)
            info.Position=UDim2.fromOffset(43,22)
            info.Size=UDim2.new(1,-91,0,14)
            local add=actionButton(row,"+",UDim2.fromOffset(34,28),UDim2.fromOffset(39,27),Theme.Panel3)
            add.Position=UDim2.new(1,-45,0,9)
            if #team>=8 or teamHasUUID(selectedTeam,pet.UUID) then
                add.TextColor3=Theme.Muted
                add.BackgroundColor3=Theme.Background
            end
            add.Activated:Connect(function()
                local ok,err=addToTeam(selectedTeam,pet.UUID)
                if ok then
                    log(pet.PetType.." → "..TeamNames[selectedTeam])
                    redrawTeams()
                else
                    log(err)
                end
            end)
        end
    end
end

invRefresh.Activated:Connect(function()
    rebuildInventory()
    redrawTeams()
    log("Inventory refreshed • "..#State.Inventory.." pets")
end)
invSearch:GetPropertyChangedSignal("Text"):Connect(redrawTeams)

-- Team action buttons
local teamActions=Instance.new("Frame")
teamActions.Position=UDim2.new(0,0,1,-35)
teamActions.Size=UDim2.fromOffset(390,29)
teamActions.BackgroundTransparency=1
teamActions.Parent=tp
local clearTeamButton=actionButton(teamActions,"CLEAR TEAM",UDim2.fromOffset(0,0),UDim2.fromOffset(120,27),Theme.Panel2)
local applyTeamButton=actionButton(teamActions,"APPLY / VERIFY TEAM",UDim2.fromOffset(126,0),UDim2.fromOffset(160,27),Theme.PurpleDark)
local autoFillButton=actionButton(teamActions,"AUTO FILL",UDim2.fromOffset(292,0),UDim2.fromOffset(90,27),Theme.Panel2)
clearTeamButton.Activated:Connect(function()
    clearTeam(selectedTeam)
    redrawTeams()
    log("Cleared "..TeamNames[selectedTeam])
end)
applyTeamButton.Activated:Connect(function()
    ApplyTeam(selectedTeam)
end)
autoFillButton.Activated:Connect(function()
    clearTeam(selectedTeam)
    for _,pet in ipairs(State.Inventory) do
        if #State.Teams[selectedTeam]>=8 then break end
        addToTeam(selectedTeam,pet.UUID)
    end
    redrawTeams()
    log("Auto-filled "..TeamNames[selectedTeam].." • "..#State.Teams[selectedTeam].."/8")
end)

-- Pet Sell
local sp=Pages["Pet Sell"]
local sellBox=Instance.new("Frame")
sellBox.Size=UDim2.new(0.62,-5,1,0)
sellBox.BackgroundColor3=Theme.Panel
sellBox.BorderSizePixel=0
sellBox.Parent=sp
corner(sellBox,8)
outline(sellBox)
local sellTitle=text(sellBox,"PET SELL SETTINGS",10,Theme.Text,Enum.Font.GothamBold)
sellTitle.Position=UDim2.fromOffset(11,8)
sellTitle.Size=UDim2.new(1,-22,0,16)
local sellSearch=Instance.new("TextBox")
sellSearch.Position=UDim2.fromOffset(9,34)
sellSearch.Size=UDim2.new(1,-18,0,28)
sellSearch.BackgroundColor3=Theme.Panel2
sellSearch.BorderSizePixel=0
sellSearch.Text=""
sellSearch.PlaceholderText="Search owned pet types..."
sellSearch.PlaceholderColor3=Theme.Muted
sellSearch.TextColor3=Theme.Text
sellSearch.TextSize=8
sellSearch.Font=Enum.Font.Gotham
sellSearch.ClearTextOnFocus=false
sellSearch.Parent=sellBox
corner(sellSearch,7)
outline(sellSearch)
local sellScroll=Instance.new("ScrollingFrame")
sellScroll.Position=UDim2.fromOffset(9,69)
sellScroll.Size=UDim2.new(1,-18,1,-78)
sellScroll.BackgroundTransparency=1
sellScroll.BorderSizePixel=0
sellScroll.ScrollBarThickness=2
sellScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
sellScroll.Parent=sellBox
local sellList=Instance.new("UIListLayout")
sellList.Padding=UDim.new(0,4)
sellList.Parent=sellScroll
local sellRight=Instance.new("Frame")
sellRight.Position=UDim2.new(0.62,2,0,0)
sellRight.Size=UDim2.new(0.38,-2,1,0)
sellRight.BackgroundColor3=Theme.Panel
sellRight.BorderSizePixel=0
sellRight.Parent=sp
corner(sellRight,8)
outline(sellRight)
local sellRTitle=text(sellRight,"CONTROL",10,Theme.Text,Enum.Font.GothamBold)
sellRTitle.Position=UDim2.fromOffset(11,8)
sellRTitle.Size=UDim2.new(1,-22,0,16)
makeToggle(sellRight,"Auto Sell","Sell enabled types",function()return State.AutoSell end,function(v)State.AutoSell=v end,33)
makeToggle(sellRight,"Big Pet Notification","Notify when over threshold",function()return State.BigPetNotify end,function(v)State.BigPetNotify=v end,80)
local keepText=text(sellRight,"KEEP WEIGHT ABOVE [KG]",8,Theme.Muted,Enum.Font.GothamBold)
keepText.Position=UDim2.fromOffset(11,135)
keepText.Size=UDim2.new(1,-22,0,15)
local keepInput=Instance.new("TextBox")
keepInput.Position=UDim2.fromOffset(11,154)
keepInput.Size=UDim2.new(1,-22,0,31)
keepInput.BackgroundColor3=Theme.Panel2
keepInput.BorderSizePixel=0
keepInput.Text="1.30"
keepInput.TextColor3=Theme.Text
keepInput.TextSize=9
keepInput.Font=Enum.Font.Code
keepInput.ClearTextOnFocus=false
keepInput.Parent=sellRight
corner(keepInput,7)
outline(keepInput)

local function redrawSell()
    for _,child in ipairs(sellScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    local query=string.lower(sellSearch.Text or "")
    local seen={}
    local types={}
    for _,pet in ipairs(State.Inventory) do
        if not seen[pet.PetType] then
            seen[pet.PetType]=true
            types[#types+1]=pet.PetType
        end
    end
    table.sort(types)
    for _,petType in ipairs(types) do
        if query=="" or string.find(string.lower(petType),query,1,true) then
            local row=Instance.new("Frame")
            row.Size=UDim2.new(1,0,0,38)
            row.BackgroundColor3=Theme.Panel2
            row.BorderSizePixel=0
            row.Parent=sellScroll
            corner(row,7)
            local name=text(row,petType,8,Theme.Text,Enum.Font.GothamSemibold)
            name.Position=UDim2.fromOffset(8,0)
            name.Size=UDim2.new(1,-65,1,0)
            local tr=Instance.new("TextButton")
            tr.Text=""
            tr.AutoButtonColor=false
            tr.Size=UDim2.fromOffset(40,20)
            tr.Position=UDim2.new(1,-48,0.5,-10)
            tr.BackgroundColor3=State.SellPetTypes[petType] and Theme.Purple or Color3.fromRGB(55,55,66)
            tr.BorderSizePixel=0
            tr.Parent=row
            corner(tr,10)
            local k=Instance.new("Frame")
            k.Size=UDim2.fromOffset(16,16)
            k.Position=State.SellPetTypes[petType] and UDim2.new(1,-18,0,2) or UDim2.fromOffset(2,2)
            k.BackgroundColor3=State.SellPetTypes[petType] and Color3.new(1,1,1) or Theme.Muted
            k.BorderSizePixel=0
            k.Parent=tr
            corner(k,8)
            tr.Activated:Connect(function()
                State.SellPetTypes[petType]=not State.SellPetTypes[petType]
                redrawSell()
                log(petType.." • "..(State.SellPetTypes[petType] and "SELL" or "KEEP"))
            end)
        end
    end
end
sellSearch:GetPropertyChangedSignal("Text"):Connect(redrawSell)

-- Egg ESP
local ep=Pages["Egg ESP"]
local espLeft=Instance.new("Frame")
espLeft.Size=UDim2.new(0.62,-5,1,0)
espLeft.BackgroundColor3=Theme.Panel
espLeft.BorderSizePixel=0
espLeft.Parent=ep
corner(espLeft,8)
outline(espLeft)
local espTitle=text(espLeft,"EGG ESP",10,Theme.Text,Enum.Font.GothamBold)
espTitle.Position=UDim2.fromOffset(11,8)
espTitle.Size=UDim2.new(1,-22,0,17)
makeToggle(espLeft,"Egg ESP","Show owned egg state",function()return State.EggESP end,function(v)State.EggESP=v end,32)
local espDesc=text(espLeft,"Ready-state data is shown only after EggReadyToHatch_RE\nreveals the pet. BaseWeight is displayed only when an\nexact ready-weight value has been supplied.",8,Theme.Muted,Enum.Font.Code)
espDesc.Position=UDim2.fromOffset(11,86)
espDesc.Size=UDim2.new(1,-22,0,72)
espDesc.TextWrapped=true
local espRight=Instance.new("Frame")
espRight.Position=UDim2.new(0.62,2,0,0)
espRight.Size=UDim2.new(0.38,-2,1,0)
espRight.BackgroundColor3=Theme.Panel
espRight.BorderSizePixel=0
espRight.Parent=ep
corner(espRight,8)
outline(espRight)
local espRTitle=text(espRight,"READY EGG DETAIL",10,Theme.Text,Enum.Font.GothamBold)
espRTitle.Position=UDim2.fromOffset(11,8)
espRTitle.Size=UDim2.new(1,-22,0,17)
local espDetail=text(espRight,"",8,Theme.Text,Enum.Font.Code)
espDetail.Position=UDim2.fromOffset(11,34)
espDetail.Size=UDim2.new(1,-22,0,150)
espDetail.TextWrapped=true
espDetail.TextYAlignment=Enum.TextYAlignment.Top

-- Settings
local set=Pages.Settings
local setBox=Instance.new("Frame")
setBox.Size=UDim2.new(0.65,-5,1,0)
setBox.BackgroundColor3=Theme.Panel
setBox.BorderSizePixel=0
setBox.Parent=set
corner(setBox,8)
outline(setBox)
local setTitle=text(setBox,"SETTINGS",10,Theme.Text,Enum.Font.GothamBold)
setTitle.Position=UDim2.fromOffset(11,8)
setTitle.Size=UDim2.new(1,-22,0,17)
local setBody=text(setBox,"Fable V6 is deliberately dependency-free.\n\nAll pet team entries are backed by exact inventory UUIDs.\nNo guessed inventory entries are created.\n\nThe hatch remote and READY event are the verified native paths.\nThe pre-hatch BaseWeight is never fabricated.\n\nCurrent helper hook:\nFableAutoHatch.SetReadyWeight(UUID, exactWeight)",8,Theme.Text,Enum.Font.Code)
setBody.Position=UDim2.fromOffset(11,34)
setBody.Size=UDim2.new(1,-22,0,230)
setBody.TextWrapped=true
setBody.TextYAlignment=Enum.TextYAlignment.Top

-- Master toggle sync
local function drawMaster()
    MasterToggle.BackgroundColor3 = State.AutoHatch and Theme.Purple or Color3.fromRGB(55,55,66)
    masterKnob.BackgroundColor3 = State.AutoHatch and Color3.new(1,1,1) or Theme.Muted
    masterKnob.Position = State.AutoHatch and UDim2.new(1,-22,0,2) or UDim2.fromOffset(2,2)
    runningText.Text = State.AutoHatch and "RUNNING" or "IDLE"
    runningText.TextColor3 = State.AutoHatch and Theme.Green or Theme.Muted
end

MasterToggle.Activated:Connect(function()
    State.AutoHatch = not State.AutoHatch
    drawMaster()
    log("Auto Hatch • " .. (State.AutoHatch and "ON" or "OFF"))
end)

-- Dragging
local dragging=false
local dragStart
local startPos
Header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true
        dragStart=input.Position
        startPos=Main.Position
    end
end)
Header.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType~=Enum.UserInputType.MouseMovement and input.UserInputType~=Enum.UserInputType.Touch then return end
    local delta=input.Position-dragStart
    Main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
end)

local minimized=false
local fullSize=UDim2.fromOffset(720,455)
MinButton.Activated:Connect(function()
    minimized=not minimized
    for _,child in ipairs(Main:GetChildren()) do
        if child~=Header then
            child.Visible=not minimized
        end
    end
    Main.Size=minimized and UDim2.fromOffset(300,54) or fullSize
    MinButton.Text=minimized and "+" or "—"
end)

CloseButton.Activated:Connect(function()
    State.AutoHatch=false
    Gui:Destroy()
end)

-- Search across page names.
Search:GetPropertyChangedSignal("Text"):Connect(function()
    local q=string.lower(Search.Text or "")
    for name,nav in pairs(NavButtons) do
        nav.Visible=(q=="" or string.find(string.lower(name),q,1,true)~=nil)
    end
end)

-- Runtime loop. UI refresh is throttled; egg polling is light.
task.spawn(function()
    local refreshCounter=0
    while Gui.Parent do
        task.wait(0.25)
        refreshCounter += 1

        refreshEggCounts()

        if refreshCounter % 4 == 0 then
            rebuildInventory()
            if State.Page=="Teams" then redrawTeams() end
            if State.Page=="Pet Sell" then redrawSell() end
        end

        statValues.EGGS.Text=tostring(State.Eggs)
        statValues.READY.Text=tostring(State.Ready)
        statValues.HATCHED.Text=tostring(State.Hatched)
        statValues.FAILED.Text=tostring(State.Failed)

        liveState.Text=State.AutoHatch and "● FABLE IS RUNNING" or "FABLE IS READY"
        liveState.TextColor3=State.AutoHatch and Theme.Green or Theme.Purple
        drawMaster()

        live1.Text=("Eggs %d  |  Ready %d  |  Created %d  |  Hatched %d"):format(State.Eggs,State.Ready,State.Created,State.Hatched)
        live2.Text=("Failed %d  |  Sold %d  |  Activity %d"):format(State.Failed,State.Sold,State.Activity)
        live3.Text=("Current: %s  |  Team: %s  |  Weight: %s"):format(State.CurrentStatus,State.CurrentTeam,weightText(State.CurrentWeight))
        activity.Text=("Decision: %s  |  Last hatch: %.2fs"):format(State.CurrentDecision,Num(State.LastHatchTime,0))

        readyText.Text=("Egg: %s\nUUID: %s\nPet: %s\nWeight: %s\nDecision: %s\nTeam: %s"):format(
            State.CurrentEgg,State.CurrentUUID,State.CurrentPet,weightText(State.CurrentWeight),State.CurrentDecision,State.CurrentTeam
        )
        espDetail.Text=readyText.Text

        local logLines={}
        for i=1,math.min(7,#State.Logs) do logLines[#logLines+1]=State.Logs[i] end
        logText.Text=table.concat(logLines,"\n")

        ruleBody.Text=(
            "Threshold: %.2f KG\n\n" ..
            "BaseWeight > threshold → BRONTO\n" ..
            "BaseWeight <= threshold → KOI\n\n" ..
            "Fable never fabricates a missing weight."
        ):format(State.WeightThreshold)

        selected.Text="Selected teams:\n" ..
            "Hatch  "..#State.Teams.Hatch.."/8  •  "..teamTypeSummary("Hatch").."\n" ..
            "Bronto "..#State.Teams.Bronto.."/8 •  "..teamTypeSummary("Bronto")

        if State.AutoHatch then
            for _,egg in ipairs(ownedEggs()) do
                if not State.AutoHatch then break end
                if isReady(egg) then
                    local did=hatchEgg(egg)
                    if did and not State.BatchHatching then break end
                    task.wait(math.max(0,State.HatchDelay))
                end
            end
        end
    end
end)

-- Initial state
rebuildInventory()
refreshEggCounts()
log(("Loaded • %d inventory pets • %d eggs • teams are 8-slot"):format(#State.Inventory,State.Eggs))
activatePage("Dashboard")
drawMaster()
redrawTeams()
redrawSell()

print("==================================================")
print("[FABLE] V6 final UI loaded")
print("[FABLE] Inventory-backed 8-slot team editor ready")
print("[FABLE] READY event: " .. (ReadyEvent and "OK" or "MISSING"))
print("[FABLE] Hatch service: " .. (PetEggService and "OK" or "MISSING"))
print("==================================================")
