-- FABLE AUTO HATCH v5.0
-- Standalone / dependency-free build.
-- Designed to avoid the large embedded UI-library startup failure.
-- No external UI framework and no external asset is required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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

-- Remove previous standalone instance cleanly.
local oldGui = PlayerGui:FindFirstChild("FableAutoHatchV5")
if oldGui then
    oldGui:Destroy()
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
    DataService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DataService"))
end)

local state = {
    autoHatch = false,
    fastPlacement = false,
    batchHatching = true,
    markBigPet = true,
    pauseIfWeightUnavailable = false,
    weightThreshold = 1.3,

    eggReductionPet = "",
    hatchPet = "",
    brontoPet = "",
    sellPet = "",

    currentStatus = "Idle",
    currentEgg = "-",
    currentPet = "-",
    currentWeight = nil,
    currentDecision = "-",
    currentTeam = "-",
    lastHatchTime = 0,

    created = 0,
    ready = 0,
    hatched = 0,
    sold = 0,
    failed = 0,

    readyByUUID = {},
    processing = {},
    lastLog = "Fable loaded."
}

local function safeToString(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

local function getData()
    if not DataService then
        return nil
    end
    local ok, data = pcall(function()
        return DataService:GetData()
    end)
    if ok and type(data) == "table" then
        return data
    end
end

local function getInventory()
    local data = getData()
    local petsData = data and data.PetsData
    local inventory = petsData and petsData.PetInventory
    local stored = inventory and inventory.Data
    if type(stored) == "table" then
        return stored
    end
    return {}
end

local function findPetToolByType(petType)
    if not petType or petType == "" then
        return nil
    end

    local inventory = getInventory()
    local targetUUID

    for uuid, pet in pairs(inventory) do
        if type(pet) == "table" and safeToString(pet.PetType) == safeToString(petType) then
            targetUUID = safeToString(uuid)
            break
        end
    end

    if not targetUUID then
        return nil
    end

    local character = LocalPlayer.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and safeToString(tool:GetAttribute("PET_UUID")) == targetUUID then
                return tool
            end
        end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and safeToString(tool:GetAttribute("PET_UUID")) == targetUUID then
                return tool
            end
        end
    end

    return nil
end

local function equipPetType(petType)
    local tool = findPetToolByType(petType)
    if not tool then
        return false, "Pet not found: " .. safeToString(petType)
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false, "Humanoid unavailable"
    end

    local ok, err = pcall(function()
        humanoid:EquipTool(tool)
    end)
    if not ok then
        return false, "EquipTool failed: " .. safeToString(err)
    end

    for _ = 1, 30 do
        if tool.Parent == character then
            return true
        end
        task.wait(0.05)
    end

    return false, "Equip verification timed out"
end

local function getOwnedEggs()
    local result = {}
    for _, egg in ipairs(CollectionService:GetTagged("PetEggServer")) do
        if egg:GetAttribute("OWNER") == LocalPlayer.Name then
            table.insert(result, egg)
        end
    end
    return result
end

local function getEggUUID(egg)
    if not egg then
        return nil
    end
    local uuid = egg:GetAttribute("OBJECT_UUID")
    if uuid == nil then
        return nil
    end
    return safeToString(uuid)
end

local function isReady(egg)
    if not egg then
        return false
    end
    local timer = egg:GetAttribute("TimeToHatch")
    return typeof(timer) == "number" and timer <= 0
end

local function snapshotPets()
    local result = {}
    for uuid in pairs(getInventory()) do
        result[safeToString(uuid)] = true
    end
    return result
end

local function findNewPet(before, expectedType)
    local inventory = getInventory()
    for uuid, pet in pairs(inventory) do
        local uid = safeToString(uuid)
        if not before[uid] and type(pet) == "table" then
            if expectedType == nil or safeToString(pet.PetType) == safeToString(expectedType) then
                return uid, pet
            end
        end
    end
end

local function formatWeight(v)
    if type(v) ~= "number" then
        return "Unknown"
    end
    return string.format("%.4f", v)
end

local function log(message)
    state.lastLog = safeToString(message)
    print("[FABLE] " .. state.lastLog)
end

-- ============================================================
-- UI
-- ============================================================

local Gui = Instance.new("ScreenGui")
Gui.Name = "FableAutoHatchV5"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.DisplayOrder = 100000
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
Gui.Parent = PlayerGui

local function newCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function newStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(65, 68, 78)
    s.Thickness = thickness or 1
    s.Transparency = 0.15
    s.Parent = parent
    return s
end

local function newText(parent, text, size, font, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.Font = font or Enum.Font.Gotham
    l.TextSize = size or 12
    l.TextColor3 = color or Color3.fromRGB(235, 237, 242)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(520, 330)
Main.Position = UDim2.new(0.5, -260, 0.5, -165)
Main.BackgroundColor3 = Color3.fromRGB(14, 15, 19)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui
newCorner(Main, 10)
newStroke(Main, Color3.fromRGB(67, 70, 84), 1)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 48)
Header.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
Header.BorderSizePixel = 0
Header.Parent = Main
newCorner(Header, 10)

local Logo = newText(Header, "F", 27, Enum.Font.GothamBlack, Color3.new(1, 1, 1))
Logo.Position = UDim2.fromOffset(14, 7)
Logo.Size = UDim2.fromOffset(35, 34)
Logo.TextXAlignment = Enum.TextXAlignment.Center

local Title = newText(Header, "FABLE", 16, Enum.Font.GothamBold)
Title.Position = UDim2.fromOffset(52, 8)
Title.Size = UDim2.fromOffset(160, 20)

local Subtitle = newText(Header, "AUTO HATCH • STANDALONE", 8, Enum.Font.Code, Color3.fromRGB(135, 140, 155))
Subtitle.Position = UDim2.fromOffset(53, 27)
Subtitle.Size = UDim2.fromOffset(200, 15)

local MinButton = Instance.new("TextButton")
MinButton.Text = "—"
MinButton.Font = Enum.Font.GothamBold
MinButton.TextSize = 16
MinButton.TextColor3 = Color3.fromRGB(190, 194, 204)
MinButton.BackgroundTransparency = 1
MinButton.Size = UDim2.fromOffset(36, 36)
MinButton.Position = UDim2.new(1, -76, 0, 6)
MinButton.Parent = Header

local CloseButton = Instance.new("TextButton")
CloseButton.Text = "×"
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 22
CloseButton.TextColor3 = Color3.fromRGB(190, 194, 204)
CloseButton.BackgroundTransparency = 1
CloseButton.Size = UDim2.fromOffset(36, 36)
CloseButton.Position = UDim2.new(1, -39, 0, 5)
CloseButton.Parent = Header

local Tabs = Instance.new("Frame")
Tabs.Position = UDim2.fromOffset(12, 58)
Tabs.Size = UDim2.new(1, -24, 0, 34)
Tabs.BackgroundTransparency = 1
Tabs.Parent = Main

local Pages = {}
local ActivePage

local function makeTabButton(name, x)
    local b = Instance.new("TextButton")
    b.Name = name .. "Tab"
    b.Text = name
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = Color3.fromRGB(175, 180, 194)
    b.BackgroundColor3 = Color3.fromRGB(25, 26, 32)
    b.BorderSizePixel = 0
    b.Position = UDim2.fromOffset(x, 0)
    b.Size = UDim2.fromOffset(116, 32)
    b.Parent = Tabs
    newCorner(b, 7)
    return b
end

local function makePage(name)
    local p = Instance.new("Frame")
    p.Name = name .. "Page"
    p.Position = UDim2.fromOffset(12, 100)
    p.Size = UDim2.new(1, -24, 1, -112)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = Main
    Pages[name] = p
    return p
end

local function setPage(name)
    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end
    ActivePage = name
end

local Dashboard = makePage("Dashboard")
local Hatching = makePage("Hatching")
local Teams = makePage("Teams")
local ESP = makePage("Egg ESP")

local tabNames = {"Dashboard", "Hatching", "Teams", "Egg ESP"}
for i, name in ipairs(tabNames) do
    local button = makeTabButton(name, (i - 1) * 123)
    button.Activated:Connect(function()
        setPage(name)
    end)
end

local function makeBox(parent, pos, size)
    local f = Instance.new("Frame")
    f.Position = pos
    f.Size = size
    f.BackgroundColor3 = Color3.fromRGB(19, 20, 26)
    f.BorderSizePixel = 0
    f.Parent = parent
    newCorner(f, 8)
    newStroke(f, Color3.fromRGB(47, 50, 61), 1)
    return f
end

-- Dashboard
local DashStats = makeBox(Dashboard, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 82))
local DashLine1 = newText(DashStats, "", 11, Enum.Font.Code)
DashLine1.Position = UDim2.fromOffset(11, 7)
DashLine1.Size = UDim2.new(1, -22, 0, 22)

local DashLine2 = newText(DashStats, "", 11, Enum.Font.Code)
DashLine2.Position = UDim2.fromOffset(11, 30)
DashLine2.Size = UDim2.new(1, -22, 0, 22)

local DashLine3 = newText(DashStats, "", 10, Enum.Font.Code, Color3.fromRGB(157, 162, 175))
DashLine3.Position = UDim2.fromOffset(11, 53)
DashLine3.Size = UDim2.new(1, -22, 0, 19)

local LogBox = makeBox(Dashboard, UDim2.fromOffset(0, 92), UDim2.new(1, 0, 0, 74))
local LogTitle = newText(LogBox, "STATUS", 9, Enum.Font.GothamBold, Color3.fromRGB(145, 150, 165))
LogTitle.Position = UDim2.fromOffset(10, 6)
LogTitle.Size = UDim2.new(1, -20, 0, 16)

local LogLabel = newText(LogBox, "", 10, Enum.Font.Code)
LogLabel.Position = UDim2.fromOffset(10, 25)
LogLabel.Size = UDim2.new(1, -20, 0, 40)
LogLabel.TextWrapped = true
LogLabel.TextYAlignment = Enum.TextYAlignment.Top

local ReadyBox = makeBox(Dashboard, UDim2.fromOffset(0, 176), UDim2.new(1, 0, 0, 78))
local ReadyTitle = newText(ReadyBox, "CURRENT READY EGG", 9, Enum.Font.GothamBold, Color3.fromRGB(145, 150, 165))
ReadyTitle.Position = UDim2.fromOffset(10, 6)
ReadyTitle.Size = UDim2.new(1, -20, 0, 16)

local ReadyLabel = newText(ReadyBox, "", 10, Enum.Font.Code)
ReadyLabel.Position = UDim2.fromOffset(10, 25)
ReadyLabel.Size = UDim2.new(1, -20, 0, 43)
ReadyLabel.TextWrapped = true
ReadyLabel.TextYAlignment = Enum.TextYAlignment.Top

-- Hatching
local HatchBox = makeBox(Hatching, UDim2.fromOffset(0, 0), UDim2.new(0.5, -5, 1, 0))
local RuleBox = makeBox(Hatching, UDim2.new(0.5, 5, 0, 0), UDim2.new(0.5, -5, 1, 0))

local function makeToggle(parent, y, text, key)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = Color3.fromRGB(24, 25, 31)
    row.BorderSizePixel = 0
    row.Position = UDim2.fromOffset(8, y)
    row.Size = UDim2.new(1, -16, 0, 36)
    row.Parent = parent
    newCorner(row, 7)

    local label = newText(row, text, 10)
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(1, -82, 1, 0)

    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(52, 26)
    button.Position = UDim2.new(1, -62, 0.5, -13)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.TextSize = 9
    button.Parent = row
    newCorner(button, 13)

    local function paint()
        local enabled = state[key] == true
        button.Text = enabled and "ON" or "OFF"
        button.TextColor3 = enabled and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,155,168)
        button.BackgroundColor3 = enabled and Color3.fromRGB(118, 78, 230) or Color3.fromRGB(47, 49, 58)
    end

    button.Activated:Connect(function()
        state[key] = not state[key]
        paint()
        log(text .. ": " .. (state[key] and "ON" or "OFF"))
    end)

    paint()
    return row
end

makeToggle(HatchBox, 8, "Auto Hatch", "autoHatch")
makeToggle(HatchBox, 48, "Fast Egg Placement", "fastPlacement")
makeToggle(HatchBox, 88, "Batch Hatching", "batchHatching")
makeToggle(HatchBox, 128, "Mark Big Pet", "markBigPet")
makeToggle(HatchBox, 168, "Pause if weight unavailable", "pauseIfWeightUnavailable")

local thresholdLabel = newText(RuleBox, "Keep Weight Above [KG]", 10)
thresholdLabel.Position = UDim2.fromOffset(12, 10)
thresholdLabel.Size = UDim2.new(1, -24, 0, 22)

local thresholdBox = Instance.new("TextBox")
thresholdBox.Position = UDim2.fromOffset(12, 37)
thresholdBox.Size = UDim2.new(1, -24, 0, 34)
thresholdBox.BackgroundColor3 = Color3.fromRGB(24, 25, 31)
thresholdBox.BorderSizePixel = 0
thresholdBox.ClearTextOnFocus = false
thresholdBox.Font = Enum.Font.Code
thresholdBox.TextSize = 12
thresholdBox.TextColor3 = Color3.fromRGB(235,237,242)
thresholdBox.Text = tostring(state.weightThreshold)
thresholdBox.Parent = RuleBox
newCorner(thresholdBox, 7)

thresholdBox.FocusLost:Connect(function()
    local v = tonumber(thresholdBox.Text)
    if v and v >= 0 then
        state.weightThreshold = v
        log("Threshold set to " .. tostring(v))
    else
        thresholdBox.Text = tostring(state.weightThreshold)
        log("Invalid threshold")
    end
end)

local hint = newText(RuleBox, "Bronto when exact BaseWeight is available and above threshold.", 9, Enum.Font.Code, Color3.fromRGB(145,150,164))
hint.Position = UDim2.fromOffset(12, 79)
hint.Size = UDim2.new(1, -24, 0, 42)
hint.TextWrapped = true
hint.TextYAlignment = Enum.TextYAlignment.Top

local manual = newText(RuleBox, "When no exact ready weight is exposed, Fable uses the selected Hatch Team instead of guessing.", 9, Enum.Font.Code, Color3.fromRGB(145,150,164))
manual.Position = UDim2.fromOffset(12, 128)
manual.Size = UDim2.new(1, -24, 0, 65)
manual.TextWrapped = true
manual.TextYAlignment = Enum.TextYAlignment.Top

-- Teams
local TeamInfo = makeBox(Teams, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 42))
local TeamStatus = newText(TeamInfo, "Inventory-backed pet selectors. Refresh to update.", 9, Enum.Font.Code, Color3.fromRGB(155,160,175))
TeamStatus.Position = UDim2.fromOffset(10, 5)
TeamStatus.Size = UDim2.new(1, -20, 0, 30)
TeamStatus.TextWrapped = true

local TeamRows = {}
local TeamValues = {}
local teamKeys = {
    {"Egg Reduction", "eggReductionPet"},
    {"Hatch Team", "hatchPet"},
    {"Pet Size", "brontoPet"},
    {"Sell Team", "sellPet"}
}

local function refreshTeamValues()
    local seen = {}
    local values = {}

    for _, pet in pairs(getInventory()) do
        if type(pet) == "table" and pet.PetType then
            local name = safeToString(pet.PetType)
            if name ~= "" and not seen[name] then
                seen[name] = true
                table.insert(values, name)
            end
        end
    end

    table.sort(values)
    TeamValues = values

    for _, rowData in ipairs(TeamRows) do
        local box = rowData.box
        local key = rowData.key
        local text = state[key] ~= "" and state[key] or "(not selected)"
        rowData.value.Text = text

        for _, child in ipairs(box:GetChildren()) do
            if child.Name == "PetChoice" then
                child:Destroy()
            end
        end

        local visible = math.min(#values, 5)
        for i = 1, visible do
            local value = values[i]
            local b = Instance.new("TextButton")
            b.Name = "PetChoice"
            b.Text = value
            b.Font = Enum.Font.Code
            b.TextSize = 9
            b.TextColor3 = Color3.fromRGB(220,223,230)
            b.BackgroundColor3 = Color3.fromRGB(30,31,38)
            b.BorderSizePixel = 0
            b.Position = UDim2.fromOffset(10 + (i - 1) * 82, 42)
            b.Size = UDim2.fromOffset(76, 25)
            b.Parent = box
            newCorner(b, 6)

            b.Activated:Connect(function()
                state[key] = value
                rowData.value.Text = value
                log(rowData.title .. " = " .. value)
            end)
        end
    end

    TeamStatus.Text = ("Owned pet types: %d • only inventory entries are selectable."):format(#values)
end

for i, item in ipairs(teamKeys) do
    local y = 50 + (i - 1) * 58
    local box = makeBox(Teams, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 51))
    local title = newText(box, item[1], 9, Enum.Font.GothamBold, Color3.fromRGB(150,155,170))
    title.Position = UDim2.fromOffset(10, 3)
    title.Size = UDim2.fromOffset(140, 17)

    local value = newText(box, "(not selected)", 10, Enum.Font.Code)
    value.Position = UDim2.fromOffset(155, 3)
    value.Size = UDim2.new(1, -165, 0, 17)

    TeamRows[#TeamRows + 1] = {
        box = box,
        title = item[1],
        key = item[2],
        value = value
    }
end

local RefreshTeams = Instance.new("TextButton")
RefreshTeams.Text = "REFRESH INVENTORY"
RefreshTeams.Font = Enum.Font.GothamBold
RefreshTeams.TextSize = 10
RefreshTeams.TextColor3 = Color3.fromRGB(235,238,245)
RefreshTeams.BackgroundColor3 = Color3.fromRGB(57, 66, 89)
RefreshTeams.BorderSizePixel = 0
RefreshTeams.Position = UDim2.fromOffset(0, 286)
RefreshTeams.Size = UDim2.fromOffset(150, 30)
RefreshTeams.Parent = Teams
newCorner(RefreshTeams, 7)
RefreshTeams.Activated:Connect(refreshTeamValues)

-- ESP
local ESPInfo = makeBox(ESP, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 62))
local ESPLabel = newText(ESPInfo, "READY eggs show PetType from EggReadyToHatch_RE.", 10, Enum.Font.Code)
ESPLabel.Position = UDim2.fromOffset(10, 8)
ESPLabel.Size = UDim2.new(1, -20, 0, 42)
ESPLabel.TextWrapped = true
ESPLabel.TextYAlignment = Enum.TextYAlignment.Top

local ESPButton = Instance.new("TextButton")
ESPButton.Text = "TOGGLE EGG ESP"
ESPButton.Font = Enum.Font.GothamBold
ESPButton.TextSize = 10
ESPButton.TextColor3 = Color3.fromRGB(235,238,245)
ESPButton.BackgroundColor3 = Color3.fromRGB(57, 66, 89)
ESPButton.BorderSizePixel = 0
ESPButton.Position = UDim2.fromOffset(0, 74)
ESPButton.Size = UDim2.fromOffset(150, 31)
ESPButton.Parent = ESP
newCorner(ESPButton, 7)

local espEnabled = false
local espObjects = {}

local function destroyESP()
    for egg, billboard in pairs(espObjects) do
        if billboard and billboard.Parent then
            billboard:Destroy()
        end
        espObjects[egg] = nil
    end
end

local function addESP(egg)
    if espObjects[egg] or not egg or not egg.Parent then
        return
    end

    local adornee
    if egg:IsA("BasePart") then
        adornee = egg
    elseif egg:IsA("Model") then
        adornee = egg.PrimaryPart
        if not adornee then
            adornee = egg:FindFirstChildWhichIsA("BasePart", true)
        end
    end
    if not adornee then
        return
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "FableEggESP"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(190, 80)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = Gui

    local label = newText(billboard, "", 10, Enum.Font.Code)
    label.Size = UDim2.fromScale(1,1)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextStrokeTransparency = 0.15
    label.TextWrapped = true
    label.Parent = billboard

    espObjects[egg] = billboard
end

local function refreshESP()
    if not espEnabled then
        destroyESP()
        return
    end

    for _, egg in ipairs(getOwnedEggs()) do
        addESP(egg)
    end

    for egg, billboard in pairs(espObjects) do
        if not egg.Parent then
            billboard:Destroy()
            espObjects[egg] = nil
        else
            local uuid = getEggUUID(egg)
            local info = uuid and state.readyByUUID[uuid]
            local petText = info and safeToString(info.PetType) or "Unknown"
            local timer = egg:GetAttribute("TimeToHatch")
            local timerText = typeof(timer) == "number" and string.format("%.1fs", math.max(0, timer)) or "?"
            local readyText = isReady(egg) and "READY" or timerText
            local weightText = info and formatWeight(info.BaseWeight) or "Unknown"
            local decision = info and safeToString(info.Decision) or "Pending"

            local text = ("[%s]\nPet: %s\nWeight: %s\nDecision: %s\nTime: %s"):format(
                safeToString(egg:GetAttribute("EggName")),
                petText,
                weightText,
                decision,
                readyText
            )

            local child = billboard:FindFirstChildOfClass("TextLabel")
            if child then
                child.Text = text
            end
        end
    end
end

ESPButton.Activated:Connect(function()
    espEnabled = not espEnabled
    ESPButton.Text = espEnabled and "EGG ESP: ON" or "TOGGLE EGG ESP"
    refreshESP()
end)

-- ============================================================
-- READY EVENT
-- ============================================================

local function onEggReady(petType, eggUUID)
    local uuid = safeToString(eggUUID)
    local info = {
        PetType = safeToString(petType),
        BaseWeight = nil,
        Decision = "Pending",
        WeightSource = nil
    }

    state.readyByUUID[uuid] = info

    log(("READY: %s | UUID %s"):format(info.PetType, uuid))

    state.currentPet = info.PetType
    state.currentEgg = uuid
    state.currentWeight = nil
    state.currentDecision = "Pending"
    state.currentTeam = "-"
end

if ReadyEvent then
    ReadyEvent.OnClientEvent:Connect(onEggReady)
else
    warn("[FABLE] EggReadyToHatch_RE unavailable")
end

-- External exact-weight handoff.
-- A verified inspection layer can call:
-- getgenv().FableAutoHatch.SetReadyWeight(eggUUID, baseWeight)
local env = (type(getgenv) == "function" and getgenv()) or _G
env.FableAutoHatch = env.FableAutoHatch or {}

function env.FableAutoHatch.SetReadyWeight(uuid, weight)
    local key = safeToString(uuid)
    local n = tonumber(weight)
    if not n then
        return false
    end

    local info = state.readyByUUID[key]
    if not info then
        info = {PetType = "Unknown", BaseWeight = nil, Decision = "Pending"}
        state.readyByUUID[key] = info
    end

    info.BaseWeight = n
    info.WeightSource = "external verified"
    info.Decision = n > state.weightThreshold and "BRONTO" or "KOI"
    log(("READY WEIGHT: %s | %.4f | %s"):format(key, n, info.Decision))
    return true
end

function env.FableAutoHatch.GetState()
    return state
end

-- ============================================================
-- HATCH CORE
-- ============================================================

local function chooseDecision(info)
    local baseWeight = tonumber(info and info.BaseWeight)

    if state.markBigPet and baseWeight then
        if baseWeight > state.weightThreshold then
            return "BRONTO", state.brontoPet
        end
    end

    return "KOI", state.hatchPet
end

local function hatchReadyEgg(egg)
    local uuid = getEggUUID(egg)
    if not uuid or state.processing[uuid] then
        return false
    end

    local info = state.readyByUUID[uuid]
    if not info then
        info = {
            PetType = "Unknown",
            BaseWeight = nil,
            Decision = "Pending"
        }
        state.readyByUUID[uuid] = info
    end

    if state.markBigPet and state.pauseIfWeightUnavailable and not tonumber(info.BaseWeight) then
        log("Paused: exact ready BaseWeight unavailable for " .. safeToString(info.PetType))
        state.currentStatus = "Paused: BaseWeight"
        state.autoHatch = false
        return false
    end

    local decision, team = chooseDecision(info)
    info.Decision = decision
    info.Team = team

    if team and team ~= "" then
        local ok, err = equipPetType(team)
        if not ok then
            state.failed = state.failed + 1
            log("Team equip failed: " .. safeToString(err))
            state.currentStatus = "Stopped"
            state.autoHatch = false
            return false
        end
    end

    state.processing[uuid] = true
    state.currentEgg = safeToString(egg:GetAttribute("EggName"))
    state.currentPet = safeToString(info.PetType)
    state.currentWeight = tonumber(info.BaseWeight)
    state.currentDecision = decision
    state.currentTeam = team or "-"
    state.currentStatus = "Hatching"

    local started = os.clock()
    log(("%s -> %s -> %s"):format(state.currentPet, formatWeight(state.currentWeight), decision))

    local ok, err = pcall(function()
        if not PetEggService then
            error("PetEggService unavailable")
        end
        PetEggService:FireServer("HatchPet", egg)
    end)

    if not ok then
        state.failed = state.failed + 1
        state.processing[uuid] = nil
        state.currentStatus = "Stopped"
        log("HatchPet error: " .. safeToString(err))
        return false
    end

    local before = snapshotPets()
    local newUUID, newPet
    for _ = 1, 75 do
        task.wait(0.12)
        newUUID, newPet = findNewPet(before, info.PetType ~= "Unknown" and info.PetType or nil)
        if newUUID and newPet then
            break
        end
    end

    if not newUUID or not newPet then
        state.failed = state.failed + 1
        state.processing[uuid] = nil
        state.currentStatus = "Hatch sent / pet not verified"
        log("Hatch sent, but new PetData was not verified")
        return false
    end

    local actualWeight
    if type(newPet.PetData) == "table" then
        actualWeight = tonumber(newPet.PetData.BaseWeight)
    end

    if actualWeight then
        state.currentWeight = actualWeight
    end

    state.hatched = state.hatched + 1
    state.lastHatchTime = os.clock() - started
    state.currentStatus = "Running"
    state.processing[uuid] = nil

    info.BaseWeight = actualWeight or info.BaseWeight
    info.ActualBaseWeight = actualWeight
    info.HatchTime = state.lastHatchTime

    log(("Hatched ✓ %s | %.4f kg | %.2fs"):format(
        safeToString(info.PetType),
        tonumber(actualWeight) or tonumber(info.BaseWeight) or 0,
        state.lastHatchTime
    ))

    return true
end

local function countReady()
    local count = 0
    for _, egg in ipairs(getOwnedEggs()) do
        if isReady(egg) then
            count = count + 1
        end
    end
    return count
end

-- ============================================================
-- DRAGGING
-- ============================================================

local dragging = false
local dragStart
local startPos

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)

Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart
    Main.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
end)

local minimized = false
MinButton.Activated:Connect(function()
    minimized = not minimized
    for _, child in ipairs(Main:GetChildren()) do
        if child ~= Header and child ~= MinButton and child ~= CloseButton then
            child.Visible = not minimized
        end
    end
    Main.Size = minimized and UDim2.fromOffset(280, 48) or UDim2.fromOffset(520, 330)
    MinButton.Text = minimized and "+" or "—"
end)

CloseButton.Activated:Connect(function()
    state.autoHatch = false
    if Gui then
        Gui:Destroy()
    end
end)

-- ============================================================
-- UPDATE LOOP
-- ============================================================

setPage("Dashboard")
refreshTeamValues()

print("==================================================")
print("[FABLE] Standalone v5.0 loaded")
print("[FABLE] Dependency-free UI")
print("[FABLE] Official logo fallback: F")
print("[FABLE] Ready event: " .. (ReadyEvent and "OK" or "MISSING"))
print("[FABLE] PetEggService: " .. (PetEggService and "OK" or "MISSING"))
print("==================================================")

while Gui.Parent do
    task.wait(0.25)

    state.ready = countReady()

    local readyEgg
    for _, egg in ipairs(getOwnedEggs()) do
        if isReady(egg) then
            readyEgg = egg
            break
        end
    end

    if readyEgg then
        local uuid = getEggUUID(readyEgg)
        local info = uuid and state.readyByUUID[uuid]
        ReadyLabel.Text = ("Egg: %s\nUUID: %s\nPet: %s\nWeight: %s | Decision: %s"):format(
            safeToString(readyEgg:GetAttribute("EggName")),
            safeToString(uuid),
            info and safeToString(info.PetType) or "Unknown",
            info and formatWeight(info.BaseWeight) or "Unknown",
            info and safeToString(info.Decision) or "Pending"
        )
    else
        ReadyLabel.Text = "No READY egg."
    end

    DashLine1.Text = ("Eggs %d  |  Ready %d  |  Created %d  |  Hatched %d"):format(
        #getOwnedEggs(),
        state.ready,
        state.created,
        state.hatched
    )

    DashLine2.Text = ("Failed %d  |  Sold %d  |  Last hatch %.2fs"):format(
        state.failed,
        state.sold,
        state.lastHatchTime
    )

    DashLine3.Text = ("Current: %s  |  Team: %s  |  Weight: %s"):format(
        state.currentStatus,
        state.currentTeam,
        formatWeight(state.currentWeight)
    )

    LogLabel.Text = state.lastLog

    if state.autoHatch then
        local didOne = false

        for _, egg in ipairs(getOwnedEggs()) do
            if not state.autoHatch then
                break
            end
            if isReady(egg) then
                if hatchReadyEgg(egg) then
                    didOne = true
                    if not state.batchHatching then
                        task.wait(0.35)
                    else
                        task.wait(0.05)
                    end
                end
            end
        end

        if not didOne then
            state.currentStatus = "Waiting for READY egg"
        end
    else
        if state.currentStatus == "Waiting for READY egg" then
            state.currentStatus = "Idle"
        end
    end

    refreshESP()
end
''